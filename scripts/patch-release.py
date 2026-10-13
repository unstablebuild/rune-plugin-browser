#!/usr/bin/env python3
"""Adapt the pinned release's setup, writable paths, and viewport for Rune.

Replacements fail closed if the upstream JS bundle changes: bump the pin and
review upstream side effects before updating these anchors.
"""

from pathlib import Path
import sys


def patch(path: Path, replacements: list[tuple[str, str]]) -> None:
    contents = path.read_text()
    for old, new in replacements:
        occurrences = contents.count(old)
        if occurrences != 1:
            sys.exit(f"{path}: expected one occurrence of {old!r}, found {occurrences}")
        contents = contents.replace(old, new, 1)
    path.write_text(contents)


root = Path(sys.argv[1] if len(sys.argv) > 1 else "pkg")
patch(
    root / "cli/dist/main.js",
    [
        # Setup edits other applications' settings and installs agent skills
        # outside Rune's data dir. Both implicit and explicit paths must go.
        ('  if (command !== "setup") ensureSetup();\n', ""),
        (
            '  if (command === "setup") {\n'
            '    const sandbox = apparmorSetup(electronBinary());\n'
            '    linkSkills();\n'
            '    const editors = setupCommand();\n'
            '    markSetupDone();\n'
            '    return editors !== 0 ? editors : sandbox;\n'
            '  }',
            '  if (command === "setup") fail("setup is disabled in the Rune package");',
        ),
        # Do not invoke sudo or install a system-wide AppArmor profile on
        # browser launch; retain upstream's sandbox check and error message.
        (
            '    if (sandboxError) {\n'
            '      apparmorSetup(electron);\n'
            '      sandboxError = linuxSandboxError(electron);\n'
            '    }\n'
            '    if (sandboxError) fail(sandboxError);',
            '    if (sandboxError) fail(sandboxError);',
        ),
        (
            'var LOG_DIR = import_node_path9.default.join(import_node_os5.default.homedir(), ".terminal-browser", "logs");',
            'var LOG_DIR = LOGS_DIR;',
        ),
    ],
)
patch(
    root / "browser/dist/main.js",
    [
        ('var OUTPUT_ROOT = "/tmp/recordings";',
         'var OUTPUT_ROOT = import_node_path9.default.join(DATA_DIR, "recordings");'),
        # Square the viewport border, WebView clip, agent glow, and docked
        # DevTools together. Leave buttons, menus, and website styling alone.
        (
            'function seamRadius(radius, dock, side) {\n'
            '  if (!dock) return radius;\n'
            '  if (side === "page") {\n'
            '    return dock === "bottom" ? { topLeft: radius, topRight: radius, bottomLeft: 0, bottomRight: 0 } : { topLeft: radius, bottomLeft: radius, topRight: 0, bottomRight: 0 };\n'
            '  }\n'
            '  return dock === "bottom" ? { bottomLeft: radius, bottomRight: radius, topLeft: 0, topRight: 0 } : { topRight: radius, bottomRight: radius, topLeft: 0, bottomLeft: 0 };\n'
            '}',
            'function seamRadius(radius, dock, side) {\n'
            '  return 0;\n'
            '}',
        ),
    ],
)