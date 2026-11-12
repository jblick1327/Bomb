using System;
using System.Collections.Generic;
using UnityEngine;

namespace Bom.Unity
{
    public sealed class BomMeshGeometry
    {
        public Vector3[] Vertices,
            Normals;
        public Vector2[] UV;
        public int[] Faces,
            Sides;

        public Mesh Upload(string name)
        {
            var mesh = new Mesh
            {
                name = name,
                indexFormat = UnityEngine.Rendering.IndexFormat.UInt32,
            };
            mesh.vertices = Vertices;
            mesh.normals = Normals;
            mesh.uv = UV;
            mesh.subMeshCount = 2;
            mesh.SetTriangles(Faces, 0, false);
            mesh.SetTriangles(Sides, 1, false);
            mesh.RecalculateBounds();
            mesh.RecalculateTangents();
            return mesh;
        }

        public long Bytes => Vertices.LongLength * 32 + (Faces.LongLength + Sides.LongLength) * 4;
    }

    public static class BomExtrusion
    {
        static float Cross(Vector2 a, Vector2 b, Vector2 c) =>
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);

        // Ear clipping accepts the simple concave outlines supplied by the native core.
        public static Mesh Build(
            Vector2[] points,
            float depth = 0.6f,
            Vector2 uvOrigin = default,
            float depthCenter = 0
        )
        {
            return BuildData(points, depth, uvOrigin, depthCenter).Upload("Native cell extrusion");
        }

        static List<int> Triangulate(Vector2[] points, int n, List<int> order, bool strict)
        {
            var remaining = new List<int>(order);
            var triangles = new List<int>();
            int budget = n * n;
            while (remaining.Count > 2)
            {
                bool cut = false;
                for (int j = 0; j < remaining.Count; j++)
                {
                    int a = remaining[(j + remaining.Count - 1) % remaining.Count],
                        b = remaining[j],
                        c = remaining[(j + 1) % remaining.Count];
                    if (Cross(points[a], points[b], points[c]) <= 1e-8f)
                        continue;
                    bool inside = false;
                    foreach (int p in remaining)
                    {
                        if (p == a || p == b || p == c)
                            continue;
                        // Default: a point on the ear's boundary blocks it. Strict (fallback): only a point inside does.
                        float edge = strict ? 1e-8f : -1e-8f;
                        bool within =
                            Cross(points[a], points[b], points[p]) > edge
                            && Cross(points[b], points[c], points[p]) > edge
                            && Cross(points[c], points[a], points[p]) > edge;
                        if (!strict)
                            within =
                                Cross(points[a], points[b], points[p]) >= edge
                                && Cross(points[b], points[c], points[p]) >= edge
                                && Cross(points[c], points[a], points[p]) >= edge;
                        if (within)
                        {
                            inside = true;
                            break;
                        }
                    }
                    if (inside)
                        continue;
                    triangles.Add(a);
                    triangles.Add(c);
                    triangles.Add(b); // Front faces -Z camera.
                    triangles.Add(a + n);
                    triangles.Add(b + n);
                    triangles.Add(c + n);
                    remaining.RemoveAt(j);
                    cut = true;
                    break;
                }
                if (!cut || --budget < 0)
                    return null;
            }
            return triangles;
        }

