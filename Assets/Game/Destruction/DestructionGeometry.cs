using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    public sealed class DestructionRequest
    {
        public DestructionRequest(MaterialEntityId targetId, CanonicalPolygon2D worldCutter,
            Vector2 impulseOrigin, float impulseSpeed)
        {
            TargetId = targetId;
            WorldCutter = worldCutter;
            ImpulseOrigin = impulseOrigin;
            ImpulseSpeed = Mathf.Max(0f, impulseSpeed);
        }

        public MaterialEntityId TargetId { get; }
        public CanonicalPolygon2D WorldCutter { get; }
        public Vector2 ImpulseOrigin { get; }
        public float ImpulseSpeed { get; }
    }

    public sealed class GeometryEvaluationResult
    {
        private GeometryEvaluationResult(bool succeeded, bool changed,
            IReadOnlyList<CanonicalMaterialShape> connectedResults, string error)
        {
            Succeeded = succeeded;
            Changed = changed;
            ConnectedResults = connectedResults ?? Array.Empty<CanonicalMaterialShape>();
            Error = error;
        }

        public bool Succeeded { get; }
        public bool Changed { get; }
        public IReadOnlyList<CanonicalMaterialShape> ConnectedResults { get; }
        public string Error { get; }

        public static GeometryEvaluationResult Success(bool changed, IReadOnlyList<CanonicalMaterialShape> results)
            => new GeometryEvaluationResult(true, changed, results, null);

        public static GeometryEvaluationResult Failure(string error)
            => new GeometryEvaluationResult(false, false, Array.Empty<CanonicalMaterialShape>(), error);
    }

    public interface IDestructionGeometryEvaluator
    {
        GeometryEvaluationResult Evaluate(CanonicalMaterialState source, DestructionRequest request);
    }

    public sealed class ConvexSubtractionGeometryEvaluator : IDestructionGeometryEvaluator
    {
        private const float Epsilon = 0.00001f;
        private readonly float minimumRetainedCellArea;

        public ConvexSubtractionGeometryEvaluator(float minimumRetainedCellArea = 0.01f)
        {
            this.minimumRetainedCellArea = Mathf.Max(Epsilon, minimumRetainedCellArea);
        }

        public GeometryEvaluationResult Evaluate(CanonicalMaterialState source, DestructionRequest request)
        {
            if (source == null) return GeometryEvaluationResult.Failure("The destruction source is missing.");
            if (request == null) return GeometryEvaluationResult.Failure("The destruction request is missing.");
            if (request.WorldCutter == null) return GeometryEvaluationResult.Failure("The destruction cutter is missing.");
            if (!request.WorldCutter.TryValidate(out string cutterError))
                return GeometryEvaluationResult.Failure("The destruction cutter is invalid. " + cutterError);
            if (request.TargetId != source.Id)
                return GeometryEvaluationResult.Failure("The destruction request target does not match its source state.");

            CanonicalPolygon2D localCutter;
            try
            {
                var localPoints = new Vector2[request.WorldCutter.Vertices.Count];
                float cosine = Mathf.Cos(-source.RotationRadians);
                float sine = Mathf.Sin(-source.RotationRadians);
                for (int i = 0; i < localPoints.Length; i++)
                {
                    Vector2 translated = request.WorldCutter.Vertices[i] - source.Position;
                    localPoints[i] = new Vector2(
                        translated.x * cosine - translated.y * sine,
                        translated.x * sine + translated.y * cosine);
                }
                localCutter = new CanonicalPolygon2D(localPoints);
            }
            catch (Exception exception)
            {
                return GeometryEvaluationResult.Failure("Could not transform the cutter into material space: " + exception.Message);
            }

            var remainingCells = new List<CanonicalPolygon2D>();
            try
            {
                foreach (CanonicalPolygon2D cell in source.Shape.Cells)
                    SubtractConvex(cell.CopyVertices().ToList(), localCutter.CopyVertices().ToList(),
                        remainingCells, minimumRetainedCellArea);
            }
            catch (Exception exception)
            {
                return GeometryEvaluationResult.Failure("Polygon subtraction failed: " + exception.Message);
            }

            float remainingArea = remainingCells.Sum(cell => cell.Area);
            bool changed = source.Shape.Area - remainingArea > Epsilon;
            if (!changed)
                return GeometryEvaluationResult.Success(false, new[] { source.Shape });
            if (remainingCells.Count == 0)
                return GeometryEvaluationResult.Success(true, Array.Empty<CanonicalMaterialShape>());

            IReadOnlyList<CanonicalMaterialShape> connected = PolygonConnectivity.GroupConnected(remainingCells);
            foreach (CanonicalMaterialShape shape in connected)
            {
                if (!shape.TryValidate(out string error))
                    return GeometryEvaluationResult.Failure("Subtraction produced invalid canonical geometry: " + error);
            }
            return GeometryEvaluationResult.Success(true, connected);
        }

        private static void SubtractConvex(List<Vector2> subject, List<Vector2> cutter,
            ICollection<CanonicalPolygon2D> output, float minimumArea)
        {
            List<Vector2> remaining = subject;
            for (int edge = 0; edge < cutter.Count && remaining.Count >= 3; edge++)
            {
                Vector2 a = cutter[edge];
                Vector2 b = cutter[(edge + 1) % cutter.Count];
                List<Vector2> outside = Clip(remaining, a, b, false);
                AddCellIfValid(outside, output, minimumArea);
                remaining = Clip(remaining, a, b, true);
            }
        }

        private static void AddCellIfValid(IReadOnlyList<Vector2> points, ICollection<CanonicalPolygon2D> output,
            float minimumArea)
        {
            if (points.Count < 3) return;
            var polygon = new CanonicalPolygon2D(points);
            // Preserve the existing rock cleanup policy while keeping it replaceable at this boundary.
            if (polygon.Area > minimumArea) output.Add(polygon);
        }

        private static List<Vector2> Clip(IReadOnlyList<Vector2> polygon, Vector2 a, Vector2 b, bool inside)
        {
            var output = new List<Vector2>();
            if (polygon.Count == 0) return output;
            Vector2 previous = polygon[polygon.Count - 1];
            float previousDistance = CanonicalPolygon2D.Cross(b - a, previous - a);
            bool previousKept = inside ? previousDistance >= -Epsilon : previousDistance <= Epsilon;
            for (int i = 0; i < polygon.Count; i++)
            {
                Vector2 current = polygon[i];
                float distance = CanonicalPolygon2D.Cross(b - a, current - a);
                bool kept = inside ? distance >= -Epsilon : distance <= Epsilon;
                if (kept != previousKept)
                {
                    float denominator = previousDistance - distance;
                    if (Mathf.Abs(denominator) > Epsilon)
                        AddUnique(output, Vector2.Lerp(previous, current, previousDistance / denominator));
                }
                if (kept) AddUnique(output, current);
                previous = current;
                previousDistance = distance;
                previousKept = kept;
            }

            if (output.Count > 1 && (output[0] - output[output.Count - 1]).sqrMagnitude <= Epsilon * Epsilon)
                output.RemoveAt(output.Count - 1);
            RemoveCollinear(output);
            return output;
        }

        private static void AddUnique(ICollection<Vector2> output, Vector2 point)
        {
            if (output.Count == 0 || (output.Last() - point).sqrMagnitude > Epsilon * Epsilon)
                output.Add(point);
        }

        private static void RemoveCollinear(List<Vector2> points)
        {
            for (int i = points.Count - 1; i >= 0 && points.Count >= 3; i--)
            {
                Vector2 before = points[(i + points.Count - 1) % points.Count];
                Vector2 after = points[(i + 1) % points.Count];
                Vector2 span = after - before;
                if (Mathf.Abs(CanonicalPolygon2D.Cross(span, points[i] - before)) <= Epsilon * Mathf.Max(1f, span.magnitude))
                    points.RemoveAt(i);
            }
        }
    }

    internal static class PolygonConnectivity
    {
        private const float Epsilon = 0.0001f;

        public static bool IsConnected(IReadOnlyList<CanonicalPolygon2D> cells)
            => cells != null && cells.Count > 0 && GroupConnected(cells).Count == 1;

        public static IReadOnlyList<CanonicalMaterialShape> GroupConnected(IReadOnlyList<CanonicalPolygon2D> cells)
        {
            var results = new List<CanonicalMaterialShape>();
            if (cells == null || cells.Count == 0) return results;
            var visited = new bool[cells.Count];
            for (int seed = 0; seed < cells.Count; seed++)
            {
                if (visited[seed]) continue;
                var group = new List<CanonicalPolygon2D>();
                var queue = new Queue<int>();
                queue.Enqueue(seed);
                visited[seed] = true;
                while (queue.Count > 0)
                {
                    int current = queue.Dequeue();
                    group.Add(cells[current]);
                    for (int candidate = 0; candidate < cells.Count; candidate++)
                    {
                        if (visited[candidate] || !Touch(cells[current], cells[candidate])) continue;
                        visited[candidate] = true;
                        queue.Enqueue(candidate);
                    }
                }
                results.Add(new CanonicalMaterialShape(group));
            }
            return results;
        }

        private static bool Touch(CanonicalPolygon2D left, CanonicalPolygon2D right)
        {
            IReadOnlyList<Vector2> a = left.Vertices;
            IReadOnlyList<Vector2> b = right.Vertices;
            for (int i = 0; i < a.Count; i++)
            for (int j = 0; j < b.Count; j++)
            {
                if (SegmentsTouch(a[i], a[(i + 1) % a.Count], b[j], b[(j + 1) % b.Count])) return true;
            }
            return false;
        }

        private static bool SegmentsTouch(Vector2 a, Vector2 b, Vector2 c, Vector2 d)
        {
            Vector2 ab = b - a;
            float cSide = CanonicalPolygon2D.Cross(ab, c - a);
            float dSide = CanonicalPolygon2D.Cross(ab, d - a);
            Vector2 cd = d - c;
            float aSide = CanonicalPolygon2D.Cross(cd, a - c);
            float bSide = CanonicalPolygon2D.Cross(cd, b - c);
            if ((cSide > Epsilon && dSide > Epsilon) || (cSide < -Epsilon && dSide < -Epsilon)
                || (aSide > Epsilon && bSide > Epsilon) || (aSide < -Epsilon && bSide < -Epsilon))
                return false;

            float minAx = Mathf.Min(a.x, b.x) - Epsilon;
            float maxAx = Mathf.Max(a.x, b.x) + Epsilon;
            float minAy = Mathf.Min(a.y, b.y) - Epsilon;
            float maxAy = Mathf.Max(a.y, b.y) + Epsilon;
            float minCx = Mathf.Min(c.x, d.x) - Epsilon;
            float maxCx = Mathf.Max(c.x, d.x) + Epsilon;
            float minCy = Mathf.Min(c.y, d.y) - Epsilon;
            float maxCy = Mathf.Max(c.y, d.y) + Epsilon;
            return maxAx >= minCx && maxCx >= minAx && maxAy >= minCy && maxCy >= minAy;
        }
    }
}
