"""Input encodings. Everything is bytes, written to the app's pty exactly as a terminal would send it (1-based cells)."""
UP, DOWN, RIGHT, LEFT = b"\x1b[A", b"\x1b[B", b"\x1b[C", b"\x1b[D"
HOME, END, PGUP, PGDN = b"\x1b[H", b"\x1b[F", b"\x1b[5~", b"\x1b[6~"
ENTER, TAB, ESC, BACKSPACE, SPACE = b"\r", b"\t", b"\x1b", b"\x7f", b" "
SHIFT_TAB = b"\x1b[Z"


class Chord(bytes):
    """A modified key. The bytes are the legacy encoding every terminal sends; `.kitty` is the CSI-u form a terminal sends once the app
    has pushed kitty keyboard flags (Session.send picks the one the app negotiated, like the real terminal would)."""
    kitty = b""


def _chord(legacy, kitty):
    c = Chord(legacy)
    c.kitty = kitty
    return c


def ctrl(ch):
    """Ctrl+<letter>."""
    return _chord(bytes([ord(ch.lower()) & 0x1F]), b"\x1b[%d;5u" % ord(ch.lower()))


def click(x, y, button=0):
    """SGR mouse press + release at column x, row y."""
    return f"\x1b[<{button};{x};{y}M\x1b[<{button};{x};{y}m".encode()


def move(x, y):
    """SGR mouse motion with no button held."""
    return f"\x1b[<35;{x};{y}M".encode()


def wheel(x, y, up=True):
    """One scroll-wheel notch."""
    return f"\x1b[<{64 if up else 65};{x};{y}M".encode()


def paste(text):
    """Bracketed paste."""
    return b"\x1b[200~" + text.encode() + b"\x1b[201~"


def chars(text):
    """A string as one byte string per character (for typing with a gap between keys)."""
    return [c.encode() for c in text]
CTRL_END, CTRL_HOME = b"\x1b[1;5F", b"\x1b[1;5H"


def alt(ch):
    """Alt+<char>: ESC prefix in the legacy encoding."""
    return _chord(b"\x1b" + ch.encode(), b"\x1b[%d;3u" % ord(ch))
