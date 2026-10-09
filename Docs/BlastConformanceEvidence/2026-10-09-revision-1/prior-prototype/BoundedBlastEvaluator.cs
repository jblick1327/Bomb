using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    [Serializable]
    public sealed class BlastDiagnostics
    {
        public int candidateBodies, inputCells, sectors, resultCells;
        public double maximumReachEnclosure, maximumRadialDeficit, maximumFloatError;
    }

    // Calculation data for one explosion. It is never a canonical entity or snapshot dependency.
    public sealed class BoundedBlastField
    {
        internal readonly List<BlastInput> Inputs;
        internal readonly List<BlastSector> Sectors;
        private readonly HashSet<MaterialEntityId> exposed;
        public Vector2 Origin { get; }
        public double Radius { get; }
        public long OriginalGeneration { get; }
        public BlastDiagnostics Diagnostics { get; }
        internal BoundedBlastField(Vector2 origin, double radius, long generation, List<BlastInput> inputs,
            List<BlastSector> sectors, HashSet<MaterialEntityId> exposed, BlastDiagnostics diagnostics)
        { Origin = origin; Radius = radius; OriginalGeneration = generation; Inputs = inputs; Sectors = sectors;
            this.exposed = exposed; Diagnostics = diagnostics; }
        public bool IsExposed(MaterialEntityId character) => exposed.Contains(character);
        // A measurement of the represented inner cut, not an analytic expectation.
        public double RepresentedReach(double radians)
        {
            radians = BlastMath.Angle(radians);
            var sector = Sectors.First(s => radians >= s.A && radians <= s.B);
            var a = BlastPoint.Direction(sector.A) * sector.Left;
            var b = BlastPoint.Direction(sector.B) * sector.Right;
            var edge = b - a;
            return BlastPoint.Cross(edge, a) / BlastPoint.Cross(edge, BlastPoint.Direction(radians));
        }

        // Result vertices and old/new edge intersections partition all changes in radial ordering.
        // Within each open interval, a midpoint identifies that fixed ordering, rather than sampling
        // a finite set of unrelated paths. Even a tiny retained layer before removed core rejects.
        public bool TryValidateRemoval(IReadOnlyDictionary<MaterialEntityId, IReadOnlyList<CanonicalMaterialState>> replacements,
            out string error)
        {
            error = null;
            var after = new Dictionary<MaterialEntityId, List<BlastCell>>();
            var angles = new List<double> { 0, Math.PI * 0.5, Math.PI, Math.PI * 1.5, Math.PI * 2 };
            foreach (var input in Inputs)
            {
                foreach (var c in input.Cells) BlastMath.AddAngles(c.Points, angles);
                var results = replacements.TryGetValue(input.Body.Id, out var result) ? result : new[] { input.Body };
                var cells = results.SelectMany(b => b.Shape.Cells.Select(c => new BlastCell(c.Vertices
                    .Select(p => BlastMath.World(b, p, Origin)).ToArray()))).ToList();
                after.Add(input.Body.Id, cells);
                foreach (var c in cells)
                {
                    BlastMath.AddAngles(c.Points, angles);
                    foreach (var original in input.Cells) BlastMath.AddCrossingAngles(original.Points, c.Points, angles);
                }
            }
            var events = BlastMath.Events(angles);
            if (events.Count > 16384) { error = "Blast final continuity certificate exceeds its work budget."; return false; }
            for (int i = 0; i + 1 < events.Count; i++)
            {
                double theta = (events[i] + events[i + 1]) * 0.5;
                var spans = new List<(double lo, double hi, bool retained)>();
                foreach (var input in Inputs)
                {
                    var old = BlastMath.Spans(input.Cells, theta);
                    var current = BlastMath.Spans(after[input.Body.Id], theta);
                    foreach (var span in old)
                    {
                        double cursor = span.Lo;
                        foreach (var surviving in current.Where(s => s.Hi > span.Lo && s.Lo < span.Hi))
                        {
                            double lo = Math.Max(span.Lo, surviving.Lo), hi = Math.Min(span.Hi, surviving.Hi);
                            if (lo > cursor + BlastMath.Roundoff) spans.Add((cursor, lo, false));
                            if (hi > lo + BlastMath.Roundoff) spans.Add((lo, hi, true));
                            cursor = Math.Max(cursor, hi);
                        }
                        if (span.Hi > cursor + BlastMath.Roundoff) spans.Add((cursor, span.Hi, false));
                    }
                }
                bool blocked = false;
                foreach (var span in spans.OrderBy(s => s.lo))
                {
                    if (span.retained) blocked = true;
                    else if (blocked)
                    { error = "Blast final geometry retains intervening material before removal at angle " + theta.ToString("R") + "."; return false; }
                }
            }
            return true;
        }
    }

    public static class BoundedBlastEvaluator
    {
        public const double InwardAllowance = 0.0001;
        public const double FloatAllowance = 0.00005;
        public const double MaximumDeficit = 0.001;
        public const int MaximumSectors = 4096;
        public static bool TryCreate(CanonicalMaterialWorld world, CanonicalMaterialState bomb,
            out BoundedBlastField field, out string error)
        {
            field = null; error = null;
            try
            {
                if (world == null || bomb?.IsBomb != true) throw new InvalidOperationException("A selected live bomb is required.");
                var spec = world.Definitions.Resolve(bomb.Selection.Role);
                double radius = spec.blastRadius;
                if (radius < 0.25 || radius > 10 || Math.Abs(bomb.Position.x) > 64 || Math.Abs(bomb.Position.y) > 64)
                    throw new InvalidOperationException("Blast origin/radius is outside the reviewed numerical domain.");
                var inputs = new List<BlastInput>();
                var events = new List<double> { 0, Math.PI * 0.5, Math.PI, Math.PI * 1.5, Math.PI * 2 };
                var diagnostics = new BlastDiagnostics();
                foreach (var body in world.View.Bodies.Where(b => b.Id != bomb.Id).OrderBy(b => b.Id))
                {
                    if (CanonicalGeometry.Distance(body.Shape, body.ToLocal(bomb.Position)) > radius + FloatAllowance) continue;
                    if (body.Selection == null) throw new InvalidOperationException("Blast candidate lacks an authored material selection.");
                    var material = world.Definitions.Resolve(body.Selection.Material);
                    if (!material.hasBlastResistance || material.blastResistance < 0 || material.blastResistance > 16)
                        throw new InvalidOperationException("Blast resistance is missing or outside the reviewed 0–16 domain.");
                    var input = new BlastInput(body, material.blastResistance,
                        !world.Definitions.Resolve(body.Selection.Response).destructible, bomb.Position);
                    foreach (var cell in input.Cells)
                    {
                        if (cell.Points.Any(p => p.Length > 32)) throw new InvalidOperationException("Blast candidate vertices exceed 32 m relative bounds.");
                        if (BlastMath.Contains(cell.Points, BlastPoint.Zero)) throw new InvalidOperationException("Blast origin is inside another material body.");
                        BlastMath.AddAngles(cell.Points, events);
                    }
                    inputs.Add(input);
                    diagnostics.inputCells += input.Cells.Count;
                    if (Math.Abs(body.Position.x) > 64 || Math.Abs(body.Position.y) > 64)
                        throw new InvalidOperationException("Blast candidate pose exceeds absolute coordinate bounds.");
                }
                diagnostics.candidateBodies = inputs.Count;
                if (inputs.Count > 32 || diagnostics.inputCells > 128 || inputs.Sum(b => b.Cells.Sum(c => c.Points.Length)) > 1024)
                    throw new InvalidOperationException("Blast input work budget exceeded.");
                for (int i = 0; i < inputs.Count; i++) for (int j = i + 1; j < inputs.Count; j++)
                    foreach (var a in inputs[i].Cells) foreach (var b in inputs[j].Cells)
                        if (BlastMath.Area(BlastMath.Intersect(a.Points.ToList(), b.Points)) > BlastMath.Roundoff)
                            throw new InvalidOperationException("Overlapping original blast materials require an unaccepted composition policy.");
                var angles = BlastMath.Events(events);
                var sectors = new List<BlastSector>();
                var exposed = new HashSet<MaterialEntityId>();
                var ambiguous = new HashSet<MaterialEntityId>();
                for (int i = 0; i + 1 < angles.Count; i++)
                    Refine(inputs, radius, spec.blastPower >= 1, angles[i], angles[i + 1], 0, sectors, exposed, ambiguous);
                // Shared endpoints are lowered, never raised, so adjacent fan triangles join without
                // spurious radial teeth. True one-sided jumps retain independent endpoints.
                for (int pass = 0; ; pass++)
                {
                    JoinEndpoints(sectors, radius);
                    var split = sectors.Where(s => s.Upper - Math.Min(s.Left, s.Right) + radius * (1 - Math.Cos((s.B - s.A) / 2))
                        + FloatAllowance > MaximumDeficit).ToArray();
                    if (split.Length == 0) break;
                    if (pass >= 24) throw new InvalidOperationException("Blast shared-endpoint deficit cannot meet 1 mm.");
                    foreach (var sector in split)
                    {
                        int index = sectors.IndexOf(sector); sectors.RemoveAt(index);
                        var children = new List<BlastSector>();
                        Refine(inputs, radius, spec.blastPower >= 1, sector.A, sector.B, sector.Depth + 1, children, exposed, ambiguous, true);
                        sectors.InsertRange(index, children);
                    }
                    if (sectors.Count > MaximumSectors) throw new InvalidOperationException("Blast sector budget exceeded.");
                }
                if (ambiguous.Any(id => !exposed.Contains(id)))
                    throw new InvalidOperationException("Character exposure has only an unresolved boundary contact; no positive aperture was proved.");
                diagnostics.sectors = sectors.Count;
                diagnostics.maximumReachEnclosure = sectors.Max(s => s.Upper - s.Lower);
                diagnostics.maximumRadialDeficit = sectors.Max(s => s.Upper - Math.Min(s.Left, s.Right)
                    + radius * (1 - Math.Cos((s.B - s.A) / 2)) + FloatAllowance);
                field = new BoundedBlastField(bomb.Position, radius, world.Generation, inputs, sectors, exposed, diagnostics);
                return true;
            }
            catch (Exception exception) { error = "Bounded blast rejected: " + exception.Message; return false; }
        }

        private static void Refine(List<BlastInput> inputs, double radius, bool lethal, double a, double b, int depth,
            List<BlastSector> output, HashSet<MaterialEntityId> exposed, HashSet<MaterialEntityId> ambiguous, bool force = false)
        {
            var profiles = inputs.SelectMany(input => BlastMath.Spans(input.Cells, (a + b) / 2)
                .Select(span => new BlastProfile(input, span))).OrderBy(p => p.Span.Lo).ToList();
            foreach (var profile in profiles) profile.Bounds(a, b);
            double lower = Invert(profiles, radius, true), upper = Invert(profiles, radius, false);
            var opaque = profiles.Where(p => p.Input.Opaque).ToArray();
            if (opaque.Length > 0)
            { lower = Math.Min(lower, opaque.Min(p => p.Entry.Lo)); upper = Math.Min(upper, opaque.Min(p => p.Entry.Hi)); }
            lower = Math.Max(0, lower - InwardAllowance);
            var uncertainCharacters = new List<MaterialEntityId>();
            var witness = new List<MaterialEntityId>();
            foreach (var profile in profiles.Where(p => p.Input.Body.IsCharacter))
            {
                if (!lethal) continue;
                if (opaque.Any(p => p.Input.Body.Id != profile.Input.Body.Id && p.Span.Lo < profile.Span.Lo)) continue;
                double minCost = Cost(profiles, profile.Entry.Lo, false), maxCost = Cost(profiles, profile.Entry.Hi, true);
                if (maxCost < radius - InwardAllowance) witness.Add(profile.Input.Body.Id);
                else if (minCost <= radius + BlastMath.Roundoff && profile.Entry.Lo <= radius) uncertainCharacters.Add(profile.Input.Body.Id);
            }
            double sagitta = radius * (1 - Math.Cos((b - a) / 2));
            bool split = force || upper - lower > 0.0005 || sagitta > 0.00025;
            if (split)
            {
                if (depth >= 24) throw new InvalidOperationException("Blast reach/character boundary is unresolved at refinement depth 24.");
                Refine(inputs, radius, lethal, a, (a + b) / 2, depth + 1, output, exposed, ambiguous);
                Refine(inputs, radius, lethal, (a + b) / 2, b, depth + 1, output, exposed, ambiguous);
            }
            else
            {
                output.Add(new BlastSector(a, b, lower, upper, depth, profiles));
                foreach (var id in witness) exposed.Add(id);
                foreach (var id in uncertainCharacters) ambiguous.Add(id);
                if (output.Count > MaximumSectors) throw new InvalidOperationException("Blast sector budget exceeded at "
                    + output.Count + " sectors; current angle " + a.ToString("R") + ".." + b.ToString("R") + ".");
            }
        }
        private static double Cost(List<BlastProfile> profiles, double distance, bool upper)
        {
            double cost = distance;
            foreach (var p in profiles)
            {
                double entry = upper ? p.Entry.Lo : p.Entry.Hi, exit = upper ? p.Exit.Hi : p.Exit.Lo;
                cost += p.Input.Resistance * Math.Max(0, Math.Min(distance, exit) - entry);
            }
            return cost;
        }
        private static double Invert(List<BlastProfile> profiles, double radius, bool upperCost)
        {
            double lo = 0, hi = radius;
            for (int i = 0; i < 48; i++)
            { double mid = (lo + hi) / 2; if (Cost(profiles, mid, upperCost) <= radius) lo = mid; else hi = mid; }
            return upperCost ? lo : hi;
        }
        private static void JoinEndpoints(List<BlastSector> sectors, double radius)
        {
            foreach (var sector in sectors) sector.Left = sector.Right = sector.Lower;
            for (int i = 0; i < sectors.Count; i++)
            {
                var previous = sectors[(i + sectors.Count - 1) % sectors.Count]; var next = sectors[i];
                double theta = next.A;
                if (Math.Abs(ExactLimit(previous, theta, radius) - ExactLimit(next, theta, radius)) > 0.0000001) continue;
                previous.Right = next.Left = Math.Min(previous.Lower, next.Lower);
            }
        }
        private static double ExactLimit(BlastSector sector, double theta, double radius)
        {
            // One-sided active edges are retained from the open sector, including at a jump.
            var profiles = sector.Profiles.Select(p => p.At(theta)).ToList();
            double reach = Invert(profiles, radius, true);
            foreach (var p in profiles.Where(p => p.Input.Opaque)) reach = Math.Min(reach, p.Entry.Lo);
            return reach;
        }
    }

    internal readonly struct BlastPoint
    {
        public readonly double X, Y;
        public BlastPoint(double x, double y) { X = x; Y = y; }
        public double Length => Math.Sqrt(X * X + Y * Y);
        public static BlastPoint Zero => new BlastPoint(0, 0);
        public static BlastPoint Direction(double theta) => new BlastPoint(Math.Cos(theta), Math.Sin(theta));
        public static BlastPoint operator +(BlastPoint a, BlastPoint b) => new BlastPoint(a.X + b.X, a.Y + b.Y);
        public static BlastPoint operator -(BlastPoint a, BlastPoint b) => new BlastPoint(a.X - b.X, a.Y - b.Y);
        public static BlastPoint operator *(BlastPoint a, double k) => new BlastPoint(a.X * k, a.Y * k);
        public static double Dot(BlastPoint a, BlastPoint b) => a.X * b.X + a.Y * b.Y;
        public static double Cross(BlastPoint a, BlastPoint b) => a.X * b.Y - a.Y * b.X;
    }
    internal readonly struct BlastRange
    {
        public readonly double Lo, Hi;
        public BlastRange(double lo, double hi) { Lo = lo; Hi = hi; }
    }
    internal sealed class BlastCell
    {
        public readonly BlastPoint[] Points;
        public BlastCell(BlastPoint[] points) { Points = points; }
    }
    internal sealed class BlastInput
    {
        public readonly CanonicalMaterialState Body;
        public readonly double Resistance;
        public readonly bool Opaque;
        public readonly List<BlastCell> Cells;
        public BlastInput(CanonicalMaterialState body, double resistance, bool opaque, Vector2 origin)
        { Body = body; Resistance = resistance; Opaque = opaque;
            Cells = body.Shape.Cells.Select(c => new BlastCell(c.Vertices.Select(p => BlastMath.World(body, p, origin)).ToArray())).ToList(); }
    }
    internal sealed class BlastSpan
    {
        public double Lo, Hi;
        public BlastEdge Entry, Exit;
        public BlastSpan(double lo, double hi, BlastEdge entry, BlastEdge exit) { Lo = lo; Hi = hi; Entry = entry; Exit = exit; }
    }
    internal sealed class BlastEdge
    {
        private readonly BlastPoint normal;
        private readonly double height;
        public BlastEdge(BlastPoint a, BlastPoint b)
        { var edge = b - a; normal = new BlastPoint(-edge.Y, edge.X) * (1 / edge.Length); height = BlastPoint.Dot(normal, a); }
        public double At(double theta)
        {
            double denominator = BlastPoint.Dot(normal, BlastPoint.Direction(theta));
            if (Math.Abs(denominator) < 1e-15) return 32;
            return Math.Clamp(height / denominator, 0, 32);
        }
        public BlastRange Bounds(double a, double b)
        {
            double lo = Math.Min(BlastPoint.Dot(normal, BlastPoint.Direction(a)), BlastPoint.Dot(normal, BlastPoint.Direction(b)));
            double hi = Math.Max(BlastPoint.Dot(normal, BlastPoint.Direction(a)), BlastPoint.Dot(normal, BlastPoint.Direction(b)));
            double phase = BlastMath.Angle(Math.Atan2(normal.Y, normal.X));
            for (int k = -1; k <= 1; k++)
            {
                double maximum = phase + k * Math.PI * 2, minimum = maximum + Math.PI;
                if (maximum >= a && maximum <= b) hi = 1;
                if (minimum >= a && minimum <= b) lo = -1;
            }
            lo -= 1e-12; hi += 1e-12;
            if (lo <= 0 && hi >= 0) return new BlastRange(0, 32);
            double r0 = height / lo, r1 = height / hi;
            return new BlastRange(Math.Clamp(Math.Min(r0, r1) - BlastMath.Roundoff, 0, 32),
                Math.Clamp(Math.Max(r0, r1) + BlastMath.Roundoff, 0, 32));
        }
    }
    internal sealed class BlastProfile
    {
        public readonly BlastInput Input;
        public readonly BlastSpan Span;
        public BlastRange Entry, Exit;
        public BlastProfile(BlastInput input, BlastSpan span) { Input = input; Span = span; }
        public void Bounds(double a, double b)
        { Entry = Span.Entry?.Bounds(a, b) ?? new BlastRange(0, 0); Exit = Span.Exit?.Bounds(a, b) ?? new BlastRange(32, 32); }
        public BlastProfile At(double theta)
        { var result = new BlastProfile(Input, Span); double e = Span.Entry?.At(theta) ?? 0, x = Span.Exit?.At(theta) ?? 32;
            result.Entry = new BlastRange(e, e); result.Exit = new BlastRange(x, x); return result; }
    }
    internal sealed class BlastSector
    {
        public readonly double A, B, Lower, Upper;
        public readonly int Depth;
        public readonly List<BlastProfile> Profiles;
        public double Left, Right;
        public BlastSector(double a, double b, double lower, double upper, int depth, List<BlastProfile> profiles)
        { A = a; B = b; Lower = lower; Upper = upper; Depth = depth; Profiles = profiles; Left = Right = lower; }
    }

    internal static class BlastMath
    {
        // Arithmetic guard, distinct from the 50 micrometre conversion bound; never a cleanup area.
        public const double Roundoff = 1e-10;
        public static double Angle(double theta) { theta %= Math.PI * 2; return theta < 0 ? theta + Math.PI * 2 : theta; }
        public static BlastPoint World(CanonicalMaterialState body, Vector2 local, Vector2 origin)
            => WorldPoint(body, new BlastPoint(local.x, local.y), origin);
        public static BlastPoint WorldPoint(CanonicalMaterialState body, BlastPoint local, Vector2 origin)
        { double c = Mathf.Cos(body.RotationRadians), s = Mathf.Sin(body.RotationRadians);
            return new BlastPoint(body.Position.x - (double)origin.x + c * local.X - s * local.Y,
                body.Position.y - (double)origin.y + s * local.X + c * local.Y); }
        public static BlastPoint Local(CanonicalMaterialState body, BlastPoint world, Vector2 origin)
        { double c = Mathf.Cos(body.RotationRadians), s = Mathf.Sin(body.RotationRadians), determinant = c * c + s * s;
            var delta = world + new BlastPoint(origin.x - (double)body.Position.x, origin.y - (double)body.Position.y);
            return new BlastPoint((c * delta.X + s * delta.Y) / determinant, (-s * delta.X + c * delta.Y) / determinant); }
        public static void AddAngles(IEnumerable<BlastPoint> points, List<double> output)
        { foreach (var p in points) if (p.Length > Roundoff) output.Add(Angle(Math.Atan2(p.Y, p.X))); }
        public static List<double> Events(IEnumerable<double> angles)
        {
            var sorted = angles.OrderBy(a => a).ToList(); var result = new List<double>();
            foreach (var a in sorted) if (result.Count == 0 || a - result[result.Count - 1] > 1e-14) result.Add(a);
            return result;
        }
        public static bool Contains(IReadOnlyList<BlastPoint> polygon, BlastPoint point)
        { for (int i = 0; i < polygon.Count; i++) if (BlastPoint.Cross(polygon[(i + 1) % polygon.Count] - polygon[i], point - polygon[i]) < -Roundoff) return false; return true; }
        public static double Area(IReadOnlyList<BlastPoint> points)
        { double area = 0; for (int i = 0; i < points.Count; i++) area += BlastPoint.Cross(points[i], points[(i + 1) % points.Count]); return Math.Abs(area) / 2; }
        public static List<BlastPoint> Clip(IReadOnlyList<BlastPoint> points, BlastPoint a, BlastPoint b, bool inside)
        {
            var output = new List<BlastPoint>(); if (points.Count == 0) return output;
            var edge = b - a; double length = edge.Length; if (length <= 1e-15) throw new InvalidOperationException("Degenerate blast half-plane.");
            var previous = points[points.Count - 1]; double prior = BlastPoint.Cross(edge, previous - a) / length;
            bool keptPrior = inside ? prior >= 0 : prior <= 0;
            foreach (var current in points)
            {
                double distance = BlastPoint.Cross(edge, current - a) / length; bool kept = inside ? distance >= 0 : distance <= 0;
                if (kept != keptPrior) output.Add(previous + (current - previous) * (prior / (prior - distance)));
                if (kept) output.Add(current);
                previous = current; prior = distance; keptPrior = kept;
            }
            return Clean(output);
        }
        public static List<BlastPoint> Clean(List<BlastPoint> points)
        {
            for (int i = points.Count - 1; i >= 0 && points.Count > 1; i--)
                if ((points[i] - points[(i + 1) % points.Count]).Length <= 1e-12) points.RemoveAt(i);
            for (int i = points.Count - 1; i >= 0 && points.Count >= 3; i--)
            { var before = points[(i + points.Count - 1) % points.Count]; var after = points[(i + 1) % points.Count];
                if (Math.Abs(BlastPoint.Cross(after - before, points[i] - before)) <= 1e-12 * (after - before).Length) points.RemoveAt(i); }
            return points;
        }
        public static List<BlastPoint> Intersect(List<BlastPoint> subject, IReadOnlyList<BlastPoint> cutter)
        { for (int i = 0; i < cutter.Count && subject.Count >= 3; i++) subject = Clip(subject, cutter[i], cutter[(i + 1) % cutter.Count], true); return subject; }
        public static List<BlastSpan> Spans(IEnumerable<BlastCell> cells, double theta)
        {
            var result = new List<BlastSpan>(); var direction = BlastPoint.Direction(theta);
            foreach (var cell in cells)
            {
                double lo = 0, hi = double.PositiveInfinity; BlastEdge entry = null, exit = null; bool miss = false;
                for (int i = 0; i < cell.Points.Length; i++)
                {
                    var a = cell.Points[i]; var b = cell.Points[(i + 1) % cell.Points.Length]; var edge = b - a;
                    double denominator = BlastPoint.Cross(edge, direction), numerator = BlastPoint.Cross(edge, a);
                    if (Math.Abs(denominator) <= 1e-15) { if (numerator > 0) miss = true; continue; }
                    double t = numerator / denominator;
                    if (denominator > 0 && t > lo) { lo = t; entry = new BlastEdge(a, b); }
                    if (denominator < 0 && t < hi) { hi = t; exit = new BlastEdge(a, b); }
                }
                if (!miss && hi > lo + Roundoff && hi > 0) result.Add(new BlastSpan(Math.Max(0, lo), hi, entry, exit));
            }
            result.Sort((a, b) => a.Lo.CompareTo(b.Lo)); var merged = new List<BlastSpan>();
            foreach (var span in result)
            {
                if (merged.Count == 0 || span.Lo > merged[merged.Count - 1].Hi + Roundoff) merged.Add(span);
                else if (span.Hi > merged[merged.Count - 1].Hi)
                { merged[merged.Count - 1].Hi = span.Hi; merged[merged.Count - 1].Exit = span.Exit; }
            }
            return merged;
        }
        public static void AddCrossingAngles(IReadOnlyList<BlastPoint> a, IReadOnlyList<BlastPoint> b, List<double> angles)
        {
            for (int i = 0; i < a.Count; i++) for (int j = 0; j < b.Count; j++)
            {
                var p = a[i]; var q = b[j]; var r = a[(i + 1) % a.Count] - p; var s = b[(j + 1) % b.Count] - q;
                double denominator = BlastPoint.Cross(r, s); if (Math.Abs(denominator) < 1e-15) continue;
                double t = BlastPoint.Cross(q - p, s) / denominator, u = BlastPoint.Cross(q - p, r) / denominator;
                if (t >= 0 && t <= 1 && u >= 0 && u <= 1) AddAngles(new[] { p + r * t }, angles);
            }
        }
    }
}
