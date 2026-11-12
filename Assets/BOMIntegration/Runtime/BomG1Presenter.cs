using System;
using System.Collections.Generic;
using System.Diagnostics;
using Bom.Native;
using UnityEngine;
using Debug = UnityEngine.Debug;

namespace Bom.Unity
{
    // G1 prototype (opt-in only: --bom-g1 or BOM_G1=1; nothing changes without it). Draws every native cell from the 2D
    // simulation itself: each body is extruded to a depth derived from its own piece's area (deterministic, the same on
    // every client), so a chip looks like a chip and an intact slab fills the play band. Meshes are persistent: a body's
    // chunk is rebuilt only when its cell set changes, into the same Mesh object, from per-cell geometry cached by cell id
    // (native cells are immutable). Darryn's tile materials are reused for the look and his tile renderers are hidden,
    // because in a G1 level every visible tile is a physical part. Owns no collider and decides nothing.
    public sealed class BomG1Presenter : IDisposable
    {
        static bool? enabled;
        public static bool Enabled
        {
            get
            {
                if (enabled == null)
                {
                    var args = Environment.GetCommandLineArgs();
                    enabled =
                        Array.IndexOf(args, "--bom-g1") >= 0
                        || Environment.GetEnvironmentVariable("BOM_G1") == "1";
                }
                return enabled.Value;
            }
        }

        static float Arg(string key, float value)
        {
            var args = Environment.GetCommandLineArgs();
            int i = Array.IndexOf(args, key);
            return
                i >= 0
                && i + 1 < args.Length
                && float.TryParse(
                    args[i + 1],
                    System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture,
                    out float parsed
                )
                ? parsed
                : value;
        }

        // Play band: the deepest a piece is drawn (the player capsule is 0.9 deep, so a band >= 0.9 never hides it).
        public readonly float Band = Arg("--bom-g1-band", 1.6f),
            MinDepth = Arg("--bom-g1-min-depth", 0.1f),
            DepthScale = Arg("--bom-g1-depth-scale", 1f);
        const float DepthStep = 0.02f,
            ChunkSize = 4f;
        const int ChunkCells = 192;

        public static float DepthFor(float area, float scale, float min, float band) =>
            Mathf.Clamp(Mathf.Sqrt(Mathf.Max(area, 0)) * scale, min, band);

        sealed class Look
        {
            public Material Face,
                Side;
            public MaterialPropertyBlock FaceBlock,
                SideBlock;
        }

        sealed class Chunk
        {
            public GameObject Object;
            public Mesh Mesh;
            public MeshRenderer Renderer;
            public ulong Signature;
            public int Look = -1;
            public bool Seen;
        }

        sealed class Body
        {
            public Transform Transform;
            public Vector2 Pivot;
            public readonly Dictionary<long, Chunk> Chunks = new Dictionary<long, Chunk>();
            public bool Seen;
        }

        sealed class Work
        {
            public readonly List<int> Cells = new List<int>();
            public float Area;
            public Vector2 Pivot;
            public ulong Piece;
        }

        readonly Transform root;
        readonly Material fallback;
        readonly Dictionary<(uint, ulong), Body> bodies = new Dictionary<(uint, ulong), Body>();
        readonly Dictionary<(ulong, int), BomMeshGeometry> geometry =
            new Dictionary<(ulong, int), BomMeshGeometry>();
        readonly HashSet<(ulong, int)> geometrySeen = new HashSet<(ulong, int)>();
        readonly List<(ulong, int)> geometryDrop = new List<(ulong, int)>();
        readonly Dictionary<(uint, ulong), Work> work = new Dictionary<(uint, ulong), Work>();
        readonly Stack<Work> workPool = new Stack<Work>();
        readonly Dictionary<ulong, float> pieceArea = new Dictionary<ulong, float>();
        readonly Dictionary<long, List<int>> chunkCells = new Dictionary<long, List<int>>();
        readonly Stack<List<int>> listPool = new Stack<List<int>>();
        readonly List<Look> looks = new List<Look>();
        readonly Dictionary<string, int> lookByKey = new Dictionary<string, int>();
        readonly Stack<Chunk> chunkPool = new Stack<Chunk>();
        readonly Stack<Transform> bodyPool = new Stack<Transform>();
        readonly List<(uint, ulong)> bodyDrop = new List<(uint, ulong)>();
        readonly List<long> chunkDrop = new List<long>();
        readonly List<Vector3> vertices = new List<Vector3>(),
            normals = new List<Vector3>();
        readonly List<Vector2> uv = new List<Vector2>();
        readonly List<int> faces = new List<int>(),
            sides = new List<int>();
        bool hidTiles;
        public int LastRebuiltChunks { get; private set; }
        public int LastNewCells { get; private set; }
        public int LastChunks { get; private set; }
        public double LastMilliseconds { get; private set; }
        public long Applies { get; private set; }

