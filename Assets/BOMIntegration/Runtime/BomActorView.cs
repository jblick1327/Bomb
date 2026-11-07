using Bom.Native;
using UnityEngine;
namespace Bom.Unity {
// Read-only pose presentation. No movement, collision or damage simulation.
public sealed class BomActorView : MonoBehaviour {
 public BomPose Pose {get;private set;}
 public Vector3 VisualPosition=>visual!=null?visual.position:transform.position;
 Transform visual;MeshRenderer sourceRenderer,visualRenderer;int materialCount;MaterialPropertyBlock properties;
 void EnsureVisual(){
  if(visual!=null)return;var source=GetComponent<MeshFilter>();sourceRenderer=GetComponent<MeshRenderer>();if(source==null||sourceRenderer==null)return;
  properties=new MaterialPropertyBlock();
  var child=new GameObject("Native visual");visual=child.transform;visual.SetParent(transform,false);child.AddComponent<MeshFilter>().sharedMesh=source.sharedMesh;
  visualRenderer=child.AddComponent<MeshRenderer>();var materials=sourceRenderer.sharedMaterials;materialCount=materials.Length;visualRenderer.sharedMaterials=materials;visualRenderer.shadowCastingMode=sourceRenderer.shadowCastingMode;visualRenderer.receiveShadows=sourceRenderer.receiveShadows;sourceRenderer.enabled=false;
 }
 public void Apply(BomPose pose,Vector2 visualOffset=default){
  Pose=pose;EnsureVisual();var rotation=BomUnityCoordinates.Rotation(pose.angle);
  transform.SetPositionAndRotation(new Vector3(pose.x-visualOffset.x,pose.y-visualOffset.y,transform.position.z),rotation);
  if(visual!=null){visual.localPosition=Quaternion.Inverse(rotation)*new Vector3(visualOffset.x,visualOffset.y,0);for(int i=0;i<materialCount;i++){sourceRenderer.GetPropertyBlock(properties,i);visualRenderer.SetPropertyBlock(properties,i);}}
 }
}
}
