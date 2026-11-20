package main
// Diagnostic mutation adapter, equivalent to the legacy sandbox fixture without visuals.
headless_fixture_explode :: proc(g: ^Headless_Game,point: Vec2) {
 events:Tick_Events
 world_explode(&g.world,point,g.world.settings.blast_radius,&events)
 delete(events.explosions)
}
