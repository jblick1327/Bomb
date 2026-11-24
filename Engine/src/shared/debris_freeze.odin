package shared

import b2 "vendor:box2d"

// NPT (owner-approved 2026-11-24): settled debris freezes. A loose rigid piece (no live mortar weld to another
// piece) that stays still for about a second becomes a static body, so it stops costing the solver: a player never
// sleeps, and through the ground it stands on every touching piece of debris used to stay awake with it (server
// tick 4 ms with fresh ground, 13-14 ms after two minutes of blasts).
//
// Frozen debris touches only other loose debris. A static piece pressed against the welded ground over-constrains the
// rigid mortar welds (the OD-8 seam-contact failure again: in the blast replay the seams broke away under frozen
// debris and the yard ground blew apart), so it leaves the ground's collision filter while frozen; it no longer
// moves, so it needs no support from it. Loose debris carries DEBRIS_CATEGORY so falling rubble still piles onto it.
//
// A frozen piece thaws, back to dynamic with its own mass and full collision, when a blast reaches near it (before
// the blast is applied), when a player or bomb comes near (checked every tick, so players and bombs never meet
// frozen debris), when a moving body overlaps it, or when nothing is left around it. Nothing freezes during the
// level-start gravity ramp. Structure queries (blasts, items, support) use STRUCTURE_QUERY_FILTER, which sees frozen
// debris exactly as the default filter sees everything else.
// Off unless World.debris_freeze is set; the network server sets it. The offline game and tests are unchanged.

DEBRIS_FREEZE_EVERY :: u64(10)       // ticks between freeze and support checks
DEBRIS_FREEZE_SAMPLES :: u16(6)      // still checks in a row before freezing (about 1 s)
DEBRIS_FREEZE_SPEED :: f32(0.1)      // m/s
DEBRIS_FREEZE_SPIN :: f32(0.2)       // rad/s
DEBRIS_MOVER_MARGIN :: f32(1.5)      // m around a player or bomb where debris stays dynamic
DEBRIS_BLAST_MARGIN :: f32(0.25)     // m beyond a blast's radius where frozen debris thaws (its push ends at the radius)
DEBRIS_SUPPORT_REACH :: f32(0.05)    // m the support check reaches past a frozen piece's box
DEBRIS_OVERLAP_SPEED :: f32(0.3)     // m/s: a body moving this fast inside a frozen piece's box thaws it

DEFAULT_CATEGORY :: u64(0x1)         // Box2D's default: ground, players, bombs
DEBRIS_CATEGORY :: u64(0x2)          // loose rigid pieces
FROZEN_CATEGORY :: u64(0x4)          // frozen debris
FROZEN_QUERY_BIT :: u64(0x8)         // carried by structure queries so they see frozen debris
FROZEN_FILTER :: b2.Filter{categoryBits=FROZEN_CATEGORY,maskBits=DEBRIS_CATEGORY|FROZEN_QUERY_BIT}
DEBRIS_FILTER :: b2.Filter{categoryBits=DEBRIS_CATEGORY,maskBits=max(u64)}

// The default query filter plus FROZEN_QUERY_BIT: identical results while nothing is frozen.
STRUCTURE_QUERY_FILTER :: b2.QueryFilter{categoryBits=DEFAULT_CATEGORY|FROZEN_QUERY_BIT,maskBits=max(u64)}

debris_aabb_near :: proc(box: b2.AABB, point: Vec2, margin: f32) -> bool {
 x:=clamp(point.x,box.lowerBound.x,box.upperBound.x);y:=clamp(point.y,box.lowerBound.y,box.upperBound.y)
 dx,dy:=point.x-x,point.y-y
 return dx*dx+dy*dy<=margin*margin
}

debris_near_mover :: proc(w: ^World, box: b2.AABB) -> bool {
 for player in w.players {
  if !player.active || player.body==b2.nullBodyId || !b2.Body_IsValid(player.body) { continue }
  if debris_aabb_near(box,from_b2(b2.Body_GetPosition(player.body)),DEBRIS_MOVER_MARGIN) { return true }
 }
 for bomb in w.bombs {
  if bomb.body==b2.nullBodyId || !b2.Body_IsValid(bomb.body) { continue }
  if debris_aabb_near(box,from_b2(b2.Body_GetPosition(bomb.body)),DEBRIS_MOVER_MARGIN) { return true }
 }
 return false
}

debris_set_filter :: proc(s: ^Scene, p: ^Piece, filter: b2.Filter) {
 for id in p.subdivisions {
  row,ok:=s.sub_rows[id];if !ok { continue }
  for shape in s.subdivisions[row].shapes {
   if !b2.Shape_IsValid(shape) { continue }
   current:=b2.Shape_GetFilter(shape)
   if current.categoryBits!=filter.categoryBits || current.maskBits!=filter.maskBits || current.groupIndex!=filter.groupIndex { b2.Shape_SetFilter(shape,filter) }
  }
 }
}

// Pieces joined to another piece by a live mortar weld (Piece.connections lists only in-piece links).
debris_welded_pieces :: proc(s: ^Scene) -> map[u64]bool {
 welded:=make(map[u64]bool)
 for c in s.connections {
  if !c.live || !c.mortar { continue }
  a,aok:=s.sub_rows[c.a];b,bok:=s.sub_rows[c.b]
  if !aok || !bok { continue }
  oa,ob:=s.subdivisions[a].owner,s.subdivisions[b].owner
  if oa!=ob { welded[oa]=true;welded[ob]=true }
 }
 return welded
}

