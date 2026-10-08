using System;
using System.Globalization;
using System.Linq;
using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    public static class CanonicalMaterialSnapshotCodec
    {
        private const int CurrentSchemaVersion = 2;

        public static string Serialize(CanonicalMaterialWorld world, bool prettyPrint = false)
        {
            if (world == null) throw new ArgumentNullException(nameof(world));
            var snapshot = new SnapshotData
            {
                schemaVersion = CurrentSchemaVersion,
                allocatorPrefix = world.IdAllocator.Prefix,
                nextEntitySequence = world.IdAllocator.NextSequence.ToString(CultureInfo.InvariantCulture),
                definitions = RequiredReferences(world.View, world.Definitions).Select(world.Definitions.Resolve)
                    .OrderBy(d => d.kind).ThenBy(d => d.id, StringComparer.Ordinal).ToArray(),
                connectors = world.View.Connectors.OrderBy(c => c.Id).Select(c => new ConnectorData
                {
                    id = c.Id.Value, a = c.A.Value, b = c.B.Value, a0 = PointData.From(c.A0), a1 = PointData.From(c.A1),
                    b0 = PointData.From(c.B0), b1 = PointData.From(c.B1), strength = c.StrengthPerLength,
                    hasPercentage = c.MinimumRemainingFraction.HasValue, fraction = c.MinimumRemainingFraction ?? 0, referenceLength = c.ReferenceLength
                }).ToArray(),
                holds = world.View.Holds.OrderBy(h => h.Id).Select(h => new HoldData { id = h.Id.Value,
                    character = h.Character.Value, target = h.Target.Value, slot = h.Slot, point = PointData.From(h.HeldLocal) }).ToArray(),
                participants = world.View.Participants.OrderBy(p => p.Id).Select(p => new ParticipantData
                    { id = p.Id.Value, controlledBody = p.ControlledBody.Value }).ToArray(),
                materials = world.Entities
                    .OrderBy(entity => entity.Id)
                    .Select(ToData)
                    .ToArray()
            };
            return JsonUtility.ToJson(snapshot, prettyPrint);
        }

        public static bool TryDeserialize(string json, out CanonicalMaterialWorld world, out string error, DefinitionSet expectedDefinitions = null)
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

            try
            {
                var definitions = new DefinitionSet(snapshot.definitions);
                var bodies = new System.Collections.Generic.List<CanonicalMaterialState>();
                if (snapshot.materials == null || snapshot.connectors == null || snapshot.holds == null || snapshot.participants == null || snapshot.definitions == null)
                { error = "Recovery bundle is missing a required collection."; return false; }
                foreach (var data in snapshot.materials)
                { if (!TryFromData(data, out var state, out error)) return false; bodies.Add(state); }
                var view = new CanonicalWorldView(bodies,
                    snapshot.connectors.Select(c => new CanonicalConnector(new MaterialEntityId(c.id), new MaterialEntityId(c.a), new MaterialEntityId(c.b),
                        c.a0.ToVector2(), c.a1.ToVector2(), c.b0.ToVector2(), c.b1.ToVector2(), c.strength,
                        c.hasPercentage ? (float?)c.fraction : null, c.referenceLength)),
                    snapshot.holds.Select(h => new CanonicalHold(new MaterialEntityId(h.id), new MaterialEntityId(h.character), h.slot,
                        new MaterialEntityId(h.target), h.point.ToVector2())),
                    snapshot.participants.Select(p => new CanonicalParticipant(new MaterialEntityId(p.id), new MaterialEntityId(p.controlledBody))));
                if (expectedDefinitions != null)
                    foreach (var reference in RequiredReferences(view, definitions))
                        if (!expectedDefinitions.TryResolve(reference, reference.kind, out _, out error)) return false;
                var restored = new CanonicalMaterialWorld(new SequentialMaterialEntityIdAllocator(snapshot.allocatorPrefix, next), definitions);
                if (!restored.TryLoadInitial(view, out error)) return false;
                world = restored;
            }
            catch (Exception exception) { error = "Malformed recovery bundle: " + exception.Message; return false; }
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
                hasSelection = state.Selection != null,
                hasCountdown = state.Countdown != null,
                selection = state.Selection == null ? null : new SelectionData { material = state.Selection.Material,
                    response = state.Selection.Response, appearance = state.Selection.Appearance, role = state.Selection.Role },
                countdown = state.Countdown == null ? null : new CountdownData { active = state.Countdown.Active, remaining = state.Countdown.RemainingSeconds },
                cells = state.Shape.Cells.Select(cell => new PolygonData
                {
                    points = cell.Vertices.Select(PointData.From).ToArray()
                }).ToArray()
            };
        }

        private static bool TryFromData(MaterialData data, out CanonicalMaterialState state, out string error)
        {
            state = null;
            if (data == null || !Enum.TryParse(data.bodyMode, true, out CanonicalBodyMode bodyMode)
                || !Enum.IsDefined(typeof(CanonicalBodyMode), bodyMode))
            {
                error = "Canonical snapshot contains an invalid material body mode.";
                return false;
            }
            try
            {
                var shape = new CanonicalMaterialShape((data.cells ?? Array.Empty<PolygonData>())
                    .Select(cell => new CanonicalPolygon2D((cell?.points ?? Array.Empty<PointData>()).Select(point => point.ToVector2()))));
                if ((data.hasSelection && data.selection == null) || (data.hasCountdown && data.countdown == null))
                { error = "Recovery body is missing a declared optional record."; return false; }
                state = !data.hasSelection ? new CanonicalMaterialState(new MaterialEntityId(data.id), shape, data.geometryRevision,
                    data.position.ToVector2(), data.rotationRadians, data.linearVelocity.ToVector2(),
                    data.angularVelocityRadians, bodyMode, data.depth, data.massPerArea)
                    : new CanonicalMaterialState(new MaterialEntityId(data.id), shape, data.geometryRevision,
                        data.position.ToVector2(), data.rotationRadians, data.linearVelocity.ToVector2(), data.angularVelocityRadians, bodyMode,
                        new BodyDefinitionSelection(data.selection.material, data.selection.response, data.selection.appearance, data.selection.role),
                        !data.hasCountdown ? null : new BombCountdown(data.countdown.active, data.countdown.remaining));
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
            public DefinitionSpec[] definitions;
            public ConnectorData[] connectors;
            public HoldData[] holds;
            public ParticipantData[] participants;
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
            public SelectionData selection;
            public CountdownData countdown;
            public bool hasSelection, hasCountdown;
        }

        [Serializable] private sealed class SelectionData { public DefinitionReference material, response, appearance, role; }
        [Serializable] private sealed class CountdownData { public bool active; public float remaining; }
        [Serializable] private sealed class ConnectorData
        { public string id, a, b; public PointData a0, a1, b0, b1; public float strength, fraction, referenceLength; public bool hasPercentage; }
        [Serializable] private sealed class HoldData { public string id, character, target; public LimbSlot slot; public PointData point; }
        [Serializable] private sealed class ParticipantData { public string id, controlledBody; }

        private static DefinitionReference[] RequiredReferences(CanonicalWorldView view, DefinitionSet definitions)
        {
            var references = new System.Collections.Generic.HashSet<DefinitionReference>();
            foreach (var b in view.Bodies.Where(b => b.Selection != null))
            {
                references.Add(b.Selection.Material); references.Add(b.Selection.Response);
                references.Add(b.Selection.Appearance); references.Add(b.Selection.Role);
                if (b.IsCharacter)
                {
                    var character = definitions.Resolve(b.Selection.Role);
                    references.Add(character.corpseRole); references.Add(character.corpseMaterial);
                    references.Add(character.corpseResponse); references.Add(character.corpseAppearance);
                }
            }
            return references.ToArray();
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
