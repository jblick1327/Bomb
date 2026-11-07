using System;
using System.IO;
using System.Security.Cryptography;
using Unity.Collections;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

// Reads source mesh data through the Editor API without changing import settings.
public static class BomMeshPreprocessor {
 public const int BuilderVersion=1;
 static bool Finite(float x)=>!float.IsNaN(x)&&!float.IsInfinity(x);
 public static Mesh Bake(Mesh original,Matrix4x4 meshToGroup,string objectPath){
  if(original==null)throw new InvalidOperationException(objectPath+": missing mesh; author an explicit proxy and use extrusion");
  for(int i=0;i<16;i++)if(!Finite(meshToGroup[i]))throw new InvalidOperationException(objectPath+": nonfinite visual transform");
  float determinant=meshToGroup.determinant;
  if(Mathf.Abs(determinant)<1e-8f||!Finite(determinant))throw new InvalidOperationException(objectPath+": singular transform; bake a nonzero scale");
  if(Mathf.Abs(meshToGroup.m30)>1e-6f||Mathf.Abs(meshToGroup.m31)>1e-6f||Mathf.Abs(meshToGroup.m32)>1e-6f||Mathf.Abs(meshToGroup.m33-1)>1e-6f)throw new InvalidOperationException(objectPath+": perspective transforms are unsupported");
  using(var dataArray=MeshUtility.AcquireReadOnlyMeshData(original)){
   var data=dataArray[0];int count=data.vertexCount;
   if(count==0||count>1000000)throw new InvalidOperationException(objectPath+": visual vertex count exceeds preprocessing bounds");
   using(var positions=new NativeArray<Vector3>(count,Allocator.Temp)){
    data.GetVertices(positions);var vertices=positions.ToArray();
    for(int i=0;i<count;i++){vertices[i]=meshToGroup.MultiplyPoint3x4(vertices[i]);if(!Finite(vertices[i].x)||!Finite(vertices[i].y)||!Finite(vertices[i].z))throw new InvalidOperationException(objectPath+": nonfinite mesh vertex");}
    var output=new Mesh{name=original.name+" BOM derived",indexFormat=count>65535?IndexFormat.UInt32:IndexFormat.UInt16};
    try{
     output.vertices=vertices;
     if(data.HasVertexAttribute(VertexAttribute.Normal))using(var normals=new NativeArray<Vector3>(count,Allocator.Temp)){
      data.GetNormals(normals);var transformed=normals.ToArray();var normalMatrix=meshToGroup.inverse.transpose;
      for(int i=0;i<count;i++)transformed[i]=normalMatrix.MultiplyVector(transformed[i]).normalized;output.normals=transformed;
     }
     if(data.HasVertexAttribute(VertexAttribute.Tangent))using(var tangents=new NativeArray<Vector4>(count,Allocator.Temp)){
      data.GetTangents(tangents);var transformed=tangents.ToArray();
      for(int i=0;i<count;i++){var t=transformed[i];Vector3 direction=meshToGroup.MultiplyVector(new Vector3(t.x,t.y,t.z)).normalized;transformed[i]=new Vector4(direction.x,direction.y,direction.z,t.w*(determinant<0?-1:1));}output.tangents=transformed;
     }
     if(data.HasVertexAttribute(VertexAttribute.TexCoord0))using(var uv=new NativeArray<Vector2>(count,Allocator.Temp)){data.GetUVs(0,uv);output.uv=uv.ToArray();}
     if(data.HasVertexAttribute(VertexAttribute.Color))using(var colors=new NativeArray<Color>(count,Allocator.Temp)){data.GetColors(colors);output.colors=colors.ToArray();}
     output.subMeshCount=data.subMeshCount;long totalIndices=0;
     for(int sub=0;sub<data.subMeshCount;sub++){
      var descriptor=data.GetSubMesh(sub);totalIndices+=descriptor.indexCount;
      if(descriptor.topology!=MeshTopology.Triangles||descriptor.indexCount%3!=0||totalIndices>6000000)throw new InvalidOperationException(objectPath+": only bounded triangle submeshes support source clipping");
      using(var indices=new NativeArray<int>(descriptor.indexCount,Allocator.Temp)){
       data.GetIndices(indices,sub,true);var triangles=indices.ToArray();
       foreach(int index in triangles)if(index<0||index>=count)throw new InvalidOperationException(objectPath+": invalid triangle index");
       if(determinant<0)for(int i=0;i<triangles.Length;i+=3){int swap=triangles[i+1];triangles[i+1]=triangles[i+2];triangles[i+2]=swap;}
       output.SetTriangles(triangles,sub,false);
      }
     }
     if(!data.HasVertexAttribute(VertexAttribute.Normal))output.RecalculateNormals();
     output.RecalculateBounds();return output;
    }catch{UnityEngine.Object.DestroyImmediate(output);throw;}
   }
  }
 }
 public static string ContentHash(Mesh mesh,Material[] materials){
  using(var bytes=new MemoryStream())using(var writer=new BinaryWriter(bytes)){
   writer.Write(BuilderVersion);writer.Write(mesh.vertexCount);
   foreach(var p in mesh.vertices){writer.Write(p.x);writer.Write(p.y);writer.Write(p.z);}
   var normals=mesh.normals;writer.Write(normals.Length);foreach(var p in normals){writer.Write(p.x);writer.Write(p.y);writer.Write(p.z);}
   var tangents=mesh.tangents;writer.Write(tangents.Length);foreach(var p in tangents){writer.Write(p.x);writer.Write(p.y);writer.Write(p.z);writer.Write(p.w);}
   var uv=mesh.uv;writer.Write(uv.Length);foreach(var p in uv){writer.Write(p.x);writer.Write(p.y);}
   var colors=mesh.colors;writer.Write(colors.Length);foreach(var p in colors){writer.Write(p.r);writer.Write(p.g);writer.Write(p.b);writer.Write(p.a);}
   writer.Write(mesh.subMeshCount);for(int sub=0;sub<mesh.subMeshCount;sub++){var indices=mesh.GetIndices(sub);writer.Write(indices.Length);foreach(int index in indices)writer.Write(index);}
   writer.Write(materials.Length);foreach(var material in materials){string path=AssetDatabase.GetAssetPath(material);writer.Write(path);writer.Write(string.IsNullOrEmpty(path)?"missing":AssetDatabase.GetAssetDependencyHash(path).ToString());}
   writer.Flush();using(var hash=SHA256.Create())return BitConverter.ToString(hash.ComputeHash(bytes.ToArray())).Replace("-","").ToLowerInvariant();
  }
 }
}
