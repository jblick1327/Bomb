using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

// G5 (design doc integration/review/destruction-design-2026-11.md section 3): the mapping from Darryn's tile scenes to an
// Odin layout, as plain data in and out. No UnityEngine here, so the same code runs in the editor exporter
// (BomTileLevelBuilder) and in the negative tests (integration/tools/g5/TileMappingTests, plain dotnet).
//   1. Tile -> part: the tile's XY silhouette (convex hull of its mesh), clipped to the arena (inner wall faces, floor top).
//      Members that only existed off the player plane (truss, pillars) come onto the plane: nothing is decoration.
//   2. Front/rear duplicates (same XY outline) merge into one member; the report keeps every path.
//   3. Overlaps become a partition, never a gap: the continuous member keeps the overlap and the other is cut at its
//      face (priority terrain > decks/girders/floors > posts/pillars > braces > rocks; then higher top, lower x, path).
//      Stacked post segments of one column join into one run first (as G1), so posts are cut only by what crosses them.
//   4. Every contact within the native glue fillet (0.2) becomes a glue link, checked with the native sampling rule.
//   5. Materials come from the level's table (OD-2); a tile the table does not name fails the export (I4).
//   6. Anchors only at real support (I3): the bottom edge of the terrain mass (bedrock), a post foot standing on terrain,
//      and on the Bridge exactly the five pile feet (OD-3: piles drawn from the lowest post feet down to the riverbed).
// Invariants I1-I4 are export failures (InvariantException names the tile and the invariant); I5 is the settle run.
public static class BomTileMapping
{
    public struct P
    {
        public double X,
            Y;

        public P(double x, double y)
        {
            X = x;
            Y = y;
        }

        public override string ToString() => "(" + F(X) + "," + F(Y) + ")";
    }

    public enum Role
    {
        Terrain,
        Horizontal,
        Post,
        Brace,
        Rock,
    }

    public sealed class Tile
    {
        public string Path = "",
            Name = "",
            Behaviour = "",
            DarrynMaterial = "";
        public P[] Hull; // convex XY silhouette of the tile's meshes (world)
        public double ZMin,
            ZMax;
    }

    public sealed class Boundary
    {
        public string Name = "";
        public P Lo,
            Hi;
        public bool Indestructible,
            Visible;
    }

    public sealed class Rules
    {
        public string Level = "";
        public double PlaneZ;

        // OD-2: Darryn's tile name (without the " (n)" suffix) by prefix -> palette material. Nothing else is accepted.
        public (string Prefix, string Material)[] Materials = Array.Empty<(string, string)>();

        // OD-3: draw piles from the lowest post feet down to the floor and anchor exactly their feet.
        public int Piles;
        public string PileMaterial = "";
    }

    public sealed class Input
    {
        public Rules Rules = new Rules();
        public List<Tile> Tiles = new List<Tile>();
        public List<Boundary> Boundaries = new List<Boundary>();
    }

    public sealed class Anchor
    {
        public P A,
            B;
        public string Support = "";
    }

    public sealed class Pile
    {
        public P Lo,
            Hi;
        public string TemplatePath = ""; // the post tile whose mesh dresses the pile
    }

    public sealed class Part
    {
        public int Index;
        public Role Role;
        public string Material = "",
            Note = "";
        public P[] Outline;
        public List<string> Tiles = new List<string>(); // every Darryn tile this part stands for (all duplicates)
        public List<string> Visual = new List<string>(); // one tile per distinct outline, whose mesh dresses the part
        public List<Pile> Piles = new List<Pile>();
        public double ZMin,
            ZMax;
        public List<Anchor> Anchors = new List<Anchor>();
    }

    public sealed class GlueLink
    {
        public int A,
            B;
        public double Weight;
    }

    public sealed class Row
    {
        public string path,
            name,
            behaviour,
            darryn_material,
            role,
            classification,
            material,
            note;
        public double zmin,
            zmax;
        public bool brought_onto_plane;
        public int[] parts;
    }

    public sealed class Result
    {
        public string Level = "";
        public List<Part> Parts = new List<Part>();
        public List<GlueLink> Glue = new List<GlueLink>();
        public List<Row> Rows = new List<Row>();
        public List<Boundary> Boundaries = new List<Boundary>();
        public int Tiles,
            InArena,
            OutsideArena,
            Backdrop,
            MergedDuplicates,
            ColumnJoins,
            BroughtOntoPlane,
            DroppedSlivers;
        public double DroppedArea,
            MaxDroppedArea,
            TerrainFloor = double.NaN;
        public List<string> Notes = new List<string>();
        public List<string> Nudges = new List<string>(); // OD-7: every geometry nudge with its before and after values
    }

    public sealed class InvariantException : Exception
    {
        public readonly string Invariant,
            Tile;

        public InvariantException(string invariant, string tile, string message)
            : base(invariant + " " + tile + ": " + message)
        {
            Invariant = invariant;
            Tile = tile;
        }
    }

    // Native limits (Documents/BOM src/shared/level_layout.odin, sim_glue.odin).
    public const int MaxParts = 1024,
        MaxSources = 512,
        MaxGlue = 2048;
    public const double GlueFillet = .2,
        GlueContact = .001,
        GlueStep = .05;

