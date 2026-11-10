using System;
using System.IO;
using Bom.Unity;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class BomPerformanceBuilder {
 const string Folder="Assets/BOMIntegration/";
 static Mesh Box(string name,Vector2 lo,Vector2 hi){
  string path=Folder+name+".asset";var mesh=BomExtrusion.Build(new[]{lo,new Vector2(hi.x,lo.y),hi,new Vector2(lo.x,hi.y)},.4f);
  var old=AssetDatabase.LoadAssetAtPath<Mesh>(path);if(old==null){AssetDatabase.CreateAsset(mesh,path);return mesh;}EditorUtility.CopySerialized(mesh,old);UnityEngine.Object.DestroyImmediate(mesh);return old;
 }
 static void Visual(GameObject root,Mesh mesh,Material material){root.AddComponent<MeshFilter>().sharedMesh=mesh;var renderer=root.AddComponent<MeshRenderer>();renderer.sharedMaterials=new[]{material,material};renderer.enabled=false;}
 static void Create(string name,int columns,int parts){
  var scene=EditorSceneManager.NewScene(NewSceneSetup.DefaultGameObjects,NewSceneMode.Single);
  var level=new GameObject(name+" native authoring").AddComponent<BomLevelAuthoring>();level.LevelId="bom-"+name.ToLowerInvariant()+"-v1";level.NextIdentityDecimal="9007199254800001";
  level.SimulationBounds=new BomBounds2(new Vector2(-20,-5),new Vector2(20,40));level.KillBounds=new BomBounds2(new Vector2(-19,-4),new Vector2(19,38));level.CameraBounds=new BomBounds2(new Vector2(-18,-1),new Vector2(18,34));level.AimBounds=level.CameraBounds;level.FragmentCullBounds=level.SimulationBounds;level.BombCleanupBounds=level.SimulationBounds;level.BombSpawnX=new Vector2(-13,13);level.BombSpawnHeight=35;
  level.Spawns=new[]{new Vector2(-15,.565f),new Vector2(15,.565f),new Vector2(-16,.565f),new Vector2(16,.565f)};
  var material=AssetDatabase.LoadAssetAtPath<Material>("Assets/Game/Materials/YardDirt.mat");var mesh=Box("PerformanceBox",new Vector2(-.0625f,-.0625f),new Vector2(.0625f,.0625f));
  for(int y=0;y<columns;y++)for(int x=0;x<columns;x++){
   var group=new GameObject("Independent quartet "+x+" "+y);group.transform.SetParent(level.transform,false);group.transform.localPosition=new Vector3((x-(columns-1)*.5f)*2.1f,2+y*2.1f,0);
   var source=group.AddComponent<BomAssetInstance>();source.AssetKey="performance/disconnected-group-"+parts+"-v1";source.Motion=BomMotionPolicy.Dynamic;source.Damage=BomDamagePolicy.Destructible;source.FallbackDepth=new Vector2(-.2f,.2f);source.CapMaterial=material;
   for(int i=0;i<parts;i++){var body=new GameObject("Independent body "+i);body.transform.SetParent(group.transform,false);body.transform.localPosition=new Vector3((i%(parts==4?2:3))*.5f,(i/(parts==4?2:3))*.5f,0);Visual(body,mesh,material);var part=body.AddComponent<BomPhysicsPart>();part.Minimum=new Vector2(-.0625f,-.0625f);part.Maximum=new Vector2(.0625f,.0625f);part.MaterialKey="wood";}
  }
  var floor=new GameObject("Fixed native floor");floor.transform.SetParent(level.transform,false);floor.transform.localPosition=new Vector3(0,-.5f,0);Visual(floor,Box("PerformanceFloor",new Vector2(-18,-.5f),new Vector2(18,.5f)),material);
  var fixedSource=floor.AddComponent<BomAssetInstance>();fixedSource.AssetKey="performance/floor";fixedSource.Motion=BomMotionPolicy.Fixed;fixedSource.Damage=BomDamagePolicy.Indestructible;fixedSource.CapMaterial=material;fixedSource.FallbackDepth=new Vector2(-.2f,.2f);
  var floorPart=floor.AddComponent<BomPhysicsPart>();floorPart.Minimum=new Vector2(-18,-.5f);floorPart.Maximum=new Vector2(18,.5f);floorPart.MaterialKey="stone";
  string scenePath=Folder+name+".unity";EditorSceneManager.SaveScene(scene,scenePath);BomAuthoringIdentity.Assign(level);
  string directory=Environment.GetEnvironmentVariable("BOM_PERFORMANCE_LAYOUT_DIR");if(string.IsNullOrEmpty(directory))throw new InvalidOperationException("Set BOM_PERFORMANCE_LAYOUT_DIR");
  var registry=BomLevelExporter.Export(level,Path.Combine(directory,name+".json"));
  var client=new GameObject("Native measured client").AddComponent<BomClientBehaviour>();client.VisualRegistry=registry;client.ConnectOnEnable=false;client.DiagnosticOverlay=false;client.PlayerPrefab=AssetDatabase.LoadAssetAtPath<GameObject>(Folder+"NetworkClaymate.prefab");client.BombPrefab=AssetDatabase.LoadAssetAtPath<GameObject>(Folder+"NetworkBomb.prefab");client.BlastPrefab=AssetDatabase.LoadAssetAtPath<GameObject>(Folder+"NetworkBlast.prefab");client.Material=AssetDatabase.LoadAssetAtPath<Material>(Folder+"NativeFallback.mat");
  var camera=Camera.main;camera.orthographic=true;camera.orthographicSize=19;camera.transform.SetPositionAndRotation(new Vector3(0,16,-30),Quaternion.identity);camera.backgroundColor=new Color(.05f,.07f,.1f);client.View=camera;
  EditorSceneManager.SaveScene(scene,scenePath);AssetDatabase.SaveAssets();
 }
 public static void BuildMono()=>Build(false,true);
 public static void RebuildMono()=>Build(false,false);
 public static void RebuildIl2Cpp()=>Build(true,false);
 public static void BuildIl2Cpp()=>Build(true,true);
 static void HideAuthoringPreviews(){
  foreach(string name in new[]{"PerformanceReference","PerformanceStress"}){
   var scene=EditorSceneManager.OpenScene(Folder+name+".unity",OpenSceneMode.Single);var level=UnityEngine.Object.FindFirstObjectByType<BomLevelAuthoring>();if(level==null)throw new InvalidOperationException("Missing benchmark authoring root");
   foreach(var renderer in level.GetComponentsInChildren<Renderer>(true))renderer.enabled=false;
   EditorSceneManager.SaveScene(scene);foreach(var renderer in level.GetComponentsInChildren<Renderer>(true))if(renderer.enabled)throw new InvalidOperationException("Authoring preview leaked into the benchmark player");
  }
  AssetDatabase.SaveAssets();Debug.Log("BOM BENCHMARK VISIBILITY PASS: authoring previews hidden; native presenters own all physical body visuals");
 }
 static void Build(bool il2cpp,bool create){
  if(create){Create("PerformanceReference",10,4);Create("PerformanceStress",10,9);}HideAuthoringPreviews();BomSession.VerifyLayouts();BomAuthorityValidation.Run();BomM7GeometryGate.Run();
  string output=Environment.GetEnvironmentVariable("BOM_PERFORMANCE_PLAYER_OUT");if(string.IsNullOrEmpty(output))throw new InvalidOperationException("Set BOM_PERFORMANCE_PLAYER_OUT");Directory.CreateDirectory(output);
  PlayerSettings.enableFrameTimingStats=true;PlayerSettings.SetScriptingBackend(NamedBuildTarget.Standalone,il2cpp?ScriptingImplementation.IL2CPP:ScriptingImplementation.Mono2x);
  var report=BuildPipeline.BuildPlayer(new BuildPlayerOptions{scenes=new[]{BomNetworkMenuBuilder.ScenePath,Folder+"PerformanceReference.unity",Folder+"PerformanceStress.unity",BomRoundFixtureBuilder.ScenePath},target=BuildTarget.StandaloneWindows64,locationPathName=Path.Combine(output,"BombPerformance.exe"),options=BuildOptions.Development});
  if(report.summary.result!=BuildResult.Succeeded)throw new InvalidOperationException("Performance player build failed");Debug.Log("BOM PERFORMANCE BUILD PASS "+(il2cpp?"IL2CPP":"Mono"));
 }
}
