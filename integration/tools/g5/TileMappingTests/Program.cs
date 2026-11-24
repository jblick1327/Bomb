using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;
using static BomTileMapping;

// G5 negative tests and dry runs for BomTileMapping (see TileMappingTests.csproj).
static class Program
{
    static int failures;

    static int Main(string[] args)
    {
        if (args.Length >= 2 && args[0] == "map")
            return MapFile(args[1], args.Length > 2 ? args[2] : null);
        if (args.Length >= 1 && args[0] == "test")
            return Tests();
        Console.Error.WriteLine("usage: test | map <input.json> [report.json]");
        return 2;
    }

    // ---------------- input dumps ----------------
    static P V(JsonElement e) => new P(e[0].GetDouble(), e[1].GetDouble());

    public static Input Load(string path)
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        var root = doc.RootElement;
        var r = root.GetProperty("rules");
        var input = new Input
        {
            Rules = new Rules
            {
                Level = r.GetProperty("level").GetString(),
                PlaneZ = r.GetProperty("plane_z").GetDouble(),
                Materials = r.GetProperty("materials").EnumerateArray().Select(m => (m[0].GetString(), m[1].GetString())).ToArray(),
                Piles = r.GetProperty("piles").GetInt32(),
                PileMaterial = r.GetProperty("pile_material").GetString(),
            },
        };
        foreach (var b in root.GetProperty("boundaries").EnumerateArray())
            input.Boundaries.Add(new Boundary { Name = b.GetProperty("name").GetString(), Lo = V(b.GetProperty("lo")), Hi = V(b.GetProperty("hi")), Indestructible = b.GetProperty("indestructible").GetBoolean(), Visible = b.GetProperty("visible").GetBoolean() });
        foreach (var t in root.GetProperty("tiles").EnumerateArray())
            input.Tiles.Add(new Tile
            {
                Path = t.GetProperty("path").GetString(),
                Name = t.GetProperty("name").GetString(),
                Behaviour = t.GetProperty("behaviour").GetString(),
                DarrynMaterial = t.GetProperty("darryn_material").GetString(),
                Hull = t.GetProperty("hull").EnumerateArray().Select(V).ToArray(),
                ZMin = t.GetProperty("zmin").GetDouble(),
                ZMax = t.GetProperty("zmax").GetDouble(),
            });
        return input;
    }

    static int MapFile(string path, string report)
    {
        var input = Load(path);
        try
        {
            var r = Map(input);
            var summary = new Dictionary<string, object>
            {
                ["level"] = r.Level,
                ["tiles"] = r.Tiles,
                ["in_arena"] = r.InArena,
                ["outside_arena"] = r.OutsideArena,
                ["backdrop"] = r.Backdrop,
                ["merged_duplicates"] = r.MergedDuplicates,
                ["column_joins"] = r.ColumnJoins,
                ["brought_onto_plane"] = r.BroughtOntoPlane,
                ["covered"] = r.Rows.Count(x => x.classification == "covered"),
                ["parts"] = r.Parts.Count,
                ["parts_by_role"] = r.Parts.GroupBy(p => p.Role.ToString()).ToDictionary(g => g.Key, g => g.Count()),
                ["parts_by_material"] = r.Parts.GroupBy(p => p.Material).ToDictionary(g => g.Key, g => g.Count()),
                ["glue_links"] = r.Glue.Count,
                ["anchored_parts"] = r.Parts.Count(p => p.Anchors.Count > 0),
                ["anchor_segments"] = r.Parts.Sum(p => p.Anchors.Count),
                ["piles"] = r.Parts.Sum(p => p.Piles.Count),
                ["dropped_slivers"] = r.DroppedSlivers,
                ["dropped_area"] = Math.Round(r.DroppedArea, 4),
                ["max_dropped_area"] = Math.Round(r.MaxDroppedArea, 4),
                ["nudges"] = r.Nudges,
            };
            Console.WriteLine(JsonSerializer.Serialize(summary));
            if (report != null)
                File.WriteAllText(report, JsonSerializer.Serialize(new
                {
                    summary,
                    parts = r.Parts.Select(p => new { p.Index, role = p.Role.ToString(), p.Material, outline = p.Outline.Select(v => new[] { Math.Round(v.X, 4), Math.Round(v.Y, 4) }), anchors = p.Anchors.Select(a => a.Support), p.Tiles, p.Visual, piles = p.Piles.Count, p.Note }),
                    glue = r.Glue.Select(g => new[] { g.A, g.B }),
                    rows = r.Rows,
                }, new JsonSerializerOptions { WriteIndented = true, IncludeFields = true }));
            return 0;
        }
        catch (InvariantException e)
        {
            Console.WriteLine("EXPORT FAILED " + e.Message);
            return 1;
        }
    }

    // ---------------- negative tests ----------------
    static Tile Box(string path, double x0, double y0, double x1, double y1, double z0 = -2, double z1 = 2) =>
        new Tile { Path = "Test/" + path, Name = path, Behaviour = "Carve", DarrynMaterial = "Test.mat", Hull = Rect(new P(x0, y0), new P(x1, y1)), ZMin = z0, ZMax = z1 };

    static Input Arena(string level, params Tile[] tiles)
    {
        var input = new Input { Rules = new Rules { Level = level, Materials = new[] { ("Ground", "earth"), ("Deck", "wood"), ("Post", "steel"), ("Slab", "stone") }, PileMaterial = "steel" } };
        input.Boundaries.Add(new Boundary { Name = "Left Wall", Lo = new P(-10.6, -20), Hi = new P(-10, 20) });
        input.Boundaries.Add(new Boundary { Name = "Right Wall", Lo = new P(10, -20), Hi = new P(10.6, 20) });
        input.Boundaries.Add(new Boundary { Name = "Bottom Boundary", Lo = new P(-10.6, -20.6), Hi = new P(10.6, -20) });
        input.Tiles.AddRange(tiles);
        return input;
    }

    static void Expect(string name, string invariant, string tile, Func<Input> make)
    {
        try
        {
            Map(make());
            Fail(name + ": export passed, expected an " + invariant + " failure naming " + tile);
        }
        catch (InvariantException e)
        {
            if (e.Invariant == invariant && e.Message.Contains(tile))
                Console.WriteLine("PASS " + name + " -> " + e.Message);
            else
                Fail(name + ": wrong failure: " + e.Message);
        }
    }

    static void Fail(string message)
    {
        failures++;
        Console.WriteLine("FAIL " + message);
    }

    static Result Pass(string name, Input input)
    {
        try
        {
            var r = Map(input);
            Console.WriteLine("PASS " + name + " -> parts=" + r.Parts.Count + " glue=" + r.Glue.Count + " anchored=" + r.Parts.Count(p => p.Anchors.Count > 0));
            return r;
        }
        catch (InvariantException e)
        {
            Fail(name + ": " + e.Message);
            return null;
        }
    }

    // A tiny two-deck bridge: decks on posts, five columns, piles to the floor.
    static Input Bridge(int columns)
    {
        var tiles = new List<Tile> { Box("Deck A", -9, 0, 9, .5), Box("Deck B", -9, 4, 9, 4.5) };
        for (int i = 0; i < columns; i++)
        {
            double x = -8 + i * 4;
            tiles.Add(Box("Post " + i + " (1)", x, -1, x + .34, 2.5, 2.08, 2.42));
            tiles.Add(Box("Post " + i + " (2)", x, 2.5, x + .34, 4.8, 2.08, 2.42));
            tiles.Add(Box("Post " + i + " (3)", x, -1, x + .34, 2.5, -2.42, -2.08)); // rear duplicate
        }
        var input = Arena("TinyBridge", tiles.ToArray());
        input.Rules.Piles = 5;
        return input;
    }

    static int Tests()
    {
        // Positive controls: the same small inputs pass when they are not broken.
        var yard = Pass("control yard (terrain, posts, slab)", Arena("TinyYard",
            Box("Ground (1)", -10.5, -3, 0.2, 0, -5, 5), Box("Ground (2)", 0, -3.1, 10.5, 0.05, -5, 5),
            Box("Post (1)", -4, -0.05, -3, 2.5, 1.06, 1.76), Box("Slab (1)", -6, 2.5, 6, 3.5)));
        if (yard != null)
        {
            if (yard.Parts.Any(p => p.Role == Role.Terrain && p.Anchors.Count == 0)) Fail("control yard: a terrain part at the floor is not anchored");
            if (yard.Parts.Any(p => p.Role == Role.Horizontal && p.Anchors.Count > 0)) Fail("control yard: the slab is anchored (it must hang on glue)");
            if (!yard.Parts.Any(p => p.Role == Role.Post && p.Anchors.Count == 1)) Fail("control yard: the post foot on terrain is not anchored");
            if (yard.OutsideArena != 0 || yard.Rows.Any(r => r.classification != "part")) Fail("control yard: a tile is not a part");
            if (yard.Glue.Count < 3) Fail("control yard: expected glue ground-ground, ground-post, post-slab");
        }
        var bridge = Pass("control bridge (5 piles)", Bridge(5));
        if (bridge != null && (bridge.Parts.Count(p => p.Anchors.Count > 0) != 5 || bridge.MergedDuplicates != 5))
            Fail("control bridge: expected 5 anchored pile columns and 5 merged rear duplicates");

        // I1: a visible tile that cannot become a part (a 0.03-thick strip), and a tile with no silhouette.
        Expect("I1 thin strip", "I1", "Test/Slab (9)", () => Arena("I1", Box("Ground (1)", -10, -3, 10, 0, -5, 5), Box("Slab (9)", -5, 1, 5, 1.03)));
        Expect("I1 no mesh", "I1", "Test/Slab (8)", () =>
        {
            var input = Arena("I1b", Box("Ground (1)", -10, -3, 10, 0, -5, 5));
            input.Tiles.Add(new Tile { Path = "Test/Slab (8)", Name = "Slab (8)", Hull = Array.Empty<P>() });
            return input;
        });
        // I2: an indestructible boundary, and a fixed source that is not one of the existing boundary walls.
        Expect("I2 indestructible wall", "I2", "Left Wall", () =>
        {
            var input = Arena("I2", Box("Ground (1)", -10, -3, 10, 0, -5, 5));
            input.Boundaries[0].Indestructible = true;
            return input;
        });
        Expect("I2 extra fixed", "I2", "Middle Pillar", () =>
        {
            var input = Arena("I2b", Box("Ground (1)", -10, -3, 10, 0, -5, 5));
            input.Boundaries.Add(new Boundary { Name = "Middle Pillar", Lo = new P(-1, 0), Hi = new P(1, 5) });
            return input;
        });
        // I3: a bridge whose lowest feet are not the five OD-3 piles, and a part anchored on every edge (C6's rule).
        Expect("I3 four piles", "I3", "TinyBridge", () => Bridge(4));
        try
        {
            var r = Map(Arena("I3b", Box("Ground (1)", -10, -3, 10, 0, -5, 5), Box("Slab (1)", -2, 3, 2, 4)));
            var slab = r.Parts.First(p => p.Role == Role.Horizontal);
            var o = slab.Outline;
            for (int i = 0; i < o.Length; i++)
                slab.Anchors.Add(new Anchor { A = o[i], B = o[(i + 1) % o.Length], Support = "every edge (C6)" });
            Check(r, new Rules { Level = "I3b" }, -20);
            Fail("I3 every edge: check passed");
        }
        catch (InvariantException e)
        {
            if (e.Invariant == "I3" && e.Message.Contains("Test/Slab (1)")) Console.WriteLine("PASS I3 every edge -> " + e.Message);
            else Fail("I3 every edge: wrong failure: " + e.Message);
        }
        // I4: a tile the OD-2 material table does not name, and a glue link between parts that do not touch.
        Expect("I4 no material", "I4", "Test/Railing (1)", () => Arena("I4", Box("Ground (1)", -10, -3, 10, 0, -5, 5), Box("Railing (1)", -1, 2, 1, 2.5)));
        try
        {
            var r = Map(Arena("I4b", Box("Ground (1)", -10, -3, 10, 0, -5, 5), Box("Slab (1)", -2, 3, 2, 4)));
            r.Glue.Add(new GlueLink { A = 0, B = 1 });
            Check(r, new Rules { Level = "I4b" }, -20);
            Fail("I4 zero-sample glue: check passed");
        }
        catch (InvariantException e)
        {
            if (e.Invariant == "I4" && e.Message.Contains("no native glue samples")) Console.WriteLine("PASS I4 zero-sample glue -> " + e.Message);
            else Fail("I4 zero-sample glue: wrong failure: " + e.Message);
        }
        Console.WriteLine(failures == 0 ? "ALL PASS" : failures + " FAILED");
        return failures == 0 ? 0 : 1;
    }
}
