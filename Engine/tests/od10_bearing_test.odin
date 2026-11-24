package main

import "core:testing"
import "core:sync"
import "core:math"
import shared "shared"

// OD-10 (G-N10b): the bearing rule in running worlds. Unit tests of the normal and the split are next to the rule
// (src/shared/od10_bearing_test.odin).

// Every live mortar link's cached normal equals the one its rest geometry gives now (it was set when the link was built).
od10_expect_cached_normals :: proc(t: ^testing.T,s: ^Scene,where_: string) -> (links: int) {
 for c in s.connections {
  if !c.live || !c.mortar { continue }
  links+=1
  fresh:=mortar_link_normal(s,c)
  testing.expectf(t,c.seam_normal==fresh,"%s: link %d cached normal %v, rest geometry gives %v",where_,c.id,c.seam_normal,fresh)
  testing.expectf(t,math.abs(vlen(c.seam_normal)-1)<1e-5,"%s: link %d normal is not unit: %v",where_,c.id,c.seam_normal)
 }
 return
}

// Mortar link id -> cached normal.
od10_normals :: proc(s: ^Scene) -> map[u64]Vec2 {
 m:=make(map[u64]Vec2)
 for c in s.connections { if c.live && c.mortar { m[c.id]=c.seam_normal } }
 return m
}

od10_same_normals :: proc(t: ^testing.T,a,b: ^Scene,where_: string) {
 na,nb:=od10_normals(a),od10_normals(b); defer delete(na); defer delete(nb)
 testing.expectf(t,len(na)==len(nb) && len(na)>0,"%s: %d vs %d mortar links",where_,len(na),len(nb))
 for id,n in na { m,ok:=nb[id]; testing.expectf(t,ok && m==n,"%s: link %d normal %v vs %v",where_,id,n,m) }
}

// A glued 6x3 grid of tiles (level glue: glue-sample links, cell-centre normals).
od10_grid_level :: proc() -> string {
 tiles,links:=glue_test_grid(6,3); defer delete(tiles); defer delete(links)
 return glue_test_level(tiles[:],links[:],2)
}

@(test)
od10_a_real_stack_carries_bearing_that_is_not_charged :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 // The 2.4 cantilever stands on its post (Mortar B holds it 600 ticks); breaking off so the seams can be read steadily.
 g:=mortar_cantilever(2.4); defer sandbox_destroy(&g)
 s:=&g.world.scene; s.physics.mortar_breaking=false
 for _ in 0..<120 { sandbox_tick(&g,0,false) }
 seams:=mortar_seams(s); defer mortar_free_seams(seams)
 bearing_seams:=0
 for seam in seams {
  testing.expectf(t,math.abs(vlen(seam.normal)-1)<1e-5,"seam normal must be unit: %v",seam.normal)
  strength:=MORTAR_STRENGTH*shared.mortar_seam_toughness(s,seam)
  raw:=vlen(seam.force)/(strength*seam.length)+math.abs(seam.torque)/(0.5*strength*seam.length*seam.length)
  r:=mortar_seam_ratio(s,seam)
  fn:=vdot(seam.force,seam.normal)
  if fn>0 {
   testing.expect(t,seam.bearing==fn && r<raw,"a seam in bearing is charged less than its weld force")
   if fn>=0.5*vlen(seam.force) { bearing_seams+=1 }
  } else { testing.expect(t,seam.bearing==0 && r==raw,"a seam in tension is charged in full") }
 }
 testing.expectf(t,bearing_seams>0,"the post carries the cantilever's weight across a seam face (%d seams)",len(seams))
}

