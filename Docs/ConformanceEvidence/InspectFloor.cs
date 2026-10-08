var w = Bomb.CanonicalDestruction.HandbookConformanceFixture.Create(out var ids);
w.TryCommit(new Bomb.CanonicalDestruction.StructuralMutationPlan(w.Generation,
    new Bomb.CanonicalDestruction.CanonicalWorldView(w.View.Bodies,w.View.Connectors,null,w.View.Participants)),out var commit,out var error);
using(var r = new Bomb.CanonicalDestruction.CanonicalWorldRuntime2D())
{
    r.TryRebuild(w,out error);
    var h = new Bomb.CanonicalDestruction.CanonicalSimulationHost(w,r);
    var samples = new System.Collections.Generic.List<string>();
    for(int i=0;i<150;i++)
    {
        if(!h.Tick(out error)) break;
        r.TryGetBody(ids.Character,out var k); r.TryGetBody(ids.Support,out var s);
        if(i%10==0) samples.Add(i+": x="+k.position.x+", y="+k.position.y+", vx="+k.linearVelocity.x+", vy="+k.linearVelocity.y+
            ", angle="+k.rotation+", contacts="+k.GetContacts(new UnityEngine.ContactPoint2D[16])+
            ", floor="+s.GetComponent<UnityEngine.PolygonCollider2D>().OverlapPoint(new UnityEngine.Vector2(2,-0.5f)));
    }
    r.TryGetBody(ids.Character,out var actor); r.TryGetBody(ids.Platform,out var p);
    return new { error, samples=string.Join(" | ",samples), actorX=actor.position.x, actorY=actor.position.y,
        platformX=p.position.x, platformY=p.position.y, angle=p.rotation,
        jointA0x=r.ConnectorJoints(ids.Connector)[0].anchor.x, jointB0x=r.ConnectorJoints(ids.Connector)[0].connectedAnchor.x };
}
