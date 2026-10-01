using System;
using System.Collections.Generic;
using System.Linq;
using Bomb.CanonicalDestruction;
using NUnit.Framework;
using UnityEngine;

namespace Bomb.CanonicalDestruction.Tests
{
    public sealed class CanonicalDestructionTests
    {
        [Test]
        public void FullRemoval_RetiresSourceWithoutReplacement()
        {
            Fixture fixture = CreateFixture();

            Assert.That(fixture.Execute(Rectangle(-3f, -2f, 3f, 2f), out DestructionCommitOutcome outcome), Is.True);

            Assert.That(fixture.World.Count, Is.Zero);
            Assert.That(fixture.World.Contains(fixture.SourceId), Is.False);
            Assert.That(outcome.Commit.SourceRetired, Is.True);
            Assert.That(outcome.Commit.ResultIds, Is.Empty);
        }

        [Test]
        public void ConnectedBite_PreservesSourceAndAdvancesRevision()
        {
            Fixture fixture = CreateFixture();

            Assert.That(fixture.Execute(Rectangle(1f, 0f, 3f, 2f), out DestructionCommitOutcome outcome), Is.True);

            Assert.That(fixture.World.Count, Is.EqualTo(1));
            Assert.That(fixture.World.TryGet(fixture.SourceId, out CanonicalMaterialState updated), Is.True);
            Assert.That(updated.GeometryRevision, Is.EqualTo(2));
            Assert.That(updated.Shape.Area, Is.LessThan(8f));
            Assert.That(outcome.Commit.SourceRetired, Is.False);
            Assert.That(outcome.Commit.ResultIds, Is.EqualTo(new[] { fixture.SourceId }));
        }

        [Test]
        public void SeparatingCut_RetiresParentAndGivesEveryResultAFreshId()
        {
            Fixture fixture = CreateFixture();

            Assert.That(fixture.Execute(Rectangle(-0.25f, -2f, 0.25f, 2f), out DestructionCommitOutcome outcome), Is.True);

            Assert.That(fixture.World.Count, Is.EqualTo(2));
            Assert.That(fixture.World.Contains(fixture.SourceId), Is.False);
            Assert.That(outcome.Commit.SourceRetired, Is.True);
            Assert.That(outcome.Commit.ResultIds.Count, Is.EqualTo(2));
            Assert.That(outcome.Commit.ResultIds.Distinct().Count(), Is.EqualTo(2));
            Assert.That(outcome.Commit.ResultIds, Has.None.EqualTo(fixture.SourceId));
            foreach (MaterialEntityId resultId in outcome.Commit.ResultIds)
            {
                Assert.That(fixture.World.TryGet(resultId, out CanonicalMaterialState result), Is.True);
                Assert.That(result.GeometryRevision, Is.EqualTo(1));
            }
        }

        [Test]
        public void FailedEvaluation_LeavesCanonicalBytesAndNotificationsUntouched()
        {
            Fixture fixture = CreateFixture(new FailingEvaluator());
            string before = CanonicalMaterialSnapshotCodec.Serialize(fixture.World);
            int notifications = 0;
            fixture.World.Committed += _ => notifications++;

            bool succeeded = fixture.Service.TryExecute(
                new DestructionRequest(fixture.SourceId, Rectangle(-1f, -1f, 1f, 1f), Vector2.zero, 0f),
                out _, out string error);

            Assert.That(succeeded, Is.False);
            Assert.That(error, Does.Contain("fixture failure"));
            Assert.That(CanonicalMaterialSnapshotCodec.Serialize(fixture.World), Is.EqualTo(before));
            Assert.That(notifications, Is.Zero);
        }

        [Test]
        public void InvalidPlan_LeavesCanonicalBytesUntouched()
        {
            Fixture fixture = CreateFixture();
            string before = CanonicalMaterialSnapshotCodec.Serialize(fixture.World);
            Assert.That(fixture.World.TryGet(fixture.SourceId, out CanonicalMaterialState source), Is.True);
            var invalid = new StructuralMutationPlan(fixture.SourceId, source.GeometryRevision, false,
                source, Array.Empty<CanonicalMaterialState>(), new[] { fixture.SourceId });

            Assert.That(fixture.World.TryCommit(invalid, out _, out string error), Is.False);
            Assert.That(error, Does.Contain("advance"));
            Assert.That(CanonicalMaterialSnapshotCodec.Serialize(fixture.World), Is.EqualTo(before));
        }

        [Test]
        public void CommitObserver_SeesEntireMultiResultWorldAtomically()
        {
            Fixture fixture = CreateFixture();
            int notifications = 0;
            fixture.World.Committed += commit =>
            {
                notifications++;
                Assert.That(fixture.World.Contains(fixture.SourceId), Is.False);
                Assert.That(fixture.World.Count, Is.EqualTo(2));
                Assert.That(commit.ResultIds.All(fixture.World.Contains), Is.True);
            };

            Assert.That(fixture.Execute(Rectangle(-0.25f, -2f, 0.25f, 2f), out _), Is.True);
            Assert.That(notifications, Is.EqualTo(1));
        }

