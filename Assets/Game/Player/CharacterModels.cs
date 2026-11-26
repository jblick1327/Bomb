using System.Collections.Generic;
using UnityEngine;

public enum CharacterModel : byte
{
    Original,
    Daryn,
    NoNeckNelson
}

internal static class CharacterModels
{
    private static readonly string[] Names = { "A", "B", "C" };
    private static readonly string[] ModelPaths = { null, "CharacterModels/ClaymateD", "CharacterModels/ClaymateNoNeck" };
    private static readonly Variant[] variants = new Variant[Names.Length];

    private sealed class Variant
    {
        public GameObject Prefab;
        public AnimationClip Idle;
        public AnimationClip Run;
    }

    public static CharacterModel FromIndex(int index) =>
        index >= 0 && index < Names.Length ? (CharacterModel)index : CharacterModel.Original;

    public static CharacterModel Next(CharacterModel model) =>
        FromIndex(((int)model + 1) % Names.Length);

    public static string Name(CharacterModel model) => Names[(int)model];

    private static Variant Load(CharacterModel model)
    {
        int index = (int)model;
        if (variants[index] != null) return variants[index];

        string path = ModelPaths[index];
        var variant = new Variant { Prefab = Resources.Load<GameObject>(path) };
        foreach (AnimationClip clip in Resources.LoadAll<AnimationClip>(path))
        {
            if (clip.name == "Idle") variant.Idle = clip;
            if (clip.name == "Run") variant.Run = clip;
        }

        variants[index] = variant;
        return variant;
    }

    private static readonly Texture2D[] portraits = new Texture2D[Names.Length];

    public static Texture2D Portrait(CharacterModel model)
    {
        int index = (int)model;
        if (portraits[index] == null)
            portraits[index] = Resources.Load<Texture2D>("CharacterModels/" + Names[index]);
        return portraits[index];
    }

    public static Animator CreateVisual(CharacterModel model, Animator original, out AnimatorOverrideController controller)
    {
        controller = null;
        if (model == CharacterModel.Original || original == null || original.runtimeAnimatorController == null)
            return original;

        Variant variant = Load(model);
        if (variant.Prefab == null || variant.Idle == null || variant.Run == null)
        {
            Debug.LogWarning($"Missing model or animation clips for {Name(model)}.", original);
            return original;
        }

        Transform source = original.transform;
        GameObject visual = Object.Instantiate(variant.Prefab, source.parent, false);
        visual.transform.SetLocalPositionAndRotation(source.localPosition, source.localRotation);
        visual.transform.localScale = source.localScale;
        foreach (SkinnedMeshRenderer skin in visual.GetComponentsInChildren<SkinnedMeshRenderer>(true))
        {
            skin.enabled = true;
            skin.updateWhenOffscreen = true;
        }

        controller = new AnimatorOverrideController(original.runtimeAnimatorController);
        var overrides = new List<KeyValuePair<AnimationClip, AnimationClip>>(controller.overridesCount);
        controller.GetOverrides(overrides);
        for (int i = 0; i < overrides.Count; i++)
        {
            AnimationClip clip = overrides[i].Key;
            if (clip == null) continue;
            AnimationClip replacement = clip.name.Contains("Idle") ? variant.Idle : variant.Run;
            overrides[i] = new KeyValuePair<AnimationClip, AnimationClip>(clip, replacement);
        }
        controller.ApplyOverrides(overrides);

        if (!visual.TryGetComponent(out Animator animator)) animator = visual.AddComponent<Animator>();
        animator.runtimeAnimatorController = controller;
        animator.applyRootMotion = false;
        animator.cullingMode = AnimatorCullingMode.AlwaysAnimate;
        animator.updateMode = original.updateMode;
        original.gameObject.SetActive(false);
        return animator;
    }

    // Fit the idle pose to the physical capsule once, before the first round.
    // Keep the correction above the Animator so re-binding after a reset preserves it.
    public static void FitToCapsule(Animator body, CharacterController capsule)
    {
        if (body == null || body.runtimeAnimatorController == null) return;
        Transform visual = body.transform;
        var mount = new GameObject("Character appearance").transform;
        mount.SetParent(capsule.transform, false);
        visual.SetParent(mount, true);
        foreach (AnimationClip clip in body.runtimeAnimatorController.animationClips)
        {
            if (clip.name != "Idle" && clip.name != "Rob|Idle") continue;
            clip.SampleAnimation(body.gameObject, 0f);
            break;
        }
        if (!TryGetSkinnedBounds(body.gameObject, capsule.transform, out Bounds bounds) || bounds.size.y < .001f) return;
        float scale = capsule.height / bounds.size.y;
        Vector3 feet = new Vector3(bounds.center.x, bounds.min.y, bounds.center.z);
        mount.localScale = Vector3.one * scale;
        mount.localPosition = capsule.center - Vector3.up * (capsule.height * .5f) - feet * scale;
    }

    public static bool TryGetSkinnedBounds(GameObject model, Transform space, out Bounds bounds)
    {
        bounds = default;
        bool hasBounds = false;
        Matrix4x4 worldToSpace = space != null ? space.worldToLocalMatrix : Matrix4x4.identity;
        foreach (SkinnedMeshRenderer skin in model.GetComponentsInChildren<SkinnedMeshRenderer>(true))
        {
            // ArenaSession also configures players whose GameObject is inactive.
            // Measure from the sampled bones before a renderer or camera has updated.
            Mesh mesh = skin.sharedMesh;
            if (mesh == null || !mesh.isReadable) continue;
            Transform[] bones = skin.bones;
            Matrix4x4[] bind = mesh.bindposes;
            Vector3[] vertices = mesh.vertices;
            BoneWeight[] weights = mesh.boneWeights;
            if (bones.Length != bind.Length || weights.Length != vertices.Length) continue;
            for (int i = 0; i < bones.Length; i++)
                if (bones[i] != null) bind[i] = worldToSpace * bones[i].localToWorldMatrix * bind[i];

            for (int i = 0; i < vertices.Length; i++)
            {
                BoneWeight w = weights[i];
                if (w.weight0 <= 0f) continue;
                Vector3 v = vertices[i];
                Vector3 point = bind[w.boneIndex0].MultiplyPoint3x4(v) * w.weight0;
                if (w.weight1 > 0f) point += bind[w.boneIndex1].MultiplyPoint3x4(v) * w.weight1;
                if (w.weight2 > 0f) point += bind[w.boneIndex2].MultiplyPoint3x4(v) * w.weight2;
                if (w.weight3 > 0f) point += bind[w.boneIndex3].MultiplyPoint3x4(v) * w.weight3;
                if (hasBounds) bounds.Encapsulate(point);
                else
                {
                    bounds = new Bounds(point, Vector3.zero);
                    hasBounds = true;
                }
            }
        }
        return hasBounds;
    }
}
