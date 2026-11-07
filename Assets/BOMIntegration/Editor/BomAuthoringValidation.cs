using System;
using System.IO;
using Bom.Unity;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class BomAuthoringValidation {
 static void Check(bool value,string text){if(!value)throw new InvalidOperationException(text);}
 public static void Run(){
  const string directory="Assets/BOMIntegration/Validation";
  if(!AssetDatabase.IsValidFolder(directory))AssetDatabase.CreateFolder("Assets/BOMIntegration","Validation");
  const string path=directory+"/Identity.unity";
  var scene=EditorSceneManager.NewScene(NewSceneSetup.EmptyScene,NewSceneMode.Single);
  var level=new GameObject("Identity fixture").AddComponent<BomLevelAuthoring>();
  level.NextIdentityDecimal="9007199254741001";
  var source=new GameObject("Source").AddComponent<BomAssetInstance>();source.transform.SetParent(level.transform);
  var part=source.gameObject.AddComponent<BomPhysicsPart>();part.PartIdDecimal="9007199254742001";
  EditorSceneManager.SaveScene(scene,path);BomAuthoringIdentity.Assign(level);
  ulong sourceId=source.Identity,partId=part.PartId;string levelId=level.LevelId;
  Check(sourceId==9007199254741001UL&&partId==9007199254742001UL,"Authoring IDs were rounded or replaced");
  var duplicate=UnityEngine.Object.Instantiate(source,level.transform);duplicate.name="Duplicate";
  duplicate.gameObject.SetActive(false);
  BomAuthoringIdentity.Assign(level);
  Check(source.Identity==sourceId&&duplicate.Identity!=sourceId&&duplicate.Identity>sourceId,"Duplicate source did not receive a fresh ID");
  var duplicatePart=new GameObject("Duplicate part").AddComponent<BomPhysicsPart>();duplicatePart.transform.SetParent(source.transform);duplicatePart.PartIdDecimal=part.PartIdDecimal;
  BomAuthoringIdentity.Assign(level);Check(part.PartId==partId&&duplicatePart.PartId!=partId,"Duplicate part did not receive a fresh ID");
  ulong duplicateId=duplicate.Identity;EditorSceneManager.SaveScene(scene,path);
  scene=EditorSceneManager.OpenScene(path,OpenSceneMode.Single);level=UnityEngine.Object.FindFirstObjectByType<BomLevelAuthoring>();BomAuthoringIdentity.Assign(level);
  var sources=level.GetComponentsInChildren<BomAssetInstance>(true);
  Check(sources.Length==2&&level.LevelId==levelId&&sources[0].Identity==sourceId&&sources[1].Identity==duplicateId,"Reopen changed source/level identity");
  string prefabPath=directory+"/IdentityTemplate.prefab";
  var prefab=PrefabUtility.SaveAsPrefabAsset(sources[0].gameObject,prefabPath);BomAuthoringIdentity.NormalizeTemplate(prefab);
  Check(prefab.GetComponent<BomAssetInstance>().Identity==0,"Prefab template has a live source ID");
  var instance=(GameObject)PrefabUtility.InstantiatePrefab(prefab);instance.transform.SetParent(level.transform);BomAuthoringIdentity.Assign(level);
  var instanceSource=instance.GetComponent<BomAssetInstance>();ulong instanceId=instanceSource.Identity;
  Check(instanceId!=0&&instanceId!=sourceId,"Prefab instance did not get a live ID");
  // Applying presentation data cannot copy live identity back into the template.
  instanceSource.AssetKey="fixture";PrefabUtility.ApplyPropertyOverride(new SerializedObject(instanceSource).FindProperty("AssetKey"),prefabPath,InteractionMode.AutomatedAction);
  BomAuthoringIdentity.Assign(level);Check(instanceSource.Identity==instanceId,"Prefab apply changed instance identity");
  EditorSceneManager.SaveScene(scene,path);string copied=directory+"/IdentityCopy.unity";Check(AssetDatabase.CopyAsset(path,copied),"Could not copy level fixture");
  EditorSceneManager.OpenScene(copied,OpenSceneMode.Single);level=UnityEngine.Object.FindFirstObjectByType<BomLevelAuthoring>();BomAuthoringIdentity.Assign(level);Check(level.LevelId!=levelId,"Copied level retained its original level ID");
  ValidateMesh();AssetDatabase.SaveAssets();Debug.Log("BOM AUTHORING PASS: high u64 identity, duplicate/reopen/prefab apply/copied level; unreadable mirrored transformed mesh");
 }
 static void ValidateMesh(){
  var original=new Mesh{name="Transform fixture"};
  original.vertices=new[]{new Vector3(0,0,0),new Vector3(1,0,0),new Vector3(0,1,0)};
  original.normals=new[]{Vector3.forward,Vector3.forward,Vector3.forward};
  original.uv=new[]{Vector2.zero,Vector2.right,Vector2.up};original.subMeshCount=1;original.SetTriangles(new[]{0,1,2},0);
  var matrix=Matrix4x4.TRS(new Vector3(7,-2,4),Quaternion.Euler(23,37,-11),new Vector3(-2,3,.4f));
  original.UploadMeshData(true);Mesh baked=null;
  try{
   Check(!original.isReadable,"Unreadable mesh fixture is still readable");baked=BomMeshPreprocessor.Bake(original,matrix,"fixture/mesh");
   var expected=matrix.MultiplyPoint3x4(Vector3.right);Check(Vector3.Distance(baked.vertices[1],expected)<.00001f,"Visual child transform was not baked exactly once");
   var triangles=baked.triangles;var vertices=baked.vertices;Vector3 geometric=Vector3.Cross(vertices[triangles[1]]-vertices[triangles[0]],vertices[triangles[2]]-vertices[triangles[0]]).normalized;
   Check(Vector3.Dot(geometric,baked.normals[0])>.9999f,"Mirrored winding/normal inverse transpose disagree");
   Check(baked.uv[2]==Vector2.up,"Baking changed exterior UV");
   string hash=BomMeshPreprocessor.ContentHash(baked,Array.Empty<Material>());Check(hash.Length==64&&hash==BomMeshPreprocessor.ContentHash(baked,Array.Empty<Material>()),"Visual hash is unstable");
   bool rejected=false;try{var invalid=BomMeshPreprocessor.Bake(original,Matrix4x4.Scale(new Vector3(0,1,1)),"fixture/singular");UnityEngine.Object.DestroyImmediate(invalid);}catch(InvalidOperationException error){rejected=error.Message.Contains("fixture/singular");}Check(rejected,"Singular transform was not rejected with its object path");
  }finally{if(baked!=null)UnityEngine.Object.DestroyImmediate(baked);UnityEngine.Object.DestroyImmediate(original);}
 }
}
