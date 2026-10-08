using System.Collections.Generic;
using UnityEngine;

// Rebuilds the yard ground mesh and collider with a lowered surface at each crater.
[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer), typeof(MeshCollider))]
[AddComponentMenu("Arena/Gameplay Ground")]
public sealed class ArenaGameplayGround : MonoBehaviour
{
    [SerializeField, Min(0.01f)] private float craterDepth = 2.6f;
    [SerializeField, Range(16, 256)] private int surfaceSegments = 128;
    [SerializeField, Min(0f)] private float flatFloorHalfWidth = 0.45f;

    // Stores the horizontal profile and depth of one surface cut.
    private struct Crater
    {
        public float centerX;
        public float radius;
        public float depth;
    }

    private readonly List<Crater> craters = new List<Crater>();
    private MeshCollider groundCollider;
    private Mesh generatedColliderMesh;
    private Mesh generatedVisualMesh;
    private Bounds worldBounds;
    private float groundTop;
    private float grassTop;
    private float dirtTop;
    private float frontZ;
    private float backZ;
    private bool initialized;

    public Collider GameplayCollider => groundCollider;

    private void Awake() => Initialize();

    public void Initialize()
    {
        if (initialized) return;

        groundCollider = GetComponent<MeshCollider>();
        MeshRenderer renderer = GetComponent<MeshRenderer>();
        worldBounds = renderer.bounds;
        dirtTop = renderer.bounds.max.y;
        MeshRenderer grassRenderer = FindGrassRenderer();
        grassTop = grassRenderer != null ? grassRenderer.bounds.max.y : dirtTop;
        // Blast reach is checked against the exposed dirt surface. Outside
        // craters, the collider still follows the intact grass surface.
        groundTop = dirtTop;
        frontZ = renderer.bounds.min.z;
        backZ = renderer.bounds.max.z;
        initialized = true;
        RebuildMeshes();
    }

    public void ApplyCrater(Vector2 center, float radius)
    {
        Initialize();
        if (radius <= 0f) return;
        // Check against the current dirt profile, including existing craters.
        // Comparing only with the original top falsely cuts dirt below a raised
        // impact when the actual surface has already dropped away.
        if (!BlastTouchesCurrentSurface(center, radius)) return;
        craters.Add(new Crater { centerX = center.x, radius = radius, depth = craterDepth });
        RebuildMeshes();
    }

    private bool BlastTouchesCurrentSurface(Vector2 center, float radius)
    {
        const int samples = 64;
        for (int i = 0; i <= samples; i++)
        {
            float dx = Mathf.Lerp(-radius, radius, i / (float)samples);
            float x = center.x + dx;
            if (x < worldBounds.min.x || x > worldBounds.max.x) continue;
            float verticalReach = Mathf.Sqrt(Mathf.Max(0f, radius * radius - dx * dx));
            float surfaceY = SurfaceHeight(x, groundTop);
            if (Mathf.Abs(center.y - surfaceY) <= verticalReach + 0.001f) return true;
        }
        return false;
    }

    public void ResetGround()
    {
        craters.Clear();
        Initialize();
        RebuildMeshes();
    }

    // Combine crater profiles, then clamp the cut so the floor cannot pass through its base.
    private float SurfaceHeight(float x, float top)
    {
        float lowered = 0f;
        foreach (Crater crater in craters)
        {
            float distance = Mathf.Abs(x - crater.centerX);
            if (distance >= crater.radius) continue;
            float flatWidth = Mathf.Min(flatFloorHalfWidth, crater.radius * 0.45f);
            float slopeDistance = Mathf.Max(0f, distance - flatWidth);
            float slopeRadius = Mathf.Max(0.01f, crater.radius - flatWidth);
            float amount = Mathf.Sqrt(Mathf.Max(0f, 1f - slopeDistance * slopeDistance / (slopeRadius * slopeRadius)));
            lowered += crater.depth * amount;
        }
        return Mathf.Max(worldBounds.min.y, top - Mathf.Min(lowered, craterDepth * 2f));
    }

    private Vector3 ToLocal(float x, float y, float z) => transform.InverseTransformPoint(new Vector3(x, y, z));

    private void RebuildMeshes()
    {
        int count = Mathf.Max(16, surfaceSegments);
        RebuildSlab(ref generatedColliderMesh, "Gameplay Ground Collision", count, groundTop, true);
        RebuildSlab(ref generatedVisualMesh, "Destructible Dirt Ground", count, dirtTop, false);
        groundCollider.sharedMesh = null;
        groundCollider.sharedMesh = generatedColliderMesh;
        groundCollider.convex = false;
        groundCollider.enabled = true;
        GetComponent<MeshFilter>().sharedMesh = generatedVisualMesh;
        Physics.SyncTransforms();
    }

