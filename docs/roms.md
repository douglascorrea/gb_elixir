# ROM, BIOS, and Trademark Policy

GbEmu is for emulator study, hardware documentation practice, and lawful
homebrew experimentation. It is not a ROM distribution project.

> [!IMPORTANT]
> Do not commit or redistribute commercial game ROMs, proprietary console BIOS
> files, or third-party binaries unless you have explicit redistribution rights
> and the required license/source notices are present. Do not upload any ROM or
> BIOS to a deployment unless you are legally allowed to use it and trust that
> deployment's operator. This is project policy, not legal advice.

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

For local testing, upload a legal `.gb` or `.gbc` file in the browser, or place
legal `.gb` files in `priv/roms/`. The app lists files from that directory and
validates LiveView ROM selections against the server-side directory listing.

Good local inputs include:

- Homebrew ROMs whose license allows your local use
- Public hardware test ROMs whose license allows your local use
- Personal cartridge dumps that you are legally allowed to use

Do not use ROMs for games you do not own or are not licensed to use. Laws vary
by jurisdiction; this document is project policy, not legal advice.

## Browser Upload Retention

Browser uploads are stored server-side under a random signed browser-session id.
The app keeps only fixed filenames for that session (`game.gb` and `boot.bin`)
and refreshes a `.last_seen` marker while the same browser stays connected.
An upload is therefore not client-only: on a remote deployment the operator's
server receives the file. Use a local/private deployment when that is the only
use your rights permit.

`GB_EMU_UPLOAD_TTL_MS` controls how long uploaded files and the signed browser
session remain valid after the browser stops reconnecting:

```sh
GB_EMU_UPLOAD_TTL_MS=7200000 mix phx.server
```

The repository default is two hours. That default is intended for this project's
public deployment, but it is configurable. Developers operating their own copy
can choose a different retention window, upload root, access-control layer, or
disable public upload access according to their own legal and operational
requirements.

Use `GB_EMU_UPLOAD_ROOT` to place uploads outside the release directory or on a
dedicated volume:

```sh
GB_EMU_UPLOAD_ROOT=/var/lib/gb_emu/uploads mix phx.server
```

## Boot ROM Behavior

By default the emulator uses `GbEmu.BootRom.minimal/0`, a tiny open stub. The
normal play/Reset path does **not** execute it: the emulator applies post-boot
compatibility register and I/O state directly, disables the overlay, and starts
the cartridge at `$0100`.

After attaching the debugger, **Boot** selects a cold restart at `$0000`. That
workflow executes the stub as three instruction boundaries:

1. `$0000`: jumps to `$00FC`.
2. `$00FC`: loads `1` into register A.
3. `$00FE`: writes A to `$FF50`, unmaps the overlay, applies the documented
   minimal-stub compatibility handoff, and continues at `$0100`.

This is enough for many homebrew and test ROM workflows, but it does not
recreate the original startup animation, audio chime, or header checks.

If you have a legally obtained DMG BIOS dump, keep it outside the repository and
set:

```sh
GB_EMU_BOOT_ROM=/absolute/path/to/dmg_boot.bin mix phx.server
```

A file boot source is exactly 256 bytes, remains mapped over `$0000-$00FF`, and
executes from `$0000` on a normal load or debugger Boot. The emulator does not
replace that file's instruction sequence with the open compatibility shortcut.

The debugger displays bytes from the ROM/BIOS supplied by the current session.
Do not publish screenshots, traces, or copied memory dumps containing material
you are not allowed to redistribute. See [debugger.md](debugger.md) for the
technical boot and memory workflow.

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
