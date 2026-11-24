package ffi

import "base:runtime"
import "core:math"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import w "core:sys/windows"

// Native network pump (ABI 1.7). Opt-in per slot through bom_client_start_pump.
//
// Locks: every exported call that touches a slot takes the slot lock, then core_lock;
// the pump thread takes them in the same order for each pump. core_lock is process-wide
// because Box2D's world registry (prediction worlds) is process-global, so two slots
// must never run client-core work at the same time. Nothing ever waits for a slot lock
// while holding core_lock.
//
// acquire_sample keeps the slot lock (not core_lock) until release_sample. Calls the
// owner thread makes in that window see s.acquired (written only by the owner thread)
// and skip locking, since the owner thread already holds the slot lock.
core_lock: sync.Mutex
qpc_frequency: f64

PUMP_INPUT_HEARTBEAT :: 0.25 // seconds without an input call before held move goes neutral
PUMP_LATE :: 0.004           // a timer wake this late counts in pump_late_count
WAIT_BUCKETS :: 64           // 0.25 ms lock-wait histogram buckets; the last one is overflow
PUMP_MAIN_PATIENCE :: 0.002  // update/acquire give up (BUSY) after waiting this long on a pumping slot

// Raw QPC seconds. On CoreCLR this equals BomSession.Now; Unity's Mono Stopwatch counts the same
// ticks from another origin, so each slot adds clock_offset (slot_now) learned from Unity's `now`.
qpc_now :: proc "contextless" () -> f64 {
	if qpc_frequency == 0 {
		f: w.LARGE_INTEGER
		w.QueryPerformanceFrequency(&f)
		qpc_frequency = f64(f)
	}
	c: w.LARGE_INTEGER
	w.QueryPerformanceCounter(&c)
	return f64(c) / qpc_frequency
}

@(export)
bom_clock_now :: proc "c" () -> f64 { return qpc_now() }

// The slot's clock in the caller's timebase (the `now` Unity passes to update and input calls).
slot_now :: proc "contextless" (s: ^Client_Slot) -> f64 { return qpc_now() + s.clock_offset }

record_wait :: proc "contextless" (hist: ^[WAIT_BUCKETS]u32, max_ms: ^f64, seconds: f64) {
	ms := max(seconds, 0) * 1000
	if ms > max_ms^ { max_ms^ = ms }
	bucket := min(int(ms * 4), WAIT_BUCKETS - 1)
	if hist[bucket] < max(u32) { hist[bucket] += 1 }
}

// Upper edge of the bucket holding the 99th percentile; the overflow bucket reports the max.
wait_p99 :: proc "contextless" (hist: ^[WAIT_BUCKETS]u32, max_ms: f64) -> f64 {
	total := u64(0)
	for n in hist { total += u64(n) }
	if total == 0 { return 0 }
	target := u64(math.ceil(f64(total) * 0.99))
	seen := u64(0)
	for n, i in hist {
		seen += u64(n)
		if seen >= target { return i == WAIT_BUCKETS - 1 ? max_ms : min(f64(i + 1) * 0.25, max_ms) }
	}
	return max_ms
}

// Owner-thread entry for exported calls. held=false means no lock was taken: either the
// handle is bad or a sample is acquired and this thread already holds the slot lock.
enter :: proc "contextless" (handle: u64) -> (s: ^Client_Slot, status: u32, held: bool) {
	s, status = get_slot(handle)
	if status != OK || s.acquired { return }
	start := qpc_now()
	sync.mutex_lock(&s.lock)
	sync.mutex_lock(&core_lock)
	record_wait(&s.main_wait_hist, &s.main_lock_wait_max, qpc_now() - start)
	held = true
	return
}

