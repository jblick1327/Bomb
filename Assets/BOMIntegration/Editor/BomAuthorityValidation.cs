using System;
using Bom.Unity;
using UnityEditor;
using UnityEngine;

public static class BomAuthorityValidation {
 static void Rejected(GameObject root){try{BomAuthorityAudit.Validate(root);}catch(InvalidOperationException){return;}throw new InvalidOperationException("Authority audit accepted forbidden component");}
 public static void Run(){
  var root=new GameObject("Authority audit fixture");root.SetActive(false);var child=new GameObject("Inactive nested fixture");child.transform.SetParent(root.transform,false);
  try{
   BomAuthorityAudit.Validate(root);
   var collider=child.AddComponent<BoxCollider>();collider.enabled=false;Rejected(root);UnityEngine.Object.DestroyImmediate(collider);
   var collider2D=child.AddComponent<BoxCollider2D>();collider2D.enabled=false;Rejected(root);UnityEngine.Object.DestroyImmediate(collider2D);
   var body=child.AddComponent<Rigidbody>();Rejected(root);UnityEngine.Object.DestroyImmediate(body);
   var body2D=child.AddComponent<Rigidbody2D>();Rejected(root);UnityEngine.Object.DestroyImmediate(body2D);
   var animator=child.AddComponent<Animator>();animator.applyRootMotion=true;Rejected(root);UnityEngine.Object.DestroyImmediate(animator);
   var type=AssetDatabase.LoadAssetAtPath<MonoScript>("Assets/Game/Bombs/BombBlastVisual.cs").GetClass();var legacy=(MonoBehaviour)child.AddComponent(type);legacy.enabled=false;Rejected(root);
   var adapter=child.AddComponent<BomLegacyBlastView>();adapter.Animation=legacy;BomAuthorityAudit.Validate(root);legacy.enabled=true;Rejected(root);
  }finally{UnityEngine.Object.DestroyImmediate(root);}
  foreach(string name in new[]{"NetworkClaymate","NetworkBomb","NetworkBlast"})BomAuthorityAudit.Validate(AssetDatabase.LoadAssetAtPath<GameObject>("Assets/BOMIntegration/"+name+".prefab"));
  Debug.Log("BOM AUTHORITY AUDIT PASS: inactive nested 3D/2D physics, animator and legacy script rejection; exact disabled blast adapter and derived presentation prefabs accepted");
 }
}
