using System.Collections.Generic;
using UnityEngine;

// Receives blast damage and carves or splits a mesh object into physical fragments.
[AddComponentMenu("Arena/Destructible Object")]
public sealed class DestructibleObject : MonoBehaviour, IBlastReceiver
{
    public enum DestructionBehavior { Carve, CarveAndFragment }
    [SerializeField] private DestructionBehavior behavior = DestructionBehavior.Carve;
    [SerializeField, Tooltip("Carve And Fragment only: fall when a blast removes what this piece rests on.")]
    private bool fallWhenUnsupported = true;

    private const float Epsilon = 0.00001f;
    private const float MinimumSurvivingWidth = 0.18f;
    private const float MinimumSurvivingArea = 0.035f;
    private Collider rockCollider;
    private Renderer[] rockRenderers;
    private Bounds originalBounds;
    private Material rockMaterial;
    private MeshFilter rockFilter;
    private Mesh originalMesh;
    private MeshCollider rockMeshCollider;
    private Mesh generatedMesh;
    private readonly List<List<Vector2>> meshCutters = new List<List<Vector2>>();
    // XY bounds of each cutter, used to skip cutters that miss a shape.
    private readonly List<Rect> cutterBounds = new List<Rect>();
    private int lastCutFrame = -1;
    private static readonly List<DestructibleObject> Enabled = new List<DestructibleObject>();
    private bool originalStateCached;
    private static readonly HashSet<DestructibleObject> ActiveFragments = new HashSet<DestructibleObject>();
    private DestructibleObject fragmentOwner;
    private bool broken;

    private void Awake()
    {
        CacheOriginalState();
    }

    private void CacheOriginalState()
    {
        rockRenderers = GetComponentsInChildren<Renderer>(true);
        if (rockFilter == null) rockFilter = GetComponentInChildren<MeshFilter>(true);
        if (originalMesh == null && rockFilter != null) originalMesh = rockFilter.sharedMesh;
        // Unity's built-in Cube can't be read at runtime, so it can't be cut.
        // Swap it for a readable box of the same size.
        if (originalMesh != null && !originalMesh.isReadable)
        {
            Mesh box = CreateBoxMesh(originalMesh.bounds);
            foreach (Collider candidate in GetComponentsInChildren<Collider>(true))
                if (candidate is MeshCollider meshCollider && meshCollider.sharedMesh == originalMesh)
                    meshCollider.sharedMesh = box;
            originalMesh = box;
            rockFilter.sharedMesh = box;
        }

        Collider[] colliders = GetComponentsInChildren<Collider>(true);
        foreach (Collider candidate in colliders)
        {
            if (candidate is MeshCollider mesh && mesh.sharedMesh != null)
            {
                rockCollider = candidate;
                break;
            }
        }
        if (rockCollider == null && colliders.Length > 0)
            rockCollider = colliders[0];
        // Imported rock meshes often have no collider. Give the destructible its
        // source mesh collider so blasts can reach it and reset can always restore it.
        // Prefer a mesh collider paired with the rendered mesh. A box collider
        // may exist for coarse gameplay, but it cannot be rebuilt with the cut mesh.
        if (rockFilter != null && originalMesh != null && !(rockCollider is MeshCollider))
        {
            rockMeshCollider = rockFilter.GetComponent<MeshCollider>();
            if (rockMeshCollider == null) rockMeshCollider = rockFilter.gameObject.AddComponent<MeshCollider>();
            rockMeshCollider.sharedMesh = originalMesh;
            rockCollider = rockMeshCollider;
        }
        foreach (Collider candidate in colliders)
        {
            if (candidate != rockCollider && candidate is MeshCollider mesh && mesh.sharedMesh == null)
                candidate.enabled = false;
        }
        if (rockCollider == null) return;
        rockMeshCollider = rockCollider as MeshCollider;
        if (rockMeshCollider != null && rockMeshCollider.sharedMesh == null && originalMesh != null)
            rockMeshCollider.sharedMesh = originalMesh;
        if (!originalStateCached) originalBounds = rockCollider.bounds;
        originalStateCached = true;
        foreach (Renderer renderer in rockRenderers)
        {
            if (renderer.sharedMaterial != null)
            {
                rockMaterial = renderer.sharedMaterial;
                break;
            }
        }
    }

