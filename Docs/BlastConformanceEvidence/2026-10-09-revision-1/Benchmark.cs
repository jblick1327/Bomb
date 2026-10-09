var records=new System.Collections.Generic.List<object>();
Bomb.CanonicalDestruction.CanonicalMaterialShape Rect(float a,float b,float c,float d)=>Bomb.CanonicalDestruction.HandbookConformanceFixture.Shape(Bomb.CanonicalDestruction.HandbookConformanceFixture.Rectangle(a,b,c,d));
Bomb.CanonicalDestruction.CanonicalMaterialWorld Build(string name)
{
    if(name=="second-layered-rot37")
    {
        var world=Bomb.CanonicalDestruction.BlastConformanceFixture.Layers(8,out var first,out _,out _,37*UnityEngine.Mathf.Deg2Rad,new UnityEngine.Vector2(12,-9));
        var host=new Bomb.CanonicalDestruction.CanonicalSimulationHost(world);
        if(!host.TryDetonate(first,out var error))throw new System.Exception(error);
        if(!world.TryReserveEntityIds(1,out var reservation,out error))throw new System.Exception(error);
        var next=Bomb.CanonicalDestruction.BlastConformanceFixture.Body(world.Definitions,System.Linq.Enumerable.Single(reservation.Ids),Rect(-.1f,-.1f,.1f,.1f),"bomb",new UnityEngine.Vector2(12,-9),kind:Bomb.CanonicalDestruction.DefinitionKind.Bomb,response:"indestructible");
        if(!world.TryCommit(new Bomb.CanonicalDestruction.StructuralMutationPlan(world.Generation,
            new Bomb.CanonicalDestruction.CanonicalWorldView(System.Linq.Enumerable.Concat(world.View.Bodies,new[]{next})),reservation),out _,out error))throw new System.Exception(error);
        if(!Bomb.CanonicalDestruction.CanonicalMaterialSnapshotCodec.TryDeserialize(Bomb.CanonicalDestruction.CanonicalMaterialSnapshotCodec.Serialize(world),out var recovered,out error))throw new System.Exception(error);
        return recovered;
    }
    if(name.StartsWith("wide"))
    {
        float radius=name=="wide5"?5:8;float rotation=name=="wide8-rot37"?37*UnityEngine.Mathf.Deg2Rad:0;
        var world=Bomb.CanonicalDestruction.BlastConformanceFixture.Layers(radius,out _,out _,out _,rotation,rotation==0?UnityEngine.Vector2.zero:new UnityEngine.Vector2(12,-9));
        if(name!="wide8-character")return world;
        var character=Bomb.CanonicalDestruction.BlastConformanceFixture.Body(world.Definitions,Bomb.CanonicalDestruction.BlastConformanceFixture.Id(4),Rect(4.1f,-0.1f,4.3f,0.1f),"clay",kind:Bomb.CanonicalDestruction.DefinitionKind.Character,response:"indestructible");
        return Bomb.CanonicalDestruction.BlastConformanceFixture.World(world.Definitions,System.Linq.Enumerable.Concat(world.View.Bodies,new[]{character}));
    }
    var defs=Bomb.CanonicalDestruction.BlastConformanceFixture.Definitions(name=="thin"?1.05f:5);
    var bomb=Bomb.CanonicalDestruction.BlastConformanceFixture.Body(defs,Bomb.CanonicalDestruction.BlastConformanceFixture.Id(1),Rect(-0.1f,-0.1f,0.1f,0.1f),"bomb",kind:Bomb.CanonicalDestruction.DefinitionKind.Bomb,response:"indestructible");
    var blocker=name=="thin"?Bomb.CanonicalDestruction.BlastConformanceFixture.Body(defs,Bomb.CanonicalDestruction.BlastConformanceFixture.Id(2),Rect(1,-1,1.02f,1),"cover"):
        Bomb.CanonicalDestruction.BlastConformanceFixture.Body(defs,Bomb.CanonicalDestruction.BlastConformanceFixture.Id(2),Rect(-0.01f,-0.01f,0.01f,0.01f),"narrow",new UnityEngine.Vector2(3.01f,0),name=="narrow37"?37*UnityEngine.Mathf.Deg2Rad:0);
    var target=Bomb.CanonicalDestruction.BlastConformanceFixture.Body(defs,Bomb.CanonicalDestruction.BlastConformanceFixture.Id(3),name=="thin"?Rect(1.02f,-1,1.5f,1):Rect(4.5f,-0.02f,5.1f,0.02f),name=="thin"?"core":"clay");
    return Bomb.CanonicalDestruction.BlastConformanceFixture.World(defs,new[]{bomb,blocker,target});
}
var evidence=System.IO.Path.Combine(UnityEngine.Application.dataPath,"../Docs/BlastConformanceEvidence/2026-10-09-revision-1");
System.IO.Directory.CreateDirectory(System.IO.Path.Combine(evidence,"states"));
foreach(var name in new[]{"wide5","wide8","wide8-rot37","wide8-character","narrow0","narrow37","thin","second-layered-rot37"})
for(int sample=0;sample<6;sample++)
{
    var world=Build(name);var host=new Bomb.CanonicalDestruction.CanonicalSimulationHost(world);
    if(sample==1)System.IO.File.WriteAllText(System.IO.Path.Combine(evidence,"states/benchmark-"+name+"-before.json"),Bomb.CanonicalDestruction.CanonicalMaterialSnapshotCodec.Serialize(world,true));
    var bombId=System.Linq.Enumerable.First(world.View.Bodies,b=>b.IsBomb).Id;
    var watch=System.Diagnostics.Stopwatch.StartNew();bool ok=host.TryDetonate(bombId,out var error);
    double milliseconds=watch.Elapsed.TotalMilliseconds;
    records.Add(new{name,sample,warmup=sample==0,ok,error,milliseconds,diagnostics=host.LastBlastDiagnostics});
    if(sample==1)System.IO.File.WriteAllText(System.IO.Path.Combine(evidence,"states/benchmark-"+name+"-after.json"),Bomb.CanonicalDestruction.CanonicalMaterialSnapshotCodec.Serialize(world,true));
}
System.IO.File.WriteAllText(System.IO.Path.Combine(evidence,"benchmark.json"),Newtonsoft.Json.JsonConvert.SerializeObject(records,Newtonsoft.Json.Formatting.Indented));
return "Saved 8 cases, one warmup and five measured host detonations per case; fixture construction/first detonation/recovery excluded.";
