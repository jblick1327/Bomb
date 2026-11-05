package main
import "core:time"
import "core:fmt"
BOM_PROFILE :: #config(BOM_PROFILE,false)
when BOM_PROFILE {
 Profile :: struct { start: time.Tick, ms: [18]f64, counts: [8]int, before: [2]int }
 @(thread_local) blast_profile: ^Profile
 @(thread_local) profile_tick: u64
 profile_add :: proc(slot:int,start:time.Tick) { if blast_profile!=nil { blast_profile.ms[slot]+=f64(time.tick_diff(start,time.tick_now()))/f64(time.Millisecond) } }
}
