using System;
using System.Globalization;
using System.Linq;
using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    public static class CanonicalMaterialSnapshotCodec
    {
        private const int CurrentSchemaVersion = 1;

        public static string Serialize(CanonicalMaterialWorld world, bool prettyPrint = false)
        {
            if (world == null) throw new ArgumentNullException(nameof(world));
            var snapshot = new SnapshotData
            {
                schemaVersion = CurrentSchemaVersion,
                allocatorPrefix = world.IdAllocator.Prefix,
                nextEntitySequence = world.IdAllocator.NextSequence.ToString(CultureInfo.InvariantCulture),
                materials = world.Entities
                    .OrderBy(entity => entity.Id)
                    .Select(ToData)
                    .ToArray()
            };
            return JsonUtility.ToJson(snapshot, prettyPrint);
        }

        public static bool TryDeserialize(string json, out CanonicalMaterialWorld world, out string error)
        {
            world = null;
            if (string.IsNullOrWhiteSpace(json))
            {
                error = "Canonical snapshot JSON is empty.";
                return false;
            }

            SnapshotData snapshot;
            try { snapshot = JsonUtility.FromJson<SnapshotData>(json); }
            catch (Exception exception)
            {
                error = "Canonical snapshot JSON is malformed: " + exception.Message;
                return false;
            }
            if (snapshot == null || snapshot.schemaVersion != CurrentSchemaVersion)
            {
                error = "Unsupported canonical snapshot schema version.";
                return false;
            }
            if (string.IsNullOrWhiteSpace(snapshot.allocatorPrefix)
                || !ulong.TryParse(snapshot.nextEntitySequence, NumberStyles.None, CultureInfo.InvariantCulture, out ulong next)
                || next == 0)
            {
                error = "Canonical snapshot allocator state is invalid.";
                return false;
            }

            var restored = new CanonicalMaterialWorld(new SequentialMaterialEntityIdAllocator(snapshot.allocatorPrefix, next));
            foreach (MaterialData data in snapshot.materials ?? Array.Empty<MaterialData>())
            {
                if (!TryFromData(data, out CanonicalMaterialState state, out error)
                    || !restored.TryAddInitial(state, out error))
                    return false;
            }
            world = restored;
            error = null;
            return true;
        }

        private static MaterialData ToData(CanonicalMaterialState state)
        {
            return new MaterialData
            {
                id = state.Id.Value,
                geometryRevision = state.GeometryRevision,
                position = PointData.From(state.Position),
                rotationRadians = state.RotationRadians,
                linearVelocity = PointData.From(state.LinearVelocity),
                angularVelocityRadians = state.AngularVelocityRadians,
                bodyMode = state.BodyMode.ToString(),
                depth = state.Depth,
                massPerArea = state.MassPerArea,
                cells = state.Shape.Cells.Select(cell => new PolygonData
                {
                    points = cell.Vertices.Select(PointData.From).ToArray()
                }).ToArray()
            };
        }

        private static bool TryFromData(MaterialData data, out CanonicalMaterialState state, out string error)
        {
            state = null;
            if (data == null || !Enum.TryParse(data.bodyMode, true, out CanonicalBodyMode bodyMode))
            {
                error = "Canonical snapshot contains an invalid material body mode.";
                return false;
            }
            try
            {
                var shape = new CanonicalMaterialShape((data.cells ?? Array.Empty<PolygonData>())
                    .Select(cell => new CanonicalPolygon2D((cell?.points ?? Array.Empty<PointData>()).Select(point => point.ToVector2()))));
                state = new CanonicalMaterialState(new MaterialEntityId(data.id), shape, data.geometryRevision,
                    data.position.ToVector2(), data.rotationRadians, data.linearVelocity.ToVector2(),
                    data.angularVelocityRadians, bodyMode, data.depth, data.massPerArea);
            }
            catch (Exception exception)
            {
                error = "Canonical snapshot material data is malformed: " + exception.Message;
                return false;
            }
            return state.TryValidate(out error);
        }

        [Serializable]
        private sealed class SnapshotData
        {
            public int schemaVersion;
            public string allocatorPrefix;
            public string nextEntitySequence;
            public MaterialData[] materials;
        }

        [Serializable]
        private sealed class MaterialData
        {
            public string id;
            public uint geometryRevision;
            public PointData position;
            public float rotationRadians;
            public PointData linearVelocity;
            public float angularVelocityRadians;
            public string bodyMode;
            public float depth;
            public float massPerArea;
            public PolygonData[] cells;
        }

        [Serializable]
        private sealed class PolygonData
        {
            public PointData[] points;
        }

        [Serializable]
        private struct PointData
        {
            public float x;
            public float y;

            public static PointData From(Vector2 value) => new PointData { x = value.x, y = value.y };
            public Vector2 ToVector2() => new Vector2(x, y);
        }
    }
}
