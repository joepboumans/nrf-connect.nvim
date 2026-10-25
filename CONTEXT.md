# nrf-connect.nvim

Nordic-specific additions built on zephyr.nvim, aiming to match nRF Connect for VS Code.

## Language

**NCS version**:
The nRF Connect SDK revision a Workspace's Manifest pins; it may be an official release or a customised fork.
_Avoid_: SDK version, nRF version

**NCS toolchain**:
The Toolchain bundle Nordic publishes for each NCS version, provided to zephyr.nvim as a second Toolchain provider; it can be switched without changing the NCS version.
_Avoid_: nRF toolchain, nrfutil toolchain