// update, acquire_sample and set_held_input while the pump runs: wait at most PUMP_MAIN_PATIENCE for the locks,
// then return held=false with status BUSY so Unity keeps last frame's sample instead of blocking
// for the pump's heavy work (a level or snapshot apply can hold the lock for 150 ms).
// Other calls (input, commands) still wait; they are rare and must not be dropped.
enter_or_skip :: proc "contextless" (handle: u64) -> (s: ^Client_Slot, status: u32, held: bool) {
	s, status = get_slot(handle)
	if status != OK || s.acquired { return }
	if s.pump == nil { return enter(handle) }
	start := qpc_now()
	for {
		if sync.mutex_try_lock(&s.lock) {
			if sync.mutex_try_lock(&core_lock) {
				record_wait(&s.main_wait_hist, &s.main_lock_wait_max, qpc_now() - start)
				held = true
				return
			}
			sync.mutex_unlock(&s.lock)
		}
		if qpc_now() - start > PUMP_MAIN_PATIENCE {
			sync.atomic_add(&s.main_skips, 1)
			return s, BUSY, false
		}
		w.SwitchToThread()
	}
}

// A successful acquire_sample keeps the slot lock until release_sample.
leave :: proc "contextless" (s: ^Client_Slot, held: bool) {
	if !held { return }
	sync.mutex_unlock(&core_lock)
	if !s.acquired { sync.mutex_unlock(&s.lock) }
}

// Pump-thread failures are recorded here; the owner thread reports them through
// fail_client on its next bom_client_update.
pump_fail :: proc(s: ^Client_Slot, code: u32, reason: string, on_thread: bool) -> u32 {
	if !on_thread { return fail_client(s, code, reason) }
	delete(s.pump_reason)
	s.pump_reason = strings.clone(reason)
	s.pump_status = code
	return code
}

// Owner thread, both locks held. Releases them while joining so a pump waiting on the
// lock can see the stop flag, then takes them back in the same order.
stop_pump :: proc(s: ^Client_Slot) {
	if s.pump == nil { return }
	sync.atomic_store(&s.pump_stop, true)
	w.SetEvent(s.pump_stop_event)
	t := s.pump
	sync.mutex_unlock(&core_lock)
	sync.mutex_unlock(&s.lock)
	{
		context = runtime.default_context()
		thread.destroy(t) // joins, then frees
	}
	sync.mutex_lock(&s.lock)
	sync.mutex_lock(&core_lock)
	if s.pump_socket_event != nil {
		if s.socket.is_open { w.WSAEventSelect(w.SOCKET(uintptr(s.socket.handle)), nil, 0) }
		w.WSACloseEvent(s.pump_socket_event)
		s.pump_socket_event = nil
	}
	w.CloseHandle(s.pump_stop_event)
	s.pump_stop_event = nil
	s.pump = nil
	sync.atomic_store(&s.pump_stop, false)
	s.pump_status = OK
	delete(s.pump_reason)
	s.pump_reason = ""
}

@(export)
bom_client_start_pump :: proc "c" (handle: u64, now: f64) -> u32 {
	s, status, held := enter(handle)
	if status != OK { return status }
	defer leave(s, held)
	context = s.ctx
	if s.acquired { return BUSY }
	if !s.live { return NOT_CONNECTED }
	if s.pump != nil { return OK }
	if math.is_nan(now) || math.is_inf(now) { return BAD_ARGUMENT }
	s.clock_offset = now - qpc_now()
	s.pump_status = OK
	s.pump_ticks = 0; s.pump_late_count = 0; s.pump_max_gap = 0; s.pump_high_res = false
	s.pump_lock_wait_max = 0; s.main_lock_wait_max = 0; s.pump_wait_hist = {}; s.main_wait_hist = {}
	s.heartbeat_neutral_ticks = 0
	sync.atomic_store(&s.main_skips, 0)
	s.last_input = slot_now(s); s.main_now = now
	sync.atomic_store(&s.pump_stop, false)
	s.pump_stop_event = w.CreateEventW(nil, true, false, nil)
	if s.pump_stop_event == nil { return IO_ERROR }
	// Optional: wake on arriving datagrams so receive timestamps are not quantised to the tick.
	s.pump_socket_event = w.WSACreateEvent()
	if s.pump_socket_event != nil && w.WSAEventSelect(w.SOCKET(uintptr(s.socket.handle)), s.pump_socket_event, w.FD_READ) != 0 {
		w.WSACloseEvent(s.pump_socket_event)
		s.pump_socket_event = nil
	}
	s.pump_generation = s.generation
	t: ^thread.Thread
	{
		context = runtime.default_context()
		t = thread.create(pump_main)
	}
	if t == nil {
		if s.pump_socket_event != nil { w.WSAEventSelect(w.SOCKET(uintptr(s.socket.handle)), nil, 0); w.WSACloseEvent(s.pump_socket_event); s.pump_socket_event = nil }
		w.CloseHandle(s.pump_stop_event); s.pump_stop_event = nil
		return IO_ERROR
	}
	t.data = s
	s.pump = t
	thread.start(t)
	return OK
}

