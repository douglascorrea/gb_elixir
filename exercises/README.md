# GBEmulings

GBEmulings is a branch-based Rustlings-style path through this Game Boy
emulator. The command creates each exercise branch, activates one real
implementation as a failing `TODO`, locks later exercise targets, adds a
failing test, and switches your working tree to that branch.

You do not create the exercise branches or stubs manually.

## Start

Begin from a clean branch containing the curriculum runner and reference
implementation, normally `master`:

```sh
git status
mix gb_emu.exercises start
```

The command creates and switches to a branch such as:

```text
codex/gbemulings/001-parse-a-hexadecimal-byte
```

It also prints the exact source file containing the new `TODO`.

## Solve One Exercise

The complete loop is:

```sh
mix gb_emu.exercises status
mix gb_emu.exercises hint

# Edit the TODO in the source file printed by the command.

mix gb_emu.exercises check
mix gb_emu.exercises next
```

`check` rejects the scaffold marker and runs both the generated exercise test
and the focused behavioral tests for that subsystem. Fix production or
workbench code; do not edit the generated test under `test/gb_emulings/`.

Later targets are compile-valid locked stubs on your branch. For validation,
`check` creates a disposable Git worktree, copies your uncommitted solution
into it, temporarily hydrates only the later targets from the reference commit,
and runs the checks there. The disposable worktree is removed afterward; the
future code on your exercise branch stays locked. This keeps the feedback about
the exercise you are solving without placing future implementations in your
working source.

`next` does four things:

1. Runs the current checks again.
2. Stages and commits all changes on the dedicated exercise branch.
3. Creates the next branch from that passing commit.
4. Replaces the next implementation with a new failing `TODO` scaffold.

Keep unrelated work out of exercise branches because `next` intentionally
commits every change there.

## How Progress Builds

The branches form a cumulative chain:

```text
reference branch
└── 001 TODO + 002..110 locked
    └── 001 learner solution
        └── 002 TODO + 003..110 locked
            └── 002 learner solution
                └── ...
                    └── 110 complete emulator
```

Your passing implementation is carried into every later branch. Code for
topics you have not reached raises a clearly labeled `locked until its turn`
error. Exactly one target contains the active `TODO`; `check` isolates it from
those later stubs.

## Resume Or Inspect

```sh
mix gb_emu.exercises resume 048
mix gb_emu.exercises show 048
mix gb_emu.exercises hint 048
mix gb_emu.exercises list
mix gb_emu.exercises list cpu-arithmetic
```

`resume` switches to an existing exercise branch. `show` is read-only and
prints the goal, exact scaffold target, checks, and hints.

To begin at a later exercise from the reference implementation:

```sh
mix gb_emu.exercises start 048
```

Starting in the middle intentionally uses the reference implementation for
earlier targets and locks everything after the requested exercise. Use plain
`start` for the complete cumulative path.

## Curriculum

The 110 exercises progress through:

1. Elixir bitwise, binary, endian, atomics, and tile-row fundamentals.
2. Machine state, boot policy, cartridge detection, and memory allocation.
3. Bus regions, IO side effects, DMA, MBC1, and MBC5.
4. CPU fetch, loads, arithmetic, control flow, CB opcodes, and interrupts.
5. Timer, serial, joypad, PPU state, rendering, sprites, and frames.
6. Machine integration, OTP runtime, LiveView, uploads, and debugger behavior.
7. ROM policy and release readiness.

The complete implementation remains available in the recorded reference commit
for comparison after attempting the hints and checks. Exercise 109 requires a
real ROM/trademark policy, and exercise 110 runs precommit, asset compilation,
and a production release build. Do not add commercial ROMs, proprietary boot
ROMs, or other copyrighted game data to exercise branches.
