using System;
using System.Collections;
using System.IO;
using System.Linq;
using Bomb.CanonicalDestruction;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace Bomb.Tests.PlayMode
{
    public sealed class BlastConformanceRuntimeTests
    {
        private static MaterialEntityId Id(int n)=>BlastConformanceFixture.Id(n);
        private static CanonicalMaterialShape Rect(float x0,float y0,float x1,float y1)
            =>HandbookConformanceFixture.Shape(HandbookConformanceFixture.Rectangle(x0,y0,x1,y1));
        private static void Evidence(string file,string contents)
        {
            var dir=Path.GetFullPath(Path.Combine(Application.dataPath,"../Docs/BlastConformanceEvidence/2026-10-09-revision-1/states"));
            Directory.CreateDirectory(dir); File.WriteAllText(Path.Combine(dir,file),contents);
        }
        [UnityTest]
        public IEnumerator SimultaneouslyExpiredBombs_CommitInBodyIdOrder_AndSecondCarvesNewCorpse()
        {
            var defs=BlastConformanceFixture.Definitions(0.75f);
            var first=BlastConformanceFixture.Body(defs,Id(1),Rect(-0.1f,-0.1f,0.1f,0.1f),"bomb",
                kind:DefinitionKind.Bomb,response:"indestructible").WithCountdown(new BombCountdown(true,0.01));
            var second=BlastConformanceFixture.Body(defs,Id(2),first.Shape,"bomb",new Vector2(0,0.3f),
                kind:DefinitionKind.Bomb,response:"indestructible").WithCountdown(new BombCountdown(true,0.01));
            var character=BlastConformanceFixture.Body(defs,Id(3),Rect(0.4f,-0.1f,0.6f,0.1f),"clay",
                kind:DefinitionKind.Character,response:"indestructible");
            var world=BlastConformanceFixture.World(defs,new[]{second,character,first});
            var runtime=new CanonicalWorldRuntime2D();
            try
            {
                Assert.That(runtime.TryRebuild(world,out var error),Is.True,error);
                var host=new CanonicalSimulationHost(world,runtime); var observed=new System.Collections.Generic.List<string>();
                world.Committed+=_=>observed.Add(CanonicalMaterialSnapshotCodec.Serialize(world));
                Evidence("same-tick-before.json",CanonicalMaterialSnapshotCodec.Serialize(world,true));
                Assert.That(host.Tick(out error),Is.True,error);
                Assert.That(observed,Has.Count.EqualTo(2));
                Assert.That(CanonicalMaterialSnapshotCodec.TryDeserialize(observed[0],out var firstResult,out error),Is.True,error);
                Assert.That(firstResult.Contains(Id(1)),Is.False); Assert.That(firstResult.Contains(Id(2)),Is.True);
                var corpse=firstResult.View.Body(Id(3)); Assert.That(corpse.IsCharacter,Is.False);
                Assert.That(corpse.Shape.Cells.Single().Vertices,Is.EqualTo(character.Shape.Cells.Single().Vertices));
                Assert.That(world.Contains(Id(2)),Is.False); Assert.That(world.Contains(Id(3)),Is.False);
                Assert.That(host.LastExplosionCenter.Value.y,Is.GreaterThan(0.25f));
                Evidence("same-tick-first.json",observed[0]); Evidence("same-tick-second.json",observed[1]);
                int frame=Time.frameCount; yield return null; Assert.That(Time.frameCount,Is.GreaterThan(frame));
            }
            finally { runtime.Dispose(); }
            yield return null;
        }
        [UnityTest]
        public IEnumerator RealFallingBomb_LandsAndExpiresThroughHost_AboveOpaqueFoundation()
        {
            var specs=BlastConformanceFixture.Definitions(0.75f).Export();
            specs.Single(s=>s.kind==DefinitionKind.Environment&&s.id=="platform").bodyMode=CanonicalBodyMode.Static;
            var defs=new DefinitionSet(specs);
            var bomb=BlastConformanceFixture.Body(defs,Id(1),Rect(-0.2f,-0.4f,0.2f,0.4f),"bomb",new Vector2(0,2),
                kind:DefinitionKind.Bomb,response:"indestructible");
            var floor=BlastConformanceFixture.Body(defs,Id(2),Rect(-2,-0.5f,2,0),"cover",response:"indestructible");
            var world=BlastConformanceFixture.World(defs,new[]{bomb,floor}); var runtime=new CanonicalWorldRuntime2D();
            try
            {
                Assert.That(runtime.TryRebuild(world,out var error),Is.True,error);
                var host=new CanonicalSimulationHost(world,runtime); int landingTicks=0;
                while(!world.View.Body(Id(1)).Countdown.Active&&landingTicks<250)
                { Assert.That(host.Tick(out error),Is.True,error); landingTicks++; }
                var landed=world.View.Body(Id(1)); Assert.That(landed.Countdown.Active,Is.True);
                Assert.That(landed.Position.y,Is.LessThan(1)); Assert.That(landed.Countdown.RemainingSeconds,Is.EqualTo(8));
                Assert.That(host.TryCapture(out var before,out error),Is.True,error); Evidence("landing-active-before.json",before);
                int expiryTicks=0;
                while(world.Contains(Id(1))&&expiryTicks<401)
                { Assert.That(host.Tick(out error),Is.True,error); expiryTicks++; }
                Assert.That(expiryTicks,Is.EqualTo(400)); Assert.That(world.Contains(Id(1)),Is.False);
                Assert.That(world.View.Body(Id(2)).Shape,Is.SameAs(floor.Shape));
                Assert.That(host.LastStructuralCommit.NotificationErrors,Is.Empty);
                Evidence("landing-after.json",CanonicalMaterialSnapshotCodec.Serialize(world,true));
                Evidence("landing-measurements.txt","landingTicks="+landingTicks+"\nexpiryTicks="+expiryTicks+
                    "\nlandingY="+landed.Position.y.ToString("R")+"\ncenter="+host.LastExplosionCenter+"\n"+JsonUtility.ToJson(host.LastBlastDiagnostics));
                Assert.That(host.TryRecover(before,out error),Is.True,error);
                Assert.That(host.World.Definitions.Resolve(host.World.View.Body(Id(2)).Selection.Material).blastResistance,Is.EqualTo(4));
                int frame=Time.frameCount; yield return null; Assert.That(Time.frameCount,Is.GreaterThan(frame));
            }
            finally { runtime.Dispose(); }
            yield return null;
        }
        [UnityTest]
        public IEnumerator RealFallingBomb_LayeredRadiusFiveAndEight_ExpireAndRebuildThroughLiveHost()
        {
            foreach(float radius in new[]{5f,8f})
            {
                var specs=BlastConformanceFixture.Definitions(radius).Export();
                specs.Single(s=>s.kind==DefinitionKind.Environment&&s.id=="platform").bodyMode=CanonicalBodyMode.Static;
                specs.Single(s=>s.kind==DefinitionKind.Character&&s.id=="fixture-claymate").bodyMode=CanonicalBodyMode.Static;
                var defs=new DefinitionSet(specs);
                var bomb=BlastConformanceFixture.Body(defs,Id(1),Rect(-0.2f,-0.4f,0.2f,0.4f),"bomb",new Vector2(0,2),kind:DefinitionKind.Bomb,response:"indestructible");
                // This 0.1 m support has its shadow outside both wide layers within
                // reach 8. The prior 0.4 m support/corner rejection is separately
                // preserved; do not weaken the final prefix check to accept it.
                var floor=BlastConformanceFixture.Body(defs,Id(2),Rect(-0.05f,-0.5f,0.05f,0),"cover",response:"indestructible");
                var cover=BlastConformanceFixture.Body(defs,Id(3),Rect(1,-6,2,6),"cover");
                var core=BlastConformanceFixture.Body(defs,Id(4),Rect(2,-6,4,6),"core");
                var character=BlastConformanceFixture.Body(defs,Id(5),Rect(4.1f,0.3f,4.3f,0.5f),"clay",kind:DefinitionKind.Character,response:"indestructible");
                var world=BlastConformanceFixture.World(defs,new[]{bomb,floor,cover,core,character});
                var runtime=new CanonicalWorldRuntime2D();
                try
                {
                    Assert.That(runtime.TryRebuild(world,out var error),Is.True,error);
                    var host=new CanonicalSimulationHost(world,runtime);int landingTicks=0;
                    while(!host.World.View.Body(Id(1)).Countdown.Active&&landingTicks<250)
                    { Assert.That(host.Tick(out error),Is.True,error);landingTicks++; }
                    Assert.That(host.World.View.Body(Id(1)).Countdown.RemainingSeconds,Is.EqualTo(8));
                    Assert.That(host.TryCapture(out var before,out error),Is.True,error);Evidence("live-layers-"+radius+"-before.json",before);
                    runtime.Clear();yield return null;
                    Assert.That(host.TryRecover(before,out error),Is.True,error);
                    int expiryTicks=0,publications=0;host.World.Committed+=_=>publications++;
                    var watch=System.Diagnostics.Stopwatch.StartNew();
                    while(host.World.Contains(Id(1))&&expiryTicks<401)
                    {
                        bool ticked=host.Tick(out error);
                        if(!ticked)
                        {
                            string rejected=CanonicalMaterialSnapshotCodec.Serialize(host.World,true);
                            Evidence("live-layers-"+radius+"-rejected-before.json",rejected);
                            Evidence("live-layers-"+radius+"-rejected.txt",error+"\n"+JsonUtility.ToJson(host.LastBlastDiagnostics));
                            int priorPublications=publications;
                            Assert.That(host.TryDetonate(Id(1),out _),Is.False);
                            Assert.That(CanonicalMaterialSnapshotCodec.Serialize(host.World,true),Is.EqualTo(rejected));
                            Assert.That(publications,Is.EqualTo(priorPublications));
                            Evidence("live-layers-"+radius+"-rejected-after.json",CanonicalMaterialSnapshotCodec.Serialize(host.World,true));
                        }
                        Assert.That(ticked,Is.True,error);expiryTicks++;
                    }
                    double expiryMilliseconds=watch.Elapsed.TotalMilliseconds;
                    Assert.That(expiryTicks,Is.EqualTo(400));Assert.That(publications,Is.EqualTo(1));
                    var origin=host.LastExplosionCenter.Value;Assert.That(Math.Abs(origin.x),Is.LessThan(0.00001));
                    var covers=host.World.View.Bodies.Where(b=>b.Id!=Id(2)&&b.Selection.Material.id=="cover").ToArray();
                    var survivingCore=host.World.View.Body(Id(4));
                    double Front(CanonicalMaterialState[] bodies,double angle)
                    {
                        double dx=Math.Cos(angle),dy=Math.Sin(angle),front=double.PositiveInfinity;
                        foreach(var body in bodies)foreach(var cell in body.Shape.Cells)
                        {
                            var points=cell.Vertices.Select(body.ToWorld).ToArray();double lo=0,hi=double.PositiveInfinity;bool miss=false;
                            for(int i=0;i<points.Length;i++)
                            {
                                var p=points[i]-origin;var e=points[(i+1)%points.Length]-points[i];double den=e.x*dy-e.y*dx,h=e.x*(double)p.y-e.y*(double)p.x;
                                if(Math.Abs(den)<1e-14){if(h>1e-12)miss=true;continue;}
                                if(den>0)lo=Math.Max(lo,h/den);else hi=Math.Min(hi,h/den);
                            }
                            if(!miss&&hi>lo+1e-9)front=Math.Min(front,lo);
                        }
                        return front;
                    }
                    foreach(double angle in new[]{-30*Math.PI/180,0,30*Math.PI/180})
                    {
                        double cosine=Math.Cos(angle);
                        if(radius==5)
                        {
                            double expected=(5+4*(1-origin.x)/cosine)/5;
                            Assert.That(Front(covers,angle),Is.InRange(expected-0.001,expected));
                            Assert.That(Front(new[]{survivingCore},angle),Is.EqualTo((2-origin.x)/cosine).Within(0.00005));
                        }
                        else
                        {
                            Assert.That(Front(covers,angle),Is.EqualTo(double.PositiveInfinity));
                            double expected=(8-(2+origin.x)/cosine)/2;
                            Assert.That(Front(new[]{survivingCore},angle),Is.InRange(expected-0.001,expected));
                        }
                    }
                    Assert.That(host.World.View.Body(Id(5)).IsCharacter,Is.True);Assert.That(host.World.View.Body(Id(5)).Shape.Cells.Single().Vertices,Is.EqualTo(character.Shape.Cells.Single().Vertices));
                    Assert.That(Vector2.Distance(new Vector2(4.1f,0.4f),origin),Is.LessThan(radius));
                    Assert.That(host.World.View.Body(Id(2)).Shape.Cells.Single().Vertices,Is.EqualTo(floor.Shape.Cells.Single().Vertices));
                    if(radius==8){Assert.That(host.World.Contains(Id(3)),Is.False);Assert.That(covers,Has.Length.EqualTo(2));}
                    else Assert.That(host.World.Contains(Id(3)),Is.True);
                    var masses=new System.Collections.Generic.List<LiveMassMeasurement>();
                    foreach(var state in host.World.View.Bodies)
                    {
                        Assert.That(runtime.TryGetBody(state.Id,out var body),Is.True);
                        var colliders=body.GetComponents<PolygonCollider2D>();Assert.That(colliders.Length,Is.EqualTo(state.Shape.Cells.Count));
                        for(int i=0;i<colliders.Length;i++)Assert.That(colliders[i].GetPath(0),Is.EqualTo(state.Shape.Cells[i].Vertices.ToArray()));
                        string material=state.Selection.Material.id;
                        if(material=="cover"||material=="core")
                        {
                            double area=0;int density=material=="cover"?2:3;
                            foreach(var collider in colliders)
                            {
                                var points=collider.GetPath(0);double twice=0;
                                for(int i=0;i<points.Length;i++)twice+=points[i].x*(double)points[(i+1)%points.Length].y-points[i].y*(double)points[(i+1)%points.Length].x;
                                area+=Math.Abs(twice)/2;
                            }
                            Assert.That(state.Mass(host.World.Definitions),Is.EqualTo(density*area).Within(0.0001));
                            Assert.That(body.mass,Is.EqualTo(density*area).Within(0.0001));
                            masses.Add(new LiveMassMeasurement{id=state.Id.Value,material=material,density=density,independentArea=area,
                                expectedMass=density*area,canonicalMass=state.Mass(host.World.Definitions),runtimeMass=body.mass});
                        }
                    }
                    Assert.That(host.LastStructuralCommit.NotificationErrors,Is.Empty);
                    Assert.That(host.TryCapture(out var after,out error),Is.True,error);Evidence("live-layers-"+radius+"-after.json",after);
                    Evidence("live-layers-"+radius+"-measurements.json",JsonUtility.ToJson(new LiveLayerMeasurements{landingTicks=landingTicks,expiryTicks=expiryTicks,
                        publications=publications,expiryMilliseconds=expiryMilliseconds,origin=origin,coverFront=Front(covers,0).ToString("R",System.Globalization.CultureInfo.InvariantCulture),
                        coreFront=Front(new[]{survivingCore},0),diagnostics=host.LastBlastDiagnostics,masses=masses.ToArray()},true));
                    Assert.That(host.TryRecover(after,out error),Is.True,error);Assert.That(host.World.Definitions.Resolve(host.World.View.Body(Id(4)).Selection.Material).blastResistance,Is.EqualTo(1));
                }
                finally{runtime.Dispose();}
                yield return null;
            }
        }
        [Serializable]
        private sealed class LiveLayerMeasurements
        {
            public int landingTicks,expiryTicks,publications;
            public double expiryMilliseconds,coreFront;
            public string coverFront;
            public Vector2 origin;
            public BlastDiagnostics diagnostics;
            public LiveMassMeasurement[] masses;
        }
        [Serializable]
        private sealed class LiveMassMeasurement
        {
            public string id,material;
            public int density;
            public double independentArea,expectedMass;
            public float canonicalMass,runtimeMass;
        }
    }
}
