using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using Bom.Native;
using Unity.Collections;
using UnityEngine;
using UnityEngine.Rendering;
using Debug = UnityEngine.Debug;

namespace Bom.Unity
{
    // G2: the only native cell path (G1's prototype made the default). Presents copied native cells; owns no collider
    // and decides nothing.
    // - Bodies persist: one Transform per native body (pose kind + piece or cell id), kept across revisions and epochs.
    // - Per-cell geometry is extruded once into a native arena, keyed by (cell id, outline+depth hash). Native cells never
    //   change shape, so a round start whose cells did not change rebuilds nothing (F2 fix 1a).
    // - A body's cells are grouped into chunks (look, and 4x4-unit tiles for large bodies). A chunk is rebuilt only when
    //   its cell signature changes, into the same Mesh, through Mesh.MeshData (no managed garbage).
    // - G3 default look (BomDepthLook.Mode.Band, owner decision OD-4): every cell, intact or not, is extruded from its
    //   native outline at its piece's depth (BomDepthLook.PieceDepth) inside the play band, dressed in Darryn's materials
    //   from the visual registry (per cell, split exactly where his materials meet). Terrain sources get a static, darker
    //   back wall behind the band (no top cap, built once per source, never rebuilt).
    // - Stock look (--bom-stock-look, one release): a source that is still intact (its registry cells, one static piece)
    //   draws Darryn's own mesh; any other cell is an extrusion over the source's depth with his surface material and
    //   the interior colour on cut sides. Darryn's meshes are never clipped per fragment in either look.
    // --bom-g1 keeps the G1 prototype look (band depth, tiles hidden, materials by scene path) for its G1 layouts.
    public sealed class BomCellPresenter : IDisposable
    {
        static bool? g1Flag;
        public static bool G1
        {
            get
            {
                if (g1Flag == null)
                {
                    var args = Environment.GetCommandLineArgs();
                    g1Flag =
                        Array.IndexOf(args, "--bom-g1") >= 0
                        || Environment.GetEnvironmentVariable("BOM_G1") == "1";
                }
                return g1Flag.Value;
            }
        }

        const float ChunkSize = 4f;
        const int ChunkCells = 192;
        const string ChunkMeshName = "Native cell chunk";

        // Band look: where a cell's face covers more than one of Darryn's materials, the other materials' parts are drawn
        // as face-only overlays this far in front of the cell's face (exact edges, no holes, no clipping of the cell).
        const float OverlayLift = 0.004f;

        [StructLayout(LayoutKind.Sequential)]
        struct Vertex
        {
            public Vector3 Position,
                Normal;
            public Vector2 UV;
        }

        static readonly VertexAttributeDescriptor[] Layout =
        {
            new VertexAttributeDescriptor(VertexAttribute.Position, VertexAttributeFormat.Float32, 3),
            new VertexAttributeDescriptor(VertexAttribute.Normal, VertexAttributeFormat.Float32, 3),
            new VertexAttributeDescriptor(VertexAttribute.TexCoord0, VertexAttributeFormat.Float32, 2),
        };

        const MeshUpdateFlags UpdateFlags =
            MeshUpdateFlags.DontRecalculateBounds | MeshUpdateFlags.DontValidateIndices;

        // One extruded cell inside the arena: vertices [V, V+VN), face then side indices [I, I+FN+SN), cell-local.
        struct Geometry
        {
            public int V,
                VN,
                I,
                FN,
                SN;
            public long Stamp;
        }

        sealed class Look
        {
            public Material[] Materials;
            public MaterialPropertyBlock Face,
                Side;
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
            public Vector2 Pivot;
            public ulong Piece;
        }

        // One native source and how it is drawn this revision.
        sealed class Source
        {
            public ulong Id;
            public BomSourceState Native;
            public string AssetKey,
                VisualHash;
            public BomVisualEntry Entry;
            public HashSet<ulong> Initial;
            public Material Face;
            public float Lo,
                Hi;
            public GameObject Art,
                BackWall;
            public Mesh BackWallMesh;
            public bool ArtBuilt,
                ArtValid;
            public Transform ArtBody;
            public Vector2 ArtPivot;
            public long Stamp;
            public int Count;
            public ulong Piece;
            public bool Uniform,
                Intact;
            // Darryn's camera-facing triangles in rest space, one paint per (group, submesh): which of his materials
            // a cell sits on, and his UV mapping as a planar fit when it is exact. Built once per source at load.
            public Paint[] Paints;
            public List<PaintTriangle> Triangles;
            public List<int>[] Grid;
            public Vector2 GridMin;
            public int GridW,
                GridH;
        }

        sealed class Paint
        {
            public Material Material;
            public bool Mapped;
            // G3: depth order of Darryn's front faces (0 = deepest). Where two of his materials overlap on screen, the
            // one in front shows, so overlays are lifted by rank.
            public float Z;
            public int Rank;
            public float Ux,
                Uy,
                U0,
                Vx,
                Vy,
                V0;
        }

        struct PaintTriangle
        {
            public Vector2 A,
                B,
                C;
            public int Paint;
        }

        const float GridCell = 1f;
        readonly Dictionary<ulong, (ulong, int)> cellPaint = new Dictionary<ulong, (ulong, int)>();
        int[] cellPaintIndex = Array.Empty<int>();

        readonly Transform root;
        readonly Material fallback;
        readonly bool g1;

        // band: depth from piece area (G3 default and the G1 prototype). bandLook: the G3 default look (registry
        // materials, no intact art, material overlays, terrain back walls).
        readonly bool band,
            bandLook;
        BomVisualRegistry registry;
        readonly Dictionary<ulong, HashSet<ulong>> initial = new Dictionary<ulong, HashSet<ulong>>();
        bool trusted;
        ulong trustedHash0,
            trustedHash1,
            trustedHash2,
            trustedHash3;
        bool trustKnown;

        readonly Dictionary<(uint, ulong), Body> bodies = new Dictionary<(uint, ulong), Body>();
        readonly Dictionary<(ulong, ulong), Geometry> geometry = new Dictionary<(ulong, ulong), Geometry>();
        readonly List<(ulong, ulong)> geometryKeys = new List<(ulong, ulong)>();
        readonly Dictionary<(uint, ulong), Work> work = new Dictionary<(uint, ulong), Work>();
        readonly Stack<Work> workPool = new Stack<Work>();
        readonly Dictionary<ulong, float> pieceArea = new Dictionary<ulong, float>();
        readonly Dictionary<long, List<int>> chunkCells = new Dictionary<long, List<int>>();
        readonly Stack<List<int>> listPool = new Stack<List<int>>();
        readonly List<Look> looks = new List<Look>();
        readonly Dictionary<(int, int, uint), int> lookIndex = new Dictionary<(int, int, uint), int>();
        readonly Stack<Chunk> chunkPool = new Stack<Chunk>();
        readonly List<Mesh> ownedMeshes = new List<Mesh>();
        readonly Stack<Transform> bodyPool = new Stack<Transform>();
        readonly List<(uint, ulong)> bodyDrop = new List<(uint, ulong)>();
        readonly List<long> chunkDrop = new List<long>();
        readonly Dictionary<ulong, Source> sources = new Dictionary<ulong, Source>();
        readonly List<ulong> sourceDrop = new List<ulong>();

        // Per-cell scratch for one Apply, indexed like client.Cells.
        Source[] cellSource = Array.Empty<Source>();
        ulong[] cellShape = Array.Empty<ulong>();

        // Native arena of extruded cells.
        NativeArray<Vertex> arenaVertices;
        NativeArray<int> arenaIndices;
        int usedVertices,
            usedIndices,
            liveVertices,
            liveIndices;

        // Allocation-free ear clipping scratch.
        Vector2[] points = new Vector2[64];
        int[] order = new int[64],
            remaining = new int[64],
            cleaned = new int[64],
            triangles = new int[64 * 6];

        bool hidTiles;
        long stamp;
        public int LastRebuiltChunks { get; private set; }
        public int LastNewCells { get; private set; }
        public int LastChunks { get; private set; }
        public double LastMilliseconds { get; private set; }
        public long Applies { get; private set; }
        public int IntactSources { get; private set; }
        public int FragmentSources { get; private set; }
        public int FallbackSources { get; private set; }
        public int HiddenSources { get; private set; }
        public int CachedCells => geometry.Count;
        public long ArenaBytes => (long)usedVertices * 32 + (long)usedIndices * 4;

