using System;
using System.Collections;
using System.IO;
using System.Linq;
using Bomb.CanonicalDestruction;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using Object = UnityEngine.Object;

namespace Bomb.Tests.PlayMode
{
    public sealed class HandbookConformanceRuntimeTests
    {
        private static void Rebuild(CanonicalWorldRuntime2D runtime,CanonicalMaterialWorld world)
        { Assert.That(runtime.TryRebuild(world,out var error),Is.True,error); }
        private static void Tick(CanonicalSimulationHost host,int count)
        { for (int i = 0; i < count; i++) Assert.That(host.Tick(out var error),Is.True,error); }
        private static Rigidbody2D Body(CanonicalWorldRuntime2D runtime,MaterialEntityId id)
        { Assert.That(runtime.TryGetBody(id,out var body),Is.True,"Missing " + id); return body; }
        private static void Commit(CanonicalMaterialWorld world,CanonicalWorldView view)
        { Assert.That(world.TryCommit(new StructuralMutationPlan(world.Generation,view),out var result,out var error),Is.True,error); Assert.That(result.NotificationErrors,Is.Empty); }
        private static void Evidence(string file,string contents)
        { var dir = Path.GetFullPath(Path.Combine(Application.dataPath,"../Temp/ConformanceEvidence")); Directory.CreateDirectory(dir); File.WriteAllText(Path.Combine(dir,file),contents); }
        private static void AssertProjection(CanonicalSimulationHost host)
        {
            foreach (var state in host.World.View.Bodies)
            {
                var body = Body(host.Runtime,state.Id);
                Assert.That(body.GetComponent<CanonicalMaterialProjectionIdentity>().CanonicalId,Is.EqualTo(state.Id));
                Assert.That(body.GetComponent<Rigidbody>(),Is.Null); Assert.That(body.GetComponentsInChildren<Collider>(),Is.Empty);
                Assert.That(Vector2.Distance(body.position,state.Position),Is.LessThan(0.0001f));
                Assert.That(Mathf.Abs(Mathf.DeltaAngle(body.rotation,state.RotationRadians * Mathf.Rad2Deg)),Is.LessThan(0.001f));
                if (state.BodyMode == CanonicalBodyMode.Dynamic)
                {
                    Assert.That(body.mass,Is.EqualTo(state.Mass(host.World.Definitions)).Within(0.00001f));
                    Assert.That(Vector2.Distance(body.linearVelocity,state.LinearVelocity),Is.LessThan(0.0001f));
                    Assert.That(body.angularVelocity * Mathf.Deg2Rad,Is.EqualTo(state.AngularVelocityRadians).Within(0.0001f));
                }
                var colliders = body.GetComponents<PolygonCollider2D>(); Assert.That(colliders.Length,Is.EqualTo(state.Shape.Cells.Count));
                for (int i = 0; i < colliders.Length; i++)
                { Assert.That(colliders[i].pathCount,Is.EqualTo(1)); Assert.That(colliders[i].GetPath(0),Is.EqualTo(state.Shape.Cells[i].Vertices.ToArray())); }
                var mesh = body.GetComponent<MeshFilter>().sharedMesh;
                var canonicalPoints = state.Shape.Cells.SelectMany(c => c.Vertices).ToArray();
                Assert.That(mesh.vertices.All(v => canonicalPoints.Any(p => Vector2.Distance(p,new Vector2(v.x,v.y)) < 0.00001f)),Is.True,
                    "Presentation may only use the current local gameplay geometry.");
                Assert.That(canonicalPoints.All(p => mesh.vertices.Any(v => Vector2.Distance(p,new Vector2(v.x,v.y)) < 0.00001f)),Is.True);
                var actualTint = body.GetComponent<MeshRenderer>().sharedMaterial.GetColor("_BaseColor");
                var expectedTint = host.World.Definitions.Resolve(state.Selection.Appearance).tint;
                Assert.That(Vector4.Distance(actualTint,expectedTint),Is.LessThan(0.00001f),"Resolved appearance tint must survive engine float conversion.");
            }
        }
        private static float FitError(CanonicalWorldRuntime2D runtime,CanonicalConnector c)
        {
            var a = Body(runtime,c.A); var b = Body(runtime,c.B);
            return Mathf.Max(Vector2.Distance(a.GetRelativePoint(c.A0),b.GetRelativePoint(c.B0)),Vector2.Distance(a.GetRelativePoint(c.A1),b.GetRelativePoint(c.B1)));
        }
        private static float HoldDistance(CanonicalSimulationHost host,CanonicalHold hold)
        {
            var character = host.World.View.Body(hold.Character); var role = host.World.Definitions.Resolve(character.Selection.Role);
            return Vector2.Distance(Body(host.Runtime,hold.Character).GetRelativePoint(role.Root(hold.Slot)),Body(host.Runtime,hold.Target).GetRelativePoint(hold.HeldLocal));
        }
        private static void Land(CanonicalSimulationHost host,ConformanceIds ids)
        {
            float initialY = host.World.View.Body(ids.Bomb).Position.y;
            for (int i = 0; i < 250 && !host.World.View.Body(ids.Bomb).Countdown.Active; i++) Tick(host,1);
            var bomb = host.World.View.Body(ids.Bomb);
            Assert.That(bomb.Countdown.Active,Is.True,"A real 2D support contact must activate the countdown.");
            Assert.That(bomb.Position.y,Is.LessThan(initialY - 1)); Assert.That(bomb.Position.y,Is.GreaterThan(3.65f));
            Assert.That(bomb.Countdown.RemainingSeconds,Is.EqualTo(8).Within(0.0001f));
        }
        [UnityTest]
        public IEnumerator SupportedHeldActiveFixture_ReconstructsBeforeAndAfterRealSplit_WithoutOldObjects()
        {
            var world = HandbookConformanceFixture.Create(out var ids); var runtime = new CanonicalWorldRuntime2D();
            try
            {
                Rebuild(runtime,world); var host = new CanonicalSimulationHost(world,runtime); Land(host,ids);
                var foundationCells = Body(runtime,ids.Support).GetComponents<PolygonCollider2D>();
                Assert.That(foundationCells.Any(c => c.OverlapPoint(new Vector2(2,1))),Is.False,"Open space must not become a collision hull.");
                Assert.That(foundationCells.Any(c => c.OverlapPoint(new Vector2(2,-0.5f))),Is.True);
                Assert.That(foundationCells.Any(c => c.OverlapPoint(new Vector2(-3.5f,3))),Is.True);
                Assert.That(Body(runtime,ids.Support).bodyType,Is.EqualTo(RigidbodyType2D.Static));
                Assert.That(Body(runtime,ids.Support).position,Is.EqualTo(Vector2.zero));
                Assert.That(Vector2.Distance(Body(runtime,ids.Platform).position,new Vector2(0,3)),Is.LessThan(0.03f));
                Assert.That(FitError(runtime,world.View.Connectors.Single()),Is.LessThan(0.03f));
                Assert.That(HoldDistance(host,world.View.Holds.Single()),Is.LessThan(1.55f));
                Assert.That(host.TryCapture(out var before,out var error),Is.True,error); Evidence("primary-before.json",before);
                var oldBodies = world.View.Bodies.Select(b => Body(runtime,b.Id)).ToArray(); int frame = Time.frameCount;
                runtime.Clear(); world = null; yield return null;
                Assert.That(Time.frameCount,Is.GreaterThan(frame),"Play frames must advance."); Assert.That(oldBodies.All(b => b == null),Is.True);
                Assert.That(host.TryRecover(before,out error),Is.True,error); AssertProjection(host);
                Assert.That(host.World.View.Body(ids.Bomb).Countdown.RemainingSeconds,Is.EqualTo(8).Within(0.0001f));
                bool completeDerived = false;
                host.World.Committed += commit => completeDerived = !runtime.TryGetBody(ids.Platform,out _)
                    && commit.ResultIds.All(id => runtime.TryGetBody(id,out _))
                    && host.World.View.Holds.Single().Target != host.World.View.Connectors.Single().B;
                var service = new CanonicalDestructionService(host.World);
                Assert.That(service.TryExecute(new DestructionRequest(ids.Platform,HandbookConformanceFixture.Rectangle(-0.25f,2.4f,0.25f,3.6f),Vector2.zero,0),out var split,out error),Is.True,error);
                Assert.That(split.Commit.NotificationErrors,Is.Empty); Assert.That(completeDerived,Is.True);
                Assert.That(host.World.View.Connectors.Single().Id,Is.EqualTo(ids.Connector)); Assert.That(host.World.View.Holds.Single().Id,Is.EqualTo(ids.Hold));
                Assert.That(host.TryCapture(out var after,out error),Is.True,error); Evidence("primary-after.json",after);
                oldBodies = host.World.View.Bodies.Select(b => Body(runtime,b.Id)).ToArray(); runtime.Clear(); yield return null;
                Assert.That(oldBodies.All(b => b == null),Is.True); Assert.That(host.TryRecover(after,out error),Is.True,error); AssertProjection(host);
                Assert.That(host.World.Contains(ids.Platform),Is.False);
                Tick(host,30);
                Assert.That(Body(runtime,ids.Support).position,Is.EqualTo(Vector2.zero));
                Assert.That(FitError(runtime,host.World.View.Connectors.Single()),Is.LessThan(0.03f));
                Assert.That(HoldDistance(host,host.World.View.Holds.Single()),Is.LessThan(1.55f));
                Assert.That(host.World.View.Body(ids.Bomb).Countdown.RemainingSeconds,Is.EqualTo(7.4f).Within(0.001f));
                Evidence("primary-measurements.json",JsonUtility.ToJson(new Measurements { frameAdvanced = true, steps = runtime.Steps,
                    support = Body(runtime,ids.Support).position, connectorFit = FitError(runtime,host.World.View.Connectors.Single()),
                    holdDistance = HoldDistance(host,host.World.View.Holds.Single()), remainingSeconds = host.World.View.Body(ids.Bomb).Countdown.RemainingSeconds },true));
            }
            finally { runtime.Dispose(); }
            yield return null;
        }
        [UnityTest]
        public IEnumerator SpinningSingleSurvivor_PreservesEnginePointVelocity_AcrossCommitAndRecovery()
        {
            var world = HandbookConformanceFixture.Create(out var ids); var runtime = new CanonicalWorldRuntime2D();
            try
            {
                var source = world.View.Body(ids.Platform).WithMotion(new Vector2(4,7),Mathf.PI * 0.5f,new Vector2(1,-2),2);
                Assert.That(world.TryUpdateBodyBatch(new[] { source },out var error),Is.True,error);
                Commit(world,new CanonicalWorldView(new[] { source })); Rebuild(runtime,world);
                var point = source.ToWorld(new Vector2(1,0));
                var beforeVelocity = Body(runtime,ids.Platform).GetPointVelocity(point);
                Assert.That(Vector2.Distance(beforeVelocity,new Vector2(-1,-2)),Is.LessThan(0.0001f));
                var cutter = new CanonicalPolygon2D(HandbookConformanceFixture.Rectangle(2.5f,-0.6f,4,0.6f).Vertices.Select(source.ToWorld));
                Assert.That(new CanonicalDestructionService(world).TryExecute(new DestructionRequest(ids.Platform,cutter,Vector2.zero,0),out var outcome,out error),Is.True,error);
                Assert.That(outcome.Commit.NotificationErrors,Is.Empty); Assert.That(outcome.Commit.ResultIds.Single(),Is.EqualTo(ids.Platform));
                Assert.That(Vector2.Distance(Body(runtime,ids.Platform).GetPointVelocity(point),beforeVelocity),Is.LessThan(0.0001f));
                var host = new CanonicalSimulationHost(world,runtime);
                Assert.That(host.TryCapture(out var snapshot,out error),Is.True,error);
                var previousBody = Body(runtime,ids.Platform); runtime.Clear(); yield return null;
                Assert.That(previousBody == null,Is.True); Assert.That(host.TryRecover(snapshot,out error),Is.True,error);
                Assert.That(Vector2.Distance(Body(runtime,ids.Platform).position,source.Position),Is.LessThan(0.0001f));
                Assert.That(Vector2.Distance(Body(runtime,ids.Platform).GetPointVelocity(point),beforeVelocity),Is.LessThan(0.0001f));
            }
            finally { runtime.Dispose(); }
            yield return null;
        }
        [UnityTest]
        public IEnumerator PerturbedReconstruction_RestoresAuthoredRigidFit_InsteadOfAdoptingDisplacement()
        {
            var world = HandbookConformanceFixture.Create(out var ids); var runtime = new CanonicalWorldRuntime2D();
            try
            {
                var p = world.View.Body(ids.Platform).WithMotion(new Vector2(0.4f,3.2f),0.15f,Vector2.zero,0);
                Assert.That(world.TryUpdateBodyBatch(new[] { p },out var error),Is.True,error);
                string json = CanonicalMaterialSnapshotCodec.Serialize(world);
                Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(json,out world,out error),Is.True,error);
                Rebuild(runtime,world); var c = world.View.Connectors.Single(); float initialError = FitError(runtime,c);
                Assert.That(initialError,Is.GreaterThan(0.1f));
                // Constraint isolation: host load failure is tested separately; automatic engine breakage stays disabled.
                for (int i = 0; i < 100; i++) runtime.Step();
                Assert.That(runtime.TryCaptureMotion(world,out error),Is.True,error);
                Assert.That(FitError(runtime,c),Is.LessThan(0.03f));
                Assert.That(Vector2.Distance(Body(runtime,ids.Platform).position,new Vector2(0,3)),Is.LessThan(0.03f));
                Assert.That(Mathf.Abs(Mathf.DeltaAngle(Body(runtime,ids.Platform).rotation,0)),Is.LessThan(1));
                Evidence("connector-rest-fit.json",JsonUtility.ToJson(new Measurements { initialFit = initialError, connectorFit = FitError(runtime,c), steps = runtime.Steps },true));
            }
            finally { runtime.Dispose(); }
            yield return null;
        }
        [UnityTest]
        public IEnumerator MeasuredForce_ExceedingCapacity_RetiresConnectorOnFirstStep()
        {
            var world = HandbookConformanceFixture.Create(out var ids); var runtime = new CanonicalWorldRuntime2D();
            try
            {
                var old = world.View.Body(ids.Platform);
                var p = new CanonicalMaterialState(old.Id,HandbookConformanceFixture.Shape(HandbookConformanceFixture.Rectangle(-0.5f,-0.5f,0.5f,0.5f)),
                    2,new Vector2(-3,3),0,Vector2.zero,0,CanonicalBodyMode.Dynamic,old.Selection);
                var c = new CanonicalConnector(ids.Connector,ids.Support,ids.Platform,new Vector2(-3,2.7f),new Vector2(-3,3.3f),
                    new Vector2(0,-0.3f),new Vector2(0,0.3f),100,0.5f,0.6f);
                Commit(world,new CanonicalWorldView(world.View.Bodies.Select(b => b.Id == p.Id ? p : b),new[] { c },null,world.View.Participants));
                Rebuild(runtime,world); var host = new CanonicalSimulationHost(world,runtime);
                Body(runtime,ids.Platform).AddForce(new Vector2(0,200),ForceMode2D.Force); Tick(host,1);
                var load = host.LastLoads[ids.Connector]; Assert.That(load.Force.magnitude,Is.GreaterThan(c.ForceCapacity));
                Assert.That(Mathf.Abs(load.Torque),Is.LessThan(c.TorqueCapacity)); Assert.That(world.View.Connectors,Is.Empty); Assert.That(runtime.ConnectorJoints(ids.Connector),Is.Empty);
                Evidence("connector-force.json",JsonUtility.ToJson(new Measurements { force = load.Force, torque = load.Torque, forceCapacity = c.ForceCapacity, torqueCapacity = c.TorqueCapacity, steps = 1 },true));
            }
            finally { runtime.Dispose(); }
            yield return null;
        }
        [UnityTest]
        public IEnumerator MeasuredBendingMoment_ExceedingCapacity_RetiresConnectorOnFirstStep()
        {
            var world = HandbookConformanceFixture.Create(out var ids); var runtime = new CanonicalWorldRuntime2D();
            try
            {
                var old = world.View.Connectors.Single(); var c = new CanonicalConnector(old.Id,old.A,old.B,old.A0,old.A1,old.B0,old.B1,1000,0.5f,0.6f);
                Commit(world,new CanonicalWorldView(world.View.Bodies,new[] { c },null,world.View.Participants));
                Rebuild(runtime,world); var host = new CanonicalSimulationHost(world,runtime); Body(runtime,ids.Platform).AddTorque(2000,ForceMode2D.Force); Tick(host,1);
                var load = host.LastLoads[ids.Connector]; Assert.That(Mathf.Abs(load.Torque),Is.GreaterThan(c.TorqueCapacity));
                Assert.That(load.Force.magnitude,Is.LessThan(c.ForceCapacity)); Assert.That(world.View.Connectors,Is.Empty);
                Evidence("connector-torque.json",JsonUtility.ToJson(new Measurements { force = load.Force, torque = load.Torque, forceCapacity = c.ForceCapacity, torqueCapacity = c.TorqueCapacity, steps = 1 },true));
            }
            finally { runtime.Dispose(); }
            yield return null;
        }
        [UnityTest]
        public IEnumerator Hold_AllowsMovementRotationAndLargeForce_WhileConstrainingReach()
        {
            var world = HandbookConformanceFixture.Create(out var ids); var runtime = new CanonicalWorldRuntime2D();
            try
            {
                var hold = new CanonicalHold(ids.Hold,ids.Character,LimbSlot.RightHand,ids.Support,new Vector2(2,0));
                Commit(world,new CanonicalWorldView(world.View.Bodies,world.View.Connectors,new[] { hold },world.View.Participants));
                Rebuild(runtime,world); var host = new CanonicalSimulationHost(world,runtime); var actor = Body(runtime,ids.Character);
                Vector2 start = actor.position; actor.linearVelocity = new Vector2(1,0); actor.angularVelocity = 50;
                Tick(host,8); actor = Body(runtime,ids.Character);
                Assert.That(actor.position.x - start.x,Is.GreaterThan(0.1f)); Assert.That(Mathf.Abs(actor.rotation),Is.GreaterThan(5));
                actor.AddForce(new Vector2(1000,500),ForceMode2D.Force); Tick(host,1);
                var joint = runtime.HoldJoint(ids.Hold); float reaction = joint.GetReactionForce(CanonicalWorldRuntime2D.StepSeconds).magnitude;
                Assert.That(reaction,Is.GreaterThan(100)); Assert.That(HoldDistance(host,hold),Is.LessThan(1.55f));
                for (int i = 0; i < 12; i++) { Tick(host,1); Assert.That(HoldDistance(host,hold),Is.LessThan(1.55f)); }
                Assert.That(world.View.Holds.Single().Id,Is.EqualTo(ids.Hold)); Assert.That(runtime.HoldJoint(ids.Hold).maxDistanceOnly,Is.True);
                Assert.That(float.IsPositiveInfinity(runtime.HoldJoint(ids.Hold).breakForce),Is.True);
                Assert.That(HoldDistance(host,hold),Is.LessThan(1.55f));
                Evidence("hold-reach.json",JsonUtility.ToJson(new Measurements { holdDistance = HoldDistance(host,hold), force = new Vector2(reaction,0),
                    rotation = Body(runtime,ids.Character).rotation, position = Body(runtime,ids.Character).position },true));
            }
            finally { runtime.Dispose(); }
            yield return null;
        }
        [UnityTest]
        public IEnumerator ExtremeForce_RetainsHoldIdentity_AndReportsTransientSolverStretch()
        {
            var world = HandbookConformanceFixture.Create(out var ids); var runtime = new CanonicalWorldRuntime2D();
            try
            {
                var hold = new CanonicalHold(ids.Hold,ids.Character,LimbSlot.RightHand,ids.Support,new Vector2(2,0));
                Commit(world,new CanonicalWorldView(world.View.Bodies,world.View.Connectors,new[] { hold },world.View.Participants));
                Rebuild(runtime,world); var host = new CanonicalSimulationHost(world,runtime); var actor = Body(runtime,ids.Character);
                actor.linearVelocity = new Vector2(1,0); actor.angularVelocity = 50; Tick(host,8);
                Body(runtime,ids.Character).AddForce(new Vector2(10000,5000),ForceMode2D.Force);
                float peak = 0, maximumReaction = 0;
                for (int i = 0; i < 40; i++)
                {
                    Tick(host,1);
                    Assert.That(world.View.Holds.Single().Id,Is.EqualTo(ids.Hold)); Assert.That(runtime.HoldJoint(ids.Hold),Is.Not.Null);
                    peak = Mathf.Max(peak,HoldDistance(host,hold)); maximumReaction = Mathf.Max(maximumReaction,runtime.HoldJoint(ids.Hold).GetReactionForce(0.02f).magnitude);
                }
                Assert.That(maximumReaction,Is.GreaterThan(1000)); Assert.That(HoldDistance(host,hold),Is.LessThan(1.55f));
                Evidence("hold-extreme-solver-limit.json",JsonUtility.ToJson(new Measurements { holdDistance = HoldDistance(host,hold),
                    peakHoldDistance = peak, authoredReach = 1.5f, force = new Vector2(maximumReaction,0), steps = 40 },true));
            }
            finally { runtime.Dispose(); }
            yield return null;
        }
        [UnityTest]
        public IEnumerator Hold_OnMovingTarget_KeepsTheSameTargetLocalMaterialPoint()
        {
            var world = HandbookConformanceFixture.Create(out var ids); var runtime = new CanonicalWorldRuntime2D();
            try
            {
                Commit(world,new CanonicalWorldView(world.View.Bodies,null,world.View.Holds,world.View.Participants));
                Rebuild(runtime,world); var host = new CanonicalSimulationHost(world,runtime); var hold = world.View.Holds.Single();
                Vector2 before = Body(runtime,ids.Platform).GetRelativePoint(hold.HeldLocal); Body(runtime,ids.Platform).linearVelocity = new Vector2(2,0);
                Tick(host,25);
                Assert.That(world.View.Holds.Single().HeldLocal,Is.EqualTo(new Vector2(2,-0.5f))); Assert.That(world.View.Holds.Single().Id,Is.EqualTo(ids.Hold));
                Assert.That(Vector2.Distance(Body(runtime,ids.Platform).GetRelativePoint(hold.HeldLocal),before),Is.GreaterThan(0.5f));
                Assert.That(HoldDistance(host,hold),Is.LessThan(1.55f));
            }
            finally { runtime.Dispose(); }
            yield return null;
        }
        [UnityTest]
        public IEnumerator OrdinaryFootContact_CreatesNoHold()
        {
            var world = HandbookConformanceFixture.Create(out var ids); var runtime = new CanonicalWorldRuntime2D();
            try
            {
                Commit(world,new CanonicalWorldView(world.View.Bodies,world.View.Connectors,null,world.View.Participants));
                Rebuild(runtime,world); var host = new CanonicalSimulationHost(world,runtime); Tick(host,150);
                Assert.That(Body(runtime,ids.Character).position.y,Is.EqualTo(0.4f).Within(0.03f));
                Assert.That(world.View.Holds,Is.Empty); Assert.That(Body(runtime,ids.Character).GetComponents<DistanceJoint2D>(),Is.Empty);
            }
            finally { runtime.Dispose(); }
            yield return null;
        }
        [UnityTest]
        public IEnumerator EngineMassBelowPointOne_AndPresentationDepth_DoNotChangeAuthoritativeMotion()
        {
            var world = HandbookConformanceFixture.Create(out var ids); var old = world.View.Body(ids.Platform);
            var selection = HandbookConformanceFixture.Selection(world.Definitions,"light","convex-subtraction","terrain",DefinitionKind.Environment,"platform");
            var p = new CanonicalMaterialState(ids.Platform,HandbookConformanceFixture.Shape(HandbookConformanceFixture.Rectangle(-0.25f,-0.1f,0.25f,0.1f)),
                2,new Vector2(0,5),0,Vector2.zero,0,CanonicalBodyMode.Dynamic,selection);
            Commit(world,new CanonicalWorldView(new[] { p })); string initial = CanonicalMaterialSnapshotCodec.Serialize(world);
            var runtime = new CanonicalWorldRuntime2D();
            try
            {
                Rebuild(runtime,world); var host = new CanonicalSimulationHost(world,runtime); float mass = Body(runtime,ids.Platform).mass;
                Assert.That(mass,Is.EqualTo(0.02f).Within(0.000001f)); Assert.That(mass,Is.LessThan(0.1f));
                Tick(host,30); Vector2 firstPosition = Body(runtime,ids.Platform).position, firstVelocity = Body(runtime,ids.Platform).linearVelocity;
                Assert.That(firstVelocity.y,Is.EqualTo(-9.81f * 0.6f).Within(0.001f));
                runtime.Clear(); yield return null; runtime.PresentationDepthMultiplier = 4;
                Assert.That(host.TryRecover(initial,out var error),Is.True,error); Tick(host,30);
                Assert.That(Vector2.Distance(Body(runtime,ids.Platform).position,firstPosition),Is.LessThan(0.00001f));
                Assert.That(Vector2.Distance(Body(runtime,ids.Platform).linearVelocity,firstVelocity),Is.LessThan(0.00001f));
                Assert.That(Body(runtime,ids.Platform).GetComponent<MeshFilter>().sharedMesh.bounds.size.z,Is.EqualTo(0.8f).Within(0.00001f));
                Evidence("mass-and-presentation.json",JsonUtility.ToJson(new Measurements { mass = mass, position = firstPosition, velocity = firstVelocity, depth = 0.8f },true));
            }
            finally { runtime.Dispose(); }
            yield return null;
        }
        [UnityTest]
        public IEnumerator PhysicallyFallingHeldBomb_CountsDownAndExplodesFromReachableOrigin_WithAtomicDeathAndHoldCleanup()
        {
            var world = HandbookConformanceFixture.Create(out var ids); var runtime = new CanonicalWorldRuntime2D();
            try
            {
                Rebuild(runtime,world); var host = new CanonicalSimulationHost(world,runtime); Land(host,ids);
                Assert.That(host.TryRelease(ids.Participant,LimbSlot.RightHand,out var error),Is.True,error);
                var bomb = world.View.Body(ids.Bomb); double timer = bomb.Countdown.RemainingSeconds;
                Body(runtime,ids.Character).position = bomb.Position + new Vector2(0,1.25f); Body(runtime,ids.Character).linearVelocity = Vector2.zero;
                Assert.That(runtime.TryCaptureMotion(world,out error),Is.True,error);
                Assert.That(host.TryHold(new HoldRequest(ids.Participant,ids.Character,LimbSlot.LeftHand,ids.Bomb,new Vector2(0,0.25f),1),out var hold,out error),Is.True,error);
                Assert.That(world.View.Body(ids.Bomb).Countdown.RemainingSeconds,Is.EqualTo(timer));
                CanonicalMaterialState platformBeforeBlast = null; CanonicalWorldView observed = null; bool projectedBombRetired = false;
                world.Committed += commit => { observed = world.View; projectedBombRetired = !runtime.TryGetBody(ids.Bomb,out _); };
                int steps = 0;
                while (world.Contains(ids.Bomb) && steps++ < 450) { platformBeforeBlast = world.View.Body(ids.Platform); Tick(host,1); }
                Assert.That(steps,Is.EqualTo(400),"The landed eight-second timer must detonate on its 400th active step.");
                Assert.That(world.Contains(ids.Bomb),Is.False); Assert.That(host.LastExplosionCenter.HasValue,Is.True); Vector2 origin = host.LastExplosionCenter.Value;
                Assert.That(CanonicalGeometry.Contains(platformBeforeBlast.Shape,platformBeforeBlast.ToLocal(origin)),Is.False);
                Assert.That(origin.y,Is.GreaterThan(3.6f)); Assert.That(world.View.Body(ids.Platform).Shape.Area,Is.LessThan(6));
                Assert.That(observed.Holds.Any(h => h.Target == ids.Bomb || h.Character == ids.Character),Is.False); Assert.That(projectedBombRetired,Is.True);
                Assert.That(world.View.Body(ids.Character).IsCharacter,Is.False); Assert.That(world.View.Participants.Single().ControlledBody.IsValid,Is.False);
                Assert.That(host.LastStructuralCommit.NotificationErrors,Is.Empty);
                Evidence("reachable-bomb.json",JsonUtility.ToJson(new Measurements { position = origin, remainingSeconds = 0, steps = steps,
                    platformArea = world.View.Body(ids.Platform).Shape.Area, bodyIdPreserved = world.Contains(ids.Character), bombRetired = !world.Contains(ids.Bomb) },true));
            }
            finally { runtime.Dispose(); }
            yield return null;
        }
        [Serializable]
        private sealed class Measurements
        {
            public bool frameAdvanced, bodyIdPreserved, bombRetired;
            public int steps;
            public Vector2 support, force, position, velocity;
            public double remainingSeconds;
            public float initialFit, connectorFit, holdDistance, peakHoldDistance, authoredReach, torque, forceCapacity, torqueCapacity, rotation, mass, depth, platformArea;
        }
    }
}