pump_main :: proc(t: ^thread.Thread) {
	s := cast(^Client_Slot)t.data
	// Written by the owner thread before thread.start and not changed until after the join.
	generation := s.pump_generation
	stop_event := s.pump_stop_event
	socket_event := s.pump_socket_event
	// Normal priority by default: above normal let two pumps doing level applies crowd out a
	// server on the same machine (NPT A/B). BOM_PUMP_PRIORITY=above restores it for comparison.
	buf: [16]u8
	if os.get_env_buf(buf[:], "BOM_PUMP_PRIORITY") == "above" {
		w.SetThreadPriority(w.GetCurrentThread(), w.THREAD_PRIORITY_ABOVE_NORMAL)
	}
	high := true
	timer := w.CreateWaitableTimerExW(nil, nil, w.CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, w.TIMER_ALL_ACCESS)
	if timer == nil {
		high = false
		timer = w.CreateWaitableTimerExW(nil, nil, 0, w.TIMER_ALL_ACCESS)
	}
	defer if timer != nil { w.CloseHandle(timer) }
	handles: [3]w.HANDLE
	count := u32(0)
	handles[count] = stop_event; count += 1
	if timer != nil { handles[count] = timer; count += 1 }
	socket_index := u32(0xffffffff)
	if socket_event != nil { socket_index = count; handles[count] = socket_event; count += 1 }
	due, last_full := f64(0), f64(0)
	for !sync.atomic_load(&s.pump_stop) {
		start := qpc_now()
		sync.mutex_lock(&s.lock)
		sync.mutex_lock(&core_lock)
		waited := qpc_now() - start
		if sync.atomic_load(&s.pump_stop) || !s.live || s.generation != generation || s.pump_status != OK {
			sync.mutex_unlock(&core_lock)
			sync.mutex_unlock(&s.lock)
			break
		}
		record_wait(&s.pump_wait_hist, &s.pump_lock_wait_max, waited)
		s.pump_high_res = high
		offset := s.clock_offset // read under the lock; the owner thread refines it
		now := qpc_now() + offset
		// A socket wake before the tick only receives; the timer wake steps and sends.
		full := due == 0 || now >= due - 0.0002
		if full {
			s.pump_ticks += 1
			if last_full > 0 { s.pump_max_gap = max(s.pump_max_gap, (now - last_full) * 1000) }
			if due > 0 && now - due > PUMP_LATE { s.pump_late_count += 1 }
			last_full = now
		}
		status: u32
		{
			context = s.ctx
			status = pump_locked(s, now, full, true)
		}
		next := s.next_tick
		sync.mutex_unlock(&core_lock)
		sync.mutex_unlock(&s.lock)
		free_all(context.temp_allocator)
		if status != OK { break }
		if full { due = next }
		remaining := max(due - (qpc_now() + offset), 0.0002)
		wait_ms := u32(100) // safety net only; the timer or an event normally wakes first
		if timer != nil {
			relative := w.LARGE_INTEGER(-i64(remaining * 1e7))
			if !w.SetWaitableTimerEx(timer, &relative, 0, nil, nil, nil, 0) { wait_ms = max(u32(1), u32(remaining * 1000)) }
		} else {
			wait_ms = max(u32(1), u32(remaining * 1000))
		}
		r := w.WaitForMultipleObjects(count, &handles[0], false, wait_ms)
		if socket_index != 0xffffffff && r == w.WAIT_OBJECT_0 + socket_index { w.ResetEvent(socket_event) }
	}
}