        public BomCellPresenter(Transform parent, Material fallback, bool g1)
        {
            root = new GameObject("Native cells").transform;
            root.SetParent(parent, false);
            this.fallback = fallback;
            this.g1 = g1;
            bandLook = !g1 && BomDepthLook.Current == BomDepthLook.Mode.Band;
            band = g1 || bandLook;
            if (g1)
                Debug.Log(
                    "BOM G1 ON band="
                        + BomDepthLook.Band.ToString("0.###", CultureInfo.InvariantCulture)
                        + " min_depth="
                        + BomDepthLook.MinDepth.ToString("0.###", CultureInfo.InvariantCulture)
                        + " depth_scale="
                        + BomDepthLook.Scale.ToString("0.###", CultureInfo.InvariantCulture)
                );
            else
                Debug.Log("BOM CELLS ON path=persistent-chunks clip=off look=" + BomDepthLook.Describe());
            // Warm the pools at join so the first blast does not create dozens of GameObjects/Meshes in one frame
            // (measured: Yard's first blast 22 ms without this, later blasts ~4 ms).
            for (int i = 0; i < WarmChunks; i++)
            {
                ReturnChunk(NewChunk());
                var body = new GameObject("Native body").transform;
                body.SetParent(root, false);
                body.gameObject.SetActive(false);
                bodyPool.Push(body);
            }
            WarmPath();
        }

        const int WarmChunks = 128;

        // First-use warm-up: one synthetic square through extrude, ear clipping and the MeshData assembly, so the
        // first blast does not pay JIT for them (measured: first blast 21-42 ms even when it rebuilt only 9 chunks).
        void WarmPath()
        {
            var watch = System.Diagnostics.Stopwatch.StartNew();
            points[0] = new Vector2(-0.5f, -0.5f);
            points[1] = new Vector2(0.5f, -0.5f);
            points[2] = new Vector2(0.5f, 0.5f);
            points[3] = new Vector2(-0.5f, 0.5f);
            var g = ExtrudePoints(4, Vector2.zero, 0, 1, null);
            parts.Clear();
            parts.Add((g, Vector3.zero));
            var chunk = chunkPool.Pop();
            Assemble(g.VN, g.FN, g.SN, chunk.Mesh);
            chunk.Mesh.Clear();
            chunkPool.Push(chunk);
            parts.Clear();
            usedVertices = usedIndices = liveVertices = liveIndices = 0;
            Debug.Log("BOM CELLS WARM ms=" + watch.Elapsed.TotalMilliseconds.ToString("0.00", CultureInfo.InvariantCulture));
        }

        void UseRegistry(BomVisualRegistry next)
        {
            if (g1)
                next = null;
            if (ReferenceEquals(next, registry))
                return;
            registry = next;
            trustKnown = false;
            initial.Clear();
            foreach (var source in sources.Values)
                DestroyArt(source);
            sources.Clear();
            if (registry == null)
                return;
            foreach (var source in registry.InitialSources)
            {
                if (!ulong.TryParse(source.SourceIdentity, NumberStyles.None, CultureInfo.InvariantCulture, out ulong id))
                    continue;
                var ids = new HashSet<ulong>();
                foreach (string text in source.InitialCellIds)
                    if (ulong.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out ulong cell))
                        ids.Add(cell);
                initial[id] = ids;
            }
        }

        // The registry's initial cell membership is only trusted for the exact gameplay manifest it was exported from.
        void UpdateTrust(BomSession client)
        {
            var c = client.Catalog;
            if (
                trustKnown
                && c.gameplay_hash0 == trustedHash0
                && c.gameplay_hash1 == trustedHash1
                && c.gameplay_hash2 == trustedHash2
                && c.gameplay_hash3 == trustedHash3
            )
                return;
            trustKnown = true;
            trustedHash0 = c.gameplay_hash0;
            trustedHash1 = c.gameplay_hash1;
            trustedHash2 = c.gameplay_hash2;
            trustedHash3 = c.gameplay_hash3;
            trusted =
                registry != null
                && registry.GameplayManifestHash
                    == BomSession.HashText(c.gameplay_hash0, c.gameplay_hash1, c.gameplay_hash2, c.gameplay_hash3);
        }

        Source SourceFor(BomSession client, ulong id)
        {
            if (!client.Sources.TryGetValue(id, out var native))
                return null;
            sources.TryGetValue(id, out var source);
            if (source != null && source.Stamp == stamp)
                return source;
            var b = native.Binding;
            if (
                source == null
                || !ReferenceEquals(source.Native, native)
                    && (
                        source.AssetKey != native.AssetKey
                        || source.VisualHash != native.VisualHash
                        || source.Lo != b.depth_lo
                        || source.Hi != b.depth_hi
                        || Matrix(b) != Matrix(source.Native.Binding)
                    )
            )
            {
                if (source != null)
                    DestroyArt(source);
                source = new Source
                {
                    Id = id,
                    AssetKey = native.AssetKey,
                    VisualHash = native.VisualHash,
                    Lo = b.depth_lo,
                    Hi = b.depth_hi,
                };
                if (registry != null && registry.TryFind(native.AssetKey, native.VisualHash, out var entry))
                {
                    source.Entry = entry;
                    foreach (var group in entry.Groups)
                    {
                        foreach (var material in group.SurfaceMaterials)
                            if (material != null)
                            {
                                source.Face = material;
                                break;
                            }
                        if (source.Face != null)
                            break;
                    }
                    if (source.Face == null)
                        source.Face = fallback;
                    initial.TryGetValue(id, out source.Initial);
                    source.Native = native;
                    if (!entry.Hidden)
                    {
                        PreparePaints(source);
                        if (bandLook && BomDepthLook.IsTerrain(source.Lo, source.Hi))
                            BuildBackWall(source);
                    }
                }
                sources[id] = source;
            }
            source.Native = native;
            source.Stamp = stamp;
            source.Count = 0;
            source.Uniform = true;
            source.Intact = false;
            return source;
        }

