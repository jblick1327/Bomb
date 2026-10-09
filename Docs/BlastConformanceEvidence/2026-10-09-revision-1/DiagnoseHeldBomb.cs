var dir = System.IO.Path.Combine(UnityEngine.Application.dataPath,"../Docs/BlastConformanceEvidence/2026-10-09-revision-1/held-diagnostic");
System.IO.Directory.CreateDirectory(dir);
var world = Bomb.CanonicalDestruction.HandbookConformanceFixture.Create(out var ids);
var runtime = new Bomb.CanonicalDestruction.CanonicalWorldRuntime2D();
try
{
    if (!runtime.TryRebuild(world,out var error)) throw new System.Exception(error);
    var host = new Bomb.CanonicalDestruction.CanonicalSimulationHost(world,runtime);
    for(int i=0;i<250&&!world.View.Body(ids.Bomb).Countdown.Active;i++)
        if(!host.Tick(out error)) throw new System.Exception(error);
    if(!host.TryRelease(ids.Participant,Bomb.CanonicalDestruction.LimbSlot.RightHand,out error)) throw new System.Exception(error);
    runtime.TryGetBody(ids.Character,out var actor);
    actor.position=world.View.Body(ids.Bomb).Position+new UnityEngine.Vector2(0,1.25f); actor.linearVelocity=UnityEngine.Vector2.zero;
    if(!runtime.TryCaptureMotion(world,out error)) throw new System.Exception(error);
    if(!host.TryHold(new Bomb.CanonicalDestruction.HoldRequest(ids.Participant,ids.Character,Bomb.CanonicalDestruction.LimbSlot.LeftHand,
        ids.Bomb,new UnityEngine.Vector2(0,0.25f),1),out _,out error)) throw new System.Exception(error);
    int steps=0; bool ok=true;
    while(world.Contains(ids.Bomb)&&steps++<450) { ok=host.Tick(out error); if(!ok) break; }
    System.IO.File.WriteAllText(System.IO.Path.Combine(dir,"held-input.json"),Bomb.CanonicalDestruction.CanonicalMaterialSnapshotCodec.Serialize(world,true));
    var diagnostics=new System.Collections.Generic.List<object>();
    if(world.Contains(ids.Bomb))
    {
        var bomb=world.View.Body(ids.Bomb);
        if(Bomb.CanonicalDestruction.BoundedBlastEvaluator.TryCreate(world,bomb,out var field,out var fieldError))
        {
            var service=new Bomb.CanonicalDestruction.CanonicalDestructionService(world);
            var replacements=new System.Collections.Generic.Dictionary<Bomb.CanonicalDestruction.MaterialEntityId,System.Collections.Generic.IReadOnlyList<Bomb.CanonicalDestruction.CanonicalMaterialState>>();
            foreach(var source in world.View.Bodies)
            {
                if(source.IsBomb||source.IsCharacter) continue;
                bool evaluated=service.TryEvaluateBlast(source,field,out var geometry,out var geometryError);
                if(evaluated&&geometry.Changed)
                {
                    var results=new System.Collections.Generic.List<Bomb.CanonicalDestruction.CanonicalMaterialState>();
                    for(int i=0;i<geometry.ConnectedResults.Count;i++) results.Add(new Bomb.CanonicalDestruction.PreserveMotionAndApplyBlastPolicy().BuildResult(source,
                        geometry.ConnectedResults.Count==1?source.Id:new Bomb.CanonicalDestruction.MaterialEntityId("diagnostic-"+i),geometry.ConnectedResults[i],
                        geometry.ConnectedResults.Count==1?source.GeometryRevision+1:1,new Bomb.CanonicalDestruction.DestructionRequest(source.Id,null,UnityEngine.Vector2.zero,0)));
                    replacements[source.Id]=results;
                    foreach(var result in results) diagnostics.Add(new { source=source.Id.Value,result=result.Id.Value,position=new[]{result.Position.x,result.Position.y},rotation=result.RotationRadians,
                        cells=System.Linq.Enumerable.ToArray(System.Linq.Enumerable.Select(result.Shape.Cells,c=>System.Linq.Enumerable.ToArray(System.Linq.Enumerable.Select(c.Vertices,p=>new[]{p.x,p.y})))) });
                }
                else diagnostics.Add(new { source=source.Id.Value,evaluated,geometryError,changed=geometry?.Changed });
            }
            field.TryValidateRemoval(replacements,out var continuityError);
            diagnostics.Add(new { continuityError,field.Diagnostics });
        }
        else diagnostics.Add(new {fieldError});
    }
    System.IO.File.WriteAllText(System.IO.Path.Combine(dir,"held-proposed-geometry.json"),Newtonsoft.Json.JsonConvert.SerializeObject(diagnostics,Newtonsoft.Json.Formatting.Indented));
    return Newtonsoft.Json.JsonConvert.SerializeObject(new {ok,steps,error,host.LastExplosionCenter,host.LastBlastDiagnostics});
}
finally { runtime.Dispose(); }
