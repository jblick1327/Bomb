using System;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace Bom.Unity {
// Run before connecting and before instantiating each authored presentation prefab.
// Include inactive descendants: hiding a legacy controller must not authorize it.
public static class BomAuthorityAudit {
 public static void Validate(GameObject root){
  if(root==null)return;
  foreach(var component in root.GetComponentsInChildren<Component>(true)){
   if(component==null)throw new InvalidOperationException("Missing script in native presentation: "+root.name);
   if(component is Collider||component is Collider2D||component is Rigidbody||component is Rigidbody2D||component is CharacterController||component is Joint||component is Joint2D)
    throw new InvalidOperationException("Unity gameplay physics component in native presentation: "+component.GetType().Name+" on "+component.name);
   if(component is Animator animator&&animator.applyRootMotion)throw new InvalidOperationException("Animator root motion in native presentation: "+component.name);
   if(component is MonoBehaviour script&&script.GetType().Assembly.GetName().Name=="Assembly-CSharp"){
    var adapter=script.GetComponent<BomLegacyBlastView>();
    if(script.GetType().FullName!="BombBlastVisual"||script.enabled||adapter==null||adapter.Animation!=script)
     throw new InvalidOperationException("Unaudited legacy script in native presentation: "+script.GetType().FullName+" on "+component.name);
   }
  }
 }
 public static void ValidateScene(){
  for(int i=0;i<SceneManager.sceneCount;i++){var scene=SceneManager.GetSceneAt(i);if(scene.isLoaded)foreach(var root in scene.GetRootGameObjects())Validate(root);}
 }
}
}
