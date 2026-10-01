#!/usr/bin/env bash
# Verifies the built release tarball. Run after `make`.
#
# Guards:
#   1. Expected payload: launcher, config.yaml, license, electron runtime,
#      and none of upstream's agent skills.
#   2. Only the executables that must be executed carry an exec bit (Rune
#      copies every executable onto PATH), and the launcher is the last one,
#      so it owns the terminal-browser name on PATH.
#   3. Patched JS disables setup and keeps writable output under Rune data.
#   4. The launcher uses only the supplied absolute Rune data directory.
#   5. On darwin hosts, the macOS app's signature still verifies.
set -euo pipefail

TAR="${TAR:-browser.tar.gz}"
TARGET_OS="${TARGET_OS:-$(uname | tr '[:upper:]' '[:lower:]')}"

[ -f "$TAR" ] || { echo "error: $TAR not found; run 'make' first" >&2; exit 1; }

members="$(tar -tzf "$TAR")"

case "$TARGET_OS" in
darwin)
	electron=./electron/terminal-browser.app/Contents/MacOS/terminal-browser
	want_exec="./agent-browser/bin/agent-browser ./bin/native-scroll-helper ./bin/terminal-browser"
	;;
linux)
	electron=./electron/pixel
	want_exec="./agent-browser/bin/agent-browser ./bin/terminal-browser ./electron/chrome-sandbox ./electron/chrome_crashpad_handler ./electron/pixel"
	;;
*) echo "error: unsupported TARGET_OS $TARGET_OS" >&2; exit 1 ;;
esac

for want in ./bin/terminal-browser ./config.yaml ./cli/dist/main.js \
	./licenses/terminal-browser/LICENSE "$electron"; do
	grep -qxF "$want" <<<"$members" || {
		echo "error: $TAR is missing '$want'" >&2
		exit 1
	}
done
if grep -q '^\./skills/' <<<"$members"; then
	echo "error: $TAR still bundles upstream's agent skills" >&2
	exit 1
fi
echo "ok: expected payload present"

# Regular files with any exec bit, in archive order.
execs="$(python3 -c '
import sys, tarfile
for m in tarfile.open(sys.argv[1]):
    if m.isreg() and m.mode & 0o111:
        print(m.name)
' "$TAR")"
last="$(printf '%s\n' "$execs" | tail -1)"
if [ "$last" != ./bin/terminal-browser ]; then
	echo "error: last executable is '$last', want ./bin/terminal-browser" >&2
	exit 1
fi

# On darwin the Electron executable and its helpers must stay executable too.
required_exec() {
	case " $want_exec " in *" $1 "*) return 0 ;; esac
	[ "$TARGET_OS" = darwin ] || return 1
	case "$1" in
	./electron/terminal-browser.app/Contents/MacOS/* | \
		*"/Electron Helper"*.app/Contents/MacOS/* | \
		*/Helpers/chrome_crashpad_handler) return 0 ;;
	esac
	return 1
}
unexpected=""
while read -r f; do
	required_exec "$f" || unexpected="$unexpected$f"$'\n'
done <<<"$execs"
if [ -n "$unexpected" ]; then
	echo "error: unexpected executables would be published onto PATH:" >&2
	printf '%s\n' "$unexpected" >&2
	exit 1
fi
echo "ok: only required executables, launcher last"

# Inspect the packaged files, not the staging tree. These anchors cover both
# removed side effects and their Rune-local replacements.
python3 - "$TAR" <<'PY'
import sys
import tarfile

with tarfile.open(sys.argv[1], "r:gz") as archive:
    cli = archive.extractfile("./cli/dist/main.js").read().decode()
    browser = archive.extractfile("./browser/dist/main.js").read().decode()
    package_config = archive.extractfile("./config.yaml").read().decode()
    upstream_license = archive.extractfile("./licenses/terminal-browser/LICENSE").read().decode()
    launcher_source = archive.extractfile("./bin/terminal-browser").read().decode()

