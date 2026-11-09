using System;
using System.IO;
using Bom.Native;
using Bom.Unity;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.UIElements;

public static class BomNetworkMenuBuilder {
 public const string ScenePath="Assets/BOMIntegration/NetworkMenu.unity";
 static GameObject Player(BomActorShapeInfo shape){
  const string path="Assets/BOMIntegration/NetworkClaymate.prefab";
  var root=(GameObject)PrefabUtility.InstantiatePrefab(AssetDatabase.LoadAssetAtPath<GameObject>("Assets/BOMIntegration/NativePlayer.prefab"));
  PrefabUtility.UnpackPrefabInstance(root,PrefabUnpackMode.Completely,InteractionMode.AutomatedAction);root.name="Network Claymate";root.transform.SetPositionAndRotation(Vector3.zero,Quaternion.identity);
  var visual=new GameObject("Claymate presentation");visual.transform.SetParent(root.transform,false);
  var art=(GameObject)PrefabUtility.InstantiatePrefab(AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Game/Player/Player.prefab"));
  PrefabUtility.UnpackPrefabInstance(art,PrefabUnpackMode.Completely,InteractionMode.AutomatedAction);
  foreach(var script in art.GetComponentsInChildren<MonoBehaviour>(true))UnityEngine.Object.DestroyImmediate(script);
  foreach(var collider in art.GetComponentsInChildren<Collider>(true))UnityEngine.Object.DestroyImmediate(collider);
  foreach(var body in art.GetComponentsInChildren<Rigidbody>(true))UnityEngine.Object.DestroyImmediate(body);
  foreach(var animator in art.GetComponentsInChildren<Animator>(true)){animator.applyRootMotion=false;animator.updateMode=AnimatorUpdateMode.UnscaledTime;}
  art.transform.SetParent(visual.transform,false);art.transform.localPosition=Vector3.zero;
  bool any=false;Bounds bounds=default;foreach(var renderer in art.GetComponentsInChildren<Renderer>(true)){if(!any){bounds=renderer.bounds;any=true;}else bounds.Encapsulate(renderer.bounds);}
  if(!any||bounds.size.y<=0)throw new InvalidOperationException("Original Claymate has no usable render bounds");
  float scale=2*(shape.player_radius+shape.player_segment)/bounds.size.y;art.transform.localScale*=scale;
  // Normalize only the derived visual. Native body and original prefab stay untouched.
  art.transform.localPosition=new Vector3(-bounds.center.x*scale,-bounds.min.y*scale-shape.player_radius-shape.player_segment,-bounds.center.z*scale);
  root.GetComponent<BomActorView>().AuthoredVisual=visual.transform;root.GetComponent<MeshRenderer>().enabled=false;
  var prefab=PrefabUtility.SaveAsPrefabAsset(root,path);UnityEngine.Object.DestroyImmediate(root);return prefab;
 }
 static GameObject Bomb(BomActorShapeInfo shape){
  var root=(GameObject)PrefabUtility.InstantiatePrefab(AssetDatabase.LoadAssetAtPath<GameObject>("Assets/BOMIntegration/NativeBomb.prefab"));PrefabUtility.UnpackPrefabInstance(root,PrefabUnpackMode.Completely,InteractionMode.AutomatedAction);root.name="Network bomb";
  var art=GameObject.CreatePrimitive(PrimitiveType.Sphere);art.name="Original bomb material";UnityEngine.Object.DestroyImmediate(art.GetComponent<Collider>());art.transform.SetParent(root.transform,false);art.transform.localScale=Vector3.one*(2*shape.bomb_radius);art.GetComponent<MeshRenderer>().sharedMaterial=AssetDatabase.LoadAssetAtPath<Material>("Assets/Game/Materials/Bomb.mat");
  var fuse=GameObject.CreatePrimitive(PrimitiveType.Cylinder);fuse.name="Fuse";UnityEngine.Object.DestroyImmediate(fuse.GetComponent<Collider>());fuse.transform.SetParent(art.transform,false);fuse.transform.localPosition=new Vector3(.12f,.52f,0);fuse.transform.localRotation=Quaternion.Euler(0,0,-20);fuse.transform.localScale=new Vector3(.1f,.15f,.1f);fuse.GetComponent<MeshRenderer>().sharedMaterial=AssetDatabase.LoadAssetAtPath<Material>("Assets/Game/Materials/Blast.mat");
  root.GetComponent<BomActorView>().AuthoredVisual=art.transform;root.GetComponent<MeshRenderer>().enabled=false;
  var prefab=PrefabUtility.SaveAsPrefabAsset(root,"Assets/BOMIntegration/NetworkBomb.prefab");UnityEngine.Object.DestroyImmediate(root);return prefab;
 }
 static GameObject Blast(){
  var root=new GameObject("Network blast ring");var line=root.AddComponent<LineRenderer>();line.sharedMaterial=AssetDatabase.LoadAssetAtPath<Material>("Assets/Game/Materials/Blast.mat");line.useWorldSpace=false;line.loop=true;line.positionCount=64;line.startWidth=line.endWidth=.12f;line.shadowCastingMode=UnityEngine.Rendering.ShadowCastingMode.Off;line.receiveShadows=false;
  for(int i=0;i<64;i++){float angle=i*Mathf.PI*2/64;line.SetPosition(i,new Vector3(Mathf.Cos(angle),Mathf.Sin(angle),0));}
  var script=AssetDatabase.LoadAssetAtPath<MonoScript>("Assets/Game/Bombs/BombBlastVisual.cs");if(script==null||script.GetClass()==null)throw new InvalidOperationException("Original blast-ring script is unavailable");
  var animation=(MonoBehaviour)root.AddComponent(script.GetClass());animation.enabled=false;root.AddComponent<BomLegacyBlastView>().Animation=animation;
  var prefab=PrefabUtility.SaveAsPrefabAsset(root,"Assets/BOMIntegration/NetworkBlast.prefab");UnityEngine.Object.DestroyImmediate(root);return prefab;
 }
 public static void ConfigureScene(){
  var client=UnityEngine.Object.FindFirstObjectByType<BomClientBehaviour>();client.Port=47380;client.BlastPrefab=Blast();EditorUtility.SetDirty(client);
  var shape=new BomActorShapeInfo{struct_size=(uint)System.Runtime.InteropServices.Marshal.SizeOf<BomActorShapeInfo>(),version=1};BomSession.Check(BomNative.bom_actor_shape_info(ref shape));client.BombPrefab=Bomb(shape);
  var hud=UnityEngine.Object.FindFirstObjectByType<BomNetworkHud>();hud.NetworkMenuStyle=AssetDatabase.LoadAssetAtPath<StyleSheet>("Assets/BOMIntegration/Runtime/BomNetworkMenu.uss");EditorUtility.SetDirty(hud);
  Debug.Log("BOM PRESENTATION AUDIT original_audio_clips="+AssetDatabase.FindAssets("t:AudioClip",new[]{"Assets"}).Length+" original_blast_ring=read_only_adapter native_player_capsule=unchanged");
  EditorSceneManager.SaveScene(UnityEngine.SceneManagement.SceneManager.GetActiveScene());AssetDatabase.SaveAssets();
 }
 public static void BuildMono(){
  BomYardBuilder.CreateAndExport();
  var shape=new BomActorShapeInfo{struct_size=(uint)System.Runtime.InteropServices.Marshal.SizeOf<BomActorShapeInfo>(),version=1};BomSession.Check(BomNative.bom_actor_shape_info(ref shape));
  var player=Player(shape);var bomb=Bomb(shape);
  var scene=UnityEngine.SceneManagement.SceneManager.GetActiveScene();EditorSceneManager.SaveScene(scene,ScenePath,true);scene=EditorSceneManager.OpenScene(ScenePath,OpenSceneMode.Single);
  var client=UnityEngine.Object.FindFirstObjectByType<BomClientBehaviour>();client.ConnectOnEnable=false;client.DiagnosticOverlay=false;client.PlayerPrefab=player;client.BombPrefab=bomb;
  var scenario=client.gameObject.AddComponent<BomRoundScenario>();scenario.Client=client;
  var ui=new GameObject("Network menu and arena HUD");var doc=ui.AddComponent<UIDocument>();doc.panelSettings=AssetDatabase.LoadAssetAtPath<PanelSettings>("Assets/Game/UI/ArenaPanelSettings.asset");var hud=ui.AddComponent<BomNetworkHud>();hud.Client=client;hud.ArenaHudTemplate=AssetDatabase.LoadAssetAtPath<VisualTreeAsset>("Assets/Game/UI/ArenaHud.uxml");hud.ArenaHudStyle=AssetDatabase.LoadAssetAtPath<StyleSheet>("Assets/Game/UI/ArenaHud.uss");
  EditorSceneManager.SaveScene(scene,ScenePath);AssetDatabase.SaveAssets();
  ConfigureScene();
  BuildCurrent();
 }
 public static void RebuildMono(){EditorSceneManager.OpenScene(ScenePath,OpenSceneMode.Single);ConfigureScene();BomSession.VerifyLayouts();BuildCurrent();}
 public static void BuildWithDrawFixture(){BomRoundFixtureBuilder.CreateAndExport();RebuildMono();}
 static void BuildCurrent(){
  string output=Environment.GetEnvironmentVariable("BOM_NETWORK_PLAYER_OUT");if(string.IsNullOrEmpty(output))throw new InvalidOperationException("Set BOM_NETWORK_PLAYER_OUT");Directory.CreateDirectory(output);
  PlayerSettings.SetScriptingBackend(NamedBuildTarget.Standalone,ScriptingImplementation.Mono2x);
  var scenes=File.Exists(BomRoundFixtureBuilder.ScenePath)?new[]{ScenePath,BomYardBuilder.ScenePath,BomRoundFixtureBuilder.ScenePath}:new[]{ScenePath,BomYardBuilder.ScenePath};
  var report=BuildPipeline.BuildPlayer(new BuildPlayerOptions{scenes=scenes,target=BuildTarget.StandaloneWindows64,locationPathName=Path.Combine(output,"BombNetwork.exe"),options=BuildOptions.Development});
  if(report.summary.result!=BuildResult.Succeeded)throw new InvalidOperationException("Network menu build failed");Debug.Log("BOM NETWORK MENU MONO BUILD PASS");
 }
}
