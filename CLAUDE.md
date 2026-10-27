
## Design rules

Apply these by default to every change. When they pull against each other, prefer the simpler code.

- KISS: write the plainest code that does the job. No clever indirection, no options nobody asked for.
- YAGNI: build only what a ticket or the spec asks for now. No hooks, flags or fields "for later"; delete leftovers such as stubs and unused branches.
- DRY: before writing a helper, search `lua/` for one that already does it (file reading, line splitting, running west, picking the Workspace of an App). Extend that one instead of adding a copy. Duplicate knowledge (a field list, a CMake variable mapping) belongs in one module.
- SOLID, read as deep modules: each module owns one concept from CONTEXT.md and hides its details behind a small interface. Callers should not need to know how another module stores or parses things. New behaviour from vendor plugins goes through the registries (ADR 0001), not through `if vendor` branches.
- Tests go through a module's public interface, not its private helpers.
