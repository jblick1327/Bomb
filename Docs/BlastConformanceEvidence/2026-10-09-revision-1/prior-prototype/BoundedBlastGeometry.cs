using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    internal static class BoundedBlastGeometry
    {
        // Same convex half-plane backend, one batch. Positive-area retained cells
        // are never removed by the old per-cut cleanup threshold.
        public static GeometryEvaluationResult Evaluate(CanonicalMaterialState source, BoundedBlastField field, float minimumArea)
        {
            if (source == null || field == null) return GeometryEvaluationResult.Failure("Missing blast source/field.");
            var pieces = new List<List<BlastPoint>>();
            double originalArea = 0;
            var origin = BlastMath.Local(source, BlastPoint.Zero, field.Origin);
            foreach (var cell in source.Shape.Cells)
            {
                var polygon = cell.Vertices.Select(p => new BlastPoint(p.x, p.y)).ToList();
                originalArea += BlastMath.Area(polygon);
                foreach (var sector in field.Sectors)
                {
                    var rayA = BlastMath.Local(source, BlastPoint.Direction(sector.A), field.Origin);
                    var rayB = BlastMath.Local(source, BlastPoint.Direction(sector.B), field.Origin);
                    var part = BlastMath.Clip(polygon, origin, rayA, true);
                    part = BlastMath.Clip(part, origin, rayB, false);
                    var a = BlastMath.Local(source, BlastPoint.Direction(sector.A) * sector.Left, field.Origin);
                    var b = BlastMath.Local(source, BlastPoint.Direction(sector.B) * sector.Right, field.Origin);
                    part = BlastMath.Clip(part, a, b, false);
                    if (part.Count >= 3 && BlastMath.Area(part) > 0) pieces.Add(part);
                }
            }
            double area = pieces.Sum(p => BlastMath.Area(p));
            if (area > originalArea + BlastMath.Roundoff) return GeometryEvaluationResult.Failure("Blast partition increased source area.");
            if (originalArea - area <= BlastMath.Roundoff) return GeometryEvaluationResult.Success(false, new[] { source.Shape });
            Merge(pieces);
            var cells = new List<CanonicalPolygon2D>();
            foreach (var piece in pieces)
            {
                var points = piece.Select(p => new Vector2((float)p.X, (float)p.Y)).ToArray();
                for (int i = 0; i < points.Length; i++)
                {
                    double drift = (BlastMath.World(source, points[i], field.Origin) - BlastMath.WorldPoint(source, piece[i], field.Origin)).Length;
                    field.Diagnostics.maximumFloatError = Math.Max(field.Diagnostics.maximumFloatError, drift);
                    if (drift > BoundedBlastEvaluator.FloatAllowance) return GeometryEvaluationResult.Failure("Blast float conversion exceeds 0.05 mm.");
                }
                var polygon = new CanonicalPolygon2D(points);
                bool valid = polygon.TryValidate(out var validation);
                if (polygon.Area <= minimumArea || !valid)
                    return GeometryEvaluationResult.Failure("Lossless blast partition cannot represent a retained cell: area="
                        + polygon.Area.ToString("R") + ", selected minimum=" + minimumArea.ToString("R")
                        + ", vertices=" + points.Length + ", minimum edge="
                        + piece.Select((p,i) => (p-piece[(i+1)%piece.Count]).Length).Min().ToString("R")
                        + ", canonical validation=" + validation + ".");
                cells.Add(polygon);
            }
            var connected = PolygonConnectivity.GroupConnected(cells);
            foreach (var shape in connected)
            {
                if (shape.Cells.Count > 512) return GeometryEvaluationResult.Failure("Blast result exceeds 512 canonical cells.");
                if (!shape.TryValidate(out var error)) return GeometryEvaluationResult.Failure("Invalid blast result: " + error);
            }
            field.Diagnostics.resultCells += cells.Count;
            return GeometryEvaluationResult.Success(true, connected);
        }
        private static void Merge(List<List<BlastPoint>> pieces)
        {
            bool changed;
            do
            {
                changed = false;
                for (int i = 0; i < pieces.Count; i++) for (int j = i + 1; j < pieces.Count; j++)
                {
                    if (!ShareSegment(pieces[i], pieces[j])) continue;
                    var hull = Hull(pieces[i].Concat(pieces[j]));
                    if (Math.Abs(BlastMath.Area(hull) - BlastMath.Area(pieces[i]) - BlastMath.Area(pieces[j])) > 1e-12) continue;
                    pieces[i] = hull; pieces.RemoveAt(j); changed = true; j = i;
                }
            } while (changed);
        }
        private static bool ShareSegment(List<BlastPoint> a, List<BlastPoint> b)
        {
            for (int i = 0; i < a.Count; i++) for (int j = 0; j < b.Count; j++)
            {
                var edge = a[(i + 1) % a.Count] - a[i]; double length = edge.Length;
                var c = b[j] - a[i]; var d = b[(j + 1) % b.Count] - a[i];
                if (Math.Abs(BlastPoint.Cross(edge, c)) / length > 1e-12 || Math.Abs(BlastPoint.Cross(edge, d)) / length > 1e-12) continue;
                double tc = BlastPoint.Dot(edge, c) / length, td = BlastPoint.Dot(edge, d) / length;
                if (Math.Min(length, Math.Max(tc, td)) - Math.Max(0, Math.Min(tc, td)) > 1e-10) return true;
            }
            return false;
        }
        private static List<BlastPoint> Hull(IEnumerable<BlastPoint> input)
        {
            var points = input.OrderBy(p => p.X).ThenBy(p => p.Y).ToList(); var hull = new List<BlastPoint>();
            foreach (var p in points)
            {
                while (hull.Count >= 2 && BlastPoint.Cross(hull[hull.Count - 1] - hull[hull.Count - 2], p - hull[hull.Count - 1]) <= 0) hull.RemoveAt(hull.Count - 1);
                hull.Add(p);
            }
            int lower = hull.Count;
            for (int i = points.Count - 2; i >= 0; i--)
            {
                var p = points[i];
                while (hull.Count > lower && BlastPoint.Cross(hull[hull.Count - 1] - hull[hull.Count - 2], p - hull[hull.Count - 1]) <= 0) hull.RemoveAt(hull.Count - 1);
                hull.Add(p);
            }
            if (hull.Count > 1) hull.RemoveAt(hull.Count - 1);
            return BlastMath.Clean(hull);
        }
    }
}
