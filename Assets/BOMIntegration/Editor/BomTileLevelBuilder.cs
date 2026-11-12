using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using Bom.Native;
using Bom.Unity;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

// C6: exports Darryn's tile-built levels (YardLevel, BridgeLevel, TowerLevel) as native v4 layouts and derived network
// scenes. His scenes are only opened and immediately saved *as a copy* under Assets/BOMIntegration; the originals are
// never written. Rules (each recorded per tile in <layout>.tiles.json):
//   - Every DestructibleObject is a candidate tile. A tile whose depth (Z) interval misses the player's plane
//     (ArenaLayout origin z +/- the player's 0.45 CharacterController radius) is off-plane: Darryn's players can never touch
//     it (the bridge truss, the yard/tower pillars), so it stays as visible, non-destructible decoration. Native physics is XY.
//   - Carve -> Anchored, anchor segments on every outline edge (pieces still touching the tile's original outline stay;
//     only islands cut free fall). CarveAndFragment -> Dynamic when something in the plane (a tile or the floor) holds it;
//     when it only rests on off-plane pillars it is Anchored at those pillar contacts, so it falls when a blast removes the
//     contact cells (Darryn's fallWhenUnsupported); with no support at all it is anchored on its bottom edge.
//   - Left Wall / Right Wall / Bottom Boundary are Fixed + Indestructible stone; walls without a renderer are hidden.
//   - Tiles are clipped to the walls' inner faces and the floor's top (never overlap a Fixed part, C2b), and tiles wholly
//     outside the arena stay decoration. Darryn's tiles overlap their neighbours by small seams, which native rejects, so
//     each overlapping tile is trimmed along its shallowest side against tiles already kept (kept first: higher top, then
//     lower x). A trim deeper than MaxTrim or a quarter of the tile fails the export instead of guessing.
//   - Spawns: ArenaSession/ArenaLayout spawn height and spacing (4 players), dropped onto the first surface below.
//     Camera bounds: the Level Bounds collider (Darryn's ArenaCamera uses the same). Bombs drop at its top + 2 (his
//     BombDropper). Kill bounds: inner wall faces and Level Bounds; other bounds follow the classic yard's margins.
public static class BomTileLevelBuilder
{
    public sealed class Spec
    {
        public string Name,
            Source,
            Scene,
            LevelId,
            Material;
    }

    public static readonly Spec[] Levels =
    {
        new Spec { Name = "YardLevel", Source = "Assets/Game/Scenes/YardLevel.unity", Scene = "Assets/BOMIntegration/NetworkYardTiles.unity", LevelId = "bomb-yard-tiles-v1", Material = "earth" },
        new Spec { Name = "BridgeLevel", Source = "Assets/Game/Scenes/BridgeLevel.unity", Scene = "Assets/BOMIntegration/NetworkBridge.unity", LevelId = "bomb-bridge-v1", Material = "wood" },
        new Spec { Name = "TowerLevel", Source = "Assets/Game/Scenes/TowerLevel.unity", Scene = "Assets/BOMIntegration/NetworkTower.unity", LevelId = "bomb-tower-v1", Material = "stone" },
    };

    const float PlayerHalfDepth = .45f, // Darryn's Player.prefab CharacterController radius
        MaxTrim = .5f,
        SupportGap = .3f,
        MinTile = .2f,
        Seam = 1e-5f;

    static readonly string[] PresentationRoots = { "BOM native yard session", "Network menu and arena HUD", "BOM native yard camera" };

    [Serializable]
    sealed class TileRow
    {
        public string path,
            behaviour,
            classification,
            motion,
            note;
        public Vector2 depth,
            original_min,
            original_max,
            final_min,
            final_max;
        public float trimmed;
        public int anchors;
    }

    [Serializable]
    sealed class TileReport
    {
        public string level,
            source_scene,
            derived_scene,
            level_id;
        public float player_plane_z,
            max_trim;
        public int tiles,
            exported,
            off_plane,
            outside_arena,
            anchored,
            dynamic,
            trimmed;
        public Vector2[] spawns;
        public TileRow[] rows;
    }

    sealed class Tile
    {
        public Transform T;
        public string Path,
            Behaviour;
        public bool Fragment,
            Rect,
            InPlane,
            Exported;
        public Vector2[] Hull,
            OriginalHull;
        public Vector2 Lo,
            Hi,
            Depth;
        public float ClippedArea;
        public TileRow Row;
    }

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

    static object Get(Component component, string property) =>
        component.GetType().GetProperty(property).GetValue(component);

