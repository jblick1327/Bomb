var path=System.IO.Path.Combine(UnityEngine.Application.dataPath,"../Temp/BlastConformanceEvidence/layers-5-0-before.json");
if(!Bomb.CanonicalDestruction.CanonicalMaterialSnapshotCodec.TryDeserialize(System.IO.File.ReadAllText(path),out var world,out var error))throw new System.Exception(error);
var bomb=System.Linq.Enumerable.First(world.View.Bodies,b=>b.IsBomb);
Bomb.CanonicalDestruction.BoundedBlastEvaluator.TryCreate(world,bomb,out var field,out error);
var service=new Bomb.CanonicalDestruction.CanonicalDestructionService(world);
var before=new System.Collections.Generic.List<object>();var after=new System.Collections.Generic.List<object>();
double[][][] Points(Bomb.CanonicalDestruction.CanonicalMaterialState body)
{
    double c=UnityEngine.Mathf.Cos(body.RotationRadians),s=UnityEngine.Mathf.Sin(body.RotationRadians);
    return System.Linq.Enumerable.ToArray(System.Linq.Enumerable.Select(body.Shape.Cells,cell=>System.Linq.Enumerable.ToArray(System.Linq.Enumerable.Select(cell.Vertices,
        p=>new[]{body.Position.x-(double)bomb.Position.x+c*p.x-s*p.y,body.Position.y-(double)bomb.Position.y+s*p.x+c*p.y}))));
}
foreach(var source in world.View.Bodies)
{
    if(source.IsBomb)continue; before.Add(new{id=source.Id.Value,cells=Points(source)});
    if(!service.TryEvaluateBlast(source,field,out var geometry,out error))throw new System.Exception(error);
    if(!geometry.Changed)after.Add(new{id=source.Id.Value,cells=Points(source)});
    else foreach(var shape in geometry.ConnectedResults)
    {
        var result=new Bomb.CanonicalDestruction.PreserveMotionAndApplyBlastPolicy().BuildResult(source,source.Id,shape,2,
            new Bomb.CanonicalDestruction.DestructionRequest(source.Id,null,UnityEngine.Vector2.zero,0));
        after.Add(new{id=source.Id.Value,cells=Points(result)});
    }
}
double theta=1.2490457670578967;
var output=Newtonsoft.Json.JsonConvert.SerializeObject(new{theta,direction=new[]{System.Math.Cos(theta),System.Math.Sin(theta)},before,after},Newtonsoft.Json.Formatting.Indented);
var target=System.IO.Path.Combine(UnityEngine.Application.dataPath,"../Docs/BlastConformanceEvidence/2026-10-09-revision-1/continuity-case.json");
System.IO.File.WriteAllText(target,output);return "Saved exact-predicate diagnostic input.";
