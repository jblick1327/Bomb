using System.Collections.Generic;
using System;
using UnityEngine;
using UnityEngine.Rendering;

[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer), typeof(MeshCollider))]
[AddComponentMenu("Arena/Destructible Ground")]
public sealed class DestructibleGround : MonoBehaviour
{
    [Header("Scene references")]
    [SerializeField, Tooltip("Ground bounds and extrusion depth come from Arena Layout.")]
    private ArenaLayout layout;

    private const float Epsilon = 0.00001f;
    private List<List<Vector2>> pieces = new List<List<Vector2>>();
    private Mesh generatedMesh;
    public int SolidPieceCount => pieces.Count;
    public int BoundaryEdgeCount { get; private set; }
    public int VertexCount => generatedMesh != null ? generatedMesh.vertexCount : 0;

    private void Awake() => ResetGround();

    public void ResetGround()
    {
        if (layout == null) layout = GetComponentInParent<ArenaLayout>();
        if (layout == null) throw new InvalidOperationException("Ground requires an ArenaLayout.");
        Rect bounds = layout.GroundRect;
        pieces = new List<List<Vector2>>
        {
            new List<Vector2>
            {
                new Vector2(bounds.xMin, bounds.yMin),
                new Vector2(bounds.xMax, bounds.yMin),
                new Vector2(bounds.xMax, bounds.yMax),
                new Vector2(bounds.xMin, bounds.yMax)
            }
        };
        RebuildMesh();
    }

    // Subtract a counterclockwise convex outline in world XY coordinates.
    // Splitting solid pieces preserves exact polygon edges, including overlapping craters.
    public void Carve(IReadOnlyList<Vector2> worldOutline)
    {
        if (worldOutline == null || worldOutline.Count < 3) return;
        var cutter = new List<Vector2>(worldOutline.Count);
        for (int i = 0; i < worldOutline.Count; i++)
            cutter.Add((Vector2)transform.InverseTransformPoint(new Vector3(worldOutline[i].x, worldOutline[i].y, transform.position.z)));
        if (Area(cutter) < 0f) cutter.Reverse();
        if (Mathf.Abs(Area(cutter)) < Epsilon) return;
        Rect cutterBounds = PolygonBounds(cutter);

        var next = new List<List<Vector2>>();
        bool changed = false;
        foreach (var piece in pieces)
        {
            if (!PolygonBounds(piece).Overlaps(cutterBounds))
            {
                next.Add(piece);
                continue;
            }
            var overlap = piece;
            for (int edge = 0; edge < cutter.Count && overlap.Count >= 3; edge++)
                overlap = Clip(overlap, cutter[edge], cutter[(edge + 1) % cutter.Count], true);
            if (overlap.Count < 3 || Mathf.Abs(Area(overlap)) < Epsilon)
            {
                next.Add(piece);
                continue;
            }

            changed = true;
            var remaining = piece;
            for (int edge = 0; edge < cutter.Count && remaining.Count >= 3; edge++)
            {
                Vector2 a = cutter[edge];
                Vector2 b = cutter[(edge + 1) % cutter.Count];
                var outside = Clip(remaining, a, b, false);
                if (outside.Count >= 3 && Mathf.Abs(Area(outside)) > Epsilon) next.Add(outside);
                remaining = Clip(remaining, a, b, true);
            }
        }

        if (!changed) return;
        pieces = next;
        RebuildMesh();
    }

    public bool ContainsSolid(Vector2 worldPoint)
    {
        Vector2 point = transform.InverseTransformPoint(new Vector3(worldPoint.x, worldPoint.y, transform.position.z));
        foreach (var piece in pieces)
        {
            bool inside = true;
            for (int edge = 0; edge < piece.Count; edge++)
            {
                if (Cross(piece[(edge + 1) % piece.Count] - piece[edge], point - piece[edge]) < -Epsilon)
                {
                    inside = false;
                    break;
                }
            }
            if (inside) return true;
        }
        return false;
    }

    private static List<Vector2> Clip(List<Vector2> polygon, Vector2 a, Vector2 b, bool inside)
    {
        var output = new List<Vector2>();
        if (polygon.Count == 0) return output;
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
        for (int i = output.Count - 1; i >= 0 && output.Count >= 3; i--)
        {
            Vector2 before = output[(i + output.Count - 1) % output.Count];
            Vector2 after = output[(i + 1) % output.Count];
            Vector2 span = after - before;
            if (Mathf.Abs(Cross(span, output[i] - before)) <= Epsilon * span.magnitude)
                output.RemoveAt(i);
        }
        return output;
    }

    private static void AddUnique(List<Vector2> points, Vector2 point)
    {
        if (points.Count == 0 || (points[points.Count - 1] - point).sqrMagnitude > Epsilon * Epsilon)
            points.Add(point);
    }

    private static float Cross(Vector2 a, Vector2 b) => a.x * b.y - a.y * b.x;

    private static Rect PolygonBounds(List<Vector2> polygon)
    {
        Vector2 min = polygon[0];
        Vector2 max = min;
        foreach (Vector2 point in polygon)
        {
            min = Vector2.Min(min, point);
            max = Vector2.Max(max, point);
        }
        return Rect.MinMaxRect(min.x, min.y, max.x, max.y);
    }

    private static float Area(List<Vector2> polygon)
    {
        float area = 0f;
        for (int i = 0; i < polygon.Count; i++) area += Cross(polygon[i], polygon[(i + 1) % polygon.Count]);
        return area * 0.5f;
    }