        public BomG1Presenter(Transform parent, Material fallback)
        {
            root = new GameObject("BOM G1 bodies").transform;
            root.SetParent(parent, false);
            this.fallback = fallback;
            Debug.Log(
                "BOM G1 ON band="
                    + Band.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                    + " min_depth="
                    + MinDepth.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                    + " depth_scale="
                    + DepthScale.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
            );
        }

        static float Area(BomSession client, BomCell cell)
        {
            float a = 0;
            uint n = cell.vertex_count;
            for (uint j = 0; j < n; j++)
            {
                var p = client.Vertices[cell.vertex_start + j];
                var q = client.Vertices[cell.vertex_start + (j + 1) % n];
                a += p.x * q.y - q.x * p.y;
            }
            return Mathf.Abs(a) * 0.5f;
        }

        // Darryn's tiles: remember each tile's material by object path, then hide every tile renderer (a G1 level makes
        // every visible tile a physical part, so his originals would double up or show non-physical decoration).
        readonly Dictionary<string, Material> tileMaterials = new Dictionary<string, Material>();

        static string PathOf(Transform t) => t.parent == null ? t.name : PathOf(t.parent) + "/" + t.name;

        void HideTiles()
        {
            hidTiles = true;
            int hidden = 0;
            foreach (var behaviour in UnityEngine.Object.FindObjectsByType<MonoBehaviour>(
                FindObjectsInactive.Include,
                FindObjectsSortMode.None
            ))
            {
                if (behaviour == null || behaviour.GetType().Name != "DestructibleObject")
                    continue;
                foreach (var renderer in behaviour.GetComponentsInChildren<Renderer>(true))
                {
                    if (renderer.sharedMaterial != null)
                        tileMaterials[PathOf(behaviour.transform)] = renderer.sharedMaterial;
                    if (renderer.enabled)
                        hidden++;
                    renderer.enabled = false;
                }
            }
            Debug.Log("BOM G1 TILES materials=" + tileMaterials.Count + " hidden_renderers=" + hidden);
        }

        // A G1 layout names, per source, the Darryn tiles it replaces: asset key "g1:<path>" and cap key
        // "g1-also:<path>|<path>...". Their material dresses the extrusion and their renderers are hidden (the derived
        // scenes keep his truss/pillar renderers as decoration and strip DestructibleObject, so names are the link).
        readonly Dictionary<ulong, Material> sourceMaterials = new Dictionary<ulong, Material>();
        int hiddenByPath;

        Material SourceMaterial(BomSession client, ulong source)
        {
            if (sourceMaterials.TryGetValue(source, out var known))
                return known;
            Material found = null;
            if (source != 0 && client.Sources.TryGetValue(source, out var state))
            {
                var paths = new List<string>();
                if (state.AssetKey.StartsWith("g1:", StringComparison.Ordinal))
                    paths.Add(state.AssetKey.Substring(3));
                if (state.CapKey.StartsWith("g1-also:", StringComparison.Ordinal))
                    paths.AddRange(state.CapKey.Substring(8).Split('|'));
                foreach (string path in paths)
                {
                    if (tileMaterials.TryGetValue(path, out var remembered) && found == null)
                        found = remembered;
                    var obj = GameObject.Find(path);
                    if (obj == null)
                        continue;
                    foreach (var renderer in obj.GetComponentsInChildren<Renderer>(true))
                    {
                        if (found == null && renderer.sharedMaterial != null)
                            found = renderer.sharedMaterial;
                        if (renderer.enabled)
                            hiddenByPath++;
                        renderer.enabled = false;
                    }
                }
            }
            sourceMaterials[source] = found;
            return found;
        }

