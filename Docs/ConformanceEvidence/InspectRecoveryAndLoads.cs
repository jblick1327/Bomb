var results = new System.Collections.Generic.List<string>();
{
    var w = Bomb.CanonicalDestruction.HandbookConformanceFixture.Create(out var ids);
    using(var r = new Bomb.CanonicalDestruction.CanonicalWorldRuntime2D())
    {
        r.TryRebuild(w,out var error); var h = new Bomb.CanonicalDestruction.CanonicalSimulationHost(w,r);
        for(int i=0;i<100 && !w.View.Body(ids.Bomb).Countdown.Active;i++) h.Tick(out error);
        h.TryCapture(out var json,out error); h.TryRecover(json,out error);
        foreach(var b in h.World.View.Bodies)
        {
            r.TryGetBody(b.Id,out var engine);
            results.Add("recovery " + b.Id + ": canonical="+b.LinearVelocity.x+","+b.LinearVelocity.y+", engine="+engine.linearVelocity.x+","+engine.linearVelocity.y);
        }
    }
}
foreach(var input in new[] { 1000f,2000f,3000f,5000f })
{
    var w = Bomb.CanonicalDestruction.HandbookConformanceFixture.Create(out var ids);
    var c = w.View.Connectors[0];
    c = new Bomb.CanonicalDestruction.CanonicalConnector(c.Id,c.A,c.B,c.A0,c.A1,c.B0,c.B1,1000,0.5f,0.6f);
    w.TryCommit(new Bomb.CanonicalDestruction.StructuralMutationPlan(w.Generation,new Bomb.CanonicalDestruction.CanonicalWorldView(w.View.Bodies,new[] { c },null,w.View.Participants)),out _,out _);
    using(var r = new Bomb.CanonicalDestruction.CanonicalWorldRuntime2D())
    {
        r.TryRebuild(w,out var error); var h = new Bomb.CanonicalDestruction.CanonicalSimulationHost(w,r);
        r.TryGetBody(ids.Platform,out var engine); engine.AddTorque(input); h.Tick(out error);
        var load = h.LastLoads[c.Id]; results.Add("torque input="+input+", force="+load.Force.magnitude+", moment="+load.Torque);
    }
}
foreach(var input in new[] { 1000f,10000f })
{
    var w = Bomb.CanonicalDestruction.HandbookConformanceFixture.Create(out var ids);
    var hold = new Bomb.CanonicalDestruction.CanonicalHold(ids.Hold,ids.Character,Bomb.CanonicalDestruction.LimbSlot.RightHand,ids.Support,new UnityEngine.Vector2(2,0));
    w.TryCommit(new Bomb.CanonicalDestruction.StructuralMutationPlan(w.Generation,new Bomb.CanonicalDestruction.CanonicalWorldView(w.View.Bodies,w.View.Connectors,new[] { hold },w.View.Participants)),out _,out _);
    using(var r = new Bomb.CanonicalDestruction.CanonicalWorldRuntime2D())
    {
        r.TryRebuild(w,out var error); var h = new Bomb.CanonicalDestruction.CanonicalSimulationHost(w,r);
        r.TryGetBody(ids.Character,out var actor); actor.linearVelocity = new UnityEngine.Vector2(1,0); actor.angularVelocity=50;
        for(int i=0;i<8;i++) h.Tick(out error);
        actor.AddForce(new UnityEngine.Vector2(input,input*0.5f));
        for(int i=0;i<80;i++)
        {
            h.Tick(out error);
            r.TryGetBody(ids.Character,out actor); r.TryGetBody(ids.Support,out var target);
            if(i%10==0 || i==12)
            {
                var root = w.Definitions.Resolve(w.View.Body(ids.Character).Selection.Role).Root(hold.Slot);
                results.Add("hold input="+input+", step="+i+", distance="+UnityEngine.Vector2.Distance(actor.GetRelativePoint(root),target.GetRelativePoint(hold.HeldLocal))+
                    ", reaction="+r.HoldJoint(ids.Hold).GetReactionForce(0.02f).magnitude+", angle="+actor.rotation);
            }
        }
    }
}
return string.Join("\n",results);
