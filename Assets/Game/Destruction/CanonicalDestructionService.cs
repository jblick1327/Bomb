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
            // LinearVelocity describes COM motion, including when a sole survivor keeps its local frame.
            Vector2 comOffset = Rotate(resultShape.Centroid - source.Shape.Centroid, source.RotationRadians);
            Vector2 velocity = source.LinearVelocity + CanonicalGeometry.AngularVelocityAt(source.AngularVelocityRadians, comOffset)
                + direction.normalized * request.ImpulseSpeed;
            var result = source.WithGeometry(resultId, resultShape, revision, velocity,
                source.AngularVelocityRadians, source.BodyMode);
            if (resultId != source.Id && source.Selection != null)
            {
                Vector2 center = resultShape.Centroid;
                result = result.WithGeometry(resultId, CanonicalGeometry.Translate(resultShape, -center), revision,
                    velocity,
                    source.AngularVelocityRadians, source.BodyMode).WithMotion(source.ToWorld(center), source.RotationRadians,
                        velocity, source.AngularVelocityRadians);
            }
            return result;
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
            this.evaluator = evaluator;
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

            if (!TryEvaluate(source, request, out GeometryEvaluationResult evaluation, out error)) return false;
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

            var derived = new List<CanonicalMaterialState>();
            int count = evaluation.ConnectedResults.Count;
            try
            {
                for (int i = 0; i < count; i++)
                {
                    var id = count == 1 ? source.Id : new MaterialEntityId("__geometry-result-" + i);
                    derived.Add(resultStatePolicy.BuildResult(source, id, evaluation.ConnectedResults[i],
                        count == 1 ? revisionPolicy.NextRevision(source.GeometryRevision) : revisionPolicy.InitialRevision, request));
                }
            }
            catch (Exception exception) { error = "Could not derive result material state: " + exception.Message; return false; }
            var replacements = new Dictionary<MaterialEntityId, IReadOnlyList<CanonicalMaterialState>> { [source.Id] = derived };
            if (!CanonicalOutcomePlanner.TryPlan(world, replacements, null, out var plan, out error, source.Id)) return false;
            if (!world.TryCommit(plan, out StructuralCommitResult commit, out error)) return false;
            outcome = new DestructionCommitOutcome(true, commit);
            return true;
        }

        public bool TryEvaluate(CanonicalMaterialState source, DestructionRequest request, out GeometryEvaluationResult evaluation, out string error)
        {
            evaluation = null; error = null;
            try
            {
                if (source.Selection != null)
                {
                    var response = world.Definitions.Resolve(source.Selection.Response);
                    if (!response.destructible) { evaluation = GeometryEvaluationResult.Success(false, new[] { source.Shape }); return true; }
                    evaluation = (evaluator ?? new ConvexSubtractionGeometryEvaluator(response.minimumRetainedCellArea)).Evaluate(source, request);
                }
                else evaluation = (evaluator ?? new ConvexSubtractionGeometryEvaluator()).Evaluate(source, request);
                if (evaluation == null || !evaluation.Succeeded) { error = evaluation?.Error ?? "Missing geometry result."; return false; }
                return true;
            }
            catch (Exception exception) { error = "Geometry evaluation failed: " + exception.Message; return false; }
        }
    }
}