    // A readable box mesh filling the given local bounds, with one UV square per face.
    private static Mesh CreateBoxMesh(Bounds bounds)
    {
        Vector3 min = bounds.min, max = bounds.max;
        Vector3[] normals = { Vector3.forward, Vector3.back, Vector3.up, Vector3.down, Vector3.right, Vector3.left };
        var vertices = new List<Vector3>(24);
        var faceNormals = new List<Vector3>(24);
        var uvs = new List<Vector2>(24);
        var triangles = new List<int>(36);
        foreach (Vector3 normal in normals)
        {
            // Two axes across the face, chosen so the face winds outward.
            Vector3 u = normal.y != 0f ? Vector3.right : Vector3.Cross(Vector3.up, normal);
            Vector3 v = Vector3.Cross(normal, u);
            int start = vertices.Count;
            for (int corner = 0; corner < 4; corner++)
            {
                float su = corner == 1 || corner == 2 ? 1f : -1f;
                float sv = corner >= 2 ? 1f : -1f;
                Vector3 direction = normal + u * su + v * sv;
                vertices.Add(new Vector3(
                    direction.x > 0f ? max.x : min.x,
                    direction.y > 0f ? max.y : min.y,
                    direction.z > 0f ? max.z : min.z));
                faceNormals.Add(normal);
                uvs.Add(new Vector2(su * 0.5f + 0.5f, sv * 0.5f + 0.5f));
            }
            // Clockwise seen from outside, which Unity draws as the front.
            triangles.Add(start); triangles.Add(start + 1); triangles.Add(start + 2);
            triangles.Add(start); triangles.Add(start + 2); triangles.Add(start + 3);
        }
        var mesh = new Mesh { name = "Readable Box" };
        mesh.SetVertices(vertices);
        mesh.SetNormals(faceNormals);
        mesh.SetUVs(0, uvs);
        mesh.SetTriangles(triangles, 0);
        mesh.RecalculateBounds();
        return mesh;
    }

    public void ReceiveBlast(BlastPayload blast)
    {
        if (broken || rockCollider == null || !rockCollider.enabled) return;

        Vector2 center = blast.Center;
        if (DistanceInPlane(center) > blast.OuterRadius) return;
        lastCutFrame = Time.frameCount;

        var cutter = CreateCircle(center, blast.OuterRadius, 32);
        meshCutters.Add(cutter);
        cutterBounds.Add(new Rect(center.x - blast.OuterRadius, center.y - blast.OuterRadius,
            blast.OuterRadius * 2f, blast.OuterRadius * 2f));

        if (behavior == DestructionBehavior.Carve)
        {
            RebuildCarvedObject();
            return;
        }

        RebuildCarvedObject();
        if (broken) return;
        broken = true;
        rockCollider.enabled = false;
        foreach (Renderer renderer in rockRenderers) renderer.enabled = false;
        if (generatedMesh != null && generatedMesh.vertexCount > 0)
            CreateMeshFragment(generatedMesh, center, blast.Impulse);
        if (fragmentOwner != null) Destroy(gameObject);
    }

    // True when a blast cut into this object during the current frame.
    public bool WasCutThisFrame => lastCutFrame == Time.frameCount;
    // The object's main material, used to colour rubble thrown from it.
    public Material SurfaceMaterial => rockMaterial;
    public bool BreaksApart => behavior == DestructionBehavior.CarveAndFragment;

    // Distance in the XY play plane from a point to this object's collider.
    private float DistanceInPlane(Vector2 point)
    {
        // ClosestPoint does not support concave mesh colliders, so use their
        // bounds instead. For the box-shaped blocks the bounds are exact.
        Vector3 closest;
        if (rockCollider is MeshCollider mesh && !mesh.convex)
        {
            Bounds bounds = rockCollider.bounds;
            closest = new Vector3(Mathf.Clamp(point.x, bounds.min.x, bounds.max.x),
                Mathf.Clamp(point.y, bounds.min.y, bounds.max.y), 0f);
        }
        else closest = rockCollider.ClosestPoint(new Vector3(point.x, point.y, originalBounds.center.z));
        return Vector2.Distance(point, new Vector2(closest.x, closest.y));
    }

