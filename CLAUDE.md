# Agent notes

- No CI: don't add GitHub Actions or other hosted CI workflows; they cost money and aren't needed. Run `make test` locally instead.
- Vocabulary lives in CONTEXT.md.

## Design rules

Apply these by default to every change. When they pull against each other, prefer the simpler code.

- KISS: write the plainest code that does the job. No clever indirection, no options nobody asked for.
- YAGNI: build only what a ticket or the spec asks for now. No hooks, flags or fields "for later"; delete leftovers such as stubs and unused branches.
- DRY: before writing a helper, search `lua/` (and zephyr.nvim's public API) for one that already does it. Extend or reuse that one instead of adding a copy. Duplicate knowledge belongs in one module.
- SOLID, read as deep modules: each module owns one concept from CONTEXT.md and hides its details behind a small interface. Nordic behaviour reaches zephyr.nvim through its registries (zephyr.nvim ADR 0001), never by reaching into its internals.
- Tests go through a module's public interface, not its private helpers.
