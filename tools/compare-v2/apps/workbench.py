"""The workbench benchmark app: one spec (apps/workbench/SPEC.md), implemented in DABT and idiomatically in Textual."""
import os

from harness.apps import App, register
from harness.versions import PYTHON, dabt_version, textual_version

HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "workbench")

register(App("wb-dabt", "DABT", lambda home: ["bash", os.path.join(HERE, "dabt", "run.sh")], color="cyan",
             background_done="Page cache ready", version=dabt_version))
register(App("wb-textual", "Textual", lambda home: [PYTHON, os.path.join(HERE, "textual", "app.py")],
             color="magenta", version=textual_version))
register(App("wb-dabt-plain", "DABT (plain headings)", lambda home: ["bash", os.path.join(HERE, "dabt", "run.sh")], color="blue",
             env={"WB_PLAIN_HEADINGS": "1"}, background_done="Page cache ready", version=dabt_version))
