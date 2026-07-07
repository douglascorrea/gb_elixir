# Third-Party Notices

This repository does not distribute commercial game ROMs, proprietary console
BIOS files, or third-party Game Boy ROM binaries.

## Runtime and Build Dependencies

Elixir and Phoenix dependencies are declared in `mix.exs` and locked in
`mix.lock`. Review each dependency's upstream license before redistributing a
compiled release.

## Vendored Front-End Build Assets

- `assets/vendor/topbar.js` - topbar 3.0.0, MIT license, copyright Buu Nguyen.
- `assets/vendor/daisyui.js` and `assets/vendor/daisyui-theme.js` - daisyUI
  bundles, MIT license.
- `assets/vendor/heroicons.js` - local Tailwind helper that reads Heroicons from
  the Hex/Git dependency declared in `mix.exs`; Heroicons is MIT licensed.

## ROM Fixtures

Any future redistributable ROM fixture must include:

- License name and text or link
- Upstream source URL pinned to a tag, commit, or release
- Exact binary hash
- Build or provenance notes for the distributed binary

Do not add ROM binaries without this notice entry.