assert "skills" not in package_config
assert 'browser: terminalnewtab terminal-browser $1' in package_config
assert 'pkg install browser' in launcher_source
assert 'ROOT="$RUNE_DATADIR/lib/browser"' in launcher_source
assert 'Zenbu Labs, Inc.' in upstream_license
assert 'ripgrep' not in upstream_license

for forbidden in (
    'if (command !== "setup") ensureSetup();',
    'const sandbox = apparmorSetup(electronBinary());',
    '      apparmorSetup(electron);',
    'import_node_path9.default.join(import_node_os5.default.homedir(), ".terminal-browser", "logs")',
):
    assert forbidden not in cli, f"unexpected CLI side effect: {forbidden}"
assert 'if (command === "setup") fail("setup is disabled in the Rune package");' in cli
assert 'var LOG_DIR = LOGS_DIR;' in cli
assert 'var OUTPUT_ROOT = import_node_path9.default.join(DATA_DIR, "recordings");' in browser
assert 'var OUTPUT_ROOT = "/tmp/recordings";' not in browser
PY
echo "ok: patched JS invariants"

# Use a stub executable, so this checks the launcher without starting Electron
# or running a browser command. Keep HOME outside the simulated Rune data dir.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar -xzf "$TAR" -C "$tmp" ./bin/terminal-browser
launcher="$tmp/bin/terminal-browser"
mkdir -p "$tmp/home" "$tmp/rune/lib/browser/electron"
cat > "$tmp/rune/lib/browser/electron/pixel" <<'SH'
#!/bin/sh
printf '%s\n' "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" \
    "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR" "$TMPDIR" \
    "$TERMINAL_BROWSER_INTEROP_DIR" "$TERMINAL_BROWSER_APPDATA" \
    "$TERMINAL_BROWSER_CONFIG_DIR" "$TERMINAL_BROWSER_DIST_ROOT" \
    "$1" "$2"
SH
chmod +x "$tmp/rune/lib/browser/electron/pixel"
if (cd "$tmp/home" && env -u RUNE_DATADIR HOME="$tmp/home" "$launcher" --help) >"$tmp/unset.out" 2>&1; then
    echo 'error: launcher accepts unset RUNE_DATADIR' >&2; exit 1
fi
if (cd "$tmp/home" && RUNE_DATADIR=relative HOME="$tmp/home" "$launcher" --help) >"$tmp/relative.out" 2>&1; then
    echo 'error: launcher accepts relative RUNE_DATADIR' >&2; exit 1
fi
HOME="$tmp/home" RUNE_DATADIR="$tmp/rune" "$launcher" --help >"$tmp/actual.out"
printf '%s\n' \
    "$tmp/rune/terminal-browser/data" "$tmp/rune/terminal-browser/state" \
    "$tmp/rune/terminal-browser/cache" "$tmp/rune/terminal-browser/config" \
    "$tmp/rune/terminal-browser/runtime" "$tmp/rune/terminal-browser/tmp" \
    "$tmp/rune/terminal-browser/interop" "$tmp/rune/terminal-browser/appdata" \
    "$tmp/rune/terminal-browser/config/terminal-browser" \
    "$tmp/rune/lib/browser" "$tmp/rune/lib/browser/cli/dist/main.js" \
    '--help' >"$tmp/expected.out"
diff -u "$tmp/expected.out" "$tmp/actual.out"
if [ -n "$(ls -A "$tmp/home")" ] || [ -e "$tmp/home/relative" ]; then
    echo 'error: launcher wrote outside RUNE_DATADIR' >&2; exit 1
fi
echo "ok: launcher data directory isolation"

if [ "$TARGET_OS" = darwin ] && command -v codesign >/dev/null; then
	tar -xzf "$TAR" -C "$tmp" ./electron
	codesign --verify --deep --strict "$tmp/electron/terminal-browser.app"
	echo "ok: macOS app signature verifies"
fi