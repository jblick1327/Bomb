using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    public sealed class CanonicalConnector
    {
        public CanonicalConnector(MaterialEntityId id, MaterialEntityId a, MaterialEntityId b,
            Vector2 a0, Vector2 a1, Vector2 b0, Vector2 b1, float strengthPerLength,
            float? minimumRemainingFraction = null, float referenceLength = 0)
        { Id = id; A = a; B = b; A0 = a0; A1 = a1; B0 = b0; B1 = b1; StrengthPerLength = strengthPerLength;
            MinimumRemainingFraction = minimumRemainingFraction; ReferenceLength = referenceLength; }
        public MaterialEntityId Id { get; }
        public MaterialEntityId A { get; }
        public MaterialEntityId B { get; }
        public Vector2 A0 { get; }
        public Vector2 A1 { get; }
        public Vector2 B0 { get; }
        public Vector2 B1 { get; }
        public float StrengthPerLength { get; }
        public float? MinimumRemainingFraction { get; }
        public float ReferenceLength { get; }
        public float AttachedLength => Mathf.Min((A1 - A0).magnitude, (B1 - B0).magnitude);
        // Approved fixture convention; the handbook does not prescribe these capacity formulas.
        public float ForceCapacity => StrengthPerLength * AttachedLength;
        public float TorqueCapacity => StrengthPerLength * AttachedLength * AttachedLength * 0.5f;
        public bool FailsAttachment(float remainingLength) => remainingLength <= CanonicalGeometry.ClipTolerance
            || (MinimumRemainingFraction.HasValue && remainingLength + CanonicalGeometry.ClipTolerance < ReferenceLength * MinimumRemainingFraction.Value);
        public bool FailsLoad(Vector2 force, float torque) => force.magnitude > ForceCapacity || Mathf.Abs(torque) > TorqueCapacity;
    }
    public sealed class CanonicalHold
    {
        public CanonicalHold(MaterialEntityId id, MaterialEntityId character, LimbSlot slot, MaterialEntityId target, Vector2 heldLocal)
        { Id = id; Character = character; Slot = slot; Target = target; HeldLocal = heldLocal; }
        public MaterialEntityId Id { get; }
        public MaterialEntityId Character { get; }
        public LimbSlot Slot { get; }
        public MaterialEntityId Target { get; }
        public Vector2 HeldLocal { get; }
    }
    public sealed class CanonicalParticipant
    {
        public CanonicalParticipant(MaterialEntityId id, MaterialEntityId controlledBody = default)
        { Id = id; ControlledBody = controlledBody; }
        public MaterialEntityId Id { get; }
        public MaterialEntityId ControlledBody { get; }
    }
    public sealed class CanonicalWorldView
    {
        public CanonicalWorldView(IEnumerable<CanonicalMaterialState> bodies,
            IEnumerable<CanonicalConnector> connectors = null, IEnumerable<CanonicalHold> holds = null,
            IEnumerable<CanonicalParticipant> participants = null)
        {
            Bodies = Array.AsReadOnly((bodies ?? Array.Empty<CanonicalMaterialState>()).ToArray());
            Connectors = Array.AsReadOnly((connectors ?? Array.Empty<CanonicalConnector>()).ToArray());
            Holds = Array.AsReadOnly((holds ?? Array.Empty<CanonicalHold>()).ToArray());
            Participants = Array.AsReadOnly((participants ?? Array.Empty<CanonicalParticipant>()).ToArray());
        }
        public IReadOnlyList<CanonicalMaterialState> Bodies { get; }
        public IReadOnlyList<CanonicalConnector> Connectors { get; }
        public IReadOnlyList<CanonicalHold> Holds { get; }
        public IReadOnlyList<CanonicalParticipant> Participants { get; }
        public IEnumerable<MaterialEntityId> AllIds => Bodies.Select(b => b.Id).Concat(Connectors.Select(c => c.Id))
            .Concat(Holds.Select(h => h.Id)).Concat(Participants.Select(p => p.Id));
        public CanonicalMaterialState Body(MaterialEntityId id) => Bodies.FirstOrDefault(b => b.Id == id);
        public bool TryValidate(DefinitionSet definitions, out string error)
        {
            error = "Invalid canonical graph.";
            if (Bodies.Any(b => b == null) || Connectors.Any(c => c == null) || Holds.Any(h => h == null) || Participants.Any(p => p == null)) return false;
            if (AllIds.Any(id => !id.IsValid) || AllIds.Distinct().Count() != AllIds.Count()) { error = "Persistent IDs must be unique across the match."; return false; }
            foreach (var b in Bodies)
                if (!b.TryValidate(out error) || (b.Selection != null && !b.Selection.TryValidate(definitions, b.BodyMode, out error))) return false;
            foreach (var c in Connectors)
            {
                var a = Body(c.A); var b = Body(c.B);
                if (a == null || b == null || c.A == c.B || a.IsCharacter || b.IsCharacter || a.IsBomb || b.IsBomb
                    || !DefinitionSpec.Positive(c.StrengthPerLength) || !DefinitionSpec.Finite(c.A0) || !DefinitionSpec.Finite(c.A1)
                    || !DefinitionSpec.Finite(c.B0) || !DefinitionSpec.Finite(c.B1) || !DefinitionSpec.Positive(c.AttachedLength)
                    || Mathf.Abs((c.A1 - c.A0).magnitude - (c.B1 - c.B0).magnitude) > CanonicalGeometry.ConnectivityTolerance
                    || !FullSegment(a.Shape, c.A0, c.A1) || !FullSegment(b.Shape, c.B0, c.B1)
                    || (c.MinimumRemainingFraction.HasValue && (!DefinitionSpec.Nonnegative(c.MinimumRemainingFraction.Value)
                        || c.MinimumRemainingFraction.Value > 1 || !DefinitionSpec.Positive(c.ReferenceLength)
                        || c.ReferenceLength + CanonicalGeometry.ConnectivityTolerance < c.AttachedLength || c.FailsAttachment(c.AttachedLength))))
                { error = "Invalid connector endpoints, attachment, strength, or percentage reference: " + c.Id; return false; }
            }
            var slots = new HashSet<(MaterialEntityId, LimbSlot)>();
            foreach (var h in Holds)
            {
                var actor = Body(h.Character); var target = Body(h.Target);
                if (actor == null || !actor.IsCharacter || target == null || h.Character == h.Target || !DefinitionSpec.Finite(h.HeldLocal)
                    || !Enum.IsDefined(typeof(LimbSlot), h.Slot) || !slots.Add((h.Character, h.Slot))
                    || !CanonicalGeometry.Contains(target.Shape, h.HeldLocal))
                { error = "Invalid or ambiguous limb attachment: " + h.Id; return false; }
                // Existing holds survive eligibility changes (including death); eligibility is checked for new requests.
            }
            var controls = new HashSet<MaterialEntityId>();
            foreach (var p in Participants)
                if (p.ControlledBody.IsValid && (Body(p.ControlledBody) == null || !Body(p.ControlledBody).IsCharacter || !controls.Add(p.ControlledBody)))
                { error = "Invalid or duplicate participant control assignment."; return false; }
            error = null;
            return true;
        }
        private static bool FullSegment(CanonicalMaterialShape shape, Vector2 a, Vector2 b)
        { var ranges = CanonicalGeometry.ClipSegment(shape, a, b); return ranges.Count == 1 && ranges[0].Start <= CanonicalGeometry.ClipTolerance && ranges[0].End >= 1 - CanonicalGeometry.ClipTolerance; }
    }
    // Publish must not fail or perform additional validation: only swap already prepared objects/indexes.
    public interface IPreparedCanonicalProjection : IDisposable { void Publish(); }
    public interface ICanonicalWorldProjection
    {
        bool TryPrepare(CanonicalWorldView view, DefinitionSet definitions, out IPreparedCanonicalProjection prepared, out string error);
    }
}
