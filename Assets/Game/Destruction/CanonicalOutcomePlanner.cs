using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    // Resolves every affected relationship before reserving IDs or exposing a new graph.
    public static class CanonicalOutcomePlanner
    {
        public static bool TryPlan(CanonicalMaterialWorld world,
            IReadOnlyDictionary<MaterialEntityId, IReadOnlyList<CanonicalMaterialState>> replacements,
            IEnumerable<MaterialEntityId> retire, out StructuralMutationPlan plan, out string error,
            MaterialEntityId sourceId = default, IEnumerable<MaterialEntityId> retireConnectors = null)
        {
            plan = null;
            error = null;
            MaterialEntityIdReservation reservation = null;
            try
            {
                var bodies = world.View.Bodies.ToDictionary(b => b.Id);
                var maps = new Dictionary<MaterialEntityId, IReadOnlyList<CanonicalMaterialState>>();
                var provisional = new List<MaterialEntityId>();
                int sequence = 0;
                foreach (var pair in replacements.OrderBy(p => p.Key))
                {
                    if (!bodies.TryGetValue(pair.Key, out var source)) throw new InvalidOperationException("Missing replacement source.");
                    bodies.Remove(pair.Key);
                    var results = new List<CanonicalMaterialState>();
                    foreach (var supplied in pair.Value)
                    {
                        if (supplied == null) throw new InvalidOperationException("Missing geometry result.");
                        if (!supplied.TryValidate(out var invalid)) throw new InvalidOperationException("Invalid geometry result: " + invalid);
                        MaterialEntityId id = pair.Value.Count == 1 ? source.Id : new MaterialEntityId("__planned-body-" + sequence++);
                        if (pair.Value.Count > 1) provisional.Add(id);
                        var result = supplied.WithGeometry(id, supplied.Shape, supplied.GeometryRevision,
                            supplied.LinearVelocity, supplied.AngularVelocityRadians, supplied.BodyMode);
                        bodies.Add(id, result); results.Add(result);
                    }
                    maps.Add(source.Id, results);
                }
                foreach (var id in retire ?? Array.Empty<MaterialEntityId>())
                { bodies.Remove(id); maps[id] = Array.Empty<CanonicalMaterialState>(); }

                IReadOnlyList<CanonicalMaterialState> Endpoints(MaterialEntityId id) => maps.TryGetValue(id, out var mapped) ? mapped
                    : bodies.TryGetValue(id, out var body) ? new[] { body } : Array.Empty<CanonicalMaterialState>();
                var connectors = new List<CanonicalConnector>();
                foreach (var old in world.View.Connectors)
                {
                    if (retireConnectors != null && retireConnectors.Contains(old.Id)) continue;
                    var oldA = world.View.Body(old.A); var oldB = world.View.Body(old.B);
                    var survivors = new List<CanonicalConnector>();
                    foreach (var a in Endpoints(old.A)) foreach (var b in Endpoints(old.B))
                    {
                        Vector2 a0 = a.ToLocal(oldA.ToWorld(old.A0)), a1 = a.ToLocal(oldA.ToWorld(old.A1));
                        Vector2 b0 = b.ToLocal(oldB.ToWorld(old.B0)), b1 = b.ToLocal(oldB.ToWorld(old.B1));
                        var paired = new List<CanonicalGeometry.Interval>();
                        foreach (var ar in CanonicalGeometry.ClipSegment(a.Shape, a0, a1))
                            foreach (var br in CanonicalGeometry.ClipSegment(b.Shape, b0, b1))
                            {
                                float lo = Mathf.Max(ar.Start, br.Start), hi = Mathf.Min(ar.End, br.End);
                                if (hi - lo > CanonicalGeometry.ClipTolerance) paired.Add(new CanonicalGeometry.Interval(lo, hi));
                            }
                        if (paired.Count > 1) throw new InvalidOperationException("Disconnected attachment remnants on one unchanged child pair require additional semantics.");
                        foreach (var span in paired)
                            survivors.Add(new CanonicalConnector(old.Id, a.Id, b.Id, Vector2.Lerp(a0, a1, span.Start), Vector2.Lerp(a0, a1, span.End),
                                Vector2.Lerp(b0, b1, span.Start), Vector2.Lerp(b0, b1, span.End), old.StrengthPerLength,
                                old.MinimumRemainingFraction, old.ReferenceLength));
                    }
                    // Test the OLD lifetime reference against all surviving attachment before any replacement exists.
                    if (old.FailsAttachment(survivors.Sum(c => c.AttachedLength))) continue;
                    if (survivors.Count == 1) connectors.Add(survivors[0]);
                    else foreach (var c in survivors)
                    {
                        var id = new MaterialEntityId("__planned-connector-" + sequence++); provisional.Add(id);
                        connectors.Add(new CanonicalConnector(id, c.A, c.B, c.A0, c.A1, c.B0, c.B1, c.StrengthPerLength,
                            c.MinimumRemainingFraction, c.MinimumRemainingFraction.HasValue ? c.AttachedLength : 0));
                    }
                }
                var holds = new List<CanonicalHold>();
                foreach (var h in world.View.Holds)
                {
                    if (!bodies.TryGetValue(h.Character, out var actor) || !actor.IsCharacter) continue;
                    var oldTarget = world.View.Body(h.Target);
                    var matches = Endpoints(h.Target).Select(t => (body: t, point: t.ToLocal(oldTarget.ToWorld(h.HeldLocal))))
                        .Where(p => CanonicalGeometry.Contains(p.body.Shape, p.point)).ToArray();
                    if (matches.Length > 1) throw new InvalidOperationException("A held material location maps ambiguously to more than one child.");
                    if (matches.Length == 1) holds.Add(new CanonicalHold(h.Id, h.Character, h.Slot, matches[0].body.Id, matches[0].point));
                }
                var participants = world.View.Participants.Select(p => new CanonicalParticipant(p.Id,
                    bodies.TryGetValue(p.ControlledBody, out var controlled) && controlled.IsCharacter ? p.ControlledBody : default)).ToArray();
                if (provisional.Count > 0 && !world.TryReserveEntityIds(provisional.Count, out reservation, out error)) return false;
                var ids = provisional.Select((id, i) => (id, final: reservation.Ids[i])).ToDictionary(p => p.id, p => p.final);
                MaterialEntityId Final(MaterialEntityId id) => ids.TryGetValue(id, out var final) ? final : id;
                var complete = new CanonicalWorldView(bodies.Values.Select(b => b.WithGeometry(Final(b.Id), b.Shape, b.GeometryRevision,
                        b.LinearVelocity, b.AngularVelocityRadians, b.BodyMode)),
                    connectors.Select(c => new CanonicalConnector(Final(c.Id), Final(c.A), Final(c.B), c.A0, c.A1, c.B0, c.B1,
                        c.StrengthPerLength, c.MinimumRemainingFraction, c.ReferenceLength)),
                    holds.Select(h => new CanonicalHold(h.Id, h.Character, h.Slot, Final(h.Target), h.HeldLocal)), participants);
                var resultIds = sourceId.IsValid && maps.TryGetValue(sourceId, out var sourceResults)
                    ? sourceResults.Select(b => Final(b.Id)).ToArray() : Array.Empty<MaterialEntityId>();
                plan = new StructuralMutationPlan(world.Generation, complete, reservation, sourceId,
                    sourceId.IsValid ? world.View.Body(sourceId).GeometryRevision : 0, resultIds);
                return true;
            }
            catch (Exception exception)
            { world.IdAllocator.Cancel(reservation); error = "Complete outcome resolution failed: " + exception.Message; return false; }
        }
    }
}
