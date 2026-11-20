using System.Collections.Generic;
using UnityEngine;

namespace Bom.Unity
{
    // Presentation only. The look of Darryn's PlayerBodyDamage (a lost limb is cut out of the skinned mesh and
    // thrown off as a few clay chunks), driven by the copied native BomRoundPlayer.graze_count. Odin decides
    // grazes and the death; nothing here feeds back. No colliders, no Rigidbody: chunks are BomDeathBurst.
    [DisallowMultipleComponent]
    public sealed class BomLimbLoss : MonoBehaviour
    {
        const int ChunksPerLimb = 4;

        // One limb: its first bone plus every bone below it (as PlayerBodyDamage).
        sealed class Limb
        {
            public Transform Root;
            public readonly List<Transform> Bones = new List<Transform>();
            public bool Lost;
        }

        readonly List<Limb> limbs = new List<Limb>();
        readonly List<int> kept = new List<int>();
        SkinnedMeshRenderer[] skins;
        Mesh[] originalMeshes,
            damagedMeshes;
        bool keyed,
            warnedUnreadable;
        ulong roundId,
            sessionId,
            generation;
        uint shownCount;

        public uint ShownCount => shownCount;
        public int LimbCount
        {
            get
            {
                EnsureLimbs();
                return limbs.Count;
            }
        }
        public int LostLimbs
        {
            get
            {
                int lost = 0;
                foreach (var limb in limbs)
                    if (limb.Lost)
                        lost++;
                return lost;
            }
        }

        // Pooled actors are reused (BomActorPool.Rent): call this whenever an actor is (re)built.
        public void ResetBody()
        {
            keyed = false;
            shownCount = 0;
            RestoreBody();
        }

        // Applies the native graze count for one round player. Returns the number of grazes newly shown with
        // chunks. A new actor, round or session rebuilds the look from the count alone (late observers) and
        // throws nothing, so repeated or late snapshots never replay an effect.
        public int Present(
            ulong round,
            ulong session,
            ulong playerGeneration,
            uint count,
            Material chunkMaterial,
            Transform chunkParent,
            Color tint,
            Vector2 blast,
            bool hasBlast
        )
        {
            EnsureLimbs();
            if (
                !keyed
                || round != roundId
                || session != sessionId
                || playerGeneration != generation
                || count < shownCount
            )
            {
                RestoreBody();
                keyed = true;
                roundId = round;
                sessionId = session;
                generation = playerGeneration;
                shownCount = count;
                for (uint i = 0; i < count; i++)
                {
                    var limb = NextLimb();
                    if (limb == null)
                        break;
                    limb.Lost = true;
                }
                if (count > 0)
                    RemoveLostLimbsFromMesh();
                return 0;
            }
            if (count == shownCount)
                return 0;
            int presented = 0;
            for (uint i = shownCount; i < count; i++)
            {
                presented++;
                var limb = hasBlast ? ClosestLimb(blast) : NextLimb();
                if (limb == null)
                    continue;
                limb.Lost = true;
                if (chunkMaterial == null || chunkParent == null)
                    continue;
                Vector3 center = Vector3.zero;
                foreach (var bone in limb.Bones)
                    center += bone.position;
                center /= Mathf.Max(1, limb.Bones.Count);
                BomDeathBurst.Spawn(
                    chunkParent,
                    chunkMaterial,
                    center,
                    tint,
                    hasBlast ? blast : (Vector2)center - Vector2.up,
                    ChunksPerLimb,
                    "Native graze chunks"
                );
            }
            shownCount = count;
            RemoveLostLimbsFromMesh();
            return presented;
        }

        void EnsureLimbs()
        {
            if (skins != null)
                return;
            var view = GetComponent<BomActorView>();
            var root = view != null && view.AuthoredVisual != null ? view.AuthoredVisual : transform;
            skins = root.GetComponentsInChildren<SkinnedMeshRenderer>(true);
            originalMeshes = new Mesh[skins.Length];
            damagedMeshes = new Mesh[skins.Length];
            for (int i = 0; i < skins.Length; i++)
                originalMeshes[i] = skins[i].sharedMesh;
            // Limbs are bone chains named .L/.R (or _L/_R) hanging off a centre bone; without such names,
            // each child of the root bone counts as a limb.
            var seen = new HashSet<Transform>();
            foreach (var skin in skins)
            foreach (var bone in skin.bones)
            {
                if (bone == null || !IsSided(bone) || (bone.parent != null && IsSided(bone.parent)))
                    continue;
                if (seen.Add(bone))
                    limbs.Add(CreateLimb(bone));
            }
            if (limbs.Count > 0)
                return;
            foreach (var skin in skins)
            {
                if (skin.rootBone == null)
                    continue;
                foreach (Transform child in skin.rootBone)
                    if (seen.Add(child))
                        limbs.Add(CreateLimb(child));
            }
        }

