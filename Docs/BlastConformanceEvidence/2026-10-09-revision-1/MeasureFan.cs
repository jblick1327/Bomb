var measurements = new System.Collections.Generic.List<object>();
foreach (float radius in new[] { 5f, 8f })
{
    var world = Bomb.CanonicalDestruction.BlastConformanceFixture.Layers(radius, out var bomb, out var cover, out var core);
    var clock = System.Diagnostics.Stopwatch.StartNew();
    bool ok = Bomb.CanonicalDestruction.BoundedBlastEvaluator.TryCreate(world,world.View.Body(bomb),out var field,out var error);
    measurements.Add(new { radius, ok, error, milliseconds=clock.ElapsedMilliseconds, diagnostics=field?.Diagnostics,
        central=field?.RepresentedReach(0) });
}
return Newtonsoft.Json.JsonConvert.SerializeObject(measurements);
