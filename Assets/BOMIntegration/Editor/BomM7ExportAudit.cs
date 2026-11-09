using System;
using System.IO;
using Bom.Unity;
using UnityEngine;
using UnityEditor;
public static class BomM7ExportAudit {
 [Serializable]sealed class RockReport{public string asset,classification,cut_result,remedy;public int triangles,candidates;public bool tier2_geometry;}
 public static void Run(){
  BomM7GeometryGate.Run();BomLevelExportValidation.Run();BomYardBuilder.CreateAndExport();
  const string path="Assets/Game/Geometry/Rock.fbx";Mesh original=null;foreach(var asset in AssetDatabase.LoadAllAssetsAtPath(path))if(asset is Mesh mesh){original=mesh;break;}if(original==null)throw new InvalidOperationException("The original Rock.fbx render mesh must be audited");
  var report=new RockReport{asset=path,remedy="Keep the original FBX/importer unchanged. If the audited source is open or nonmanifold, author a closed derived source or declare native extrusion."};Mesh derived=null;
  try{
   derived=BomMeshPreprocessor.Bake(original,Matrix4x4.identity,path);var material=AssetDatabase.LoadAssetAtPath<Material>("Assets/BOMIntegration/NativeFallback.mat");var entry=new BomVisualEntry{BuilderVersion=2,ContentHash=new string('b',64),Groups=new[]{new BomVisualMeshGroup{Mesh=derived,SurfaceMaterials=new[]{material}}}};
   var arrays=BomSourceMeshData.Read(entry,Matrix4x4.identity,material,64L*1024*1024);if(arrays.Failure!=null){report.classification=arrays.Failure;}else{var source=BomPrismClipper.Prepare(arrays.Triangles,arrays.Materials.Length-1);report.triangles=arrays.Triangles.Length;report.classification=source.Failure??source.Classification;if(source.Failure==null){float middle=(source.Min.x+source.Max.x)/2;var clipped=BomPrismClipper.Build(source,new[]{new Vector2(middle,source.Min.y-1),new Vector2(source.Max.x+1,source.Min.y-1),new Vector2(source.Max.x+1,source.Max.y+1),new Vector2(middle,source.Max.y+1)});report.cut_result=clipped.Reason;report.tier2_geometry=clipped.Supported;report.candidates=clipped.Candidates;}}
  }finally{if(derived!=null)UnityEngine.Object.DestroyImmediate(derived);}
  string output=Environment.GetEnvironmentVariable("BOM_M7_ROCK_AUDIT");if(string.IsNullOrEmpty(output))throw new InvalidOperationException("Set BOM_M7_ROCK_AUDIT");Directory.CreateDirectory(Path.GetDirectoryName(output));File.WriteAllText(output,JsonUtility.ToJson(report,true));Debug.Log("BOM ORIGINAL ROCK AUDIT "+report.classification+" cut="+report.cut_result+" tier2="+report.tier2_geometry);
 }
}