    // Mapping constants. A piece thinner than MinThickness or smaller than MinArea is a cutting sliver (dropped and counted);
    // a dropped piece larger than MaxDroppedArea would make a visible piece vanish, which I1 forbids.
    public const double TerrainDepth = 6, // same split as BomDepthLook.TerrainMinDepth
        PlayerHalfDepth = .45,
        MinThickness = .05,
        MinArea = .005,
        MaxDroppedArea = .05,
        ColumnGap = .05,
        TerrainFloorBand = .5, // Darryn places ground tiles with offsets up to ~0.4; a bottom edge this close to the lowest one is the mass's underside
        MinGlueWeight = 1e-6, // at least one native sample from each side (native keeps a link with any sample; G1's 1-sample brace/deck corner links hold the truss)
        SupportGap = GlueFillet,
        Eps = 1e-9;

    // OD-7 nudges (owner, 2026-11-18: "feel free to nudge bits around if they help the structure"). Measured in evidence/G5/nudge.
    // BearingGap: a horizontal part floating at most this far above a horizontal part's top grows down onto it (contact bearing, OD-8);
    // a post stopping at most this far below a horizontal part's bottom grows up to it (OD-10, the Tower pillars).
    // SeatHeight / SeatSnap: a brace end meeting a girder underside within SeatSnap of a post face is snapped to the face and given a
    // SeatHeight-tall seat on it, so the brace bears on the post face instead of a ~0.05 corner point.
    public const double BearingGap = .05,
        SeatHeight = .25,
        SeatSnap = .01;

    public static readonly string[] BoundaryNames = { "Bottom Boundary", "Left Wall", "Right Wall" };

    static string F(double v) => v.ToString("0.###", CultureInfo.InvariantCulture);

    public static string BaseName(string name)
    {
        int open = name.LastIndexOf(" (", StringComparison.Ordinal);
        return open > 0 && name.EndsWith(")", StringComparison.Ordinal) ? name.Substring(0, open) : name;
    }

    // ---------------- convex geometry (CCW) ----------------
    public static double Area(P[] p)
    {
        double s = 0;
        for (int i = 0; i < p.Length; i++)
            s += p[i].X * p[(i + 1) % p.Length].Y - p[(i + 1) % p.Length].X * p[i].Y;
        return s / 2;
    }

    static double Perimeter(P[] p)
    {
        double s = 0;
        for (int i = 0; i < p.Length; i++)
            s += Len(p[i], p[(i + 1) % p.Length]);
        return s;
    }

    static double Len(P a, P b) => Math.Sqrt((a.X - b.X) * (a.X - b.X) + (a.Y - b.Y) * (a.Y - b.Y));

    public static double Thickness(P[] p) => p.Length < 3 ? 0 : 2 * Math.Abs(Area(p)) / Perimeter(p);

    public static P[] Ccw(P[] p) => Area(p) >= 0 ? p : p.Reverse().ToArray();

    public static (P lo, P hi) Box(P[] p)
    {
        P lo = new P(double.MaxValue, double.MaxValue),
            hi = new P(double.MinValue, double.MinValue);
        foreach (var v in p)
        {
            lo = new P(Math.Min(lo.X, v.X), Math.Min(lo.Y, v.Y));
            hi = new P(Math.Max(hi.X, v.X), Math.Max(hi.Y, v.Y));
        }
        return (lo, hi);
    }

    public static P[] Rect(P lo, P hi) => new[] { lo, new P(hi.X, lo.Y), hi, new P(lo.X, hi.Y) };

    public static bool IsAxisRect(P[] p)
    {
        if (p.Length != 4)
            return false;
        for (int i = 0; i < 4; i++)
        {
            P a = p[i],
                b = p[(i + 1) % 4];
            if (Math.Abs(a.X - b.X) > 1e-4 && Math.Abs(a.Y - b.Y) > 1e-4)
                return false;
        }
        return true;
    }

    // Keep n.p <= d. An axis-aligned cut lands exactly on the cutting coordinate, so both sides of a seam share it.
    public static P[] Clip(P[] poly, double nx, double ny, double d)
    {
        var result = new List<P>();
        for (int i = 0; i < poly.Length; i++)
        {
            P a = poly[i],
                b = poly[(i + 1) % poly.Length];
            double fa = nx * a.X + ny * a.Y - d,
                fb = nx * b.X + ny * b.Y - d;
            if (fa <= 0)
                result.Add(a);
            if (fa < 0 && fb > 0 || fb < 0 && fa > 0)
            {
                double t = fa / (fa - fb);
                var q = new P(a.X + t * (b.X - a.X), a.Y + t * (b.Y - a.Y));
                if (ny == 0)
                    q.X = d / nx;
                else if (nx == 0)
                    q.Y = d / ny;
                result.Add(q);
            }
        }
        return Clean(result.ToArray());
    }

    // Drop repeated and collinear vertices.
    public static P[] Clean(P[] p)
    {
        var list = new List<P>(p);
        bool changed = true;
        while (changed && list.Count >= 3)
        {
            changed = false;
            for (int i = 0; i < list.Count && list.Count >= 3; i++)
            {
                P a = list[(i + list.Count - 1) % list.Count],
                    b = list[i],
                    c = list[(i + 1) % list.Count];
                double cross = (b.X - a.X) * (c.Y - b.Y) - (b.Y - a.Y) * (c.X - b.X);
                if (Len(a, b) < 1e-4 || Math.Abs(cross) < 1e-9 * Math.Max(1, Len(a, c)))
                {
                    list.RemoveAt(i);
                    changed = true;
                    break;
                }
            }
        }
        return list.Count >= 3 ? list.ToArray() : Array.Empty<P>();
    }

