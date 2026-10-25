# nrf-connect.nvim

[nRF Connect SDK](https://www.nordicsemi.com/Products/Development-software/nRF-Connect-SDK) support for Neovim, built on [zephyr.nvim](https://github.com/joepboumans/zephyr.nvim). It adds what is Nordic-specific: the NCS toolchain (find, install, activate, also for a customised NCS fork), the NCS version your `west.yml` pins, and Nordic probe discovery through `nrfutil`.

It plugs into zephyr.nvim's registries instead of wrapping it, so build, flash, RTT and clangd all stay `:Zephyr` commands.

> Status: early. The NCS toolchain provider, the NCS version and the Nordic probe finder work.

## Requirements

- Neovim 0.10+ and zephyr.nvim
- `nrfutil` on `PATH` with `sdk-manager` (NCS 3.0+) or `toolchain-manager`, and `device`
- Linux or WSL for now

## Install (lazy.nvim)

```lua
{
  "joepboumans/nrf-connect.nvim",
  dependencies = { "joepboumans/zephyr.nvim" },
  opts = {
    -- install_dir = "~/ncs", -- passed to nrfutil as --install-dir; nrfutil's default when unset
    -- watch_manifest = true, -- report NCS version changes when the Manifest is saved
  },
}
```

Run `:checkhealth nrf` to check the setup.

## Commands and events

`:Nrf ncs | toolchain`. Events are `User` autocmds named `Nrf<Event>` (for example `NrfNcsVersionChanged`) with details in `ev.data`.

| Command | What it does |
|---|---|
| `:Nrf ncs` | Show the Workspace's NCS version (official release or custom revision) and the Active toolchain; offers to activate the installed NCS toolchain matching an official version |
| `:Nrf toolchain list` | List installed NCS toolchains (asks `nrfutil` again); `*` marks the Workspace's Active toolchain |
| `:Nrf toolchain select` | Pick an NCS toolchain and make it the Active toolchain of the current Workspace. Any installed toolchain works for any Workspace, so a customised NCS fork can use whichever toolchain it needs |
| `:Nrf toolchain install <version>` | Install the NCS toolchain for an NCS version, e.g. `v3.0.2`, in the background |

| Event | `ev.data` |
|---|---|
| `NrfToolchainInstalled` | `{ provider = "ncs", version, path }` |
| `NrfNcsVersionChanged` | `{ workspace, old, new, official }`, when a saved Manifest pins a different NCS version than when it was opened |

The NCS version (`require("nrf.ncs")`) is the `nrf` project's revision in the Manifest (`west list nrf`). When nrf is the manifest repo itself, it is the checkout's `git describe --tags`, or `nrf/VERSION` when no tag is reachable (always reported as custom). Tags like `v3.0.2`, `v3.1.0-rc1` and `v3.0.0-preview2` count as official; fork branches, SHAs and commits past a tag are custom revisions. `version(workspace, cb)` and `suggest_toolchain(workspace, cb)` run in the background. On a version change nrf-connect.nvim only notifies and suggests a toolchain; it never switches one by itself.

The `ncs` Toolchain provider (`require("nrf.toolchain")`) uses `nrfutil sdk-manager toolchain` when present, else `nrfutil toolchain-manager`. zephyr.nvim calls `find()` and `env()` synchronously, so each nrfutil call is bounded by `require("nrf.toolchain").timeout_ms` (15 s) and the results are cached: the toolchain list until `:Nrf toolchain list`, an install or `refresh()`, and the environment per toolchain for the session. The environment comes from `env --as-script sh` and does not set `ZEPHYR_BASE`; west finds Zephyr from the Workspace.

The `nrfutil` probe finder (`require("nrf.probes")`) lists connected J-Link Probes from `nrfutil device list --json` as `{ finder = "nrfutil", serial, name }`, named after the DK when nrfutil reports its board (e.g. `nRF52840 DK (PCA10056)`). zephyr.nvim calls its `find()` synchronously, so it waits at most `require("nrf.probes").timeout_ms` (5 s) and returns an empty list when `nrfutil` is missing or fails.

## Development

`make test` expects zephyr.nvim next to this repo (`../zephyr.nvim`, override with `ZEPHYR_DIR=`). Vocabulary lives in [CONTEXT.md](CONTEXT.md).
