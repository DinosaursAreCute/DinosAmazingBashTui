"""Paths and version strings shared by app definitions."""
import os
import subprocess

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
VENV = os.environ.get("COMPARE_VENV", os.path.expanduser("~/.cache/dabt-compare-venv"))
PYTHON = os.path.join(VENV, "bin", "python")


def dabt_version():
    path = os.path.join(ROOT, "VERSION")
    return "DABT " + (open(path).read().strip() if os.path.exists(path) else "?")


def textual_version():
    try:
        out = subprocess.run([PYTHON, "-c", "import textual,sys;print(textual.__version__, sys.version.split()[0])"],
                             capture_output=True, text=True, timeout=20).stdout.split()
        return f"Textual {out[0]} / Python {out[1]}"
    except (OSError, IndexError, subprocess.SubprocessError):
        return "Textual ?"