        void PreparePaints(Source source)
        {
            var matrix = Matrix(source.Native.Binding);
            var paints = new List<Paint>();
            var triangles = new List<PaintTriangle>();
            foreach (var group in source.Entry.Groups)
            {
                var mesh = group.Mesh;
                if (mesh == null || !mesh.isReadable)
                    continue;
                var m = matrix * group.MeshToGroup;
                var normalMatrix = m.inverse.transpose;
                var vertices = mesh.vertices;
                var normals = mesh.normals;
                var uv = mesh.uv;
                bool hasUV = uv.Length == vertices.Length;
                for (int sub = 0; sub < mesh.subMeshCount; sub++)
                {
                    var paint = new Paint
                    {
                        Material =
                            sub < group.SurfaceMaterials.Length && group.SurfaceMaterials[sub] != null
                                ? group.SurfaceMaterials[sub]
                                : fallback,
                    };
                    int index = paints.Count;
                    // Least squares u,v = a*x + b*y + c over the front-facing vertices.
                    double sxx = 0, sxy = 0, syy = 0, sx = 0, sy = 0, n = 0, sxu = 0, syu = 0, su = 0, sxv = 0, syv = 0, sv = 0;
                    var indices = mesh.GetTriangles(sub);
                    int front = 0;
                    for (int t = 0; t + 2 < indices.Length; t += 3)
                    {
                        int i0 = indices[t], i1 = indices[t + 1], i2 = indices[t + 2];
                        Vector3 p0 = m.MultiplyPoint3x4(vertices[i0]),
                            p1 = m.MultiplyPoint3x4(vertices[i1]),
                            p2 = m.MultiplyPoint3x4(vertices[i2]);
                        Vector3 normal =
                            normals.Length == vertices.Length
                                ? normalMatrix.MultiplyVector(normals[i0] + normals[i1] + normals[i2])
                                : Vector3.Cross(p1 - p0, p2 - p0);
                        if (normal.sqrMagnitude < 1e-12f || normal.normalized.z > -0.5f)
                            continue;
                        front++;
                        paint.Z += (p0.z + p1.z + p2.z) / 3;
                        triangles.Add(new PaintTriangle { A = p0, B = p1, C = p2, Paint = index });
                        if (!hasUV)
                            continue;
                        foreach (int k in new[] { i0, i1, i2 })
                        {
                            var p = m.MultiplyPoint3x4(vertices[k]);
                            double x = p.x, y = p.y, u = uv[k].x, v = uv[k].y;
                            sxx += x * x; sxy += x * y; syy += y * y; sx += x; sy += y; n++;
                            sxu += x * u; syu += y * u; su += u; sxv += x * v; syv += y * v; sv += v;
                        }
                    }
                    if (hasUV && front > 0)
                    {
                        // Solve [sxx sxy sx; sxy syy sy; sx sy n] * [a b c] = rhs (Cramer).
                        double det = sxx * (syy * n - sy * sy) - sxy * (sxy * n - sy * sx) + sx * (sxy * sy - syy * sx);
                        if (Math.Abs(det) > 1e-9)
                        {
                            double[] Solve(double r0, double r1, double r2) =>
                                new[]
                                {
                                    (r0 * (syy * n - sy * sy) - sxy * (r1 * n - sy * r2) + sx * (r1 * sy - syy * r2)) / det,
                                    (sxx * (r1 * n - sy * r2) - r0 * (sxy * n - sy * sx) + sx * (sxy * r2 - r1 * sx)) / det,
                                    (sxx * (syy * r2 - r1 * sy) - sxy * (sxy * r2 - r1 * sx) + r0 * (sxy * sy - syy * sx)) / det,
                                };
                            var a = Solve(sxu, syu, su);
                            var b = Solve(sxv, syv, sv);
                            paint.Ux = (float)a[0]; paint.Uy = (float)a[1]; paint.U0 = (float)a[2];
                            paint.Vx = (float)b[0]; paint.Vy = (float)b[1]; paint.V0 = (float)b[2];
                            // Exact only: every front vertex must map within 1e-3 of its own UV.
                            double worst = 0;
                            for (int t = 0; t + 2 < indices.Length; t += 3)
                            for (int c = 0; c < 3; c++)
                            {
                                int k = indices[t + c];
                                var p = m.MultiplyPoint3x4(vertices[k]);
                                Vector3 normal =
                                    normals.Length == vertices.Length
                                        ? normalMatrix.MultiplyVector(normals[indices[t]] + normals[indices[t + 1]] + normals[indices[t + 2]])
                                        : Vector3.forward;
                                if (normals.Length == vertices.Length && (normal.sqrMagnitude < 1e-12f || normal.normalized.z > -0.5f))
                                    continue;
                                worst = Math.Max(worst, Math.Abs(paint.Ux * p.x + paint.Uy * p.y + paint.U0 - uv[k].x));
                                worst = Math.Max(worst, Math.Abs(paint.Vx * p.x + paint.Vy * p.y + paint.V0 - uv[k].y));
                            }
                            paint.Mapped = worst < 1e-3;
                        }
                    }
                    if (front > 0)
                        paint.Z /= front;
                    paints.Add(paint);
                }
            }
            if (paints.Count == 0)
                return;
            source.Paints = paints.ToArray();
            foreach (var a in paints)
                foreach (var b in paints)
                    if (b.Z > a.Z || b.Z == a.Z && paints.IndexOf(b) < paints.IndexOf(a))
                        a.Rank++;
            source.Triangles = triangles; // the authored front outline (G3 back wall, material overlays)
            if (paints.Count == 1 || triangles.Count == 0)
                return;
            Vector2 lo = triangles[0].A, hi = lo;
            foreach (var t in triangles)
            {
                lo = Vector2.Min(lo, Vector2.Min(t.A, Vector2.Min(t.B, t.C)));
                hi = Vector2.Max(hi, Vector2.Max(t.A, Vector2.Max(t.B, t.C)));
            }
            source.GridMin = lo;
            source.GridW = Mathf.Clamp(Mathf.CeilToInt((hi.x - lo.x) / GridCell) + 1, 1, 4096);
            source.GridH = Mathf.Clamp(Mathf.CeilToInt((hi.y - lo.y) / GridCell) + 1, 1, 4096);
            source.Grid = new List<int>[source.GridW * source.GridH];
            for (int i = 0; i < triangles.Count; i++)
            {
                var t = triangles[i];
                Vector2 a = Vector2.Min(t.A, Vector2.Min(t.B, t.C)), b = Vector2.Max(t.A, Vector2.Max(t.B, t.C));
                int x0 = Cell(a.x - lo.x, source.GridW), x1 = Cell(b.x - lo.x, source.GridW),
                    y0 = Cell(a.y - lo.y, source.GridH), y1 = Cell(b.y - lo.y, source.GridH);
                for (int y = y0; y <= y1; y++)
                for (int x = x0; x <= x1; x++)
                {
                    ref var bucket = ref source.Grid[y * source.GridW + x];
                    bucket ??= new List<int>();
                    bucket.Add(i);
                }
            }
            int mapped = 0;
            foreach (var p in paints)
                if (p.Mapped)
                    mapped++;
            Debug.Log(
                "BOM CELLS PAINTS source=" + source.Id + " asset=" + source.AssetKey + " paints=" + paints.Count
                    + " mapped=" + mapped + " front_triangles=" + triangles.Count
            );
        }

        static int Cell(float offset, int size) => Mathf.Clamp(Mathf.FloorToInt(offset / GridCell), 0, size - 1);

        // Which of Darryn's paints a cell sits on (its centroid's front triangle, else the nearest one). Cached per cell.
        int PaintOf(BomSession client, Source source, int i)
        {
            if (source.Paints == null)
                return -1;
            if (source.Paints.Length == 1 || source.Grid == null)
                return 0;
            var cell = client.Cells[i];
            if (cellPaint.TryGetValue(cell.id, out var known) && known.Item1 == cellShape[i])
                return known.Item2;
            Vector2 c = Vector2.zero;
            for (uint j = 0; j < cell.vertex_count; j++)
            {
                var v = client.Vertices[cell.vertex_start + j];
                c += new Vector2(v.x, v.y);
            }
            c /= cell.vertex_count;
            int found = -1;
            float best = float.MaxValue;
            int gx = Cell(c.x - source.GridMin.x, source.GridW), gy = Cell(c.y - source.GridMin.y, source.GridH);
            for (int ring = 0; ring < 3 && found < 0; ring++)
            for (int y = gy - ring; y <= gy + ring; y++)
            for (int x = gx - ring; x <= gx + ring; x++)
            {
                if (x < 0 || y < 0 || x >= source.GridW || y >= source.GridH)
                    continue;
                var bucket = source.Grid[y * source.GridW + x];
                if (bucket == null)
                    continue;
                foreach (int k in bucket)
                {
                    var t = source.Triangles[k];
                    float d1 = Cross(t.A, t.B, c), d2 = Cross(t.B, t.C, c), d3 = Cross(t.C, t.A, c);
                    bool inside = (d1 >= 0 && d2 >= 0 && d3 >= 0) || (d1 <= 0 && d2 <= 0 && d3 <= 0);
                    float distance = inside ? -1 : ((t.A + t.B + t.C) / 3 - c).sqrMagnitude;
                    if (distance < best)
                    {
                        best = distance;
                        found = t.Paint;
                    }
                }
            }
            if (found < 0)
                found = 0;
            cellPaint[cell.id] = (cellShape[i], found);
            return found;
        }

        static Matrix4x4 Matrix(BomSourceBinding b) =>
            new Matrix4x4(
                new Vector4(b.m00, b.m10, b.m20, b.m30),
                new Vector4(b.m01, b.m11, b.m21, b.m31),
                new Vector4(b.m02, b.m12, b.m22, b.m32),
                new Vector4(b.m03, b.m13, b.m23, b.m33)
            );

        // Darryn's own mesh for an intact source: one child per visual group, placed by the source matrix in native
        // rest space. Built once per source; drawn only while the source is intact.
        void BuildArt(Source source)
        {
            source.ArtBuilt = true;
            source.ArtValid = false;
            var groups = source.Entry.Groups;
            if (groups.Length == 0)
                return;
            var matrix = Matrix(source.Native.Binding);
            var art = new GameObject("BOM source " + source.Id + " intact");
            art.SetActive(false);
            art.transform.SetParent(root, false);
            source.Art = art;
            foreach (var group in groups)
            {
                var m = matrix * group.MeshToGroup;
                if (group.Mesh == null || !m.ValidTRS() || m.determinant <= 1e-8f)
                {
                    Debug.LogWarning(
                        "BOM CELLS ART EXTRUDED source=" + source.Id + " asset=" + source.AssetKey + " reason=non_trs_group"
                    );
                    return;
                }
                var child = new GameObject("group");
                child.transform.SetParent(art.transform, false);
                child.transform.localPosition = m.GetColumn(3);
                child.transform.localRotation = m.rotation;
                child.transform.localScale = m.lossyScale;
                child.AddComponent<MeshFilter>().sharedMesh = group.Mesh;
                var materials = new Material[group.Mesh.subMeshCount];
                for (int sub = 0; sub < materials.Length; sub++)
                    materials[sub] =
                        sub < group.SurfaceMaterials.Length && group.SurfaceMaterials[sub] != null
                            ? group.SurfaceMaterials[sub]
                            : fallback;
                child.AddComponent<MeshRenderer>().sharedMaterials = materials;
            }
            source.ArtValid = true;
        }

        void DetachArt(Source source)
        {
            if (source.Art == null || source.ArtBody == null && !source.Art.activeSelf)
                return;
            source.Art.SetActive(false);
            source.Art.transform.SetParent(root, false);
            source.ArtBody = null;
        }

        void DestroyArt(Source source)
        {
            if (source.Art != null)
                UnityEngine.Object.Destroy(source.Art);
            if (source.BackWall != null)
                UnityEngine.Object.Destroy(source.BackWall);
            if (source.BackWallMesh != null)
                UnityEngine.Object.Destroy(source.BackWallMesh);
            source.BackWall = null;
            source.BackWallMesh = null;
            source.Art = null;
            source.ArtBody = null;
            source.ArtBuilt = false;
        }

