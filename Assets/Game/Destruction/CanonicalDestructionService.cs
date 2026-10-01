using System;
using System.Collections.Generic;
using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    public interface IDestructionResultStatePolicy
    {
        CanonicalMaterialState BuildResult(
            CanonicalMaterialState source,
            MaterialEntityId resultId,
            CanonicalMaterialShape resultShape,
            uint revision,
            DestructionRequest request);
    }

    public sealed class PreserveMotionAndApplyBlastPolicy : IDestructionResultStatePolicy
    {
        public CanonicalMaterialState BuildResult(CanonicalMaterialState source, MaterialEntityId resultId,
            CanonicalMaterialShape resultShape, uint revision, DestructionRequest request)
        {
            Vector2 worldCentroid = Rotate(resultShape.Centroid, source.RotationRadians) + source.Position;
            Vector2 direction = worldCentroid - request.ImpulseOrigin;
            if (direction.sqrMagnitude <= 0.00001f) direction = Vector2.up;
            Vector2 velocity = source.LinearVelocity + direction.normalized * request.ImpulseSpeed;
            return source.WithGeometry(resultId, resultShape, revision, velocity,
                source.AngularVelocityRadians, CanonicalBodyMode.Dynamic);
        }

        private static Vector2 Rotate(Vector2 value, float radians)
        {
            float cosine = Mathf.Cos(radians);
            float sine = Mathf.Sin(radians);
            return new Vector2(value.x * cosine - value.y * sine, value.x * sine + value.y * cosine);
        }
    }

    public sealed class DestructionCommitOutcome
    {
        internal DestructionCommitOutcome(bool changed, StructuralCommitResult commit)
        {
            Changed = changed;
            Commit = commit;
        }

        public bool Changed { get; }
        public StructuralCommitResult Commit { get; }
    }

    public sealed class CanonicalDestructionService
    {
        private readonly CanonicalMaterialWorld world;
        private readonly IDestructionGeometryEvaluator evaluator;
        private readonly IGeometryRevisionPolicy revisionPolicy;
        private readonly IDestructionResultStatePolicy resultStatePolicy;

        public CanonicalDestructionService(CanonicalMaterialWorld world,
            IDestructionGeometryEvaluator evaluator = null,
            IGeometryRevisionPolicy revisionPolicy = null,
            IDestructionResultStatePolicy resultStatePolicy = null)
        {
            this.world = world ?? throw new ArgumentNullException(nameof(world));
            this.evaluator = evaluator ?? new ConvexSubtractionGeometryEvaluator();
            this.revisionPolicy = revisionPolicy ?? new DefaultGeometryRevisionPolicy();
            this.resultStatePolicy = resultStatePolicy ?? new PreserveMotionAndApplyBlastPolicy();
        }

        public bool TryExecute(DestructionRequest request, out DestructionCommitOutcome outcome, out string error)
        {
            outcome = null;
            if (request == null || !world.TryGet(request.TargetId, out CanonicalMaterialState source))
            {
                error = request == null
                    ? "Destruction request is missing."
                    : "Destruction target does not exist: " + request.TargetId;
                return false;
            }

            GeometryEvaluationResult evaluation = evaluator.Evaluate(source, request);
            if (evaluation == null || !evaluation.Succeeded)
            {
                error = evaluation == null ? "The geometry evaluator returned no result." : evaluation.Error;
                return false;
            }
            if (!evaluation.Changed)
            {
                outcome = new DestructionCommitOutcome(false, null);
                error = null;
                return true;
            }

            StructuralMutationPlan plan;
            int count = evaluation.ConnectedResults.Count;
            if (count == 0)
            {
                plan = new StructuralMutationPlan(source.Id, source.GeometryRevision, true, null,
                    Array.Empty<CanonicalMaterialState>(), Array.Empty<MaterialEntityId>());
            }
            else if (count == 1)
            {
                uint revision;
                try { revision = revisionPolicy.NextRevision(source.GeometryRevision); }
                catch (Exception exception)
                {
                    error = "Could not advance the geometry revision: " + exception.Message;
                    return false;
                }
                CanonicalMaterialState updated = resultStatePolicy.BuildResult(source, source.Id,
                    evaluation.ConnectedResults[0], revision, request);
                plan = new StructuralMutationPlan(source.Id, source.GeometryRevision, false, updated,
                    Array.Empty<CanonicalMaterialState>(), new[] { source.Id });
            }
            else
            {
                if (!world.TryReserveEntityIds(count, out MaterialEntityIdReservation reservation, out error))
                    return false;
                var created = new List<CanonicalMaterialState>(count);
                try
                {
                    for (int i = 0; i < count; i++)
                    {
                        created.Add(resultStatePolicy.BuildResult(source, reservation.Ids[i],
                            evaluation.ConnectedResults[i], revisionPolicy.InitialRevision, request));
                    }
                }
                catch (Exception exception)
                {
                    world.IdAllocator.Cancel(reservation);
                    error = "Could not derive result material state: " + exception.Message;
                    return false;
                }
                plan = new StructuralMutationPlan(source.Id, source.GeometryRevision, true, null,
                    created, reservation.Ids, reservation);
            }

            if (!world.TryCommit(plan, out StructuralCommitResult commit, out error)) return false;
            outcome = new DestructionCommitOutcome(true, commit);
            return true;
        }
    }
}
