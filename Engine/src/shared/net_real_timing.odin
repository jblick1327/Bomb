package shared

import time "core:time"
import w "core:sys/windows"

// Server loop timing (2026-11-27, movement stutter). A plain 1 ms sleep lasts up to ~15.6 ms on Windows 11 unless the
// process itself raises the timer resolution, so the server woke in bursts and sent world updates unevenly; on a host
// PC that also runs the game window the server could also be starved. The loop now waits 1 ms on a high-resolution
// waitable timer (as the client pump does), and the server process and its loop thread run above normal priority.
when ODIN_OS == .Windows {
	foreign import kernel32 "system:Kernel32.lib"
	@(default_calling_convention = "system")
	foreign kernel32 {
		SetPriorityClass :: proc(process: w.HANDLE, priority_class: w.DWORD) -> w.BOOL ---
	}
}

Net_Real_Waiter :: struct {
	timer: w.HANDLE,
}

net_real_waiter_init :: proc() -> Net_Real_Waiter {
	waiter: Net_Real_Waiter
	when ODIN_OS == .Windows {
		w.timeBeginPeriod(1)
		SetPriorityClass(w.GetCurrentProcess(), w.ABOVE_NORMAL_PRIORITY_CLASS)
		w.SetThreadPriority(w.GetCurrentThread(), w.THREAD_PRIORITY_ABOVE_NORMAL)
		waiter.timer = w.CreateWaitableTimerExW(nil, nil, w.CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, w.TIMER_ALL_ACCESS)
	}
	return waiter
}

net_real_waiter_wait :: proc(waiter: ^Net_Real_Waiter, seconds: f64) {
	when ODIN_OS == .Windows {
		if waiter.timer != nil {
			relative := w.LARGE_INTEGER(-i64(seconds * 1e7)) // 100 ns units, negative = relative
			if w.SetWaitableTimerEx(waiter.timer, &relative, 0, nil, nil, nil, 0) {
				w.WaitForSingleObject(waiter.timer, w.INFINITE)
				return
			}
		}
	}
	time.sleep(time.Duration(seconds * f64(time.Second)))
}

net_real_waiter_destroy :: proc(waiter: ^Net_Real_Waiter) {
	when ODIN_OS == .Windows {
		if waiter.timer != nil { w.CloseHandle(waiter.timer); waiter.timer = nil }
		w.timeEndPeriod(1)
	}
}
