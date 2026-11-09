using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using UnityEngine;
using UnityEngine.Rendering;
namespace Bom.Unity {
public sealed class BomSourceArrays {public BomClipTriangle[] Triangles;public Material[] Materials;public string Key,Failure;public long ReservedBytes;}
public static class BomSourceMeshData {
 public static string MatrixKey(string content,Matrix4x4 matrix){using(var stream=new MemoryStream())using(var writer=new BinaryWriter(stream)){writer.Write(BomPrismClipper.BuilderVersion);writer.Write(content);for(int i=0;i<16;i++)writer.Write(matrix[i]);writer.Flush();using(var hash=SHA256.Create())return BitConverter.ToString(hash.ComputeHash(stream.ToArray())).Replace("-","").ToLowerInvariant();}}
 static bool Finite(float value)=>!float.IsNaN(value)&&!float.IsInfinity(value);
 static bool Finite(Vector4 v)=>Finite(v.x)&&Finite(v.y)&&Finite(v.z)&&Finite(v.w);
 public static long Estimate(BomVisualEntry entry){long triangles=0;foreach(var group in entry.Groups){if(group.Mesh==null)return long.MaxValue;for(int i=0;i<group.Mesh.subMeshCount;i++)triangles+=checked((long)group.Mesh.GetIndexCount(i))/3;}return triangles*576*8+65536;}
 public static BomSourceArrays Read(BomVisualEntry entry,Matrix4x4 groupToRest,Material fallback,long bufferLimit){
  var result=new BomSourceArrays{Key=MatrixKey(entry.ContentHash,groupToRest)};
  try{
   if(entry.BuilderVersion!=BomPrismClipper.BuilderVersion)throw new InvalidOperationException("source preprocessing version differs; re-export the level");
   result.ReservedBytes=Estimate(entry);if(result.ReservedBytes>bufferLimit)throw new InvalidOperationException("source preprocessing exceeds the bounded geometry buffer; simplify or split the visual group");
   var materials=new List<Material>();var triangles=new List<BomClipTriangle>();
   foreach(var group in entry.Groups){
    var mesh=group.Mesh;if(mesh==null||!mesh.isReadable)throw new InvalidOperationException("missing or unreadable derived source mesh; re-export without changing the original importer");
    var matrix=groupToRest*group.MeshToGroup;for(int i=0;i<16;i++)if(!Finite(matrix[i]))throw new InvalidOperationException("nonfinite source matrix");float determinant=matrix.determinant;if(!Finite(determinant)||Math.Abs(determinant)<1e-8f)throw new InvalidOperationException("singular source matrix");var normalsMatrix=matrix.inverse.transpose;
    var positions=mesh.vertices;var normals=mesh.normals;var tangents=mesh.tangents;var colors=mesh.colors;var uv=new List<Vector4>[8];for(int channel=0;channel<8;channel++){uv[channel]=new List<Vector4>();if(mesh.HasVertexAttribute((VertexAttribute)((int)VertexAttribute.TexCoord0+channel)))mesh.GetUVs(channel,uv[channel]);}
    var vertices=new BomClipVertex[positions.Length];
    for(int i=0;i<positions.Length;i++){
     var position=matrix.MultiplyPoint3x4(positions[i]);var normal=normals.Length==positions.Length?normalsMatrix.MultiplyVector(normals[i]).normalized:Vector3.zero;if(!Finite(new Vector4(position.x,position.y,position.z,1))||!Finite(new Vector4(normal.x,normal.y,normal.z,1))||normal.sqrMagnitude<.5f)throw new InvalidOperationException("invalid source positions or normals");
     var direction=tangents.Length==positions.Length?matrix.MultiplyVector(new Vector3(tangents[i].x,tangents[i].y,tangents[i].z)).normalized:Vector3.Cross(normal,Math.Abs(normal.y)<.9f?Vector3.up:Vector3.forward).normalized;
     var tangent=new Vector4(direction.x,direction.y,direction.z,(tangents.Length==positions.Length?tangents[i].w:1)*(determinant<0?-1:1));var color=colors.Length==positions.Length?colors[i]:Color.white;if(!Finite(tangent)||!Finite(new Vector4(color.r,color.g,color.b,color.a)))throw new InvalidOperationException("invalid source tangent or color");
     Vector4 UV(int channel){var values=uv[channel];var value=values.Count==positions.Length?values[i]:Vector4.zero;if(!Finite(value))throw new InvalidOperationException("nonfinite source UV channel");return value;}
     vertices[i]=new BomClipVertex{Position=position,Normal=normal,Tangent=tangent,Color=color,UV0=UV(0),UV1=UV(1),UV2=UV(2),UV3=UV(3),UV4=UV(4),UV5=UV(5),UV6=UV(6),UV7=UV(7)};
    }
    for(int sub=0;sub<mesh.subMeshCount;sub++){
     if(mesh.GetTopology(sub)!=MeshTopology.Triangles)throw new InvalidOperationException("nontriangle source submesh");int material=materials.Count;materials.Add(sub<group.SurfaceMaterials.Length&&group.SurfaceMaterials[sub]!=null?group.SurfaceMaterials[sub]:fallback);var indices=mesh.GetIndices(sub);if(indices.Length%3!=0)throw new InvalidOperationException("invalid source triangle count");for(int i=0;i<indices.Length;i+=3){int a=indices[i],b=indices[i+1],c=indices[i+2];if(a<0||a>=vertices.Length||b<0||b>=vertices.Length||c<0||c>=vertices.Length)throw new InvalidOperationException("source triangle index exceeds vertices");triangles.Add(determinant<0?new BomClipTriangle(vertices[a],vertices[c],vertices[b],material):new BomClipTriangle(vertices[a],vertices[b],vertices[c],material));}
    }
   }
   if(triangles.Count==0)throw new InvalidOperationException("empty visual group");result.Triangles=triangles.ToArray();materials.Add(entry.CapMaterial!=null?entry.CapMaterial:fallback);result.Materials=materials.ToArray();
  }catch(InvalidOperationException error){result.Failure=error.Message;}
  return result;
 }
}
public static class BomClipMeshUpload {
 public const int TriangleChunk=4096;
 public static Mesh Upload(IReadOnlyList<BomClipTriangle> triangles,int start,int count,Vector2 origin,int materialCount,string name){
  if(count<1||count>TriangleChunk||start<0||start+count>triangles.Count)throw new ArgumentOutOfRangeException(nameof(count));
  var positions=new List<Vector3>(count*3);var normals=new List<Vector3>(count*3);var tangents=new List<Vector4>(count*3);var colors=new List<Color>(count*3);var uv=new List<Vector4>[8];for(int i=0;i<8;i++)uv[i]=new List<Vector4>(count*3);var indices=new List<int>[materialCount];for(int i=0;i<indices.Length;i++)indices[i]=new List<int>();
  void Vertex(BomClipVertex v){positions.Add(v.Position-new Vector3(origin.x,origin.y,0));var normal=v.Normal.normalized;normals.Add(normal);var direction=new Vector3(v.Tangent.x,v.Tangent.y,v.Tangent.z);direction=(direction-normal*Vector3.Dot(normal,direction)).normalized;if(direction.sqrMagnitude<.5f)direction=Vector3.Cross(normal,Math.Abs(normal.y)<.9f?Vector3.up:Vector3.forward).normalized;tangents.Add(new Vector4(direction.x,direction.y,direction.z,v.Tangent.w<0?-1:1));colors.Add(v.Color);uv[0].Add(v.UV0);uv[1].Add(v.UV1);uv[2].Add(v.UV2);uv[3].Add(v.UV3);uv[4].Add(v.UV4);uv[5].Add(v.UV5);uv[6].Add(v.UV6);uv[7].Add(v.UV7);}
  for(int i=start;i<start+count;i++){var t=triangles[i];if(t.Material<0||t.Material>=materialCount)throw new InvalidOperationException("clipped surface material index exceeds palette");int first=positions.Count;Vertex(t.A);Vertex(t.B);Vertex(t.C);indices[t.Material].Add(first);indices[t.Material].Add(first+1);indices[t.Material].Add(first+2);}
  var mesh=new Mesh{name=name,indexFormat=IndexFormat.UInt16};try{mesh.SetVertices(positions);mesh.SetNormals(normals);mesh.SetTangents(tangents);mesh.SetColors(colors);for(int i=0;i<8;i++)mesh.SetUVs(i,uv[i]);mesh.subMeshCount=materialCount;for(int i=0;i<materialCount;i++)mesh.SetTriangles(indices[i],i,false);mesh.RecalculateBounds();return mesh;}catch{UnityEngine.Object.Destroy(mesh);throw;}
 }
}
}
