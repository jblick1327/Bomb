using System;
using System.Globalization;
using UnityEngine;
namespace Bom.Unity {
public enum BomProxyShape { Rectangle,Wedge,Polygon }
[Serializable]public struct BomAnchorSegment {public Vector2 A,B;}
[DisallowMultipleComponent]public sealed class BomPhysicsPart:MonoBehaviour {
 public string PartIdDecimal="1";
 public string MaterialKey="stone";
 public BomProxyShape Shape=BomProxyShape.Rectangle;
 public Vector2 Minimum=new Vector2(-.5f,-.5f),Maximum=new Vector2(.5f,.5f);
 public Vector2[] Outline=Array.Empty<Vector2>();
 public BomAnchorSegment[] Anchors=Array.Empty<BomAnchorSegment>();
 public bool WorldRestCoordinates;
 [TextArea]public string ApproximationNote="";
 public ulong PartId=>ulong.TryParse(PartIdDecimal,NumberStyles.None,CultureInfo.InvariantCulture,out var id)?id:0;
 public Vector2[] LocalOutline(){if(Shape==BomProxyShape.Polygon)return (Vector2[])Outline.Clone();if(Shape==BomProxyShape.Wedge)return new[]{Minimum,new Vector2(Maximum.x,Minimum.y),Maximum};return new[]{Minimum,new Vector2(Maximum.x,Minimum.y),Maximum,new Vector2(Minimum.x,Maximum.y)};}
 public Vector2[] WorldOutline(){var points=LocalOutline();if(!WorldRestCoordinates)for(int i=0;i<points.Length;i++){Vector3 p=transform.TransformPoint(new Vector3(points[i].x,points[i].y,0));points[i]=new Vector2(p.x,p.y);}return points;}
 public BomAnchorSegment[] WorldAnchors(){var anchors=(BomAnchorSegment[])Anchors.Clone();if(!WorldRestCoordinates)for(int i=0;i<anchors.Length;i++){var a=transform.TransformPoint(new Vector3(anchors[i].A.x,anchors[i].A.y,0));var b=transform.TransformPoint(new Vector3(anchors[i].B.x,anchors[i].B.y,0));anchors[i]=new BomAnchorSegment{A=new Vector2(a.x,a.y),B=new Vector2(b.x,b.y)};}return anchors;}
 void OnDrawGizmosSelected(){var points=WorldOutline();Gizmos.color=new Color(.2f,1,.4f,1);for(int i=0;i<points.Length;i++)Gizmos.DrawLine(new Vector3(points[i].x,points[i].y,0),new Vector3(points[(i+1)%points.Length].x,points[(i+1)%points.Length].y,0));Gizmos.color=Color.yellow;foreach(var anchor in WorldAnchors())Gizmos.DrawLine(new Vector3(anchor.A.x,anchor.A.y,0),new Vector3(anchor.B.x,anchor.B.y,0));}
}
}