    private bool CanFall => behavior == DestructionBehavior.CarveAndFragment && fallWhenUnsupported
        && !broken && fragmentOwner == null && isActiveAndEnabled
        && rockCollider != null && rockCollider.enabled && rockFilter != null && originalMesh != null;

    // Breakable pieces resting on something solid right now. Taken before a
    // blast, so pieces built to float in the level are never dropped.
    public static List<DestructibleObject> FindSupportedPieces()
    {
        Physics.SyncTransforms();
        var supported = new List<DestructibleObject>();
        foreach (DestructibleObject piece in Enabled)
            if (piece.CanFall && piece.IsSupported()) supported.Add(piece);
        return supported;
    }

    private void OnEnable() => Enabled.Add(this);
    private void OnDisable() => Enabled.Remove(this);

    // Drops pieces that lost their support in a blast. Repeats so a piece
    // resting on another falling piece comes down with it.
    public static void DropUnsupportedPieces(List<DestructibleObject> previouslySupported)
    {
        bool droppedAny = true;
        while (droppedAny)
        {
            droppedAny = false;
            Physics.SyncTransforms();
            for (int i = previouslySupported.Count - 1; i >= 0; i--)
            {
                DestructibleObject piece = previouslySupported[i];
                if (piece != null && piece.CanFall && piece.IsSupported()) continue;
                previouslySupported.RemoveAt(i);
                if (piece == null || !piece.CanFall) continue;
                piece.Fall();
                droppedAny = true;
            }
        }
    }

    private static readonly Collider[] SupportHits = new Collider[32];

    // Looks in a thin slab just under the piece for a solid, non-moving collider.
    private bool IsSupported()
    {
        const float probeHeight = 0.08f;
        Bounds bounds = rockCollider.bounds;
        Vector3 center = new Vector3(bounds.center.x, bounds.min.y - probeHeight * 0.5f, bounds.center.z);
        Vector3 halfSize = new Vector3(Mathf.Max(0.01f, bounds.extents.x * 0.9f), probeHeight * 0.5f,
            Mathf.Max(0.01f, bounds.extents.z * 0.9f));
        int count = Physics.OverlapBoxNonAlloc(center, halfSize, SupportHits, Quaternion.identity,
            Physics.AllLayers, QueryTriggerInteraction.Ignore);
        for (int i = 0; i < count; i++)
        {
            Collider hit = SupportHits[i];
            // Players, items, bombs and falling pieces all have rigidbodies and never hold anything up.
            if (hit == rockCollider || hit.attachedRigidbody != null || hit.transform.IsChildOf(transform)) continue;
            return true;
        }
        return false;
    }

    // Swaps the intact piece for a physics copy that drops under gravity.
    private void Fall()
    {
        broken = true;
        rockCollider.enabled = false;
        foreach (Renderer renderer in rockRenderers) renderer.enabled = false;
        Mesh mesh = generatedMesh != null && generatedMesh.vertexCount > 0 ? generatedMesh : originalMesh;
        CreateMeshFragment(mesh, rockFilter.transform.position, 0f);
    }

    public void ResetObject()
    {
        if (rockCollider == null) CacheOriginalState();
        var fragmentsToDestroy = new List<DestructibleObject>();
        foreach (DestructibleObject fragment in ActiveFragments)
        {
            if (fragment != null && fragment.fragmentOwner == this)
                fragmentsToDestroy.Add(fragment);
        }
        foreach (DestructibleObject fragment in fragmentsToDestroy)
        {
            // Destroy is deferred during play mode. Deactivate now so a reset
            // cannot leave fragment renderers or colliders alive until frame end.
            fragment.gameObject.SetActive(false);
            Destroy(fragment.gameObject);
        }
        broken = false;
        meshCutters.Clear();
        cutterBounds.Clear();
        if (generatedMesh != null) { Destroy(generatedMesh); generatedMesh = null; }
        if (rockFilter != null) rockFilter.sharedMesh = originalMesh;
        // Reacquire the collider from the source mesh object every reset. The
        // previous collider may have been removed or left without a cooked mesh.
        if (rockFilter != null && originalMesh != null)
        {
            rockMeshCollider = rockFilter.GetComponent<MeshCollider>();
            if (rockMeshCollider == null) rockMeshCollider = rockFilter.gameObject.AddComponent<MeshCollider>();
            rockMeshCollider.sharedMesh = null;
            rockMeshCollider.sharedMesh = originalMesh;
            rockMeshCollider.enabled = true;
            rockCollider = rockMeshCollider;
        }
        if (rockMeshCollider != null)
        {
            rockMeshCollider.sharedMesh = null;
            rockMeshCollider.sharedMesh = originalMesh;
        }
        if (rockCollider != null) rockCollider.enabled = true;
        foreach (Renderer renderer in rockRenderers) renderer.enabled = true;
    }

