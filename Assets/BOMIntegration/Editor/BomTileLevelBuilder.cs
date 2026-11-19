using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using Bom.Native;
using Bom.Unity;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;
using M = BomTileMapping;

// G5 (tile exporter v2): exports Darryn's tile-built levels (YardLevel, BridgeLevel, TowerLevel) as native v4 layouts and
// derived network scenes with the design doc section 3 mapping (BomTileMapping): every visible tile inside the arena is a
// simulated part with an OD-2 material, front/rear duplicates merge, overlaps become glued seams, anchors sit only at real
// support (terrain bedrock, post feet on terrain, the Bridge's five OD-3 piles), and invariants I1-I4 fail the export.
// Darryn's scenes are only opened and saved *as a copy* under Assets/BOMIntegration; the originals are never written.
// G8: boundaries are mapping metadata; native walls are visible bedrock (Yard/Tower), or absent (Bridge).
// Per level it writes <layout>.json, <layout>.tiles.json (summary + one row per tile + parts) and <layout>.tiles-input.json
// (the exact mapping input, replayable with integration/tools/g5/TileMappingTests).
public static class BomTileLevelBuilder
{
    public sealed class Spec
    {
        public string Name,
            Source,
            Scene,
            LevelId;
        public (string Prefix, string Material)[] Materials;
        public int Piles;
    }

    // OD-2 (2026-11-17): Bridge decks wood; truss, posts, girders, braces steel; Yard ground earth, rocks stone; Tower stone.
    // Yard "Cube" (its 8 pillars and 2 top slabs) is not in the OD-2 table; it takes stone like the Tower's blocks and pillars (G6 tunes).
    public static readonly Spec[] Levels =
    {
        new Spec
        {
            Name = "YardLevel",
            Source = "Assets/Game/Scenes/YardLevel.unity",
            Scene = "Assets/BOMIntegration/NetworkYardTiles.unity",
            LevelId = "bomb-yard-tiles-v2",
            Materials = new[] { ("Yard Ground Tile", "earth"), ("Rock", "stone"), ("Cube", "stone") },
        },
        new Spec
        {
            Name = "BridgeLevel",
            Source = "Assets/Game/Scenes/BridgeLevel.unity",
            Scene = "Assets/BOMIntegration/NetworkBridge.unity",
            LevelId = "bomb-bridge-v2",
            Materials = new[] { ("Bridge Deck Tile", "wood"), ("Bridge Girder", "steel"), ("Bridge Truss Post", "steel"), ("Bridge Truss Brace", "steel") },
            Piles = 5, // OD-3 (a)
        },
        new Spec
        {
            Name = "TowerLevel",
            Source = "Assets/Game/Scenes/TowerLevel.unity",
            Scene = "Assets/BOMIntegration/NetworkTower.unity",
            LevelId = "bomb-tower-v2",
            Materials = new[] { ("Cube", "stone") },
        },
    };

    // Custom palette entries (native allows 4 per level). Steel per OD-2; earth as C6.
    static BomCustomMaterial Custom(string name) =>
        name == "steel" ? new BomCustomMaterial { Name = "steel", Base = "stone", Toughness = 1.25f, BlastResistance = 4, StripThickness = .2f, ShockLoss = 4, Flexibility = .5f, Color = new Color32(52, 66, 86, 255) }
        : name == "earth" ? new BomCustomMaterial { Name = "earth", Base = "stone", Color = new Color32(132, 95, 64, 255) }
        : null;

    static readonly string[] BuiltInMaterials = { "stone", "wood", "glass", "rubber" };

    static readonly string[] PresentationRoots = { "BOM native yard session", "Network menu and arena HUD", "BOM native yard camera" };

    static string Env(string name)
    {
        string value = Environment.GetEnvironmentVariable(name);
        if (string.IsNullOrEmpty(value))
            throw new InvalidOperationException("Set " + name);
        return value;
    }

    // Batch entry: BOM_TILE_LEVEL_DIR=<folder> (integration/fixtures/levels), BOM_NATIVE_SERVER_EXE for validation.
    public static void ExportAll() => ExportAll(Env("BOM_TILE_LEVEL_DIR"));

    public static void ExportAll(string folder)
    {
        foreach (var spec in Levels)
            Export(spec, Path.Combine(folder, spec.Name + ".json"));
    }

    static string ObjectPath(Transform t) => t.parent == null ? t.name : ObjectPath(t.parent) + "/" + t.name;

    static Component FindByType(Scene scene, string type)
    {
        foreach (var root in scene.GetRootGameObjects())
        foreach (var component in root.GetComponentsInChildren<Component>(true))
            if (component != null && component.GetType().Name == type)
                return component;
        return null;
    }

