using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using Bom.Unity;
using Bom.Native;
using System.Runtime.InteropServices;

public static class BomSliceBuilder {
 static GameObject ActorPrefab(string name,bool player,Material material,GameObject parent){
  Mesh actorMesh=null;
  if(parent!=null){
   var info=new BomActorShapeInfo{struct_size=(uint)Marshal.SizeOf<BomActorShapeInfo>(),version=1};BomSession.Check(BomNative.bom_actor_shape_info(ref info));
   string meshPath="Assets/BOMIntegration/"+name+"Mesh.asset";actorMesh=AssetDatabase.LoadAssetAtPath<Mesh>(meshPath);var generated=BomExtrusion.Build(BomUnityCoordinates.ActorOutline(player,info));
   if(actorMesh==null){actorMesh=generated;AssetDatabase.CreateAsset(actorMesh,meshPath);}else{EditorUtility.CopySerialized(generated,actorMesh);UnityEngine.Object.DestroyImmediate(generated);EditorUtility.SetDirty(actorMesh);}
  }
  string path="Assets/BOMIntegration/"+name+".prefab";var prefab=AssetDatabase.LoadAssetAtPath<GameObject>(path);if(prefab!=null)return prefab;
  var instance=parent==null?new GameObject(name):(GameObject)PrefabUtility.InstantiatePrefab(parent);instance.name=name;
  if(parent==null){instance.AddComponent<MeshFilter>();instance.AddComponent<MeshRenderer>().sharedMaterials=new[]{material,material};instance.AddComponent<BomActorView>();}
  else{
   instance.GetComponent<MeshFilter>().sharedMesh=actorMesh;
  }
  prefab=PrefabUtility.SaveAsPrefabAsset(instance,path);UnityEngine.Object.DestroyImmediate(instance);return prefab;
 }
 public static void BuildMono() {Build(false);}
 public static void BuildIl2Cpp() {Build(true);}
 static void Build(bool il2cpp) {
  string output=Environment.GetEnvironmentVariable("BOM_SLICE_OUTPUT");if(string.IsNullOrEmpty(output))throw new Exception("BOM_SLICE_OUTPUT required");Directory.CreateDirectory(output);
  foreach(string pluginPath in AssetDatabase.GetAllAssetPaths())if(pluginPath.EndsWith("/bomcore.dll")){
   var importer=(PluginImporter)AssetImporter.GetAtPath(pluginPath);importer.SetCompatibleWithAnyPlatform(false);importer.SetCompatibleWithEditor(true);importer.SetEditorData("CPU","x86_64");importer.SetEditorData("OS","Windows");importer.SetCompatibleWithPlatform(BuildTarget.StandaloneWindows64,true);importer.SetPlatformData(BuildTarget.StandaloneWindows64,"CPU","x86_64");importer.SaveAndReimport();
  }
  BomGeometryValidation.Run();
  var scene=EditorSceneManager.NewScene(NewSceneSetup.EmptyScene,NewSceneMode.Single);
  var camera=new GameObject("Native view").AddComponent<Camera>();camera.orthographic=true;camera.orthographicSize=14;camera.transform.position=new Vector3(0,10,-40);camera.nearClipPlane=0.1f;camera.farClipPlane=100;camera.clearFlags=CameraClearFlags.SolidColor;camera.backgroundColor=new Color(0.045f,0.06f,0.09f);camera.gameObject.AddComponent<AudioListener>();
  const string materialPath="Assets/BOMIntegration/NativeFallback.mat";var material=AssetDatabase.LoadAssetAtPath<Material>(materialPath);if(material==null){material=new Material(Shader.Find("Universal Render Pipeline/Unlit"));AssetDatabase.CreateAsset(material,materialPath);}
  var client=new GameObject("Native session").AddComponent<BomClientBehaviour>();client.Material=material;client.View=camera;
  var actor=ActorPrefab("NativeActor",false,material,null);client.PlayerPrefab=ActorPrefab("NativePlayer",true,material,actor);client.BombPrefab=ActorPrefab("NativeBomb",false,material,actor);
  const string path="Assets/BOMIntegration/NativeSlice.unity";EditorSceneManager.SaveScene(scene,path);AssetDatabase.SaveAssets();
  PlayerSettings.SetScriptingBackend(NamedBuildTarget.Standalone,il2cpp?ScriptingImplementation.IL2CPP:ScriptingImplementation.Mono2x);
  var built=BuildPipeline.BuildPlayer(new BuildPlayerOptions{scenes=new[]{path},target=BuildTarget.StandaloneWindows64,locationPathName=Path.Combine(output,"BombNativeSlice.exe"),options=BuildOptions.Development});
  File.WriteAllText(Path.Combine(output,"build-summary.json"),JsonUtility.ToJson(new Result{result=built.summary.result.ToString(),errors=(int)built.summary.totalErrors,warnings=(int)built.summary.totalWarnings},true));
  if(built.summary.result!=BuildResult.Succeeded)throw new Exception("Native Unity slice build failed");
 }
 [Serializable]class Result{public string result;public int errors,warnings;}
}