        int LookFor(BomSession client, ulong source, uint rgba)
        {
            Material tile = SourceMaterial(client, source);
            string key = tile != null ? "m:" + tile.GetInstanceID() : "c:" + rgba;
            if (lookByKey.TryGetValue(key, out int index))
                return index;
            var look = new Look { FaceBlock = new MaterialPropertyBlock(), SideBlock = new MaterialPropertyBlock() };
            Color color;
            if (tile != null)
            {
                look.Face = look.Side = tile;
                color = tile.HasProperty("_BaseColor") ? tile.GetColor("_BaseColor") : Color.white;
            }
            else
            {
                look.Face = look.Side = fallback;
                color = new Color32((byte)rgba, (byte)(rgba >> 8), (byte)(rgba >> 16), 255);
                look.FaceBlock.SetColor("_BaseColor", color);
            }
            look.SideBlock.SetColor("_BaseColor", new Color(color.r * 0.7f, color.g * 0.7f, color.b * 0.7f, 1));
            looks.Add(look);
            lookByKey.Add(key, looks.Count - 1);
            return looks.Count - 1;
        }

        static ulong Mix(ulong hash, ulong value)
        {
            hash ^= value;
            return hash * 1099511628211UL;
        }

        List<int> RentList()
        {
            if (listPool.Count == 0)
                return new List<int>();
            var list = listPool.Pop();
            list.Clear();
            return list;
        }