    static (double nx, double ny, double d) EdgeLine(P[] a, int i)
    {
        P p = a[i],
            q = a[(i + 1) % a.Length];
        double nx = q.Y - p.Y,
            ny = -(q.X - p.X); // outward normal of a CCW edge
        double len = Math.Sqrt(nx * nx + ny * ny);
        nx /= len;
        ny /= len;
        if (Math.Abs(nx) < 1e-12)
            nx = 0;
        if (Math.Abs(ny) < 1e-12)
            ny = 0;
        if (nx == 0)
            ny = Math.Sign(ny);
        if (ny == 0)
            nx = Math.Sign(nx);
        return (nx, ny, nx * p.X + ny * p.Y);
    }

    public static P[] Intersect(P[] a, P[] b)
    {
        var p = a;
        for (int i = 0; i < b.Length && p.Length >= 3; i++)
        {
            var (nx, ny, d) = EdgeLine(b, i);
            p = Clip(p, nx, ny, d);
        }
        return p;
    }

    public static double OverlapArea(P[] a, P[] b)
    {
        var (alo, ahi) = Box(a);
        var (blo, bhi) = Box(b);
        if (Math.Min(ahi.X, bhi.X) - Math.Max(alo.X, blo.X) <= 1e-9 || Math.Min(ahi.Y, bhi.Y) - Math.Max(alo.Y, blo.Y) <= 1e-9)
            return 0;
        var i = Intersect(a, b);
        return i.Length < 3 ? 0 : Area(i);
    }

    static bool Sliver(P[] p) => p.Length < 3 || Area(p) < MinArea || Thickness(p) < MinThickness;

    // b minus convex a, as disjoint convex pieces. Every starting edge is tried; the split with the fewest real (non-sliver)
    // pieces, then the largest piece, wins, so a shallow seam overlap trims a face instead of slicing the tile in two.
    public static List<P[]> Difference(P[] b, P[] a)
    {
        List<P[]> best = null;
        int bestReal = int.MaxValue;
        double bestLargest = -1;
        for (int start = 0; start < a.Length; start++)
        {
            var pieces = new List<P[]>();
            var rest = b;
            for (int k = 0; k < a.Length && rest.Length >= 3; k++)
            {
                var (nx, ny, d) = EdgeLine(a, (start + k) % a.Length);
                var outside = Clip(rest, -nx, -ny, -d);
                if (outside.Length >= 3 && Area(outside) > 1e-9)
                    pieces.Add(outside);
                rest = Clip(rest, nx, ny, d);
            }
            int real = pieces.Count(p => !Sliver(p));
            double largest = pieces.Count == 0 ? 0 : pieces.Max(p => Area(p));
            if (real < bestReal || real == bestReal && largest > bestLargest + 1e-9)
            {
                best = pieces;
                bestReal = real;
                bestLargest = largest;
            }
        }
        return best ?? new List<P[]> { b };
    }

    // ---------------- native glue sampling (sim_glue.odin glue_side / glue_samples) ----------------
    static P Nearest(P[] y, P p)
    {
        P best = y[0];
        double bd = double.MaxValue;
        for (int i = 0; i < y.Length; i++)
        {
            P a = y[i],
                b = y[(i + 1) % y.Length];
            double vx = b.X - a.X,
                vy = b.Y - a.Y,
                l = vx * vx + vy * vy;
            double t = l == 0 ? 0 : Math.Max(0, Math.Min(1, ((p.X - a.X) * vx + (p.Y - a.Y) * vy) / l));
            var q = new P(a.X + t * vx, a.Y + t * vy);
            double d = Len(p, q);
            if (d < bd)
            {
                bd = d;
                best = q;
            }
        }
        return best;
    }

    static double SideWeight(P[] x, P[] y)
    {
        double total = 0;
        for (int i = 0; i < x.Length; i++)
        {
            P a = x[i];
            P e = new P(x[(i + 1) % x.Length].X - a.X, x[(i + 1) % x.Length].Y - a.Y);
            double length = Math.Sqrt(e.X * e.X + e.Y * e.Y);
            if (length < 1e-7)
                continue;
            int n = (int)Math.Ceiling(length / GlueStep);
            var normal = new P(e.Y / length, -e.X / length);
            for (int j = 0; j < n; j++)
            {
                var p = new P(a.X + e.X * (j + .5) / n, a.Y + e.Y * (j + .5) / n);
                bool hit = Len(Nearest(y, p), p) <= GlueContact;
                double distance = GlueFillet + 1e-6;
                for (int k = 0; k < y.Length && !hit; k++)
                {
                    P c = y[k];
                    var dd = new P(y[(k + 1) % y.Length].X - c.X, y[(k + 1) % y.Length].Y - c.Y);
                    double denom = normal.X * dd.Y - normal.Y * dd.X;
                    if (Math.Abs(denom) < 1e-8)
                        continue;
                    var cp = new P(c.X - p.X, c.Y - p.Y);
                    double t = (cp.X * dd.Y - cp.Y * dd.X) / denom,
                        u = (cp.X * normal.Y - cp.Y * normal.X) / denom;
                    if (t >= 0 && t <= distance && u >= 0 && u <= 1)
                        hit = true;
                }
                if (hit)
                    total += length / n;
            }
        }
        return total;
    }

    // Native keeps the lighter side of the two (glue_samples), so a link holds only if both sides find the other.
    public static double GlueWeight(P[] a, P[] b) => Math.Min(SideWeight(a, b), SideWeight(b, a));

    // ---------------- mapping ----------------
    sealed class Member
    {
        public Role Role;
        public string Material = "",
            Note = "";
        public P[] Outline;
        public List<Tile> Tiles = new List<Tile>();
        public List<Tile> Visual = new List<Tile>();
        public List<Pile> Piles = new List<Pile>();
        public double ZMin = double.MaxValue,
            ZMax = double.MinValue;
        public string First => Tiles.Count > 0 ? Tiles[0].Path : "pile";
    }

