using System;
using UnityEngine;
namespace Bom.Unity {
[Serializable]public sealed class BomVisualMeshGroup {
 public Mesh Mesh;
 public Material[] SurfaceMaterials=Array.Empty<Material>();
 public Matrix4x4 MeshToGroup=Matrix4x4.identity;
}
[Serializable]public sealed class BomVisualEntry {
 public string AssetKey="",ContentHash="";
 public int BuilderVersion=1;
 public BomVisualMeshGroup[] Groups=Array.Empty<BomVisualMeshGroup>();
 public Material CapMaterial;
 public Vector2 FallbackDepth;
 public GameObject IntactPrefab;
}
[CreateAssetMenu(menuName="BOM/Visual Registry")]
public sealed class BomVisualRegistry:ScriptableObject {
 public string LevelId="",GameplayManifestHash="",CatalogHash="";
 public BomVisualEntry[] Entries=Array.Empty<BomVisualEntry>();
 public bool TryFind(string key,string hash,out BomVisualEntry result){foreach(var entry in Entries)if(entry.AssetKey==key&&entry.ContentHash==hash){result=entry;return true;}result=null;return false;}
}
}