        // G3 terrain back wall: Darryn's authored front triangles of this source (its intact outline, from the registry),
        // flat at BomDepthLook.BackWallZ, darker, no top cap and no sides. Built once when the source is first seen and
        // never rebuilt: blasts only take away the front layer, so a crater shows dark earth behind.
        void BuildBackWall(Source source)
        {
            var tris = source.Triangles;
            float z = BomDepthLook.BackWallZ;
            if (source.Paints == null || tris == null || tris.Count == 0 || source.Hi <= z)
                return;
            int paints = source.Paints.Length;
            var vertices = new List<Vector3>(tris.Count * 3);
            var uvs = new List<Vector2>(tris.Count * 3);
            var perPaint = new List<int>[paints];
            foreach (var t in tris)
            {
                var paint = source.Paints[t.Paint];
                Vector2 b = t.B,
                    c = t.C;
                if (Cross(t.A, b, c) > 0) // front faces are clockwise as seen by the camera (as Triangulate emits them)
                {
                    b = t.C;
                    c = t.B;
                }
                int at = vertices.Count;
                foreach (var p in new[] { t.A, b, c })
                {
                    vertices.Add(new Vector3(p.x, p.y, z));
                    uvs.Add(
                        paint.Mapped
                            ? new Vector2(paint.Ux * p.x + paint.Uy * p.y + paint.U0, paint.Vx * p.x + paint.Vy * p.y + paint.V0)
                            : p
                    );
                }
                (perPaint[t.Paint] ??= new List<int>()).AddRange(new[] { at, at + 1, at + 2 });
            }
            var mesh = new Mesh { name = "BOM back wall", indexFormat = vertices.Count > 65000 ? IndexFormat.UInt32 : IndexFormat.UInt16 };
            mesh.SetVertices(vertices);
            var normals = new Vector3[vertices.Count];
            for (int k = 0; k < normals.Length; k++)
                normals[k] = Vector3.back;
            mesh.normals = normals;
            mesh.SetUVs(0, uvs);
            var materials = new List<Material>();
            var blocks = new List<MaterialPropertyBlock>();
            for (int p = 0; p < paints; p++)
            {
                if (perPaint[p] == null)
                    continue;
                var material = source.Paints[p].Material;
                var block = new MaterialPropertyBlock();
                Color color =
                    material != null && material.HasProperty("_BaseColor") ? material.GetColor("_BaseColor")
                    : material != null && material.HasProperty("_Color") ? material.GetColor("_Color")
                    : Color.white;
                float shade = BomDepthLook.BackWallShade;
                var dark = new Color(color.r * shade, color.g * shade, color.b * shade, 1);
                block.SetColor("_BaseColor", dark);
                block.SetColor("_Color", dark);
                materials.Add(material);
                blocks.Add(block);
            }
            mesh.subMeshCount = materials.Count;
            for (int p = 0, sub = 0; p < paints; p++)
                if (perPaint[p] != null)
                    mesh.SetTriangles(perPaint[p], sub++, true);
            mesh.RecalculateBounds();
            var wall = new GameObject("BOM source " + source.Id + " back wall");
            wall.transform.SetParent(root, false);
            wall.AddComponent<MeshFilter>().sharedMesh = mesh;
            var renderer = wall.AddComponent<MeshRenderer>();
            renderer.sharedMaterials = materials.ToArray();
            renderer.shadowCastingMode = ShadowCastingMode.Off;
            for (int sub = 0; sub < blocks.Count; sub++)
                renderer.SetPropertyBlock(blocks[sub], sub);
            source.BackWall = wall;
            source.BackWallMesh = mesh;
            BackWalls++;
        }

        public int BackWalls { get; private set; }

        // ---- G3 band look: exact material edges. A cell's face is drawn whole in the paint that covers most of it; each
        // other paint it touches is drawn as a face-only overlay of exactly (cell intersect that paint's triangles), lifted
        // OverlayLift towards the camera. Cached per cell (native cell outlines never change). ----
        readonly Dictionary<ulong, (ulong shape, int main, int extra)> cellSplit =
            new Dictionary<ulong, (ulong, int, int)>();
        readonly List<Vector2> cellPoly = new List<Vector2>(),
            clipA = new List<Vector2>(),
            clipB = new List<Vector2>();
        readonly List<int> triangleHits = new List<int>();
        readonly HashSet<int> triangleSeen = new HashSet<int>();
        readonly float[] paintArea = new float[32];
        const int MaxSplitPaints = 31;

        void LoadCell(BomSession client, BomCell cell)
        {
            cellPoly.Clear();
            for (uint j = 0; j < cell.vertex_count; j++)
            {
                var v = client.Vertices[cell.vertex_start + j];
                cellPoly.Add(new Vector2(v.x, v.y));
            }
        }

        // Darryn's front triangles whose grid buckets overlap the loaded cell's bounds.
        void CollectTriangles(Source source)
        {
            triangleHits.Clear();
            triangleSeen.Clear();
            Vector2 lo = cellPoly[0],
                hi = lo;
            foreach (var p in cellPoly)
            {
                lo = Vector2.Min(lo, p);
                hi = Vector2.Max(hi, p);
            }
            int x0 = Cell(lo.x - source.GridMin.x, source.GridW), x1 = Cell(hi.x - source.GridMin.x, source.GridW),
                y0 = Cell(lo.y - source.GridMin.y, source.GridH), y1 = Cell(hi.y - source.GridMin.y, source.GridH);
            for (int y = y0; y <= y1; y++)
            for (int x = x0; x <= x1; x++)
            {
                var bucket = source.Grid[y * source.GridW + x];
                if (bucket == null)
                    continue;
                foreach (int k in bucket)
                    if (triangleSeen.Add(k))
                        triangleHits.Add(k);
            }
        }

        // The loaded cell clipped to one triangle (Sutherland-Hodgman); the result is in the returned list.
        List<Vector2> Clip(PaintTriangle t)
        {
            Vector2 a = t.A,
                b = t.B,
                c = t.C;
            if (Cross(a, b, c) < 0)
            {
                b = t.C;
                c = t.B;
            }
            clipA.Clear();
            clipA.AddRange(cellPoly);
            ClipEdge(clipA, clipB, a, b);
            ClipEdge(clipB, clipA, b, c);
            ClipEdge(clipA, clipB, c, a);
            return clipB;
        }

        static void ClipEdge(List<Vector2> input, List<Vector2> output, Vector2 e0, Vector2 e1)
        {
            output.Clear();
            int n = input.Count;
            for (int k = 0; k < n; k++)
            {
                Vector2 p = input[k],
                    q = input[(k + 1) % n];
                float dp = Cross(e0, e1, p),
                    dq = Cross(e0, e1, q);
                if (dp >= 0)
                    output.Add(p);
                if ((dp >= 0) != (dq >= 0))
                    output.Add(p + (q - p) * (dp / (dp - dq)));
            }
        }

        static float PolygonArea(List<Vector2> poly)
        {
            float a = 0;
            for (int k = 0; k < poly.Count; k++)
            {
                Vector2 p = poly[k],
                    q = poly[(k + 1) % poly.Count];
                a += p.x * q.y - q.x * p.y;
            }
            return a * 0.5f;
        }

        // main: the paint drawn on the whole cell; extra: bit mask of paints drawn as overlays (0 = none).
        void Split(BomSession client, Source source, int i, out int main, out int extra)
        {
            main = PaintOf(client, source, i);
            extra = 0;
            if (!bandLook || source.Grid == null || source.Triangles == null || source.Paints.Length > MaxSplitPaints)
                return;
            var cell = client.Cells[i];
            if (cellSplit.TryGetValue(cell.id, out var known) && known.shape == cellShape[i])
            {
                if (known.main >= 0)
                    main = known.main;
                extra = known.extra;
                return;
            }
            LoadCell(client, cell);
            CollectTriangles(source);
            int paints = source.Paints.Length;
            Array.Clear(paintArea, 0, paints);
            foreach (int k in triangleHits)
            {
                var t = source.Triangles[k];
                var clipped = Clip(t);
                if (clipped.Count >= 3)
                    paintArea[t.Paint] += Mathf.Abs(PolygonArea(clipped));
            }
            float cellArea = Mathf.Abs(PolygonArea(cellPoly));
            // The whole face takes the deepest material that covers part of the cell; each material in front of it is
            // an overlay, drawn nearer the camera the further forward Darryn placed it.
            float minArea = Mathf.Max(1e-5f, cellArea * 0.002f);
            int best = -1;
            for (int p = 0; p < paints; p++)
                if (paintArea[p] > minArea && (best < 0 || source.Paints[p].Rank < source.Paints[best].Rank))
                    best = p;
            int mask = 0;
            if (best >= 0)
                for (int p = 0; p < paints; p++)
                    if (p != best && paintArea[p] > minArea)
                        mask |= 1 << p;
            cellSplit[cell.id] = (cellShape[i], best, mask);
            if (best >= 0)
                main = best;
            extra = mask;
        }