        [Test]
        public void SnapshotRoundTrip_PreservesPostDestructionCanonicalStateAndAllocator()
        {
            Fixture fixture = CreateFixture();
            Assert.That(fixture.Execute(Rectangle(-0.25f, -2f, 0.25f, 2f), out DestructionCommitOutcome outcome), Is.True);
            int index = 0;
            foreach (MaterialEntityId id in outcome.Commit.ResultIds)
            {
                Assert.That(fixture.World.TryUpdateMotion(id, new Vector2(index + 2f, index - 3f), 0.2f + index,
                    new Vector2(4f + index, -2f), 0.5f + index, out string motionError), Is.True, motionError);
                index++;
            }

            string json = CanonicalMaterialSnapshotCodec.Serialize(fixture.World);
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(json, out CanonicalMaterialWorld restored, out string error), Is.True, error);

            Assert.That(CanonicalMaterialSnapshotCodec.Serialize(restored), Is.EqualTo(json));
            Assert.That(restored.IdAllocator.NextSequence, Is.EqualTo(fixture.World.IdAllocator.NextSequence));
            AssertEquivalent(fixture.World, restored);
        }

        [Test]
        public void SnapshotContainsSemanticDataAndNoUnityObjectReferences()
        {
            Fixture fixture = CreateFixture();
            Assert.That(fixture.Execute(Rectangle(1f, 0f, 3f, 2f), out _), Is.True);

            string json = CanonicalMaterialSnapshotCodec.Serialize(fixture.World).ToLowerInvariant();

            Assert.That(json, Does.Contain("geometryrevision"));
            Assert.That(json, Does.Contain("linearvelocity"));
            Assert.That(json, Does.Not.Contain("instanceid"));
            Assert.That(json, Does.Not.Contain("gameobject"));
            Assert.That(json, Does.Not.Contain("transform"));
            Assert.That(json, Does.Not.Contain("rigidbody"));
            Assert.That(json, Does.Not.Contain("collider"));
            Assert.That(json, Does.Not.Contain("unityengine"));
        }

        private static Fixture CreateFixture(IDestructionGeometryEvaluator evaluator = null)
        {
            var sourceId = new MaterialEntityId("material-source");
            var world = new CanonicalMaterialWorld(new SequentialMaterialEntityIdAllocator("material-result-"));
            var state = new CanonicalMaterialState(sourceId,
                new CanonicalMaterialShape(new[] { Rectangle(-2f, -1f, 2f, 1f) }),
                1, Vector2.zero, 0f, Vector2.zero, 0f, CanonicalBodyMode.Static, 1f, 0.2f);
            Assert.That(world.TryAddInitial(state, out string error), Is.True, error);
            return new Fixture(sourceId, world, new CanonicalDestructionService(world, evaluator));
        }

        private static CanonicalPolygon2D Rectangle(float left, float bottom, float right, float top)
        {
            return new CanonicalPolygon2D(new[]
            {
                new Vector2(left, bottom), new Vector2(right, bottom),
                new Vector2(right, top), new Vector2(left, top)
            });
        }

        private static void AssertEquivalent(CanonicalMaterialWorld expected, CanonicalMaterialWorld actual)
        {
            Assert.That(actual.Count, Is.EqualTo(expected.Count));
            foreach (CanonicalMaterialState left in expected.Entities)
            {
                Assert.That(actual.TryGet(left.Id, out CanonicalMaterialState right), Is.True);
                Assert.That(right.GeometryRevision, Is.EqualTo(left.GeometryRevision));
                Assert.That(Vector2.Distance(right.Position, left.Position), Is.LessThan(0.00001f));
                Assert.That(right.RotationRadians, Is.EqualTo(left.RotationRadians).Within(0.00001f));
                Assert.That(Vector2.Distance(right.LinearVelocity, left.LinearVelocity), Is.LessThan(0.00001f));
                Assert.That(right.AngularVelocityRadians, Is.EqualTo(left.AngularVelocityRadians).Within(0.00001f));
                Assert.That(right.Shape.Cells.Count, Is.EqualTo(left.Shape.Cells.Count));
                for (int cell = 0; cell < left.Shape.Cells.Count; cell++)
                {
                    Assert.That(right.Shape.Cells[cell].Vertices.Count, Is.EqualTo(left.Shape.Cells[cell].Vertices.Count));
                    for (int point = 0; point < left.Shape.Cells[cell].Vertices.Count; point++)
                        Assert.That(Vector2.Distance(right.Shape.Cells[cell].Vertices[point], left.Shape.Cells[cell].Vertices[point]), Is.LessThan(0.00001f));
                }
            }
        }

        private sealed class Fixture
        {
            public Fixture(MaterialEntityId sourceId, CanonicalMaterialWorld world, CanonicalDestructionService service)
            {
                SourceId = sourceId;
                World = world;
                Service = service;
            }

            public MaterialEntityId SourceId { get; }
            public CanonicalMaterialWorld World { get; }
            public CanonicalDestructionService Service { get; }

            public bool Execute(CanonicalPolygon2D cutter, out DestructionCommitOutcome outcome)
            {
                bool result = Service.TryExecute(new DestructionRequest(SourceId, cutter, Vector2.zero, 0f),
                    out outcome, out string error);
                Assert.That(result, Is.True, error);
                return result;
            }
        }

        private sealed class FailingEvaluator : IDestructionGeometryEvaluator
        {
            public GeometryEvaluationResult Evaluate(CanonicalMaterialState source, DestructionRequest request)
                => GeometryEvaluationResult.Failure("fixture failure");
        }
    }
}
