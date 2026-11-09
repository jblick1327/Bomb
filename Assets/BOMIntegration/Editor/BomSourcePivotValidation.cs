using System;
using System.Collections.Generic;
using Bom.Unity;
using UnityEngine;
using UnityEditor;
public static class BomSourcePivotValidation {
 static void Check(bool value,string message){if(!value)throw new InvalidOperationException(message);}
 public static void Run(){
  var original=BomExtrusion.Build(new[]{new Vector2(-.5f,-.5f),new Vector2(.5f,-.5f),new Vector2(.5f,.5f),new Vector2(-.5f,.5f)},1);
  var objects=new List<GameObject>();var meshes=new List<Mesh>();
  try{
   var material=AssetDatabase.LoadAssetAtPath<Material>("Assets/BOMIntegration/NativeFallback.mat");var entry=new BomVisualEntry{BuilderVersion=2,ContentHash=new string('c',64),Groups=new[]{new BomVisualMeshGroup{Mesh=original,SurfaceMaterials=new[]{material,material}}}};
   var common=new GameObject("Native shared rigid owner");objects.Add(common);var rotation=BomUnityCoordinates.Rotation(.41f);var position=new Vector3(7,9,0);common.transform.SetPositionAndRotation(position,rotation);var pivot=new Vector2(3.5f,6.5f);
   for(int source=0;source<2;source++){
    var rest=new Vector2(3+source,6.5f);var arrays=BomSourceMeshData.Read(entry,Matrix4x4.Translate(new Vector3(rest.x,rest.y,0)),material,64L*1024*1024);Check(arrays.Failure==null,"distinct source normalization");var prepared=BomPrismClipper.Prepare(arrays.Triangles,arrays.Materials.Length-1);var cut=BomPrismClipper.Build(prepared,new[]{new Vector2(rest.x-.5f,6),new Vector2(rest.x+.25f,6),new Vector2(rest.x+.25f,7),new Vector2(rest.x-.5f,7)});Check(cut.Supported,"distinct source clipped fixture: "+cut.Reason);var triangles=new List<BomClipTriangle>(cut.Exterior);foreach(var patch in cut.Caps)triangles.AddRange(patch.Triangles);
    var mesh=BomClipMeshUpload.Upload(triangles,0,triangles.Count,Vector2.zero,arrays.Materials.Length,"Distinct source clipped render geometry");meshes.Add(mesh);var visual=new GameObject("Source "+source);objects.Add(visual);visual.AddComponent<MeshFilter>().sharedMesh=mesh;BomSourcePresentation.AttachRestGeometry(visual.transform,common.transform,pivot);var vertices=mesh.vertices;var before=new Vector3[vertices.Length];for(int i=0;i<vertices.Length;i++)before[i]=visual.transform.TransformPoint(vertices[i]);
    var split=new GameObject("Native split owner "+source);objects.Add(split);var newPivot=rest;var nativeSplitPosition=position+rotation*new Vector3(newPivot.x-pivot.x,newPivot.y-pivot.y,0);split.transform.SetPositionAndRotation(nativeSplitPosition,rotation);BomSourcePresentation.AttachRestGeometry(visual.transform,split.transform,newPivot);
    for(int i=0;i<vertices.Length;i++)Check(Vector3.Distance(before[i],visual.transform.TransformPoint(vertices[i]))<.00001f,"shared-to-split source pivot moved a vertex or depth");
    var displacement=new Vector3(.7f,-.3f,0);split.transform.position+=displacement;for(int i=0;i<vertices.Length;i++)Check(Vector3.Distance(before[i]+displacement,visual.transform.TransformPoint(vertices[i]))<.00001f,"native moving owner applied a second source transform");
    // A flexible cell supplies its own native pivot through the same adapter.
    var flexiblePivot=new Vector2(rest.x-.125f,6.5f);var flexible=new GameObject("Native flexible cell");objects.Add(flexible);flexible.transform.SetPositionAndRotation(position+rotation*new Vector3(flexiblePivot.x-pivot.x,flexiblePivot.y-pivot.y,0),rotation);BomSourcePresentation.AttachRestGeometry(visual.transform,flexible.transform,flexiblePivot);for(int i=0;i<vertices.Length;i++)Check(Vector3.Distance(before[i],visual.transform.TransformPoint(vertices[i]))<.00001f,"flexible-cell reference pivot moved source geometry");
   }
   Debug.Log("BOM MULTI SOURCE PIVOT PASS: distinct clipped source meshes share a native rigid owner, split with new reference pivots, move independently, and use flexible-cell pivots without changing world vertices or depth");
  }finally{foreach(var obj in objects)if(obj!=null)UnityEngine.Object.DestroyImmediate(obj);foreach(var mesh in meshes)UnityEngine.Object.DestroyImmediate(mesh);UnityEngine.Object.DestroyImmediate(original);}
 }
}