        static bool IsSided(Transform bone) =>
            bone.name.EndsWith(".L")
            || bone.name.EndsWith(".R")
            || bone.name.EndsWith("_L")
            || bone.name.EndsWith("_R");

        static Limb CreateLimb(Transform root)
        {
            var limb = new Limb { Root = root };
            limb.Bones.AddRange(root.GetComponentsInChildren<Transform>(true));
            return limb;
        }

        // Fixed order, so every observer rebuilding from the count alone shows the same limbs.
        Limb NextLimb()
        {
            foreach (var limb in limbs)
                if (!limb.Lost && limb.Root != null)
                    return limb;
            return null;
        }

        Limb ClosestLimb(Vector2 point)
        {
            Limb best = null;
            float bestDistance = float.MaxValue;
            foreach (var limb in limbs)
            {
                if (limb.Lost || limb.Root == null)
                    continue;
                float distance = Vector2.Distance(point, limb.Root.position);
                if (distance >= bestDistance)
                    continue;
                bestDistance = distance;
                best = limb;
            }
            return best;
        }

        void RestoreBody()
        {
            if (skins == null)
                return;
            foreach (var limb in limbs)
                limb.Lost = false;
            for (int i = 0; i < skins.Length; i++)
            {
                if (skins[i] != null)
                    skins[i].sharedMesh = originalMeshes[i];
                if (damagedMeshes[i] != null)
                    Destroy(damagedMeshes[i]);
                damagedMeshes[i] = null;
            }
        }

        // Drops every triangle whose vertices are mainly moved by a lost limb's bones, so the limb disappears
        // cleanly while the rest keeps animating (PlayerBodyDamage.RemoveLostLimbsFromMesh).
        void RemoveLostLimbsFromMesh()
        {
            var lostBones = new HashSet<Transform>();
            foreach (var limb in limbs)
                if (limb.Lost)
                    lostBones.UnionWith(limb.Bones);
            for (int i = 0; i < skins.Length; i++)
            {
                Mesh source = originalMeshes[i];
                if (skins[i] == null || source == null)
                    continue;
                if (!source.isReadable)
                {
                    if (!warnedUnreadable)
                        Debug.LogWarning(
                            "BOM LIMB LOSS mesh '" + source.name + "' is not readable; limbs stay on",
                            this
                        );
                    warnedUnreadable = true;
                    continue;
                }
                Transform[] bones = skins[i].bones;
                var lostIndex = new bool[bones.Length];
                for (int b = 0; b < bones.Length; b++)
                    lostIndex[b] = bones[b] != null && lostBones.Contains(bones[b]);
                // Unity sorts weights so boneIndex0 is the strongest influence.
                BoneWeight[] weights = source.boneWeights;
                if (weights.Length != source.vertexCount)
                    continue;
                if (damagedMeshes[i] == null)
                {
                    damagedMeshes[i] = Instantiate(source);
                    damagedMeshes[i].name = source.name + " (damaged)";
                    skins[i].sharedMesh = damagedMeshes[i];
                }
                for (int submesh = 0; submesh < source.subMeshCount; submesh++)
                {
                    int[] triangles = source.GetTriangles(submesh);
                    kept.Clear();
                    for (int t = 0; t < triangles.Length; t += 3)
                    {
                        if (
                            IsLost(weights[triangles[t]], lostIndex)
                            || IsLost(weights[triangles[t + 1]], lostIndex)
                            || IsLost(weights[triangles[t + 2]], lostIndex)
                        )
                            continue;
                        kept.Add(triangles[t]);
                        kept.Add(triangles[t + 1]);
                        kept.Add(triangles[t + 2]);
                    }
                    damagedMeshes[i].SetTriangles(kept, submesh);
                }
            }
        }

        static bool IsLost(BoneWeight weight, bool[] lostIndex) =>
            weight.boneIndex0 >= 0
            && weight.boneIndex0 < lostIndex.Length
            && lostIndex[weight.boneIndex0];

        void OnDestroy()
        {
            if (damagedMeshes == null)
                return;
            foreach (var mesh in damagedMeshes)
                if (mesh != null)
                    Destroy(mesh);
        }
    }
}