        // Face-only overlay for one cell and one paint: exactly the cell's part covered by that paint, in front of the
        // cell's face, with that paint's UV mapping.
        Geometry ExtrudeOverlay(BomSession client, BomCell cell, float lo, Source source, int paintIndex)
        {
            var paint = source.Paints[paintIndex];
            var rest = new Vector2(cell.rest_x, cell.rest_y);
            float z = lo - OverlayLift * Mathf.Max(1, paint.Rank);
            LoadCell(client, cell);
            CollectTriangles(source);
            Reserve(0, 0);
            var g = new Geometry
            {
                V = usedVertices,
                I = usedIndices,
                Stamp = stamp,
            };
            foreach (int k in triangleHits)
            {
                var t = source.Triangles[k];
                if (t.Paint != paintIndex)
                    continue;
                var poly = Clip(t);
                int m = poly.Count;
                if (m < 3)
                    continue;
                float area = PolygonArea(poly);
                if (Mathf.Abs(area) < 1e-7f)
                    continue;
                EnsureScratch(m);
                for (int q = 0; q < m; q++)
                    points[q] = poly[q] - rest;
                for (int q = 0; q < m; q++)
                    order[q] = area > 0 ? q : m - 1 - q;
                if (!Triangulate(m, order, m, false, out int count))
                    continue; // a degenerate sliver; the cell's own face is under it, so nothing shows through
                int faces = count / 2;
                Reserve(m, faces);
                int vb = usedVertices;
                for (int q = 0; q < m; q++)
                {
                    Vector2 p = poly[q];
                    arenaVertices[usedVertices++] = new Vertex
                    {
                        Position = new Vector3(points[q].x, points[q].y, z),
                        Normal = Vector3.back,
                        UV = paint.Mapped
                            ? new Vector2(paint.Ux * p.x + paint.Uy * p.y + paint.U0, paint.Vx * p.x + paint.Vy * p.y + paint.V0)
                            : p,
                    };
                }
                for (int e = 0; e < count; e += 6) // Triangulate emits front (a,c,b) then back; keep the front only
                {
                    arenaIndices[usedIndices++] = triangles[e] + vb - g.V;
                    arenaIndices[usedIndices++] = triangles[e + 1] + vb - g.V;
                    arenaIndices[usedIndices++] = triangles[e + 2] + vb - g.V;
                }
            }
            g.VN = usedVertices - g.V;
            g.FN = usedIndices - g.I;
            g.SN = 0;
            liveVertices += g.VN;
            liveIndices += g.FN;
            return g;
        }

