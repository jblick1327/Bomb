using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
public static class BomYardInventory {
 [Serializable]sealed class Row{public string path,mesh,component_data;public Vector3 position,euler,scale,render_min,render_max,collider_min,collider_max;public bool renderer,collider,trigger;}
 [Serializable]sealed class Report{public Row[] objects;}
 static string PathOf(Transform value)=>value.parent==null?value.name:PathOf(value.parent)+"/"+value.name;
 public static void Run(){
  var scene=EditorSceneManager.OpenScene("Assets/Game/Scenes/YardLevel.unity",OpenSceneMode.Single);var rows=new List<Row>();
  foreach(var root in scene.GetRootGameObjects())foreach(var transform in root.GetComponentsInChildren<Transform>(true)){
   var row=new Row{path=PathOf(transform),position=transform.position,euler=transform.eulerAngles,scale=transform.lossyScale};
   var renderer=transform.GetComponent<Renderer>();if(renderer!=null){row.renderer=true;row.render_min=renderer.bounds.min;row.render_max=renderer.bounds.max;}
   var collider=transform.GetComponent<Collider>();if(collider!=null){row.collider=true;row.trigger=collider.isTrigger;row.collider_min=collider.bounds.min;row.collider_max=collider.bounds.max;}
   var filter=transform.GetComponent<MeshFilter>();if(filter!=null)row.mesh=filter.sharedMesh==null?"missing":AssetDatabase.GetAssetPath(filter.sharedMesh)+"#"+filter.sharedMesh.name;
   foreach(var behaviour in transform.GetComponents<MonoBehaviour>())if(behaviour!=null&&behaviour.GetType().Assembly.GetName().Name=="Assembly-CSharp")row.component_data+=behaviour.GetType().Name+":"+JsonUtility.ToJson(behaviour)+"\n";
   rows.Add(row);
  }
  string output=Environment.GetEnvironmentVariable("BOM_YARD_INVENTORY_OUT");if(string.IsNullOrEmpty(output))throw new InvalidOperationException("Set BOM_YARD_INVENTORY_OUT");File.WriteAllText(output,JsonUtility.ToJson(new Report{objects=rows.ToArray()},true));Debug.Log("BOM YARD INVENTORY objects="+rows.Count);
 }
}
