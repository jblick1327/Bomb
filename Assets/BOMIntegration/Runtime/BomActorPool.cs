using System;
using System.Collections.Generic;
using UnityEngine;

namespace Bom.Unity {
// Only render objects are reused. Every lease receives a new native pose; no
// input, collision, event acknowledgement or native identity lives in this pool.
public sealed class BomActorPool:IDisposable {
 const int IdlePerPrefab=32;
 readonly Dictionary<GameObject,Stack<GameObject>> idle=new Dictionary<GameObject,Stack<GameObject>>();
 readonly Dictionary<GameObject,GameObject> owned=new Dictionary<GameObject,GameObject>();
 readonly HashSet<GameObject> leased=new HashSet<GameObject>();
 public int OwnedCount=>owned.Count;
 public int IdleCount{get{int count=0;foreach(var stack in idle.Values)count+=stack.Count;return count;}}
 public GameObject Rent(GameObject prefab){
  if(prefab==null)throw new ArgumentNullException(nameof(prefab));
  if(!idle.TryGetValue(prefab,out var stack)){BomAuthorityAudit.Validate(prefab);stack=new Stack<GameObject>();idle.Add(prefab,stack);}
  GameObject obj;
  if(stack.Count>0)obj=stack.Pop();else{obj=UnityEngine.Object.Instantiate(prefab);BomAuthorityAudit.Validate(obj);owned.Add(obj,prefab);}
  if(!leased.Add(obj))throw new InvalidOperationException("Actor view is already leased");var view=obj.GetComponent<BomActorView>();if(view!=null)view.ResetPresentation();obj.SetActive(true);return obj;
 }
 public bool Return(GameObject obj){
  if(!owned.TryGetValue(obj,out var prefab))return false;
  if(!leased.Remove(obj))throw new InvalidOperationException("Actor view returned twice");
  obj.SetActive(false);var stack=idle[prefab];
  if(stack.Count<IdlePerPrefab)stack.Push(obj);else{owned.Remove(obj);UnityEngine.Object.Destroy(obj);}return true;
 }
 public void Dispose(){foreach(var obj in owned.Keys)if(obj!=null)UnityEngine.Object.Destroy(obj);owned.Clear();leased.Clear();idle.Clear();}
}
}
