package main

// Legacy fixture/frontend ownership transfer. No UI state enters the server.
net_server_init :: proc(ns: ^Net_Server,game: Sandbox,record_hashes: bool=false) {
 net_server_init_world(ns,Headless_Game{world=game.world,layout=game.layout},record_hashes)
 owned:=game
 owned.world={}; owned.layout={}
 sandbox_destroy(&owned)
}
