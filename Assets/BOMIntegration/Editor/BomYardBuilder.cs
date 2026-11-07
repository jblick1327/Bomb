using System;
using System.Collections.Generic;
using System.IO;
using Bom.Unity;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEngine;
using UnityEngine.SceneManagement;

public static class BomYardBuilder {
 public const string ScenePath="Assets/BOMIntegration/NetworkYard.unity";
 public static void BuildMono()=>Build(false);
 public static void BuildIl2Cpp()=>Build(true);
 static void Build(bool il2cpp){CreateAndExport();BomGeometryValidation.Run();string output=Environment.GetEnvironmentVariable("BOM_YARD_PLAYER_OUT");if(string.IsNullOrEmpty(output))throw new InvalidOperationException("Set BOM_YARD_PLAYER_OUT");Directory.CreateDirectory(output);PlayerSettings.SetScriptingBackend(NamedBuildTarget.Standalone,il2cpp?ScriptingImplementation.IL2CPP:ScriptingImplementation.Mono2x);var report=BuildPipeline.BuildPlayer(new BuildPlayerOptions{scenes=new[]{ScenePath},target=BuildTarget.StandaloneWindows64,locationPathName=Path.Combine(output,"BombNetworkYard.exe"),options=BuildOptions.Development});if(report.summary.result!=BuildResult.Succeeded)throw new InvalidOperationException("Network yard build failed: "+report.summary.result);Debug.Log("BOM NETWORK YARD "+(il2cpp?"IL2CPP":"MONO")+" BUILD PASS");}
 [Serializable]sealed class Classification{public string path,classification,reason;}
 [Serializable]sealed class ClassificationReport{public Classification[] objects;}
 static string OriginalPath(Transform t)=>t.parent==null?t.name:OriginalPath(t.parent)+"/"+t.name;
 static Transform Find(Scene scene,string path){foreach(var root in scene.GetRootGameObjects()){if(root.name==path)return root.transform;var found=root.transform.Find(path.StartsWith(root.name+"/",StringComparison.Ordinal)?path.Substring(root.name.Length+1):path);if(found!=null&&OriginalPath(found)==path)return found;}return null;}
 static Bounds RenderBounds(Transform root){bool any=false;var result=new Bounds(root.position,Vector3.zero);foreach(var renderer in root.GetComponentsInChildren<Renderer>(true)){if(!any){result=renderer.bounds;any=true;}else result.Encapsulate(renderer.bounds);}if(!any)throw new InvalidOperationException(OriginalPath(root)+": no render bounds for explicit proxy authoring");return result;}
 static BomPhysicsPart Part(GameObject root,string name,Vector2 lo,Vector2 hi,string material,string note){var child=new GameObject(name);child.transform.SetParent(root.transform,false);var part=child.AddComponent<BomPhysicsPart>();part.WorldRestCoordinates=true;part.Shape=BomProxyShape.Rectangle;part.Minimum=lo;part.Maximum=hi;part.MaterialKey=material;part.ApproximationNote=note;return part;}
 static BomAssetInstance Bind(Transform root,string key,BomMotionPolicy motion,BomDamagePolicy damage,Vector2 depth,string note){var source=root.gameObject.AddComponent<BomAssetInstance>();source.AssetKey=key;source.OriginalObjectPath=OriginalPath(root);source.Motion=motion;source.Damage=damage;source.FallbackDepth=depth;source.ApproximationNote=note;return source;}
 static string MeshKey(Transform root){var text="";foreach(var filter in root.GetComponentsInChildren<MeshFilter>(true)){text+=AssetDatabase.GetAssetPath(filter.sharedMesh)+"#"+(filter.sharedMesh==null?"missing":filter.sharedMesh.name);var renderer=filter.GetComponent<MeshRenderer>();if(renderer!=null)foreach(var material in renderer.sharedMaterials)text+="|"+AssetDatabase.GetAssetPath(material);}return "yard/"+Hash128.Compute(text).ToString();}
 public static void CreateAndExport(){
  string output=Environment.GetEnvironmentVariable("BOM_YARD_LAYOUT_OUT");if(string.IsNullOrEmpty(output))throw new InvalidOperationException("Set BOM_YARD_LAYOUT_OUT");
  BomLevelAuthoring level;
  if(File.Exists(ScenePath)){var existing=EditorSceneManager.OpenScene(ScenePath,OpenSceneMode.Single);level=UnityEngine.Object.FindFirstObjectByType<BomLevelAuthoring>();if(level==null)throw new InvalidOperationException("Existing network yard has no level authoring root");}
  else{
   var scene=EditorSceneManager.OpenScene("Assets/Game/Scenes/YardLevel.unity",OpenSceneMode.Single);
   EditorSceneManager.SaveScene(scene,ScenePath,true);scene=EditorSceneManager.OpenScene(ScenePath,OpenSceneMode.Single);
   var roots=scene.GetRootGameObjects();foreach(var root in roots)if(PrefabUtility.IsAnyPrefabInstanceRoot(root))PrefabUtility.UnpackPrefabInstance(root,PrefabUnpackMode.Completely,InteractionMode.AutomatedAction);
   var rows=new List<Classification>();foreach(var root in scene.GetRootGameObjects())foreach(var t in root.GetComponentsInChildren<Transform>(true))rows.Add(new Classification{path=OriginalPath(t),classification="decorative",reason="Not opted into native gameplay; distant art/colliders do not imply XY solidity"});
   var levelRoot=new GameObject("BOM Yard Authoring");level=levelRoot.AddComponent<BomLevelAuthoring>();level.LevelId="bomb-yard-network-v1";level.NextIdentityDecimal="9007199254741001";
   level.SimulationBounds=new BomBounds2(new Vector2(-22,-28),new Vector2(22,38));level.KillBounds=new BomBounds2(new Vector2(-18,-25.36f),new Vector2(18,34.64f));level.CameraBounds=new BomBounds2(new Vector2(-20,0),new Vector2(20,24));level.AimBounds=new BomBounds2(new Vector2(-21,-25),new Vector2(21,35));level.FragmentCullBounds=new BomBounds2(new Vector2(-30,-32),new Vector2(30,45));level.BombCleanupBounds=new BomBounds2(new Vector2(-24,-29),new Vector2(24,43));level.BombSpawnX=new Vector2(-17.25f,17.25f);level.BombSpawnHeight=36.64f;
   level.Spawns=new[]{new Vector2(-11.5f,10.065f),new Vector2(11.5f,10.065f),new Vector2(-2,13.565f),new Vector2(2,13.565f)};
   level.Materials.Add(new BomCustomMaterial{Name="earth",Base="stone",Color=new Color32(132,95,64,255)});level.Materials.Add(new BomCustomMaterial{Name="grass",Base="stone",Color=new Color32(103,153,70,255)});
   var terrain=Find(scene,"YardLevel");var grass=Find(scene,"YardLevel/Grass_Mesh");var earth=Find(scene,"YardLevel/Ground_Mesh");if(terrain==null||grass==null||earth==null)throw new InvalidOperationException("Original yard mesh paths changed; inspect the inventory");
   var groundSource=Bind(terrain,MeshKey(terrain),BomMotionPolicy.Anchored,BomDamagePolicy.Destructible,new Vector2(-5.5f,5.5f),"Explicit layered XY proxies: earth follows the authored ground rectangle; grass uses y=5..6 to remove the original art's overlapping y=4..5 layer. This is a listed proxy approximation, not an inferred collision mesh.");
   var soil=Part(terrain.gameObject,"Native earth proxy",new Vector2(-20,-25),new Vector2(20,5),"earth","Rectangular ground proxy chosen explicitly from the inspected mesh bounds");soil.Anchors=new[]{new BomAnchorSegment{A=new Vector2(-20,-25),B=new Vector2(20,-25)}};
   var turf=Part(terrain.gameObject,"Native grass proxy",new Vector2(-20.5f,5),new Vector2(20.5f,6),"grass","The grass art overlaps earth from y=4..5; physical layers meet only at y=5");level.Glue.Add(new BomGlueAuthoring{A=soil,B=turf});
   foreach(string path in new[]{"Arena/Bottom Boundary","Arena/Left Wall","Arena/Right Wall"}){
    var transform=Find(scene,path);if(transform==null||transform.GetComponent<Collider>()==null)throw new InvalidOperationException("Missing explicit boundary: "+path);var bounds=transform.GetComponent<Collider>().bounds;
    Bind(transform,MeshKey(transform)+"/"+transform.name,BomMotionPolicy.Fixed,BomDamagePolicy.Indestructible,new Vector2(bounds.min.z,bounds.max.z),"Explicit XY boundary from the original gameplay wall collider; no collider is retained at runtime");Part(transform.gameObject,"Native fixed boundary",new Vector2(bounds.min.x,bounds.min.y),new Vector2(bounds.max.x,bounds.max.y),"stone","");
   }
   foreach(var root in roots){
    if(root.name=="Cube (12)"||!root.name.StartsWith("Cube",StringComparison.Ordinal)&&!root.name.StartsWith("Rock",StringComparison.Ordinal))continue;
    var bounds=RenderBounds(root.transform);bool rock=root.name.StartsWith("Rock",StringComparison.Ordinal);
    Bind(root.transform,MeshKey(root.transform),BomMotionPolicy.Dynamic,BomDamagePolicy.Destructible,new Vector2(bounds.min.z,bounds.max.z),rock?"Deliberately authored rectangular XY rock proxy from render bounds; original Rock.fbx render mesh remains available. Legacy collider references are not gameplay geometry.":"Explicit box proxy exactly matches the axis-aligned placeholder cube in XY; depth remains visual.");
    Part(root,"Native physical proxy",new Vector2(bounds.min.x,bounds.min.y),new Vector2(bounds.max.x,bounds.max.y),rock?"stone":"wood",rock?"Rock silhouette is deliberately simplified to this visible rectangle":"");
   }
   foreach(var root in roots)root.transform.SetParent(levelRoot.transform,true);
   foreach(var source in level.GetComponentsInChildren<BomAssetInstance>(true))foreach(var row in rows)if(row.path==source.OriginalObjectPath){row.classification="native physics source";row.reason=source.ApproximationNote+" motion="+source.Motion+" damage="+source.Damage;}
   foreach(var row in rows){if(row.path=="Arena/Level Bounds"){row.classification="bounds metadata";row.reason="Original trigger supplies conceptual kill extent; bounds do not create a solid";}if(row.path=="Arena/Back Wall"){row.classification="legacy depth constraint";row.reason="Native physics is XY; a Z fence must not fill the entire arena with a solid";}if(row.path=="Cube (12)"){row.classification="decorative background";row.reason="187.91-wide slab lies at visual depth z=6..7, beyond the gameplay plane; no automatic XY solidity";}}
   foreach(var behaviour in level.GetComponentsInChildren<MonoBehaviour>(true))if(behaviour!=null&&behaviour.GetType().Assembly.GetName().Name=="Assembly-CSharp")UnityEngine.Object.DestroyImmediate(behaviour);
   foreach(var collider in level.GetComponentsInChildren<Collider>(true))UnityEngine.Object.DestroyImmediate(collider);foreach(var body in level.GetComponentsInChildren<Rigidbody>(true))UnityEngine.Object.DestroyImmediate(body);foreach(var animator in level.GetComponentsInChildren<Animator>(true))animator.applyRootMotion=false;
   foreach(var source in level.GetComponentsInChildren<BomAssetInstance>(true))foreach(var renderer in source.Group.GetComponentsInChildren<Renderer>(true))renderer.enabled=false;
   foreach(var camera in level.GetComponentsInChildren<Camera>(true))camera.enabled=false;
   EditorSceneManager.SaveScene(scene,ScenePath);BomAuthoringIdentity.Assign(level);EditorSceneManager.SaveScene(scene,ScenePath);
   Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output)));File.WriteAllText(output+".classifications.json",JsonUtility.ToJson(new ClassificationReport{objects=rows.ToArray()},true));
  }
  if(level.YardBuilderVersion==0){
   foreach(var source in level.GetComponentsInChildren<BomAssetInstance>(true))if(source.OriginalObjectPath.StartsWith("Rock",StringComparison.Ordinal)&&!source.gameObject.activeInHierarchy){source.IncludeInExport=false;source.ApproximationNote="Inactive reference rock in the original yard: retained as art/authoring reference and excluded from native gameplay by default";EditorUtility.SetDirty(source);}
   level.YardBuilderVersion=1;EditorUtility.SetDirty(level);EditorSceneManager.SaveScene(level.gameObject.scene,ScenePath);
  }
  if(File.Exists(output+".classifications.json")){var classifications=JsonUtility.FromJson<ClassificationReport>(File.ReadAllText(output+".classifications.json"));foreach(var source in level.GetComponentsInChildren<BomAssetInstance>(true))if(!source.IncludeInExport)foreach(var row in classifications.objects)if(row.path==source.OriginalObjectPath){row.classification="inactive authoring/art reference";row.reason=source.ApproximationNote;}File.WriteAllText(output+".classifications.json",JsonUtility.ToJson(classifications,true));}
  if(level.YardBuilderVersion==1){
   BomAssetInstance earthSource=null;var walls=new List<BomAssetInstance>();foreach(var source in level.GetComponentsInChildren<BomAssetInstance>(true)){if(source.OriginalObjectPath=="YardLevel")earthSource=source;if(source.OriginalObjectPath=="Arena/Left Wall"||source.OriginalObjectPath=="Arena/Right Wall")walls.Add(source);}
   if(earthSource==null)throw new InvalidOperationException("Missing yard terrain source");foreach(var wall in walls)foreach(var soil in earthSource.GetComponentsInChildren<BomPhysicsPart>(true))level.AllowedOverlaps.Add(new BomOverlapAuthoring{A=wall.GetComponentInChildren<BomPhysicsPart>(true),B=soil,Reason="The explicit side wall continues through the earth/grass edge. Both opted-in XY solids intentionally overlap; Z depth provides no collision exception."});
   level.YardBuilderVersion=2;EditorUtility.SetDirty(level);EditorSceneManager.SaveScene(level.gameObject.scene,ScenePath);
  }
  if(level.YardBuilderVersion==2){
   foreach(string name in new[]{"Player","Player (1)"}){var legacy=level.transform.Find(name);if(legacy!=null)legacy.gameObject.SetActive(false);}
   level.YardBuilderVersion=3;EditorUtility.SetDirty(level);EditorSceneManager.SaveScene(level.gameObject.scene,ScenePath);
  }
  var registry=BomLevelExporter.Export(level,output);
  var client=UnityEngine.Object.FindFirstObjectByType<BomClientBehaviour>();if(client==null){var session=new GameObject("BOM native yard session");client=session.AddComponent<BomClientBehaviour>();}
  client.VisualRegistry=registry;client.Material=AssetDatabase.LoadAssetAtPath<Material>("Assets/BOMIntegration/NativeFallback.mat");client.PlayerPrefab=AssetDatabase.LoadAssetAtPath<GameObject>("Assets/BOMIntegration/NativePlayer.prefab");client.BombPrefab=AssetDatabase.LoadAssetAtPath<GameObject>("Assets/BOMIntegration/NativeBomb.prefab");
  var view=GameObject.Find("BOM native yard camera");if(view==null)view=new GameObject("BOM native yard camera");var activeCamera=view.GetComponent<Camera>();if(activeCamera==null)activeCamera=view.AddComponent<Camera>();activeCamera.orthographic=true;activeCamera.transform.position=new Vector3(0,12,-40);activeCamera.transform.rotation=Quaternion.identity;activeCamera.nearClipPlane=.1f;activeCamera.farClipPlane=200;activeCamera.clearFlags=CameraClearFlags.SolidColor;activeCamera.backgroundColor=new Color(.05f,.07f,.10f);client.View=activeCamera;
  foreach(var listener in UnityEngine.Object.FindObjectsByType<AudioListener>(FindObjectsInactive.Include,FindObjectsSortMode.None))listener.enabled=false;if(view.GetComponent<AudioListener>()==null)view.AddComponent<AudioListener>();else view.GetComponent<AudioListener>().enabled=true;
  EditorSceneManager.SaveScene(level.gameObject.scene,ScenePath);AssetDatabase.SaveAssets();Debug.Log("BOM NETWORK YARD EXPORTED "+output);
 }
}
