# Sourced as bash's --rcfile for shells spawned by pty-server.ts, so the
# terminal in the deck behaves like the presenter's normal shell, plus a
# couple of demo niceties.
#
# Because --rcfile REPLACES the default startup file, the user's own
# ~/.bashrc has to be sourced explicitly first - otherwise the shell in
# the slide would lose their prompt, aliases and PATH tweaks.
if [ -f "$HOME/.bashrc" ]; then
  # shellcheck disable=SC1091
  . "$HOME/.bashrc"
fi

# kubectl emits no ANSI colour of its own. kubecolor is a drop-in wrapper
# that adds it (green Running, red Error, etc). Aliased rather than
# shimmed on PATH on purpose: kubecolor invokes the real kubectl binary
# via PATH, so a PATH shim named `kubectl` would make it call itself
# forever. Aliases don't apply to subprocesses, so this stays safe.
#
# The slides still show plain `kubectl` commands - that's what the
# audience should learn - they just render in colour here.
if command -v kubecolor >/dev/null 2>&1; then
  alias kubectl=kubecolor
fi

# Deliberately NOT setting FORCE_COLOR here. kubecolor already colours
# its output when stdout is a terminal, which is the case for every
# command typed directly. FORCE_COLOR additionally colours output going
# into a PIPE, which prepends an escape sequence to the payload and
# breaks anything downstream that parses it:
#
#   kubectl get --raw /apis/... | jq   ->  parse error: Invalid numeric
#                                          literal at line 1, column 2
#
# CLICOLOR is left on: it is only a hint that colour is welcome, and
# tools that honour it still respect a pipe.
export CLICOLOR=1
