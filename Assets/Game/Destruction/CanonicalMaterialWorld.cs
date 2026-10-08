using System;
using System.Collections.Generic;
using System.Linq;

namespace Bomb.CanonicalDestruction
{
    public sealed class MaterialEntityIdReservation
    {
        internal MaterialEntityIdReservation(long token, IReadOnlyList<MaterialEntityId> ids)
        {
            Token = token;
            Ids = ids;
        }

        internal long Token { get; }
        public IReadOnlyList<MaterialEntityId> Ids { get; }
    }

    public interface IMaterialEntityIdAllocator
    {
        string Prefix { get; }
        ulong NextSequence { get; }
        bool TryReserve(int count, out MaterialEntityIdReservation reservation, out string error);
        bool TryCommit(MaterialEntityIdReservation reservation, out string error);
        void Cancel(MaterialEntityIdReservation reservation);
    }

    public sealed class SequentialMaterialEntityIdAllocator : IMaterialEntityIdAllocator
    {
        private ulong nextSequence;
        private long nextToken = 1;
        private MaterialEntityIdReservation activeReservation;

        public SequentialMaterialEntityIdAllocator(string prefix = "material-", ulong nextSequence = 1)
        {
            if (string.IsNullOrWhiteSpace(prefix)) throw new ArgumentException("ID prefix cannot be empty.", nameof(prefix));
            if (nextSequence == 0) throw new ArgumentOutOfRangeException(nameof(nextSequence));
            Prefix = prefix;
            this.nextSequence = nextSequence;
        }

        public string Prefix { get; }
        public ulong NextSequence => nextSequence;

        public bool TryReserve(int count, out MaterialEntityIdReservation reservation, out string error)
        {
            reservation = null;
            if (count <= 0)
            {
                error = "An ID reservation must contain at least one ID.";
                return false;
            }
            if (activeReservation != null)
            {
                error = "Only one structural ID reservation may be active at a time.";
                return false;
            }
            if (nextSequence > ulong.MaxValue - (ulong)count)
            {
                error = "Material entity ID sequence exhausted.";
                return false;
            }

            var ids = new MaterialEntityId[count];
            for (int i = 0; i < count; i++)
                ids[i] = new MaterialEntityId(Prefix + (nextSequence + (ulong)i).ToString("X16"));
            activeReservation = new MaterialEntityIdReservation(nextToken++, ids);
            reservation = activeReservation;
            error = null;
            return true;
        }

        public bool TryCommit(MaterialEntityIdReservation reservation, out string error)
        {
            if (reservation == null || !ReferenceEquals(reservation, activeReservation))
            {
                error = "The mutation plan does not own the active ID reservation.";
                return false;
            }

            nextSequence += (ulong)reservation.Ids.Count;
            activeReservation = null;
            error = null;
            return true;
        }

        public void Cancel(MaterialEntityIdReservation reservation)
        {
            if (reservation != null && ReferenceEquals(reservation, activeReservation))
                activeReservation = null;
        }
    }

    public sealed class StructuralMutationPlan
    {
        public StructuralMutationPlan(
            MaterialEntityId sourceId,
            uint expectedSourceRevision,
            bool retireSource,
            CanonicalMaterialState updatedSource,
            IEnumerable<CanonicalMaterialState> createdEntities,
            IEnumerable<MaterialEntityId> resultIds,
            MaterialEntityIdReservation idReservation = null)
        {
            SourceId = sourceId;
            ExpectedSourceRevision = expectedSourceRevision;
            RetireSource = retireSource;
            UpdatedSource = updatedSource;
            CreatedEntities = (createdEntities ?? Array.Empty<CanonicalMaterialState>()).ToArray();
            ResultIds = (resultIds ?? Array.Empty<MaterialEntityId>()).ToArray();
            IdReservation = idReservation;
        }

        public StructuralMutationPlan(long expectedGeneration, CanonicalWorldView completeView,
            MaterialEntityIdReservation reservation = null, MaterialEntityId sourceId = default,
            uint expectedSourceRevision = 0, IEnumerable<MaterialEntityId> resultIds = null)
        {
            ExpectedGeneration = expectedGeneration;
            CompleteView = completeView;
            IdReservation = reservation;
            SourceId = sourceId;
            ExpectedSourceRevision = expectedSourceRevision;
            ResultIds = Array.AsReadOnly((resultIds ?? Array.Empty<MaterialEntityId>()).ToArray());
            RetireSource = sourceId.IsValid && completeView?.Body(sourceId) == null;
            UpdatedSource = sourceId.IsValid && !RetireSource ? completeView?.Body(sourceId) : null;
            CreatedEntities = Array.AsReadOnly((completeView?.Bodies.Where(b => ResultIds.Contains(b.Id) && b.Id != sourceId)
                ?? Array.Empty<CanonicalMaterialState>()).ToArray());
        }

