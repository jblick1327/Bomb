using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using UnityEngine;
using BigInteger = System.Numerics.BigInteger;

namespace Bomb.CanonicalDestruction
{
    [Serializable]
    public sealed class BlastDiagnostics
    {
        public int candidateBodies, inputCells, sectors, resultCells, certificateIntervals, halfPlaneClips;
        public double maximumReachEnclosure, maximumRadialDeficit, maximumFloatError;
        public double fieldMilliseconds, subtractionMilliseconds, continuityMilliseconds;
        public int exactFrameResults;
        public double maximumLocalComOffset;
        public int diagonalPairs, diagonalFlips, boundaryVertices;
        public int exactContinuityRays, coalescedSectors;
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
            var clock = Stopwatch.StartNew();
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
                var spans = new List<(double lo, double hi, bool retained, MaterialEntityId body)>();
                foreach (var input in Inputs)
                {
                    var old = BlastMath.Spans(input.Cells, theta, false);
                    var current = BlastMath.Spans(after[input.Body.Id], theta, false);
                    foreach (var span in old)
                    {
                        double cursor = span.Lo;
                        foreach (var surviving in current.Where(s => s.Hi > span.Lo && s.Lo < span.Hi))
                        {
                            double lo = Math.Max(span.Lo, surviving.Lo), hi = Math.Min(span.Hi, surviving.Hi);
                            if (lo > cursor) spans.Add((cursor, lo, false, input.Body.Id));
                            if (hi > lo) spans.Add((lo, hi, true, input.Body.Id));
                            cursor = Math.Max(cursor, hi);
                        }
                        if (span.Hi > cursor) spans.Add((cursor, span.Hi, false, input.Body.Id));
                    }
                }
                bool blocked = false;
                foreach (var span in spans.OrderBy(s => s.lo))
                {
                    if (span.retained) blocked = true;
                    else if (blocked)
                    {
                        // Resolve cancellation on nearly tangent shared edges with
                        // exact binary-rational predicates, never a larger tolerance.
                        if (++Diagnostics.exactContinuityRays > 4096)
                        { error="Blast exact continuity certificate exceeds 4096 rays."; return false; }
                        if (!BlastExact.HasBuriedRemoval(Inputs,replacements,Origin,theta)) break;
                        error = "Blast final geometry retains intervening material before removal at angle " + theta.ToString("R")
                        + ": " + string.Join("; ",spans.OrderBy(s=>s.lo).Select(s=>(s.retained?"retained ":"removed ")+s.body+" ["+s.lo.ToString("R")+","+s.hi.ToString("R")+"]")) + "."; return false; }
                }
            }
            Diagnostics.continuityMilliseconds = clock.Elapsed.TotalMilliseconds;
            return true;
        }
    }

    public static class BoundedBlastEvaluator
    {
        public const double InwardAllowance = 0.0004;
        public const double FloatAllowance = 0.00005;
        public const double MaximumDeficit = 0.001;
        public const int MaximumSectors = 8192;
        public static bool TryCreate(CanonicalMaterialWorld world, CanonicalMaterialState bomb,
            out BoundedBlastField field, out string error)
        {
            field = null; error = null;
            var watch = Stopwatch.StartNew();
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
                        if (input.Resistance > 0 || input.Opaque || body.IsCharacter) BlastMath.AddAngles(cell.Points, events);
                    }
                    inputs.Add(input);
                    diagnostics.inputCells += input.Cells.Count;
                    if (Math.Abs(body.Position.x) > 64 || Math.Abs(body.Position.y) > 64)
                        throw new InvalidOperationException("Blast candidate pose exceeds absolute coordinate bounds.");
                }
                diagnostics.candidateBodies = inputs.Count;
                if (inputs.Count > 32 || diagnostics.inputCells > 512 || inputs.Sum(b => b.Cells.Sum(c => c.Points.Length)) > 4096)
                    throw new InvalidOperationException("Blast input work budget exceeded.");
                for (int i = 0; i < inputs.Count; i++) for (int j = i + 1; j < inputs.Count; j++)
                    foreach (var a in inputs[i].Cells) foreach (var b in inputs[j].Cells)
                        if (BlastMath.Area(BlastMath.Intersect(a.Points.ToList(), b.Points)) > BlastMath.Roundoff)
                            throw new InvalidOperationException("Overlapping original blast materials require an unaccepted composition policy.");
                var angles = BlastMath.Events(events);
                var sectors = new List<BlastSector>();
                var exposed = new HashSet<MaterialEntityId>();
                var ambiguous = new HashSet<MaterialEntityId>();
                double maximumPitch = 2 * Math.Acos(1 - 0.00025 / radius);
                for (int i = 0; i + 1 < angles.Count; i++)
                {
                    // Begin with evenly spaced sectors close to the permitted chord
                    // pitch, rather than halving a long interval into unnecessarily
                    // small facets. Material vertices remain explicit interval breaks.
                    int count=(int)Math.Ceiling((angles[i+1]-angles[i])/maximumPitch);
                    for(int j=0;j<count;j++)
                        Refine(inputs,radius,spec.blastPower>=1,angles[i]+(angles[i+1]-angles[i])*j/count,
                            angles[i]+(angles[i+1]-angles[i])*(j+1)/count,0,sectors,exposed,ambiguous,diagnostics);
                }
                if (ambiguous.Any(id => !exposed.Contains(id)))
                    throw new InvalidOperationException("Character exposure has only an unresolved boundary contact; no positive aperture was proved.");
                sectors = Coalesce(sectors, radius, diagnostics);
                diagnostics.sectors = sectors.Count;
                diagnostics.maximumReachEnclosure = sectors.Max(s => s.Enclosure);
                diagnostics.maximumRadialDeficit = diagnostics.maximumReachEnclosure + FloatAllowance;
                diagnostics.fieldMilliseconds = watch.Elapsed.TotalMilliseconds;
                field = new BoundedBlastField(bomb.Position, radius, world.Generation, inputs, sectors, exposed, diagnostics);
                return true;
            }
            catch (Exception exception) { error = "Bounded blast rejected: " + exception.Message; return false; }
        }

        private static void Refine(List<BlastInput> inputs, double radius, bool lethal, double a, double b, int depth,
            List<BlastSector> output, HashSet<MaterialEntityId> exposed, HashSet<MaterialEntityId> ambiguous, BlastDiagnostics diagnostics)
        {
            var profiles = inputs.Where(input => input.Resistance > 0 || input.Opaque || input.Body.IsCharacter)
                .SelectMany(input => BlastMath.Spans(input.Cells, (a + b) / 2)
                .Select(span => new BlastProfile(input, span))).OrderBy(p => p.Span.Lo).ToList();
            foreach (var profile in profiles) profile.Bounds(a, b);
            var opaque = profiles.Where(p => p.Input.Opaque).ToArray();
            double leftLimit = ExactLimit(profiles, a, radius), rightLimit = ExactLimit(profiles, b, radius);
            double left = Math.Max(0, leftLimit - InwardAllowance), right = Math.Max(0, rightLimit - InwardAllowance);
            double outerLeft = leftLimit + InwardAllowance, outerRight = rightLimit + InwardAllowance;
            // Both chords have endpoints on the same rays. Positivity of the harmonic
            // interpolation gives this enclosure, including rapidly changing reach.
            double minimum = Math.Min(left, right), maximum = Math.Max(outerLeft, outerRight);
            double enclosure = minimum > 0 ? 2 * InwardAllowance * Math.Pow(maximum / minimum, 2)
                / Math.Cos((b - a) / 2) : double.PositiveInfinity;
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
            bool split = sagitta > 0.00025 || enclosure + FloatAllowance > MaximumDeficit;
            if (!split)
                split = !CertifyChord(profiles, a, b, left, right, radius, true, diagnostics)
                    || !CertifyChord(profiles, a, b, outerLeft, outerRight, radius, false, diagnostics);
            if (split)
            {
                if (depth >= 24) throw new InvalidOperationException("Blast reach/character boundary is unresolved at refinement depth 24.");
                Refine(inputs, radius, lethal, a, (a + b) / 2, depth + 1, output, exposed, ambiguous, diagnostics);
                Refine(inputs, radius, lethal, (a + b) / 2, b, depth + 1, output, exposed, ambiguous, diagnostics);
            }
            else
            {
                output.Add(new BlastSector(a, b, left, right, enclosure, depth, profiles));
                foreach (var id in witness) exposed.Add(id);
                foreach (var id in uncertainCharacters) ambiguous.Add(id);
                if (output.Count > MaximumSectors) throw new InvalidOperationException("Blast sector budget exceeded at "
                    + output.Count + " sectors; current angle " + a.ToString("R") + ".." + b.ToString("R") + ".");
            }
        }
        private static List<BlastSector> Coalesce(List<BlastSector> original, double radius, BlastDiagnostics diagnostics)
        {
            var result = new List<BlastSector>();
            for (int first = 0; first < original.Count;)
            {
                int last = first;
                var best = original[first];
                for (int next = first + 1; next < original.Count; next++)
                {
                    var end = original[next];
                    double width = end.B - best.A;
                    if (radius * (1 - Math.Cos(width / 2)) > 0.00025) break;
                    double minimum = Math.Min(best.Left, end.Right);
                    double maximum = Math.Max(best.Left, end.Right) + 2 * InwardAllowance;
                    double enclosure = minimum > 0 ? 2 * InwardAllowance * Math.Pow(maximum / minimum, 2)
                        / Math.Cos(width / 2) : double.PositiveInfinity;
                    if (enclosure + FloatAllowance > MaximumDeficit) break;
                    var inner = new BlastEdge(BlastPoint.Direction(best.A) * best.Left, BlastPoint.Direction(end.B) * end.Right);
                    var outer = new BlastEdge(BlastPoint.Direction(best.A) * (best.Left + 2 * InwardAllowance),
                        BlastPoint.Direction(end.B) * (end.Right + 2 * InwardAllowance));
                    bool valid = true;
                    // Every original edge-order interval still participates in the
                    // certificate. A material vertex is not silently sampled away.
                    for (int i = first; i <= next && valid; i++)
                    {
                        var part = original[i];
                        valid = CertifyChordRange(part.Profiles, inner, part.A, part.B, radius, true, diagnostics)
                            && CertifyChordRange(part.Profiles, outer, part.A, part.B, radius, false, diagnostics);
                    }
                    if (!valid) break;
                    last = next;
                    best = new BlastSector(best.A, end.B, best.Left, end.Right, enclosure, 0, null);
                }
                result.Add(best);
                diagnostics.coalescedSectors += last - first;
                first = last + 1;
            }
            return result;
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
        private static double ExactLimit(List<BlastProfile> active, double theta, double radius)
        {
            // One-sided active edges are retained from the open sector, including at a jump.
            var profiles = active.Select(p => p.At(theta)).ToList();
            double reach = Invert(profiles, radius, true);
            foreach (var p in profiles.Where(p => p.Input.Opaque)) reach = Math.Min(reach, p.Entry.Lo);
            return reach;
        }

        // The cost along a chord is a piecewise sum of h/(n dot direction).
        // Split at every chord/material-line crossing, then use the second derivative
        // bound M*w*w/8 for linear interpolation on the WHOLE open interval.
        // This tests an inner and an outer chord; endpoint or central-ray samples alone
        // never authorize removal. Opaque planes use the same crossings and inputs.
        private static bool CertifyChord(List<BlastProfile> profiles, double a, double b, double left, double right,
            double radius, bool inner, BlastDiagnostics diagnostics)
        {
            var chord = new BlastEdge(BlastPoint.Direction(a) * left, BlastPoint.Direction(b) * right);
            return CertifyChordRange(profiles, chord, a, b, radius, inner, diagnostics);
        }
        private static bool CertifyChordRange(List<BlastProfile> profiles, BlastEdge chord, double a, double b,
            double radius, bool inner, BlastDiagnostics diagnostics)
        {
            var events = new List<double> { a, b };
            foreach (var p in profiles)
            { chord.AddCrossing(p.Span.Entry, a, b, events); chord.AddCrossing(p.Span.Exit, a, b, events); }
            var angles = BlastMath.Events(events);
            for (int i = 0; i + 1 < angles.Count; i++)
            {
                diagnostics.certificateIntervals++;
                double lo = angles[i], hi = angles[i + 1], mid = (lo + hi) / 2, distance = chord.At(mid);
                bool blocked = profiles.Any(p => p.Input.Opaque && (p.Span.Entry?.At(mid) ?? 0) < distance);
                if (blocked) { if (inner) return false; else continue; }
                double coefficient = 1, curvature = 0;
                foreach (var p in profiles)
                {
                    double entry = p.Span.Entry?.At(mid) ?? 0, exit = p.Span.Exit?.At(mid) ?? 32;
                    if (distance <= entry || p.Input.Resistance == 0) continue;
                    curvature += p.Input.Resistance * (p.Span.Entry?.CurvatureBound(lo, hi) ?? 0);
                    if (distance < exit) coefficient += p.Input.Resistance;
                    else curvature += p.Input.Resistance * (p.Span.Exit?.CurvatureBound(lo, hi) ?? 0);
                }
                curvature += coefficient * chord.CurvatureBound(lo, hi);
                double ca = Cost(profiles.Select(p => p.At(lo)).ToList(), chord.At(lo), true);
                double cb = Cost(profiles.Select(p => p.At(hi)).ToList(), chord.At(hi), true);
                double remainder = curvature * (hi - lo) * (hi - lo) / 8 + BlastMath.Roundoff;
                if (inner ? Math.Max(ca, cb) + remainder > radius : Math.Min(ca, cb) - remainder < radius)
                    return false;
            }
            return true;
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
        public readonly BlastEdge[] Edges;
        public BlastCell(BlastPoint[] points)
        { Points = points; Edges = points.Select((p,i)=>new BlastEdge(p,points[(i+1)%points.Length])).ToArray(); }
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
        public readonly double Orientation;
        public BlastEdge(BlastPoint a, BlastPoint b)
        {
            // Opposite sides of a shared segment use identical floating arithmetic.
            // Computing h from opposite endpoints can invent a gap on nearly tangent rays.
            Orientation = a.X < b.X || (a.X == b.X && a.Y < b.Y) ? 1 : -1;
            if (Orientation < 0) { var p=a;a=b;b=p; }
            var edge = b - a; normal = new BlastPoint(-edge.Y, edge.X) * (1 / edge.Length); height = BlastPoint.Dot(normal, a);
        }
        public double SignedDenominator(BlastPoint direction)=>BlastPoint.Dot(normal,direction)*Orientation;
        public double SignedHeight=>height*Orientation;
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
        public double CurvatureBound(double a, double b)
        {
            double da = BlastPoint.Dot(normal, BlastPoint.Direction(a)), db = BlastPoint.Dot(normal, BlastPoint.Direction(b));
            if (da * db <= 0) return double.PositiveInfinity;
            // For intervals shorter than pi, |cos| attains its minimum at an endpoint
            // unless it crosses zero. r'' = r * (1 + 2*tan^2).
            double cosine = Math.Min(Math.Abs(da), Math.Abs(db)) - 1e-12;
            return cosine > 0 ? (Math.Abs(height) / cosine + BlastMath.Roundoff) * (2 / (cosine * cosine) - 1)
                : double.PositiveInfinity;
        }
        public void AddCrossing(BlastEdge other, double a, double b, List<double> events)
        {
            if (other == null) return;
            double determinant = BlastPoint.Cross(normal, other.normal);
            if (Math.Abs(determinant) < 1e-15) return;
            var point = new BlastPoint((height * other.normal.Y - normal.Y * other.height) / determinant,
                (normal.X * other.height - height * other.normal.X) / determinant);
            if (point.Length <= BlastMath.Roundoff) return;
            double angle = BlastMath.Angle(Math.Atan2(point.Y, point.X));
            if (angle > a && angle < b) events.Add(angle);
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
        public readonly double A, B, Enclosure;
        public readonly int Depth;
        public readonly List<BlastProfile> Profiles;
        public readonly double Left, Right;
        public BlastSector(double a, double b, double left, double right, double enclosure, int depth, List<BlastProfile> profiles)
        { A = a; B = b; Enclosure = enclosure; Depth = depth; Profiles = profiles; Left = left; Right = right; }
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
        public static List<BlastSpan> Spans(IEnumerable<BlastCell> cells, double theta, bool mergeRoundoff = true)
        {
            var result = new List<BlastSpan>(); var direction = BlastPoint.Direction(theta);
            foreach (var cell in cells)
            {
                double lo = 0, hi = double.PositiveInfinity; BlastEdge entry = null, exit = null; bool miss = false;
                for (int i = 0; i < cell.Points.Length; i++)
                {
                    var plane = cell.Edges[i];
                    double denominator = plane.SignedDenominator(direction), numerator = plane.SignedHeight;
                    if (Math.Abs(denominator) <= 1e-15) { if (numerator > 0) miss = true; continue; }
                    double t = numerator / denominator;
                    if (denominator > 0 && t > lo) { lo = t; entry = plane; }
                    if (denominator < 0 && t < hi) { hi = t; exit = plane; }
                }
                if (!miss && hi > lo + (mergeRoundoff ? Roundoff : 0) && hi > 0) result.Add(new BlastSpan(Math.Max(0, lo), hi, entry, exit));
            }
            result.Sort((a, b) => a.Lo.CompareTo(b.Lo)); var merged = new List<BlastSpan>();
            foreach (var span in result)
            {
                if (merged.Count == 0 || span.Lo > merged[merged.Count - 1].Hi + (mergeRoundoff ? Roundoff : 0)) merged.Add(span);
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

    // Adaptive predicate only. System.Numerics is the existing .NET base library;
    // these integers/fractions are ephemeral and do not alter canonical encoding.
    internal static class BlastExact
    {
        private sealed class Fraction : IComparable<Fraction>
        {
            public readonly BigInteger N,D;
            public Fraction(BigInteger numerator,BigInteger denominator)
            { if(denominator.Sign<0){numerator=-numerator;denominator=-denominator;} N=numerator;D=denominator; }
            public int CompareTo(Fraction other)=>(N*other.D).CompareTo(other.N*D);
            public static readonly Fraction Zero=new Fraction(BigInteger.Zero,BigInteger.One);
        }
        private sealed class Span
        {
            public Fraction Lo,Hi;
            public Span(Fraction lo,Fraction hi){Lo=lo;Hi=hi;}
        }
        private static void Binary(double value,out ulong mantissa,out int exponent)
        {
            long bits=BitConverter.DoubleToInt64Bits(value);int biased=(int)((bits>>52)&0x7ff);
            mantissa=(ulong)bits&0xfffffffffffffUL;exponent=biased==0?-1074:biased-1075;
            if(biased!=0)mantissa|=1UL<<52;
            if(mantissa==0){exponent=0;return;}
            while((mantissa&1)==0){mantissa>>=1;exponent++;}
        }
        private static BigInteger Integer(double value,int shift)
        {
            Binary(value,out var mantissa,out int exponent);
            var result=new BigInteger(mantissa)<<(exponent+shift);
            long bits=BitConverter.DoubleToInt64Bits(value);
            return bits<0?-result:result;
        }
        private static List<Span> Spans(IEnumerable<CanonicalMaterialState> bodies,Vector2 origin,BigInteger dx,BigInteger dy,int shift)
        {
            var spans=new List<Span>();
            var scale=BigInteger.One<<shift;var ox=Integer(origin.x,shift);var oy=Integer(origin.y,shift);
            foreach(var body in bodies)
            {
                var c=Integer(Mathf.Cos(body.RotationRadians),shift);var s=Integer(Mathf.Sin(body.RotationRadians),shift);
                var px=(Integer(body.Position.x,shift)-ox)*scale;var py=(Integer(body.Position.y,shift)-oy)*scale;
                foreach(var cell in body.Shape.Cells)
                {
                // Compose the authored float affine transform exactly too. Rounding
                // transformed vertices before this predicate would reintroduce seams.
                var points=cell.Vertices.Select(p=>(x:px+c*Integer(p.x,shift)-s*Integer(p.y,shift),y:py+s*Integer(p.x,shift)+c*Integer(p.y,shift))).ToArray();
                var lo=Fraction.Zero;Fraction hi=null;bool miss=false;
                for(int i=0;i<points.Length;i++)
                {
                    var a=points[i];var b=points[(i+1)%points.Length];var ex=b.x-a.x;var ey=b.y-a.y;
                    var denominator=ex*dy-ey*dx;var numerator=ex*a.y-ey*a.x;
                    if(denominator.IsZero){if(numerator.Sign>0)miss=true;continue;}
                    var t=new Fraction(numerator,denominator);
                    if(denominator.Sign>0&&t.CompareTo(lo)>0)lo=t;
                    if(denominator.Sign<0&&(hi==null||t.CompareTo(hi)<0))hi=t;
                }
                if(!miss&&hi!=null&&hi.CompareTo(lo)>0)spans.Add(new Span(lo,hi));
                }
            }
            spans.Sort((a,b)=>a.Lo.CompareTo(b.Lo));var merged=new List<Span>();
            foreach(var span in spans)
                if(merged.Count==0||span.Lo.CompareTo(merged[merged.Count-1].Hi)>0)merged.Add(span);
                else if(span.Hi.CompareTo(merged[merged.Count-1].Hi)>0)merged[merged.Count-1].Hi=span.Hi;
            return merged;
        }
        public static bool HasBuriedRemoval(List<BlastInput> inputs,
            IReadOnlyDictionary<MaterialEntityId,IReadOnlyList<CanonicalMaterialState>> after,Vector2 origin,double theta)
        {
            // Choose the smallest common binary scale for this predicate instead of
            // allocating 1074-bit padding on ordinary metre-scale inputs. No rounding.
            int minimum=0;
            void Include(double v){Binary(v,out var mantissa,out int e);if(mantissa!=0)minimum=Math.Min(minimum,e);}
            Include(origin.x);Include(origin.y);Include(Math.Cos(theta));Include(Math.Sin(theta));
            foreach(var body in inputs.SelectMany(i=>after.TryGetValue(i.Body.Id,out var result)?result:new[]{i.Body}).Concat(inputs.Select(i=>i.Body)))
            {
                Include(body.Position.x);Include(body.Position.y);Include(Mathf.Cos(body.RotationRadians));Include(Mathf.Sin(body.RotationRadians));
                foreach(var cell in body.Shape.Cells)foreach(var p in cell.Vertices){Include(p.x);Include(p.y);}
            }
            int shift=-minimum;var dx=Integer(Math.Cos(theta),shift);var dy=Integer(Math.Sin(theta),shift);
            var pieces=new List<(Fraction lo,Fraction hi,bool retained)>();
            foreach(var input in inputs)
            {
                var current=Spans(after.TryGetValue(input.Body.Id,out var result)?result:new[]{input.Body},origin,dx,dy,shift);
                foreach(var span in Spans(new[]{input.Body},origin,dx,dy,shift))
                {
                    var cursor=span.Lo;
                    foreach(var surviving in current)
                    {
                        var lo=span.Lo.CompareTo(surviving.Lo)>0?span.Lo:surviving.Lo;
                        var hi=span.Hi.CompareTo(surviving.Hi)<0?span.Hi:surviving.Hi;
                        if(hi.CompareTo(lo)<=0)continue;
                        if(lo.CompareTo(cursor)>0)pieces.Add((cursor,lo,false));
                        pieces.Add((lo,hi,true));if(hi.CompareTo(cursor)>0)cursor=hi;
                    }
                    if(span.Hi.CompareTo(cursor)>0)pieces.Add((cursor,span.Hi,false));
                }
            }
            bool blocked=false;
            foreach(var piece in pieces.OrderBy(p=>p.lo))
                if(piece.retained)blocked=true;else if(blocked)return true;
            return false;
        }
    }
}
