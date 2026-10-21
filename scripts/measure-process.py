"""SPDX-License-Identifier: Apache-2.0
Measure one child CLI; sample OS-reported peak RSS/working-set every 10 ms.
This is an observed lower bound if the child exits between samples.
"""
import ctypes
import ctypes.wintypes as W
import json
import os
from pathlib import Path
import subprocess
import sys
import time

def main():
    output = Path(sys.argv[1])
    command = sys.argv[2:]
    if command[0] == "--":
        command.pop(0)
    output.parent.mkdir(parents=True, exist_ok=True)
    start = time.perf_counter()
    peak = 0
    with output.open("wb") as report:
        process = subprocess.Popen(command, stdout=report, stderr=subprocess.STDOUT)
        handle = None
        if os.name == "nt":
            class Counters(ctypes.Structure):
                _fields_ = [("cb", W.DWORD), ("PageFaultCount", W.DWORD)] + [(k, ctypes.c_size_t) for k in ("PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage", "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage", "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage")]
            kernel = ctypes.WinDLL("kernel32", use_last_error=True)
            kernel.OpenProcess.restype = W.HANDLE
            kernel.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
            kernel.CloseHandle.argtypes = [W.HANDLE]
            psapi = ctypes.WinDLL("psapi", use_last_error=True)
            psapi.GetProcessMemoryInfo.argtypes = [W.HANDLE, ctypes.POINTER(Counters), W.DWORD]
            handle = kernel.OpenProcess(0x0400 | 0x0010, False, process.pid)
        while process.poll() is None:
            if handle:
                counters = Counters()
                counters.cb = ctypes.sizeof(counters)
                if psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
                    peak = max(peak, counters.PeakWorkingSetSize)
            elif sys.platform.startswith("linux"):
                try:
                    for line in Path(f"/proc/{process.pid}/status").read_text().splitlines():
                        if line.startswith("VmHWM:"):
                            peak = max(peak, int(line.split()[1]) * 1024)
                except (FileNotFoundError, ProcessLookupError):
                    pass
            time.sleep(.01)
        if handle:
            kernel.CloseHandle(handle)
    print(json.dumps({"exit": process.returncode, "elapsed_ms": round((time.perf_counter()-start)*1000, 1), "observed_peak_rss_bytes": peak or None, "memory_method": "OS high-water working set/RSS, sampled every 10 ms; observed lower bound"}))
    return process.returncode

if __name__ == "__main__":
    raise SystemExit(main())