    private void RebuildMesh()
    {
        var vertices = new List<Vector3>();
        var triangles = new List<int>();
        float front = -layout.Depth * 0.5f;
        float back = layout.Depth * 0.5f;
        var lines = new Dictionary<(int, int), EdgeLine>();
        foreach (var polygon in pieces)
        {
            int start = vertices.Count;
            foreach (Vector2 point in polygon) vertices.Add(new Vector3(point.x, point.y, front));
            foreach (Vector2 point in polygon) vertices.Add(new Vector3(point.x, point.y, back));
            for (int i = 1; i < polygon.Count - 1; i++)
            {
                triangles.Add(start); triangles.Add(start + i + 1); triangles.Add(start + i);
                triangles.Add(start + polygon.Count); triangles.Add(start + polygon.Count + i); triangles.Add(start + polygon.Count + i + 1);
            }
            for (int i = 0; i < polygon.Count; i++)
            {
                Vector2 a = polygon[i];
                Vector2 b = polygon[(i + 1) % polygon.Count];
                AddEdge(lines, a, b);
            }
        }

        // Cancel shared edges, including partial edges at polygon T-junctions.
        // Only exposed contours get side faces in the render mesh and collider.
        BoundaryEdgeCount = 0;
        foreach (EdgeLine line in lines.Values)
        {
            line.Events.Sort((a, b) => a.Position.CompareTo(b.Position));
            int winding = 0;
            int eventIndex = 0;
            float previous = line.Events[0].Position;
            while (eventIndex < line.Events.Count)
            {
                float position = line.Events[eventIndex].Position;
                int nextWinding = winding;
                do
                {
                    nextWinding += line.Events[eventIndex].Winding;
                    eventIndex++;
                }
                while (eventIndex < line.Events.Count && line.Events[eventIndex].Position - position < Epsilon);
                bool contourChanged = Math.Sign(nextWinding) != Math.Sign(winding);
                if (contourChanged && winding != 0 && position - previous > Epsilon)
                {
                    Vector2 a = line.Direction * previous + line.Normal * line.Offset;
                    Vector2 b = line.Direction * position + line.Normal * line.Offset;
                    if (winding < 0) { Vector2 swap = a; a = b; b = swap; }
                    int edge = vertices.Count;
                    vertices.Add(new Vector3(a.x, a.y, front));
                    vertices.Add(new Vector3(b.x, b.y, front));
                    vertices.Add(new Vector3(b.x, b.y, back));
                    vertices.Add(new Vector3(a.x, a.y, back));
                    triangles.Add(edge); triangles.Add(edge + 1); triangles.Add(edge + 2);
                    triangles.Add(edge); triangles.Add(edge + 2); triangles.Add(edge + 3);
                    BoundaryEdgeCount++;
                }
                if (contourChanged) previous = position;
                winding = nextWinding;
            }
        }

        if (generatedMesh == null) generatedMesh = new Mesh { name = "Destructible Ground" };
        var collision = GetComponent<MeshCollider>();
        collision.sharedMesh = null;
        generatedMesh.Clear();
        generatedMesh.indexFormat = vertices.Count > 65535 ? IndexFormat.UInt32 : IndexFormat.UInt16;
        generatedMesh.SetVertices(vertices);
        generatedMesh.SetTriangles(triangles, 0);
        generatedMesh.RecalculateNormals();
        generatedMesh.RecalculateBounds();
        GetComponent<MeshFilter>().sharedMesh = generatedMesh;
        collision.sharedMesh = vertices.Count > 0 ? generatedMesh : null;
    }

    private void OnDestroy()
    {
        if (Application.isPlaying && generatedMesh != null) Destroy(generatedMesh);
    }

    private sealed class EdgeLine
    {
        public Vector2 Direction;
        public Vector2 Normal;
        public float Offset;
        public readonly List<EdgeEvent> Events = new List<EdgeEvent>();
    }

    private struct EdgeEvent
    {
        public float Position;
        public int Winding;
    }

    private static void AddEdge(Dictionary<(int, int), EdgeLine> lines, Vector2 a, Vector2 b)
    {
        Vector2 delta = b - a;
        if (delta.sqrMagnitude < Epsilon * Epsilon) return;
        Vector2 direction = delta.normalized;
        if (direction.x < -Epsilon || (Mathf.Abs(direction.x) <= Epsilon && direction.y < 0f)) direction = -direction;
        Vector2 normal = new Vector2(-direction.y, direction.x);
        float offset = Vector2.Dot(a, normal);
        int angleKey = Mathf.RoundToInt(Mathf.Atan2(direction.y, direction.x) * 10000f);
        int offsetKey = Mathf.RoundToInt(offset * 10000f);
        EdgeLine line = null;
        for (int angleStep = -1; angleStep <= 1 && line == null; angleStep++)
        for (int offsetStep = -1; offsetStep <= 1 && line == null; offsetStep++)
        {
            if (lines.TryGetValue((angleKey + angleStep, offsetKey + offsetStep), out EdgeLine candidate)
                && Vector2.Dot(candidate.Direction, direction) > 0.9999999f
                && Mathf.Abs(Vector2.Dot(a, candidate.Normal) - candidate.Offset) < 0.0002f
                && Mathf.Abs(Vector2.Dot(b, candidate.Normal) - candidate.Offset) < 0.0002f)
                line = candidate;
        }
        if (line == null)
        {
            line = new EdgeLine { Direction = direction, Normal = normal, Offset = offset };
            // A rare quantization collision must not merge distinct contour lines.
            while (lines.ContainsKey((angleKey, offsetKey))) offsetKey++;
            lines.Add((angleKey, offsetKey), line);
        }
        float start = Vector2.Dot(a, line.Direction);
        float end = Vector2.Dot(b, line.Direction);
        int winding = end > start ? 1 : -1;
        line.Events.Add(new EdgeEvent { Position = Mathf.Min(start, end), Winding = winding });
        line.Events.Add(new EdgeEvent { Position = Mathf.Max(start, end), Winding = -winding });
    }
}
