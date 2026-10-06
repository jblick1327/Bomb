using System.Collections.Generic;
using UnityEngine;

// Receives blast damage and carves or splits a mesh object into physical fragments.
[AddComponentMenu("Arena/Destructible Object")]
public sealed class DestructibleObject : MonoBehaviour, IBlastReceiver
{
    public enum DestructionBehavior { Carve, CarveAndFragment }
    [SerializeField] private DestructionBehavior behavior = DestructionBehavior.Carve;

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
    private List<List<Vector2>> carvedPieces;
    private readonly List<List<Vector2>> meshCutters = new List<List<Vector2>>();
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
        carvedPieces = new List<List<Vector2>> { BoundsPolygon(originalBounds) };
        foreach (Renderer renderer in rockRenderers)
        {
            if (renderer.sharedMaterial != null)
            {
                rockMaterial = renderer.sharedMaterial;
                break;
            }
        }
    }

    public void ReceiveBlast(BlastPayload blast)
    {
        if (broken || rockCollider == null || !rockCollider.enabled) return;

        Vector2 center = blast.Center;
        Vector3 closestPoint = rockCollider.ClosestPoint(new Vector3(center.x, center.y, originalBounds.center.z));
        Vector2 closestPointXY = new Vector2(closestPoint.x, closestPoint.y);
        float distance = Vector2.Distance(center, closestPointXY);
        if (distance > blast.OuterRadius) return;

        var cutter = CreateCircle(center, blast.OuterRadius, 32);
        meshCutters.Add(cutter);

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
            CreateMeshFragment(center, blast.Impulse);
        if (fragmentOwner != null) Destroy(gameObject);
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
        carvedPieces = new List<List<Vector2>> { BoundsPolygon(originalBounds) };
        meshCutters.Clear();
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

    private static List<Vector2> BoundsPolygon(Bounds bounds) => new List<Vector2>
    {
        new Vector2(bounds.min.x, bounds.min.y), new Vector2(bounds.max.x, bounds.min.y),
        new Vector2(bounds.max.x, bounds.max.y), new Vector2(bounds.min.x, bounds.max.y)
    };

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
                foreach (List<Vector2> cutter in meshCutters)
                {
                    var nextPieces = new List<List<CutVertex>>();
                    foreach (List<CutVertex> sourcePiece in pieces) SubtractCutter(sourcePiece, cutter, nextPieces);
                    pieces = nextPieces;
                    if (pieces.Count == 0) break;
                }
                foreach (List<CutVertex> survivingPiece in pieces)
                {
                    if (survivingPiece.Count < 3) continue;
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
        if (generatedMesh == null) generatedMesh = new Mesh { name = "Carved Destructible Object" };
        generatedMesh.Clear();
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

    // Keep each outside slice while clipping the remaining polygon through every cutter edge.
    private void AddOutsidePieces(List<Vector2> piece, List<Vector2> cutter, List<List<Vector2>> output)
    {
        var remaining = piece;
        for (int edge = 0; edge < cutter.Count && remaining.Count >= 3; edge++)
        {
            Vector2 a = cutter[edge];
            Vector2 b = cutter[(edge + 1) % cutter.Count];
            List<Vector2> outside = Clip(remaining, a, b, false);
            if (outside.Count >= 3 && Mathf.Abs(Area(outside)) > Epsilon)
                output.Add(outside);
            remaining = Clip(remaining, a, b, true);
        }
    }

    // Extrude a surviving polygon into a convex physics fragment and push it away from the blast.
    private void CreateFragment(List<Vector2> polygon, Vector2 center, float radius, float impulse)
    {
        var fragment = new GameObject("Rock Fragment");
        fragment.transform.position = Vector3.zero;
        var mesh = new Mesh { name = "Rock Fragment Mesh" };
        var vertices = new List<Vector3>();
        var triangles = new List<int>();
        float front = originalBounds.min.z;
        float back = originalBounds.max.z;
        foreach (Vector2 point in polygon) vertices.Add(new Vector3(point.x, point.y, front));
        foreach (Vector2 point in polygon) vertices.Add(new Vector3(point.x, point.y, back));
        for (int i = 1; i < polygon.Count - 1; i++)
        {
            triangles.Add(0); triangles.Add(i + 1); triangles.Add(i);
            triangles.Add(polygon.Count); triangles.Add(polygon.Count + i); triangles.Add(polygon.Count + i + 1);
        }
        for (int i = 0; i < polygon.Count; i++)
        {
            int next = (i + 1) % polygon.Count;
            int frontA = vertices.Count;
            vertices.Add(new Vector3(polygon[i].x, polygon[i].y, front));
            vertices.Add(new Vector3(polygon[next].x, polygon[next].y, front));
            vertices.Add(new Vector3(polygon[next].x, polygon[next].y, back));
            vertices.Add(new Vector3(polygon[i].x, polygon[i].y, back));
            triangles.Add(frontA); triangles.Add(frontA + 1); triangles.Add(frontA + 2);
            triangles.Add(frontA); triangles.Add(frontA + 2); triangles.Add(frontA + 3);
        }
        mesh.SetVertices(vertices);
        mesh.SetTriangles(triangles, 0);
        mesh.RecalculateNormals();
        mesh.RecalculateBounds();

        var filter = fragment.AddComponent<MeshFilter>();
        filter.sharedMesh = mesh;
        var renderer = fragment.AddComponent<MeshRenderer>();
        renderer.sharedMaterial = rockMaterial;
        var collider = fragment.AddComponent<MeshCollider>();
        collider.sharedMesh = mesh;
        collider.convex = true;
        var receiver = fragment.AddComponent<DestructibleObject>();
        receiver.fragmentOwner = fragmentOwner != null ? fragmentOwner : this;
        ActiveFragments.Add(receiver);
        var body = fragment.AddComponent<Rigidbody>();
        body.mass = Mathf.Max(0.1f, Mathf.Abs(Area(polygon)) * 0.2f);
        body.constraints = RigidbodyConstraints.FreezePositionZ
            | RigidbodyConstraints.FreezeRotationX
            | RigidbodyConstraints.FreezeRotationY;
        Vector2 direction = ((Vector2)polygon[0] - center).normalized;
        if (direction.sqrMagnitude < Epsilon) direction = Vector2.up;
        body.AddForce(new Vector3(direction.x, direction.y, 0f) * impulse, ForceMode.Impulse);
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

    private void CreateMeshFragment(Vector2 center, float impulse)
    {
        Transform sourceTransform = rockFilter.transform;
        var fragment = new GameObject("Rock Mesh Fragment");
        fragment.transform.SetPositionAndRotation(sourceTransform.position, sourceTransform.rotation);
        fragment.transform.localScale = sourceTransform.lossyScale;
        fragment.AddComponent<MeshFilter>().sharedMesh = generatedMesh;
        var renderer = fragment.AddComponent<MeshRenderer>();
        MeshRenderer sourceRenderer = rockFilter.GetComponent<MeshRenderer>();
        if (sourceRenderer == null) sourceRenderer = GetComponentInChildren<MeshRenderer>(true);
        if (sourceRenderer != null) renderer.sharedMaterials = sourceRenderer.sharedMaterials;
        var collider = fragment.AddComponent<MeshCollider>();
        collider.sharedMesh = generatedMesh;
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

    private static List<Vector2> Clip(List<Vector2> polygon, Vector2 a, Vector2 b, bool inside)
    {
        var output = new List<Vector2>();
        Vector2 previous = polygon[polygon.Count - 1];
        float previousDistance = Cross(b - a, previous - a);
        bool previousKept = inside ? previousDistance >= 0f : previousDistance <= 0f;
        foreach (Vector2 current in polygon)
        {
            float distance = Cross(b - a, current - a);
            bool kept = inside ? distance >= 0f : distance <= 0f;
            if (kept != previousKept)
                AddUnique(output, Vector2.Lerp(previous, current, previousDistance / (previousDistance - distance)));
            if (kept) AddUnique(output, current);
            previous = current;
            previousDistance = distance;
            previousKept = kept;
        }
        if (output.Count > 1 && (output[0] - output[output.Count - 1]).sqrMagnitude < Epsilon * Epsilon)
            output.RemoveAt(output.Count - 1);
        return output;
    }

    private static void AddUnique(List<Vector2> points, Vector2 point)
    {
        if (points.Count == 0 || (points[points.Count - 1] - point).sqrMagnitude > Epsilon * Epsilon)
            points.Add(point);
    }

    private static float Cross(Vector2 a, Vector2 b) => a.x * b.y - a.y * b.x;

    private static float Area(List<Vector2> polygon)
    {
        float area = 0f;
        for (int i = 0; i < polygon.Count; i++) area += Cross(polygon[i], polygon[(i + 1) % polygon.Count]);
        return area * 0.5f;
    }

    private void OnDestroy()
    {
        ActiveFragments.Remove(this);
        if (Application.isPlaying && generatedMesh != null) Destroy(generatedMesh);
    }
}
