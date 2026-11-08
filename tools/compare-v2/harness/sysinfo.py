"""Environment capture and 'is this machine quiet enough to measure' checks."""
import os
import platform
import subprocess
import sys
import time


def _read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def cpu_groups():
    """SMT sibling groups [[0,6],[1,7],...] (physical cores), or [] if unknown."""
    groups = set()
    for i in range(os.cpu_count() or 1):
        s = _read(f"/sys/devices/system/cpu/cpu{i}/topology/thread_siblings_list")
        if s:
            ids = []
            for part in s.split(","):
                lo, _, hi = part.partition("-")
                ids += range(int(lo), int(hi or lo) + 1)
            groups.add(tuple(ids))
    return sorted(groups)


def parse_cpus(s):
    out = set()
    for part in s.split(","):
        lo, _, hi = part.partition("-")
        out |= set(range(int(lo), int(hi or lo) + 1))
    return out


def pick_pinning(spec):
    """'auto' | 'single' | 'none' | 'APPCPUS:HARNESSCPUS' -> (app_cpus|None, harness_cpus|None).
    auto:   harness on the last physical core, app free on all the others (the harness's polling never competes with the app,
            and multi-process apps like DABT keep the parallelism a real user would have)
    single: app on one physical core only (lowest noise, but penalises multi-process designs)"""
    if spec == "none":
        return None, None
    if ":" in spec:
        a, h = spec.split(":")
        return parse_cpus(a), parse_cpus(h)
    groups = cpu_groups()
    if len(groups) >= 3:
        rest = {c for g in groups[:-1] for c in g}
        return (set(groups[-2]) if spec == "single" else rest), set(groups[-1])
    n = os.cpu_count() or 1
    return (set(range(n - 1)), {n - 1}) if n >= 3 else (None, None)


def busy_pct(cpus, seconds=0.5):
    """Average busy % of the given CPUs over a short window (from /proc/stat), to detect a noisy machine."""
    def snap():
        out = {}
        for line in _read("/proc/stat").splitlines():
            p = line.split()
            if p and p[0].startswith("cpu") and p[0] != "cpu":
                v = list(map(int, p[1:9]))
                out[int(p[0][3:])] = (sum(v), v[3] + v[4])
        return out
    a = snap()
    time.sleep(seconds)
    b = snap()
    use = [100 * (1 - (b[c][1] - a[c][1]) / max(1, b[c][0] - a[c][0])) for c in (cpus or b) if c in a and c in b]
    return sum(use) / len(use) if use else 0.0


def git_info(repo):
    try:
        rev = subprocess.run(["git", "-C", repo, "rev-parse", "--short", "HEAD"], capture_output=True, text=True, timeout=5).stdout.strip()
        dirty = bool(subprocess.run(["git", "-C", repo, "status", "--porcelain"], capture_output=True, text=True, timeout=5).stdout.strip())
        return rev + ("+dirty" if dirty else "")
    except (OSError, subprocess.SubprocessError):
        return ""


def collect(repo, app_cpus, harness_cpus):
    model = next((ln.split(":", 1)[1].strip() for ln in _read("/proc/cpuinfo").splitlines() if ln.startswith("model name")), "")
    info = {
        "cpu": model, "logical_cpus": os.cpu_count(), "kernel": platform.release(), "python": sys.version.split()[0],
        "governor": _read("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor", "n/a"),
        "boost": _read("/sys/devices/system/cpu/cpufreq/boost", "n/a"),
        "loadavg": _read("/proc/loadavg").split()[:3], "mem_gb": round(int(_read("/proc/meminfo").split()[1]) / 1048576, 1),
        "bash": subprocess.run(["bash", "-c", "echo $BASH_VERSION"], capture_output=True, text=True).stdout.strip(),
        "git": git_info(repo), "term": "xterm-256color", "pinned_app": sorted(app_cpus) if app_cpus else None,
        "pinned_harness": sorted(harness_cpus) if harness_cpus else None,
    }
    warn = []
    ncpu = os.cpu_count() or 1
    if info["governor"] not in ("performance", "n/a"):
        warn.append(f"CPU governor is '{info['governor']}': frequency scaling adds run-to-run noise (use 'performance' for publishable numbers).")
    if float(info["loadavg"][0]) > max(1.0, 0.25 * ncpu):
        warn.append(f"1-min load average is {info['loadavg'][0]} on {ncpu} CPUs: other work is competing.")
    busy = busy_pct(app_cpus)
    info["busy_pct"] = round(busy, 1)
    if busy > 5:
        warn.append(f"the app's CPUs are {busy:.0f}% busy before the run starts.")
    if not app_cpus:
        warn.append("not pinned to CPUs: the scheduler may move the app and the harness between cores.")
    return info, warn
