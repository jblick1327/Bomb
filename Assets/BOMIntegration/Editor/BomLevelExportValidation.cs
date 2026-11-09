using System;
using System.IO;
using Bom.Unity;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class BomLevelExportValidation {
 [Serializable]sealed class SourceReport{public float[] matrix_probe;}
 [Serializable]sealed class Report{public string status,gameplay_manifest_hash,catalog_hash;public int source_count,part_count,cell_count;public SourceReport[] sources;}
 static void Check(bool value,string text){if(!value)throw new InvalidOperationException(text);}
 public static void Run(){
  const string folder="Assets/BOMIntegration/Validation";if(!AssetDatabase.IsValidFolder(folder))AssetDatabase.CreateFolder("Assets/BOMIntegration","Validation");
  var scene=EditorSceneManager.NewScene(NewSceneSetup.EmptyScene,NewSceneMode.Single);var level=new GameObject("Export fixture").AddComponent<BomLevelAuthoring>();level.NextIdentityDecimal="9007199254741001";level.LevelId="editor-export-v4-fixture";
  var first=Cube(level,"Explicit floor",new Vector2(-6,-1),new Vector2(6,0));first.Motion=BomMotionPolicy.Fixed;first.Damage=BomDamagePolicy.Indestructible;
  first.transform.localPosition=new Vector3(7,-2,4);first.transform.localRotation=Quaternion.Euler(23,37,-11);first.transform.localScale=new Vector3(-2,3,.4f);
  first.ApproximationNote="Transform fixture: explicit world-rest floor is deliberately independent of the rotated visual cube.";
  var second=Cube(level,"Same asset second instance",new Vector2(1,0),new Vector2(2,1));second.Motion=BomMotionPolicy.Dynamic;second.Damage=BomDamagePolicy.Destructible;
  level.Spawns[3]=new Vector2(-3,.565f);
  second.transform.localPosition=new Vector3(-1,2,-.5f);
  EditorSceneManager.SaveScene(scene,folder+"/ExportFixture.unity");BomAuthoringIdentity.Assign(level);
  string output=Environment.GetEnvironmentVariable("BOM_EXPORT_VALIDATION_OUT");if(string.IsNullOrEmpty(output))throw new InvalidOperationException("Set BOM_EXPORT_VALIDATION_OUT to a new evidence layout JSON path");
  var registry=BomLevelExporter.Export(level,output);EditorSceneManager.SaveScene(scene);
  Check(first.Identity==9007199254741001UL&&second.Identity==9007199254741002UL,"Exact source identity allocation differs");
  Check(registry.Entries.Length==1&&registry.Entries[0].Groups.Length==1&&registry.Entries[0].IntactPrefab!=null,"Two identical asset instances did not share one runtime registry entry");
  Check(registry.Entries[0].IntactPrefab.GetComponentsInChildren<Collider>(true).Length==0&&registry.Entries[0].IntactPrefab.GetComponentsInChildren<MonoBehaviour>(true).Length==0,"Intact prefab imported gameplay authority");
  string text=File.ReadAllText(output);Check(text.Contains("9007199254741001")&&text.Contains("9007199254742001"),"Exporter rounded full-width source/part IDs");
  var report=JsonUtility.FromJson<Report>(File.ReadAllText(output+".native-report.json"));Check(report.status=="passed"&&report.source_count==2&&report.part_count==2&&report.cell_count>1,"Native report did not validate actual constructed geometry");
  Check(registry.InitialSources.Length==2&&registry.InitialSources[0].SourceIdentity=="9007199254741001"&&registry.InitialSources[0].InitialCellIds.Length+registry.InitialSources[1].InitialCellIds.Length==report.cell_count,"Native exact initial source/cell membership differs");
  Check(registry.GameplayManifestHash==report.gameplay_manifest_hash&&registry.CatalogHash==report.catalog_hash,"Registry did not use native fingerprints");
  Vector3 expected=first.Group.localToWorldMatrix.MultiplyPoint3x4(new Vector3(1,2,3));float[] point=report.sources[0].matrix_probe;
  Check(Vector3.Distance(expected,new Vector3(point[0],point[1],point[2]))<.0001f,"Column-major Unity/native transform differs");
  AssetDatabase.SaveAssets();Debug.Log("BOM LEVEL AUTHORING EXPORT PASS: native construction, two high-u64 sources, shared runtime mesh/material registry, arbitrary mirrored affine matrix and explicit proxies");
 }
 static BomAssetInstance Cube(BomLevelAuthoring level,string name,Vector2 lo,Vector2 hi){
  var root=GameObject.CreatePrimitive(PrimitiveType.Cube);root.name=name;root.transform.SetParent(level.transform);UnityEngine.Object.DestroyImmediate(root.GetComponent<Collider>());
  var source=root.AddComponent<BomAssetInstance>();source.AssetKey="fixture/cube";source.Motion=BomMotionPolicy.Dynamic;source.FallbackDepth=new Vector2(-.5f,.5f);
  var part=root.AddComponent<BomPhysicsPart>();part.WorldRestCoordinates=true;part.Minimum=lo;part.Maximum=hi;part.PartIdDecimal="9007199254742001";part.MaterialKey="stone";return source;
 }
}
