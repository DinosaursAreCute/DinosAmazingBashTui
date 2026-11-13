"""The two existing comparison apps in tools/compare (same 4 pages, same behaviour), plus DABT with a painted background."""
import os

from harness.apps import App, register
from harness.versions import PYTHON, ROOT, dabt_version, textual_version

SRC = os.path.join(ROOT, "tools", "compare")


register(App("dabt", "DABT", lambda home: ["bash", os.path.join(SRC, "dabt_app", "run.sh")], color="cyan",
             background_done="Page cache ready", version=dabt_version))
register(App("dabt-themed", "DABT (themed)", lambda home: ["bash", os.path.join(SRC, "dabt_app", "run.sh"), "--themed"], color="blue",
             background_done="Page cache ready", version=dabt_version))
register(App("textual", "Textual", lambda home: [PYTHON, os.path.join(SRC, "textual_app", "app.py")],
             color="magenta", version=textual_version))
