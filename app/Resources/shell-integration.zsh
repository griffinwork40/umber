# shell-integration.zsh — Umber terminal shell integration for zsh.
#
# What this enables:
#   OSC 7  — tells Umber where the shell is on every prompt, so the sidebar
#            follows the shell without polling the kernel every 750ms.
#   OSC 133 A/C/D — command lifecycle boundaries, so Umber can mark a tab
#            when a command fails or a long-running build finishes while you
#            were looking elsewhere.
#
# How to install:
#   Add to ~/.zshrc (after oh-my-zsh / prezto / zi init if you use one):
#
#     [[ -n "$UMBER_INTEGRATION" ]] && source "$UMBER_INTEGRATION"
#
#   Umber sets UMBER_INTEGRATION to the path of this script in the shell
#   environment. If you prefer to source explicitly:
#
#     source /path/to/Umber.app/Contents/Resources/shell-integration.zsh
#
# Guard: only activates when TERM_PROGRAM is Umber. Sourcing in another
# terminal is a no-op, so this block is safe to leave in your .zshrc
# unconditionally.

[[ "$TERM_PROGRAM" == "Umber" ]] || return 0

# ── helpers ──────────────────────────────────────────────────────────────────

# Emit an OSC sequence. BEL (\a) is the terminator — shorter than ST (ESC \)
# and universally understood by SwiftTerm.
_umber_osc() {
    printf '\033]%s\a' "$1"
}

# RFC 3986 percent-encode a path. Only the characters that are unsafe inside a
# file:// URL are encoded; '/' is left unencoded (it is a path separator, not
# data). Implemented in pure zsh so this file has no external dependency.
_umber_urlencode() {
    local string="$1" encoded="" i char
    for (( i = 0; i < ${#string}; i++ )); do
        char="${string:$i:1}"
        case "$char" in
            [a-zA-Z0-9_.~/-]) encoded+="$char" ;;
            *) encoded+=$(printf '%%%02X' "'$char") ;;
        esac
    done
    printf '%s' "$encoded"
}

# ── OSC 133 hooks ─────────────────────────────────────────────────────────────

# precmd fires AFTER a command, BEFORE the prompt is drawn.
# Order within precmd: D first (command ended), then A (prompt starting).
# Both are emitted in a single precmd function registered with add-zsh-hook so
# the ordering is guaranteed — two separate hooks could interleave.
_umber_precmd() {
    local exit_status=$?  # capture before anything else changes $?

    # OSC 133 D — command finished. Only emit if a command actually ran (i.e.
    # preexec ran before this precmd). The _umber_cmd_running guard prevents a
    # spurious D on the very first prompt after sourcing, before any command.
    if [[ -n "$_umber_cmd_running" ]]; then
        _umber_osc "133;D;${exit_status}"
        unset _umber_cmd_running
    fi

    # OSC 133 A — prompt start. Tells Umber the shell is about to draw a prompt.
    _umber_osc "133;A"

    # OSC 7 — current working directory. Emitted here (in precmd) so Umber knows
    # where the shell is as soon as the prompt is visible. SwiftTerm accepts the
    # file://hostname/path format; the hostname is included per the spec so the
    # terminal can ignore OSC 7 from a remote shell in a local tab.
    local url_path
    url_path="$(_umber_urlencode "$PWD")"
    _umber_osc "7;file://${HOST}${url_path}"
}

# preexec fires after the user presses Return and before the command runs.
_umber_preexec() {
    # OSC 133 C — command start. Marks the moment the shell hands control to the
    # user's command, so Umber can measure how long it ran.
    _umber_osc "133;C"
    _umber_cmd_running=1
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd  _umber_precmd
add-zsh-hook preexec _umber_preexec
