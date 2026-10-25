# nrf-connect.nvim

[nRF Connect SDK](https://www.nordicsemi.com/Products/Development-software/nRF-Connect-SDK) support for Neovim, built on [zephyr.nvim](https://github.com/joepboumans/zephyr.nvim). It adds what is Nordic-specific: the NCS toolchain (find, install, activate, also for a customised NCS fork), the NCS version your `west.yml` pins, and Nordic probe discovery through `nrfutil`.

It plugs into zephyr.nvim's registries instead of wrapping it, so build, flash, RTT and clangd all stay `:Zephyr` commands.

> Status: skeleton. The provider and probe finder are registered but return nothing yet.

## Requirements

- Neovim 0.10+ and zephyr.nvim
- `nrfutil` on `PATH` (with the `toolchain-manager` and `device` commands)
- Linux or WSL for now

## Install (lazy.nvim)

```lua
{
  "joepboumans/nrf-connect.nvim",
  dependencies = { "joepboumans/zephyr.nvim" },
  opts = {},
}
```

Run `:checkhealth nrf` to check the setup.

## Commands and events

`:Nrf ncs | toolchain`. Events are `User` autocmds named `Nrf<Event>` (for example `NrfNcsVersionChanged`) with details in `ev.data`.

## Development

`make test` expects zephyr.nvim next to this repo (`../zephyr.nvim`, override with `ZEPHYR_DIR=`). Vocabulary lives in [CONTEXT.md](CONTEXT.md).
