"""Process-tree resource probe (/proc). CPU is summed over every live process and thread of the app plus the CPU of
children it has already reaped, so short-lived subshells (DABT forks a lot) are not missed.

CPU resolution: live threads come from schedstat (ns). Reaped children and exited threads are only exposed by the kernel
in clock ticks (10 ms), so a single reading can be off by up to one tick for those; sums over many steps and the
whole-run total are not biased by it."""
import os

TICK_NS = 1_000_000_000 // os.sysconf("SC_CLK_TCK")


def _stat_fields(pid):
    with open(f"/proc/{pid}/stat") as f:
        raw = f.read()
    return raw[raw.rindex(")") + 2:].split()  # [0]=state [1]=ppid [11]=utime [12]=stime [13]=cutime [14]=cstime


class Probe:
    def __init__(self, root):
        self.root = root

    def tree(self):
        """Root pid and all its descendants that are alive right now."""
        kids = {}
        for e in os.listdir("/proc"):
            if e.isdigit():
                try:
                    kids.setdefault(int(_stat_fields(e)[1]), []).append(int(e))
                except (OSError, ValueError, IndexError):
                    pass
        out, todo = [], [self.root]
        while todo:
            p = todo.pop()
            out.append(p)
            todo.extend(kids.get(p, ()))
        return out

    def cpu_ns(self):
        total = 0
        for pid in self.tree():
            try:
                f = _stat_fields(pid)
                ticks = (int(f[11]) + int(f[12])) * TICK_NS
                live = 0
                for tid in os.listdir(f"/proc/{pid}/task"):
                    try:
                        with open(f"/proc/{pid}/task/{tid}/schedstat") as s:
                            live += int(s.read().split()[0])
                    except (OSError, ValueError, IndexError):
                        pass
                # schedstat is exact for live threads but forgets exited ones; the tick count remembers them. The larger one is right.
                total += max(live, ticks) + (int(f[13]) + int(f[14])) * TICK_NS
            except (OSError, ValueError, IndexError):
                pass
        return total

    def mem(self):
        """{'rss_kb','pss_kb','procs','threads'} summed over the tree. PSS splits shared pages between their users (fair across runtimes)."""
        rss = pss = threads = 0
        pids = self.tree()
        for pid in pids:
            try:
                with open(f"/proc/{pid}/smaps_rollup") as f:
                    for line in f:
                        if line.startswith("Rss:"):
                            rss += int(line.split()[1])
                        elif line.startswith("Pss:"):
                            pss += int(line.split()[1])
                threads += len(os.listdir(f"/proc/{pid}/task"))
            except OSError:
                pass
        return {"rss_kb": rss, "pss_kb": pss, "procs": len(pids), "threads": threads}
