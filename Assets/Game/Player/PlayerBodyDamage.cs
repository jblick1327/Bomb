using System.Collections.Generic;
using UnityEngine;

// Knocks pieces off the Claymate. A graze from the edge of a blast removes the
// limb closest to the bomb and throws it out as clay chunks. Too many grazes, or
// a close hit, bursts the whole body into chunks.
[RequireComponent(typeof(ArenaPlayerController))]
[AddComponentMenu("Arena/Player Body Damage")]
public sealed class PlayerBodyDamage : MonoBehaviour
{
    [SerializeField, Min(0), InspectorName("Grazes survived"),
     Tooltip("How many edge-of-blast hits a player survives. The next one bursts them.")]
    private int grazesSurvived = 2;
    [SerializeField, Min(0.02f), InspectorName("Chunk size (units)")]
    private float chunkSize = 0.14f;
    [SerializeField, Range(1, 12), InspectorName("Chunks per lost limb")]
    private int grazeChunks = 4;
    [SerializeField, Range(4, 24), InspectorName("Chunks when burst")]
    private int burstChunks = 12;
    [SerializeField, Min(0f), InspectorName("Chunk impulse")]
    private float chunkImpulse = 2.2f;
    [SerializeField, Range(0f, 2f), InspectorName("Depth spread"),
     Tooltip("How strongly chunks fly toward or away from the camera, relative to the impulse.")]
    private float depthSpread = 0.8f;

    // One limb: its first bone plus every bone below it.
    private sealed class Limb
    {
        public Transform Root;
        public readonly List<Transform> Bones = new List<Transform>();
        public bool Lost;
    }

    private ArenaPlayerController player;
    private SkinnedMeshRenderer[] skins;
    private Mesh[] originalMeshes;
    private Mesh[] damagedMeshes;
    private readonly List<Limb> limbs = new List<Limb>();
    private int grazes;

    private void Awake()
    {
        player = GetComponent<ArenaPlayerController>();
        skins = GetComponentsInChildren<SkinnedMeshRenderer>(true);
        originalMeshes = new Mesh[skins.Length];
        damagedMeshes = new Mesh[skins.Length];
        for (int i = 0; i < skins.Length; i++) originalMeshes[i] = skins[i].sharedMesh;
        FindLimbs();
    }

    // Limbs are bone chains named .L or .R (Blender's left/right convention)
    // that hang off a centre bone. Without such names, each child of the root
    // bone counts as a limb.
    private void FindLimbs()
    {
        var seen = new HashSet<Transform>();
        foreach (SkinnedMeshRenderer skin in skins)
        {
            foreach (Transform bone in skin.bones)
            {
                if (bone == null || !IsSided(bone) || (bone.parent != null && IsSided(bone.parent))) continue;
                if (seen.Add(bone)) limbs.Add(CreateLimb(bone));
            }
        }
        if (limbs.Count > 0) return;
        foreach (SkinnedMeshRenderer skin in skins)
        {
            if (skin.rootBone == null) continue;
            foreach (Transform child in skin.rootBone)
                if (seen.Add(child)) limbs.Add(CreateLimb(child));
        }
    }

    private static bool IsSided(Transform bone) => bone.name.EndsWith(".L") || bone.name.EndsWith(".R")
        || bone.name.EndsWith("_L") || bone.name.EndsWith("_R");

    private static Limb CreateLimb(Transform root)
    {
        var limb = new Limb { Root = root };
        limb.Bones.AddRange(root.GetComponentsInChildren<Transform>(true));
        return limb;
    }

    // Called for a hit from the edge of a blast. Returns true when the hit
    // should kill: the player has run out of grazes or limbs.
    public bool TakeGraze(Vector2 blastCenter)
    {
        grazes++;
        if (grazes > grazesSurvived) return true;

        Limb limb = ClosestLimb(blastCenter);
        if (limb == null) return true;
        limb.Lost = true;
        RemoveLostLimbsFromMesh();
        foreach (Vector3 point in RandomPoints(limb.Bones, grazeChunks))
            SpawnChunk(point, blastCenter);
        return false;
    }

    // Bursts the whole body into chunks. The player is hidden by the caller.
    public void Burst(Vector2 blastCenter)
    {
        var bones = new List<Transform>();
        foreach (SkinnedMeshRenderer skin in skins)
            foreach (Transform bone in skin.bones)
                if (bone != null) bones.Add(bone);
        if (bones.Count == 0) bones.Add(transform);
        foreach (Vector3 point in RandomPoints(bones, burstChunks))
            SpawnChunk(point, blastCenter);
    }

