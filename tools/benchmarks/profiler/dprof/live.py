"""The profiler's live progress: the shared LiveUI (tools/benchmarks/reporting/live.py) rated against the scenario file's groups."""
from reporting.live import LiveUI as _LiveUI, NullLive, mmss, eta_str   # noqa: F401
from . import scenarios


class LiveUI(_LiveUI):
    def __init__(self, phases, out=None, tty=None, events=None):
        super().__init__(phases, out=out, tty=tty, events=events, info_of=lambda group: scenarios.GROUP_INFO.get(group))
