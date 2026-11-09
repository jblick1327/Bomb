using System;
using System.IO;
using Bom.Unity;
using UnityEngine;
using UnityEditor;
public static class BomCaptureCutFixtures {
 [Serializable]sealed class Input{public string asset,reason,source;public ulong cell;public Vector2[] outline;public float[] matrix;}
 [Serializable]sealed class Output{public string asset,source,original_failure,current_result;public ulong cell;public Vector2[] outline;public Vector3[] vertices;public int[] material_slots;public int materials;public float epsilon;}
 public static void Run(){
  string input=Environment.GetEnvironmentVariable("BOM_CUT_FIXTURE_INPUT"),output=Environment.GetEnvironmentVariable("BOM_CUT_FIXTURE_OUTPUT");Directory.CreateDirectory(output);var registry=AssetDatabase.LoadAssetAtPath<BomVisualRegistry>("Assets/BOMIntegration/Levels/bomb-yard-network-v1/VisualRegistry.asset");if(registry==null)throw new InvalidOperationException("Missing yard registry");var fallback=AssetDatabase.LoadAssetAtPath<Material>("Assets/BOMIntegration/NativeFallback.mat");
  foreach(string file in Directory.GetFiles(input,"*.json")){var row=JsonUtility.FromJson<Input>(File.ReadAllText(file));BomVisualEntry entry=null;foreach(var candidate in registry.Entries)if(candidate.AssetKey==row.asset){entry=candidate;break;}if(entry==null)throw new InvalidOperationException("Missing entry "+row.asset);var matrix=new Matrix4x4();for(int i=0;i<16;i++)matrix[i]=row.matrix[i];var arrays=BomSourceMeshData.Read(entry,matrix,fallback,64L*1024*1024);if(arrays.Failure!=null)throw new InvalidOperationException(arrays.Failure);var source=BomPrismClipper.Prepare(arrays.Triangles,arrays.Materials.Length-1);var cut=BomPrismClipper.Build(source,row.outline);var vertices=new Vector3[arrays.Triangles.Length*3];var slots=new int[arrays.Triangles.Length];for(int i=0;i<arrays.Triangles.Length;i++){vertices[i*3]=arrays.Triangles[i].A.Position;vertices[i*3+1]=arrays.Triangles[i].B.Position;vertices[i*3+2]=arrays.Triangles[i].C.Position;slots[i]=arrays.Triangles[i].Material;}File.WriteAllText(Path.Combine(output,Path.GetFileName(file)),JsonUtility.ToJson(new Output{asset=row.asset,source=row.source,cell=row.cell,original_failure=row.reason,current_result=cut.Reason,outline=row.outline,vertices=vertices,material_slots=slots,materials=arrays.Materials.Length-1,epsilon=source.Epsilon},true));Debug.Log("BOM CAPTURED CUT "+Path.GetFileName(file)+" "+cut.Reason);}
 }
}
