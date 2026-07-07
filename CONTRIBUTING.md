# Contributing

Thanks for helping make GbEmu clearer and safer.

## Development

```sh
mix setup
mix test
mix precommit
```

Use focused commits and keep behavior changes covered by tests when practical.
The project follows the Phoenix and Elixir style already present in the repo.

## ROM and BIOS Rules

Do not commit game ROMs, proprietary BIOS files, or binary fixtures unless the
project has explicit redistribution rights and a matching entry in
`THIRD_PARTY_NOTICES.md`.

Acceptable test inputs include:

- Tiny synthetic fixtures generated in tests
- Homebrew ROMs with clear redistribution permission and source/provenance
- Public test ROMs with their license and source recorded

Do not ask maintainers to provide copyrighted ROMs or BIOS files.

## Pull Requests

Before opening a PR:

- Run `mix precommit`
- Update docs when behavior changes
- Add or update tests for emulator behavior, safety checks, or public APIs
- Keep UI copy user-facing and avoid internal/debug labels

If a change affects existing tests, explain whether the behavior intentionally
changed, the test was obsolete, or the previous assertion was implementation
coupled.