    static object Get(Component component, string property) => component.GetType().GetProperty(property).GetValue(component);

    static M.P[] Hull(List<M.P> points)
    {
        points.Sort((a, b) => a.X != b.X ? a.X.CompareTo(b.X) : a.Y.CompareTo(b.Y));
        var hull = new List<M.P>();
        double Cross(M.P o, M.P a, M.P b) => (a.X - o.X) * (b.Y - o.Y) - (a.Y - o.Y) * (b.X - o.X);
        for (int pass = 0; pass < 2; pass++)
        {
            int start = hull.Count;
            for (int i = 0; i < points.Count; i++)
            {
                var p = points[pass == 0 ? i : points.Count - 1 - i];
                while (hull.Count >= start + 2 && Cross(hull[hull.Count - 2], hull[hull.Count - 1], p) <= 1e-7)
                    hull.RemoveAt(hull.Count - 1);
                hull.Add(p);
            }
            hull.RemoveAt(hull.Count - 1);
        }
        return hull.ToArray();
    }

    // The tile's XY silhouette: convex hull of every mesh vertex in world space (rounded to 1e-5), and its Z interval.
    static M.Tile Measure(Component destructible)
    {
        var t = destructible.transform;
        var tile = new M.Tile { Path = ObjectPath(t), Name = t.name };
        var behaviour = new SerializedObject(destructible).FindProperty("behavior").intValue;
        tile.Behaviour = behaviour == 1 ? "CarveAndFragment" : "Carve";
        var points = new List<M.P>();
        double zmin = double.MaxValue,
            zmax = double.MinValue;
        foreach (var filter in t.GetComponentsInChildren<MeshFilter>(true))
        {
            if (filter.sharedMesh == null)
                continue;
            var renderer = filter.GetComponent<MeshRenderer>();
            if (renderer != null && renderer.sharedMaterial != null && tile.DarrynMaterial.Length == 0)
                tile.DarrynMaterial = AssetDatabase.GetAssetPath(renderer.sharedMaterial) + ":" + renderer.sharedMaterial.name;
            var matrix = filter.transform.localToWorldMatrix;
            foreach (var v in filter.sharedMesh.vertices)
            {
                var p = matrix.MultiplyPoint3x4(v);
                points.Add(new M.P(Math.Round(p.x, 5), Math.Round(p.y, 5)));
                zmin = Math.Min(zmin, p.z);
                zmax = Math.Max(zmax, p.z);
            }
        }
        tile.Hull = points.Count >= 3 ? Hull(points) : Array.Empty<M.P>();
        tile.ZMin = Math.Round(zmin, 5);
        tile.ZMax = Math.Round(zmax, 5);
        return tile;
    }

    static string MeshKey(Transform group)
    {
        var text = new StringBuilder();
        foreach (var filter in group.GetComponentsInChildren<MeshFilter>(true))
        {
            text.Append(AssetDatabase.GetAssetPath(filter.sharedMesh)).Append('#').Append(filter.sharedMesh == null ? "missing" : filter.sharedMesh.name);
            var local = group.worldToLocalMatrix * filter.transform.localToWorldMatrix;
            for (int i = 0; i < 16; i++)
                text.Append(',').Append(Math.Round(local[i], 5).ToString(CultureInfo.InvariantCulture));
            var renderer = filter.GetComponent<MeshRenderer>();
            if (renderer != null)
                foreach (var material in renderer.sharedMaterials)
                    text.Append('|').Append(AssetDatabase.GetAssetPath(material)).Append(':').Append(material == null ? "" : material.name);
        }
        return "tiles/" + Hash128.Compute(text.ToString());
    }

    static Vector2 V(M.P p) => new Vector2((float)p.X, (float)p.Y);

    static BomPhysicsPart Part(Transform owner, string name, Vector2[] outline, string material, BomAnchorSegment[] anchors, string note)
    {
        var child = new GameObject(name);
        child.transform.SetParent(owner, false);
        var part = child.AddComponent<BomPhysicsPart>();
        part.WorldRestCoordinates = true;
        part.Shape = BomProxyShape.Polygon;
        part.Outline = outline;
        part.Anchors = anchors;
        part.MaterialKey = material;
        part.ApproximationNote = note;
        return part;
    }

    static Vector2[] RectOutline(Vector2 lo, Vector2 hi) => new[] { lo, new Vector2(hi.x, lo.y), hi, new Vector2(lo.x, hi.y) };

    static GameObject Root(Scene scene, string name)
    {
        foreach (var root in scene.GetRootGameObjects())
            if (root.name == name)
                return root;
        return null;
    }