    // Clip source mesh triangles in world XY so the surviving rock keeps its
    // authored silhouette and facets instead of becoming an extruded bounds box.
    private void RebuildCarvedObject()
    {
        if (rockFilter == null || originalMesh == null) return;
        Vector3[] sourceVertices = originalMesh.vertices;
        Vector2[] sourceUvs = originalMesh.uv;
        var vertices = new List<Vector3>();
        var uvs = new List<Vector2>();
        var submeshTriangles = new List<int>[originalMesh.subMeshCount];
        var wallSpans = new Dictionary<(int cutter, int edge, int submesh), List<Vector2>>();
        for (int s = 0; s < submeshTriangles.Length; s++) submeshTriangles[s] = new List<int>();
        Transform meshTransform = rockFilter != null ? rockFilter.transform : transform;
        for (int submesh = 0; submesh < originalMesh.subMeshCount; submesh++)
        {
            int[] indices = originalMesh.GetTriangles(submesh);
            for (int triangle = 0; triangle < indices.Length; triangle += 3)
            {
                var polygon = new List<CutVertex>(3);
                for (int corner = 0; corner < 3; corner++)
                {
                    int index = indices[triangle + corner];
                    polygon.Add(new CutVertex(meshTransform.TransformPoint(sourceVertices[index]),
                        sourceUvs != null && sourceUvs.Length == sourceVertices.Length ? sourceUvs[index] : Vector2.zero));
                }
                var pieces = new List<List<CutVertex>> { polygon };
                for (int c = 0; c < meshCutters.Count; c++)
                {
                    // Only split pieces the cutter can reach. Clipping a piece
                    // against a distant cutter still slices it along the
                    // cutter's edge lines, which multiplies pieces for nothing.
                    var nextPieces = new List<List<CutVertex>>();
                    foreach (List<CutVertex> sourcePiece in pieces)
                    {
                        if (PieceBounds(sourcePiece).Overlaps(cutterBounds[c])) SubtractCutter(sourcePiece, meshCutters[c], nextPieces);
                        else nextPieces.Add(sourcePiece);
                    }
                    pieces = nextPieces;
                    if (pieces.Count == 0) break;
                }
                foreach (List<CutVertex> survivingPiece in pieces)
                {
                    if (survivingPiece.Count < 3) continue;
                    CollectWallSpans(survivingPiece, submesh, wallSpans);
                    int start = vertices.Count;
                    foreach (CutVertex vertex in survivingPiece)
                    {
                        vertices.Add(meshTransform.InverseTransformPoint(vertex.position));
                        uvs.Add(vertex.uv);
                    }
                    for (int i = 1; i < survivingPiece.Count - 1; i++)
                    {
                        submeshTriangles[submesh].Add(start);
                        submeshTriangles[submesh].Add(start + i);
                        submeshTriangles[submesh].Add(start + i + 1);
                    }
                }
            }
        }
        AddCutWallGeometry(meshTransform, vertices, uvs, submeshTriangles, MergeWallSpans(wallSpans));
        if (generatedMesh == null) generatedMesh = new Mesh { name = "Carved Destructible Object" };
        generatedMesh.Clear();
        generatedMesh.indexFormat = vertices.Count > 65535
            ? UnityEngine.Rendering.IndexFormat.UInt32
            : UnityEngine.Rendering.IndexFormat.UInt16;
        generatedMesh.SetVertices(vertices);
        generatedMesh.SetUVs(0, uvs);
        generatedMesh.subMeshCount = submeshTriangles.Length;
        for (int s = 0; s < submeshTriangles.Length; s++) generatedMesh.SetTriangles(submeshTriangles[s], s);
        generatedMesh.RecalculateNormals(); generatedMesh.RecalculateBounds();
        if (IsTooSmall(generatedMesh, meshTransform))
        {
            broken = true;
            if (rockCollider != null) rockCollider.enabled = false;
            foreach (Renderer renderer in rockRenderers) renderer.enabled = false;
            return;
        }
        if (rockFilter != null) rockFilter.sharedMesh = generatedMesh;
        if (rockCollider is MeshCollider meshCollider)
        {
            meshCollider.sharedMesh = null;
            meshCollider.sharedMesh = generatedMesh;
        }
        else rockCollider.enabled = false;
    }

