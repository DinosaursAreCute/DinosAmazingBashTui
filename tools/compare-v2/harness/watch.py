"""--watch: mirror the app's output into a second window of the test size. The viewer machinery (Hyprland-aware window sizing, FIFO
replay, kitty/ghostty/alacritty) is shared with the profiler and loaded from tools/profiler/dprof/watch.py instead of copied.
Mirroring costs a write per pty read, so a watched run is for looking, not for comparing timings."""
import importlib.util
import os

SRC = os.path.join(os.path.dirname(__file__), "..", "..", "profiler", "dprof", "watch.py")


def open_viewer(rows, cols):
    if not os.path.exists(SRC):
        raise SystemExit(f"--watch needs {os.path.normpath(SRC)}")
    spec = importlib.util.spec_from_file_location("shared_watch", SRC)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.Watch(rows, cols)
