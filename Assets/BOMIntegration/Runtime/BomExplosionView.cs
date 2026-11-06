using UnityEngine;
namespace Bom.Unity {
// Presentation aging only. Its lifetime/radius never participates in gameplay.
public sealed class BomExplosionView : MonoBehaviour {
 double ends;LineRenderer line;
 public void Show(Material material,Vector3 center,float radius) {
  line=gameObject.AddComponent<LineRenderer>();line.sharedMaterial=material;line.useWorldSpace=true;line.loop=true;line.widthMultiplier=0.07f;line.positionCount=40;
  for(int i=0;i<40;i++){float a=i*Mathf.PI/20;line.SetPosition(i,center+new Vector3(Mathf.Cos(a),Mathf.Sin(a),0)*radius);}
  var properties=new MaterialPropertyBlock();properties.SetColor("_BaseColor",new Color(1,0.75f,0.1f));line.SetPropertyBlock(properties);ends=BomSession.Now+0.3;
 }
 void Update(){if(BomSession.Now>=ends)Destroy(gameObject);}
}
}
