package main

shape_demo_layout :: proc()->Layout {
 l:=Layout{next_identity=7}
 append(&l.objects,Authored_Shape{identity=1,material=recipe_slot(.Stone),lo={-1,0},hi={-0.5,2.5},mortar=true})
 append(&l.objects,Authored_Shape{identity=2,material=recipe_slot(.Stone),lo={3,0},hi={3.5,2.5},mortar=true})
 append(&l.objects,Authored_Shape{identity=3,material=recipe_slot(.Wood),lo={-0.35,1.85},hi={0.85,4.35},angle=90,shape=.Wedge})
 append(&l.objects,Authored_Shape{identity=4,material=recipe_slot(.Wood),lo={1.5,2.5},hi={3.5,3.7},shape=.Wedge})
 left:=Authored_Shape{identity=5,material=recipe_slot(.Wood),lo={0,0},hi={3,0.3},angle=30}
 p:=shape_polygon(left);move:=vsub(Vec2{-1,2},p.points[1]);delete(p.points);left.lo=vadd(left.lo,move);left.hi=vadd(left.hi,move)
 right:=Authored_Shape{identity=6,material=recipe_slot(.Glass),lo={0,0},hi={3,0.3},angle=150}
 p=shape_polygon(right);move=vsub(Vec2{3.5,2},p.points[2]);delete(p.points);right.lo=vadd(right.lo,move);right.hi=vadd(right.hi,move)
 append(&l.objects,left,right)
 append(&l.glue,Glue_Link{1,5},Glue_Link{2,6},Glue_Link{3,4})
 return l
}