    static Vector2[] Hull(List<Vector2> points)
    {
        points.Sort((a, b) => a.x != b.x ? a.x.CompareTo(b.x) : a.y.CompareTo(b.y));
        var hull = new List<Vector2>();
        float Cross(Vector2 o, Vector2 a, Vector2 b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
        for (int pass = 0; pass < 2; pass++)
        {
            int start = hull.Count;
            for (int i = 0; i < points.Count; i++)
            {
                var p = points[pass == 0 ? i : points.Count - 1 - i];
                while (hull.Count >= start + 2 && Cross(hull[hull.Count - 2], hull[hull.Count - 1], p) <= 1e-7f)
                    hull.RemoveAt(hull.Count - 1);
                hull.Add(p);
            }
            hull.RemoveAt(hull.Count - 1);
        }
        return hull.ToArray();
    }

    static bool Measure(Tile tile)
    {
        var points = new List<Vector2>();
        float zmin = float.MaxValue,
            zmax = float.MinValue;
        foreach (var filter in tile.T.GetComponentsInChildren<MeshFilter>(true))
        {
            if (filter.sharedMesh == null)
                continue;
            var matrix = filter.transform.localToWorldMatrix;
            foreach (var v in filter.sharedMesh.vertices)
            {
                var p = matrix.MultiplyPoint3x4(v);
                points.Add(new Vector2((float)Math.Round(p.x, 5), (float)Math.Round(p.y, 5)));
                zmin = Mathf.Min(zmin, p.z);
                zmax = Mathf.Max(zmax, p.z);
            }
        }
        if (points.Count < 3)
            return false;
        tile.Hull = Hull(points);
        tile.OriginalHull = tile.Hull;
        tile.Depth = new Vector2(zmin, zmax);
        tile.Lo = new Vector2(float.MaxValue, float.MaxValue);
        tile.Hi = -tile.Lo;
        foreach (var p in tile.Hull)
        {
            tile.Lo = Vector2.Min(tile.Lo, p);
            tile.Hi = Vector2.Max(tile.Hi, p);
        }
        tile.Rect = tile.Hull.Length == 4;
        for (int i = 0; tile.Rect && i < 4; i++)
        {
            var a = tile.Hull[i];
            var b = tile.Hull[(i + 1) % 4];
            tile.Rect = Mathf.Abs(a.x - b.x) < 1e-4f || Mathf.Abs(a.y - b.y) < 1e-4f;
        }
        return true;
    }

    static float Area(Vector2[] p)
    {
        double s = 0;
        for (int i = 0; i < p.Length; i++)
            s += (double)p[i].x * p[(i + 1) % p.Length].y - (double)p[(i + 1) % p.Length].x * p[i].y;
        return (float)(s / 2);
    }

    // Keep the part of a convex outline where dot(n, p) >= d.
    static Vector2[] HalfPlane(Vector2[] poly, Vector2 n, float d)
    {
        var result = new List<Vector2>();
        for (int i = 0; i < poly.Length; i++)
        {
            Vector2 p = poly[i],
                q = poly[(i + 1) % poly.Length];
            float sp = Vector2.Dot(n, p) - d,
                sq = Vector2.Dot(n, q) - d;
            if (sp >= 0)
                result.Add(p);
            if (sp >= 0 != sq >= 0)
                result.Add(p + (q - p) * (sp / (sp - sq)));
        }
        return result.ToArray();
    }

    // A non-box tile (Darryn's rocks) sunk into a box: cut its convex outline at the box face that removes the least area.
    static void ClipShape(Tile tile, Tile box)
    {
        float before = Area(tile.Hull);
        Vector2[] best = null;
        float bestArea = -1;
        foreach (var (n, d) in new[] { (Vector2.up, box.Hi.y), (Vector2.down, -box.Lo.y), (Vector2.right, box.Hi.x), (Vector2.left, -box.Lo.x) })
        {
            var clipped = HalfPlane(tile.Hull, n, d);
            if (clipped.Length < 3)
                continue;
            float area = Area(clipped);
            if (area > bestArea)
            {
                bestArea = area;
                best = clipped;
            }
        }
        float total = tile.ClippedArea + before - bestArea;
        if (best == null || total > Area(tile.OriginalHull) * .25f)
            throw new InvalidOperationException(tile.Path + " is sunk into " + box.Path + " too deeply to clip (" + (before - bestArea).ToString("0.###", CultureInfo.InvariantCulture) + " of " + before.ToString("0.###", CultureInfo.InvariantCulture) + ")");
        var cleaned = new List<Vector2>();
        foreach (var p in best)
            if (cleaned.Count == 0 || (p - cleaned[cleaned.Count - 1]).magnitude >= .002f)
                cleaned.Add(p);
        if (cleaned.Count > 1 && (cleaned[0] - cleaned[cleaned.Count - 1]).magnitude < .002f)
            cleaned.RemoveAt(cleaned.Count - 1);
        tile.Hull = cleaned.ToArray();
        tile.ClippedArea = total;
        tile.Lo = new Vector2(float.MaxValue, float.MaxValue);
        tile.Hi = -tile.Lo;
        foreach (var p in tile.Hull)
        {
            tile.Lo = Vector2.Min(tile.Lo, p);
            tile.Hi = Vector2.Max(tile.Hi, p);
        }
    }

    static bool Overlaps(Vector2 alo, Vector2 ahi, Vector2 blo, Vector2 bhi) =>
        Mathf.Min(ahi.x, bhi.x) - Mathf.Max(alo.x, blo.x) > Seam && Mathf.Min(ahi.y, bhi.y) - Mathf.Max(alo.y, blo.y) > Seam;

    static float Overlap1(float alo, float ahi, float blo, float bhi) => Mathf.Min(ahi, bhi) - Mathf.Max(alo, blo);

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

    static BomAnchorSegment[] EdgeAnchors(Vector2[] outline)
    {
        var anchors = new BomAnchorSegment[outline.Length];
        for (int i = 0; i < outline.Length; i++)
            anchors[i] = new BomAnchorSegment { A = outline[i], B = outline[(i + 1) % outline.Length] };
        return anchors;
    }

    static GameObject Root(Scene scene, string name)
    {
        foreach (var root in scene.GetRootGameObjects())
            if (root.name == name)
                return root;
        return null;
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

        // Walls and floor.
        var fixedParts = new List<(Transform t, Vector2 lo, Vector2 hi, Vector2 depth)>();
        foreach (string name in new[] { "Bottom Boundary", "Left Wall", "Right Wall" })
        {
            var t = layout.transform.Find(name);
            var collider = t != null ? t.GetComponent<Collider>() : null;
            if (collider == null)
                throw new InvalidOperationException(spec.Name + ": missing boundary " + name);
            var cb = collider.bounds;
            fixedParts.Add((t, new Vector2(cb.min.x, cb.min.y), new Vector2(cb.max.x, cb.max.y), new Vector2(cb.min.z, cb.max.z)));
        }
        float innerLeft = fixedParts[1].hi.x,
            innerRight = fixedParts[2].lo.x,
            floor = fixedParts[0].hi.y;

        // Tiles.
        var tiles = new List<Tile>();
        foreach (var root in scene.GetRootGameObjects())
        foreach (var component in root.GetComponentsInChildren<Component>(true))
            if (component != null && component.GetType().Name == "DestructibleObject")
            {
                var behaviour = new SerializedObject(component).FindProperty("behavior").intValue;
                var tile = new Tile
                {
                    T = component.transform,
                    Path = ObjectPath(component.transform),
                    Fragment = behaviour == 1,
                    Behaviour = behaviour == 1 ? "CarveAndFragment" : "Carve",
                };
                tile.Row = new TileRow { path = tile.Path, behaviour = tile.Behaviour };
                tiles.Add(tile);
                if (!Measure(tile))
                {
                    tile.Row.classification = "decoration";
                    tile.Row.note = "No mesh to measure";
                    continue;
                }
                tile.Row.depth = tile.Depth;
                tile.Row.original_min = tile.Lo;
                tile.Row.original_max = tile.Hi;
                tile.InPlane = tile.Depth.y > planeZ - PlayerHalfDepth && tile.Depth.x < planeZ + PlayerHalfDepth;
                if (!tile.InPlane)
                {
                    tile.Row.classification = "off-plane decoration";
                    tile.Row.note = "Depth " + tile.Depth.x.ToString("0.###", CultureInfo.InvariantCulture) + ".." + tile.Depth.y.ToString("0.###", CultureInfo.InvariantCulture)
                        + " misses the player plane z=" + planeZ.ToString("0.###", CultureInfo.InvariantCulture) + "+/-" + PlayerHalfDepth + "; visible art, not destructible on Odin";
                    continue;
                }
                // Clip to the arena (inner wall faces, floor top).
                var lo = new Vector2(Mathf.Max(tile.Lo.x, innerLeft), Mathf.Max(tile.Lo.y, floor));
                var hi = new Vector2(Mathf.Min(tile.Hi.x, innerRight), tile.Hi.y);
                if (hi.x - lo.x < MinTile || hi.y - lo.y < MinTile)
                {
                    tile.Row.classification = "outside arena decoration";
                    tile.Row.note = "Outside the walls/floor; visible art only";
                    continue;
                }
                if (!tile.Rect && (lo != tile.Lo || hi != tile.Hi))
                    throw new InvalidOperationException(tile.Path + ": a non-rectangular tile crosses a wall or the floor; author a proxy");
                if (lo != tile.Lo || hi != tile.Hi)
                    tile.Row.note = "Clipped to the arena walls/floor. ";
                tile.Lo = lo;
                tile.Hi = hi;
                tile.Exported = true;
            }

        // Seam trimming: boxes first, then other shapes (rocks), each by higher top, then lower x, then path (deterministic).
        var order = tiles.FindAll(t => t.Exported);
        order.Sort((a, c) =>
        {
            int r = c.Rect.CompareTo(a.Rect);
            if (r == 0)
                r = c.Hi.y.CompareTo(a.Hi.y);
            if (r == 0)
                r = a.Lo.x.CompareTo(c.Lo.x);
            return r != 0 ? r : string.CompareOrdinal(a.Path, c.Path);
        });
        var kept = new List<Tile>();
        float maxTrim = 0;
        foreach (var tile in order)
        {
            var origLo = tile.Lo;
            var origHi = tile.Hi;
            foreach (var other in kept)
            {
                if (!Overlaps(tile.Lo, tile.Hi, other.Lo, other.Hi))
                    continue;
                if (!other.Rect)
                    throw new InvalidOperationException(tile.Path + " overlaps " + other.Path + " and neither is an axis-aligned box; author a proxy");
                if (!tile.Rect)
                {
                    ClipShape(tile, other);
                    continue;
                }
                float left = other.Hi.x - tile.Lo.x,
                    right = tile.Hi.x - other.Lo.x,
                    bottom = other.Hi.y - tile.Lo.y,
                    top = tile.Hi.y - other.Lo.y;
                float best = Mathf.Min(Mathf.Min(left, right), Mathf.Min(bottom, top));
                // Relative to the tile as Darryn placed it (before the wall clip).
                var full = tile.Row.original_max - tile.Row.original_min;
                float size = best == left || best == right ? full.x : full.y;
                if (best > MaxTrim || best > size * .25f)
                    throw new InvalidOperationException(
                        tile.Path + " overlaps " + other.Path + " by " + best.ToString("0.###", CultureInfo.InvariantCulture) + "; too deep to trim as a seam"
                    );
                if (best == left)
                    tile.Lo.x = other.Hi.x;
                else if (best == right)
                    tile.Hi.x = other.Lo.x;
                else if (best == bottom)
                    tile.Lo.y = other.Hi.y;
                else
                    tile.Hi.y = other.Lo.y;
            }
            if (tile.Hi.x - tile.Lo.x < MinTile || tile.Hi.y - tile.Lo.y < MinTile)
            {
                tile.Exported = false;
                tile.Row.classification = "outside arena decoration";
                tile.Row.note += "Only a sliver inside the walls is left once the seams are trimmed; visible art only";
                continue;
            }
            float trim = tile.Rect ? (tile.Lo - origLo).magnitude + (tile.Hi - origHi).magnitude : tile.ClippedArea;
            tile.Row.trimmed = trim;
            if (trim > 0)
                tile.Row.note += (tile.Rect ? "Seam trimmed by " : "Outline clipped at box faces, area removed ") + trim.ToString("0.###", CultureInfo.InvariantCulture) + " against tiles kept whole. ";
            maxTrim = Mathf.Max(maxTrim, trim);
            kept.Add(tile);
        }

        // Authoring root and materials.
        var levelRoot = new GameObject("BOM " + spec.Name + " Authoring");
        SceneManager.MoveGameObjectToScene(levelRoot, scene);
        var level = levelRoot.AddComponent<BomLevelAuthoring>();
        level.LevelId = spec.LevelId;
        level.NextIdentityDecimal = "1";
        var yardScene = EditorSceneManager.OpenScene(BomNetworkMenuBuilder.ScenePath, OpenSceneMode.Additive);
        var yardLevel = UnityEngine.Object.FindObjectsByType<BomLevelAuthoring>(FindObjectsInactive.Include, FindObjectsSortMode.None);
        foreach (var candidate in yardLevel)
            if (candidate.gameObject.scene == yardScene)
            {
                // Same tuning as the classic yard (one gameplay config for every level).
                level.Gameplay = JsonUtility.FromJson<BomGameplayTuning>(JsonUtility.ToJson(candidate.Gameplay));
                level.GameplayConfigId = candidate.GameplayConfigId;
                level.Seed = candidate.Seed;
            }
        if (spec.Material == "earth")
            level.Materials.Add(new BomCustomMaterial { Name = "earth", Base = "stone", Color = new Color32(132, 95, 64, 255) });

        var shape = new BomActorShapeInfo { struct_size = (uint)System.Runtime.InteropServices.Marshal.SizeOf<BomActorShapeInfo>(), version = 1 };
        BomSession.Check(BomNative.bom_actor_shape_info(ref shape));

        // Fixed boundaries.
        var allSolid = new List<(Vector2 lo, Vector2 hi)>();
        foreach (var wall in fixedParts)
        {
            bool visible = false;
            foreach (var renderer in wall.t.GetComponentsInChildren<MeshRenderer>(true))
                if (renderer.enabled && renderer.GetComponent<MeshFilter>() != null && renderer.GetComponent<MeshFilter>().sharedMesh != null)
                    visible = true;
            var source = wall.t.gameObject.AddComponent<BomAssetInstance>();
            source.AssetKey = "tiles/" + spec.Name + "/" + wall.t.name;
            source.OriginalObjectPath = ObjectPath(wall.t);
            source.Motion = BomMotionPolicy.Fixed;
            source.Damage = BomDamagePolicy.Indestructible;
            source.FallbackDepth = wall.depth;
            source.HiddenVisual = !visible;
            source.ApproximationNote = "Explicit XY boundary from the original ArenaLayout collider" + (visible ? "" : "; invisible in the original, so hidden");
            Part(wall.t, "Native fixed boundary", RectOutline(wall.lo, wall.hi), "stone", Array.Empty<BomAnchorSegment>(), "");
            allSolid.Add((wall.lo, wall.hi));
        }

        // Tiles: motion and anchors.
        var offPlane = tiles.FindAll(t => !t.InPlane && t.Hull != null);
        foreach (var tile in kept)
            allSolid.Add((tile.Lo, tile.Hi));
        int anchored = 0,
            dynamic = 0;
        foreach (var tile in kept)
        {
            var outline = tile.Rect ? RectOutline(tile.Lo, tile.Hi) : tile.Hull;
            BomMotionPolicy motion;
            BomAnchorSegment[] anchors;
            if (!tile.Fragment)
            {
                motion = BomMotionPolicy.Anchored;
                anchors = EdgeAnchors(outline);
                tile.Row.note += "Carve: anchored on every edge.";
            }
            else
            {
                bool held = false;
                foreach (var solid in allSolid)
                    if (solid.hi.y <= tile.Lo.y + Seam && tile.Lo.y - solid.hi.y <= SupportGap && Overlap1(tile.Lo.x, tile.Hi.x, solid.lo.x, solid.hi.x) >= .05f)
                        held = true;
                if (held)
                {
                    motion = BomMotionPolicy.Dynamic;
                    anchors = Array.Empty<BomAnchorSegment>();
                    tile.Row.note += "CarveAndFragment: dynamic, resting on a tile or the floor.";
                }
                else
                {
                    motion = BomMotionPolicy.Anchored;
                    var contacts = new List<BomAnchorSegment>();
                    foreach (var pillar in offPlane)
                    {
                        float a = Mathf.Max(tile.Lo.x, pillar.Lo.x),
                            c = Mathf.Min(tile.Hi.x, pillar.Hi.x);
                        if (Mathf.Abs(pillar.Hi.y - tile.Lo.y) <= SupportGap && c - a >= .05f)
                            contacts.Add(new BomAnchorSegment { A = new Vector2(a, tile.Lo.y), B = new Vector2(c, tile.Lo.y) });
                    }
                    if (contacts.Count > 0)
                        tile.Row.note += "CarveAndFragment on off-plane pillars: anchored at " + contacts.Count + " pillar contact(s) (falls when a blast removes them).";
                    else
                    {
                        contacts.Add(new BomAnchorSegment { A = new Vector2(tile.Lo.x, tile.Lo.y), B = new Vector2(tile.Hi.x, tile.Lo.y) });
                        tile.Row.note += "CarveAndFragment with nothing under it in the original: anchored on its bottom edge.";
                    }
                    anchors = contacts.ToArray();
                }
            }
            if (motion == BomMotionPolicy.Anchored)
                anchored++;
            else
                dynamic++;
            var source = tile.T.gameObject.AddComponent<BomAssetInstance>();
            source.AssetKey = MeshKey(tile.T);
            source.OriginalObjectPath = tile.Path;
            source.Motion = motion;
            source.Damage = BomDamagePolicy.Destructible;
            source.FallbackDepth = tile.Depth;
            source.ApproximationNote = "C6 tile (" + tile.Behaviour + "): " + tile.Row.note;
            Part(tile.T, "Native tile proxy", outline, spec.Material, anchors, tile.Row.trimmed > 0 ? tile.Row.note : "");
            tile.Row.classification = "native tile";
            tile.Row.motion = motion.ToString();
            tile.Row.final_min = tile.Lo;
            tile.Row.final_max = tile.Hi;
            tile.Row.anchors = anchors.Length;
        }

        // Spawns: Darryn's spacing around the layout spawn, dropped onto the first surface below.
        float half = shape.player_segment + shape.player_radius;
        var spawns = new Vector2[4];
        for (int i = 0; i < 4; i++)
        {
            float x = desired.x + (i - 1.5f) * spacing;
            float top = float.MinValue;
            foreach (var solid in allSolid)
                if (Overlap1(x - shape.player_radius, x + shape.player_radius, solid.lo.x, solid.hi.x) > 0 && solid.hi.y <= desired.y + .5f)
                    top = Mathf.Max(top, solid.hi.y);
            spawns[i] = new Vector2(x, top > float.MinValue ? top + half + .05f : desired.y);
        }
        level.Spawns = spawns;
        level.CameraBounds = new BomBounds2(new Vector2(b.min.x, b.min.y), new Vector2(b.max.x, b.max.y));
        float bombHeight = b.max.y + 2; // BombDropper: CameraBounds.max.y + dropHeightAboveArena (2)
        level.SimulationBounds = new BomBounds2(new Vector2(b.min.x - 4, fixedParts[0].lo.y - 2), new Vector2(b.max.x + 4, bombHeight + 2));
        level.KillBounds = new BomBounds2(new Vector2(innerLeft, b.min.y), new Vector2(innerRight, b.max.y)); // classic yard: walls + Level Bounds
        level.AimBounds = new BomBounds2(level.SimulationBounds.Minimum + Vector2.one, level.SimulationBounds.Maximum - Vector2.one);
        level.FragmentCullBounds = new BomBounds2(level.SimulationBounds.Minimum - new Vector2(8, 4), level.SimulationBounds.Maximum + new Vector2(8, 7));
        level.BombCleanupBounds = new BomBounds2(level.SimulationBounds.Minimum - new Vector2(2, 1), level.SimulationBounds.Maximum + new Vector2(2, 5));
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

        var report = new TileReport
        {
            level = spec.Name,
            source_scene = spec.Source,
            derived_scene = spec.Scene,
            level_id = spec.LevelId,
            player_plane_z = planeZ,
            max_trim = maxTrim,
            tiles = tiles.Count,
            exported = kept.Count,
            off_plane = tiles.FindAll(t => t.Row.classification == "off-plane decoration").Count,
            outside_arena = tiles.FindAll(t => t.Row.classification == "outside arena decoration").Count,
            anchored = anchored,
            dynamic = dynamic,
            trimmed = kept.FindAll(t => t.Row.trimmed > 0).Count,
            spawns = spawns,
            rows = tiles.ConvertAll(t => t.Row).ToArray(),
        };
        Directory.CreateDirectory(Path.GetDirectoryName(output));
        File.WriteAllText(output + ".tiles.json", JsonUtility.ToJson(report, true));

        var registry = BomLevelExporter.Export(level, output);
        client.VisualRegistry = registry;
        EditorUtility.SetDirty(client);
        EditorSceneManager.SaveScene(scene, spec.Scene);
        AssetDatabase.SaveAssets();
        Debug.Log(
            "BOM TILE LEVEL EXPORTED " + spec.Name + " tiles=" + report.tiles + " exported=" + report.exported + " off_plane=" + report.off_plane
                + " outside=" + report.outside_arena + " anchored=" + anchored + " dynamic=" + dynamic + " trimmed=" + report.trimmed
                + " max_trim=" + maxTrim.ToString("0.###", CultureInfo.InvariantCulture) + " layout=" + output
        );
        return registry;
    }
}
