using System;
using System.Linq;
using Bom.Unity;
using UnityEditor;
using UnityEngine;

// G7/G8, OD-1/OD-5: drawn, destructible bedrock. Legacy boundary colliders are mapping metadata only.
public static class BomArenaBoundaryBuilder
{
    public static BomCustomMaterial Bedrock() => BomMaterialConfig.Get("bedrock"); // values: integration/fixtures/materials.json (G6b)

    static Material RockMaterial()
    {
        const string path = "Assets/BOMIntegration/Bedrock.mat";
        var material = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (material == null)
        {
            material = new Material(AssetDatabase.LoadAssetAtPath<Material>("Assets/BOMIntegration/NativeFallback.mat"));
            material.name = "Bedrock";
            material.color = Bedrock().Color;
            AssetDatabase.CreateAsset(material, path);
        }
        return material;
    }

    public static void AddWalls(BomLevelAuthoring level, float left, float right, float bottom, float top, float outer)
    {
        level.Materials.Add(Bedrock());
        Wall(level, "Left bedrock", new Vector2(-outer, bottom), new Vector2(left, top));
        Wall(level, "Right bedrock", new Vector2(right, bottom), new Vector2(outer, top));
    }

    static void Wall(BomLevelAuthoring level, string name, Vector2 lo, Vector2 hi)
    {
        var root = new GameObject(name);
        root.transform.SetParent(level.transform, false);
        var source = root.AddComponent<BomAssetInstance>();
        source.AssetKey = "bedrock/" + name;
        source.OriginalObjectPath = name;
        source.Motion = BomMotionPolicy.Anchored;
        source.Damage = BomDamagePolicy.Destructible;
        source.FallbackDepth = new Vector2(-.8f, .8f);
        source.ApproximationNote = "OD-1/OD-5 bedrock: visible arena edge, anchored only along its bottom; Stone 1.4/4";
        var art = GameObject.CreatePrimitive(PrimitiveType.Cube);
        art.name = "Bedrock rock face";
        UnityEngine.Object.DestroyImmediate(art.GetComponent<Collider>());
        art.transform.SetParent(root.transform, false);
        art.transform.position = new Vector3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, 0);
        art.transform.localScale = new Vector3(hi.x - lo.x, hi.y - lo.y, 1.6f);
        art.GetComponent<MeshRenderer>().sharedMaterial = RockMaterial();
        art.GetComponent<MeshRenderer>().enabled = false;
        // Same solid envelope and art. Limit the terrain-facing part's cell count so the unchanged native
        // Cartesian glue sampler does not pair the entire tall wall with Classic's large ground part.
        float split = name.StartsWith("Left", StringComparison.Ordinal) ? hi.x - .3f : lo.x + .3f;
        var a = WallPart(root, "Bedrock west", lo, new Vector2(split, hi.y));
        var b = WallPart(root, "Bedrock east", new Vector2(split, lo.y), hi);
        level.Glue.Add(new BomGlueAuthoring { A = a, B = b });
    }

    static BomPhysicsPart WallPart(GameObject root, string name, Vector2 lo, Vector2 hi)
    {
        var child = new GameObject(name); child.transform.SetParent(root.transform, false);
        var part = child.AddComponent<BomPhysicsPart>();
        part.WorldRestCoordinates = true;
        part.Minimum = lo; part.Maximum = hi; part.MaterialKey = "bedrock";
        part.Anchors = new[] { new BomAnchorSegment { A = lo, B = new Vector2(hi.x, lo.y) } };
        return part;
    }

    public static void Check(BomLevelAuthoring level)
    {
        foreach (var s in level.GetComponentsInChildren<BomAssetInstance>(true).Where(s => s.IncludeInExport))
            if (s.HiddenVisual || s.Motion == BomMotionPolicy.Fixed || s.Damage != BomDamagePolicy.Destructible)
                throw new InvalidOperationException("I2 " + s.OriginalObjectPath + ": hidden/fixed/indestructible source");
        if (level.AllowedOverlaps.Count != 0) throw new InvalidOperationException("I4 allowed overlaps");
        var parts = level.GetComponentsInChildren<BomPhysicsPart>(true).Where(p => p.GetComponentInParent<BomAssetInstance>(true).IncludeInExport).ToArray();
        foreach (var p in parts)
        {
            var outline = p.WorldOutline();
            if (string.IsNullOrEmpty(p.MaterialKey)) throw new InvalidOperationException("I4 material missing");
            foreach (var a in p.WorldAnchors())
                if (Mathf.Abs(a.A.y - a.B.y) > .00001f || a.B.x <= a.A.x || Mathf.Abs(a.A.y - outline.Min(v => v.y)) > .00001f)
                    throw new InvalidOperationException("I3 anchor must be on supported bottom edge: " + p.name);
        }
        for (int i = 0; i < parts.Length; i++)
        for (int j = i + 1; j < parts.Length; j++)
            if (BomTileMapping.OverlapArea(Points(parts[i]), Points(parts[j])) > .000001)
                throw new InvalidOperationException("I4 overlap: " + parts[i].name + " / " + parts[j].name);
        foreach (var g in level.Glue)
            if (BomTileMapping.GlueWeight(Points(g.A), Points(g.B)) < BomTileMapping.MinGlueWeight)
                throw new InvalidOperationException("I4 zero-sample glue");
    }

    public static BomTileMapping.P[] Points(BomPhysicsPart part) => part.WorldOutline().Select(v => new BomTileMapping.P(v.x, v.y)).ToArray();

    static void GlueContacts(BomLevelAuthoring level)
    {
        level.Glue.Clear();
        var parts = level.GetComponentsInChildren<BomPhysicsPart>(true).Where(p => p.GetComponentInParent<BomAssetInstance>(true).IncludeInExport).ToArray();
        for (int i = 0; i < parts.Length; i++)
        for (int j = i + 1; j < parts.Length; j++)
            if (BomTileMapping.GlueWeight(Points(parts[i]), Points(parts[j])) >= BomTileMapping.MinGlueWeight)
                level.Glue.Add(new BomGlueAuthoring { A = parts[i], B = parts[j] });
    }

    static void PartitionTerrain(BomLevelAuthoring level)
    {
        var source = level.GetComponentsInChildren<BomAssetInstance>(true).Single(s => s.OriginalObjectPath == "YardLevel");
        foreach (var old in source.GetComponentsInChildren<BomPhysicsPart>(true))
        {
            Vector2 lo = old.Minimum, hi = old.Maximum; string material = old.MaterialKey;
            for (float y = lo.y; y < hi.y; y += 6)
            for (float x = lo.x; x < hi.x; x += 6)
            {
                var child = new GameObject("G7 " + material + " " + x + " " + y); child.transform.SetParent(source.transform, false);
                var p = child.AddComponent<BomPhysicsPart>(); p.WorldRestCoordinates = true;
                p.Minimum = new Vector2(x, y); p.Maximum = new Vector2(Mathf.Min(x + 6, hi.x), Mathf.Min(y + 6, hi.y));
                p.MaterialKey = material;
                if (material == "earth" && Mathf.Abs(y + 25) < .001f)
                    p.Anchors = new[] { new BomAnchorSegment { A = p.Minimum, B = new Vector2(p.Maximum.x, y) } };
                p.ApproximationNote = "G7 exact partition of existing terrain; unchanged union and art, 6x6 maximum; bottom anchors only";
            }
            UnityEngine.Object.DestroyImmediate(old.gameObject);
        }
    }

    // Odin culls by a subdivision's pose position, not by its outline. Include a whole level diagonal beyond
    // the camera footprint: even a rotating fragment with its reference point at one extreme is off screen first.
    // Covers landscape/portrait aspect ratios 1:4 through 4:1; the camera itself is unchanged.
    public static void SetCullBounds(BomLevelAuthoring level)
    {
        var points = level.GetComponentsInChildren<BomPhysicsPart>(true)
            .Where(p => p.GetComponentInParent<BomAssetInstance>(true).IncludeInExport).SelectMany(p => p.WorldOutline()).ToArray();
        var lo = new Vector2(points.Min(p => p.x), points.Min(p => p.y));
        var hi = new Vector2(points.Max(p => p.x), points.Max(p => p.y));
        float extent = (hi - lo).magnitude;
        var half = (level.CameraBounds.Maximum - level.CameraBounds.Minimum) / 2;
        var center = (level.CameraBounds.Maximum + level.CameraBounds.Minimum) / 2;
        float cos = Mathf.Cos(10 * Mathf.Deg2Rad), sin = Mathf.Sin(10 * Mathf.Deg2Rad);
        float heightSize = Mathf.Max(8, (half.y + .5f) * cos + sin);
        float horizontal = Mathf.Max(heightSize * 4, half.x + .5f) + .35f;
        float vertical = (Mathf.Max(heightSize, (half.x + .5f) / .25f) + sin * .8f) / cos + .35f;
        var margin = new Vector2(Mathf.Ceil(horizontal + extent + 1), Mathf.Ceil(vertical + extent + 1));
        level.FragmentCullBounds = new BomBounds2(center - margin, center + margin);
    }

    public static void Classic(BomLevelAuthoring level)
    {
        if (level.YardBuilderVersion < 6)
        {
            foreach (var source in level.GetComponentsInChildren<BomAssetInstance>(true))
            {
                if (source.OriginalObjectPath.StartsWith("Arena/") && source.GetComponentInChildren<BomPhysicsPart>(true) != null)
                { UnityEngine.Object.DestroyImmediate(source.gameObject); continue; }
                if (!source.IncludeInExport) continue;
                // Eight existing posts were behind the band. The XY outline and original assets stay unchanged.
                if (source.FallbackDepth.x > .45f && source.FallbackDepth.y < 2)
                {
                    var p = source.transform.position; p.z -= 1.41f; source.transform.position = p;
                    source.FallbackDepth = new Vector2(-.35f, .35f);
                    source.ApproximationNote += "; G7 post depth 1.06..1.76 -> -0.35..0.35 (XY unchanged)";
                }
            }
            AddWalls(level, -18, 18, -25, 34.64f, 22.6f);
            level.Glue.Clear();
            var parts = level.GetComponentsInChildren<BomPhysicsPart>(true).Where(p => p.GetComponentInParent<BomAssetInstance>(true).IncludeInExport).ToArray();
            foreach (var part in parts)
            {
                var source = part.GetComponentInParent<BomAssetInstance>(true);
                if (part.MaterialKey != "wood") continue;
                // Only the six feet on the grass are anchored. Upper posts and all slabs stand by contact and glue.
                if (Mathf.Abs(part.Minimum.y - 6) < .001f && part.Maximum.x - part.Minimum.x < 1.01f)
                {
                    source.Motion = BomMotionPolicy.Anchored;
                    part.Anchors = new[] { new BomAnchorSegment { A = part.Minimum, B = new Vector2(part.Maximum.x, part.Minimum.y) } };
                }
            }
            for (int i = 0; i < parts.Length; i++)
            for (int j = i + 1; j < parts.Length; j++)
            {
                var a = parts[i].WorldOutline().Select(v => new BomTileMapping.P(v.x, v.y)).ToArray();
                var b = parts[j].WorldOutline().Select(v => new BomTileMapping.P(v.x, v.y)).ToArray();
                if (BomTileMapping.GlueWeight(a, b) >= BomTileMapping.MinGlueWeight)
                    level.Glue.Add(new BomGlueAuthoring { A = parts[i], B = parts[j] });
            }
            level.SimulationBounds = new BomBounds2(new Vector2(-36, -28), new Vector2(36, 40));
            level.YardBuilderVersion = 6;
            BomAuthoringIdentity.Assign(level);
        }
        if (level.YardBuilderVersion == 6)
        {
            // The original 36x30 single earth proxy becomes unstable when coupled to the tall boundary.
            // A partition (the G5 terrain approach) preserves its exact visible union, materials and bottom support.
            PartitionTerrain(level);
            GlueContacts(level);
            level.YardBuilderVersion = 7;
            BomAuthoringIdentity.Assign(level);
        }
        SetCullBounds(level);
        Check(level);
    }

    // Runner entry: exact editor export path, without building a player.
    [Serializable] sealed class Config { public string OdinRoot; }
    public static void ExportAll()
    {
        const string integration = "C:/Users/jblic/Desktop/Bomb-integration/integration";
        var config = JsonUtility.FromJson<Config>(System.IO.File.ReadAllText(integration + "/local.config.owner-validation.json"));
        Environment.SetEnvironmentVariable("BOM_NATIVE_SERVER_EXE", config.OdinRoot + "/build/BOM-server.exe");
        Environment.SetEnvironmentVariable("BOM_YARD_LAYOUT_OUT", integration + "/fixtures/network-yard/yard.json");
        Environment.SetEnvironmentVariable("BOM_TILE_LEVEL_DIR", integration + "/fixtures/levels");
        BomYardBuilder.CreateAndExport();
        UnityEditor.SceneManagement.EditorSceneManager.OpenScene(BomNetworkMenuBuilder.ScenePath);
        BomNetworkMenuBuilder.ConfigureScene();
        BomTileLevelBuilder.ExportAll(Environment.GetEnvironmentVariable("BOM_TILE_LEVEL_DIR"));
    }
}
