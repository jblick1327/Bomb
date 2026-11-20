using System;
using System.Collections.Generic;
using System.Globalization;
using UnityEngine;

namespace Bom.Unity
{
    public enum BomMotionPolicy
    {
        Dynamic,
        Fixed,
        Anchored,
    }

    public enum BomDamagePolicy
    {
        Destructible,
        Indestructible,
    }

    [DisallowMultipleComponent]
    public sealed class BomAssetInstance : MonoBehaviour
    {
        [SerializeField]
        string identityDecimal = "0";
        public string NextPartIdDecimal = "1";

        [HideInInspector]
        public List<BomIdentityRecord> PartIdentityRegistry = new List<BomIdentityRecord>();
        public string AssetKey = "";
        public Transform VisualGroup;
        public BomMotionPolicy Motion = BomMotionPolicy.Anchored;
        public BomDamagePolicy Damage = BomDamagePolicy.Destructible;
        public Vector2 FallbackDepth = new Vector2(-.3f, .3f);
        public Material CapMaterial;
        public string OriginalObjectPath = "";

        [TextArea]
        public string ApproximationNote = "";
        public bool IncludeInExport = true;

        // C6: export this source as a hidden registry entry (no mesh, nothing drawn), e.g. invisible boundary walls.
        public bool HiddenVisual;
        public ulong Identity =>
            ulong.TryParse(
                identityDecimal,
                NumberStyles.None,
                CultureInfo.InvariantCulture,
                out var id
            )
                ? id
                : 0;
        public string IdentityText => identityDecimal;

        public void SetEditorIdentity(ulong id)
        {
            identityDecimal = id.ToString(CultureInfo.InvariantCulture);
        }

        public Transform Group => VisualGroup != null ? VisualGroup : transform;
    }
}