debris_thaw :: proc(s: ^Scene, p: ^Piece) {
 p.frozen=false;p.rest_samples=0
 if p.body==b2.nullBodyId || !b2.Body_IsValid(p.body) { return }
 debris_set_filter(s,p,DEBRIS_FILTER)
 b2.Body_SetType(p.body,.dynamicBody)
 // SetType recomputes mass from shapes; restore the piece's own mass and its (zero) rest velocity.
 physics_finish_piece_mass(s,p)
 b2.Body_SetAwake(p.body,true)
}

debris_freeze :: proc(s: ^Scene, p: ^Piece) {
 p.frozen=true
 b2.Body_SetType(p.body,.staticBody)
 debris_set_filter(s,p,FROZEN_FILTER)
}

// Thaws frozen pieces a blast at point with radius can reach, so cover, push and damage apply as before.
debris_thaw_near_blast :: proc(w: ^World, point: Vec2, radius: f32) {
 if !w.debris_freeze { return }
 s:=&w.scene
 for &p in s.pieces {
  if !p.live || !p.frozen || p.body==b2.nullBodyId || !b2.Body_IsValid(p.body) { continue }
  if debris_aabb_near(b2.Body_ComputeAABB(p.body),point,radius+DEBRIS_BLAST_MARGIN) { debris_thaw(s,&p) }
 }
}

Debris_Support_Query :: struct { body: b2.BodyId, found, moving: bool }

// found: some other shape lies within reach of the frozen piece's box; moving: one of them is a body moving through.
debris_surroundings :: proc(s: ^Scene, body: b2.BodyId) -> (found, moving: bool) {
 box:=b2.Body_ComputeAABB(body)
 box.lowerBound.x-=DEBRIS_SUPPORT_REACH;box.lowerBound.y-=DEBRIS_SUPPORT_REACH
 box.upperBound.x+=DEBRIS_SUPPORT_REACH;box.upperBound.y+=DEBRIS_SUPPORT_REACH
 query:=Debris_Support_Query{body=body}
 _=b2.World_OverlapAABB(s.physics.world,box,STRUCTURE_QUERY_FILTER,proc "c" (shape: b2.ShapeId, ctx: rawptr) -> bool {
  q:=(^Debris_Support_Query)(ctx)
  other:=b2.Shape_GetBody(shape)
  if other==q.body { return true }
  q.found=true
  if b2.Body_GetType(other)==.dynamicBody {
   v:=b2.Body_GetLinearVelocity(other)
   if v.x*v.x+v.y*v.y>DEBRIS_OVERLAP_SPEED*DEBRIS_OVERLAP_SPEED { q.moving=true;return false }
  }
  return true
 },&query)
 return query.found,query.moving
}

// Runs after each physics step of a debris_freeze world.
debris_freeze_step :: proc(w: ^World) {
 if !w.debris_freeze || !w.scene.physics.active { return }
 s:=&w.scene
 check:=w.tick%DEBRIS_FREEZE_EVERY==0 && w.tick>=STRUCTURE_GRAVITY_RAMP_TICKS
 // Pieces and welds change only with the structure: between checks, re-sort them only after a structure change.
 refresh:=check || s.structure_revision!=w.debris_revision
 welded_pieces:map[u64]bool
 if refresh { welded_pieces=debris_welded_pieces(s);w.debris_revision=s.structure_revision }
 defer delete(welded_pieces)
 for &p in s.pieces {
  if !p.live || p.body==b2.nullBodyId || !b2.Body_IsValid(p.body) || s.materials[p.material].flexibility>0 { continue }
  if p.frozen {
   thaw:=debris_near_mover(w,b2.Body_ComputeAABB(p.body))
   if !thaw && check { found,moving:=debris_surroundings(s,p.body);thaw=!found || moving }
   if thaw { debris_thaw(s,&p) } else if check { debris_set_filter(s,&p,FROZEN_FILTER) } // shapes rebuilt while frozen
   continue
  }
  if !refresh { continue }
  if b2.Body_GetType(p.body)!=.dynamicBody { p.rest_samples=0;continue }
  // After every structure change: loose pieces carry the debris category, so they keep landing on frozen debris.
  welded:=welded_pieces[p.id]
  if !welded { debris_set_filter(s,&p,DEBRIS_FILTER) }
  // Under the level-start gravity ramp everything is nearly weightless and looks still: wait for full gravity.
  if !check { continue }
  if welded { p.rest_samples=0;continue }
  v:=b2.Body_GetLinearVelocity(p.body)
  still:=!b2.Body_IsAwake(p.body) || v.x*v.x+v.y*v.y<DEBRIS_FREEZE_SPEED*DEBRIS_FREEZE_SPEED && abs(b2.Body_GetAngularVelocity(p.body))<DEBRIS_FREEZE_SPIN
  if !still { p.rest_samples=0;continue }
  if p.rest_samples<max(u16) { p.rest_samples+=1 }
  if p.rest_samples<DEBRIS_FREEZE_SAMPLES || debris_near_mover(w,b2.Body_ComputeAABB(p.body)) { continue }
  debris_freeze(s,&p)
 }
}

// The mass of the frozen piece that owns shape (its regions' area, as Box2D's mass for the dynamic piece).
debris_frozen_mass :: proc(s: ^Scene, shape: b2.ShapeId) -> (mass: f32, frozen: bool) {
 if shape==b2.nullShapeId || !b2.Shape_IsValid(shape) { return }
 row,ok:=s.sub_rows[u64(uintptr(b2.Shape_GetUserData(shape)))];if !ok { return }
 prow,pok:=s.piece_rows[s.subdivisions[row].owner];if !pok || !s.pieces[prow].frozen { return }
 for id in s.pieces[prow].subdivisions { if r,found:=s.sub_rows[id];found { mass+=polygon_area(s.subdivisions[r].outline) } }
 return mass,true
}