        public MaterialEntityId SourceId { get; }
        public uint ExpectedSourceRevision { get; }
        public bool RetireSource { get; }
        public CanonicalMaterialState UpdatedSource { get; }
        public IReadOnlyList<CanonicalMaterialState> CreatedEntities { get; }
        public IReadOnlyList<MaterialEntityId> ResultIds { get; }
        public long? ExpectedGeneration { get; }
        public CanonicalWorldView CompleteView { get; }
        internal MaterialEntityIdReservation IdReservation { get; }
    }

    public sealed class StructuralCommitResult
    {
        internal StructuralCommitResult(MaterialEntityId sourceId, bool sourceRetired, IReadOnlyList<MaterialEntityId> resultIds)
        {
            SourceId = sourceId;
            SourceRetired = sourceRetired;
            ResultIds = resultIds;
        }

        public MaterialEntityId SourceId { get; }
        public bool SourceRetired { get; }
        public IReadOnlyList<MaterialEntityId> ResultIds { get; }
        public List<Exception> NotificationErrors { get; } = new List<Exception>();
    }

    public sealed class CanonicalMaterialWorld
    {
        private Dictionary<MaterialEntityId, CanonicalMaterialState> entities =
            new Dictionary<MaterialEntityId, CanonicalMaterialState>();
        private CanonicalWorldView view = new CanonicalWorldView(null);
        private readonly HashSet<MaterialEntityId> legacyIssued = new HashSet<MaterialEntityId>();
        private bool committing;

        public CanonicalMaterialWorld(IMaterialEntityIdAllocator idAllocator, DefinitionSet definitions = null)
        {
            IdAllocator = idAllocator ?? throw new ArgumentNullException(nameof(idAllocator));
            Definitions = definitions ?? new DefinitionSet();
        }

        public IMaterialEntityIdAllocator IdAllocator { get; }
        public IReadOnlyCollection<CanonicalMaterialState> Entities => view.Bodies;
        public CanonicalWorldView View => view;
        public DefinitionSet Definitions { get; }
        public long Generation { get; private set; }
        public ICanonicalWorldProjection Projection { get; set; }
        public int Count => entities.Count;
        public event Action<StructuralCommitResult> Committed;

        public bool TryAddInitial(CanonicalMaterialState state, out string error)
        {
            if (state == null)
            {
                error = "Initial canonical material state is missing.";
                return false;
            }
            if (!state.TryValidate(out error)) return false;
            if (state.Selection != null) { error = "Defined match bodies must enter through an allocated complete plan."; return false; }
            if (view.AllIds.Contains(state.Id) || legacyIssued.Contains(state.Id))
            {
                error = "Duplicate canonical material entity ID: " + state.Id;
                return false;
            }
            var staged = new Dictionary<MaterialEntityId, CanonicalMaterialState>(entities)
            {
                [state.Id] = state
            };
            entities = staged;
            view = new CanonicalWorldView(staged.Values, view.Connectors, view.Holds, view.Participants);
            legacyIssued.Add(state.Id);
            Generation++;
            error = null;
            return true;
        }

        public bool TryGet(MaterialEntityId id, out CanonicalMaterialState state) => entities.TryGetValue(id, out state);
        public bool Contains(MaterialEntityId id) => entities.ContainsKey(id);

        public bool TryReserveEntityIds(int count, out MaterialEntityIdReservation reservation, out string error)
            => IdAllocator.TryReserve(count, out reservation, out error);

