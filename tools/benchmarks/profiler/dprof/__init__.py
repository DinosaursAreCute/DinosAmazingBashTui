"""DABT profiler engine. The shared terminal toolkit and reporter live in tools/benchmarks/reporting."""
import os
import sys

_BENCHMARKS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _BENCHMARKS not in sys.path:
    sys.path.insert(0, _BENCHMARKS)
