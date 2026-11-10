using System;
using System.Collections.Generic;
using Bom.Unity;
using UnityEngine;
using UnityEditor;
public static class BomSourceDataValidation {
 static void Check(bool value,string text){if(!value)throw new InvalidOperationException(text);}
 public static void Run(){
  var original=BomExtrusion.Build(new[]{new Vector2(-1,-1),new Vector2(1,-1),new Vector2(1,1),new Vector2(-1,1)},1);Mesh uploaded=null,compactMesh=null;
  try{
   var uv7=new List<Vector4>();foreach(var p in original.vertices)uv7.Add(new Vector4(p.x*7,p.y*7,p.z*7,7));original.SetUVs(7,uv7);
   var material=AssetDatabase.LoadAssetAtPath<Material>("Assets/BOMIntegration/NativeFallback.mat");Check(material!=null,"Missing fixture material");
   var entry=new BomVisualEntry{BuilderVersion=2,ContentHash=new string('a',64),Groups=new[]{new BomVisualMeshGroup{Mesh=original,SurfaceMaterials=new[]{material,material}}},CapMaterial=material};
   var matrix=Matrix4x4.TRS(new Vector3(7,-2,4),Quaternion.Euler(23,37,-11),new Vector3(-2,3,.4f));var arrays=BomSourceMeshData.Read(entry,matrix,material,64L*1024*1024);Check(arrays.Failure==null,"source reader: "+arrays.Failure);Check(arrays.Materials.Length==3,"Material palette/cap slot differs");
   var source=BomPrismClipper.Prepare(arrays.Triangles,arrays.Materials.Length-1);Check(source.Failure==null,"normalized source: "+source.Failure);var result=BomPrismClipper.Build(source,new[]{new Vector2(7,source.Min.y-1),new Vector2(source.Max.x+1,source.Min.y-1),new Vector2(source.Max.x+1,source.Max.y+1),new Vector2(7,source.Max.y+1)});Check(result.Supported,"normalized clip: "+result.Reason);
   var triangles=new List<BomClipTriangle>(result.Exterior);foreach(var patch in result.Caps)triangles.AddRange(patch.Triangles);uploaded=BomClipMeshUpload.Upload(triangles,0,triangles.Count,new Vector2(7,-2),arrays.Materials.Length,"Source upload fixture");
   Check(uploaded.subMeshCount==3&&uploaded.GetIndexCount(2)>0,"GPU upload omitted the cap material");Check(Vector3.Distance(uploaded.vertices[0]+new Vector3(7,-2,0),triangles[0].A.Position)<.00001f,"GPU upload applied the reference offset more than once");Check(Vector3.Dot(uploaded.normals[0],triangles[0].A.Normal.normalized)>.9999f,"GPU normal differs");var copy=new List<Vector4>();uploaded.GetUVs(7,copy);Check(copy.Count==uploaded.vertexCount&&(copy[0]-triangles[0].A.UV7).sqrMagnitude<1e-10f,"GPU upload lost higher UV channels");Check(Mathf.Abs(uploaded.tangents[0].w-(triangles[0].A.Tangent.w<0?-1:1))<.00001f,"GPU mirrored tangent sign differs");
   var remapped=new List<BomClipTriangle>();foreach(var triangle in triangles)remapped.Add(new BomClipTriangle(triangle.A,triangle.B,triangle.C,triangle.Material==2?26:triangle.Material==1?24:3));
   compactMesh=BomClipMeshUpload.UploadCompact(remapped,0,remapped.Count,new Vector2(7,-2),27,"Sparse material slots",out var slots);
   Check(slots.Length==3&&slots[0]==3&&slots[1]==24&&slots[2]==26&&compactMesh.subMeshCount==3,"Sparse material mapping changed used surfaces");
   ulong indices=0;for(int i=0;i<slots.Length;i++)indices+=compactMesh.GetIndexCount(i);Check(indices==(ulong)triangles.Count*3,"Compaction lost triangles");
   Check(compactMesh.vertexCount==uploaded.vertexCount&&Vector3.Distance(compactMesh.vertices[0],uploaded.vertices[0])<1e-7f,"Compaction changed geometry");
   Debug.Log("BOM SOURCE MATERIAL COMPACTION PASS: sparse slots 3/24/26 preserved with identical vertices and complete triangles");
   Debug.Log("BOM SOURCE DATA UPLOAD PASS: runtime direct mesh reads, arbitrary mirrored affine transform, palette/caps, reference pivot, normals, tangents and UV7");
  }finally{if(compactMesh!=null)UnityEngine.Object.DestroyImmediate(compactMesh);if(uploaded!=null)UnityEngine.Object.DestroyImmediate(uploaded);UnityEngine.Object.DestroyImmediate(original);}
 }
}
public static class BomM7GeometryGate {public static void Run(){BomAuthoringValidation.Run();BomClipperValidation.Run();BomSourceDataValidation.Run();BomSourcePivotValidation.Run();}}
