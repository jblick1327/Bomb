using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    public enum CanonicalBodyMode
    {
        Static,
        Dynamic
    }

    public sealed class CanonicalPolygon2D
    {
        private const float Epsilon = 0.00001f;
        private readonly Vector2[] vertices;

        public CanonicalPolygon2D(IEnumerable<Vector2> vertices)
        {
            if (vertices == null) throw new ArgumentNullException(nameof(vertices));
            this.vertices = vertices.ToArray();
            if (SignedArea(this.vertices) < 0f) Array.Reverse(this.vertices);
        }

        public IReadOnlyList<Vector2> Vertices => vertices;
        public float Area => Mathf.Abs(SignedArea(vertices));

        public Vector2 Centroid
        {
            get
            {
                float twiceArea = 0f;
                Vector2 weighted = Vector2.zero;
                for (int i = 0; i < vertices.Length; i++)
                {
                    Vector2 a = vertices[i];
                    Vector2 b = vertices[(i + 1) % vertices.Length];
                    float cross = Cross(a, b);
                    twiceArea += cross;
                    weighted += (a + b) * cross;
                }

                if (Mathf.Abs(twiceArea) <= Epsilon)
                    return vertices.Length == 0 ? Vector2.zero : vertices.Aggregate(Vector2.zero, (sum, point) => sum + point) / vertices.Length;
                return weighted / (3f * twiceArea);
            }
        }

        public bool TryValidate(out string error)
        {
            if (vertices.Length < 3)
            {
                error = "A canonical polygon needs at least three vertices.";
                return false;
            }

            for (int i = 0; i < vertices.Length; i++)
            {
                Vector2 point = vertices[i];
                if (!float.IsFinite(point.x) || !float.IsFinite(point.y))
                {
                    error = "Canonical polygon coordinates must be finite.";
                    return false;
                }

                if ((point - vertices[(i + 1) % vertices.Length]).sqrMagnitude <= Epsilon * Epsilon)
                {
                    error = "Canonical polygons cannot contain zero-length edges.";
                    return false;
                }
            }

            if (Area <= Epsilon)
            {
                error = "Canonical polygons must have non-zero area.";
                return false;
            }

            float winding = 0f;
            for (int i = 0; i < vertices.Length; i++)
            {
                Vector2 a = vertices[i];
                Vector2 b = vertices[(i + 1) % vertices.Length];
                Vector2 c = vertices[(i + 2) % vertices.Length];
                float cross = Cross(b - a, c - b);
                if (Mathf.Abs(cross) <= Epsilon) continue;
                if (winding == 0f) winding = Mathf.Sign(cross);
                else if (Mathf.Sign(cross) != winding)
                {
                    error = "Canonical cells must be convex.";
                    return false;
                }
            }

            error = null;
            return true;
        }

        internal Vector2[] CopyVertices() => (Vector2[])vertices.Clone();
        internal static float Cross(Vector2 a, Vector2 b) => a.x * b.y - a.y * b.x;

        private static float SignedArea(IReadOnlyList<Vector2> points)
        {
            if (points == null || points.Count < 3) return 0f;
            float area = 0f;
            for (int i = 0; i < points.Count; i++) area += Cross(points[i], points[(i + 1) % points.Count]);
            return area * 0.5f;
        }
    }

    public sealed class CanonicalMaterialShape
    {
        private readonly CanonicalPolygon2D[] cells;

        public CanonicalMaterialShape(IEnumerable<CanonicalPolygon2D> cells)
        {
            if (cells == null) throw new ArgumentNullException(nameof(cells));
            this.cells = cells.ToArray();
        }

        public IReadOnlyList<CanonicalPolygon2D> Cells => cells;
        public float Area => cells.Sum(cell => cell.Area);

        public Vector2 Centroid
        {
            get
            {
                float totalArea = Area;
                if (totalArea <= 0f) return Vector2.zero;
                Vector2 weighted = Vector2.zero;
                foreach (CanonicalPolygon2D cell in cells) weighted += cell.Centroid * cell.Area;
                return weighted / totalArea;
            }
        }

        public bool TryValidate(out string error)
        {
            if (cells.Length == 0)
            {
                error = "A live material entity needs at least one canonical cell.";
                return false;
            }

            foreach (CanonicalPolygon2D cell in cells)
            {
                if (cell == null)
                {
                    error = "Canonical material shapes cannot contain null cells.";
                    return false;
                }
                if (!cell.TryValidate(out error)) return false;
            }

            if (!PolygonConnectivity.IsConnected(cells))
            {
                error = "One material entity cannot contain disconnected canonical cells.";
                return false;
            }

            error = null;
            return true;
        }
    }

    public sealed class CanonicalMaterialState
    {
        public CanonicalMaterialState(
            MaterialEntityId id,
            CanonicalMaterialShape shape,
            uint geometryRevision,
            Vector2 position,
            float rotationRadians,
            Vector2 linearVelocity,
            float angularVelocityRadians,
            CanonicalBodyMode bodyMode,
            float depth,
            float massPerArea)
        {
            Id = id;
            Shape = shape;
            GeometryRevision = geometryRevision;
            Position = position;
            RotationRadians = rotationRadians;
            LinearVelocity = linearVelocity;
            AngularVelocityRadians = angularVelocityRadians;
            BodyMode = bodyMode;
            Depth = depth;
            MassPerArea = massPerArea;
        }

        public MaterialEntityId Id { get; }
        public CanonicalMaterialShape Shape { get; }
        public uint GeometryRevision { get; }
        public Vector2 Position { get; }
        public float RotationRadians { get; }
        public Vector2 LinearVelocity { get; }
        public float AngularVelocityRadians { get; }
        public CanonicalBodyMode BodyMode { get; }
        public float Depth { get; }
        public float MassPerArea { get; }

        public CanonicalMaterialState WithGeometry(
            MaterialEntityId id,
            CanonicalMaterialShape shape,
            uint revision,
            Vector2 linearVelocity,
            float angularVelocityRadians,
            CanonicalBodyMode bodyMode)
        {
            return new CanonicalMaterialState(id, shape, revision, Position, RotationRadians,
                linearVelocity, angularVelocityRadians, bodyMode, Depth, MassPerArea);
        }

        public CanonicalMaterialState WithMotion(Vector2 position, float rotationRadians, Vector2 velocity, float angularVelocityRadians)
        {
            return new CanonicalMaterialState(Id, Shape, GeometryRevision, position, rotationRadians,
                velocity, angularVelocityRadians, BodyMode, Depth, MassPerArea);
        }

        public bool TryValidate(out string error)
        {
            if (!Id.IsValid)
            {
                error = "Material entity IDs cannot be empty.";
                return false;
            }
            if (GeometryRevision == 0)
            {
                error = "Geometry revision zero is reserved as invalid.";
                return false;
            }
            if (Shape == null)
            {
                error = "Canonical material geometry is missing.";
                return false;
            }
            if (!Shape.TryValidate(out error)) return false;
            if (!IsFinite(Position) || !IsFinite(LinearVelocity)
                || !float.IsFinite(RotationRadians) || !float.IsFinite(AngularVelocityRadians))
            {
                error = "Canonical pose and velocity must be finite.";
                return false;
            }
            if (!float.IsFinite(Depth) || Depth <= 0f || !float.IsFinite(MassPerArea) || MassPerArea <= 0f)
            {
                error = "Canonical depth and mass density must be positive and finite.";
                return false;
            }

            error = null;
            return true;
        }

        private static bool IsFinite(Vector2 value) => float.IsFinite(value.x) && float.IsFinite(value.y);
    }

    public interface IGeometryRevisionPolicy
    {
        uint InitialRevision { get; }
        uint NextRevision(uint current);
    }

    public sealed class DefaultGeometryRevisionPolicy : IGeometryRevisionPolicy
    {
        public DefaultGeometryRevisionPolicy(uint initialRevision = 1)
        {
            if (initialRevision == 0) throw new ArgumentOutOfRangeException(nameof(initialRevision));
            InitialRevision = initialRevision;
        }

        public uint InitialRevision { get; }

        public uint NextRevision(uint current)
        {
            if (current == uint.MaxValue) throw new InvalidOperationException("Geometry revision overflow.");
            return current + 1;
        }
    }
}