    // A renderer-only copy of one of Darryn's meshes under a part's visual group (world pose kept). The copy dresses the
    // part's cells in the visual registry; the original tile is hidden, so nothing is drawn twice.
    static void CopyMesh(MeshFilter filter, Transform group, Vector3 position, Vector3 scale)
    {
        var copy = new GameObject(filter.name + " (G5 visual)");
        copy.transform.SetParent(group, false);
        copy.transform.SetPositionAndRotation(position, filter.transform.rotation);
        copy.transform.localScale = scale;
        copy.AddComponent<MeshFilter>().sharedMesh = filter.sharedMesh;
        copy.AddComponent<MeshRenderer>().sharedMaterials = filter.GetComponent<MeshRenderer>().sharedMaterials;
    }

    [Serializable]
    sealed class PartRow
    {
        public int part;
        public long source_identity;
        public string role,
            material,
            motion,
            note;
        public string[] tiles,
            visual,
            anchors;
        public int piles;
        public Vector2[] outline;
    }

    [Serializable]
    sealed class BoundaryRow
    {
        public string name,
            motion,
            damage,
            note;
        public bool visible;
        public Vector2 lo,
            hi;
    }

    [Serializable]
    sealed class TileRowOut
    {
        public string path,
            name,
            behaviour,
            darryn_material,
            role,
            classification,
            material,
            note;
        public float zmin,
            zmax;
        public bool brought_onto_plane;
        public int[] parts;
    }

    [Serializable]
    sealed class TileReport
    {
        public string level,
            source_scene,
            derived_scene,
            level_id,
            exporter = "G5 tile exporter v2 (BomTileMapping)";
        public float player_plane_z;
        public int tiles,
            in_arena,
            outside_arena,
            backdrop_tiles,
            merged_duplicates,
            post_column_joins,
            brought_onto_plane,
            covered_tiles,
            parts,
            glue_links,
            anchored_parts,
            anchor_segments,
            piles,
            dropped_slivers,
            native_glue_links = -1,
            native_glue_zero_sample_links = -1,
            native_parts = -1,
            native_cells = -1,
            allowed_overlaps;
        public float dropped_area,
            max_dropped_area;
        public string[] parts_by_role,
            parts_by_material,
            custom_materials,
            fixed_sources,
            nudges;
        public BoundaryRow[] boundaries;
        public Vector2[] spawns;
        public TileRowOut[] rows;
        public PartRow[] part_rows;
    }

    [Serializable]
    sealed class NativeGlueReport
    {
        public string status;
        public int part_count,
            cell_count,
            glue_link_count,
            glue_zero_sample_links;
    }

    static string Json(M.P p) => "[" + p.X.ToString("R", CultureInfo.InvariantCulture) + "," + p.Y.ToString("R", CultureInfo.InvariantCulture) + "]";

    static string Q(string s) => "\"" + (s ?? "").Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";

    // The mapping input as JSON (TileMappingTests "map" replays it without Unity).
    static string InputJson(M.Input input)
    {
        var s = new StringBuilder("{\"rules\":{\"level\":").Append(Q(input.Rules.Level)).Append(",\"plane_z\":").Append(input.Rules.PlaneZ.ToString("R", CultureInfo.InvariantCulture));
        s.Append(",\"materials\":[").Append(string.Join(",", input.Rules.Materials.Select(m => "[" + Q(m.Prefix) + "," + Q(m.Material) + "]"))).Append(']');
        s.Append(",\"piles\":").Append(input.Rules.Piles).Append(",\"pile_material\":").Append(Q(input.Rules.PileMaterial)).Append("},\"boundaries\":[");
        s.Append(string.Join(",", input.Boundaries.Select(b => "{\"name\":" + Q(b.Name) + ",\"lo\":" + Json(b.Lo) + ",\"hi\":" + Json(b.Hi) + ",\"indestructible\":" + (b.Indestructible ? "true" : "false") + ",\"visible\":" + (b.Visible ? "true" : "false") + "}")));
        s.Append("],\"tiles\":[\n");
        s.Append(string.Join(",\n", input.Tiles.Select(t => "{\"path\":" + Q(t.Path) + ",\"name\":" + Q(t.Name) + ",\"behaviour\":" + Q(t.Behaviour) + ",\"darryn_material\":" + Q(t.DarrynMaterial)
            + ",\"hull\":[" + string.Join(",", t.Hull.Select(Json)) + "],\"zmin\":" + t.ZMin.ToString("R", CultureInfo.InvariantCulture) + ",\"zmax\":" + t.ZMax.ToString("R", CultureInfo.InvariantCulture) + "}")));
        return s.Append("\n]}\n").ToString();
    }

