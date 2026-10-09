using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Bomb.CanonicalDestruction;
using NUnit.Framework;
using UnityEngine;

namespace Bomb.Tests.EditMode
{
    public sealed class BlastConformanceTests
    {
        private static CanonicalMaterialShape Rect(float x0, float y0, float x1, float y1)
            => HandbookConformanceFixture.Shape(HandbookConformanceFixture.Rectangle(x0,y0,x1,y1));
        private static MaterialEntityId Id(int n) => BlastConformanceFixture.Id(n);
        private static CanonicalMaterialState Bomb(DefinitionSet definitions, int id = 1, Vector2 position = default)
            => BlastConformanceFixture.Body(definitions,Id(id),Rect(-0.1f,-0.1f,0.1f,0.1f),"bomb",position,
                kind:DefinitionKind.Bomb,response:"indestructible");
        private static CanonicalMaterialState Character(DefinitionSet definitions, int id, float x0, float y0, float x1, float y1)
            => BlastConformanceFixture.Body(definitions,Id(id),Rect(x0,y0,x1,y1),"clay",
                kind:DefinitionKind.Character,response:"indestructible");
        private static void Evidence(string name, string contents)
        {
            var dir = Path.GetFullPath(Path.Combine(Application.dataPath,"../Docs/BlastConformanceEvidence/2026-10-09-revision-1/states"));
            Directory.CreateDirectory(dir); File.WriteAllText(Path.Combine(dir,name),contents);
        }
        private static void Detonate(CanonicalMaterialWorld world, MaterialEntityId bomb, string name)
        {
            Evidence(name+"-before.json",CanonicalMaterialSnapshotCodec.Serialize(world,true));
            string before = CanonicalMaterialSnapshotCodec.Serialize(world);
            var host = new CanonicalSimulationHost(world);
            bool ok = host.TryDetonate(bomb,out var error);
            Evidence(name+"-outcome.txt","accepted="+ok+"\nerror="+error+"\n"+JsonUtility.ToJson(host.LastBlastDiagnostics));
            Evidence(name+"-after.json",CanonicalMaterialSnapshotCodec.Serialize(world,true));
            if (!ok) Assert.That(CanonicalMaterialSnapshotCodec.Serialize(world),Is.EqualTo(before),"Rejected blast must not publish or allocate.");
            Assert.That(ok,Is.True,error);
            Assert.That(host.LastStructuralCommit.NotificationErrors,Is.Empty);
        }
        // Measurement uses independent half-plane/ray clipping of the actual published
        // geometry, not the evaluator's interval or reported penetration calculation.
        private static List<(double lo,double hi)> Intervals(IEnumerable<CanonicalMaterialState> bodies, Vector2 origin, double angle)
        {
            double dx=Math.Cos(angle),dy=Math.Sin(angle); var spans=new List<(double lo,double hi)>();
            foreach(var body in bodies) foreach(var cell in body.Shape.Cells)
            {
                double lo=0,hi=double.PositiveInfinity; bool miss=false;
                var points=cell.Vertices.Select(body.ToWorld).ToArray();
                for(int i=0;i<points.Length;i++)
                {
                    var a=points[i]-origin; var e=points[(i+1)%points.Length]-points[i];
                    double den=e.x*dy-e.y*dx,h=e.x*(double)a.y-e.y*(double)a.x;
                    if(Math.Abs(den)<1e-14) { if(h>1e-12) miss=true; continue; }
                    if(den>0) lo=Math.Max(lo,h/den); else hi=Math.Min(hi,h/den);
                }
                if(!miss&&hi>lo+1e-9) spans.Add((lo,hi));
            }
            spans.Sort((a,b)=>a.lo.CompareTo(b.lo)); var merged=new List<(double lo,double hi)>();
            foreach(var s in spans)
                if(merged.Count==0||s.lo>merged[merged.Count-1].hi+1e-7) merged.Add(s);
                else merged[merged.Count-1]=(merged[merged.Count-1].lo,Math.Max(merged[merged.Count-1].hi,s.hi));
            return merged;
        }
        [TestCase(0.25f)] [TestCase(0.75f)] [TestCase(5f)] [TestCase(10f)]
        public void EmptySpace_IndependentCircleBound(float radius)
        {
            var definitions=BlastConformanceFixture.Definitions(radius);
            var world=BlastConformanceFixture.World(definitions,new[]{Bomb(definitions)});
            Assert.That(BoundedBlastEvaluator.TryCreate(world,world.View.Body(Id(1)),out var field,out var error),Is.True,error);
            double maxDeficit=0;
            for(int i=0;i<10001;i++)
            {
                double reach=field.RepresentedReach(i*Math.PI*2/10001);
                Assert.That(reach,Is.LessThanOrEqualTo(radius+1e-10)); maxDeficit=Math.Max(maxDeficit,radius-reach);
            }
            Assert.That(maxDeficit,Is.LessThanOrEqualTo(0.001));
            Assert.That(field.Diagnostics.maximumReachEnclosure,Is.LessThanOrEqualTo(0.001-BoundedBlastEvaluator.FloatAllowance));
            Evidence("empty-"+radius+".txt","measuredDeficit="+maxDeficit.ToString("R")+"\n"+JsonUtility.ToJson(field.Diagnostics));
            Detonate(world,Id(1),"empty-host-"+radius);
            Assert.That(world.Count,Is.Zero);
        }
        [TestCase(5f,0f)] [TestCase(8f,0f)] [TestCase(5f,17f)] [TestCase(8f,37f)] [TestCase(8f,90f)]
        public void WideLayers_ActualGeometryMatchesIndependentCentralAndOffAxisExpectations(float radius,float degrees)
        {
            float rotation=degrees*Mathf.Deg2Rad; var translation=new Vector2(12,-9);
            var world=BlastConformanceFixture.Layers(radius,out var bomb,out var cover,out var core,rotation,translation);
            Detonate(world,bomb,"layers-"+radius+"-"+degrees);
            var coverBodies=world.View.Bodies.Where(b=>b.Selection.Material.id=="cover").ToArray();
            var coreBodies=world.View.Bodies.Where(b=>b.Selection.Material.id=="core").ToArray();
            foreach(double theta in new[]{0d,10*Math.PI/180,20*Math.PI/180,30*Math.PI/180})
            {
                var c=Intervals(coverBodies,translation,rotation+theta); var k=Intervals(coreBodies,translation,rotation+theta);
                double cosine=Math.Cos(theta);
                if(radius==5)
                {
                    double expected=1+0.8/cosine;
                    Assert.That(c[0].lo,Is.InRange(expected-0.001,expected));
                    Assert.That(c[0].hi,Is.EqualTo(2/cosine).Within(0.00005));
                    Assert.That(k[0].lo,Is.EqualTo(2/cosine).Within(0.00005));
                }
                else
                {
                    Assert.That(c,Is.Empty,"Cover must be fully breached before core removal.");
                    Assert.That(k[0].lo,Is.InRange(4-1/cosine-0.001,4-1/cosine));
                }
            }
            if(radius==5) Assert.That(world.View.Body(core).GeometryRevision,Is.EqualTo(1));
            else
            {
                Assert.That(world.Contains(cover),Is.False); Assert.That(coverBodies,Has.Length.EqualTo(2));
                Assert.That(world.Contains(core),Is.True); Assert.That(coreBodies,Has.Length.EqualTo(1));
                Assert.That(coreBodies[0].Mass(world.Definitions),Is.EqualTo(3*coreBodies[0].Shape.Area));
                foreach(var body in coverBodies) Assert.That(body.Mass(world.Definitions),Is.EqualTo(2*body.Shape.Area));
            }
        }
        [Test]
        public void WideLayers_ShieldCharacterAndRebuildResistance()
        {
            var original=BlastConformanceFixture.Layers(8,out var bomb,out _,out _);
            var definitions=original.Definitions;
            var world=BlastConformanceFixture.World(definitions,original.View.Bodies.Concat(new[]{Character(definitions,4,4.1f,-0.1f,4.3f,0.1f)}));
            string before=CanonicalMaterialSnapshotCodec.Serialize(world);
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(before,out var recovered,out var error),Is.True,error);
            Assert.That(recovered.Definitions.Reference(DefinitionKind.Material,"cover"),Is.EqualTo(definitions.Reference(DefinitionKind.Material,"cover")));
            Detonate(recovered,bomb,"shielded-character");
            Assert.That(recovered.View.Body(Id(4)).IsCharacter,Is.True,"All direct paths cost at least 10.1 m.");
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(CanonicalMaterialSnapshotCodec.Serialize(recovered),out var again,out error),Is.True,error);
            Assert.That(again.Definitions.Resolve(again.View.Body(Id(3)).Selection.Material).blastResistance,Is.EqualTo(1));
        }
        [Test]
        public void OriginalCoverCost_AndTargetOrder_ArePreserved()
        {
            var a=BlastConformanceFixture.Layers(8,out var bomb,out _,out var core);
            var b=BlastConformanceFixture.World(a.Definitions,a.View.Bodies.Reverse());
            Detonate(a,bomb,"forward-order"); Detonate(b,bomb,"reverse-order");
            Assert.That(CanonicalMaterialSnapshotCodec.Serialize(a),Is.EqualTo(CanonicalMaterialSnapshotCodec.Serialize(b)));
            Assert.That(Intervals(new[]{a.View.Body(core)},Vector2.zero,0)[0].lo,Is.InRange(2.999d,3d));
        }
        [Test]
        public void IndestructibleCover_BlocksCarvingAndCharacterExposure()
        {
            var defs=BlastConformanceFixture.Definitions(5);
            var cover=BlastConformanceFixture.Body(defs,Id(2),Rect(1,-6,2,6),"cover",response:"indestructible");
            var core=BlastConformanceFixture.Body(defs,Id(3),Rect(2,-1,3,1),"core");
            var world=BlastConformanceFixture.World(defs,new[]{Bomb(defs),cover,core,Character(defs,4,3.2f,-0.1f,3.4f,0.1f)});
            Detonate(world,Id(1),"opaque");
            Assert.That(world.View.Body(Id(2)).Shape,Is.SameAs(cover.Shape)); Assert.That(world.View.Body(Id(3)).Shape,Is.SameAs(core.Shape));
            Assert.That(world.View.Body(Id(4)).IsCharacter,Is.True);
        }
        [Test]
        public void BoundedOpaqueBarrier_ShieldsActualCoreGeometryAndCharacter()
        {
            var defs=BlastConformanceFixture.Definitions(0.75f);
            var cover=BlastConformanceFixture.Body(defs,Id(2),Rect(0.4f,-1,0.5f,1),"cover",response:"indestructible");
            var core=BlastConformanceFixture.Body(defs,Id(3),Rect(0.5f,-0.04f,0.55f,0.04f),"core");
            var character=Character(defs,4,0.6f,-0.02f,0.65f,0.02f);
            var world=BlastConformanceFixture.World(defs,new[]{Bomb(defs),cover,core,character});
            Detonate(world,Id(1),"bounded-opaque");
            Assert.That(world.View.Body(Id(2)).Shape,Is.SameAs(cover.Shape));
            Assert.That(world.View.Body(Id(3)).Shape,Is.SameAs(core.Shape));
            Assert.That(world.View.Body(Id(4)).IsCharacter,Is.True); Assert.That(world.View.Body(Id(4)).Shape,Is.SameAs(character.Shape));
        }
        [Test]
        public void PureTangentCharacterExposure_IsRejectedWithoutChoosingBoundaryLethality()
        {
            var defs=BlastConformanceFixture.Definitions(0.75f);
            var world=BlastConformanceFixture.World(defs,new[]{Bomb(defs),Character(defs,2,0.75f,-0.1f,0.77f,0.1f)});
            string before=CanonicalMaterialSnapshotCodec.Serialize(world);
            Assert.That(new CanonicalSimulationHost(world).TryDetonate(Id(1),out var error),Is.False);
            Assert.That(error,Does.Contain("unresolved boundary contact"));
            Assert.That(CanonicalMaterialSnapshotCodec.Serialize(world),Is.EqualTo(before));
        }
        [Test]
        public void ExposedDeath_PreservesShapeAndIncomingHold_ThenNextBlastCarvesCorpse()
        {
            var defs=BlastConformanceFixture.Definitions(0.75f);
            var killed=Character(defs,2,0.4f,-0.1f,0.6f,0.1f);
            var survivor=Character(defs,3,2,-0.1f,2.2f,0.1f);
            var terrain=BlastConformanceFixture.Body(defs,Id(4),Rect(1.1f,-0.1f,1.3f,0.1f),"core");
            var outgoing=new CanonicalHold(Id(5),Id(2),LimbSlot.RightHand,Id(4),new Vector2(1.1f,0));
            var incoming=new CanonicalHold(Id(6),Id(3),LimbSlot.LeftHand,Id(2),new Vector2(0.6f,0));
            var world=BlastConformanceFixture.World(defs,new[]{Bomb(defs),killed,survivor,terrain,Bomb(defs,8,new Vector2(0,0.15f))},
                holds:new[]{outgoing,incoming},participants:new[]{new CanonicalParticipant(Id(7),Id(2))});
            Detonate(world,Id(1),"death");
            var corpse=world.View.Body(Id(2)); Assert.That(corpse.IsCharacter,Is.False); Assert.That(corpse.Shape,Is.SameAs(killed.Shape));
            Assert.That(corpse.Id,Is.EqualTo(killed.Id)); Assert.That(corpse.Selection.Role.id,Is.EqualTo("corpse"));
            Assert.That(world.View.Participants.Single().ControlledBody.IsValid,Is.False);
            Assert.That(world.View.Holds.Select(h=>h.Id),Is.EqualTo(new[]{incoming.Id}));
            string snapshot=CanonicalMaterialSnapshotCodec.Serialize(world);
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(snapshot,out var recovered,out var error),Is.True,error);
            Detonate(recovered,Id(8),"next-blast"); Assert.That(recovered.Contains(Id(2)),Is.False);
        }
        [TestCase(0f)] [TestCase(37f)]
        public void NarrowLayer_IsNotMissedBetweenUniformRays(float degrees)
        {
            var defs=BlastConformanceFixture.Definitions(5);
            var blocker=BlastConformanceFixture.Body(defs,Id(2),Rect(-0.01f,-0.01f,0.01f,0.01f),"narrow",new Vector2(3.01f,0),degrees*Mathf.Deg2Rad);
            var target=BlastConformanceFixture.Body(defs,Id(3),Rect(4.5f,-0.02f,5.1f,0.02f),"clay");
            var world=BlastConformanceFixture.World(defs,new[]{Bomb(defs),blocker,target});
            Detonate(world,Id(1),"narrow-"+degrees);
            double expected=5-0.32/Math.Cos(degrees*Math.PI/180);
            var span=Intervals(world.View.Bodies.Where(b=>b.Selection.Material.id=="clay"),Vector2.zero,0).Single();
            Assert.That(span.lo,Is.InRange(expected-0.001,expected));
        }
        [Test]
        public void ThinUnbreachedLayer_DoesNotLeaveBuriedCoreCut()
        {
            var defs=BlastConformanceFixture.Definitions(1.05f);
            var world=BlastConformanceFixture.World(defs,new[]{Bomb(defs),
                BlastConformanceFixture.Body(defs,Id(2),Rect(1,-1,1.02f,1),"cover"),
                BlastConformanceFixture.Body(defs,Id(3),Rect(1.02f,-1,1.5f,1),"core")});
            Detonate(world,Id(1),"thin");
            var surviving=Intervals(new[]{world.View.Body(Id(2))},Vector2.zero,0)[0];
            Assert.That(surviving.lo,Is.InRange(1.009,1.01));
            Assert.That(surviving.hi-surviving.lo,Is.GreaterThanOrEqualTo(0.01-0.0000001));
            Assert.That(world.View.Body(Id(3)).GeometryRevision,Is.EqualTo(1));
        }
        [Test]
        public void Cavity_ChargesAirGapOnceAndEachMaterialLayer()
        {
            var defs=BlastConformanceFixture.Definitions(5);
            var shell=HandbookConformanceFixture.Shape(HandbookConformanceFixture.Rectangle(1,-1,2,1),
                HandbookConformanceFixture.Rectangle(2,-1,3,-0.5f),HandbookConformanceFixture.Rectangle(2,0.5f,3,1),
                HandbookConformanceFixture.Rectangle(3,-1,4,1));
            var world=BlastConformanceFixture.World(defs,new[]{Bomb(defs),BlastConformanceFixture.Body(defs,Id(2),shell,"core")});
            Detonate(world,Id(1),"cavity");
            Assert.That(Intervals(world.View.Bodies,Vector2.zero,0).Single().lo,Is.InRange(3.499,3.5));
        }
        [Test]
        public void CoveredCorner_DoesNotWrapAlongShorterAirRoute()
        {
            var defs=BlastConformanceFixture.Definitions(7);
            var corner=HandbookConformanceFixture.Shape(HandbookConformanceFixture.Rectangle(1,-1,2,3),HandbookConformanceFixture.Rectangle(2,2,4,3));
            var exposed=Character(defs,4,0.4f,-2.1f,0.6f,-1.9f);
            var world=BlastConformanceFixture.World(defs,new[]{Bomb(defs),BlastConformanceFixture.Body(defs,Id(2),corner,"cover"),Character(defs,3,3.4f,1.4f,3.6f,1.6f),exposed});
            Detonate(world,Id(1),"corner"); Assert.That(world.View.Body(Id(3)).IsCharacter,Is.True,"Minimum straight cost >8.0027, while the bent air route is <5.5743.");
            Assert.That(world.View.Body(Id(4)).IsCharacter,Is.False); Assert.That(world.View.Body(Id(4)).Shape,Is.SameAs(exposed.Shape));
        }
        [Test]
        public void ActualRetainedLayerBelowOneMillimetre_StillRejectsBuriedRemoval()
        {
            var world=BlastConformanceFixture.Layers(8,out var bomb,out var cover,out var core);
            Assert.That(BoundedBlastEvaluator.TryCreate(world,world.View.Body(bomb),out var field,out var error),Is.True,error);
            var policy=new PreserveMotionAndApplyBlastPolicy();
            CanonicalMaterialState Result(MaterialEntityId id,CanonicalMaterialShape shape)=>policy.BuildResult(world.View.Body(id),id,shape,2,
                new DestructionRequest(id,null,Vector2.zero,0));
            var replacements=new Dictionary<MaterialEntityId,IReadOnlyList<CanonicalMaterialState>>{
                [cover]=new[]{Result(cover,Rect(1.99998f,-6,2,6))},[core]=new[]{Result(core,Rect(3,-6,4,6))}};
            string before=CanonicalMaterialSnapshotCodec.Serialize(world);
            Assert.That(field.TryValidateRemoval(replacements,out error),Is.False); Assert.That(error,Does.Contain("retains intervening"));
            Assert.That(CanonicalMaterialSnapshotCodec.Serialize(world),Is.EqualTo(before));
        }
        [Test]
        public void UnrepresentableAuthoredMinimum_RejectsBeforePublicationOrAllocation()
        {
            var defs=BlastConformanceFixture.Definitions(0.75f);
            var world=BlastConformanceFixture.World(defs,new[]{Bomb(defs),BlastConformanceFixture.Body(defs,Id(2),Rect(0.7f,-0.02f,0.9f,0.02f),"clay",response:"convex-subtraction")});
            string before=CanonicalMaterialSnapshotCodec.Serialize(world); int publications=0; world.Committed+=_=>publications++;
            var host=new CanonicalSimulationHost(world);
            Assert.That(host.TryDetonate(Id(1),out var error),Is.False); Assert.That(error,Does.Contain("retained cell"));
            Assert.That(CanonicalMaterialSnapshotCodec.Serialize(world),Is.EqualTo(before)); Assert.That(publications,Is.Zero);
            Evidence("authored-minimum-rejection-before.json",before); Evidence("authored-minimum-rejection-after.json",CanonicalMaterialSnapshotCodec.Serialize(world));
            Evidence("authored-minimum-rejection.txt",error);
        }
        [Test]
        public void LayeredRecovery_AndIndependentNextBlast_HaveNoFrameInducedOverlap()
        {
            var world=BlastConformanceFixture.Layers(8,out var bomb,out _,out _,37*Mathf.Deg2Rad,new Vector2(12,-9));
            Detonate(world,bomb,"recovered-layer-first");
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(CanonicalMaterialSnapshotCodec.Serialize(world),out var recovered,out var error),Is.True,error);
            // Spawning uses the fixture's authored catalog; the second recovery bundle
            // supplies the new current bomb's dependencies, not its retired predecessor.
            Assert.That(world.TryReserveEntityIds(1,out var reservation,out error),Is.True,error);
            var next=BlastConformanceFixture.Body(world.Definitions,reservation.Ids.Single(),Rect(-0.1f,-0.1f,0.1f,0.1f),"bomb",new Vector2(12,-9),
                kind:DefinitionKind.Bomb,response:"indestructible");
            Assert.That(world.TryCommit(new StructuralMutationPlan(world.Generation,new CanonicalWorldView(world.View.Bodies.Concat(new[]{next})),reservation),out _,out error),Is.True,error);
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(CanonicalMaterialSnapshotCodec.Serialize(world),out recovered,out error),Is.True,error);
            Detonate(recovered,next.Id,"recovered-layer-next");
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(CanonicalMaterialSnapshotCodec.Serialize(recovered),out _,out error),Is.True,error);
        }
        [Test]
        public void OriginalCellEnumeration_DoesNotChangeCavityRemoval()
        {
            var defs=BlastConformanceFixture.Definitions(5);
            var cells=new[]{HandbookConformanceFixture.Rectangle(1,-1,2,1),HandbookConformanceFixture.Rectangle(2,-1,3,-0.5f),
                HandbookConformanceFixture.Rectangle(2,0.5f,3,1),HandbookConformanceFixture.Rectangle(3,-1,4,1)};
            var a=BlastConformanceFixture.World(defs,new[]{Bomb(defs),BlastConformanceFixture.Body(defs,Id(2),new CanonicalMaterialShape(cells),"core")});
            var b=BlastConformanceFixture.World(defs,new[]{Bomb(defs),BlastConformanceFixture.Body(defs,Id(2),new CanonicalMaterialShape(cells.Reverse()),"core")});
            Detonate(a,Id(1),"cavity-forward-cells"); Detonate(b,Id(1),"cavity-reverse-cells");
            for(int i=0;i<1001;i++)
            {
                double angle=2*Math.PI*(i+0.5)/1001;
                var ai=Intervals(a.View.Bodies,Vector2.zero,angle);var bi=Intervals(b.View.Bodies,Vector2.zero,angle);
                Assert.That(ai.Count,Is.EqualTo(bi.Count));
                for(int j=0;j<ai.Count;j++) { Assert.That(ai[j].lo,Is.EqualTo(bi[j].lo).Within(0.000002)); Assert.That(ai[j].hi,Is.EqualTo(bi[j].hi).Within(0.000002)); }
            }
        }
        [Test]
        public void FullLayeredResult_UsesRealPlannerForMotionConnectorsAndHeldPoints()
        {
            var original=BlastConformanceFixture.Layers(8,out var bomb,out var cover,out var core);
            var defs=original.Definitions;
            var source=original.View.Body(cover).WithMotion(Vector2.zero,0,new Vector2(2,-1),1.25f);
            var bodies=original.View.Bodies.Select(b=>b.Id==cover?source:b).Concat(new[]{Character(defs,4,-12,-0.1f,-11.8f,0.1f)});
            var connectors=new[]{
                new CanonicalConnector(Id(6),cover,core,new Vector2(2,-4),new Vector2(2,4),new Vector2(2,-4),new Vector2(2,4),1000,0.6f,8),
                new CanonicalConnector(Id(7),cover,core,new Vector2(2,-4),new Vector2(2,4),new Vector2(2,-4),new Vector2(2,4),1000,0.4f,8)};
            var holds=new[]{new CanonicalHold(Id(8),Id(4),LimbSlot.LeftHand,cover,new Vector2(1,0)),
                new CanonicalHold(Id(9),Id(4),LimbSlot.RightHand,cover,new Vector2(2,5))};
            var world=BlastConformanceFixture.World(defs,bodies,connectors,holds,new[]{new CanonicalParticipant(Id(5),Id(4))});
            int publications=0; world.Committed+=_=>publications++;
            Detonate(world,bomb,"complete-planner"); Assert.That(publications,Is.EqualTo(1));
            Assert.That(world.Contains(cover),Is.False); Assert.That(world.Contains(core),Is.True);
            Assert.That(world.View.Connectors,Has.Count.EqualTo(2));
            Assert.That(world.View.Connectors.All(c=>c.Id!=Id(6)&&c.Id!=Id(7)&&c.MinimumRemainingFraction==0.4f
                &&Mathf.Abs(c.ReferenceLength-c.AttachedLength)<0.00005f),Is.True);
            Assert.That(world.View.Holds,Has.Count.EqualTo(1)); var held=world.View.Holds.Single(); Assert.That(held.Id,Is.EqualTo(Id(9)));
            Assert.That(Vector2.Distance(world.View.Body(held.Target).ToWorld(held.HeldLocal),new Vector2(2,5)),Is.LessThan(0.00005f));
            foreach(var child in world.View.Bodies.Where(b=>b.Selection.Material.id=="cover"))
            {
                Assert.That(child.Selection,Is.EqualTo(source.Selection)); Assert.That(child.GeometryRevision,Is.EqualTo(1));
                double area=0;
                foreach(var cell in child.Shape.Cells)
                {
                    double twice=0;var vertices=cell.Vertices;
                    for(int i=0;i<vertices.Count;i++)twice+=vertices[i].x*(double)vertices[(i+1)%vertices.Count].y-vertices[i].y*(double)vertices[(i+1)%vertices.Count].x;
                    area+=Math.Abs(twice)/2;
                }
                Assert.That(child.Mass(defs),Is.EqualTo(2*area).Within(0.0001),"Authored cover density 2 times independently measured retained area.");
                var point=child.ToWorld(child.Shape.Cells[0].Vertices[0]);
                Vector2 Velocity(CanonicalMaterialState state)
                { var d=point-state.ToWorld(state.Shape.Centroid); return state.LinearVelocity+state.AngularVelocityRadians*new Vector2(-d.y,d.x); }
                Assert.That(Vector2.Distance(Velocity(child),Velocity(source)),Is.LessThan(0.0001f));
            }
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(CanonicalMaterialSnapshotCodec.Serialize(world),out var recovered,out var error),Is.True,error);
            Assert.That(recovered.Contains(cover),Is.False); Assert.That(recovered.View.Holds.Single().Id,Is.EqualTo(Id(9)));
        }
        [TestCase(false)] [TestCase(true)]
        public void UnsupportedOverlapOrEmbeddedOrigin_RejectsAtomically(bool embedded)
        {
            var defs=BlastConformanceFixture.Definitions(5);
            var world=BlastConformanceFixture.World(defs,new[]{Bomb(defs),
                BlastConformanceFixture.Body(defs,Id(2),embedded?Rect(-1,-1,1,1):Rect(1,-1,2,1),"cover"),
                BlastConformanceFixture.Body(defs,Id(3),Rect(1.5f,-1,3,1),"core")});
            string before=CanonicalMaterialSnapshotCodec.Serialize(world); var host=new CanonicalSimulationHost(world);
            Assert.That(host.TryDetonate(Id(1),out var error),Is.False); Assert.That(error,Does.Contain(embedded?"inside":"Overlapping"));
            Assert.That(CanonicalMaterialSnapshotCodec.Serialize(world),Is.EqualTo(before));
        }
        [Test]
        public void RecordedOpaqueSupportCorner_RejectsInsteadOfPublishingBuriedRemoval()
        {
            // The original 0.4 m live support produced this reachable float pose.
            // A rounded shadow edge would leave cover before a buried cover cut.
            // Keep that measured limitation visible as a strict atomic rejection.
            var specs=BlastConformanceFixture.Definitions(8).Export();
            specs.Single(s=>s.kind==DefinitionKind.Environment&&s.id=="platform").bodyMode=CanonicalBodyMode.Static;
            specs.Single(s=>s.kind==DefinitionKind.Character&&s.id=="fixture-claymate").bodyMode=CanonicalBodyMode.Static;
            var defs=new DefinitionSet(specs);
            var bomb=Bomb(defs,position:new Vector2(-0.000003744023615581682f,0.41500017046928408f));
            var floor=BlastConformanceFixture.Body(defs,Id(2),Rect(-0.2f,-0.5f,0.2f,0),"cover",response:"indestructible");
            var cover=BlastConformanceFixture.Body(defs,Id(3),Rect(1,-6,2,6),"cover");
            var core=BlastConformanceFixture.Body(defs,Id(4),Rect(2,-6,4,6),"core");
            var character=Character(defs,5,4.1f,0.3f,4.3f,0.5f);
            var world=BlastConformanceFixture.World(defs,new[]{bomb,floor,cover,core,character});
            string before=CanonicalMaterialSnapshotCodec.Serialize(world,true);int publications=0;
            world.Committed+=_=>publications++;
            var host=new CanonicalSimulationHost(world);
            Assert.That(host.TryDetonate(bomb.Id,out var error),Is.False);
            Assert.That(error,Does.Contain("retains intervening material"));
            Assert.That(CanonicalMaterialSnapshotCodec.Serialize(world,true),Is.EqualTo(before));
            Assert.That(publications,Is.Zero);
            Evidence("opaque-support-corner-before.json",before);
            Evidence("opaque-support-corner-after.json",CanonicalMaterialSnapshotCodec.Serialize(world,true));
            Evidence("opaque-support-corner-rejection.txt",error+"\n"+JsonUtility.ToJson(host.LastBlastDiagnostics));
        }
        [TestCase(-1f)] [TestCase(float.NaN)] [TestCase(float.PositiveInfinity)]
        public void InvalidResistance_IsRejected(float value)
        {
            var spec=new DefinitionSpec{kind=DefinitionKind.Material,id="invalid",density=1,hasBlastResistance=true,blastResistance=value};
            Assert.That(spec.TryValidate(out var error),Is.False); Assert.That(error,Does.Contain("blast resistance"));
        }
        [Test]
        public void Resistance_IsIndependentFrozenAuthoredInputAndRecoveryDependency()
        {
            var definitions=BlastConformanceFixture.Definitions(5);
            var specs=definitions.Export(); var material=specs.Single(s=>s.kind==DefinitionKind.Material&&s.id=="cover");
            material.density=11; var changed=new DefinitionSet(specs);
            material.blastResistance=15;
            Assert.That(changed.Resolve(changed.Reference(DefinitionKind.Material,"cover")).blastResistance,Is.EqualTo(4));
            Assert.That(changed.Resolve(changed.Reference(DefinitionKind.Material,"cover")).density,Is.EqualTo(11));
            Assert.That(definitions.Resolve(definitions.Reference(DefinitionKind.Material,"cover")).density,Is.EqualTo(2));
            var body=BlastConformanceFixture.Body(changed,Id(1),Rect(1,-1,2,1),"cover",response:"indestructible");
            var world=BlastConformanceFixture.World(changed,new[]{body});
            string bytes=CanonicalMaterialSnapshotCodec.Serialize(world);
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(bytes,out var recovered,out var error),Is.True,error);
            Assert.That(recovered.Definitions.Resolve(recovered.View.Body(Id(1)).Selection.Material).blastResistance,Is.EqualTo(4));
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(bytes,out _,out error,definitions),Is.False,"Changed authored dependency must not satisfy the old material hash.");
        }
        [Test]
        public void MissingResistanceAndHistoricalSchema_AreRejectedWithoutMigration()
        {
            var defs=BlastConformanceFixture.Definitions(5); var world=BlastConformanceFixture.World(defs,new[]{Bomb(defs)});
            string json=CanonicalMaterialSnapshotCodec.Serialize(world);
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(json.Replace("\"hasBlastResistance\":true","\"hasBlastResistance\":false"),out _,out var error),Is.False);
            Assert.That(error,Does.Contain("blast resistance"));
            Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(json.Replace("\"schemaVersion\":3","\"schemaVersion\":2"),out _,out error),Is.False);
            Assert.That(error,Does.Contain("schema"));
        }
    }
}