    public static Role Classify(Tile tile)
    {
        if (tile.ZMax - tile.ZMin >= TerrainDepth)
            return Role.Terrain;
        if (!IsAxisRect(tile.Hull))
            return tile.Hull.Length == 4 ? Role.Brace : Role.Rock;
        var (lo, hi) = Box(tile.Hull);
        double w = hi.X - lo.X,
            h = hi.Y - lo.Y;
        return h >= 1.5 * w && w <= 1.5 ? Role.Post : Role.Horizontal;
    }

    static int Priority(Role role) =>
        role == Role.Terrain ? 0
        : role == Role.Horizontal ? 1
        : role == Role.Post ? 2
        : role == Role.Brace ? 3
        : 4;

    static Boundary Named(Input input, string name)
    {
        var b = input.Boundaries.Find(x => x.Name == name);
        if (b == null)
            throw new InvariantException("I2", name, "missing boundary; the layout keeps exactly " + string.Join(", ", BoundaryNames) + " until G8");
        return b;
    }

    public static Result Map(Input input)
    {
        var rules = input.Rules;
        var result = new Result { Level = rules.Level, Boundaries = input.Boundaries };
        // I2: no indestructible source; fixed only on the existing boundary walls (G8 replaces them).
        foreach (var b in input.Boundaries)
        {
            if (Array.IndexOf(BoundaryNames, b.Name) < 0)
                throw new InvariantException("I2", b.Name, "fixed is allowed only on the existing boundary walls (" + string.Join(", ", BoundaryNames) + ")");
            if (b.Indestructible)
                throw new InvariantException("I2", b.Name, "no source may be indestructible; the boundary is fixed + destructible until G8");
        }
        var left = Named(input, "Left Wall");
        var right = Named(input, "Right Wall");
        var bottom = Named(input, "Bottom Boundary");
        double innerLeft = left.Hi.X,
            innerRight = right.Lo.X,
            floor = bottom.Hi.Y;

        // 1. Tiles -> members (clipped to the arena), with roles and OD-2 materials.
        var rows = new Dictionary<Tile, Row>();
        var raw = new List<(Tile tile, P[] outline, Role role, string material)>();
        foreach (var tile in input.Tiles.OrderBy(t => t.Path, StringComparer.Ordinal))
        {
            var row = new Row
            {
                path = tile.Path,
                name = tile.Name,
                behaviour = tile.Behaviour,
                darryn_material = tile.DarrynMaterial,
                zmin = tile.ZMin,
                zmax = tile.ZMax,
                note = "",
                parts = Array.Empty<int>(),
            };
            rows[tile] = row;
            result.Rows.Add(row);
            result.Tiles++;
            if (tile.Hull == null || tile.Hull.Length < 3 || Math.Abs(Area(tile.Hull)) < 1e-9)
                throw new InvariantException("I1", tile.Path, "no measurable mesh silhouette; every tile must become a part (author a proxy mesh)");
            var hull = Ccw(tile.Hull);
            var role = Classify(new Tile { Hull = hull, ZMin = tile.ZMin, ZMax = tile.ZMax });
            row.role = role.ToString();
            var clipped = Clip(Clip(Clip(hull, -1, 0, -innerLeft), 1, 0, innerRight), 0, -1, -floor);
            if (clipped.Length < 3 || Area(clipped) < 1e-6)
            {
                row.classification = "outside arena";
                row.note = "Wholly outside the boundary walls; left as Darryn's art for G8 to decide.";
                result.OutsideArena++;
                continue;
            }
            result.InArena++;
            string material = null;
            foreach (var (prefix, m) in rules.Materials)
                if (BaseName(tile.Name).StartsWith(prefix, StringComparison.Ordinal))
                {
                    material = m;
                    break;
                }
            if (string.IsNullOrEmpty(material))
                throw new InvariantException("I4", tile.Path, "the level's OD-2 material table has no entry for '" + BaseName(tile.Name) + "'");
            row.material = material;
            if (Area(clipped) < Area(hull) - 1e-6)
                row.note += "Clipped at the boundary wall/floor face (" + F(Area(hull) - Area(clipped)) + " of " + F(Area(hull)) + " outside). ";
            bool offPlane = tile.ZMax <= rules.PlaneZ - PlayerHalfDepth || tile.ZMin >= rules.PlaneZ + PlayerHalfDepth;
            if (offPlane)
            {
                row.brought_onto_plane = true;
                result.BroughtOntoPlane++;
                row.note += "Off the player plane in the original (z " + F(tile.ZMin) + ".." + F(tile.ZMax) + "); brought onto the plane. ";
            }
            raw.Add((tile, clipped, role, material));
        }

        // 2. Front/rear duplicates: same XY outline -> one member.
        var members = new List<Member>();
        var byKey = new Dictionary<string, Member>();
        foreach (var (tile, outline, role, material) in raw)
        {
            string key = string.Join(";", outline.Select(v => Math.Round(v.X, 3).ToString(CultureInfo.InvariantCulture) + "," + Math.Round(v.Y, 3).ToString(CultureInfo.InvariantCulture)).OrderBy(s => s, StringComparer.Ordinal));
            if (byKey.TryGetValue(key, out var same))
            {
                if (same.Material != material)
                    throw new InvariantException("I4", tile.Path, "duplicates " + same.First + " but maps to " + material + " instead of " + same.Material);
                same.Tiles.Add(tile);
                same.ZMin = Math.Min(same.ZMin, tile.ZMin);
                same.ZMax = Math.Max(same.ZMax, tile.ZMax);
                rows[tile].note += "Front/rear duplicate of " + same.First + " (merged). ";
                result.MergedDuplicates++;
                continue;
            }
            var m = new Member { Role = role, Material = material, Outline = outline, ZMin = tile.ZMin, ZMax = tile.ZMax };
            m.Tiles.Add(tile);
            m.Visual.Add(tile);
            byKey[key] = m;
            members.Add(m);
        }

        // 3. Piles (OD-3): from each lowest post foot straight down to the floor, joined to that post's column.
        if (rules.Piles > 0)
        {
            var posts = members.Where(m => m.Role == Role.Post && IsAxisRect(m.Outline)).ToList();
            if (posts.Count == 0)
                throw new InvariantException("I3", rules.Level, "the level asks for piles (OD-3) but has no posts");
            double foot = posts.Min(m => Box(m.Outline).lo.Y);
            foreach (var post in posts.Where(m => Box(m.Outline).lo.Y <= foot + ColumnGap).OrderBy(m => Box(m.Outline).lo.X))
            {
                var (lo, hi) = Box(post.Outline);
                var pile = new Member { Role = Role.Post, Material = rules.PileMaterial, Outline = Rect(new P(lo.X, floor), new P(hi.X, lo.Y)), ZMin = post.ZMin, ZMax = post.ZMax };
                pile.Piles.Add(new Pile { Lo = new P(lo.X, floor), Hi = new P(hi.X, lo.Y), TemplatePath = post.First });
                pile.Note = "OD-3 pile under " + post.First + ". ";
                members.Add(pile);
            }
        }

        // 4. Stacked post segments of one column (same x extent, touching in y) join into one run before cutting.
        bool joined = true;
        while (joined)
        {
            joined = false;
            for (int i = 0; i < members.Count && !joined; i++)
            for (int j = i + 1; j < members.Count && !joined; j++)
            {
                Member a = members[i],
                    b = members[j];
                if (a.Role != Role.Post || b.Role != Role.Post || a.Material != b.Material || !IsAxisRect(a.Outline) || !IsAxisRect(b.Outline))
                    continue;
                var (alo, ahi) = Box(a.Outline);
                var (blo, bhi) = Box(b.Outline);
                if (Math.Abs(alo.X - blo.X) > 1e-3 || Math.Abs(ahi.X - bhi.X) > 1e-3)
                    continue;
                if (Math.Max(alo.Y, blo.Y) - Math.Min(ahi.Y, bhi.Y) > ColumnGap)
                    continue;
                a.Outline = Rect(new P(alo.X, Math.Min(alo.Y, blo.Y)), new P(ahi.X, Math.Max(ahi.Y, bhi.Y)));
                a.Tiles.AddRange(b.Tiles);
                a.Visual.AddRange(b.Visual);
                a.Piles.AddRange(b.Piles);
                a.Note += b.Note;
                a.ZMin = Math.Min(a.ZMin, b.ZMin);
                a.ZMax = Math.Max(a.ZMax, b.ZMax);
                members.RemoveAt(j);
                result.ColumnJoins++;
                joined = true;
            }
        }
        foreach (var m in members)
            foreach (var t in m.Tiles)
                if (m.Tiles.Count > 1 && m.Role == Role.Post && m.Tiles.Select(x => Box(Ccw(x.Hull)).lo.Y).Distinct().Count() > 1)
                    rows[t].note += "Joined into one post column with " + (m.Tiles.Count - 1) + " other tile(s). ";

        // 5. Partition: the continuous member keeps the overlap, the other is cut at its face (glued in step 6).
        members = members
            .OrderBy(m => Priority(m.Role))
            .ThenByDescending(m => Box(m.Outline).hi.Y)
            .ThenBy(m => Box(m.Outline).lo.X)
            .ThenBy(m => m.First, StringComparer.Ordinal)
            .ToList();
        var parts = new List<Part>();
        var memberOf = new List<Member>();
        foreach (var m in members)
        {
            var pieces = new List<P[]> { m.Outline };
            var cutBy = new List<string>();
            foreach (var kept in parts)
            {
                var next = new List<P[]>();
                bool touched = false;
                foreach (var piece in pieces)
                {
                    if (OverlapArea(piece, kept.Outline) <= 1e-7)
                    {
                        next.Add(piece);
                        continue;
                    }
                    touched = true;
                    next.AddRange(Difference(piece, kept.Outline));
                }
                if (touched)
                    cutBy.Add(kept.Tiles.Count > 0 ? kept.Tiles[0] : "pile");
                pieces = next;
            }
            var made = new List<int>();
            foreach (var piece in pieces)
            {
                if (Sliver(piece))
                {
                    double area = Math.Max(0, Area(piece));
                    result.DroppedSlivers++;
                    result.DroppedArea += area;
                    result.MaxDroppedArea = Math.Max(result.MaxDroppedArea, area);
                    if (area > MaxDroppedArea)
                        throw new InvariantException("I1", m.First, "a visible piece (area " + F(area) + ", " + F(Thickness(piece)) + " thick) is too thin to become a part; it would be decoration");
                    continue;
                }
                var part = new Part
                {
                    Index = parts.Count,
                    Role = m.Role,
                    Material = m.Material,
                    Outline = Ccw(piece),
                    ZMin = m.ZMin,
                    ZMax = m.ZMax,
                    Note = m.Note + (cutBy.Count > 0 ? "Cut at the faces of " + string.Join(", ", cutBy.Distinct()) + " (glued). " : ""),
                };
                part.Tiles.AddRange(m.Tiles.Select(t => t.Path));
                foreach (var v in m.Visual)
                    if (OverlapArea(Ccw(v.Hull), part.Outline) > 1e-7)
                        part.Visual.Add(v.Path);
                foreach (var pile in m.Piles)
                    if (OverlapArea(Rect(pile.Lo, pile.Hi), part.Outline) > 1e-7)
                        part.Piles.Add(pile);
                if (part.Visual.Count == 0 && part.Piles.Count == 0 && m.Visual.Count > 0)
                    part.Visual.Add(m.Visual[0].Path);
                made.Add(part.Index);
                parts.Add(part);
                memberOf.Add(m);
            }
            foreach (var t in m.Tiles)
            {
                var row = rows[t];
                row.parts = made.ToArray();
                if (made.Count > 0)
                    row.classification = "part";
                else
                {
                    // Wholly inside parts that were kept whole: what you see there is those parts.
                    row.classification = "covered";
                    row.note += "Wholly inside " + string.Join(", ", cutBy.Distinct()) + ", which already stand for this area. ";
                }
                if (cutBy.Count > 0 && made.Count > 0)
                    row.note += "Cut at the faces of " + string.Join(", ", cutBy.Distinct()) + "; " + made.Count + " part(s). ";
            }
        }
        result.Parts = parts;

        // 5b. OD-7 nudges: small geometry changes so the structure bears by contact. Glue (step 6) is found on the nudged outlines.
        Nudge(parts, result);

        // 6. Glue every contact the native sampler sees from both sides.
        for (int i = 0; i < parts.Count; i++)
        for (int j = i + 1; j < parts.Count; j++)
        {
            var (alo, ahi) = Box(parts[i].Outline);
            var (blo, bhi) = Box(parts[j].Outline);
            if (Math.Max(alo.X, blo.X) - Math.Min(ahi.X, bhi.X) > GlueFillet || Math.Max(alo.Y, blo.Y) - Math.Min(ahi.Y, bhi.Y) > GlueFillet)
                continue;
            double w = GlueWeight(parts[i].Outline, parts[j].Outline);
            if (w >= MinGlueWeight)
                result.Glue.Add(new GlueLink { A = i, B = j, Weight = w });
        }

        // 7. Anchors only at real support (I3).
        var terrain = parts.Where(p => p.Role == Role.Terrain).ToList();
        if (terrain.Count > 0)
            result.TerrainFloor = terrain.Min(p => Box(p.Outline).lo.Y);
        foreach (var part in parts)
        {
            var o = part.Outline;
            for (int i = 0; i < o.Length; i++)
            {
                P a = o[i],
                    b = o[(i + 1) % o.Length];
                if (Math.Abs(a.Y - b.Y) > 1e-6 || b.X <= a.X)
                    continue; // only downward-facing (bottom) edges can rest on something; on a CCW outline they run left to right
                double y = a.Y;
                if (part.Piles.Count > 0 && Math.Abs(y - floor) < 1e-6)
                {
                    part.Anchors.Add(new Anchor { A = a, B = b, Support = "pile foot on the riverbed (" + bottom.Name + " top, OD-3)" });
                    continue;
                }
                if (part.Role == Role.Terrain && y - result.TerrainFloor <= TerrainFloorBand && !Below(parts, part, a, b))
                {
                    part.Anchors.Add(new Anchor { A = a, B = b, Support = "bottom of the terrain mass (bedrock)" });
                    continue;
                }
                if (part.Role == Role.Post)
                    foreach (var ground in terrain)
                    {
                        var g = ground.Outline;
                        for (int k = 0; k < g.Length; k++)
                        {
                            P c = g[k],
                                d = g[(k + 1) % g.Length];
                            if (Math.Abs(c.Y - d.Y) > 1e-6 || d.X >= c.X || y - c.Y < -1e-6 || y - c.Y > SupportGap)
                                continue; // terrain top edges (CCW: right to left) at or just below the foot
                            double x0 = Math.Max(a.X, d.X),
                                x1 = Math.Min(b.X, c.X);
                            if (x1 - x0 >= .05)
                                part.Anchors.Add(new Anchor { A = new P(x0, y), B = new P(x1, y), Support = "post foot standing on terrain " + ground.Tiles[0] });
                        }
                    }
            }
        }
        foreach (var part in parts)
            foreach (var path in part.Tiles)
            {
                var row = result.Rows.Find(r => r.path == path);
                if (part.Anchors.Count > 0 && row != null && !row.note.Contains("Anchored"))
                    row.note += "Anchored: " + part.Anchors[0].Support + ". ";
            }

        Check(result, rules, floor);
        return result;
    }

