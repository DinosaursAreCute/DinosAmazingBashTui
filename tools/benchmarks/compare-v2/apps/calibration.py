"""Reference app with known response times, used by `compare.py selftest`."""
import os
import sys

from harness.apps import App, register

register(App("calib", "calibration", lambda home: [sys.executable, os.path.join(os.path.dirname(__file__), "..", "harness", "calib_app.py")],
             color="green", version=lambda: "known delays"))