    // Puts lost limbs back for a new round.
    public void RestoreBody()
    {
        grazes = 0;
        foreach (Limb limb in limbs) limb.Lost = false;
        for (int i = 0; i < skins.Length; i++)
        {
            if (skins[i] != null) skins[i].sharedMesh = originalMeshes[i];
            if (damagedMeshes[i] != null) Destroy(damagedMeshes[i]);
            damagedMeshes[i] = null;
        }
    }

    private Limb ClosestLimb(Vector2 point)
    {
        Limb best = null;
        float bestDistance = float.MaxValue;
        foreach (Limb limb in limbs)
        {
            if (limb.Lost || limb.Root == null) continue;
            float distance = Vector2.Distance(point, limb.Root.position);
            if (distance >= bestDistance) continue;
            bestDistance = distance;
            best = limb;
        }
        return best;
    }

    // Drops every triangle whose vertices are mainly moved by a lost limb's
    // bones, so the limb disappears cleanly while the rest keeps animating.
    private void RemoveLostLimbsFromMesh()
    {
        var lostBones = new HashSet<Transform>();
        foreach (Limb limb in limbs)
            if (limb.Lost) lostBones.UnionWith(limb.Bones);

        for (int i = 0; i < skins.Length; i++)
        {
            Mesh source = originalMeshes[i];
            if (skins[i] == null || source == null) continue;
            if (!source.isReadable)
            {
                Debug.LogWarning($"[PlayerBodyDamage] Turn on Read/Write for '{source.name}' so limbs can be removed.", this);
                continue;
            }

            Transform[] bones = skins[i].bones;
            var lostIndex = new bool[bones.Length];
            for (int b = 0; b < bones.Length; b++) lostIndex[b] = bones[b] != null && lostBones.Contains(bones[b]);

            // Unity sorts weights so boneIndex0 is the strongest influence.
            BoneWeight[] weights = source.boneWeights;
            if (weights.Length != source.vertexCount) continue;
            if (damagedMeshes[i] == null)
            {
                damagedMeshes[i] = Instantiate(source);
                damagedMeshes[i].name = source.name + " (damaged)";
                skins[i].sharedMesh = damagedMeshes[i];
            }

            var kept = new List<int>();
            for (int submesh = 0; submesh < source.subMeshCount; submesh++)
            {
                int[] triangles = source.GetTriangles(submesh);
                kept.Clear();
                for (int t = 0; t < triangles.Length; t += 3)
                {
                    if (IsLost(weights[triangles[t]], lostIndex) || IsLost(weights[triangles[t + 1]], lostIndex)
                        || IsLost(weights[triangles[t + 2]], lostIndex)) continue;
                    kept.Add(triangles[t]); kept.Add(triangles[t + 1]); kept.Add(triangles[t + 2]);
                }
                damagedMeshes[i].SetTriangles(kept, submesh);
            }
        }
    }

    private static bool IsLost(BoneWeight weight, bool[] lostIndex) =>
        weight.boneIndex0 >= 0 && weight.boneIndex0 < lostIndex.Length && lostIndex[weight.boneIndex0];

    private static IEnumerable<Vector3> RandomPoints(List<Transform> bones, int count)
    {
        for (int i = 0; i < count; i++)
        {
            Transform bone = bones[Random.Range(0, bones.Count)];
            yield return bone.position + Random.insideUnitSphere * 0.12f;
        }
    }

    private void SpawnChunk(Vector3 position, Vector2 blastCenter)
    {
        Material material = skins.Length > 0 && skins[0] != null ? skins[0].sharedMaterial : null;
        if (material == null) return;
        Vector2 away = (Vector2)position - blastCenter;
        if (away.sqrMagnitude < 0.0001f) away = Random.insideUnitCircle;
        away = away.normalized + Vector2.up * 0.6f;
        float strength = chunkImpulse * Random.Range(0.7f, 1.3f);
        Vector3 impulse = new Vector3(away.x * strength, away.y * strength,
            Random.Range(-1f, 1f) * strength * depthSpread);
        // Not parented to the round's effects, which are cleared the moment a
        // round ends. Chunks shrink away on their own instead.
        GroundRubble chunk = GroundRubble.Spawn(position, chunkSize * Random.Range(0.75f, 1.3f), impulse,
            material, null, player.CharacterColor);
        // Chunks start inside the player's body; without this they would be
        // shoved out violently by the collision.
        if (chunk != null && chunk.Collider != null && TryGetComponent(out CharacterController body))
            Physics.IgnoreCollision(chunk.Collider, body);
    }
}
