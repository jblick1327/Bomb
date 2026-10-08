using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace Bomb.CanonicalDestruction
{
    public static class CanonicalShapeMesh
    {
        public static Mesh Build(IReadOnlyList<CanonicalPolygon2D> cells, float depth, string name)
        {
            var vertices = new List<Vector3>();
            var triangles = new List<int>();
            float front = -depth * 0.5f;
            float back = depth * 0.5f;
            foreach (CanonicalPolygon2D cell in cells)
            {
                int start = vertices.Count;
                foreach (Vector2 point in cell.Vertices) vertices.Add(new Vector3(point.x, point.y, front));
                foreach (Vector2 point in cell.Vertices) vertices.Add(new Vector3(point.x, point.y, back));
                for (int i = 1; i < cell.Vertices.Count - 1; i++)
                {
                    triangles.Add(start); triangles.Add(start + i + 1); triangles.Add(start + i);
                    triangles.Add(start + cell.Vertices.Count); triangles.Add(start + cell.Vertices.Count + i);
                    triangles.Add(start + cell.Vertices.Count + i + 1);
                }
                for (int i = 0; i < cell.Vertices.Count; i++)
                {
                    int next = (i + 1) % cell.Vertices.Count;
                    int side = vertices.Count;
                    Vector2 a = cell.Vertices[i];
                    Vector2 b = cell.Vertices[next];
                    vertices.Add(new Vector3(a.x, a.y, front));
                    vertices.Add(new Vector3(b.x, b.y, front));
                    vertices.Add(new Vector3(b.x, b.y, back));
                    vertices.Add(new Vector3(a.x, a.y, back));
                    triangles.Add(side); triangles.Add(side + 1); triangles.Add(side + 2);
                    triangles.Add(side); triangles.Add(side + 2); triangles.Add(side + 3);
                }
            }

            var mesh = new Mesh { name = name };
            mesh.indexFormat = vertices.Count > 65535 ? IndexFormat.UInt32 : IndexFormat.UInt16;
            mesh.SetVertices(vertices);
            mesh.SetTriangles(triangles, 0);
            mesh.RecalculateNormals();
            mesh.RecalculateBounds();
            return mesh;
        }

    }
}
