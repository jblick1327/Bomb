using UnityEngine;

namespace Bom.Unity
{
    // Presentation only. Clay chunks thrown out when a native player dies, like PlayerBodyDamage.Burst.
    // No colliders and no Rigidbody: the chunks are animated here and removed when their time is up.
    public sealed class BomDeathBurst : MonoBehaviour
    {
        const int ChunkCount = 14;
        const float Lifetime = 1.2f;
        const float Gravity = 18f;
        static Mesh chunkMesh;
        readonly Transform[] chunks = new Transform[ChunkCount];
        readonly Vector3[] velocity = new Vector3[ChunkCount];
        readonly Vector3[] spin = new Vector3[ChunkCount];
        readonly float[] baseSize = new float[ChunkCount];
        float age;

        public int ChunkTotal => ChunkCount;

        public static BomDeathBurst Spawn(
            Transform parent,
            Material material,
            Vector3 center,
            Color color,
            Vector2 awayFrom
        )
        {
            var root = new GameObject("Native death burst");
            root.transform.SetParent(parent, false);
            var burst = root.AddComponent<BomDeathBurst>();
            burst.Build(material, center, color, awayFrom);
            return burst;
        }

        void Build(Material material, Vector3 center, Color color, Vector2 awayFrom)
        {
            var properties = new MaterialPropertyBlock();
            properties.SetColor("_BaseColor", color);
            // Presentation randomness only; it never feeds back into the native simulation.
            var random = new System.Random(unchecked((int)(center.x * 1000) ^ (int)(center.y * 7919)));
            float Next() => (float)random.NextDouble();
            for (int i = 0; i < ChunkCount; i++)
            {
                var chunk = new GameObject("Chunk " + i);
                chunk.transform.SetParent(transform, false);
                chunk.transform.position =
                    center + new Vector3(Next() - .5f, Next() - .5f, 0) * .5f;
                baseSize[i] = .1f + Next() * .14f;
                chunk.transform.localScale = Vector3.one * baseSize[i];
                chunk.AddComponent<MeshFilter>().sharedMesh = ChunkMesh();
                var renderer = chunk.AddComponent<MeshRenderer>();
                renderer.sharedMaterial = material;
                renderer.SetPropertyBlock(properties);
                Vector2 away = (Vector2)chunk.transform.position - awayFrom;
                if (away.sqrMagnitude < .0001f)
                    away = Vector2.up;
                away.Normalize();
                velocity[i] =
                    (Vector3)(away * (2f + Next() * 4f)) + new Vector3(0, 2f + Next() * 3f, 0);
                spin[i] = new Vector3(Next() - .5f, Next() - .5f, Next() - .5f) * 720f;
                chunks[i] = chunk.transform;
            }
        }

        void Update()
        {
            float dt = Time.unscaledDeltaTime;
            age += dt;
            if (age >= Lifetime)
            {
                Destroy(gameObject);
                return;
            }
            float shrink = Mathf.Clamp01((Lifetime - age) / .4f);
            for (int i = 0; i < ChunkCount; i++)
            {
                velocity[i].y -= Gravity * dt;
                chunks[i].position += velocity[i] * dt;
                chunks[i].Rotate(spin[i] * dt);
                chunks[i].localScale = Vector3.one * baseSize[i] * shrink;
            }
        }

        static Mesh ChunkMesh()
        {
            if (chunkMesh != null)
                return chunkMesh;
            var v = new Vector3[8];
            for (int i = 0; i < 8; i++)
                v[i] = new Vector3((i & 1) - .5f, ((i >> 1) & 1) - .5f, ((i >> 2) & 1) - .5f);
            chunkMesh = new Mesh { name = "Native burst chunk", vertices = v };
            chunkMesh.triangles = new[]
            {
                0, 2, 1, 1, 2, 3, 4, 5, 6, 5, 7, 6, 0, 1, 4, 1, 5, 4,
                2, 6, 3, 3, 6, 7, 0, 4, 2, 2, 4, 6, 1, 3, 5, 3, 7, 5,
            };
            chunkMesh.RecalculateNormals();
            chunkMesh.hideFlags = HideFlags.HideAndDontSave;
            return chunkMesh;
        }
    }
}
