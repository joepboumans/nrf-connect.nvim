# nrf-connect.nvim

[nRF Connect SDK](https://www.nordicsemi.com/Products/Development-software/nRF-Connect-SDK) support for Neovim, built on [zephyr.nvim](https://github.com/joepboumans/zephyr.nvim). It adds what is Nordic-specific: the NCS toolchain (find, install, activate, also for a customised NCS fork), the NCS version your `west.yml` pins, and Nordic probe discovery through `nrfutil`.

It plugs into zephyr.nvim's registries instead of wrapping it, so build, flash, RTT and clangd all stay `:Zephyr` commands.

> Status: early. The NCS toolchain provider works; the probe finder returns nothing yet.

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
  },
}
```

Run `:checkhealth nrf` to check the setup.

## Commands and events

`:Nrf ncs | toolchain`. Events are `User` autocmds named `Nrf<Event>` (for example `NrfNcsVersionChanged`) with details in `ev.data`.

| Command | What it does |
|---|---|
| `:Nrf toolchain list` | List installed NCS toolchains (asks `nrfutil` again); `*` marks the Workspace's Active toolchain |
| `:Nrf toolchain select` | Pick an NCS toolchain and make it the Active toolchain of the current Workspace. Any installed toolchain works for any Workspace, so a customised NCS fork can use whichever toolchain it needs |
| `:Nrf toolchain install <version>` | Install the NCS toolchain for an NCS version, e.g. `v3.0.2`, in the background |

| Event | `ev.data` |
|---|---|
| `NrfToolchainInstalled` | `{ provider = "ncs", version, path }` |

The `ncs` Toolchain provider (`require("nrf.toolchain")`) uses `nrfutil sdk-manager toolchain` when present, else `nrfutil toolchain-manager`. zephyr.nvim calls `find()` and `env()` synchronously, so each nrfutil call is bounded by `require("nrf.toolchain").timeout_ms` (15 s) and the results are cached: the toolchain list until `:Nrf toolchain list`, an install or `refresh()`, and the environment per toolchain for the session. The environment comes from `env --as-script sh` and does not set `ZEPHYR_BASE`; west finds Zephyr from the Workspace.

## Development

`make test` expects zephyr.nvim next to this repo (`../zephyr.nvim`, override with `ZEPHYR_DIR=`). Vocabulary lives in [CONTEXT.md](CONTEXT.md).