    public static BomVisualRegistry Export(Spec spec, string output)
    {
        output = Path.GetFullPath(output);
        // Darryn's scene: open, save a copy under BOMIntegration, reopen the copy. The original file is never written.
        var original = EditorSceneManager.OpenScene(spec.Source, OpenSceneMode.Single);
        if (!EditorSceneManager.SaveScene(original, spec.Scene, true))
            throw new InvalidOperationException("Could not save the derived copy " + spec.Scene);
        var scene = EditorSceneManager.OpenScene(spec.Scene, OpenSceneMode.Single);
        foreach (var root in scene.GetRootGameObjects())
            if (PrefabUtility.IsPartOfPrefabInstance(root))
                PrefabUtility.UnpackPrefabInstance(PrefabUtility.GetOutermostPrefabInstanceRoot(root), PrefabUnpackMode.Completely, InteractionMode.AutomatedAction);
        foreach (var root in scene.GetRootGameObjects())
        foreach (var t in root.GetComponentsInChildren<Transform>(true))
            if (PrefabUtility.IsOutermostPrefabInstanceRoot(t.gameObject))
                PrefabUtility.UnpackPrefabInstance(t.gameObject, PrefabUnpackMode.Completely, InteractionMode.AutomatedAction);

        var layout = FindByType(scene, "ArenaLayout");
        if (layout == null)
            throw new InvalidOperationException(spec.Name + ": no ArenaLayout");
        var boundsT = layout.transform.Find("Level Bounds");
        var levelBounds = boundsT != null ? boundsT.GetComponent<Collider>() : null;
        if (levelBounds == null)
            throw new InvalidOperationException(spec.Name + ": ArenaLayout has no Level Bounds collider");
        layout.GetType().GetMethod("ApplyGeometry").Invoke(layout, null);
        Bounds b = levelBounds.bounds;
        var origin = (Vector3)Get(layout, "Origin");
        float planeZ = origin.z;
        var desired = (Vector3)Get(layout, "PlayerSpawn");
        float spacing = 2;
        var session = FindByType(scene, "ArenaSession");
        if (session != null)
        {
            var so = new SerializedObject(session);
            spacing = so.FindProperty("playerSpawnSpacing").floatValue;
            var first = so.FindProperty("player1").objectReferenceValue as Component;
            if (so.FindProperty("useScenePlayerSpawnHeight").boolValue && first != null)
                desired.y = first.transform.position.y;
            else if (spec.Name == "YardLevel")
                desired.y += .75f; // ArenaSession.ResetPlayer's YardLevel lift
        }

        // Mapping input: boundaries (kept as they are until G8, but destructible: I2), Darryn's tiles, the level's rules.
        var input = new M.Input
        {
            Rules = new M.Rules { Level = spec.Name, PlaneZ = planeZ, Materials = spec.Materials, Piles = spec.Piles, PileMaterial = spec.Piles > 0 ? "steel" : "" },
        };
        var boundaryTransforms = new Dictionary<string, Transform>();
        foreach (string name in M.BoundaryNames)
        {
            var t = layout.transform.Find(name);
            var collider = t != null ? t.GetComponent<Collider>() : null;
            if (collider == null)
                throw new InvalidOperationException(spec.Name + ": missing boundary " + name);
            bool visible = false;
            foreach (var renderer in t.GetComponentsInChildren<MeshRenderer>(true))
                if (renderer.enabled && renderer.GetComponent<MeshFilter>() != null && renderer.GetComponent<MeshFilter>().sharedMesh != null)
                    visible = true;
            var cb = collider.bounds;
            input.Boundaries.Add(new M.Boundary { Name = name, Lo = new M.P(cb.min.x, cb.min.y), Hi = new M.P(cb.max.x, cb.max.y), Visible = visible });
            boundaryTransforms[name] = t;
        }
        var tileObjects = new Dictionary<string, Transform>();
        foreach (var root in scene.GetRootGameObjects())
        foreach (var component in root.GetComponentsInChildren<Component>(true))
            if (component != null && component.GetType().Name == "DestructibleObject")
            {
                var tile = Measure(component);
                // Darryn's Tower has same-named siblings (two "Tower/Cube (55)"): later ones get "#2", "#3" in scene order.
                for (int n = 2; tileObjects.ContainsKey(tile.Path); n++)
                    tile.Path = ObjectPath(component.transform) + " #" + n;
                tileObjects[tile.Path] = component.transform;
                input.Tiles.Add(tile);
            }
        Directory.CreateDirectory(Path.GetDirectoryName(output));
        File.WriteAllText(output + ".tiles-input.json", InputJson(input));

        // The section 3 mapping; any invariant I1-I4 failure throws here and the level does not export.
        var mapped = M.Map(input);

        // Authoring root and materials.
        var levelRoot = new GameObject("BOM " + spec.Name + " Authoring");
        SceneManager.MoveGameObjectToScene(levelRoot, scene);
        var level = levelRoot.AddComponent<BomLevelAuthoring>();
        level.LevelId = spec.LevelId;
        // G5 assigns member identities first, then the old bottom/left/right boundary. Keep member seeds stable.
        level.NextIdentityDecimal = "1";
        var yardScene = EditorSceneManager.OpenScene(BomNetworkMenuBuilder.ScenePath, OpenSceneMode.Additive);
        foreach (var candidate in UnityEngine.Object.FindObjectsByType<BomLevelAuthoring>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            if (candidate.gameObject.scene == yardScene)
            {
                // Same tuning as the classic yard (one gameplay config for every level).
                level.Gameplay = JsonUtility.FromJson<BomGameplayTuning>(JsonUtility.ToJson(candidate.Gameplay));
                level.GameplayConfigId = candidate.GameplayConfigId;
                level.Seed = candidate.Seed;
            }
        foreach (string name in mapped.Parts.Select(p => p.Material).Distinct().OrderBy(n => n, StringComparer.Ordinal))
        {
            if (Array.IndexOf(BuiltInMaterials, name) >= 0)
                continue;
            var custom = Custom(name);
            if (custom == null)
                throw new M.InvariantException("I4", spec.Name, "material '" + name + "' is neither built in nor a known custom");
            level.Materials.Add(custom);
        }
        if (level.Materials.Count > 4)
            throw new InvalidOperationException(spec.Name + ": more than 4 custom materials");

        var shape = new BomActorShapeInfo { struct_size = (uint)System.Runtime.InteropServices.Marshal.SizeOf<BomActorShapeInfo>(), version = 1 };
        BomSession.Check(BomNative.bom_actor_shape_info(ref shape));

        // OD-1: no native boundary pieces on Bridge; visible bottom-anchored bedrock on Yard/Tower.
        // Input boundaries remain the original clipping metadata, so the arena and outside-tile classification do not change.
        var boundaryRows = new List<BoundaryRow>();
        var allSolid = new List<(Vector2 lo, Vector2 hi)>();
        int boundaryCount = spec.Piles > 0 ? 0 : 2;
        if (boundaryCount > 0)
        {
            float left = (float)input.Boundaries.First(x => x.Name == "Left Wall").Hi.X;
            float right = (float)input.Boundaries.First(x => x.Name == "Right Wall").Lo.X;
            BomArenaBoundaryBuilder.AddWalls(level, left, right, -28, 35.80739f, 26);
            foreach (var wall in level.GetComponentsInChildren<BomAssetInstance>(true))
                wall.SetEditorIdentity((ulong)mapped.Parts.Count + (wall.OriginalObjectPath == "Left bedrock" ? 2UL : 3UL));
            boundaryRows.Add(new BoundaryRow { name = "Left bedrock", motion = "anchored", damage = "destructible", visible = true, lo = new Vector2(-26, -28), hi = new Vector2(left, 35.80739f), note = "OD-1: bottom edge only; original inner face" });
            boundaryRows.Add(new BoundaryRow { name = "Right bedrock", motion = "anchored", damage = "destructible", visible = true, lo = new Vector2(right, -28), hi = new Vector2(26, 35.80739f), note = "OD-1: bottom edge only; original inner face" });
        }

        // Parts: one source per part, its visual group holding copies of the Darryn meshes it stands for.
        var partsRoot = new GameObject("BOM G5 parts").transform;
        partsRoot.SetParent(levelRoot.transform, false);
        var physics = new List<BomPhysicsPart>();
        var sources = new List<BomAssetInstance>();
        foreach (var part in mapped.Parts)
        {
            var group = new GameObject("G5 part " + part.Index + " " + part.Role + " " + (part.Tiles.FirstOrDefault() ?? "pile").Replace('/', '_'));
            group.transform.SetParent(partsRoot, false);
            foreach (string path in part.Visual)
                foreach (var filter in tileObjects[path].GetComponentsInChildren<MeshFilter>(true))
                    if (filter.sharedMesh != null && filter.GetComponent<MeshRenderer>() != null)
                        CopyMesh(filter, group.transform, filter.transform.position, filter.transform.lossyScale);
            foreach (var pile in part.Piles)
            {
                // The pile is drawn with the post's own mesh, stretched from the post foot down to the riverbed.
                var template = tileObjects[pile.TemplatePath].GetComponentsInChildren<MeshFilter>(true).First(f => f.sharedMesh != null && f.GetComponent<MeshRenderer>() != null);
                var bounds = template.GetComponent<MeshRenderer>().bounds;
                float height = (float)(pile.Hi.Y - pile.Lo.Y),
                    factor = height / Mathf.Max(bounds.size.y, 1e-4f);
                var scale = template.transform.lossyScale;
                var up = template.transform.rotation * Vector3.up;
                var axis = Mathf.Abs(up.y) > .9f ? 1 : Mathf.Abs((template.transform.rotation * Vector3.right).y) > .9f ? 0 : 2;
                scale[axis] *= factor;
                var center = new Vector3((float)(pile.Lo.X + pile.Hi.X) / 2, (float)(pile.Lo.Y + pile.Hi.Y) / 2, bounds.center.z);
                var offset = template.transform.position - bounds.center;
                offset.y *= factor;
                CopyMesh(template, group.transform, center + offset, scale);
            }
            var source = group.AddComponent<BomAssetInstance>();
            source.SetEditorIdentity((ulong)part.Index + 1);
            source.AssetKey = MeshKey(group.transform);
            source.OriginalObjectPath = part.Tiles.FirstOrDefault() ?? "pile";
            source.Motion = part.Anchors.Count > 0 ? BomMotionPolicy.Anchored : BomMotionPolicy.Dynamic;
            source.Damage = BomDamagePolicy.Destructible;
            source.FallbackDepth = new Vector2((float)part.ZMin, (float)part.ZMax);
            source.ApproximationNote = "G5 " + part.Role + " (" + part.Material + "): " + part.Note;
            var anchors = part.Anchors.Select(a => new BomAnchorSegment { A = V(a.A), B = V(a.B) }).ToArray();
            physics.Add(Part(group.transform, "Native part", part.Outline.Select(V).ToArray(), part.Material, anchors, ""));
            sources.Add(source);
            var (lo, hi) = M.Box(part.Outline);
            allSolid.Add((V(lo), V(hi)));
        }
        foreach (var link in mapped.Glue)
            level.Glue.Add(new BomGlueAuthoring { A = physics[link.A], B = physics[link.B] });
        // Every real wall/terrain contact also carries sampled glue (same G5 fillet and rule).
        var walls = levelRoot.GetComponentsInChildren<BomPhysicsPart>(true).Where(p => p.MaterialKey == "bedrock").ToArray();
        foreach (var wall in walls)
        foreach (var part in physics)
            if (M.GlueWeight(BomArenaBoundaryBuilder.Points(wall), BomArenaBoundaryBuilder.Points(part)) >= M.MinGlueWeight)
                level.Glue.Add(new BomGlueAuthoring { A = wall, B = part });
        foreach (var t in boundaryTransforms.Values) UnityEngine.Object.DestroyImmediate(t.gameObject);
        // Darryn's tiles that became parts (or lie wholly inside parts) are drawn by the parts now.
        foreach (var row in mapped.Rows)
            if (row.classification != "outside arena")
                foreach (var renderer in tileObjects[row.path].GetComponentsInChildren<Renderer>(true))
                    renderer.enabled = false;

        // Spawns: Darryn's spacing around the layout spawn, dropped onto the first surface below.
        float half = shape.player_segment + shape.player_radius;
        var spawns = new Vector2[4];
        for (int i = 0; i < 4; i++)
        {
            float x = desired.x + (i - 1.5f) * spacing;
            float top = float.MinValue;
            foreach (var solid in allSolid)
                if (Mathf.Min(x + shape.player_radius, solid.hi.x) - Mathf.Max(x - shape.player_radius, solid.lo.x) > 0 && solid.hi.y <= desired.y + .5f)
                    top = Mathf.Max(top, solid.hi.y);
            spawns[i] = new Vector2(x, top > float.MinValue ? top + half + .05f : desired.y);
        }
        float innerLeft = (float)input.Boundaries.First(x => x.Name == "Left Wall").Hi.X,
            innerRight = (float)input.Boundaries.First(x => x.Name == "Right Wall").Lo.X,
            bottomLo = (float)input.Boundaries.First(x => x.Name == "Bottom Boundary").Lo.Y;
        level.Spawns = spawns;
        level.CameraBounds = new BomBounds2(new Vector2(b.min.x, b.min.y), new Vector2(b.max.x, b.max.y));
        float bombHeight = b.max.y + 2; // BombDropper: CameraBounds.max.y + dropHeightAboveArena (2)
        level.SimulationBounds = new BomBounds2(new Vector2(b.min.x - 4, bottomLo - 2), new Vector2(b.max.x + 4, bombHeight + 2));
        level.KillBounds = new BomBounds2(new Vector2(innerLeft, b.min.y), new Vector2(innerRight, b.max.y)); // classic yard: walls + Level Bounds
        level.AimBounds = new BomBounds2(level.SimulationBounds.Minimum + Vector2.one, level.SimulationBounds.Maximum - Vector2.one);
        level.FragmentCullBounds = new BomBounds2(level.SimulationBounds.Minimum - new Vector2(8, 4), level.SimulationBounds.Maximum + new Vector2(8, 7));
        level.BombCleanupBounds = new BomBounds2(level.SimulationBounds.Minimum - new Vector2(2, 1), level.SimulationBounds.Maximum + new Vector2(2, 5));
        level.SimulationBounds = new BomBounds2(new Vector2(-30, -32), new Vector2(30, 40));
        BomArenaBoundaryBuilder.SetCullBounds(level);
        level.BombSpawnX = new Vector2(innerLeft + .75f, innerRight - .75f);
        level.BombSpawnHeight = bombHeight;

        // Presentation only: no players, bombs or Darryn's HUD; no Unity physics; no legacy scripts.
        foreach (var root in scene.GetRootGameObjects())
        {
            if (root == levelRoot)
                continue;
            if (root.name.StartsWith("Player", StringComparison.Ordinal) || root.name == "Bomb System" || root.name == "Arena UI")
            {
                UnityEngine.Object.DestroyImmediate(root);
                continue;
            }
            root.transform.SetParent(levelRoot.transform, true);
        }
        foreach (var t in levelRoot.GetComponentsInChildren<Transform>(true))
        {
            GameObjectUtility.RemoveMonoBehavioursWithMissingScript(t.gameObject);
            if (t.GetComponent("ArenaPlayerController") != null || t.name.StartsWith("Player", StringComparison.Ordinal) && t.GetComponent<CharacterController>() != null)
                t.gameObject.SetActive(false);
        }
        foreach (var behaviour in levelRoot.GetComponentsInChildren<MonoBehaviour>(true))
            if (behaviour != null && behaviour.GetType().Assembly.GetName().Name == "Assembly-CSharp")
                UnityEngine.Object.DestroyImmediate(behaviour);
        foreach (var joint in levelRoot.GetComponentsInChildren<Joint>(true))
            UnityEngine.Object.DestroyImmediate(joint);
        foreach (var collider in levelRoot.GetComponentsInChildren<Collider>(true))
            UnityEngine.Object.DestroyImmediate(collider);
        foreach (var controller in levelRoot.GetComponentsInChildren<CharacterController>(true))
            UnityEngine.Object.DestroyImmediate(controller);
        foreach (var body in levelRoot.GetComponentsInChildren<Rigidbody>(true))
            UnityEngine.Object.DestroyImmediate(body);
        foreach (var animator in levelRoot.GetComponentsInChildren<Animator>(true))
            animator.applyRootMotion = false;
        foreach (var source in levelRoot.GetComponentsInChildren<BomAssetInstance>(true))
        foreach (var renderer in source.Group.GetComponentsInChildren<Renderer>(true))
            renderer.enabled = false;
        foreach (var camera in levelRoot.GetComponentsInChildren<Camera>(true))
            camera.enabled = false;
        foreach (var listener in levelRoot.GetComponentsInChildren<AudioListener>(true))
            listener.enabled = false;

        // The network session, HUD and camera come from NetworkMenu (configured by BomNetworkMenuBuilder).
        BomClientBehaviour client = null;
        BomNetworkHud hud = null;
        Camera view = null;
        foreach (string name in PresentationRoots)
        {
            var source = Root(yardScene, name);
            if (source == null)
                throw new InvalidOperationException("NetworkMenu has no " + name);
            var copy = (GameObject)UnityEngine.Object.Instantiate(source);
            copy.name = source.name;
            SceneManager.MoveGameObjectToScene(copy, scene);
            // Explicit checks: Unity's missing-component placeholders are not C# null, so ?? would keep them.
            if (client == null)
                client = copy.GetComponent<BomClientBehaviour>();
            if (hud == null)
                hud = copy.GetComponent<BomNetworkHud>();
            if (view == null)
                view = copy.GetComponent<Camera>();
        }
        EditorSceneManager.CloseScene(yardScene, true);
        if (client == null || hud == null || view == null)
            throw new InvalidOperationException("NetworkMenu presentation roots changed");
        client.View = view;
        hud.Client = client;
        var scenario = client.GetComponent<BomRoundScenario>();
        if (scenario != null)
            scenario.Client = client;
        EditorSceneManager.SaveScene(scene, spec.Scene);
        BomAuthoringIdentity.Assign(level);
        EditorSceneManager.SaveScene(scene, spec.Scene);

        BomArenaBoundaryBuilder.Check(level);
        var registry = BomLevelExporter.Export(level, output);

        // I4 on the real validator: every glue link carries native samples (G-N2), and native saw the same parts and links.
        var native = JsonUtility.FromJson<NativeGlueReport>(File.ReadAllText(output + ".native-report.json"));
        if (native.status != "passed" || native.glue_zero_sample_links != 0 || native.glue_link_count != level.Glue.Count || native.part_count != mapped.Parts.Count + boundaryCount * 2)
            throw new M.InvariantException("I4", spec.Name, "native --validate-layout: status=" + native.status + " glue_links=" + native.glue_link_count + " (authored " + level.Glue.Count + ") zero_sample=" + native.glue_zero_sample_links + " parts=" + native.part_count + " (mapped + bedrock " + (mapped.Parts.Count + boundaryCount * 2) + ")");

        var report = new TileReport
        {
            level = spec.Name,
            source_scene = spec.Source,
            derived_scene = spec.Scene,
            level_id = spec.LevelId,
            player_plane_z = planeZ,
            tiles = mapped.Tiles,
            in_arena = mapped.InArena,
            outside_arena = mapped.OutsideArena,
            backdrop_tiles = mapped.Backdrop,
            merged_duplicates = mapped.MergedDuplicates,
            post_column_joins = mapped.ColumnJoins,
            brought_onto_plane = mapped.BroughtOntoPlane,
            covered_tiles = mapped.Rows.Count(r => r.classification == "covered"),
            parts = mapped.Parts.Count,
            glue_links = level.Glue.Count,
            anchored_parts = mapped.Parts.Count(p => p.Anchors.Count > 0),
            anchor_segments = mapped.Parts.Sum(p => p.Anchors.Count),
            piles = mapped.Parts.Sum(p => p.Piles.Count),
            dropped_slivers = mapped.DroppedSlivers,
            dropped_area = (float)mapped.DroppedArea,
            max_dropped_area = (float)mapped.MaxDroppedArea,
            native_glue_links = native.glue_link_count,
            native_glue_zero_sample_links = native.glue_zero_sample_links,
            native_parts = native.part_count,
            native_cells = native.cell_count,
            allowed_overlaps = level.AllowedOverlaps.Count,
            parts_by_role = mapped.Parts.GroupBy(p => p.Role.ToString()).Select(g => g.Key + "=" + g.Count()).ToArray(),
            parts_by_material = mapped.Parts.GroupBy(p => p.Material).Select(g => g.Key + "=" + g.Count()).ToArray(),
            custom_materials = level.Materials.Select(m => m.Name + " (base " + m.Base + ", toughness " + m.Toughness.ToString(CultureInfo.InvariantCulture) + ", blast resistance " + m.BlastResistance.ToString(CultureInfo.InvariantCulture) + ")").ToArray(),
            nudges = mapped.Nudges.ToArray(),
            fixed_sources = Array.Empty<string>(),
            boundaries = boundaryRows.ToArray(),
            spawns = spawns,
            rows = mapped.Rows.Select(r => new TileRowOut { path = r.path, name = r.name, behaviour = r.behaviour, darryn_material = r.darryn_material, role = r.role, classification = r.classification, material = r.material, note = r.note, zmin = (float)r.zmin, zmax = (float)r.zmax, brought_onto_plane = r.brought_onto_plane, parts = r.parts }).ToArray(),
            part_rows = mapped.Parts.Select(p => new PartRow
            {
                part = p.Index,
                source_identity = (long)sources[p.Index].Identity,
                role = p.Role.ToString(),
                material = p.Material,
                motion = p.Anchors.Count > 0 ? "anchored" : "dynamic",
                note = p.Note,
                tiles = p.Tiles.ToArray(),
                visual = p.Visual.ToArray(),
                anchors = p.Anchors.Select(a => a.Support + " " + a.A + "-" + a.B).ToArray(),
                piles = p.Piles.Count,
                outline = p.Outline.Select(V).ToArray(),
            }).ToArray(),
        };
        File.WriteAllText(output + ".tiles.json", JsonUtility.ToJson(report, true));

        client.VisualRegistry = registry;
        EditorUtility.SetDirty(client);
        EditorSceneManager.SaveScene(scene, spec.Scene);
        AssetDatabase.SaveAssets();
        Debug.Log(
            "BOM TILE LEVEL EXPORTED v2 " + spec.Name + " tiles=" + report.tiles + " in_arena=" + report.in_arena + " outside=" + report.outside_arena + " backdrop=" + report.backdrop_tiles
                + " merged=" + report.merged_duplicates + " parts=" + report.parts + " glue=" + report.glue_links + " native_glue=" + report.native_glue_links + " zero_sample=" + report.native_glue_zero_sample_links
                + " anchored=" + report.anchored_parts + " piles=" + report.piles + " cells=" + report.native_cells + " layout=" + output
        );
        return registry;
    }
}
