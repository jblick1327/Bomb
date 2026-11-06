using System;
using System.Collections.Generic;
using Bom.Native;
using Bom.Unity;
using UnityEngine;
using System.Runtime.InteropServices;
public static class BomGeometryValidation {
 static void Check(bool value,string message){if(!value)throw new InvalidOperationException(message);}
 public static void Run(){
  Vector2[] outline={new Vector2(0,0),new Vector2(3,0),new Vector2(3,1),new Vector2(1,1),new Vector2(1,3),new Vector2(0,3)};
  for(int winding=0;winding<2;winding++) {
   var mesh=BomExtrusion.Build(outline,0.6f,new Vector2(8,2));try {
    var vertices=mesh.vertices;var triangles=mesh.triangles;float volume=0;var edges=new Dictionary<(Vector3,Vector3),int>();
    bool Before(Vector3 a,Vector3 b)=>a.x!=b.x?a.x<b.x:a.y!=b.y?a.y<b.y:a.z<b.z;
    void Edge(int a,int b){var key=Before(vertices[a],vertices[b])?(vertices[a],vertices[b]):(vertices[b],vertices[a]);edges.TryGetValue(key,out int count);edges[key]=count+1;}
    for(int i=0;i<triangles.Length;i+=3){int a=triangles[i],b=triangles[i+1],c=triangles[i+2];volume+=Vector3.Dot(vertices[a],Vector3.Cross(vertices[b],vertices[c]))/6;Edge(a,b);Edge(b,c);Edge(c,a);}
    Check(Mathf.Abs(volume-3)<0.0001f,"Concave extrusion volume or winding differs");foreach(int count in edges.Values)Check(count==2,"Extrusion has an open or nonmanifold edge");
    Check(Mathf.Abs(mesh.bounds.size.z-0.6f)<0.0001f,"Extrusion depth differs");
    Check(mesh.subMeshCount==2&&mesh.uv.Length==vertices.Length,"Surface/interior submeshes or UVs missing");
    Check(Vector2.Distance(mesh.uv[0],outline[0]+new Vector2(8,2))<0.0001f,"Rest-space UV origin differs");
    foreach(var normal in mesh.normals)Check(Mathf.Abs(normal.magnitude-1)<0.0001f,"Invalid face normal");
   }finally{UnityEngine.Object.DestroyImmediate(mesh);}
   Array.Reverse(outline);
  }
  var rigid=new BomCell{pivot_x=8,pivot_y=2,rest_x=10,rest_y=4};Vector2 local=BomUnityCoordinates.RestVertex(new BomVertex{x=9,y=3},rigid);
  Vector3 result=BomUnityCoordinates.Rotation(Mathf.PI/2)*new Vector3(local.x,local.y,-0.3f)+new Vector3(2,4,0);
  Check(Vector3.Distance(result,new Vector3(1,5,-0.3f))<0.0001f,"Reference pivot/radians/depth mapping differs");
  var rubber=new BomCell{pivot_x=5,pivot_y=6};local=BomUnityCoordinates.RestVertex(new BomVertex{x=4,y=5},rubber);
  result=BomUnityCoordinates.Rotation(-Mathf.PI/2)*new Vector3(local.x,local.y,-0.3f)+new Vector3(9,10,0);
  Check(Vector3.Distance(result,new Vector3(8,11,-0.3f))<0.0001f,"Rubber cell-center mapping differs");
  var shapes=new BomActorShapeInfo{struct_size=(uint)Marshal.SizeOf<BomActorShapeInfo>(),version=1};BomSession.Check(BomNative.bom_actor_shape_info(ref shapes));
  var capsule=BomExtrusion.Build(BomUnityCoordinates.ActorOutline(true,shapes));var bomb=BomExtrusion.Build(BomUnityCoordinates.ActorOutline(false,shapes));
  try{Check(Mathf.Abs(capsule.bounds.min.y+shapes.player_segment+shapes.player_radius)<0.00001f,"Player foot offset differs from native capsule");Check(Mathf.Abs(bomb.bounds.max.x-shapes.bomb_radius)<0.00001f,"Bomb radius differs from native shape");}
  finally{UnityEngine.Object.DestroyImmediate(capsule);UnityEngine.Object.DestroyImmediate(bomb);}
  Debug.Log("BOM GEOMETRY PASS: concave closed extrusion, both windings, reference/rubber pivots, radians and preserved depth");
 }
}
