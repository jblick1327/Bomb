using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    public static class CanonicalGeometry
    {
        public const float ClipTolerance = 0.00001f;
        public const float ConnectivityTolerance = 0.0001f;
        public static Vector2 Rotate(Vector2 p, float radians)
        { float c = Mathf.Cos(radians), s = Mathf.Sin(radians); return new Vector2(c * p.x - s * p.y, s * p.x + c * p.y); }
        public static Vector2 AngularVelocityAt(float omega, Vector2 radius) => new Vector2(-omega * radius.y, omega * radius.x);
        public static CanonicalMaterialShape Translate(CanonicalMaterialShape shape, Vector2 offset) =>
            new CanonicalMaterialShape(shape.Cells.Select(c => new CanonicalPolygon2D(c.Vertices.Select(p => p + offset))));
        public static bool Contains(CanonicalPolygon2D cell, Vector2 point, float tolerance = ClipTolerance)
        {
            for (int i = 0; i < cell.Vertices.Count; i++)
            {
                Vector2 a = cell.Vertices[i], b = cell.Vertices[(i + 1) % cell.Vertices.Count];
                if (CanonicalPolygon2D.Cross(b - a, point - a) < -tolerance * (b - a).magnitude) return false;
            }
            return true;
        }
        public static bool Contains(CanonicalMaterialShape shape, Vector2 point) => shape.Cells.Any(c => Contains(c, point));
        public static bool InteriorOverlap(CanonicalPolygon2D a, CanonicalPolygon2D b)
        {
            foreach (var polygon in new[] { a, b })
                for (int i = 0; i < polygon.Vertices.Count; i++)
                {
                    var edge = polygon.Vertices[(i + 1) % polygon.Vertices.Count] - polygon.Vertices[i];
                    var axis = new Vector2(-edge.y, edge.x).normalized;
                    float amin = a.Vertices.Min(p => Vector2.Dot(p, axis)), amax = a.Vertices.Max(p => Vector2.Dot(p, axis));
                    float bmin = b.Vertices.Min(p => Vector2.Dot(p, axis)), bmax = b.Vertices.Max(p => Vector2.Dot(p, axis));
                    if (Mathf.Min(amax, bmax) - Mathf.Max(amin, bmin) <= ClipTolerance) return false;
                }
            return true;
        }
        public static float Distance(CanonicalMaterialShape shape, Vector2 point)
        {
            if (Contains(shape, point)) return 0;
            return shape.Cells.Min(c => c.Vertices.Select((a, i) =>
                (ClosestOnSegment(a, c.Vertices[(i + 1) % c.Vertices.Count], point) - point).magnitude).Min());
        }
        public static Vector2 ClosestOnSegment(Vector2 a, Vector2 b, Vector2 point) =>
            a + (b - a) * Mathf.Clamp01(Vector2.Dot(point - a, b - a) / (b - a).sqrMagnitude);
        public static bool IsSurface(CanonicalMaterialShape shape, Vector2 point)
        {
            if (!Contains(shape, point)) return false;
            // At least one direction must leave the union; internal cell seams are not gameplay surfaces.
            for (int i = 0; i < 16; i++)
                if (!Contains(shape, point + Rotate(Vector2.right * 0.0005f, i * Mathf.PI / 8))) return true;
            return false;
        }
        public static bool TrySurfacePoint(CanonicalMaterialShape shape, Vector2 requested, float maxCorrection, out Vector2 point)
        {
            point = requested;
            float best = float.PositiveInfinity;
            foreach (var cell in shape.Cells)
                for (int i = 0; i < cell.Vertices.Count; i++)
                {
                    var candidate = ClosestOnSegment(cell.Vertices[i], cell.Vertices[(i + 1) % cell.Vertices.Count], requested);
                    float distance = (candidate - requested).magnitude;
                    if (distance < best && IsSurface(shape, candidate)) { best = distance; point = candidate; }
                }
            return best <= maxCorrection;
        }

        public readonly struct Interval
        {
            public Interval(float start, float end) { Start = start; End = end; }
            public float Start { get; }
            public float End { get; }
        }
        // Parameters refer to the authored, ordered segment. Pairing never depends on displaced body poses.
        public static IReadOnlyList<Interval> ClipSegment(CanonicalMaterialShape shape, Vector2 a, Vector2 b)
        {
            var intervals = new List<Interval>();
            foreach (var cell in shape.Cells)
            {
                float lo = 0, hi = 1;
                bool valid = true;
                for (int i = 0; i < cell.Vertices.Count; i++)
                {
                    Vector2 e0 = cell.Vertices[i], edge = cell.Vertices[(i + 1) % cell.Vertices.Count] - e0;
                    float origin = CanonicalPolygon2D.Cross(edge, a - e0), slope = CanonicalPolygon2D.Cross(edge, b - a);
                    if (Mathf.Abs(slope) < ClipTolerance) { if (origin < -ClipTolerance) valid = false; }
                    else if (slope > 0) lo = Mathf.Max(lo, -origin / slope);
                    else hi = Mathf.Min(hi, -origin / slope);
                }
                if (valid && hi - lo > ClipTolerance) intervals.Add(new Interval(lo, hi));
            }
            var merged = new List<Interval>();
            foreach (var interval in intervals.OrderBy(v => v.Start))
            {
                if (merged.Count == 0 || interval.Start > merged[merged.Count - 1].End + ClipTolerance) merged.Add(interval);
                else { var prior = merged[merged.Count - 1]; merged[merged.Count - 1] = new Interval(prior.Start, Mathf.Max(prior.End, interval.End)); }
            }
            return merged;
        }
    }
}
