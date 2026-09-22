using System.Collections.Generic;
using UnityEngine;

[AddComponentMenu("Arena/Destructible Rock")]
public sealed class DestructibleRock : MonoBehaviour, IBlastReceiver
{
    private const float Epsilon = 0.00001f;
    private Collider rockCollider;
    private Renderer[] rockRenderers;
    private Bounds originalBounds;
    private Material rockMaterial;
    private static readonly HashSet<DestructibleRock> ActiveFragments = new HashSet<DestructibleRock>();
    private DestructibleRock fragmentOwner;
    private bool broken;

    private void Awake()
    {
        rockRenderers = GetComponentsInChildren<Renderer>(true);
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
        foreach (Collider candidate in colliders)
        {
            if (candidate != rockCollider && candidate is MeshCollider mesh && mesh.sharedMesh == null)
                candidate.enabled = false;
        }
        if (rockCollider == null) return;
        originalBounds = rockCollider.bounds;
        foreach (Renderer renderer in rockRenderers)
        {
            if (renderer.sharedMaterial != null)
            {
                rockMaterial = renderer.sharedMaterial;
                break;
            }
        }
    }

    public void ReceiveBlast(Vector2 center, float radius)
    {
        if (broken || rockCollider == null || !rockCollider.enabled) return;

        Vector3 closestPoint = rockCollider.ClosestPoint(new Vector3(center.x, center.y, originalBounds.center.z));
        Vector2 closestPointXY = new Vector2(closestPoint.x, closestPoint.y);
        if (Vector2.Distance(center, closestPointXY) > radius) return;

        var cutter = CreateCircle(center, radius, 24);
        var pieces = new List<List<Vector2>>
        {
            new List<Vector2>
            {
                new Vector2(originalBounds.min.x, originalBounds.min.y),
                new Vector2(originalBounds.max.x, originalBounds.min.y),
                new Vector2(originalBounds.max.x, originalBounds.max.y),
                new Vector2(originalBounds.min.x, originalBounds.max.y)
            }
        };
        var remainingPieces = new List<List<Vector2>>();
        foreach (List<Vector2> piece in pieces)
            AddOutsidePieces(piece, cutter, remainingPieces);

        broken = true;
        rockCollider.enabled = false;
        foreach (Renderer renderer in rockRenderers) renderer.enabled = false;
        foreach (List<Vector2> piece in remainingPieces)
        {
            if (Mathf.Abs(Area(piece)) <= 0.01f) continue;
            CreateFragment(piece, center, radius);
        }
        if (fragmentOwner != null) Destroy(gameObject);
    }

    public void ResetRock()
    {
        var fragmentsToDestroy = new List<DestructibleRock>();
        foreach (DestructibleRock fragment in ActiveFragments)
        {
            if (fragment != null && fragment.fragmentOwner == this)
                fragmentsToDestroy.Add(fragment);
        }
        foreach (DestructibleRock fragment in fragmentsToDestroy)
            Destroy(fragment.gameObject);
        broken = false;
        if (rockCollider != null) rockCollider.enabled = true;
        foreach (Renderer renderer in rockRenderers) renderer.enabled = true;
    }

    public static void ResetAllRocks()
    {
        DestructibleRock[] rocks = FindObjectsByType<DestructibleRock>(FindObjectsInactive.Include, FindObjectsSortMode.None);
        foreach (DestructibleRock rock in rocks)
        {
            if (rock.fragmentOwner == null)
                rock.ResetRock();
        }
    }

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

    private void CreateFragment(List<Vector2> polygon, Vector2 center, float radius)
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
        var receiver = fragment.AddComponent<DestructibleRock>();
        receiver.fragmentOwner = fragmentOwner != null ? fragmentOwner : this;
        ActiveFragments.Add(receiver);
        var body = fragment.AddComponent<Rigidbody>();
        body.mass = Mathf.Max(0.1f, Mathf.Abs(Area(polygon)) * 0.2f);
        body.constraints = RigidbodyConstraints.FreezePositionZ
            | RigidbodyConstraints.FreezeRotationX
            | RigidbodyConstraints.FreezeRotationY;
        Vector2 direction = ((Vector2)polygon[0] - center).normalized;
        if (direction.sqrMagnitude < Epsilon) direction = Vector2.up;
        body.AddForce(new Vector3(direction.x, direction.y, 0f) * radius * 2f, ForceMode.Impulse);
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
    }
}