        // Fills `outBodies` with one Transform per native body (pose kind + piece/cell id), as the stock path does.
        public void Apply(
            BomSession client,
            Dictionary<(uint, ulong), Transform> outBodies,
            bool newSession
        )
        {
            long started = Stopwatch.GetTimestamp();
            Applies++;
            if (!hidTiles)
                HideTiles();
            if (newSession)
            {
                geometry.Clear();
                foreach (var body in bodies.Values)
                    Release(body);
                bodies.Clear();
            }
            var s = client.Sample;
            pieceArea.Clear();
            foreach (var w in work.Values)
                workPool.Push(w);
            work.Clear();
            bool bound = client.Catalog.binding_count == s.cell_count;
            for (int i = 0; i < s.cell_count; i++)
            {
                var cell = client.Cells[i];
                if (cell.vertex_count < 3 || cell.vertex_start + cell.vertex_count > s.vertex_count)
                    throw new InvalidOperationException("Cell outline out of bounds");
                float a = Area(client, cell);
                pieceArea.TryGetValue(cell.piece_id, out float sum);
                pieceArea[cell.piece_id] = sum + a;
                var key = (cell.pose_kind, cell.pose_kind == 1 ? cell.id : cell.piece_id);
                if (!work.TryGetValue(key, out var w))
                {
                    w = workPool.Count > 0 ? workPool.Pop() : new Work();
                    w.Cells.Clear();
                    w.Pivot = new Vector2(cell.pivot_x, cell.pivot_y);
                    w.Piece = cell.piece_id;
                    work.Add(key, w);
                }
                w.Cells.Add(i);
            }
            foreach (var body in bodies.Values)
                body.Seen = false;
            geometrySeen.Clear();
            int rebuilt = 0,
                newCells = 0,
                chunks = 0;
            foreach (var pair in work)
            {
                var w = pair.Value;
                float depth = DepthFor(pieceArea[w.Piece], DepthScale, MinDepth, Band);
                int dq = Mathf.Max(1, Mathf.RoundToInt(depth / DepthStep));
                if (!bodies.TryGetValue(pair.Key, out var body))
                {
                    body = new Body();
                    body.Transform = bodyPool.Count > 0 ? bodyPool.Pop() : new GameObject().transform;
                    body.Transform.SetParent(root, false);
                    body.Transform.gameObject.SetActive(true);
                    body.Transform.name = "G1 body " + pair.Key;
                    body.Pivot = new Vector2(float.NaN, float.NaN);
                    bodies.Add(pair.Key, body);
                }
                body.Seen = true;
                bool moved = body.Pivot != w.Pivot;
                if (moved)
                {
                    body.Pivot = w.Pivot;
                    body.Transform.SetPositionAndRotation(new Vector3(w.Pivot.x, w.Pivot.y, 0), Quaternion.identity);
                }
                // Group the body's cells into chunks: by look, and spatially for large bodies so a blast only
                // rebuilds the chunks it touched.
                foreach (var list in chunkCells.Values)
                    listPool.Push(list);
                chunkCells.Clear();
                bool spatial = w.Cells.Count > ChunkCells;
                foreach (int i in w.Cells)
                {
                    var cell = client.Cells[i];
                    ulong source = bound ? client.CellBindings[i].source_identity : 0;
                    int look = LookFor(client, source, cell.color_rgba);
                    long ck = look;
                    if (spatial)
                        ck |=
                            ((long)(Mathf.FloorToInt(cell.rest_x / ChunkSize) & 0xffff) << 16)
                            | ((long)(Mathf.FloorToInt(cell.rest_y / ChunkSize) & 0xffff) << 32);
                    if (!chunkCells.TryGetValue(ck, out var list))
                    {
                        list = RentList();
                        chunkCells.Add(ck, list);
                    }
                    list.Add(i);
                }
                foreach (var chunk in body.Chunks.Values)
                    chunk.Seen = false;
                foreach (var cpair in chunkCells)
                {
                    ulong signature = Mix(Mix(14695981039346656037UL, (ulong)dq), (ulong)cpair.Value.Count);
                    foreach (int i in cpair.Value)
                    {
                        signature = Mix(signature, client.Cells[i].id);
                        geometrySeen.Add((client.Cells[i].id, dq));
                    }
                    int look = (int)(cpair.Key & 0xffff);
                    if (!body.Chunks.TryGetValue(cpair.Key, out var chunk))
                    {
                        chunk = RentChunk(body.Transform);
                        body.Chunks.Add(cpair.Key, chunk);
                    }
                    chunk.Seen = true;
                    chunks++;
                    if (chunk.Signature == signature && chunk.Look == look && !moved)
                        continue;
                    newCells += Build(client, cpair.Value, w.Pivot, depth, dq, chunk.Mesh);
                    chunk.Signature = signature;
                    if (chunk.Look != look)
                    {
                        chunk.Look = look;
                        var l = looks[look];
                        chunk.Renderer.sharedMaterials = new[] { l.Face, l.Side };
                        chunk.Renderer.SetPropertyBlock(l.FaceBlock, 0);
                        chunk.Renderer.SetPropertyBlock(l.SideBlock, 1);
                    }
                    rebuilt++;
                }
                chunkDrop.Clear();
                foreach (var cpair in body.Chunks)
                    if (!cpair.Value.Seen)
                        chunkDrop.Add(cpair.Key);
                foreach (long ck in chunkDrop)
                {
                    ReturnChunk(body.Chunks[ck]);
                    body.Chunks.Remove(ck);
                }
            }
            bodyDrop.Clear();
            foreach (var pair in bodies)
                if (!pair.Value.Seen)
                    bodyDrop.Add(pair.Key);
            foreach (var key in bodyDrop)
            {
                Release(bodies[key]);
                bodies.Remove(key);
            }
            geometryDrop.Clear();
            foreach (var key in geometry.Keys)
                if (!geometrySeen.Contains(key))
                    geometryDrop.Add(key);
            foreach (var key in geometryDrop)
                geometry.Remove(key);
            outBodies.Clear();
            foreach (var pair in bodies)
                outBodies.Add(pair.Key, pair.Value.Transform);
            LastRebuiltChunks = rebuilt;
            LastNewCells = newCells;
            LastChunks = chunks;
            LastMilliseconds = (Stopwatch.GetTimestamp() - started) * 1000.0 / Stopwatch.Frequency;
            if (rebuilt > 0 || Applies <= 2)
                Debug.Log(
                    "BOM G1 APPLY revision="
                        + s.revision
                        + " cells="
                        + s.cell_count
                        + " bodies="
                        + bodies.Count
                        + " chunks="
                        + chunks
                        + " rebuilt="
                        + rebuilt
                        + " new_cells="
                        + newCells
                        + " cached_cells="
                        + geometry.Count
                        + " tile_materials="
                        + sourceMaterials.Count
                        + " hidden_by_path="
                        + hiddenByPath
                        + " ms="
                        + LastMilliseconds.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture)
                );
        }

