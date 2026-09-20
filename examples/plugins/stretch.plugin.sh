# plugin: stretch
# title: Stretch reminder
# version: 1.0
# description: Reminds you to stand up and stretch every few minutes. The plugin built in "Writing Your First Plugin".
# author: you
# default: off

# ── called once when the plugin is switched on ───────────────────────────
plugin.stretch.on_enable() {
    STRETCH_COUNT=0 STRETCH_TICKS=0
    STRETCH_MINUTES="$(tui.config.get plugin.stretch.minutes 30)"          # your saved setting, 30 the first time

    tui.every $(( STRETCH_MINUTES * 60 )) stretch_tick stretch_timer     # a timer: call stretch_tick on an interval
    tui.cmd.add stretch.now  "Stretch: remind me now"       stretch_remind --group Stretch --desc "Shows the reminder right away"
    tui.cmd.add stretch.more "Stretch: remind more often"   stretch_more   --group Stretch --desc "Halves the interval"
    tui.cmd.add stretch.less "Stretch: remind less often"   stretch_less   --group Stretch --desc "Doubles the interval"
    tui.bind alt+s stretch_remind --desc "Stretch reminder"
}

# ── called when it is switched off (optional; the registrations above are undone for you) ──
plugin.stretch.on_disable() { tui.notify "Stretch reminders off" info 2; }

# ── the plugin's own functions ───────────────────────────────────────────
stretch_remind() {
    (( STRETCH_COUNT++ ))
    tui.notify "Stand up and stretch! (reminder #$STRETCH_COUNT)" warn 8
}
# tui.every runs its function once right away, then on every interval: skip that first call
stretch_tick() { (( STRETCH_TICKS++ )) || return 0; stretch_remind; }
stretch_set() {          # MINUTES: remember it, restart the timer with the new interval
    STRETCH_MINUTES="$1"
    tui.plugin.config stretch minutes "$1"
    tui.every.cancel stretch_timer
    STRETCH_TICKS=0; tui.every $(( STRETCH_MINUTES * 60 )) stretch_tick stretch_timer
    tui.notify "Reminding you every $STRETCH_MINUTES minute(s)" info 3
}
stretch_more() { stretch_set $(( STRETCH_MINUTES > 1 ? STRETCH_MINUTES / 2 : 1 )); }
stretch_less() { stretch_set $(( STRETCH_MINUTES * 2 )); }