        public static BomMeshGeometry BuildData(
            Vector2[] points,
            float depth = 0.6f,
            Vector2 uvOrigin = default,
            float depthCenter = 0
        )
        {
            int n = points.Length;
            if (n < 3)
                throw new ArgumentException("Outline needs three points");
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
            var order = new List<int>();
            for (int i = 0; i < n; i++)
                order.Add(area > 0 ? i : n - 1 - i);
            var triangles = Triangulate(points, n, order, false);
            if (triangles == null)
            {
                // C6: native cells can carry T-junction / near-collinear / micro-edge vertices on a candidate ear's edge, which the
                // tolerant inside test above treats as blocking. Retry without collinear vertices and with a strict
                // interior test; the first pass is unchanged so existing outlines triangulate exactly as before.
                var cleaned = new List<int>(order);
                for (int guard = 0; guard < n && cleaned.Count > 3; guard++)
                {
                    bool removed = false;
                    for (int j = 0; j < cleaned.Count && cleaned.Count > 3; j++)
                    {
                        Vector2 a = points[cleaned[(j + cleaned.Count - 1) % cleaned.Count]],
                            b = points[cleaned[j]],
                            c = points[cleaned[(j + 1) % cleaned.Count]];
                        float scale = Mathf.Max((b - a).magnitude * (c - b).magnitude, 1e-12f);
                        // Also drop micro-edges (< 0.001, native's minimum proxy edge): wood fracture can leave a tiny
                        // doubled-back cluster of vertices at a plank's end.
                        if ((b - a).magnitude < 1e-3f || Mathf.Abs(Cross(a, b, c)) <= 1e-5f * scale)
                        {
                            cleaned.RemoveAt(j);
                            removed = true;
                            break;
                        }
                    }
                    if (!removed)
                        break;
                }
                triangles = Triangulate(points, n, cleaned, true);
            }
            if (triangles == null)
            {
                var text = new System.Text.StringBuilder();
                foreach (var p in points)
                    text.Append(' ').Append(p.x.ToString("R")).Append(',').Append(p.y.ToString("R"));
                throw new ArgumentException("Outline could not triangulate:" + text);
            }
            // Separate cap/side vertices preserve hard normals and continuous side UVs.
            var vertices = new List<Vector3>(n * 6);
            var normals = new List<Vector3>(n * 6);
            var uv = new List<Vector2>(n * 6);
            var sides = new List<int>(n * 6);
            for (int face = 0; face < 2; face++)
            for (int i = 0; i < n; i++)
            {
                vertices.Add(
                    new Vector3(
                        points[i].x,
                        points[i].y,
                        depthCenter + (face == 0 ? -depth / 2 : depth / 2)
                    )
                );
                normals.Add(face == 0 ? Vector3.back : Vector3.forward);
                uv.Add(points[i] + uvOrigin);
            }
            float distance = 0;
            for (int i = 0; i < n; i++)
            {
                int j = (i + 1) % n,
                    start = vertices.Count;
                Vector2 a = points[i],
                    b = points[j],
                    edge = b - a;
                float length = edge.magnitude;
                if (length < 1e-8f)
                    throw new ArgumentException("Degenerate outline edge");
                Vector3 normal = new Vector3(edge.y, -edge.x, 0).normalized * (area > 0 ? 1 : -1);
                vertices.Add(new Vector3(a.x, a.y, depthCenter - depth / 2));
                vertices.Add(new Vector3(b.x, b.y, depthCenter - depth / 2));
                vertices.Add(new Vector3(b.x, b.y, depthCenter + depth / 2));
                vertices.Add(new Vector3(a.x, a.y, depthCenter + depth / 2));
                for (int k = 0; k < 4; k++)
                    normals.Add(normal);
                uv.Add(new Vector2(distance, 0));
                uv.Add(new Vector2(distance + length, 0));
                uv.Add(new Vector2(distance + length, depth));
                uv.Add(new Vector2(distance, depth));
                distance += length;
                if (area > 0)
                {
                    sides.Add(start);
                    sides.Add(start + 1);
                    sides.Add(start + 2);
                    sides.Add(start);
                    sides.Add(start + 2);
                    sides.Add(start + 3);
                }
                else
                {
                    sides.Add(start);
                    sides.Add(start + 2);
                    sides.Add(start + 1);
                    sides.Add(start);
                    sides.Add(start + 3);
                    sides.Add(start + 2);
                }
            }
            return new BomMeshGeometry
            {
                Vertices = vertices.ToArray(),
                Normals = normals.ToArray(),
                UV = uv.ToArray(),
                Faces = triangles.ToArray(),
                Sides = sides.ToArray(),
            };
        }
    }
}
