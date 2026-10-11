"""What machine a run was on (specs only, nothing that identifies it) and how busy it was while the run went.

machine(): CPU model and count, memory, kernel, shell and Python versions. No hostname, user name, path, address or serial.
Sampler:   a thread that reads /proc every 250 ms; summary(t0, t1) says how loaded the machine was in a time window.
Linux only: on another system the fields are missing and the sampler records nothing."""
import hashlib
import os
import platform
import subprocess
import tempfile
import threading
import time


def _read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return ""


def _cpuinfo():
    model, phys, cores, flags = "", set(), 0, ""
    cur_phys = None
    for ln in _read("/proc/cpuinfo").splitlines():
        k, _, v = ln.partition(":")
        k, v = k.strip(), v.strip()
        if k in ("model name", "Model", "Hardware") and not model:
            model = v
        elif k == "physical id":
            cur_phys = v
            phys.add(v)
        elif k == "cpu cores" and not cores:
            cores = int(v) if v.isdigit() else 0
        elif k in ("flags", "Features") and not flags:
            flags = v
    return model, max(1, len(phys)) * cores if cores else 0, " " + flags + " "


def _tmp_fs():
    """Filesystem type of the directory the profiler's throw-away HOMEs live in (tmpfs and a disk differ for cache writes)."""
    tmp, best, fstype = os.path.realpath(tempfile.gettempdir()), "", ""
    for ln in _read("/proc/mounts").splitlines():
        p = ln.split()
        if len(p) > 2 and (tmp == p[1] or tmp.startswith(p[1].rstrip("/") + "/")) and len(p[1]) > len(best):
            best, fstype = p[1], p[2]
    return fstype


def _distro():
    kv = {}
    for ln in _read("/etc/os-release").splitlines():
        k, _, v = ln.partition("=")
        kv[k] = v.strip('"')
    return " ".join(x for x in (kv.get("NAME"), kv.get("VERSION_ID")) if x)


def _bash_version():
    try:
        out = subprocess.check_output(["bash", "-c", 'printf %s "$BASH_VERSION"'], text=True, timeout=5)
        return out.split("(")[0]
    except (OSError, subprocess.SubprocessError):
        return ""


def machine(rows=None, cols=None):
    """Anonymized specs of this machine plus a short id (hash of the specs) to tell two machines apart in a comparison."""
    model, physical, flags = _cpuinfo()
    mem_kb = 0
    for ln in _read("/proc/meminfo").splitlines():
        if ln.startswith("MemTotal:"):
            mem_kb = int(ln.split()[1])
            break
    gov = _read("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor").strip()
    fmax = _read("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq").strip()
    virt = "container" if os.path.exists("/.dockerenv") else "vm" if " hypervisor " in flags else "bare metal"
    m = {
        "cpu_model": " ".join(model.split()),
        "logical_cpus": os.cpu_count() or 0,
        "physical_cores": physical,
        "cpu_max_mhz": int(fmax) // 1000 if fmax.isdigit() else None,
        "cpu_governor": gov or None,
        "ram_gb": round(mem_kb / 1048576, 1) if mem_kb else None,
        "arch": platform.machine(),
        "os": platform.system(),
        "distro": _distro(),
        "kernel": platform.release(),
        "virtualization": virt,
        "tmp_fs": _tmp_fs(),
        "bash": _bash_version(),
        "python": platform.python_version(),
        "terminal": f"{cols}x{rows}" if rows and cols else None,
    }
    ident = "|".join(str(m[k]) for k in ("cpu_model", "logical_cpus", "ram_gb", "arch", "kernel", "virtualization"))
    m["id"] = hashlib.sha1(ident.encode()).hexdigest()[:8]
    return m


def _cpu_times():
    """(busy jiffies, total jiffies) over all CPUs."""
    p = _read("/proc/stat").split("\n", 1)[0].split()[1:]
    v = [int(x) for x in p[:8]] if len(p) >= 8 else []
    if not v:
        return 0, 0
    idle = v[3] + v[4]   # idle + iowait
    return sum(v) - idle, sum(v)


def _mem_used_mb():
    avail = total = 0
    for ln in _read("/proc/meminfo").splitlines():
        if ln.startswith("MemTotal:"):
            total = int(ln.split()[1])
        elif ln.startswith("MemAvailable:"):
            avail = int(ln.split()[1])
    return (total - avail) // 1024 if total else 0


def _freq_mhz():
    """Mean current frequency over all CPUs, None when the kernel does not say."""
    vals = []
    base = "/sys/devices/system/cpu"
    try:
        for d in os.listdir(base):
            if d.startswith("cpu") and d[3:].isdigit():
                v = _read(f"{base}/{d}/cpufreq/scaling_cur_freq").strip()
                if v.isdigit():
                    vals.append(int(v) / 1000)
    except OSError:
        return None
    return sum(vals) / len(vals) if vals else None


class Sampler:
    """Reads machine load every `every` seconds on a thread. Samples: (time, cpu %, mem used MB, mean MHz, load1)."""

    def __init__(self, every=0.25):
        self.every, self.samples = every, []
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self.ncpu = os.cpu_count() or 1

    def start(self):
        self._thread.start()
        return self

    def stop(self):
        self._stop.set()
        self._thread.join(timeout=2)

    def _run(self):
        busy0, tot0 = _cpu_times()
        while not self._stop.wait(self.every):
            busy1, tot1 = _cpu_times()
            dt = tot1 - tot0
            pct = 100.0 * (busy1 - busy0) / dt if dt > 0 else 0.0
            busy0, tot0 = busy1, tot1
            try:
                load1 = float(_read("/proc/loadavg").split()[0])
            except (IndexError, ValueError):
                load1 = None
            self.samples.append((time.time(), pct, _mem_used_mb(), _freq_mhz(), load1))

    def summary(self, t0, t1, app_cpu_s=None, app_rss_kb=None):
        """Load in [t0, t1]. busy_cores = how many CPUs' worth of work the machine did; with the app's own CPU time
        given, other_cores = what was not the app (something else was running)."""
        win = [s for s in self.samples if t0 <= s[0] <= t1]
        out = {"wall_s": t1 - t0, "samples": len(win)}
        if win:
            cpu = sorted(s[1] for s in win)
            mean = sum(cpu) / len(cpu)
            out.update(sys_cpu_pct_mean=mean, sys_cpu_pct_p95=cpu[min(len(cpu) - 1, int(len(cpu) * 0.95))], sys_cpu_pct_max=cpu[-1],
                       busy_cores=mean / 100 * self.ncpu, mem_used_mb_max=max(s[2] for s in win))
            fr = [s[3] for s in win if s[3]]
            if fr:
                out["freq_mhz_mean"], out["freq_mhz_min"] = sum(fr) / len(fr), min(fr)
        if app_cpu_s is not None and t1 > t0:
            out["app_cores"] = app_cpu_s / (t1 - t0)
            if "busy_cores" in out:
                out["other_cores"] = max(0.0, out["busy_cores"] - out["app_cores"])
        if app_rss_kb:
            out["app_rss_mb_max"] = app_rss_kb / 1024
        return out
