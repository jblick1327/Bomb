var world=Bomb.CanonicalDestruction.BlastConformanceFixture.Layers(8,out var bomb,out var cover,out var core);
Bomb.CanonicalDestruction.BoundedBlastEvaluator.TryCreate(world,world.View.Body(bomb),out var field,out var error);
var result=new System.Collections.Generic.List<object>();
var service=new Bomb.CanonicalDestruction.CanonicalDestructionService(world);
foreach(var id in new[]{cover,core})
{
    bool ok=service.TryEvaluateBlast(world.View.Body(id),field,out var geometry,out error);
    result.Add(new {id=id.Value,ok,error,cells=geometry?.ConnectedResults.Count});
}
return Newtonsoft.Json.JsonConvert.SerializeObject(result);
