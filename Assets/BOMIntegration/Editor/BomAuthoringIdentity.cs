using System;
using System.Collections.Generic;
using System.Globalization;
using Bom.Unity;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

// Editor-only allocation; runtime never invents authoritative instance IDs.
[InitializeOnLoad]public static class BomAuthoringIdentity {
 public const ulong ReservedSourceStart=0xffffffffffffff00UL;
 static bool queued,assigning;
 static BomAuthoringIdentity(){EditorApplication.hierarchyChanged+=Queue;EditorApplication.projectChanged+=Queue;PrefabUtility.prefabInstanceUpdated+=_=>Queue();}
 static void Queue(){if(queued||assigning||EditorApplication.isPlayingOrWillChangePlaymode)return;queued=true;EditorApplication.delayCall+=RunQueued;}
 static void RunQueued(){queued=false;if(EditorApplication.isPlayingOrWillChangePlaymode)return;try{for(int i=0;i<SceneManager.sceneCount;i++){var scene=SceneManager.GetSceneAt(i);if(!scene.isLoaded||!scene.path.EndsWith(".unity",StringComparison.OrdinalIgnoreCase))continue;foreach(var root in scene.GetRootGameObjects())foreach(var level in root.GetComponentsInChildren<BomLevelAuthoring>(true))Assign(level);}}catch(Exception error){Debug.LogError("BOM identity assignment: "+error.Message);}}
 public static ulong Parse(string text)=>ulong.TryParse(text,NumberStyles.None,CultureInfo.InvariantCulture,out var value)?value:0;
 static string Key(UnityEngine.Object value)=>GlobalObjectId.GetGlobalObjectIdSlow(value).ToString();
 static ulong Allocate(HashSet<ulong> used,ref ulong next){if(next==0)next=1;while(next<ReservedSourceStart&&used.Contains(next))next++;if(next>=ReservedSourceStart)throw new InvalidOperationException("The authoring identity allocator is exhausted");ulong id=next++;used.Add(id);return id;}
 static void Dirty(Component value){EditorUtility.SetDirty(value);if(PrefabUtility.IsPartOfPrefabInstance(value))PrefabUtility.RecordPrefabInstancePropertyModifications(value);EditorSceneManager.MarkSceneDirty(value.gameObject.scene);}
 public static void Assign(BomLevelAuthoring level){
  if(assigning||EditorApplication.isPlayingOrWillChangePlaymode)return;
  var scene=level.gameObject.scene;if(!scene.IsValid()||string.IsNullOrEmpty(scene.path)||!scene.path.EndsWith(".unity",StringComparison.OrdinalIgnoreCase))return;
  assigning=true;try{
   string sceneGuid=AssetDatabase.AssetPathToGUID(scene.path),rootId=Key(level);
   if(string.IsNullOrEmpty(sceneGuid))return;
   Undo.RecordObject(level,"Assign BOM identities");bool changed=false;
   bool copied=(!string.IsNullOrEmpty(level.StoredSceneGuid)&&level.StoredSceneGuid!=sceneGuid)||(!string.IsNullOrEmpty(level.StoredRootGlobalId)&&level.StoredRootGlobalId!=rootId);
   if(copied){level.LevelId=Guid.NewGuid().ToString("N");level.IdentityRegistry.Clear();changed=true;}
   if(string.IsNullOrEmpty(level.LevelId)){level.LevelId=Guid.NewGuid().ToString("N");changed=true;}
   if(level.StoredSceneGuid!=sceneGuid||level.StoredRootGlobalId!=rootId)changed=true;
   level.StoredSceneGuid=sceneGuid;level.StoredRootGlobalId=rootId;
   var records=new Dictionary<string,BomIdentityRecord>();var owners=new Dictionary<ulong,string>();var used=new HashSet<ulong>();ulong next=Parse(level.NextIdentityDecimal);if(next==0)next=1;
   foreach(var record in level.IdentityRegistry){ulong id=Parse(record.IdentityDecimal);if(id==0||id>=ReservedSourceStart)continue;records[record.ObjectGlobalId]=record;used.Add(id);if(!owners.ContainsKey(id))owners[id]=record.ObjectGlobalId;if(id>=next)next=id+1;}
   foreach(var instance in level.GetComponentsInChildren<BomAssetInstance>(true)){
    if(PrefabUtility.IsPartOfPrefabAsset(instance))continue;
    string key=Key(instance);ulong id=instance.Identity;bool duplicate=false;
    if(records.TryGetValue(key,out var record))id=Parse(record.IdentityDecimal);
    else{
     if(id==0||id>=ReservedSourceStart||owners.TryGetValue(id,out var owner)&&owner!=key){id=Allocate(used,ref next);duplicate=true;}else{used.Add(id);if(id>=next)next=id+1;}
     record=new BomIdentityRecord{ObjectGlobalId=key,IdentityDecimal=id.ToString(CultureInfo.InvariantCulture)};level.IdentityRegistry.Add(record);records[key]=record;owners[id]=key;
     changed=true;
     if(instance.PartIdentityRegistry.Count>0){Undo.RecordObject(instance,"Copy BOM source namespace");instance.PartIdentityRegistry.Clear();Dirty(instance);}
    }
    if(instance.Identity!=id){Undo.RecordObject(instance,"Assign BOM source identity");instance.SetEditorIdentity(id);if(duplicate)instance.PartIdentityRegistry.Clear();Dirty(instance);}
    AssignParts(instance);
   }
   string ceiling=next.ToString(CultureInfo.InvariantCulture);if(level.NextIdentityDecimal!=ceiling){level.NextIdentityDecimal=ceiling;changed=true;}if(changed)Dirty(level);
  }finally{assigning=false;}
 }
 static void AssignParts(BomAssetInstance instance){
  Undo.RecordObject(instance,"Assign BOM part identities");bool changed=false;
  var records=new Dictionary<string,BomIdentityRecord>();var owners=new Dictionary<ulong,string>();var used=new HashSet<ulong>();ulong next=Parse(instance.NextPartIdDecimal);if(next==0)next=1;
  foreach(var record in instance.PartIdentityRegistry){ulong id=Parse(record.IdentityDecimal);if(id==0||id>=ReservedSourceStart)continue;records[record.ObjectGlobalId]=record;used.Add(id);if(!owners.ContainsKey(id))owners[id]=record.ObjectGlobalId;if(id>=next)next=id+1;}
  foreach(var part in instance.GetComponentsInChildren<BomPhysicsPart>(true)){
   if(part.GetComponentInParent<BomAssetInstance>(true)!=instance)continue;
   string key=Key(part);ulong id=part.PartId;
   if(records.TryGetValue(key,out var record))id=Parse(record.IdentityDecimal);
   else{
    if(id==0||id>=ReservedSourceStart||owners.TryGetValue(id,out var owner)&&owner!=key)id=Allocate(used,ref next);else{used.Add(id);if(id>=next)next=id+1;}
    record=new BomIdentityRecord{ObjectGlobalId=key,IdentityDecimal=id.ToString(CultureInfo.InvariantCulture)};instance.PartIdentityRegistry.Add(record);records[key]=record;owners[id]=key;
    changed=true;
   }
   if(part.PartId!=id){Undo.RecordObject(part,"Assign BOM part identity");part.PartIdDecimal=id.ToString(CultureInfo.InvariantCulture);Dirty(part);}
  }
  string ceiling=next.ToString(CultureInfo.InvariantCulture);if(instance.NextPartIdDecimal!=ceiling){instance.NextPartIdDecimal=ceiling;changed=true;}if(changed)Dirty(instance);
 }
 public static void NormalizeTemplate(GameObject root){bool changed=false;foreach(var instance in root.GetComponentsInChildren<BomAssetInstance>(true))if(instance.Identity!=0||instance.PartIdentityRegistry.Count!=0){instance.SetEditorIdentity(0);instance.PartIdentityRegistry.Clear();EditorUtility.SetDirty(instance);changed=true;}if(changed)PrefabUtility.SavePrefabAsset(root);}
}

public sealed class BomAuthoringPrefabImport:AssetPostprocessor {
 static readonly HashSet<string> Pending=new HashSet<string>();static bool queued;
 static void OnPostprocessAllAssets(string[] imported,string[] deleted,string[] moved,string[] movedFrom){foreach(string path in imported)if(path.StartsWith("Assets/BOMIntegration/",StringComparison.Ordinal)&&path.EndsWith(".prefab",StringComparison.OrdinalIgnoreCase))Pending.Add(path);if(Pending.Count>0&&!queued){queued=true;EditorApplication.delayCall+=Normalize;}}
 static void Normalize(){queued=false;if(EditorApplication.isPlayingOrWillChangePlaymode){Pending.Clear();return;}var paths=new List<string>(Pending);Pending.Clear();foreach(string path in paths){var root=AssetDatabase.LoadAssetAtPath<GameObject>(path);if(root!=null)BomAuthoringIdentity.NormalizeTemplate(root);}}
}
