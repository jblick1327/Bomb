using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using Bomb.CanonicalDestruction;
using NUnit.Framework;
using UnityEngine;

namespace Bomb.Tests.EditMode
{
    public sealed class HandbookConformanceTests
    {
        private static CanonicalPolygon2D Rect(float x0, float y0, float x1, float y1) => HandbookConformanceFixture.Rectangle(x0,y0,x1,y1);
        private static void Commit(CanonicalMaterialWorld world, CanonicalWorldView view, MaterialEntityIdReservation reservation = null)
        {
            Assert.That(world.TryCommit(new StructuralMutationPlan(world.Generation,view,reservation),out var result,out var error),Is.True,error);
            Assert.That(result.NotificationErrors,Is.Empty);
        }
        private static void Cut(CanonicalMaterialWorld world, MaterialEntityId target, CanonicalPolygon2D cutter)
        {
            Assert.That(new CanonicalDestructionService(world).TryExecute(new DestructionRequest(target,cutter,Vector2.zero,0),out var result,out var error),Is.True,error);
            Assert.That(result.Changed,Is.True); Assert.That(result.Commit.NotificationErrors,Is.Empty);
        }
        private static string Bytes(CanonicalMaterialWorld world) => CanonicalMaterialSnapshotCodec.Serialize(world);
        private static void Motion(CanonicalMaterialWorld world, CanonicalMaterialState state)
        { Assert.That(world.TryUpdateBodyBatch(new[] { state },out var error),Is.True,error); }

