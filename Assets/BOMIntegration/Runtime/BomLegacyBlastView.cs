using System;
using System.Reflection;
using UnityEngine;

namespace Bom.Unity {
// The preserved BombBlastVisual contains only ring animation. Invoke that exact
// component while supplying unscaled presentation time; no BombDropper is used.
public sealed class BomLegacyBlastView:MonoBehaviour {
 public MonoBehaviour Animation;
 MethodInfo update;FieldInfo elapsed;double started;float duration;
 public void Show(Vector3 center,float radius,float lifetime=.35f){
  if(Animation==null||Animation.GetType().FullName!="BombBlastVisual")throw new InvalidOperationException("Only the audited original blast-ring animation is supported");
  var type=Animation.GetType();update=type.GetMethod("Update",BindingFlags.Instance|BindingFlags.NonPublic);elapsed=type.GetField("elapsed",BindingFlags.Instance|BindingFlags.NonPublic);
  var initialize=type.GetMethod("Initialize",new[]{typeof(float),typeof(float)});if(update==null||elapsed==null||initialize==null)throw new InvalidOperationException("Original blast-ring adapter requires a new audit");
  Animation.enabled=false;transform.position=center;duration=lifetime;started=BomSession.Now;initialize.Invoke(Animation,new object[]{radius,lifetime});
 }
 void Update(){if(update==null)return;float age=(float)(BomSession.Now-started);elapsed.SetValue(Animation,age-Time.deltaTime);update.Invoke(Animation,null);if(age>duration+.1f)Destroy(gameObject);}
}
}
