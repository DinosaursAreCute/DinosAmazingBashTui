# plugin: hello
# title: Hello
# version: 1.0
# description: A tiny example: a command-bar command, a key, a page hook and a timer, all cleaned up when disabled.
# author: DABT
# default: off

plugin.hello.on_enable() {
    tui.cmd.add hello.say "Hello: say hello" hello_say --group Hello --desc "Shows a toast"
    tui.bind alt+h hello_say --desc "Say hello"
    tui.hook.on page hello_on_page
    tui.every 30 hello_tick hello_timer
}

plugin.hello.on_disable() { tui.notify "Hello plugin disabled" info 2; }

hello_say()     { tui.notify "Hello from a plugin!" success; }
hello_on_page() { HELLO_LAST_PAGE="$1"; }
hello_tick()    { HELLO_TICKS=$(( ${HELLO_TICKS:-0} + 1 )); }
