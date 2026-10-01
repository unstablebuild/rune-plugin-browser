# A browser package for Rune

A package that bundles [terminal-browser](https://github.com/zenbu-labs/terminal-browser),
a real Chromium browser to run as native content within
[Rune](https://github.com/unstablebuild/rune), and enables Rune Agent's built-in
`web_browser` tool.

https://github.com/user-attachments/assets/94b98df7-4452-411c-9f97-6d4c081ab1cd


## What it installs

Installing this package:

- Adds the `terminal-browser` command to your Rune data directory and puts it on your
  `PATH`. Open a browser in a new Rune tab from the command prompt with `browser [url]`.
- Enables Rune Agent's built-in `web_browser` tool, so agents can navigate, read and
  interact with web pages in a private headless browser. It does this by bundling
  `agent-browser` and putting it on your `PATH`, which also powers
  `terminal-browser action`.

This package does not install upstream's agent skills, run upstream's setup, or alter agent
directories, editor settings, or system AppArmor profiles. `terminal-browser setup` is
disabled. Upgrades go through Rune rather than `terminal-browser upgrade`.

## Install

Open the [Rune console](https://docs.rune.build/learn/console) and run:

```
pkg install browser
```

On Linux, Chromium needs a few system libraries (e.g. `libnss3`, `libgtk-3-0`,
`libasound2t64`, `libgbm1`). Some hosts also need a sandbox configuration; the package
reports the sandbox error but does not change system configuration or disable Chromium's
sandbox.

## License

This repository's packaging (the Makefile, scripts, and configuration) is licensed under
the MIT License; see [LICENSE](./LICENSE).

terminal-browser is distributed by Zenbu Labs under the MIT License. Its license text
ships inside the release package under `licenses/terminal-browser/`.