    private const float WallTolerance = 0.001f;

    private static Rect PieceBounds(List<CutVertex> polygon)
    {
        Vector2 min = polygon[0].position;
        Vector2 max = min;
        for (int i = 1; i < polygon.Count; i++)
        {
            Vector2 point = polygon[i].position;
            min = Vector2.Min(min, point);
            max = Vector2.Max(max, point);
        }
        return Rect.MinMaxRect(min.x, min.y, max.x, max.y);
    }

    // Records which part of each cutter edge borders surviving material.
    // A clipped piece's edge often runs along a cutter edge's line and past its
    // ends, so only the overlap with the cutter edge itself becomes a wall.
    private void CollectWallSpans(List<CutVertex> polygon, int submesh,
        Dictionary<(int cutter, int edge, int submesh), List<Vector2>> wallSpans)
    {
        Rect bounds = PieceBounds(polygon);
        bounds.min -= Vector2.one * WallTolerance;
        bounds.max += Vector2.one * WallTolerance;
        for (int edge = 0; edge < polygon.Count; edge++)
        {
            Vector2 a = polygon[edge].position;
            Vector2 b = polygon[(edge + 1) % polygon.Count].position;
            if ((b - a).sqrMagnitude < Epsilon * Epsilon) continue;
            for (int cutterIndex = 0; cutterIndex < meshCutters.Count; cutterIndex++)
            {
                if (!bounds.Overlaps(cutterBounds[cutterIndex])) continue;
                List<Vector2> cutter = meshCutters[cutterIndex];
                for (int cutterEdge = 0; cutterEdge < cutter.Count; cutterEdge++)
                {
                    Vector2 cutterA = cutter[cutterEdge];
                    Vector2 delta = cutter[(cutterEdge + 1) % cutter.Count] - cutterA;
                    float lengthSquared = delta.sqrMagnitude;
                    if (lengthSquared < Epsilon * Epsilon) continue;
                    float length = Mathf.Sqrt(lengthSquared);
                    if (Mathf.Abs(Cross(delta, a - cutterA)) > WallTolerance * length) continue;
                    if (Mathf.Abs(Cross(delta, b - cutterA)) > WallTolerance * length) continue;
                    float ta = Vector2.Dot(a - cutterA, delta) / lengthSquared;
                    float tb = Vector2.Dot(b - cutterA, delta) / lengthSquared;
                    float low = Mathf.Max(0f, Mathf.Min(ta, tb));
                    float high = Mathf.Min(1f, Mathf.Max(ta, tb));
                    if ((high - low) * length <= WallTolerance) continue;
                    var key = (cutterIndex, cutterEdge, submesh);
                    if (!wallSpans.TryGetValue(key, out List<Vector2> spans))
                        wallSpans.Add(key, spans = new List<Vector2>());
                    spans.Add(new Vector2(low, high));
                }
            }
        }
    }

    // Joins overlapping spans so the front and back faces share one wall.
    private List<CutWall> MergeWallSpans(Dictionary<(int cutter, int edge, int submesh), List<Vector2>> wallSpans)
    {
        var walls = new List<CutWall>();
        foreach (var entry in wallSpans)
        {
            List<Vector2> cutter = meshCutters[entry.Key.cutter];
            Vector2 cutterA = cutter[entry.Key.edge];
            Vector2 delta = cutter[(entry.Key.edge + 1) % cutter.Count] - cutterA;
            float gap = WallTolerance / delta.magnitude;
            List<Vector2> spans = entry.Value;
            spans.Sort((x, y) => x.x.CompareTo(y.x));
            Vector2 current = spans[0];
            for (int i = 1; i <= spans.Count; i++)
            {
                if (i < spans.Count && spans[i].x <= current.y + gap)
                {
                    current.y = Mathf.Max(current.y, spans[i].y);
                    continue;
                }
                walls.Add(new CutWall(cutterA + delta * current.x, cutterA + delta * current.y, entry.Key.submesh));
                if (i < spans.Count) current = spans[i];
            }
        }
        return walls;
    }