        // Overlay entries in chunk lists are encoded as ~(cell index * 32 + paint).
        (ulong, ulong) KeyOf(BomSession client, int entry)
        {
            if (entry >= 0)
                return (client.Cells[entry].id, cellShape[entry]);
            int d = ~entry;
            return (client.Cells[d >> 5].id, Mix(cellShape[d >> 5], 0x0E5E0000UL + (ulong)(d & 31)));
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

        static ulong Mix(ulong hash, ulong value)
        {
            hash ^= value;
            return hash * 1099511628211UL;
        }

        static ulong Bits(float value) => (uint)BitConverter.SingleToInt32Bits(value);

        static ulong Shape(BomSession client, BomCell cell)
        {
            ulong h = Mix(Mix(Mix(14695981039346656037UL, cell.vertex_count), Bits(cell.rest_x)), Bits(cell.rest_y));
            for (uint j = 0; j < cell.vertex_count; j++)
            {
                var v = client.Vertices[cell.vertex_start + j];
                h = Mix(Mix(h, Bits(v.x)), Bits(v.y));
            }
            return h;
        }

        // ---- G1 look: Darryn's tile materials by scene path; his tile renderers hidden. ----
        readonly Dictionary<string, Material> tileMaterials = new Dictionary<string, Material>();
        readonly Dictionary<ulong, Material> g1Materials = new Dictionary<ulong, Material>();
        int hiddenByPath;

        static string PathOf(Transform t) => t.parent == null ? t.name : PathOf(t.parent) + "/" + t.name;

        void HideTiles()
        {
            hidTiles = true;
            int hidden = 0;
            foreach (
                var behaviour in UnityEngine.Object.FindObjectsByType<MonoBehaviour>(
                    FindObjectsInactive.Include,
                    FindObjectsSortMode.None
                )
            )
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
        // "g1-also:<path>|<path>...". Their material dresses the extrusion and their renderers are hidden.
        Material G1Material(BomSession client, ulong source)
        {
            if (g1Materials.TryGetValue(source, out var known))
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
            g1Materials[source] = found;
            return found;
        }

        // ---- Looks: kind 0 = native colour (stock fallback), 1 = Darryn face + interior side, 2 = Darryn face and side,
        // 3 = G1 tile material. ----
        static Color Rgba(uint rgba) => new Color32((byte)rgba, (byte)(rgba >> 8), (byte)(rgba >> 16), 255);

        static Color Shade(Color c) => new Color(c.r * 0.7f, c.g * 0.7f, c.b * 0.7f, 1);

        int LookFor(int kind, Material material, uint rgba)
        {
            int id = material != null ? material.GetInstanceID() : 0;
            if (kind != 0 && kind != 1)
                rgba = 0;
            var key = (kind, id, rgba);
            if (lookIndex.TryGetValue(key, out int index))
                return index;
            var look = new Look { Face = new MaterialPropertyBlock(), Side = new MaterialPropertyBlock() };
            switch (kind)
            {
                case 0:
                    look.Materials = new[] { fallback, fallback };
                    look.Face.SetColor("_BaseColor", Rgba(rgba));
                    look.Side.SetColor("_BaseColor", Shade(Rgba(rgba)));
                    break;
                case 1:
                    look.Materials = new[] { material, fallback };
                    look.Side.SetColor("_BaseColor", Shade(Rgba(rgba)));
                    break;
                case 2:
                    look.Materials = new[] { material, material };
                    break;
                default:
                    look.Materials = new[] { material, material };
                    look.Side.SetColor(
                        "_BaseColor",
                        Shade(material.HasProperty("_BaseColor") ? material.GetColor("_BaseColor") : Color.white)
                    );
                    break;
            }
            looks.Add(look);
            lookIndex.Add(key, looks.Count - 1);
            return looks.Count - 1;
        }

        void AddEntry(long ck, int entry)
        {
            if (!chunkCells.TryGetValue(ck, out var list))
            {
                list = RentList();
                chunkCells.Add(ck, list);
            }
            list.Add(entry);
        }

        List<int> RentList()
        {
            if (listPool.Count == 0)
                return new List<int>();
            var list = listPool.Pop();
            list.Clear();
            return list;
        }

        // Fills `outBodies` with one Transform per native body (pose kind + piece/cell id), as the stock path did.
        public void Apply(
            BomSession client,
            BomVisualRegistry visualRegistry,
            Dictionary<(uint, ulong), Transform> outBodies
        )
        {
            if (!warmedApply && WarmApply)
            {
                // G2b: at the first presentation, run the apply once with every source treated as broken, so the
                // fragment path (looks, chunk renderers, Build, cache) runs at join instead of in the first blast's
                // frame. The real apply below replaces it in the same frame, so nothing is drawn from it.
                warmedApply = warming = true;
                try
                {
                    Apply(client, visualRegistry, outBodies);
                }
                finally
                {
                    warming = false;
                }
            }
            long started = Stopwatch.GetTimestamp();
            Applies++;
            stamp = Applies;
            if (!root.gameObject.activeSelf)
                root.gameObject.SetActive(true);
            if (g1 && !hidTiles)
                HideTiles();
            UseRegistry(visualRegistry);
            UpdateTrust(client);
            BomHitchTrace.Lap("c_trust");
            var s = client.Sample;
            int count = (int)s.cell_count;
            if (cellSource.Length < count)
            {
                cellSource = new Source[Math.Max(count, cellSource.Length * 2)];
                cellShape = new ulong[cellSource.Length];
                cellPaintIndex = new int[cellSource.Length];
            }
            pieceArea.Clear();
            foreach (var w in work.Values)
                workPool.Push(w);
            work.Clear();
            bool bound = client.Catalog.binding_count == s.cell_count;
            for (int i = 0; i < count; i++)
            {
                var cell = client.Cells[i];
                if (cell.vertex_count < 3 || cell.vertex_start + cell.vertex_count > s.vertex_count)
                    throw new InvalidOperationException("Cell outline out of bounds");
                Source source = null;
                if (bound)
                {
                    var binding = client.CellBindings[i];
                    if (binding.cell_id != cell.id)
                        throw new InvalidOperationException("Native source binding order differs from cell array");
                    source = SourceFor(client, binding.source_identity);
                }
                cellSource[i] = source;
                cellShape[i] = Shape(client, cell);
                if (source != null)
                {
                    if (source.Count++ == 0)
                        source.Piece = cell.piece_id;
                    if (
                        cell.pose_kind != 0
                        || cell.piece_id != source.Piece
                        || source.Initial == null
                        || !source.Initial.Contains(cell.id)
                    )
                        source.Uniform = false;
                }
                if (band)
                {
                    pieceArea.TryGetValue(cell.piece_id, out float sum);
                    pieceArea[cell.piece_id] = sum + Area(client, cell);
                }
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
            BomHitchTrace.Lap("c_group");
            // Which sources still show Darryn's own mesh (the old "intact" rule: trusted manifest, exactly the
            // registry's initial cells, one static piece).
            IntactSources = FragmentSources = FallbackSources = HiddenSources = 0;
            sourceDrop.Clear();
            foreach (var pair in sources)
            {
                var source = pair.Value;
                if (source.Stamp != stamp)
                {
                    DetachArt(source);
                    if (source.Native == null || !client.Sources.ContainsKey(pair.Key))
                        sourceDrop.Add(pair.Key);
                    continue;
                }
                if (source.Entry == null)
                {
                    FallbackSources++;
                    continue;
                }
                if (source.Entry.Hidden)
                {
                    HiddenSources++;
                    continue;
                }
                if (
                    !bandLook
                    && trusted
                    && source.Uniform
                    && source.Initial != null
                    && source.Count == source.Initial.Count
                )
                {
                    if (!source.ArtBuilt)
                        BuildArt(source);
                    source.Intact = source.ArtValid;
                }
                if (warming)
                    source.Intact = false;
                if (source.Intact)
                    IntactSources++;
                else
                {
                    FragmentSources++;
                    DetachArt(source);
                }
            }
            foreach (ulong id in sourceDrop)
            {
                DestroyArt(sources[id]);
                sources.Remove(id);
            }
            BomHitchTrace.Lap("c_sources");
            foreach (var body in bodies.Values)
                body.Seen = false;
            int rebuilt = 0,
                newCells = 0,
                chunks = 0;
            foreach (var pair in work)
            {
                var w = pair.Value;
                if (!bodies.TryGetValue(pair.Key, out var body))
                {
                    BomHitchTrace.NewBodies++;
                    body = new Body();
                    body.Transform = bodyPool.Count > 0 ? bodyPool.Pop() : new GameObject("Native body").transform;
                    body.Transform.SetParent(root, false);
                    body.Transform.gameObject.SetActive(true);
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
                float pieceDepth = band ? BomDepthLook.PieceDepth(pieceArea[w.Piece]) : 0;
                // Group the body's cells into chunks: by look, and spatially for large bodies so a blast only
                // rebuilds the chunks it touched. Intact and hidden sources draw no extrusion.
                foreach (var list in chunkCells.Values)
                    listPool.Push(list);
                chunkCells.Clear();
                bool spatial = w.Cells.Count > ChunkCells;
                foreach (int i in w.Cells)
                {
                    var source = cellSource[i];
                    if (source != null && (source.Intact || source.Entry != null && source.Entry.Hidden))
                        continue;
                    var cell = client.Cells[i];
                    int look,
                        extra = 0;
                    cellPaintIndex[i] = -1;
                    if (g1)
                    {
                        var tile = G1Material(client, source != null ? source.Id : 0);
                        look = tile != null ? LookFor(3, tile, 0) : LookFor(0, null, cell.color_rgba);
                    }
                    else if (source == null || source.Entry == null)
                        look = LookFor(0, null, cell.color_rgba);
                    else
                    {
                        Split(client, source, i, out int paint, out extra);
                        cellPaintIndex[i] = paint;
                        var material = paint >= 0 ? source.Paints[paint].Material : source.Face;
                        look =
                            source.Initial != null && source.Initial.Contains(cell.id)
                                ? LookFor(2, material, 0)
                                : LookFor(1, material, cell.color_rgba);
                    }
                    // The cell's geometry key: outline, depth, paint and overlay set (computed once per apply, here).
                    Depth(source, pieceDepth, out float lo, out float hi);
                    cellShape[i] = Mix(
                        Mix(Mix(Mix(cellShape[i], Bits(lo)), Bits(hi)), (ulong)(cellPaintIndex[i] + 1)),
                        (ulong)extra
                    );
                    long spatialKey = spatial
                        ? ((long)(Mathf.FloorToInt(cell.rest_x / ChunkSize) & 0xffff) << 16)
                            | ((long)(Mathf.FloorToInt(cell.rest_y / ChunkSize) & 0xffff) << 32)
                        : 0;
                    AddEntry(look | spatialKey, i);
                    for (int p = 0; extra != 0 && p < MaxSplitPaints; p++)
                        if ((extra & (1 << p)) != 0)
                        {
                            bool initialCell = source.Initial != null && source.Initial.Contains(cell.id);
                            int overlay = initialCell
                                ? LookFor(2, source.Paints[p].Material, 0)
                                : LookFor(1, source.Paints[p].Material, cell.color_rgba);
                            AddEntry(overlay | spatialKey, ~(i * 32 + p));
                        }
                }
                foreach (var chunk in body.Chunks.Values)
                    chunk.Seen = false;
                foreach (var cpair in chunkCells)
                {
                    ulong signature = Mix(14695981039346656037UL, (ulong)cpair.Value.Count);
                    foreach (int e in cpair.Value)
                    {
                        var key = KeyOf(client, e);
                        signature = Mix(Mix(signature, key.Item1), key.Item2);
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
                    {
                        foreach (int e in cpair.Value)
                            Touch(KeyOf(client, e));
                        continue;
                    }
                    long bt = BomHitchTrace.On ? Stopwatch.GetTimestamp() : 0;
                    newCells += Build(client, cpair.Value, w.Pivot, pieceDepth, chunk.Mesh);
                    if (BomHitchTrace.On)
                        BomHitchTrace.BuildTicks += Stopwatch.GetTimestamp() - bt;
                    chunk.Signature = signature;
                    if (chunk.Look != look)
                    {
                        chunk.Look = look;
                        var l = looks[look];
                        chunk.Renderer.sharedMaterials = l.Materials;
                        chunk.Renderer.SetPropertyBlock(l.Face, 0);
                        chunk.Renderer.SetPropertyBlock(l.Side, 1);
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
            BomHitchTrace.Lap("c_chunks");
            BomHitchTrace.Note("build", BomHitchTrace.BuildTicks, BomHitchTrace.NewBodies);
            BomHitchTrace.BuildTicks = 0;
            BomHitchTrace.NewBodies = 0;
            bodyDrop.Clear();
            foreach (var pair in bodies)
                if (!pair.Value.Seen)
                    bodyDrop.Add(pair.Key);
            foreach (var key in bodyDrop)
            {
                // An intact source's art may hang under a body that is going away.
                foreach (var source in sources.Values)
                    if (source.ArtBody == bodies[key].Transform)
                        DetachArt(source);
                Release(bodies[key]);
                bodies.Remove(key);
            }
            outBodies.Clear();
            foreach (var pair in bodies)
                outBodies.Add(pair.Key, pair.Value.Transform);
            // Intact sources: Darryn's mesh hangs under its piece's body at rest, as AttachRestGeometry did.
            foreach (var source in sources.Values)
            {
                if (!source.Intact || source.Stamp != stamp)
                    continue;
                if (!bodies.TryGetValue((0u, source.Piece), out var body))
                {
                    DetachArt(source);
                    continue;
                }
                if (source.ArtBody != body.Transform || source.ArtPivot != body.Pivot || !source.Art.activeSelf)
                {
                    BomSourcePresentation.AttachRestGeometry(source.Art.transform, body.Transform, body.Pivot);
                    source.ArtBody = body.Transform;
                    source.ArtPivot = body.Pivot;
                    source.Art.SetActive(true);
                }
            }
            BomHitchTrace.Lap("c_art");
            DropUnseenGeometry();
            BomHitchTrace.Lap("c_drop");
            LastRebuiltChunks = rebuilt;
            LastNewCells = newCells;
            LastChunks = chunks;
            LastMilliseconds = (Stopwatch.GetTimestamp() - started) * 1000.0 / Stopwatch.Frequency;
            if (Applies <= 2 || LastMilliseconds > 4 || Log)
                Debug.Log(
                    (g1 ? "BOM G1 APPLY revision=" : "BOM CELLS APPLY revision=")
                        + s.revision
                        + " epoch="
                        + s.epoch
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
                        + " intact="
                        + IntactSources
                        + " fragments="
                        + FragmentSources
                        + " fallback="
                        + FallbackSources
                        + " hidden="
                        + HiddenSources
                        + (g1 ? " tile_materials=" + g1Materials.Count + " hidden_by_path=" + hiddenByPath : "")
                        + (bandLook ? " back_walls=" + BackWalls + " split_cells=" + cellSplit.Count : "")
                        + " ms="
                        + LastMilliseconds.ToString("0.00", CultureInfo.InvariantCulture)
                );
        }

        // G2b: on by default; --bom-no-warm-apply turns it off for A/B timing.
        static readonly bool WarmApply = Array.IndexOf(Environment.GetCommandLineArgs(), "--bom-no-warm-apply") < 0;
        bool warmedApply,
            warming;

        // Per-apply log only when asked (--bom-cell-log); otherwise the first two applies and any slow one.
        static readonly bool Log = Array.IndexOf(Environment.GetCommandLineArgs(), "--bom-cell-log") >= 0;

        // pieceDepth is already BomDepthLook.PieceDepth (quantised); the band is centred on the player plane.
        void Depth(Source source, float pieceDepth, out float lo, out float hi)
        {
            if (band)
            {
                lo = -pieceDepth / 2;
                hi = pieceDepth / 2;
            }
            else if (source != null)
            {
                lo = source.Lo;
                hi = source.Hi;
            }
            else
            {
                lo = -.3f;
                hi = .3f;
            }
        }

        void Touch((ulong, ulong) key)
        {
            if (geometry.TryGetValue(key, out var g) && g.Stamp != stamp)
            {
                g.Stamp = stamp;
                geometry[key] = g;
            }
        }

        void DropUnseenGeometry()
        {
            geometryKeys.Clear();
            foreach (var pair in geometry)
                if (pair.Value.Stamp != stamp)
                    geometryKeys.Add(pair.Key);
            foreach (var key in geometryKeys)
            {
                var g = geometry[key];
                liveVertices -= g.VN;
                liveIndices -= g.FN + g.SN;
                geometry.Remove(key);
            }
            if (usedVertices > 65536 && usedVertices > 2 * liveVertices)
                Compact();
            if (cellPaint.Count > 2 * geometry.Count + 4096)
                cellPaint.Clear(); // recomputed lazily from the shape-checked cache
            if (cellSplit.Count > 2 * geometry.Count + 4096)
                cellSplit.Clear();
        }

        void Compact()
        {
            var vertices = new NativeArray<Vertex>(
                Math.Max(4096, liveVertices * 2),
                Allocator.Persistent,
                NativeArrayOptions.UninitializedMemory
            );
            var indices = new NativeArray<int>(
                Math.Max(8192, liveIndices * 2),
                Allocator.Persistent,
                NativeArrayOptions.UninitializedMemory
            );
            int v = 0,
                i = 0;
            geometryKeys.Clear();
            foreach (var key in geometry.Keys)
                geometryKeys.Add(key);
            foreach (var key in geometryKeys)
            {
                var g = geometry[key];
                NativeArray<Vertex>.Copy(arenaVertices, g.V, vertices, v, g.VN);
                NativeArray<int>.Copy(arenaIndices, g.I, indices, i, g.FN + g.SN);
                g.V = v;
                g.I = i;
                v += g.VN;
                i += g.FN + g.SN;
                geometry[key] = g;
            }
            arenaVertices.Dispose();
            arenaIndices.Dispose();
            arenaVertices = vertices;
            arenaIndices = indices;
            usedVertices = v;
            usedIndices = i;
        }

        void Reserve(int moreVertices, int moreIndices)
        {
            if (!arenaVertices.IsCreated || usedVertices + moreVertices > arenaVertices.Length)
            {
                var next = new NativeArray<Vertex>(
                    Math.Max(Math.Max(4096, usedVertices + moreVertices), arenaVertices.IsCreated ? arenaVertices.Length * 2 : 0),
                    Allocator.Persistent,
                    NativeArrayOptions.UninitializedMemory
                );
                if (arenaVertices.IsCreated)
                {
                    NativeArray<Vertex>.Copy(arenaVertices, next, usedVertices);
                    arenaVertices.Dispose();
                }
                arenaVertices = next;
            }
            if (!arenaIndices.IsCreated || usedIndices + moreIndices > arenaIndices.Length)
            {
                var next = new NativeArray<int>(
                    Math.Max(Math.Max(8192, usedIndices + moreIndices), arenaIndices.IsCreated ? arenaIndices.Length * 2 : 0),
                    Allocator.Persistent,
                    NativeArrayOptions.UninitializedMemory
                );
                if (arenaIndices.IsCreated)
                {
                    NativeArray<int>.Copy(arenaIndices, next, usedIndices);
                    arenaIndices.Dispose();
                }
                arenaIndices = next;
            }
        }

        static float Cross(Vector2 a, Vector2 b, Vector2 c) =>
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);

        // BomExtrusion's ear clipping, ported to reused scratch arrays (same order, tolerances and fallback).
        bool Triangulate(int n, int[] source, int m, bool strict, out int count)
        {
            Array.Copy(source, remaining, m);
            int r = m;
            count = 0;
            int budget = n * n;
            float edge = strict ? 1e-8f : -1e-8f;
            while (r > 2)
            {
                bool cut = false;
                for (int j = 0; j < r; j++)
                {
                    int a = remaining[(j + r - 1) % r],
                        b = remaining[j],
                        c = remaining[(j + 1) % r];
                    if (Cross(points[a], points[b], points[c]) <= 1e-8f)
                        continue;
                    bool inside = false;
                    for (int q = 0; q < r; q++)
                    {
                        int p = remaining[q];
                        if (p == a || p == b || p == c)
                            continue;
                        float ab = Cross(points[a], points[b], points[p]),
                            bc = Cross(points[b], points[c], points[p]),
                            ca = Cross(points[c], points[a], points[p]);
                        bool within = strict
                            ? ab > edge && bc > edge && ca > edge
                            : ab >= edge && bc >= edge && ca >= edge;
                        if (within)
                        {
                            inside = true;
                            break;
                        }
                    }
                    if (inside)
                        continue;
                    triangles[count++] = a;
                    triangles[count++] = c;
                    triangles[count++] = b; // Front faces -Z camera.
                    triangles[count++] = a + n;
                    triangles[count++] = b + n;
                    triangles[count++] = c + n;
                    Array.Copy(remaining, j + 1, remaining, j, r - j - 1);
                    r--;
                    cut = true;
                    break;
                }
                if (!cut || --budget < 0)
                    return false;
            }
            return true;
        }

        // Extrudes one cell into the arena exactly as BomExtrusion.BuildData lays it out (front/back caps, then four
        // vertices per side edge), relative to the cell's rest point, UVs in rest space.
        Geometry Extrude(BomSession client, BomCell cell, float lo, float hi, Paint paint)
        {
            int n = (int)cell.vertex_count;
            EnsureScratch(n);
            for (int i = 0; i < n; i++)
            {
                var v = client.Vertices[cell.vertex_start + (uint)i];
                points[i] = new Vector2(v.x - cell.rest_x, v.y - cell.rest_y);
            }
            return ExtrudePoints(n, new Vector2(cell.rest_x, cell.rest_y), lo, hi, paint);
        }

        void EnsureScratch(int n)
        {
            if (points.Length >= n)
                return;
            int size = Math.Max(n, points.Length * 2);
            points = new Vector2[size];
            order = new int[size];
            remaining = new int[size];
            cleaned = new int[size];
            triangles = new int[size * 6];
        }

        // Extrudes points[0..n) (relative to rest) into the arena.
        Geometry ExtrudePoints(int n, Vector2 rest, float lo, float hi, Paint paint)
        {
            float depth = hi - lo,
                center = (lo + hi) / 2;
            if (float.IsNaN(depth) || float.IsInfinity(depth) || depth <= 0)
                throw new ArgumentException("Depth must be finite and positive");
            float area = 0;
            for (int i = 0; i < n; i++)
            {
                Vector2 a = points[i],
                    b = points[(i + 1) % n];
                area += a.x * b.y - b.x * a.y;
            }
            if (Mathf.Abs(area) < 1e-8f)
                throw new ArgumentException("Degenerate outline");
            for (int i = 0; i < n; i++)
                order[i] = area > 0 ? i : n - 1 - i;
            if (!Triangulate(n, order, n, false, out int faceCount))
            {
                // Same C6 fallback as BomExtrusion: drop micro-edges and collinear vertices, then a strict test.
                int m = n;
                Array.Copy(order, cleaned, n);
                for (int guard = 0; guard < n && m > 3; guard++)
                {
                    bool removed = false;
                    for (int j = 0; j < m && m > 3; j++)
                    {
                        Vector2 a = points[cleaned[(j + m - 1) % m]],
                            b = points[cleaned[j]],
                            c = points[cleaned[(j + 1) % m]];
                        float scale = Mathf.Max((b - a).magnitude * (c - b).magnitude, 1e-12f);
                        if ((b - a).magnitude < 1e-3f || Mathf.Abs(Cross(a, b, c)) <= 1e-5f * scale)
                        {
                            Array.Copy(cleaned, j + 1, cleaned, j, m - j - 1);
                            m--;
                            removed = true;
                            break;
                        }
                    }
                    if (!removed)
                        break;
                }
                if (!Triangulate(n, cleaned, m, true, out faceCount))
                {
                    var text = new System.Text.StringBuilder();
                    for (int i = 0; i < n; i++)
                        text.Append(' ').Append(points[i].x.ToString("R")).Append(',').Append(points[i].y.ToString("R"));
                    throw new ArgumentException("Outline could not triangulate:" + text);
                }
            }
            int vertexCount = n * 6,
                sideCount = n * 6;
            Reserve(vertexCount, faceCount + sideCount);
            var g = new Geometry
            {
                V = usedVertices,
                VN = vertexCount,
                I = usedIndices,
                FN = faceCount,
                SN = sideCount,
                Stamp = stamp,
            };
            int at = g.V;
            for (int face = 0; face < 2; face++)
            for (int i = 0; i < n; i++)
                arenaVertices[at++] = new Vertex
                {
                    Position = new Vector3(points[i].x, points[i].y, center + (face == 0 ? -depth / 2 : depth / 2)),
                    Normal = face == 0 ? Vector3.back : Vector3.forward,
                    UV = paint != null && paint.Mapped
                        ? new Vector2(
                            paint.Ux * (points[i].x + rest.x) + paint.Uy * (points[i].y + rest.y) + paint.U0,
                            paint.Vx * (points[i].x + rest.x) + paint.Vy * (points[i].y + rest.y) + paint.V0
                        )
                        : points[i] + rest,
                };
            int index = g.I;
            for (int k = 0; k < faceCount; k++)
                arenaIndices[index++] = triangles[k];
            float distance = 0;
            for (int i = 0; i < n; i++)
            {
                int j = (i + 1) % n,
                    start = at - g.V;
                Vector2 a = points[i],
                    b = points[j],
                    e = b - a;
                float length = e.magnitude;
                if (length < 1e-8f)
                    throw new ArgumentException("Degenerate outline edge");
                Vector3 normal = new Vector3(e.y, -e.x, 0).normalized * (area > 0 ? 1 : -1);
                arenaVertices[at++] = new Vertex { Position = new Vector3(a.x, a.y, center - depth / 2), Normal = normal, UV = new Vector2(distance, 0) };
                arenaVertices[at++] = new Vertex { Position = new Vector3(b.x, b.y, center - depth / 2), Normal = normal, UV = new Vector2(distance + length, 0) };
                arenaVertices[at++] = new Vertex { Position = new Vector3(b.x, b.y, center + depth / 2), Normal = normal, UV = new Vector2(distance + length, depth) };
                arenaVertices[at++] = new Vertex { Position = new Vector3(a.x, a.y, center + depth / 2), Normal = normal, UV = new Vector2(distance, depth) };
                distance += length;
                if (area > 0)
                {
                    arenaIndices[index++] = start;
                    arenaIndices[index++] = start + 1;
                    arenaIndices[index++] = start + 2;
                    arenaIndices[index++] = start;
                    arenaIndices[index++] = start + 2;
                    arenaIndices[index++] = start + 3;
                }
                else
                {
                    arenaIndices[index++] = start;
                    arenaIndices[index++] = start + 2;
                    arenaIndices[index++] = start + 1;
                    arenaIndices[index++] = start;
                    arenaIndices[index++] = start + 3;
                    arenaIndices[index++] = start + 2;
                }
            }
            usedVertices += vertexCount;
            usedIndices += faceCount + sideCount;
            liveVertices += vertexCount;
            liveIndices += faceCount + sideCount;
            return g;
        }

        // Assembles one chunk from cached cell geometry straight into a writable MeshData (native memory only).
        int Build(BomSession client, List<int> cells, Vector2 pivot, float pieceDepth, Mesh mesh)
        {
            int created = 0,
                vertexCount = 0,
                faceCount = 0,
                sideCount = 0;
            foreach (int e in cells)
            {
                int i = e >= 0 ? e : ~e >> 5;
                var cell = client.Cells[i];
                var key = KeyOf(client, e);
                if (!geometry.TryGetValue(key, out var g))
                {
                    Depth(cellSource[i], pieceDepth, out float lo, out float hi);
                    var source = cellSource[i];
                    int paint = cellPaintIndex[i];
                    g =
                        e >= 0
                            ? Extrude(client, cell, lo, hi, paint >= 0 && source != null ? source.Paints[paint] : null)
                            : ExtrudeOverlay(client, cell, lo, source, ~e & 31);
                    geometry.Add(key, g);
                    created++;
                }
                else if (g.Stamp != stamp)
                {
                    g.Stamp = stamp;
                    geometry[key] = g;
                }
                vertexCount += g.VN;
                faceCount += g.FN;
                sideCount += g.SN;
                parts.Add((g, new Vector3(cell.rest_x - pivot.x, cell.rest_y - pivot.y, 0)));
            }
            Assemble(vertexCount, faceCount, sideCount, mesh);
            parts.Clear();
            return created;
        }

        readonly List<(Geometry g, Vector3 offset)> parts = new List<(Geometry, Vector3)>();

        void Assemble(int vertexCount, int faceCount, int sideCount, Mesh mesh)
        {
            var data = Mesh.AllocateWritableMeshData(1);
            var target = data[0];
            target.SetVertexBufferParams(vertexCount, Layout);
            target.SetIndexBufferParams(faceCount + sideCount, IndexFormat.UInt32);
            var vertices = target.GetVertexData<Vertex>();
            var indices = target.GetIndexData<int>();
            int v = 0,
                f = 0,
                sd = faceCount;
            Vector3 min = new Vector3(float.MaxValue, float.MaxValue, float.MaxValue),
                max = new Vector3(float.MinValue, float.MinValue, float.MinValue);
            foreach (var (g, offset) in parts)
            {
                for (int k = 0; k < g.VN; k++)
                {
                    var vertex = arenaVertices[g.V + k];
                    vertex.Position += offset;
                    min = Vector3.Min(min, vertex.Position);
                    max = Vector3.Max(max, vertex.Position);
                    vertices[v + k] = vertex;
                }
                for (int k = 0; k < g.FN; k++)
                    indices[f + k] = arenaIndices[g.I + k] + v;
                for (int k = 0; k < g.SN; k++)
                    indices[sd + k] = arenaIndices[g.I + g.FN + k] + v;
                v += g.VN;
                f += g.FN;
                sd += g.SN;
            }
            var bounds = new Bounds((min + max) * 0.5f, max - min);
            target.subMeshCount = 2;
            target.SetSubMesh(
                0,
                new SubMeshDescriptor(0, faceCount) { bounds = bounds, firstVertex = 0, vertexCount = vertexCount },
                UpdateFlags
            );
            target.SetSubMesh(
                1,
                new SubMeshDescriptor(faceCount, sideCount) { bounds = bounds, firstVertex = 0, vertexCount = vertexCount },
                UpdateFlags
            );
            Mesh.ApplyAndDisposeWritableMeshData(data, mesh, UpdateFlags);
            mesh.bounds = bounds;
        }

        Chunk RentChunk(Transform parent)
        {
            var chunk = chunkPool.Count > 0 ? chunkPool.Pop() : NewChunk();
            chunk.Object.transform.SetParent(parent, false);
            chunk.Object.SetActive(true);
            chunk.Signature = 0;
            return chunk;
        }

        Chunk NewChunk()
        {
            var obj = new GameObject("Native cell chunk");
            var chunk = new Chunk
            {
                Object = obj,
                Mesh = new Mesh { name = ChunkMeshName },
                Renderer = obj.AddComponent<MeshRenderer>(),
            };
            chunk.Mesh.MarkDynamic();
            ownedMeshes.Add(chunk.Mesh);
            obj.AddComponent<MeshFilter>().sharedMesh = chunk.Mesh;
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

        // Leaving a session or losing the world hides everything but keeps bodies, chunks and the geometry cache: the
        // next Apply diffs against them, so a rejoin or round start with the same cells rebuilds nothing.
        public void Hide()
        {
            if (root != null)
                root.gameObject.SetActive(false);
        }

        public void Dispose()
        {
            foreach (var source in sources.Values)
                DestroyArt(source);
            sources.Clear();
            foreach (var mesh in ownedMeshes)
                if (mesh != null)
                    UnityEngine.Object.Destroy(mesh);
            ownedMeshes.Clear();
            if (root != null)
                UnityEngine.Object.Destroy(root.gameObject);
            bodies.Clear();
            geometry.Clear();
            chunkPool.Clear();
            bodyPool.Clear();
            if (arenaVertices.IsCreated)
                arenaVertices.Dispose();
            if (arenaIndices.IsCreated)
                arenaIndices.Dispose();
            usedVertices = usedIndices = liveVertices = liveIndices = 0;
        }
    }
}