        public bool TryCommit(StructuralMutationPlan plan, out StructuralCommitResult result, out string error)
        {
            result = null;
            error = null;
            if (committing || plan == null || (plan.ExpectedGeneration.HasValue && plan.ExpectedGeneration != Generation))
            { error = "Missing, reentrant, or stale complete mutation plan."; if (plan != null) IdAllocator.Cancel(plan.IdReservation); return false; }
            CanonicalMaterialState source = null;
            if ((plan.CompleteView == null || plan.SourceId.IsValid) && !TryValidatePlan(plan, out source, out error))
            {
                if (plan != null) IdAllocator.Cancel(plan.IdReservation);
                return false;
            }

            CanonicalWorldView stagedView = plan.CompleteView;
            if (stagedView == null)
            {
                var staged = new Dictionary<MaterialEntityId, CanonicalMaterialState>(entities);
                if (plan.RetireSource) staged.Remove(plan.SourceId);
                if (plan.UpdatedSource != null) staged[plan.SourceId] = plan.UpdatedSource;
                foreach (var created in plan.CreatedEntities) staged.Add(created.Id, created);
                stagedView = new CanonicalWorldView(staged.Values, view.Connectors, view.Holds, view.Participants);
            }
            if (!stagedView.TryValidate(Definitions, out error)) { IdAllocator.Cancel(plan.IdReservation); return false; }
            foreach (var body in stagedView.Bodies)
                if (entities.TryGetValue(body.Id, out var previous) && body.Shape != previous.Shape && body.GeometryRevision <= previous.GeometryRevision)
                { error = "Changed geometry must advance its surviving body's revision."; IdAllocator.Cancel(plan.IdReservation); return false; }
            var added = stagedView.AllIds.Except(view.AllIds).ToArray();
            if ((plan.IdReservation == null ? added.Length != 0 : !added.OrderBy(id => id).SequenceEqual(plan.IdReservation.Ids.OrderBy(id => id)))
                )
            { error = error ?? "New body and relationship IDs must exactly match the active match reservation."; IdAllocator.Cancel(plan.IdReservation); return false; }
            var stagedIndex = stagedView.Bodies.ToDictionary(b => b.Id);
            IPreparedCanonicalProjection prepared = null;
            committing = true;
            try
            {
                if (Projection != null && !Projection.TryPrepare(stagedView, Definitions, out prepared, out error))
                { IdAllocator.Cancel(plan.IdReservation); prepared?.Dispose(); return false; }
                if (plan.IdReservation != null && !IdAllocator.TryCommit(plan.IdReservation, out error))
                { IdAllocator.Cancel(plan.IdReservation); prepared?.Dispose(); return false; }
            }
            catch (Exception exception)
            {
                prepared?.Dispose(); IdAllocator.Cancel(plan.IdReservation);
                error = "Projection preparation failed: " + exception.Message;
                return false;
            }
            finally { committing = false; }
            // Prepared.Publish is a no-fail main-thread switch. Preparation and all validation occur above;
            // an implementation violating that contract is an internal error, never a rejected mutation.
            view = stagedView; entities = stagedIndex; Generation++;
            prepared?.Publish();
            result = new StructuralCommitResult(plan.SourceId, plan.RetireSource, plan.ResultIds.ToArray());
            Action<StructuralCommitResult> callbacks = Committed;
            if (callbacks != null)
            {
                foreach (Action<StructuralCommitResult> callback in callbacks.GetInvocationList())
                {
                    try { callback(result); }
                    catch (Exception exception) { result.NotificationErrors.Add(exception); }
                }
            }

            error = null;
            return true;
        }

        public bool TryUpdateMotion(MaterialEntityId id, UnityEngine.Vector2 position, float rotationRadians,
            UnityEngine.Vector2 velocity, float angularVelocityRadians, out string error)
        {
            if (!entities.TryGetValue(id, out CanonicalMaterialState current))
            {
                error = "Cannot update motion for missing material entity " + id + ".";
                return false;
            }

            CanonicalMaterialState updated = current.WithMotion(position, rotationRadians, velocity, angularVelocityRadians);
            return TryUpdateBodyBatch(new[] { updated }, out error);
        }

        public bool TryUpdateBodyBatch(IEnumerable<CanonicalMaterialState> updates, out string error)
        {
            error = "Invalid motion/lifecycle capture batch.";
            if (committing || updates == null) return false;
            var staged = new Dictionary<MaterialEntityId, CanonicalMaterialState>(entities);
            var unique = new HashSet<MaterialEntityId>();
            foreach (var updated in updates)
            {
                if (updated == null || !unique.Add(updated.Id) || !entities.TryGetValue(updated.Id, out var old)
                    || old.Shape != updated.Shape || old.GeometryRevision != updated.GeometryRevision || old.BodyMode != updated.BodyMode
                    || !Equals(old.Selection, updated.Selection) || old.Depth != updated.Depth || old.MassPerArea != updated.MassPerArea) return false;
                staged[updated.Id] = updated;
            }
            var captured = new CanonicalWorldView(staged.Values, view.Connectors, view.Holds, view.Participants);
            if (!captured.TryValidate(Definitions, out error)) return false;
            entities = staged; view = captured; Generation++; error = null; return true;
        }

