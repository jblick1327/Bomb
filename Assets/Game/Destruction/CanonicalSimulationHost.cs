using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    public static class CanonicalBombLifecycle
    {
        public static BombCountdown AfterStep(BombCountdown current, bool landed, float authoredDuration)
            => current.Active ? current.AdvanceMilliseconds(CanonicalWorldRuntime2D.StepMilliseconds)
                : landed ? new BombCountdown(true, authoredDuration) : current;
    }
    public sealed class HoldRequest
    {
        public HoldRequest(MaterialEntityId participant, MaterialEntityId actor, LimbSlot slot, MaterialEntityId target,
            Vector2 targetLocalPoint, uint observedGeometryRevision)
        { Participant = participant; Actor = actor; Slot = slot; Target = target; TargetLocalPoint = targetLocalPoint; ObservedGeometryRevision = observedGeometryRevision; }
        public MaterialEntityId Participant { get; }
        public MaterialEntityId Actor { get; }
        public LimbSlot Slot { get; }
        public MaterialEntityId Target { get; }
        public Vector2 TargetLocalPoint { get; }
        public uint ObservedGeometryRevision { get; }
    }
    public sealed class CanonicalSimulationHost
    {
        private readonly Queue<HoldRequest> pending = new Queue<HoldRequest>();
        public CanonicalSimulationHost(CanonicalMaterialWorld world, CanonicalWorldRuntime2D runtime = null)
        { World = world ?? throw new ArgumentNullException(nameof(world)); Runtime = runtime; }
        public CanonicalMaterialWorld World { get; private set; }
        public CanonicalWorldRuntime2D Runtime { get; }
        public bool LastObservedRevisionMismatch { get; private set; }
        public IReadOnlyList<string> LastCommandErrors { get; private set; } = Array.Empty<string>();
        public IReadOnlyDictionary<MaterialEntityId, ConnectorLoad> LastLoads { get; private set; } = new Dictionary<MaterialEntityId, ConnectorLoad>();
        public Vector2? LastExplosionCenter { get; private set; }
        public StructuralCommitResult LastStructuralCommit { get; private set; }
        public void QueueHold(HoldRequest request) => pending.Enqueue(request);
        public bool TryHold(HoldRequest request, out CanonicalHold hold, out string error)
        {
            hold = null; error = "Invalid hold request.";
            if (request == null || !Enum.IsDefined(typeof(LimbSlot), request.Slot)) return false;
            var participant = World.View.Participants.FirstOrDefault(p => p.Id == request.Participant);
            var actor = World.View.Body(request.Actor); var target = World.View.Body(request.Target);
            if (participant == null || participant.ControlledBody != request.Actor || actor == null || !actor.IsCharacter
                || target == null || target.Selection == null || actor.Id == target.Id) { error = "Actor is not a living controlled body, or target is missing."; return false; }
            LastObservedRevisionMismatch = request.ObservedGeometryRevision != target.GeometryRevision;
            if (!World.Definitions.Resolve(target.Selection.Role).holdEligible) { error = "Target's authored hold eligibility is false."; return false; }
            if (World.View.Holds.Any(h => h.Character == actor.Id && h.Slot == request.Slot)) { error = "Limb slot is occupied."; return false; }
            if (!DefinitionSpec.Finite(request.TargetLocalPoint)
                || !CanonicalGeometry.TrySurfacePoint(target.Shape, request.TargetLocalPoint, CanonicalGeometry.ConnectivityTolerance, out var localPoint))
            { error = "The requested material location is not on the current surface."; return false; }
            var character = World.Definitions.Resolve(actor.Selection.Role);
            Vector2 root = actor.ToWorld(character.Root(request.Slot)), point = target.ToWorld(localPoint);
            if ((point - root).magnitude > character.Reach(request.Slot) + CanonicalGeometry.ConnectivityTolerance)
            { error = "Current body poses place the target outside limb reach."; return false; }
            foreach (var other in World.View.Bodies.Where(b => b.Id != actor.Id))
                if (CanonicalGeometry.ClipSegment(other.Shape, other.ToLocal(root), other.ToLocal(point))
                    .Any(span => span.Start < 1 - CanonicalGeometry.ConnectivityTolerance && span.End > CanonicalGeometry.ConnectivityTolerance))
                { error = "The current world obstructs the limb path."; return false; }
            if (!World.TryReserveEntityIds(1, out var reservation, out error)) return false;
            hold = new CanonicalHold(reservation.Ids[0], actor.Id, request.Slot, target.Id, localPoint);
            var view = new CanonicalWorldView(World.View.Bodies, World.View.Connectors, World.View.Holds.Concat(new[] { hold }), World.View.Participants);
            if (!World.TryCommit(new StructuralMutationPlan(World.Generation, view, reservation), out var commit, out error)) { hold = null; return false; }
            LastStructuralCommit = commit; return true;
        }
        public bool TryRelease(MaterialEntityId participantId, LimbSlot slot, out string error)
        {
            var participant = World.View.Participants.FirstOrDefault(p => p.Id == participantId);
            if (participant == null || !participant.ControlledBody.IsValid) { error = "Participant has no controlled body."; return false; }
            var view = new CanonicalWorldView(World.View.Bodies, World.View.Connectors,
                World.View.Holds.Where(h => h.Character != participant.ControlledBody || h.Slot != slot), World.View.Participants);
            if (!World.TryCommit(new StructuralMutationPlan(World.Generation, view), out var result, out error)) return false;
            LastStructuralCommit = result; return true;
        }
        public bool Tick(out string error)
        {
            error = null;
            if (Runtime == null) { error = "An authoritative runtime is required for physics ticks."; return false; }
            var commandErrors = new List<string>();
            while (pending.Count > 0) if (!TryHold(pending.Dequeue(), out _, out var rejection)) commandErrors.Add(rejection);
            LastCommandErrors = commandErrors.AsReadOnly();
            var landings = Runtime.Step();
            if (!Runtime.TryCaptureMotion(World, out error)) return false;
            var loads = World.View.Connectors.ToDictionary(c => c.Id, c => Runtime.Measure(c));
            LastLoads = loads;
            var failed = World.View.Connectors.Where(c => c.FailsLoad(loads[c.Id].Force, loads[c.Id].Torque)).Select(c => c.Id).ToArray();
            var timers = World.View.Bodies.Where(b => b.IsBomb).Select(b =>
            {
                return b.WithCountdown(CanonicalBombLifecycle.AfterStep(b.Countdown, landings.Contains(b.Id), World.Definitions.Resolve(b.Selection.Role).countdownSeconds));
            }).ToArray();
            if (!World.TryUpdateBodyBatch(timers, out error)) return false;
            var due = timers.Where(b => b.Countdown.Active && b.Countdown.RemainingSeconds <= 0).Select(b => b.Id).ToArray();
            if (due.Length > 0 || failed.Length > 0) return TryResolve(due, failed, null, out error);
            return true;
        }
        public bool TryDeath(MaterialEntityId characterId, out string error)
        {
            if (World.View.Body(characterId)?.IsCharacter != true) { error = "Death target is not a living character."; return false; }
            return TryResolve(Array.Empty<MaterialEntityId>(), Array.Empty<MaterialEntityId>(), new[] { characterId }, out error);
        }
        // Also exposed for deterministic transition tests; gameplay calls this only from an expired canonical countdown.
        public bool TryDetonate(MaterialEntityId bombId, out string error)
        {
            if (World.View.Body(bombId)?.IsBomb != true) { error = "Detonation target is not a live bomb."; return false; }
            return TryResolve(new[] { bombId }, Array.Empty<MaterialEntityId>(), null, out error);
        }
        private bool TryResolve(IReadOnlyList<MaterialEntityId> bombs, IReadOnlyList<MaterialEntityId> failedConnectors,
            IEnumerable<MaterialEntityId> explicitDeaths, out string error)
        {
            var replacements = new Dictionary<MaterialEntityId, IReadOnlyList<CanonicalMaterialState>>();
            var deaths = new HashSet<MaterialEntityId>(explicitDeaths ?? Array.Empty<MaterialEntityId>());
            var blasts = bombs.Select(id => World.View.Body(id)).ToArray();
            var service = new CanonicalDestructionService(World);
            foreach (var source in World.View.Bodies.Where(b => !b.IsBomb))
            {
                if (source.IsCharacter)
                {
                    foreach (var bomb in blasts)
                    {
                        var spec = World.Definitions.Resolve(bomb.Selection.Role);
                        if (spec.blastPower >= 1 && CanonicalGeometry.Distance(source.Shape, source.ToLocal(bomb.Position)) <= spec.blastRadius) deaths.Add(source.Id);
                    }
                    if (deaths.Contains(source.Id))
                    {
                        var character = World.Definitions.Resolve(source.Selection.Role);
                        var selection = new BodyDefinitionSelection(character.corpseMaterial, character.corpseResponse, character.corpseAppearance, character.corpseRole);
                        replacements[source.Id] = new[] { source.WithSelection(selection, World.Definitions.Resolve(selection.Role).bodyMode) };
                    }
                    continue; // A newly installed corpse is not carved by the same blast.
                }
                var pieces = new List<CanonicalMaterialShape> { source.Shape };
                bool changed = false;
                foreach (var bomb in blasts)
                {
                    var spec = World.Definitions.Resolve(bomb.Selection.Role);
                    var cutter = HandbookConformanceFixture.Circle(bomb.Position, spec.blastRadius, 24);
                    var next = new List<CanonicalMaterialShape>();
                    foreach (var piece in pieces)
                    {
                        var temporary = source.WithGeometry(source.Id, piece, source.GeometryRevision, source.LinearVelocity, source.AngularVelocityRadians, source.BodyMode);
                        if (!service.TryEvaluate(temporary, new DestructionRequest(source.Id, cutter, bomb.Position, 0), out var evaluated, out error)) return false;
                        changed |= evaluated.Changed; next.AddRange(evaluated.ConnectedResults);
                    }
                    pieces = next;
                }
                if (changed)
                {
                    var policy = new PreserveMotionAndApplyBlastPolicy();
                    replacements[source.Id] = pieces.Select((shape, i) => policy.BuildResult(source,
                        pieces.Count == 1 ? source.Id : new MaterialEntityId("__blast-child-" + i), shape,
                        pieces.Count == 1 ? new DefaultGeometryRevisionPolicy().NextRevision(source.GeometryRevision) : 1,
                        new DestructionRequest(source.Id, null, Vector2.zero, 0))).ToArray();
                }
            }
            if (!CanonicalOutcomePlanner.TryPlan(World, replacements, bombs, out var plan, out error, retireConnectors: failedConnectors)) return false;
            if (!World.TryCommit(plan, out var commit, out error)) return false;
            LastStructuralCommit = commit;
            if (blasts.Length > 0) LastExplosionCenter = blasts[blasts.Length - 1].Position;
            return true;
        }
        public bool TryCapture(out string json, out string error)
        {
            json = null;
            if (Runtime != null && !Runtime.TryCaptureMotion(World, out error)) return false;
            json = CanonicalMaterialSnapshotCodec.Serialize(World, true); error = null; return true;
        }
        public bool TryRecover(string json, out string error)
        {
            if (!CanonicalMaterialSnapshotCodec.TryDeserialize(json, out var recovered, out error)) return false;
            if (Runtime != null && !Runtime.TryRebuild(recovered, out error)) return false;
            World.Projection = null; World = recovered; return true;
        }
    }
}
