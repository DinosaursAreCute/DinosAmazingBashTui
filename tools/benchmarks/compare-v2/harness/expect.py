"""Screen predicates. A step is 'done' when its Expect is true on the emulated screen, not when some bytes were seen."""
import re


class View:
    """Read-only view of the emulated screen handed to predicates (computed lazily, once per frame)."""

    def __init__(self, screen):
        self._s = screen
        self._lines = None

    def invalidate(self):
        self._lines = None

    @property
    def lines(self):
        if self._lines is None:
            self._lines = [ln.rstrip() for ln in self._s.display]
        return self._lines

    @property
    def text(self):
        return "\n".join(self.lines)

    @property
    def cursor(self):
        return self._s.cursor.x, self._s.cursor.y

    def line(self, n):
        """Row n (0-based) or ''."""
        return self.lines[n] if 0 <= n < len(self.lines) else ""


class Expect:
    def __init__(self, fn, desc):
        self.fn, self.desc = fn, desc

    def __call__(self, view):
        return bool(self.fn(view))

    def __and__(self, o):
        o = as_expect(o)
        return Expect(lambda v: self(v) and o(v), f"{self.desc} & {o.desc}")

    def __or__(self, o):
        o = as_expect(o)
        return Expect(lambda v: self(v) or o(v), f"({self.desc} | {o.desc})")

    def __invert__(self):
        return Expect(lambda v: not self(v), f"not {self.desc}")

    def __repr__(self):
        return self.desc


def text(s):
    """The screen contains s."""
    return Expect(lambda v: s in v.text, repr(s))


def absent(s):
    """The screen does not contain s."""
    return ~text(s)


def regex(pattern, flags=0):
    rx = re.compile(pattern, flags)
    return Expect(lambda v: rx.search(v.text) is not None, f"/{pattern}/")


def row(n, s):
    """Row n (0-based) contains s."""
    return Expect(lambda v: s in v.line(n), f"row {n} has {s!r}")


def where(fn, desc="custom"):
    """Any callable(View) -> bool."""
    return Expect(fn, desc)


def as_expect(x):
    if x is None or isinstance(x, Expect):
        return x
    if isinstance(x, str):
        return text(x)
    if callable(x):
        return where(x, getattr(x, "__name__", "custom"))
    raise TypeError(f"not an expectation: {x!r}")