    static string Pt(P p) => "(" + p.X.ToString("0.####", CultureInfo.InvariantCulture) + ", " + p.Y.ToString("0.####", CultureInfo.InvariantCulture) + ")";

    static bool Convex(P[] p)
    {
        for (int i = 0; i < p.Length; i++)
        {
            P a = p[i],
                b = p[(i + 1) % p.Length],
                c = p[(i + 2) % p.Length];
            if ((b.X - a.X) * (c.Y - b.Y) - (b.Y - a.Y) * (c.X - b.X) < -Eps)
                return false;
        }
        return true;
    }

    static bool Free(List<Part> parts, Part self, P[] region)
    {
        foreach (var other in parts)
            if (other != self && OverlapArea(region, other.Outline) > 1e-7)
                return false;
        return true;
    }

    // OD-7 nudges, applied to the partitioned parts (CCW outlines). Each one is listed in result.Nudges and the part's note.
    static void Nudge(List<Part> parts, Result result)
    {
        // a. Bearing: a horizontal part fully over another horizontal part, floating up to BearingGap above its top, grows down onto it.
        foreach (var part in parts.Where(p => p.Role == Role.Horizontal && IsAxisRect(p.Outline)))
        {
            var (lo, hi) = Box(part.Outline);
            double top = double.NaN;
            foreach (var other in parts)
            {
                if (other == part || other.Role != Role.Horizontal || !IsAxisRect(other.Outline))
                    continue;
                var (olo, ohi) = Box(other.Outline);
                double gap = lo.Y - ohi.Y;
                if (gap > 1e-6 && gap <= BearingGap && olo.X <= lo.X + 1e-6 && ohi.X >= hi.X - 1e-6)
                    top = double.IsNaN(top) ? ohi.Y : Math.Max(top, ohi.Y);
            }
            if (double.IsNaN(top) || !Free(parts, part, Rect(new P(lo.X, top), new P(hi.X, lo.Y))))
                continue;
            part.Outline = Rect(new P(lo.X, top), hi);
            string what = "bottom y " + F4(lo.Y) + " -> " + F4(top) + " (rests on the part below; x " + F4(lo.X) + ".." + F4(hi.X) + ")";
            result.Nudges.Add("part " + part.Index + " " + part.Tiles.FirstOrDefault() + ": " + what);
            part.Note += "OD-7 nudge: " + what + ". ";
        }

        // a2. Post bearing (OD-10): a post whose top stops up to BearingGap below the bottom of a horizontal part directly above it grows up to meet it.
        foreach (var part in parts.Where(p => p.Role == Role.Post && IsAxisRect(p.Outline)))
        {
            var (lo, hi) = Box(part.Outline);
            double bottom = double.NaN;
            foreach (var other in parts)
            {
                if (other == part || other.Role != Role.Horizontal || !IsAxisRect(other.Outline))
                    continue;
                var (olo, ohi) = Box(other.Outline);
                double gap = olo.Y - hi.Y;
                if (gap > 1e-6 && gap <= BearingGap && Math.Min(hi.X, ohi.X) - Math.Max(lo.X, olo.X) > 1e-6)
                    bottom = double.IsNaN(bottom) ? olo.Y : Math.Min(bottom, olo.Y);
            }
            if (double.IsNaN(bottom) || !Free(parts, part, Rect(new P(lo.X, hi.Y), new P(hi.X, bottom))))
                continue;
            // move the top vertices in place (keeps the outline's vertex order; G5b attempt 1 rebuilt the rectangle and the native creep timing changed with it)
            part.Outline = part.Outline.Select(v => Math.Abs(v.Y - hi.Y) < 1e-9 ? new P(v.X, bottom) : v).ToArray();
            string what = "top y " + F4(hi.Y) + " -> " + F4(bottom) + " (meets the part above; x " + F4(lo.X) + ".." + F4(hi.X) + ")";
            result.Nudges.Add("part " + part.Index + " " + part.Tiles.FirstOrDefault() + ": " + what);
            part.Note += "OD-7 nudge: " + what + ". ";
        }

        // b. Brace seat: a brace corner on a girder underside within SeatSnap of a post face moves onto the face and gains a SeatHeight seat there.
        foreach (var part in parts.Where(p => p.Role == Role.Brace && p.Outline.Length == 4))
        {
            var o = part.Outline;
            for (int i = 0; i < o.Length; i++)
            {
                P v = o[i];
                bool onGirder = parts.Any(h => h.Role == Role.Horizontal && Math.Abs(Box(h.Outline).lo.Y - v.Y) < 1e-6 && Box(h.Outline).lo.X < v.X && Box(h.Outline).hi.X > v.X);
                if (!onGirder)
                    continue;
                double face = double.NaN;
                foreach (var post in parts.Where(p => p.Role == Role.Post && IsAxisRect(p.Outline)))
                {
                    var (plo, phi) = Box(post.Outline);
                    if (v.Y < plo.Y + SeatHeight - 1e-6 || v.Y > phi.Y + 1e-6)
                        continue;
                    foreach (double f in new[] { plo.X, phi.X })
                        if (Math.Abs(v.X - f) <= SeatSnap && (v.X < plo.X - 1e-9 || v.X > phi.X + 1e-9 || Math.Abs(v.X - f) < 1e-9))
                            face = f;
                }
                if (double.IsNaN(face))
                    continue;
                int prev = (i + o.Length - 1) % o.Length,
                    next = (i + 1) % o.Length;
                // the seat goes between the corner and its neighbour below the girder (the brace's lower edge)
                bool belowPrev = o[prev].Y < v.Y - 1e-3;
                if (belowPrev == o[next].Y < v.Y - 1e-3)
                    continue;
                P corner = new P(face, v.Y),
                    seat = new P(face, v.Y - SeatHeight);
                var list = o.ToList();
                list[i] = corner;
                list.Insert(belowPrev ? i : i + 1, seat);
                var nudged = list.ToArray();
                if (!Convex(nudged) || !Free(parts, part, nudged))
                {
                    result.Notes.Add("OD-7 seat skipped on part " + part.Index + " at " + Pt(v) + ": not convex or overlaps another part.");
                    continue;
                }
                string what = "brace end " + Pt(v) + " -> " + Pt(corner) + " on the post face, seat corner " + Pt(seat) + " added";
                result.Nudges.Add("part " + part.Index + " " + part.Tiles.FirstOrDefault() + ": " + what);
                part.Note += "OD-7 nudge: " + what + ". ";
                part.Outline = nudged;
                break; // one seat per brace end; the other end meets a post face or a girder already
            }
        }
    }

