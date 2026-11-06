using Bom.Native;
using UnityEngine;
namespace Bom.Unity {
public static class BomUnityCoordinates {
 public static Vector2 RestVertex(BomVertex point,BomCell cell)=>new Vector2(point.x-cell.pivot_x,point.y-cell.pivot_y);
 public static Quaternion Rotation(float radians)=>Quaternion.Euler(0,0,radians*Mathf.Rad2Deg);
 public static Vector2[] ActorOutline(bool player,BomActorShapeInfo shape){
  float radius=player?shape.player_radius:shape.bomb_radius;int count=player?26:24;var points=new Vector2[count];
  for(int j=0;j<count;j++){float angle=player?(j<13?j*Mathf.PI/12:Mathf.PI+(j-13)*Mathf.PI/12):j*Mathf.PI/12;points[j]=new Vector2(Mathf.Cos(angle)*radius,Mathf.Sin(angle)*radius+(player?(j<13?shape.player_segment:-shape.player_segment):0));}
  return points;
 }
}
}