    private void AddCutWallGeometry(
        Transform meshTransform,
        List<Vector3> vertices,
        List<Vector2> uvs,
        List<int>[] submeshTriangles,
        List<CutWall> cutWalls)
    {
        float front = originalBounds.min.z;
        float back = originalBounds.max.z;
        float depth = Mathf.Max(Epsilon, back - front);
        foreach (CutWall wall in cutWalls)
        {
            int submesh = Mathf.Clamp(wall.submesh, 0, submeshTriangles.Length - 1);
            int start = vertices.Count;
            // The cutter is counterclockwise, so this winding points toward
            // the removed volume rather than back into the surviving mesh.
            vertices.Add(meshTransform.InverseTransformPoint(new Vector3(wall.end.x, wall.end.y, front)));
            vertices.Add(meshTransform.InverseTransformPoint(new Vector3(wall.start.x, wall.start.y, front)));
            vertices.Add(meshTransform.InverseTransformPoint(new Vector3(wall.start.x, wall.start.y, back)));
            vertices.Add(meshTransform.InverseTransformPoint(new Vector3(wall.end.x, wall.end.y, back)));

            float length = Vector2.Distance(wall.start, wall.end);
            uvs.Add(new Vector2(0f, 0f));
            uvs.Add(new Vector2(length, 0f));
            uvs.Add(new Vector2(length, depth));
            uvs.Add(new Vector2(0f, depth));
            submeshTriangles[submesh].Add(start);
            submeshTriangles[submesh].Add(start + 1);
            submeshTriangles[submesh].Add(start + 2);
            submeshTriangles[submesh].Add(start);
            submeshTriangles[submesh].Add(start + 2);
            submeshTriangles[submesh].Add(start + 3);
        }
    }

    private static bool IsTooSmall(Mesh mesh, Transform meshTransform)
    {
        if (mesh == null || mesh.vertexCount == 0) return true;
        Bounds local = mesh.bounds;
        Vector3 corner = meshTransform.TransformPoint(new Vector3(local.min.x, local.min.y, local.min.z));
        Bounds worldBounds = new Bounds(corner, Vector3.zero);
        for (int mask = 1; mask < 8; mask++)
        {
            Vector3 point = new Vector3(
                (mask & 1) == 0 ? local.min.x : local.max.x,
                (mask & 2) == 0 ? local.min.y : local.max.y,
                (mask & 4) == 0 ? local.min.z : local.max.z);
            worldBounds.Encapsulate(meshTransform.TransformPoint(point));
        }
        float width = worldBounds.size.x;
        float height = worldBounds.size.y;
        return width < MinimumSurvivingWidth || height < MinimumSurvivingWidth
            || width * height < MinimumSurvivingArea;
    }

    private struct CutVertex
    {
        public Vector3 position;
        public Vector2 uv;
        public CutVertex(Vector3 position, Vector2 uv) { this.position = position; this.uv = uv; }
    }

    private readonly struct CutWall
    {
        public readonly Vector2 start;
        public readonly Vector2 end;
        public readonly int submesh;
        public CutWall(Vector2 start, Vector2 end, int submesh)
        {
            this.start = start;
            this.end = end;
            this.submesh = submesh;
        }
    }

    private static void SubtractCutter(List<CutVertex> polygon, List<Vector2> cutter, List<List<CutVertex>> output)
    {
        List<CutVertex> remaining = polygon;
        for (int edge = 0; edge < cutter.Count && remaining.Count >= 3; edge++)
        {
            Vector2 a = cutter[edge], b = cutter[(edge + 1) % cutter.Count];
            List<CutVertex> outside = ClipMeshPolygon(remaining, a, b, false);
            if (outside.Count >= 3) output.Add(outside);
            remaining = ClipMeshPolygon(remaining, a, b, true);
        }
    }