    static string F4(double v) => v.ToString("0.####", CultureInfo.InvariantCulture);

    // Is there another part directly under the bottom edge a-b (within the glue fillet)? Then that edge rests on it, not on bedrock.
    static bool Below(List<Part> parts, Part self, P a, P b)
    {
        var probe = Rect(new P(a.X + 1e-3, a.Y - SupportGap), new P(b.X - 1e-3, a.Y - 1e-4));
        foreach (var other in parts)
            if (other != self && OverlapArea(probe, other.Outline) > 1e-6)
                return true;
        return false;
    }

    // The export-failure checks for I1-I4 and the native budgets, on the mapped result.
    public static void Check(Result r, Rules rules, double floor)
    {
        // I1: every in-arena tile is a part (or wholly covered by parts); nothing is decoration.
        foreach (var row in r.Rows)
            if (row.classification != "part" && row.classification != "covered" && row.classification != "outside arena")
                throw new InvariantException("I1", row.path, "is '" + row.classification + "', not a part");
        // I2 is enforced on the inputs (only the named boundaries are fixed; nothing is indestructible).
        // I3: anchors only on bottom edges with a real support under them, never on every edge; the Bridge has exactly its pile feet.
        foreach (var part in r.Parts)
        {
            if (part.Anchors.Count >= part.Outline.Length)
                throw new InvariantException("I3", part.Tiles.FirstOrDefault() ?? "pile", "anchored on every edge");
            foreach (var anchor in part.Anchors)
            {
                if (Math.Abs(anchor.A.Y - anchor.B.Y) > 1e-6 || anchor.B.X <= anchor.A.X)
                    throw new InvariantException("I3", part.Tiles.FirstOrDefault() ?? "pile", "anchor " + anchor.A + "-" + anchor.B + " is not on a bottom edge");
                bool onBoundary = false;
                var o = part.Outline;
                for (int i = 0; i < o.Length && !onBoundary; i++)
                    onBoundary = Math.Abs(o[i].Y - anchor.A.Y) < 1e-6 && Math.Abs(o[(i + 1) % o.Length].Y - anchor.A.Y) < 1e-6
                        && Math.Min(o[i].X, o[(i + 1) % o.Length].X) <= anchor.A.X + 1e-6 && Math.Max(o[i].X, o[(i + 1) % o.Length].X) >= anchor.B.X - 1e-6;
                if (!onBoundary)
                    throw new InvariantException("I3", part.Tiles.FirstOrDefault() ?? "pile", "anchor " + anchor.A + "-" + anchor.B + " is not on the part's outline");
                if (string.IsNullOrEmpty(anchor.Support))
                    throw new InvariantException("I3", part.Tiles.FirstOrDefault() ?? "pile", "anchor without a named support");
            }
        }
        if (rules.Piles > 0)
        {
            var anchored = r.Parts.Where(p => p.Anchors.Count > 0).ToList();
            var piles = anchored.Where(p => p.Piles.Count > 0 && p.Anchors.All(a => Math.Abs(a.A.Y - floor) < 1e-6)).ToList();
            if (anchored.Count != rules.Piles || piles.Count != rules.Piles)
                throw new InvariantException("I3", rules.Level, "anchors must be exactly the " + rules.Piles + " pile feet (OD-3); found " + anchored.Count + " anchored part(s), " + piles.Count + " pile feet");
        }
        // I4: palette material on every part, no overlaps (so no allowed_overlaps), every glue link sampled from both sides.
        foreach (var part in r.Parts)
            if (string.IsNullOrEmpty(part.Material))
                throw new InvariantException("I4", part.Tiles.FirstOrDefault() ?? "pile", "part without an OD-2 material");
        for (int i = 0; i < r.Parts.Count; i++)
        {
            for (int j = i + 1; j < r.Parts.Count; j++)
            {
                double ov = OverlapArea(r.Parts[i].Outline, r.Parts[j].Outline);
                if (ov > 1e-6)
                    throw new InvariantException("I4", r.Parts[i].Tiles.FirstOrDefault() ?? "pile", "overlaps " + (r.Parts[j].Tiles.FirstOrDefault() ?? "pile") + " by " + F(ov) + "; overlaps must be partitioned, never allowed");
            }
            foreach (var b in r.Boundaries)
                if (OverlapArea(r.Parts[i].Outline, Rect(b.Lo, b.Hi)) > 1e-6)
                    throw new InvariantException("I4", r.Parts[i].Tiles.FirstOrDefault() ?? "pile", "overlaps the fixed " + b.Name);
        }
        foreach (var link in r.Glue)
            if (link.A == link.B || link.A < 0 || link.B < 0 || link.A >= r.Parts.Count || link.B >= r.Parts.Count || GlueWeight(r.Parts[link.A].Outline, r.Parts[link.B].Outline) < MinGlueWeight)
                throw new InvariantException("I4", link.A >= 0 && link.A < r.Parts.Count ? r.Parts[link.A].Tiles.FirstOrDefault() ?? "pile" : "?", "glue link " + link.A + "-" + link.B + " has no native glue samples (parts do not touch within the 0.2 fillet)");
        // Native budgets (level_layout.odin): parts, sources (one per part + boundaries), glue links.
        if (r.Parts.Count > MaxParts || r.Parts.Count + r.Boundaries.Count > MaxSources)
            throw new InvariantException("budget", rules.Level, r.Parts.Count + " parts exceed the native budget (" + MaxParts + " parts, " + MaxSources + " sources)");
        if (r.Glue.Count > MaxGlue)
            throw new InvariantException("budget", rules.Level, r.Glue.Count + " glue links exceed the native budget " + MaxGlue);
    }
}