        internal bool TryLoadInitial(CanonicalWorldView restored, out string error)
        {
            if (view.AllIds.Any()) { error = "Recovery requires an empty unpublished world."; return false; }
            if (!restored.TryValidate(Definitions, out error)) return false;
            // A match still owns its allocator namespace when only roster/relationship records remain.
            // Body-only legacy snapshots retain their original non-allocated IDs.
            if (restored.Bodies.Any(b => b.Selection != null) || restored.Participants.Count != 0
                || restored.Connectors.Count != 0 || restored.Holds.Count != 0)
                foreach (var id in restored.AllIds)
                {
                    if (!id.Value.StartsWith(IdAllocator.Prefix, StringComparison.Ordinal)
                        || !ulong.TryParse(id.Value.Substring(IdAllocator.Prefix.Length), System.Globalization.NumberStyles.HexNumber,
                            System.Globalization.CultureInfo.InvariantCulture, out var sequence)
                        || sequence == 0 || sequence >= IdAllocator.NextSequence)
                    { error = "Recovery IDs conflict with the match allocator high-water mark."; return false; }
                }
            view = restored; entities = restored.Bodies.ToDictionary(b => b.Id); Generation++; error = null; return true;
        }

        private bool TryValidatePlan(StructuralMutationPlan plan, out CanonicalMaterialState source, out string error)
        {
            source = null;
            if (plan == null)
            {
                error = "Structural mutation plan is missing.";
                return false;
            }
            if (!entities.TryGetValue(plan.SourceId, out source))
            {
                error = "Structural mutation target is missing: " + plan.SourceId;
                return false;
            }
            if (source.GeometryRevision != plan.ExpectedSourceRevision)
            {
                error = "Structural mutation was planned from a stale source state.";
                return false;
            }

            int resultCount = plan.ResultIds.Count;
            if (resultCount == 0)
            {
                if (!plan.RetireSource || plan.UpdatedSource != null || plan.CreatedEntities.Count != 0)
                {
                    error = "A zero-result mutation must only retire its source.";
                    return false;
                }
            }
            else if (resultCount == 1)
            {
                if (plan.RetireSource || plan.UpdatedSource == null || plan.CreatedEntities.Count != 0
                    || plan.ResultIds[0] != plan.SourceId || plan.UpdatedSource.Id != plan.SourceId)
                {
                    error = "A one-result mutation must update and preserve its source ID.";
                    return false;
                }
                if (plan.UpdatedSource.GeometryRevision <= source.GeometryRevision)
                {
                    error = "A geometry update must advance its source revision.";
                    return false;
                }
                if (!plan.UpdatedSource.TryValidate(out error)) return false;
            }
            else
            {
                if (!plan.RetireSource || plan.UpdatedSource != null || plan.CreatedEntities.Count != resultCount)
                {
                    error = "A multi-result mutation must retire its source and create every result.";
                    return false;
                }
                if (plan.IdReservation == null || plan.IdReservation.Ids.Count < resultCount)
                {
                    error = "Every created material ID must come from the world's active allocator reservation.";
                    return false;
                }

                var unique = new HashSet<MaterialEntityId>();
                for (int i = 0; i < resultCount; i++)
                {
                    CanonicalMaterialState created = plan.CreatedEntities[i];
                    MaterialEntityId resultId = plan.ResultIds[i];
                    if (created == null || created.Id != resultId || plan.IdReservation.Ids[i] != resultId
                        || resultId == plan.SourceId || !unique.Add(resultId))
                    {
                        error = "A multi-result plan contains missing, duplicate, inherited, or unreserved IDs.";
                        return false;
                    }
                    if (entities.ContainsKey(resultId))
                    {
                        error = "A created material ID already exists: " + resultId;
                        return false;
                    }
                    if (!created.TryValidate(out error)) return false;
                }
            }

            error = null;
            return true;
        }
    }
}