        int Build(BomSession client, List<int> cells, Vector2 pivot, float depth, int dq, Mesh mesh)
        {
            int created = 0;
            vertices.Clear();
            normals.Clear();
            uv.Clear();
            faces.Clear();
            sides.Clear();
            foreach (int i in cells)
            {
                var cell = client.Cells[i];
                if (!geometry.TryGetValue((cell.id, dq), out var g))
                {
                    int n = (int)cell.vertex_count;
                    var points = new Vector2[n];
                    for (int j = 0; j < n; j++)
                    {
                        var v = client.Vertices[cell.vertex_start + (uint)j];
                        points[j] = new Vector2(v.x - cell.rest_x, v.y - cell.rest_y);
                    }
                    g = BomExtrusion.BuildData(points, depth, new Vector2(cell.rest_x, cell.rest_y), 0);
                    geometry.Add((cell.id, dq), g);
                    created++;
                }
                var offset = new Vector3(cell.rest_x - pivot.x, cell.rest_y - pivot.y, 0);
                int first = vertices.Count;
                for (int k = 0; k < g.Vertices.Length; k++)
                    vertices.Add(g.Vertices[k] + offset);
                normals.AddRange(g.Normals);
                uv.AddRange(g.UV);
                for (int k = 0; k < g.Faces.Length; k++)
                    faces.Add(first + g.Faces[k]);
                for (int k = 0; k < g.Sides.Length; k++)
                    sides.Add(first + g.Sides[k]);
            }
            mesh.Clear();
            mesh.indexFormat =
                vertices.Count > 65000
                    ? UnityEngine.Rendering.IndexFormat.UInt32
                    : UnityEngine.Rendering.IndexFormat.UInt16;
            mesh.SetVertices(vertices);
            mesh.SetNormals(normals);
            mesh.SetUVs(0, uv);
            mesh.subMeshCount = 2;
            mesh.SetTriangles(faces, 0, false);
            mesh.SetTriangles(sides, 1, false);
            mesh.RecalculateBounds();
            return created;
        }

        Chunk RentChunk(Transform parent)
        {
            Chunk chunk;
            if (chunkPool.Count > 0)
                chunk = chunkPool.Pop();
            else
            {
                var obj = new GameObject("G1 chunk");
                chunk = new Chunk
                {
                    Object = obj,
                    Mesh = new Mesh { name = "G1 chunk" },
                    Renderer = obj.AddComponent<MeshRenderer>(),
                };
                chunk.Mesh.MarkDynamic();
                obj.AddComponent<MeshFilter>().sharedMesh = chunk.Mesh;
            }
            chunk.Object.transform.SetParent(parent, false);
            chunk.Object.SetActive(true);
            chunk.Signature = 0;
            return chunk;
        }

        void ReturnChunk(Chunk chunk)
        {
            chunk.Object.SetActive(false);
            chunk.Object.transform.SetParent(root, false);
            chunk.Signature = 0;
            chunkPool.Push(chunk);
        }

        void Release(Body body)
        {
            foreach (var chunk in body.Chunks.Values)
                ReturnChunk(chunk);
            body.Chunks.Clear();
            body.Transform.gameObject.SetActive(false);
            bodyPool.Push(body.Transform);
        }

        public void Clear()
        {
            foreach (var body in bodies.Values)
                Release(body);
            bodies.Clear();
            geometry.Clear();
        }

        public void Dispose()
        {
            if (root != null)
            {
                foreach (var mesh in root.GetComponentsInChildren<MeshFilter>(true))
                    if (mesh.sharedMesh != null)
                        UnityEngine.Object.Destroy(mesh.sharedMesh);
                UnityEngine.Object.Destroy(root.gameObject);
            }
            bodies.Clear();
            geometry.Clear();
            chunkPool.Clear();
            bodyPool.Clear();
        }
    }
}
