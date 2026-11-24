package main

import "core:fmt"
import "core:time"

// End-to-end fixture timings include any work done by the Sandbox wrappers.
// No drawing, allocation tracking or test-only counter in this release command.
run_presentation_bench :: proc() {
	ticks,blasts:=Soak_Timing{},Soak_Timing{}
	for replay in 0..<5 {
		g:=soak_yard()
		positions:=[3]Vec2{{-6.6,1},{0,0.6},{5.8,1.2}}
		for point in positions {
			for _ in 0..<120 { start:=time.tick_now(); sandbox_tick(&g,0,false); soak_sample(&ticks,start) }
			start:=time.tick_now(); sandbox_explode(&g,point); soak_sample(&blasts,start)
		}
		for _ in 0..<240 { start:=time.tick_now(); sandbox_tick(&g,0,false); soak_sample(&ticks,start) }
		sandbox_destroy(&g)
	}
	fmt.printf("Fixture benchmark: replays=5 ticks=%d blasts=%d tick_mean_ms=%.6f worst_blast_wrapper_ms=%.6f\n",ticks.count,blasts.count,soak_mean(ticks),blasts.max_ms)
}
