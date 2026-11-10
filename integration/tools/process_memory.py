"""Supplement tracked allocation counters with RSS/private bytes for owned PIDs."""
import ctypes
from ctypes import wintypes

class Counters(ctypes.Structure):
    _fields_=[('cb',wintypes.DWORD),('page_faults',wintypes.DWORD)]+[(name,ctypes.c_size_t) for name in ['peak_working_set','working_set','quota_peak_paged','quota_paged','quota_peak_nonpaged','quota_nonpaged','pagefile','peak_pagefile','private_bytes']]

def sample(pid):
    kernel=ctypes.WinDLL('kernel32',use_last_error=True);psapi=ctypes.WinDLL('psapi',use_last_error=True)
    kernel.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD];kernel.OpenProcess.restype=wintypes.HANDLE
    kernel.CloseHandle.argtypes=[wintypes.HANDLE]
    psapi.GetProcessMemoryInfo.argtypes=[wintypes.HANDLE,ctypes.POINTER(Counters),wintypes.DWORD];psapi.GetProcessMemoryInfo.restype=wintypes.BOOL
    handle=kernel.OpenProcess(0x410,False,pid)
    if not handle:return {'unavailable':ctypes.get_last_error()}
    try:
        result=Counters();result.cb=ctypes.sizeof(result)
        if not psapi.GetProcessMemoryInfo(handle,ctypes.byref(result),result.cb):return {'unavailable':ctypes.get_last_error()}
        return {key:getattr(result,key) for key in ['working_set','peak_working_set','private_bytes','pagefile','page_faults']}
    finally:kernel.CloseHandle(handle)
