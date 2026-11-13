"""Imports every .py in a directory so its decorators/registrations run. Used for scenarios/, apps/ and --plugins dirs."""
import importlib.util
import os


def load_dir(path):
    if not os.path.isdir(path):
        return
    for f in sorted(os.listdir(path)):
        if f.endswith(".py") and not f.startswith("_"):
            spec = importlib.util.spec_from_file_location(f"cmp_plugin_{os.path.basename(path)}_{f[:-3]}", os.path.join(path, f))
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