    private static List<CutVertex> ClipMeshPolygon(List<CutVertex> polygon, Vector2 a, Vector2 b, bool inside)
    {
        var output = new List<CutVertex>();
        CutVertex previous = polygon[polygon.Count - 1];
        float previousDistance = Cross(b - a, (Vector2)previous.position - a);
        bool previousKept = inside ? previousDistance >= 0f : previousDistance <= 0f;
        foreach (CutVertex current in polygon)
        {
            float distance = Cross(b - a, (Vector2)current.position - a);
            bool kept = inside ? distance >= 0f : distance <= 0f;
            if (kept != previousKept)
            {
                float t = previousDistance / (previousDistance - distance);
                output.Add(new CutVertex(Vector3.LerpUnclamped(previous.position, current.position, t),
                    Vector2.LerpUnclamped(previous.uv, current.uv, t)));
            }
            if (kept) output.Add(current);
            previous = current;
            previousDistance = distance;
            previousKept = kept;
        }
        return output;
    }

    public static void ResetAllObjects()
    {
        DestructibleObject[] rocks = FindObjectsByType<DestructibleObject>(FindObjectsInactive.Include, FindObjectsSortMode.None);
        foreach (DestructibleObject rock in rocks)
        {
            if (rock.fragmentOwner == null)
                rock.ResetObject();
        }
    }

    public static void DestroyFragmentsWithin(Vector2 center, float radius)
    {
        var toDestroy = new List<DestructibleObject>();
        foreach (DestructibleObject fragment in ActiveFragments)
        {
            if (fragment == null) continue;
            Collider collider = fragment.GetComponent<Collider>();
            Vector3 point = collider != null
                ? collider.ClosestPoint(new Vector3(center.x, center.y, collider.bounds.center.z))
                : fragment.transform.position;
            if (Vector2.Distance(center, new Vector2(point.x, point.y)) <= radius)
                toDestroy.Add(fragment);
        }
        foreach (DestructibleObject fragment in toDestroy)
        {
            if (fragment == null) continue;
            fragment.gameObject.SetActive(false);
            Destroy(fragment.gameObject);
        }
    }

    private void CreateMeshFragment(Mesh mesh, Vector2 center, float impulse)
    {
        Transform sourceTransform = rockFilter.transform;
        var fragment = new GameObject("Rock Mesh Fragment");
        fragment.transform.SetPositionAndRotation(sourceTransform.position, sourceTransform.rotation);
        fragment.transform.localScale = sourceTransform.lossyScale;
        fragment.AddComponent<MeshFilter>().sharedMesh = mesh;
        var renderer = fragment.AddComponent<MeshRenderer>();
        MeshRenderer sourceRenderer = rockFilter.GetComponent<MeshRenderer>();
        if (sourceRenderer == null) sourceRenderer = GetComponentInChildren<MeshRenderer>(true);
        if (sourceRenderer != null) renderer.sharedMaterials = sourceRenderer.sharedMaterials;
        var collider = fragment.AddComponent<MeshCollider>();
        collider.sharedMesh = mesh;
        collider.convex = true;
        DestructibleObject receiver = fragment.AddComponent<DestructibleObject>();
        receiver.fragmentOwner = fragmentOwner != null ? fragmentOwner : this;
        ActiveFragments.Add(receiver);
        Rigidbody body = fragment.AddComponent<Rigidbody>();
        body.constraints = RigidbodyConstraints.FreezePositionZ
            | RigidbodyConstraints.FreezeRotationX
            | RigidbodyConstraints.FreezeRotationY;
        Vector2 direction = ((Vector2)sourceTransform.position - center).normalized;
        if (direction.sqrMagnitude < Epsilon) direction = Vector2.up;
        body.AddForce(new Vector3(direction.x, direction.y, 0f) * impulse, ForceMode.Impulse);
    }

    private static List<Vector2> CreateCircle(Vector2 center, float radius, int segments)
    {
        var points = new List<Vector2>(segments);
        for (int i = 0; i < segments; i++)
        {
            float angle = i * Mathf.PI * 2f / segments;
            points.Add(center + new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * radius);
        }
        return points;
    }

    private static float Cross(Vector2 a, Vector2 b) => a.x * b.y - a.y * b.x;

    private void OnDestroy()
    {
        ActiveFragments.Remove(this);
        if (Application.isPlaying && generatedMesh != null) Destroy(generatedMesh);
    }
}
