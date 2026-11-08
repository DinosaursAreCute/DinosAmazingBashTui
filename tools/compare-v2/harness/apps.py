"""App registry. An app file in apps/ builds an App and calls register(); that is all it takes to add a contender."""
from dataclasses import dataclass, field
from typing import Callable, Optional

APPS = {}


@dataclass
class App:
    name: str
    label: str
    argv: Callable  # (home) -> list[str]
    color: str = "white"  # rich colour used in reports
    env: dict = field(default_factory=dict)
    prepare: Optional[Callable] = None  # (home) -> None, once per fresh HOME, before the first start
    background_done: Optional[str] = None  # screen text that means deferred work (cache warmup) finished; waited for after the cold start
    version: Optional[Callable] = None  # () -> str, recorded in the report


def register(app):
    APPS[app.name] = app
    return app
