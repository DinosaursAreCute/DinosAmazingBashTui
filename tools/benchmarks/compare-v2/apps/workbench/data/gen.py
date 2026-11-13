"""Deterministic data of the workbench app. The Textual app and the scenario import this; the DABT app generates the same tasks in bash
(callbacks.sh: wb_seed_tasks) and reads logs.txt directly, so any change here must be mirrored there."""


def make_tasks():
    owners = ["ada", "bob", "cy", "dee", "eli", "fay"]
    states = ["open", "done", "blocked"]
    verbs = ["Fix", "Review", "Ship", "Plan", "Test", "Draft"]
    things = ["parser", "cache", "login", "theme", "report", "build"]
    return [(f"T-{i:04d}", f"{verbs[i % 6]} {things[i // 6 % 6]} {i}", owners[i % 6], states[i % 3]) for i in range(1, 201)]


def logs():
    """The 2000 log lines: a static file, read by both apps (never generated at run time)."""
    import os
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs.txt")) as f:
        return f.read().splitlines()


def filter_count(needle, tasks=None):
    """Rows left after typing `needle` into the Tasks filter."""
    tasks = tasks or make_tasks()
    return sum(1 for r in tasks if needle.lower() in "|".join(r).lower())
