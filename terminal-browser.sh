#!/bin/sh
# Launcher for the terminal-browser Rune package. Replaces upstream's
# bin/terminal-browser, which locates the install from $0: Rune copies
# package executables into $RUNE_DATADIR/bin, away from the package files, so
# the package is found through Rune's lib/ link instead.
if [ -z "${RUNE_DATADIR:-}" ]; then
	echo 'terminal-browser: RUNE_DATADIR is not set; launch from Rune' >&2
	exit 1
fi
case "$RUNE_DATADIR" in
	/*) ;;
	*) echo 'terminal-browser: RUNE_DATADIR must be an absolute path' >&2; exit 1 ;;
esac

ROOT="$RUNE_DATADIR/lib/browser"
STATE="$RUNE_DATADIR/terminal-browser"
umask 077
mkdir -p "$STATE/data" "$STATE/state" "$STATE/cache" "$STATE/config" \
	"$STATE/tmp" "$STATE/interop" "$STATE/appdata" || exit 1

# terminal-browser binds unix sockets about 70 bytes below XDG_RUNTIME_DIR,
# and a socket path must fit sun_path (103 bytes on macOS), which a runtime
# directory under RUNE_DATADIR does not leave room for. The sockets therefore
# live in a short directory that only this user can enter; /tmp is sticky, so
# nobody else can replace it once it exists.
RUNTIME="/tmp/rune-tb-$(id -u)"
mkdir -p "$RUNTIME" || exit 1
if [ -L "$RUNTIME" ] || [ ! -O "$RUNTIME" ]; then
	echo "terminal-browser: $RUNTIME is not a directory owned by $(id -un)" >&2
	exit 1
fi
chmod 700 "$RUNTIME" || exit 1

export XDG_DATA_HOME="$STATE/data"
export XDG_STATE_HOME="$STATE/state"
export XDG_CACHE_HOME="$STATE/cache"
export XDG_CONFIG_HOME="$STATE/config"
export XDG_RUNTIME_DIR="$RUNTIME"
export TMPDIR="$STATE/tmp"
export TMP="$TMPDIR" TEMP="$TMPDIR"
export TERMINAL_BROWSER_INTEROP_DIR="$STATE/interop"
export TERMINAL_BROWSER_APPDATA="$STATE/appdata"
export TERMINAL_BROWSER_CONFIG_DIR="$STATE/config/terminal-browser"

if [ "$1" = upgrade ]; then
	echo "terminal-browser is managed by Rune: run 'pkg install browser' in the Rune console to upgrade" >&2
	exit 1
fi

if [ "$1" = setup ]; then
	echo 'terminal-browser: setup is disabled in the Rune package (it changes files outside the Rune data directory)' >&2
	exit 1
fi

export TERMINAL_BROWSER_DIST_ROOT="$ROOT"
export ELECTRON_RUN_AS_NODE=1
if [ -d "$ROOT/electron/terminal-browser.app" ]; then
	export NATIVE_SCROLL_HELPER="${NATIVE_SCROLL_HELPER:-$ROOT/bin/native-scroll-helper}"
	exec "$ROOT/electron/terminal-browser.app/Contents/MacOS/terminal-browser" "$ROOT/cli/dist/main.js" "$@"
fi
exec "$ROOT/electron/pixel" "$ROOT/cli/dist/main.js" "$@"