        [Test]
        public void RealPrimarySplit_AtomicallyRemapsConnectorAndHold_ToDifferentFreshChildren()
        {
            var world = HandbookConformanceFixture.Create(out var ids);
            var source = world.View.Body(ids.Platform); var sourceHoldPoint = source.ToWorld(new Vector2(2,-0.5f));
            var observations = new List<CanonicalWorldView>();
            world.Committed += result => observations.Add(world.View);
            Cut(world,ids.Platform,Rect(-0.25f,2.4f,0.25f,3.6f));
            Assert.That(world.Contains(ids.Platform),Is.False); Assert.That(world.Count,Is.EqualTo(5));
            Assert.That(observations,Has.Count.EqualTo(1));
            var connector = world.View.Connectors.Single(); var hold = world.View.Holds.Single();
            Assert.That(connector.Id,Is.EqualTo(ids.Connector)); Assert.That(hold.Id,Is.EqualTo(ids.Hold));
            Assert.That(connector.B,Is.Not.EqualTo(hold.Target));
            Assert.That(world.View.Body(connector.B).Position.x,Is.LessThan(0));
            Assert.That(world.View.Body(hold.Target).Position.x,Is.GreaterThan(0));
            Assert.That(Vector2.Distance(world.View.Body(hold.Target).ToWorld(hold.HeldLocal),sourceHoldPoint),Is.LessThan(0.0001f));
            var children = world.View.Bodies.Where(b => b.Id != ids.Support && b.Id != ids.Character && b.Id != ids.Bomb).ToArray();
            Assert.That(children.All(b => b.Selection.Equals(source.Selection) && b.GeometryRevision == 1),Is.True);
            Assert.That(children.Sum(b => b.Mass(world.Definitions)),Is.EqualTo(11).Within(0.0001f));
            Assert.That(source.Mass(world.Definitions),Is.EqualTo(12).Within(0.0001f));
            Assert.That(world.View.AllIds.Distinct().Count(),Is.EqualTo(world.View.AllIds.Count()));
            Assert.That(Bytes(world),Does.Not.Contain(ids.Platform.Value));
        }
        [Test]
        public void RealConnectedBite_PreservesBodyAndRelationshipIdentity_AndLocalFrame()
        {
            var world = HandbookConformanceFixture.Create(out var ids);
            Cut(world,ids.Platform,Rect(2.5f,3,3.5f,4));
            var p = world.View.Body(ids.Platform);
            Assert.That(p.GeometryRevision,Is.EqualTo(2)); Assert.That(p.Position,Is.EqualTo(new Vector2(0,3)));
            Assert.That(world.View.Connectors.Single().Id,Is.EqualTo(ids.Connector));
            Assert.That(world.View.Holds.Single().Id,Is.EqualTo(ids.Hold)); Assert.That(world.IdAllocator.NextSequence,Is.EqualTo(8));
        }
        [Test]
        public void RealFullRemoval_RetiresTargetingRelationships_WithoutChangingControl()
        {
            var world = HandbookConformanceFixture.Create(out var ids);
            Cut(world,ids.Platform,Rect(-4,2,4,4));
            Assert.That(world.Contains(ids.Platform),Is.False); Assert.That(world.View.Connectors,Is.Empty); Assert.That(world.View.Holds,Is.Empty);
            Assert.That(world.View.Participants.Single().ControlledBody,Is.EqualTo(ids.Character));
        }
        [Test]
        public void LostHeldLocation_RetiresHold_InsteadOfProjectingItOntoANewEdge()
        {
            var world = HandbookConformanceFixture.Create(out var ids);
            Cut(world,ids.Platform,Rect(1.9f,2.4f,2.1f,3.1f));
            Assert.That(world.Contains(ids.Platform),Is.True); Assert.That(world.View.Holds,Is.Empty); Assert.That(world.View.Connectors,Has.Count.EqualTo(1));
        }
        [Test]
        public void RotatedRecentering_PreservesMaterialLocationsAndRigidMotionVelocity()
        {
            var world = HandbookConformanceFixture.Create(out var ids);
            var source = world.View.Body(ids.Platform).WithMotion(new Vector2(4,7),0.4f,new Vector2(1,-2),0.7f);
            Motion(world,source);
            var cutter = new CanonicalPolygon2D(Rect(-0.25f,-0.6f,0.25f,0.6f).Vertices.Select(source.ToWorld));
            Cut(world,ids.Platform,cutter);
            foreach (var child in world.View.Bodies.Where(b => b.Selection.Equals(source.Selection)))
            {
                Assert.That(child.Shape.Centroid.magnitude,Is.LessThan(0.0001f));
                var radius = child.Position - source.ToWorld(source.Shape.Centroid);
                Assert.That(Vector2.Distance(child.LinearVelocity,source.LinearVelocity + CanonicalGeometry.AngularVelocityAt(source.AngularVelocityRadians,radius)),Is.LessThan(0.0001f));
                Assert.That(child.AngularVelocityRadians,Is.EqualTo(0.7f));
            }
            var h = world.View.Holds.Single(); var c = world.View.Connectors.Single();
            Assert.That(Vector2.Distance(world.View.Body(h.Target).ToWorld(h.HeldLocal),source.ToWorld(new Vector2(2,-0.5f))),Is.LessThan(0.0001f));
            Assert.That(Vector2.Distance(world.View.Body(c.B).ToWorld(c.B0),source.ToWorld(new Vector2(-3,-0.3f))),Is.LessThan(0.0001f));
        }
        [Test]
        public void InvalidCompleteGraph_AndRejectedPreparation_LeaveBytesNotificationsAndAllocatorUnchanged()
        {
            var world = HandbookConformanceFixture.Create(out var ids); string before = Bytes(world); int notifications = 0;
            world.Committed += _ => notifications++;
            var invalid = new CanonicalWorldView(world.View.Bodies.Where(b => b.Id != ids.Platform),world.View.Connectors,world.View.Holds,world.View.Participants);
            Assert.That(world.TryCommit(new StructuralMutationPlan(world.Generation,invalid),out _,out _),Is.False);
            Assert.That(Bytes(world),Is.EqualTo(before));
            world.Projection = new RejectProjection();
            Assert.That(new CanonicalDestructionService(world).TryExecute(new DestructionRequest(ids.Platform,Rect(-0.25f,2.4f,0.25f,3.6f),Vector2.zero,0),out _,out _),Is.False);
            Assert.That(Bytes(world),Is.EqualTo(before)); Assert.That(notifications,Is.Zero);
            Assert.That(world.TryReserveEntityIds(1,out var reservation,out var error),Is.True,error);
            Assert.That(reservation.Ids[0].Value,Is.EqualTo("match-0000000000000008")); world.IdAllocator.Cancel(reservation);
        }
        [Test]
        public void ReservationFromAnOldAllocator_CannotCommitOrCancelTheRecoveredAllocatorsReservation()
        {
            var old = new SequentialMaterialEntityIdAllocator("same-match-",8);
            var recovered = new SequentialMaterialEntityIdAllocator("same-match-",8);
            Assert.That(old.TryReserve(1,out var oldReservation,out var error),Is.True,error);
            Assert.That(recovered.TryReserve(1,out var currentReservation,out error),Is.True,error);
            Assert.That(oldReservation.Ids,Is.EqualTo(currentReservation.Ids));
            Assert.That(recovered.TryCommit(oldReservation,out error),Is.False);
            Assert.That(recovered.NextSequence,Is.EqualTo(8));
            recovered.Cancel(oldReservation);
            Assert.That(recovered.TryCommit(currentReservation,out error),Is.True,error);
            Assert.That(recovered.NextSequence,Is.EqualTo(9)); old.Cancel(oldReservation);
        }
        [Test]
        public void StaleInternalPlan_RejectsEvenWhenSourceGeometryRevisionStillMatches()
        {
            var world = HandbookConformanceFixture.Create(out var ids);
            var plan = new StructuralMutationPlan(world.Generation,new CanonicalWorldView(world.View.Bodies,world.View.Connectors,world.View.Holds,world.View.Participants));
            Motion(world,world.View.Body(ids.Bomb).WithCountdown(new BombCountdown(true,7)));
            string before = Bytes(world);
            Assert.That(world.TryCommit(plan,out _,out var error),Is.False); Assert.That(error,Does.Contain("stale")); Assert.That(Bytes(world),Is.EqualTo(before));
        }
        [Test]
        public void ThrowingOneResultPolicy_IsReportedWithoutAnyPublication()
        {
            var world = HandbookConformanceFixture.Create(out var ids); string before = Bytes(world);
            var service = new CanonicalDestructionService(world,resultStatePolicy:new ThrowingPolicy());
            Assert.That(service.TryExecute(new DestructionRequest(ids.Platform,Rect(2.5f,3,3.5f,4),Vector2.zero,0),out _,out var error),Is.False);
            Assert.That(error,Does.Contain("injected")); Assert.That(Bytes(world),Is.EqualTo(before));
        }
        [Test]
        public void InvalidMotionBatch_DoesNotPartiallyCaptureEarlierBodies()
        {
            var world = HandbookConformanceFixture.Create(out var ids); string before = Bytes(world);
            var valid = world.View.Body(ids.Character).WithMotion(new Vector2(8,9),0,Vector2.zero,0);
            var invalid = world.View.Body(ids.Bomb).WithMotion(new Vector2(float.NaN,0),0,Vector2.zero,0);
            Assert.That(world.TryUpdateBodyBatch(new[] { valid,invalid },out _),Is.False); Assert.That(Bytes(world),Is.EqualTo(before));
        }
        [Test]
        public void ObserverExceptions_AreVisible_AndOtherObserversSeeCompleteState()
        {
            var world = HandbookConformanceFixture.Create(out var ids); CanonicalWorldView observed = null;
            world.Committed += _ => throw new InvalidOperationException("injected observer"); world.Committed += _ => observed = world.View;
            Assert.That(new CanonicalDestructionService(world).TryExecute(new DestructionRequest(ids.Platform,Rect(-0.25f,2.4f,0.25f,3.6f),Vector2.zero,0),out var result,out var error),Is.True,error);
            Assert.That(result.Commit.NotificationErrors,Has.Count.EqualTo(1)); Assert.That(observed.Body(ids.Platform),Is.Null);
            Assert.That(observed.Holds.Single().Target,Is.Not.EqualTo(observed.Connectors.Single().B));
        }
        [TestCase(0.25f,2,1.75f)]
        [TestCase(1.75f,0,0)]
        public void BothEndpointRealSplits_UsePairedAttachment_AndTestOldPercentageBeforeReplacement(float halfCut,int count,float reference)
        {
            var world = TwinBars(out var a,out var b,out var oldConnector);
            var replacements = EvaluatedReplacements(world,new[] { a,b },Rect(-halfCut,2,halfCut,5));
            Assert.That(CanonicalOutcomePlanner.TryPlan(world,replacements,null,out var plan,out var error),Is.True,error);
            Assert.That(world.TryCommit(plan,out var result,out error),Is.True,error); Assert.That(result.NotificationErrors,Is.Empty);
            Assert.That(world.View.Connectors,Has.Count.EqualTo(count));
            foreach (var c in world.View.Connectors)
            {
                Assert.That(c.Id,Is.Not.EqualTo(oldConnector)); Assert.That(c.ReferenceLength,Is.EqualTo(reference).Within(0.0001f));
                Assert.That(c.AttachedLength,Is.EqualTo(reference).Within(0.0001f)); Assert.That(c.ForceCapacity,Is.EqualTo(100 * reference).Within(0.001f));
                Assert.That(Mathf.Sign(world.View.Body(c.A).Position.x),Is.EqualTo(Mathf.Sign(world.View.Body(c.B).Position.x)));
            }
        }
        [Test]
        public void ShorteningOneBond_KeepsIdentityReference_AndReducesBothCapacities()
        {
            var world = TwinBars(out var a,out _,out var id);
            Cut(world,a,Rect(1,3.2f,4,4));
            var c = world.View.Connectors.Single();
            Assert.That(c.Id,Is.EqualTo(id)); Assert.That(c.ReferenceLength,Is.EqualTo(4)); Assert.That(c.AttachedLength,Is.EqualTo(3).Within(0.0001f));
            Assert.That(c.ForceCapacity,Is.EqualTo(300).Within(0.01f)); Assert.That(c.TorqueCapacity,Is.EqualTo(450).Within(0.01f));
            Assert.That(c.FailsLoad(new Vector2(301,0),0),Is.True); Assert.That(c.FailsLoad(Vector2.zero,451),Is.True);
        }
        [Test]
        public void UnconfiguredPercentage_DoesNotInventAUniversalCutoff()
        {
            var world = TwinBars(out var a,out _,out var id); var c = world.View.Connectors.Single();
            Commit(world,new CanonicalWorldView(world.View.Bodies,new[] { new CanonicalConnector(id,c.A,c.B,c.A0,c.A1,c.B0,c.B1,100) }));
            Cut(world,a,Rect(-1.9f,3.2f,4,4));
            Assert.That(world.View.Connectors.Single().AttachedLength,Is.EqualTo(0.1f).Within(0.0001f));
            Assert.That(world.View.Connectors.Single().MinimumRemainingFraction,Is.Null);
        }
        [TestCase(LimbSlot.LeftHand,true)] [TestCase(LimbSlot.RightHand,true)]
        [TestCase(LimbSlot.LeftFoot,true)] [TestCase(LimbSlot.RightFoot,true)]
        [TestCase(LimbSlot.LeftHand,false)] [TestCase(LimbSlot.RightFoot,false)]
        public void OrdinaryHostValidation_UsesSharedAuthoredBombEligibility_AndPreservesCountdown(LimbSlot slot,bool eligible)
        {
            var world = HandbookConformanceFixture.Create(out var ids,eligible); var host = new CanonicalSimulationHost(world);
            Assert.That(host.TryRelease(ids.Participant,LimbSlot.RightHand,out var error),Is.True,error);
            var bomb = world.View.Body(ids.Bomb).WithMotion(new Vector2(2,1.7f),0,Vector2.zero,0).WithCountdown(new BombCountdown(true,6.25f)); Motion(world,bomb);
            bool accepted = host.TryHold(new HoldRequest(ids.Participant,ids.Character,slot,ids.Bomb,new Vector2(0,-0.25f),999),out var hold,out error);
            Assert.That(accepted,Is.EqualTo(eligible),error); Assert.That(world.View.Body(ids.Bomb).Countdown.RemainingSeconds,Is.EqualTo(6.25f));
            if (eligible) { Assert.That(hold.Id.IsValid,Is.True); Assert.That(host.LastObservedRevisionMismatch,Is.True); }
            else Assert.That(world.View.Holds,Is.Empty);
        }
        [Test]
        public void CurrentGeometryAndControlDecideValidity_ObservedRevisionMismatchAloneDoesNotReject()
        {
            var world = HandbookConformanceFixture.Create(out var ids); var host = new CanonicalSimulationHost(world);
            Assert.That(host.TryRelease(ids.Participant,LimbSlot.RightHand,out _),Is.True);
            Cut(world,ids.Platform,Rect(2.5f,3,3.5f,4));
            Assert.That(host.TryHold(new HoldRequest(ids.Participant,ids.Character,LimbSlot.RightHand,ids.Platform,new Vector2(2,-0.5f),1),out _,out var error),Is.True,error);
            Assert.That(host.LastObservedRevisionMismatch,Is.True);
            Assert.That(host.TryHold(new HoldRequest(ids.Participant,ids.Character,LimbSlot.RightHand,ids.Platform,new Vector2(2,-0.5f),1),out _,out error),Is.False,"Occupied slot.");
            Assert.That(host.TryHold(new HoldRequest(ids.Bomb,ids.Character,LimbSlot.LeftHand,ids.Platform,new Vector2(2,-0.5f),2),out _,out error),Is.False,"Wrong participant.");
        }
        [Test]
        public void NewHoldsRejectLostLocationsExcessReachAndObstruction_WithoutStateChanges()
        {
            var world = HandbookConformanceFixture.Create(out var ids); var host = new CanonicalSimulationHost(world);
            Assert.That(host.TryRelease(ids.Participant,LimbSlot.RightHand,out _),Is.True);
            string before = Bytes(world);
            foreach (var point in new[] { new Vector2(2,0),new Vector2(-2,-0.5f),new Vector2(2,0.5f) })
                Assert.That(host.TryHold(new HoldRequest(ids.Participant,ids.Character,LimbSlot.RightHand,ids.Platform,point,1),out _,out _),Is.False);
            Assert.That(Bytes(world),Is.EqualTo(before));
            Cut(world,ids.Platform,Rect(1.9f,2.4f,2.1f,3.1f)); before = Bytes(world);
            Assert.That(host.TryHold(new HoldRequest(ids.Participant,ids.Character,LimbSlot.RightHand,ids.Platform,new Vector2(2,-0.5f),1),out _,out _),Is.False);
            Assert.That(Bytes(world),Is.EqualTo(before));
        }
        [Test]
        public void Countdown_ActivatesOnce_AndContinuesThroughSupportLossAndFurtherLandings()
        {
            var timer = new BombCountdown(false,0);
            Assert.That(CanonicalBombLifecycle.AfterStep(timer,false,8),Is.SameAs(timer));
            timer = CanonicalBombLifecycle.AfterStep(timer,true,8); Assert.That(timer.Active,Is.True); Assert.That(timer.RemainingSeconds,Is.EqualTo(8));
            timer = CanonicalBombLifecycle.AfterStep(timer,false,8); Assert.That(timer.RemainingSeconds,Is.EqualTo(7.98f).Within(0.00001f));
            timer = CanonicalBombLifecycle.AfterStep(timer,true,8); Assert.That(timer.RemainingSeconds,Is.EqualTo(7.96f).Within(0.00001f));
        }
        [Test]
        public void DirectDetonationTransition_RetiresBombAndTargetingHoldInOneOutcome()
        {
            var world = HandbookConformanceFixture.Create(out var ids); var host = new CanonicalSimulationHost(world);
            Motion(world,world.View.Body(ids.Bomb).WithMotion(new Vector2(2,1.7f),0,Vector2.zero,0).WithCountdown(new BombCountdown(true,2)));
            Assert.That(host.TryHold(new HoldRequest(ids.Participant,ids.Character,LimbSlot.LeftHand,ids.Bomb,new Vector2(0,-0.25f),1),out var hold,out var error),Is.True,error);
            CanonicalWorldView observed = null; world.Committed += _ => observed = world.View;
            Assert.That(host.TryDetonate(ids.Bomb,out error),Is.True,error);
            Assert.That(world.Contains(ids.Bomb),Is.False); Assert.That(observed.Holds.Any(h => h.Target == ids.Bomb),Is.False);
            Assert.That(world.View.Body(ids.Character).IsCharacter,Is.False); Assert.That(host.LastStructuralCommit.NotificationErrors,Is.Empty);
        }
        [Test]
        public void TwoSublethalDirectBlastTransitions_DoNotAccumulateDamage()
        {
            var original = HandbookConformanceFixture.Create(out var ids);
            var definitions = original.Definitions.Export();
            definitions.Single(d => d.kind == DefinitionKind.Bomb).blastPower = 0.5f;
            var defs = new DefinitionSet(definitions);
            var world = new CanonicalMaterialWorld(new SequentialMaterialEntityIdAllocator("lethality-"),defs);
            Assert.That(world.TryReserveEntityIds(3,out var reservation,out var error),Is.True,error);
            var character = original.View.Body(ids.Character).WithGeometry(reservation.Ids[0],original.View.Body(ids.Character).Shape,1,Vector2.zero,0,CanonicalBodyMode.Dynamic)
                .WithMotion(Vector2.zero,0,Vector2.zero,0);
            var bomb = new CanonicalMaterialState(reservation.Ids[1],original.View.Body(ids.Bomb).Shape,1,new Vector2(0,1),0,Vector2.zero,0,CanonicalBodyMode.Dynamic,
                HandbookConformanceFixture.Selection(defs,"bomb","indestructible","bomb",DefinitionKind.Bomb,"fixture-bomb"),new BombCountdown(true,0));
            var participant = new CanonicalParticipant(reservation.Ids[2],character.Id);
            Commit(world,new CanonicalWorldView(new[] { character,bomb },participants:new[] { participant }),reservation);
            var host = new CanonicalSimulationHost(world);
            Assert.That(host.TryDetonate(bomb.Id,out error),Is.True,error);
            Assert.That(world.View.Body(character.Id).IsCharacter,Is.True);
            Assert.That(world.TryReserveEntityIds(1,out reservation,out error),Is.True,error);
            var nextBomb = bomb.WithGeometry(reservation.Ids[0],bomb.Shape,1,Vector2.zero,0,CanonicalBodyMode.Dynamic);
            Commit(world,new CanonicalWorldView(world.View.Bodies.Concat(new[] { nextBomb }),participants:world.View.Participants),reservation);
            Assert.That(host.TryDetonate(nextBomb.Id,out error),Is.True,error);
            Assert.That(world.View.Body(character.Id).IsCharacter,Is.True); Assert.That(world.View.Participants.Single().ControlledBody,Is.EqualTo(character.Id));
        }
        [Test]
        public void SameIdDeath_InstallsDefinitionSettings_ClearsControlAndOutgoingHolds_PreservesIncomingHold()
        {
            var world = HandbookConformanceFixture.Create(out var ids);
            Assert.That(world.TryReserveEntityIds(3,out var reservation,out var error),Is.True,error);
            var other = world.View.Body(ids.Character).WithGeometry(reservation.Ids[0],world.View.Body(ids.Character).Shape,1,Vector2.zero,0,CanonicalBodyMode.Dynamic)
                .WithMotion(new Vector2(2,0),0,Vector2.zero,0);
            var incoming = new CanonicalHold(reservation.Ids[1],other.Id,LimbSlot.LeftHand,ids.Character,new Vector2(0,-0.4f));
            Commit(world,new CanonicalWorldView(world.View.Bodies.Concat(new[] { other }),world.View.Connectors,world.View.Holds.Concat(new[] { incoming }),
                world.View.Participants.Concat(new[] { new CanonicalParticipant(reservation.Ids[2],other.Id) })),reservation);
            var original = world.View.Body(ids.Character); var character = world.Definitions.Resolve(original.Selection.Role);
            var host = new CanonicalSimulationHost(world); Assert.That(host.TryDeath(ids.Character,out error),Is.True,error);
            var corpse = world.View.Body(ids.Character);
            Assert.That(corpse.IsCharacter,Is.False); Assert.That(corpse.Shape,Is.SameAs(original.Shape)); Assert.That(corpse.Position,Is.EqualTo(original.Position));
            Assert.That(corpse.Selection.Material,Is.EqualTo(character.corpseMaterial)); Assert.That(corpse.Selection.Response,Is.EqualTo(character.corpseResponse));
            Assert.That(corpse.Selection.Appearance,Is.EqualTo(character.corpseAppearance)); Assert.That(corpse.Selection.Role,Is.EqualTo(character.corpseRole));
            Assert.That(world.View.Participants.Single(p => p.Id == ids.Participant).ControlledBody.IsValid,Is.False);
            Assert.That(world.View.Holds.Single().Id,Is.EqualTo(incoming.Id)); Assert.That(world.Definitions.Resolve(corpse.Selection.Role).holdEligible,Is.False);
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(Bytes(world),out var recovered,out error),Is.True,error);
            Assert.That(recovered.View.Body(ids.Character).IsCharacter,Is.False); Assert.That(recovered.View.Holds.Single().Id,Is.EqualTo(incoming.Id));
        }
        [Test]
        public void CorpseRecovery_DoesNotRequireFormerCharacterStateOrDefinition()
        {
            var world = HandbookConformanceFixture.Create(out var ids); Assert.That(new CanonicalSimulationHost(world).TryDeath(ids.Character,out var error),Is.True,error);
            string json = Bytes(world); Assert.That(json,Does.Not.Contain("fixture-claymate"));
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(json,out var recovered,out error),Is.True,error); Assert.That(recovered.Contains(ids.Character),Is.True);
        }
        [Test]
        public void RecoveryRoundTrip_PreservesCurrentGraphDefinitionsMotionTimerAndAllocatorWithoutParentHistory()
        {
            var world = HandbookConformanceFixture.Create(out var ids);
            Motion(world,world.View.Body(ids.Bomb).WithMotion(new Vector2(-1.5f,4),0.3f,new Vector2(1.2f,-0.4f),0.7f).WithCountdown(new BombCountdown(true,6.5f)));
            Cut(world,ids.Platform,Rect(-0.25f,2.4f,0.25f,3.6f)); string json = Bytes(world);
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(json,out var recovered,out var error),Is.True,error);
            Assert.That(Bytes(recovered),Is.EqualTo(json)); Assert.That(recovered.View.Body(ids.Bomb).Countdown.RemainingSeconds,Is.EqualTo(6.5f));
            Assert.That(recovered.TryReserveEntityIds(1,out var reservation,out error),Is.True,error);
            Assert.That(reservation.Ids[0].Value,Is.EqualTo("match-000000000000000A")); recovered.IdAllocator.Cancel(reservation);
        }
        [Test]
        public void RecoveryRejectsMissingChangedDefinitionsUnsupportedSchemaAndInvalidHighWater()
        {
            var world = HandbookConformanceFixture.Create(out var ids); string json = Bytes(world);
            var changed = Regex.Replace(json,"(\"kind\":0,\"id\":\"terrain\",\"density\":)2(?:\\.0)?", "${1}7.0");
            Assert.That(changed,Is.Not.EqualTo(json)); Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(changed,out var rejected,out _),Is.False); Assert.That(rejected,Is.Null);
            var missing = new DefinitionSet(world.Definitions.Export().Where(s => s.kind != DefinitionKind.Material || s.id != "terrain"));
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(json,out rejected,out _,missing),Is.False); Assert.That(rejected,Is.Null);
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(json.Replace("\"schemaVersion\":2","\"schemaVersion\":1"),out _,out _),Is.False);
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(json.Replace("\"nextEntitySequence\":\"8\"","\"nextEntitySequence\":\"1\""),out _,out _),Is.False);
        }
        [Test]
        public void InvalidOverlappingOrDisconnectedShapes_AreRejected()
        {
            Assert.That(HandbookConformanceFixture.Shape(Rect(0,0,2,2),Rect(1,1,3,3)).TryValidate(out _),Is.False);
            Assert.That(HandbookConformanceFixture.Shape(Rect(0,0,1,1),Rect(2,0,3,1)).TryValidate(out _),Is.False);
            Assert.That(HandbookConformanceFixture.Shape(Rect(0,0,1,1),Rect(1,0,2,1)).TryValidate(out _),Is.True);
        }
        private static CanonicalMaterialWorld TwinBars(out MaterialEntityId a,out MaterialEntityId b,out MaterialEntityId connector)
        {
            var defs = HandbookConformanceFixture.Definitions(); var world = new CanonicalMaterialWorld(new SequentialMaterialEntityIdAllocator("twin-"),defs);
            Assert.That(world.TryReserveEntityIds(3,out var reservation,out var error),Is.True,error);
            a = reservation.Ids[0]; b = reservation.Ids[1]; connector = reservation.Ids[2];
            var selection = HandbookConformanceFixture.Selection(defs,"terrain","convex-subtraction","terrain",DefinitionKind.Environment,"platform");
            var shape = HandbookConformanceFixture.Shape(Rect(-3,-0.5f,3,0.5f));
            var bodies = new[] { new CanonicalMaterialState(a,shape,1,new Vector2(0,3),0,Vector2.zero,0,CanonicalBodyMode.Dynamic,selection),
                new CanonicalMaterialState(b,shape,1,new Vector2(0,4),0,Vector2.zero,0,CanonicalBodyMode.Dynamic,selection) };
            Commit(world,new CanonicalWorldView(bodies,new[] { new CanonicalConnector(connector,a,b,new Vector2(-2,0.5f),new Vector2(2,0.5f),
                new Vector2(-2,-0.5f),new Vector2(2,-0.5f),100,0.5f,4) }),reservation); return world;
        }
        private static IReadOnlyDictionary<MaterialEntityId,IReadOnlyList<CanonicalMaterialState>> EvaluatedReplacements(CanonicalMaterialWorld world,
            IEnumerable<MaterialEntityId> sources,CanonicalPolygon2D cutter)
        {
            var replacements = new Dictionary<MaterialEntityId,IReadOnlyList<CanonicalMaterialState>>();
            foreach (var id in sources)
            {
                var source = world.View.Body(id); var request = new DestructionRequest(id,cutter,Vector2.zero,0);
                var evaluation = new ConvexSubtractionGeometryEvaluator().Evaluate(source,request); Assert.That(evaluation.Succeeded,Is.True,evaluation.Error);
                replacements.Add(id,evaluation.ConnectedResults.Select((shape,i) => new PreserveMotionAndApplyBlastPolicy().BuildResult(source,
                    evaluation.ConnectedResults.Count == 1 ? id : new MaterialEntityId("supplied-" + i),shape,1,request)).ToArray());
            }
            return replacements;
        }
        private sealed class RejectProjection : ICanonicalWorldProjection
        { public bool TryPrepare(CanonicalWorldView view,DefinitionSet definitions,out IPreparedCanonicalProjection prepared,out string error)
            { prepared = null; error = "injected preparation rejection"; return false; } }
        private sealed class ThrowingPolicy : IDestructionResultStatePolicy
        { public CanonicalMaterialState BuildResult(CanonicalMaterialState source,MaterialEntityId id,CanonicalMaterialShape shape,uint revision,DestructionRequest request)
            => throw new InvalidOperationException("injected one-result failure"); }
    }
}
