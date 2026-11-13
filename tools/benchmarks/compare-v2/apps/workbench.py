"""The workbench benchmark app: one spec (apps/workbench/SPEC.md), implemented in DABT and idiomatically in Textual."""
import os
import shutil
import subprocess

from harness.apps import App, register
from harness.versions import PYTHON, dabt_version, textual_version

HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "workbench")

register(App("wb-dabt", "DABT", lambda home: ["bash", os.path.join(HERE, "dabt", "run.sh")], color="cyan",
             background_done="Page cache ready", version=dabt_version))
register(App("wb-textual", "Textual", lambda home: [PYTHON, os.path.join(HERE, "textual", "app.py")],
             color="magenta", version=textual_version))
UNTHEMED = os.path.join(HERE, "dabt-unthemed")


def dabt_unthemed_prepare(home):
    """Generates apps/workbench/dabt-unthemed: the DABT app with every <theme> tag removed, so it runs on the framework's default look.
    Same depth as dabt/, so run.sh's lib path and callbacks.sh's ../data keep working. Regenerated when a source is newer."""
    src = os.path.join(HERE, "dabt")
    names = [n for n in os.listdir(src) if not n.endswith(".pyc") and os.path.isfile(os.path.join(src, n))]
    stamp = os.path.join(UNTHEMED, ".stamp")
    if os.path.exists(stamp) and all(os.path.getmtime(os.path.join(src, n)) <= os.path.getmtime(stamp) for n in names):
        return
    os.makedirs(UNTHEMED, exist_ok=True)
    for n in names:
        text = open(os.path.join(src, n)).read()
        if n.endswith(".xml"):
            text = "".join(l for l in text.splitlines(True) if "<theme " not in l)
        with open(os.path.join(UNTHEMED, n), "w") as f:
            f.write(text)
        os.chmod(os.path.join(UNTHEMED, n), os.stat(os.path.join(src, n)).st_mode)
    open(stamp, "w").close()


register(App("wb-dabt-unthemed", "DABT (unthemed)", lambda home: ["bash", os.path.join(UNTHEMED, "run.sh")], color="blue",
             prepare=dabt_unthemed_prepare, background_done="Page cache ready", version=dabt_version))
register(App("wb-dabt-plain", "DABT (plain headings)", lambda home: ["bash", os.path.join(HERE, "dabt", "run.sh")], color="blue",
             env={"WB_PLAIN_HEADINGS": "1"}, background_done="Page cache ready", version=dabt_version))


BT = os.path.join(HERE, "bubbletea")
BT_BIN = os.path.join(BT, "wb-bubbletea")


def bubbletea_prepare(home):
    """Builds the Go binary once (install.sh: dependency download + go build); a rebuild only happens when the sources are newer."""
    srcs = [os.path.join(BT, f) for f in os.listdir(BT) if f.endswith(".go") or f == "go.mod"]
    if not os.path.exists(BT_BIN) or any(os.path.getmtime(f) > os.path.getmtime(BT_BIN) for f in srcs):
        subprocess.run(["bash", os.path.join(BT, "install.sh")], check=True)


def bubbletea_version():
    go = subprocess.run(["go", "env", "GOVERSION"], capture_output=True, text=True).stdout.strip() if shutil.which("go") else "go ?"
    return f"Bubble Tea v1.3.4 / {go}"


register(App("wb-bubbletea", "Bubble Tea", lambda home: [BT_BIN], color="green", prepare=bubbletea_prepare, version=bubbletea_version))
