using Bom.Native;
using UnityEngine;
namespace Bom.Unity {
// Read-only pose presentation. No movement, collision or damage simulation.
public sealed class BomActorView : MonoBehaviour {
 public Transform AuthoredVisual;
 public bool Running=>animator!=null&&animator.GetBool("Running");
 Animator animator;bool hasPosition;Vector2 previous;double previousTime;
 public BomPose Pose {get;private set;}
 public Vector3 VisualPosition=>visual!=null?visual.position:transform.position;
 Transform visual;MeshRenderer sourceRenderer,visualRenderer;int materialCount;MaterialPropertyBlock properties;
 void EnsureVisual(){
  if(visual!=null)return;
  if(AuthoredVisual!=null){visual=AuthoredVisual;sourceRenderer=GetComponent<MeshRenderer>();if(sourceRenderer!=null)sourceRenderer.enabled=false;animator=visual.GetComponentInChildren<Animator>();if(animator!=null){animator.applyRootMotion=false;animator.updateMode=AnimatorUpdateMode.UnscaledTime;}return;}
  var source=GetComponent<MeshFilter>();sourceRenderer=GetComponent<MeshRenderer>();if(source==null||sourceRenderer==null)return;
  properties=new MaterialPropertyBlock();
  var child=new GameObject("Native visual");visual=child.transform;visual.SetParent(transform,false);child.AddComponent<MeshFilter>().sharedMesh=source.sharedMesh;
  visualRenderer=child.AddComponent<MeshRenderer>();var materials=sourceRenderer.sharedMaterials;materialCount=materials.Length;visualRenderer.sharedMaterials=materials;visualRenderer.shadowCastingMode=sourceRenderer.shadowCastingMode;visualRenderer.receiveShadows=sourceRenderer.receiveShadows;sourceRenderer.enabled=false;
 }
 public void Apply(BomPose pose,Vector2 visualOffset=default){
  Pose=pose;EnsureVisual();var rotation=BomUnityCoordinates.Rotation(pose.angle);
  transform.SetPositionAndRotation(new Vector3(pose.x-visualOffset.x,pose.y-visualOffset.y,transform.position.z),rotation);
  if(visual!=null){visual.localPosition=Quaternion.Inverse(rotation)*new Vector3(visualOffset.x,visualOffset.y,0);for(int i=0;i<materialCount;i++){sourceRenderer.GetPropertyBlock(properties,i);visualRenderer.SetPropertyBlock(properties,i);}}
  if(AuthoredVisual!=null&&pose.kind==2){
   double now=BomSession.Now;Vector2 position=new Vector2(pose.x,pose.y);float dx=hasPosition?position.x-previous.x:0;
   double dt=now-previousTime;float speed=dt>0&&dt<.5&&Mathf.Abs(dx)<1?Mathf.Abs(dx)/(float)dt:0;
   if(animator!=null)animator.SetBool("Running",speed>.08f);
   if(Mathf.Abs(dx)>.0001f&&Mathf.Abs(dx)<1){Vector3 scale=visual.localScale;scale.x=Mathf.Abs(scale.x)*(dx<0?-1:1);visual.localScale=scale;}
   previous=position;previousTime=now;hasPosition=true;
  }
 }
}
}
