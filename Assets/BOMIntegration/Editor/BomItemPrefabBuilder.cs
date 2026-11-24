using System;
using Bom.Native;
using Bom.Unity;
using UnityEditor;
using UnityEngine;

// E1-N4: presentation prefabs for native item actors, made from the item models Darryn's BombDropper uses
// (read from Assets/Game/Bombs/Bomb System.prefab, never edited). Scripts, colliders and rigidbodies are
// stripped from the copy, so Unity physics never runs; the model is normalised to the native item circle.
public static class BomItemPrefabBuilder
{
    public const string Folder = "Assets/BOMIntegration/Resources";
    const string DropperPrefab = "Assets/Game/Bombs/Bomb System.prefab";
    // Index = native item kind (BomPose.flags >> 8): Darryn's CollectibleItemType + 1.
    static readonly string[] Fields =
    {
        null,
        "coinVisualPrefab",
        "starCoinVisualPrefab",
        "shieldVisualPrefab",
        "timeVisualPrefab",
        "speedBoostVisualPrefab",
    };
    // Darryn's BombDropper.itemVisualScale, applied before normalising (keeps the model's own proportions).
    const float DarrynVisualScale = 0.5f;

    public static void Build(BomActorShapeInfo shape)
    {
        if (shape.item_radius <= 0)
            throw new InvalidOperationException("Native item radius is missing (ABI 1.6 required)");
        if (!AssetDatabase.IsValidFolder(Folder))
            AssetDatabase.CreateFolder("Assets/BOMIntegration", "Resources");
        var dropperRoot = AssetDatabase.LoadAssetAtPath<GameObject>(DropperPrefab);
        MonoBehaviour dropper = null;
        if (dropperRoot != null)
            foreach (var script in dropperRoot.GetComponentsInChildren<MonoBehaviour>(true))
                if (script != null && script.GetType().Name == "BombDropper")
                    dropper = script;
        if (dropper == null)
            throw new InvalidOperationException("Darryn's BombDropper is missing from " + DropperPrefab);
        var settings = new SerializedObject(dropper);
        for (uint kind = 1; kind < Fields.Length; kind++)
        {
            var source = settings.FindProperty(Fields[kind])?.objectReferenceValue;
            var model = source as GameObject ?? (source as Component)?.gameObject;
            if (model == null)
                throw new InvalidOperationException("BombDropper." + Fields[kind] + " is not set");
            Item(kind, model, shape.item_radius);
        }
        Debug.Log("BOM ITEM PREFABS built=5 item_radius=" + shape.item_radius);
    }

    static void Item(uint kind, GameObject model, float radius)
    {
        var root = (GameObject)
            PrefabUtility.InstantiatePrefab(
                AssetDatabase.LoadAssetAtPath<GameObject>("Assets/BOMIntegration/NativeBomb.prefab")
            );
        PrefabUtility.UnpackPrefabInstance(root, PrefabUnpackMode.Completely, InteractionMode.AutomatedAction);
        root.name = "Network item " + BomItemLook.KindName(kind);
        root.transform.SetPositionAndRotation(Vector3.zero, Quaternion.identity);
        var visual = new GameObject("Item presentation");
        visual.transform.SetParent(root.transform, false);
        var spin = new GameObject("Spin");
        spin.transform.SetParent(visual.transform, false);
        var art = (GameObject)PrefabUtility.InstantiatePrefab(model);
        PrefabUtility.UnpackPrefabInstance(art, PrefabUnpackMode.Completely, InteractionMode.AutomatedAction);
        foreach (var script in art.GetComponentsInChildren<MonoBehaviour>(true))
            UnityEngine.Object.DestroyImmediate(script);
        foreach (var collider in art.GetComponentsInChildren<Collider>(true))
            UnityEngine.Object.DestroyImmediate(collider);
        foreach (var body in art.GetComponentsInChildren<Rigidbody>(true))
            UnityEngine.Object.DestroyImmediate(body);
        foreach (var animator in art.GetComponentsInChildren<Animator>(true))
            animator.applyRootMotion = false;
        art.transform.SetParent(spin.transform, false);
        art.transform.localPosition = Vector3.zero;
        art.transform.localScale = Vector3.one * DarrynVisualScale;
        bool any = false;
        Bounds bounds = default;
        foreach (var renderer in art.GetComponentsInChildren<Renderer>(true))
        {
            if (!(renderer is MeshRenderer || renderer is SkinnedMeshRenderer))
                continue;
            if (!any)
            {
                bounds = renderer.bounds;
                any = true;
            }
            else
                bounds.Encapsulate(renderer.bounds);
        }
        if (!any || bounds.size.y <= 0)
            throw new InvalidOperationException("Item model " + model.name + " has no usable render bounds");
        // Visual height = native item diameter, centred on the native pose (as Darryn fits his collider to the model).
        float scale = 2 * radius / bounds.size.y;
        art.transform.localScale *= scale;
        art.transform.localPosition = -bounds.center * scale;
        var look = root.AddComponent<BomItemLook>();
        look.Spin = spin.transform;
        root.GetComponent<BomActorView>().AuthoredVisual = visual.transform;
        root.GetComponent<MeshRenderer>().enabled = false;
        BomAuthorityAudit.Validate(root);
        PrefabUtility.SaveAsPrefabAsset(root, Folder + "/BomItem" + kind + ".prefab");
        UnityEngine.Object.DestroyImmediate(root);
    }
}
