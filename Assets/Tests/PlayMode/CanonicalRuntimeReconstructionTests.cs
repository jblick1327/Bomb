using System.Collections;
using Bomb.CanonicalDestruction;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace Bomb.CanonicalDestruction.Tests
{
    public sealed class CanonicalRuntimeReconstructionTests
    {
        [UnityTest]
        public IEnumerator DestroyedRuntimeProjection_RebuildsFromRoundTrippedCanonicalState()
        {
            var sourceId = new MaterialEntityId("material-source");
            var world = new CanonicalMaterialWorld(new SequentialMaterialEntityIdAllocator("material-result-"));
            var source = new CanonicalMaterialState(sourceId,
                new CanonicalMaterialShape(new[] { Rectangle(-2f, -1f, 2f, 1f) }),
                1, new Vector2(3f, 4f), 0.15f, new Vector2(1.25f, -0.5f), 0.3f,
                CanonicalBodyMode.Static, 1.2f, 0.2f);
            Assert.That(world.TryAddInitial(source, out string addError), Is.True, addError);
            var service = new CanonicalDestructionService(world);
            var cut = new DestructionRequest(sourceId, Rectangle(2.75f, 2f, 3.25f, 6f), new Vector2(3f, 4f), 0f);
            Assert.That(service.TryExecute(cut, out DestructionCommitOutcome outcome, out string cutError), Is.True, cutError);
            Assert.That(outcome.Commit.ResultIds.Count, Is.EqualTo(2));

            string json = CanonicalMaterialSnapshotCodec.Serialize(world);
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(json, out CanonicalMaterialWorld restored, out string loadError), Is.True, loadError);
            var host = new GameObject("Canonical Projection Test Host");
            var projector = new CanonicalMaterialRuntimeProjector(host.transform, null);
            try
            {
                Assert.That(projector.TryReconcile(restored, out string firstError), Is.True, firstError);
                AssertRuntimeMatches(restored, projector);

                projector.Clear();
                Assert.That(projector.ProjectionCount, Is.Zero);
                yield return null;

                Assert.That(projector.TryReconcile(restored, out string rebuildError), Is.True, rebuildError);
                AssertRuntimeMatches(restored, projector);
            }
            finally
            {
                projector.Dispose();
                Object.Destroy(host);
            }
            yield return null;
        }

        private static void AssertRuntimeMatches(CanonicalMaterialWorld world, CanonicalMaterialRuntimeProjector projector)
        {
            Assert.That(projector.ProjectionCount, Is.EqualTo(world.Count));
            foreach (CanonicalMaterialState state in world.Entities)
            {
                Assert.That(projector.TryGetProjection(state.Id, out GameObject projection), Is.True);
                Assert.That(projection.GetComponent<CanonicalMaterialProjectionIdentity>().CanonicalId, Is.EqualTo(state.Id));
                Assert.That(projection.GetComponent<Rigidbody>(), Is.Not.Null);
                Assert.That(projection.GetComponent<MeshFilter>().sharedMesh, Is.Not.Null);
                Assert.That(projection.GetComponentsInChildren<MeshCollider>().Length, Is.EqualTo(state.Shape.Cells.Count));
                Assert.That(Vector2.Distance(projection.transform.position, state.Position), Is.LessThan(0.0001f));
            }
        }

        private static CanonicalPolygon2D Rectangle(float left, float bottom, float right, float top)
        {
            return new CanonicalPolygon2D(new[]
            {
                new Vector2(left, bottom), new Vector2(right, bottom),
                new Vector2(right, top), new Vector2(left, top)
            });
        }
    }
}