@(test)
od10_cached_normals_survive_blast_snapshot_restart_and_replica :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 text:=od10_grid_level(); defer delete(text)
 layout,w,ok:=glue_test_world(t,text); if !ok { return }
 defer shared.destroy_layout(&layout); defer shared.scene_destroy(&w.scene); defer delete(w.bombs)
 built:=od10_expect_cached_normals(t,&w.scene,"build")
 testing.expectf(t,built>0,"the grid is glued (%d links)",built)
 for c in w.scene.connections { if c.live && c.mortar { testing.expect(t,len(c.glue)>0 && len(c.rest_segments)==0,"level glue links carry glue samples, not rest segments") } }
 // Replica: the client builds the same links from the baseline and computes the same normals.
 srv:Repl_Server; defer repl_server_destroy(&srv)
 rep:Replica; replica_init(&rep); defer replica_destroy(&rep)
 base:=repl_server_update(&srv,&w.scene,0); defer repl_output_destroy(&base)
 testing.expect(t,repl_apply_output(&rep,&base)=="")
 od10_same_normals(t,&w.scene,&rep.scene,"replica baseline")
 for _ in 0..<10 { od8_step(&w) }
 // A blast cuts cells: the replacement cells inherit glue links, which compute their own normals when built.
 before:=make(map[u64]bool); defer delete(before)
 for sub in w.scene.subdivisions { if sub.live { before[sub.id]=true } }
 // Aim at a glued cell where it is now (the grid has no floor and is falling); radius 4 as in the bridge test.
 aim:Vec2; for c in w.scene.connections { if c.live && c.mortar { aim=w.scene.subdivisions[w.scene.sub_rows[c.a]].pose.position; break } }
 events:Tick_Events; world_explode(&w,aim,4,&events); delete(events.explosions)
 cut:=0; for id in before { row,found:=w.scene.sub_rows[id]; if !found || !w.scene.subdivisions[row].live { cut+=1 } }
 testing.expectf(t,cut>0,"the blast cuts glued cells (%d)",cut)
 for _ in 0..<5 { od8_step(&w) }
 after:=od10_expect_cached_normals(t,&w.scene,"after blast")
 testing.expectf(t,after>0,"glue links remain after the blast (%d)",after)
 delta:=repl_server_update(&srv,&w.scene,15); defer repl_output_destroy(&delta)
 testing.expect(t,repl_apply_output(&rep,&delta)=="")
 od10_same_normals(t,&w.scene,&rep.scene,"replica after blast")
 // Snapshot rebuild: the decoded world recomputes each link's normal from the same rest geometry, bit for bit.
 bytes,encoded:=encode_world_snapshot(&w); defer delete(bytes); testing.expect(t,encoded)
 rebuilt,decoded:=decode_world_snapshot(bytes,w.scene.epoch); testing.expect(t,decoded); if !decoded { return }
 defer shared.scene_destroy(&rebuilt.scene); defer delete(rebuilt.bombs)
 od10_expect_cached_normals(t,&rebuilt.scene,"snapshot rebuild")
 od10_same_normals(t,&w.scene,&rebuilt.scene,"snapshot rebuild")
 // The seams the rule judges are the same: members, length and world normal.
 sa,sb:=mortar_seams(&w.scene),mortar_seams(&rebuilt.scene); defer mortar_free_seams(sa); defer mortar_free_seams(sb)
 testing.expect(t,len(sa)==len(sb) && len(sa)>0)
 if len(sa)==len(sb) { for i in 0..<len(sa) {
  testing.expect(t,len(sa[i].members)==len(sb[i].members) && sa[i].members[0]==sb[i].members[0] && sa[i].length==sb[i].length)
  testing.expectf(t,vlen(vsub(sa[i].normal,sb[i].normal))<1e-5,"seam %d world normal %v vs %v",i,sa[i].normal,sb[i].normal)
 } }
 // Round restart: rebuilding the level starts from the same links and normals as the first build.
 first,_:=glue_test_world_normals(t,text); defer delete(first)
 shared.world_rebuild_layout(&w,&layout,false)
 od10_expect_cached_normals(t,&w.scene,"round restart")
 now:=od10_normals(&w.scene); defer delete(now)
 testing.expect(t,len(now)==len(first))
 for id,n in first { m,found:=now[id]; testing.expectf(t,found && m==n,"restart: link %d normal %v vs %v",id,n,m) }
}

// Normals of a freshly built level.
glue_test_world_normals :: proc(t: ^testing.T,text: string) -> (map[u64]Vec2,bool) {
 layout,w,ok:=glue_test_world(t,text); if !ok { return nil,false }
 defer shared.destroy_layout(&layout); defer shared.scene_destroy(&w.scene); defer delete(w.bombs)
 return od10_normals(&w.scene),true
}

@(test)
od10_rule_is_deterministic_under_load_and_blast :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 // The mortar bridge yard stands under its own weight (seams in bearing); a blast at tick 150 on its first glue link
 // breaks some of it (fixture choice: a fixed point missed the glue).
 states:[2][]u8; defer { for s in states { delete(s) } }
 breaks:[2]int // cells the blast cuts
 for run in 0..<2 {
  g:=mortar_bridge_yard()
  for tick in 1..=300 {
   sandbox_tick(&g,0,false)
   if tick==150 {
    // Aim at the first glue link (lowest id), so the blast is sure to hit glued structure.
    s:=&g.world.scene; first:=u64(0)
    for c in s.connections { if c.live && c.mortar && (first==0 || c.id<first) { first=c.id } }
    point:=connection_sample(s,s.connections[s.conn_rows[first]])
    ids:=make(map[u64]bool); defer delete(ids)
    for sub in s.subdivisions { if sub.live { ids[sub.id]=true } }
    events:Tick_Events; world_explode(&g.world,point,4,&events); delete(events.explosions)
    for id in ids { row,found:=s.sub_rows[id]; if !found || !s.subdivisions[row].live { breaks[run]+=1 } }
   }
  }
  states[run]=canonical_encode(&g.world.scene)
  sandbox_destroy(&g)
 }
 testing.expectf(t,breaks[0]>0 && breaks[0]==breaks[1],"the blast cuts the glued structure the same way twice (cells cut): %v",breaks)
 testing.expect(t,len(states[0])>0 && string(states[0])==string(states[1]),"two runs must be byte-identical")
}
