using System;
using System.IO;
using Bom.Unity;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.UIElements;

public static class BomRoundFixtureBuilder {
 public const string ScenePath="Assets/BOMIntegration/RoundDraw.unity";
 public static void CreateAndExport(){
  string output=Environment.GetEnvironmentVariable("BOM_ROUND_DRAW_LAYOUT_OUT");if(string.IsNullOrEmpty(output))throw new InvalidOperationException("Set BOM_ROUND_DRAW_LAYOUT_OUT");
  var scene=EditorSceneManager.NewScene(NewSceneSetup.DefaultGameObjects,NewSceneMode.Single);
  var level=new GameObject("Native simultaneous-death fixture").AddComponent<BomLevelAuthoring>();level.LevelId="bom-elimination-draw-fixture-v1";level.NextIdentityDecimal="9007199254750001";
  level.SimulationBounds=new BomBounds2(new Vector2(-7,-4),new Vector2(7,10));level.KillBounds=new BomBounds2(new Vector2(-6,-3),new Vector2(6,8));level.CameraBounds=new BomBounds2(new Vector2(-6,-1),new Vector2(6,6));level.AimBounds=new BomBounds2(new Vector2(-6,-2),new Vector2(6,8));level.FragmentCullBounds=new BomBounds2(new Vector2(-10,-6),new Vector2(10,12));level.BombCleanupBounds=new BomBounds2(new Vector2(-8,-4),new Vector2(8,10));
  level.Spawns=new[]{new Vector2(-3,.565f),new Vector2(-.8f,.565f),new Vector2(.8f,.565f),new Vector2(3,.565f)};level.BombSpawnX=new Vector2(-.05f,.05f);level.BombSpawnHeight=4;
  // Fixture-only coordinates guarantee that one ordinary falling bomb reaches
  // both capsules. Native drop intervals, body, fuse and lethal rules are unchanged.
  var floor=new GameObject("Fixed floor");floor.transform.SetParent(level.transform,false);floor.transform.localPosition=new Vector3(0,-.5f,0);
  var mesh=BomExtrusion.Build(new[]{new Vector2(-5,-.5f),new Vector2(5,-.5f),new Vector2(5,.5f),new Vector2(-5,.5f)},1);const string meshPath="Assets/BOMIntegration/RoundFloor.asset";var existing=AssetDatabase.LoadAssetAtPath<Mesh>(meshPath);if(existing==null){existing=mesh;AssetDatabase.CreateAsset(mesh,meshPath);}else{EditorUtility.CopySerialized(mesh,existing);UnityEngine.Object.DestroyImmediate(mesh);EditorUtility.SetDirty(existing);}
  floor.AddComponent<MeshFilter>().sharedMesh=existing;var renderer=floor.AddComponent<MeshRenderer>();renderer.sharedMaterials=new[]{AssetDatabase.LoadAssetAtPath<Material>("Assets/Game/Materials/YardGrass.mat"),AssetDatabase.LoadAssetAtPath<Material>("Assets/Game/Materials/YardDirt.mat")};renderer.enabled=false;
  var source=floor.AddComponent<BomAssetInstance>();source.AssetKey="round-fixture/fixed-floor";source.Motion=BomMotionPolicy.Fixed;source.Damage=BomDamagePolicy.Indestructible;source.FallbackDepth=new Vector2(-.5f,.5f);
  var part=floor.AddComponent<BomPhysicsPart>();part.Minimum=new Vector2(-5,-.5f);part.Maximum=new Vector2(5,.5f);part.MaterialKey="stone";
  EditorSceneManager.SaveScene(scene,ScenePath);BomAuthoringIdentity.Assign(level);var registry=BomLevelExporter.Export(level,output);
  var client=new GameObject("Native round fixture client").AddComponent<BomClientBehaviour>();client.VisualRegistry=registry;client.ConnectOnEnable=false;client.DiagnosticOverlay=false;client.PlayerPrefab=AssetDatabase.LoadAssetAtPath<GameObject>("Assets/BOMIntegration/NetworkClaymate.prefab");client.BombPrefab=AssetDatabase.LoadAssetAtPath<GameObject>("Assets/BOMIntegration/NetworkBomb.prefab");client.Material=AssetDatabase.LoadAssetAtPath<Material>("Assets/BOMIntegration/NativeFallback.mat");
  var camera=Camera.main;camera.orthographic=true;camera.transform.SetPositionAndRotation(new Vector3(0,2.5f,-20),Quaternion.identity);camera.orthographicSize=6;camera.backgroundColor=new Color(.05f,.07f,.1f);client.View=camera;
  var scenario=client.gameObject.AddComponent<BomRoundScenario>();scenario.Client=client;
  var ui=new GameObject("Network fixture HUD");ui.AddComponent<UIDocument>().panelSettings=AssetDatabase.LoadAssetAtPath<PanelSettings>("Assets/Game/UI/ArenaPanelSettings.asset");var hud=ui.AddComponent<BomNetworkHud>();hud.Client=client;hud.ArenaHudTemplate=AssetDatabase.LoadAssetAtPath<VisualTreeAsset>("Assets/Game/UI/ArenaHud.uxml");hud.ArenaHudStyle=AssetDatabase.LoadAssetAtPath<StyleSheet>("Assets/Game/UI/ArenaHud.uss");
  BomNetworkMenuBuilder.ConfigureScene();EditorSceneManager.SaveScene(scene,ScenePath);AssetDatabase.SaveAssets();Debug.Log("BOM ROUND DRAW FIXTURE EXPORTED "+output);
 }
}
