# ROM, BIOS, and Trademark Policy

GbEmu is for emulator study, hardware documentation practice, and lawful
homebrew experimentation. It is not a ROM distribution project.

> [!IMPORTANT]
> Do not commit or upload commercial game ROMs, proprietary console BIOS files,
> or third-party binaries unless you have explicit redistribution rights and the
> required license/source notices are present in this repository.

## What the Repository Includes

- Emulator source code
- Phoenix LiveView front end
- Documentation
- Synthetic tests and an open boot stub

The repository does not include:

- Nintendo DMG boot ROM dumps
- Commercial game ROMs
- Third-party homebrew ROM binaries

## Local ROM Use

For local testing, place legal `.gb` files in `priv/roms/`. The app lists files
from that directory and validates LiveView ROM selections against the server-side
directory listing.

Good local inputs include:

- Homebrew ROMs whose license allows your local use
- Public hardware test ROMs whose license allows your local use
- Personal cartridge dumps that you are legally allowed to use

Do not use ROMs for games you do not own or are not licensed to use. Laws vary
by jurisdiction; this document is project policy, not legal advice.

## Boot ROM Behavior

By default the emulator uses `GbEmu.BootRom.minimal/0`, a tiny open stub that:

1. Loads `1` into register A.
2. Writes A to `$FF50` to unmap the boot overlay.
3. Jumps to the cartridge entrypoint at `$0100`.

This is enough for many homebrew and test ROM workflows, but it does not
recreate the original startup animation, audio chime, or header checks.

If you have a legally obtained DMG BIOS dump, keep it outside the repository and
set:

```sh
GB_EMU_BOOT_ROM=/absolute/path/to/dmg_boot.bin mix phx.server
```

## Redistribution Checklist

Before adding any binary ROM fixture to the repository, include all of:

- License name and license text or canonical link
- Upstream source URL pinned to a release, tag, or commit
- Exact binary hash
- Build/provenance notes for reproducing or obtaining that exact binary
- Maintainer approval that redistribution fits the project

Prefer synthetic fixtures generated inside tests when possible.

## Trademarks

GbEmu is not affiliated with, sponsored by, or endorsed by Nintendo. "Game Boy",
"Nintendo", and related names are trademarks of their respective owners and are
used only to identify the hardware platform this study emulator targets.