    // Build top samples plus the bottom and side faces that close the extruded slab.
    private void RebuildSlab(ref Mesh mesh, string meshName, int count, float surfaceTop, bool collisionSurface)
    {
        var vertices = new List<Vector3>((count + 1) * 2 + count * 4);
        var triangles = new List<int>(count * 36);
        for (int index = 0; index <= count; index++)
        {
            float x = Mathf.Lerp(worldBounds.min.x, worldBounds.max.x, index / (float)count);
            float y = collisionSurface ? CollisionSurfaceHeight(x) : SurfaceHeight(x, surfaceTop);
            vertices.Add(ToLocal(x, y, frontZ));
            vertices.Add(ToLocal(x, y, backZ));
        }

        for (int index = 0; index < count; index++)
        {
            int top = index * 2;
            int next = top + 2;
            AddQuad(triangles, top, top + 1, next + 1, next);
            int bottomStart = vertices.Count;
            vertices.Add(ToLocal(VertexToWorldX(top, count), worldBounds.min.y, frontZ));
            vertices.Add(ToLocal(VertexToWorldX(next, count), worldBounds.min.y, frontZ));
            vertices.Add(ToLocal(VertexToWorldX(next, count), worldBounds.min.y, backZ));
            vertices.Add(ToLocal(VertexToWorldX(top, count), worldBounds.min.y, backZ));
            AddQuad(triangles, bottomStart, bottomStart + 1, bottomStart + 2, bottomStart + 3);
            AddQuad(triangles, top, next, bottomStart + 1, bottomStart);
            AddQuad(triangles, top + 1, bottomStart + 3, bottomStart + 2, next + 1);
            AddQuad(triangles, top, top + 1, bottomStart + 3, bottomStart);
            AddQuad(triangles, next, bottomStart + 1, bottomStart + 2, next + 1);
        }

        if (mesh == null) mesh = new Mesh { name = meshName };
        mesh.Clear();
        mesh.indexFormat = vertices.Count > 65535
            ? UnityEngine.Rendering.IndexFormat.UInt32 : UnityEngine.Rendering.IndexFormat.UInt16;
        mesh.SetVertices(vertices);
        mesh.SetTriangles(triangles, 0);
        mesh.RecalculateNormals();
        mesh.RecalculateBounds();
    }

    private float CollisionSurfaceHeight(float x)
    {
        float lowered = 0f;
        bool insideCrater = false;
        foreach (Crater crater in craters)
        {
            float distance = Mathf.Abs(x - crater.centerX);
            if (distance >= crater.radius) continue;
            insideCrater = true;
            float flatWidth = Mathf.Min(flatFloorHalfWidth, crater.radius * 0.45f);
            float slopeDistance = Mathf.Max(0f, distance - flatWidth);
            float slopeRadius = Mathf.Max(0.01f, crater.radius - flatWidth);
            float amount = Mathf.Sqrt(Mathf.Max(0f, 1f - slopeDistance * slopeDistance / (slopeRadius * slopeRadius)));
            lowered += crater.depth * amount;
        }
        if (!insideCrater) return grassTop;
        return Mathf.Max(worldBounds.min.y, dirtTop - Mathf.Min(lowered, craterDepth * 2f));
    }

    private float VertexToWorldX(int vertexIndex, int count)
    {
        float t = vertexIndex / 2f / count;
        return Mathf.Lerp(worldBounds.min.x, worldBounds.max.x, t);
    }

    private MeshRenderer FindGrassRenderer()
    {
        foreach (MeshRenderer candidate in transform.root.GetComponentsInChildren<MeshRenderer>(true))
            if (candidate.gameObject.name == "Grass_Mesh") return candidate;
        return null;
    }

    private static void AddQuad(List<int> triangles, int a, int b, int c, int d)
    {
        triangles.Add(a); triangles.Add(b); triangles.Add(c);
        triangles.Add(a); triangles.Add(c); triangles.Add(d);
    }

    private void OnDestroy()
    {
        if (!Application.isPlaying) return;
        if (generatedColliderMesh != null) Destroy(generatedColliderMesh);
        if (generatedVisualMesh != null) Destroy(generatedVisualMesh);
    }
}
