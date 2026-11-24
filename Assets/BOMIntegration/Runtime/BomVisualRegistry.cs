using System;
using UnityEngine;

namespace Bom.Unity
{
    [Serializable]
    public sealed class BomVisualMeshGroup
    {
        public Mesh Mesh;
        public Material[] SurfaceMaterials = Array.Empty<Material>();
        public Matrix4x4 MeshToGroup = Matrix4x4.identity;
    }

    [Serializable]
    public sealed class BomVisualEntry
    {
        public string AssetKey = "",
            ContentHash = "";
        public int BuilderVersion = 1;
        public BomVisualMeshGroup[] Groups = Array.Empty<BomVisualMeshGroup>();
        public Material CapMaterial;
        public Vector2 FallbackDepth;
        public GameObject IntactPrefab;

        // C6: an invisible boundary (Darryn's Left/Right Wall have no renderer). Native still collides with it; Unity
        // draws nothing for it, which is the original look, instead of falling back to a visible extrusion.
        public bool Hidden;
    }

    [Serializable]
    public sealed class BomInitialSourceRegion
    {
        public string SourceIdentity = "";
        public string[] InitialCellIds = Array.Empty<string>();
    }

    [CreateAssetMenu(menuName = "BOM/Visual Registry")]
    public sealed class BomVisualRegistry : ScriptableObject
    {
        public string LevelId = "",
            GameplayManifestHash = "",
            CatalogHash = "";
        public BomVisualEntry[] Entries = Array.Empty<BomVisualEntry>();
        public BomInitialSourceRegion[] InitialSources = Array.Empty<BomInitialSourceRegion>();

        public bool TryFind(string key, string hash, out BomVisualEntry result)
        {
            foreach (var entry in Entries)
                if (entry.AssetKey == key && entry.ContentHash == hash && (entry.Groups.Length > 0 || entry.Hidden))
                {
                    bool valid = true;
                    foreach (var group in entry.Groups)
                        if (group.Mesh == null)
                            valid = false;
                    if (valid)
                    {
                        result = entry;
                        return true;
                    }
                }
            result = null;
            return false;
        }
    }
}
