# Security Policy

## Supported Versions

Security fixes are handled on the `master` branch until the project publishes
versioned releases.

## Reporting a Vulnerability

Please report security issues through GitHub Security Advisories when available.
If advisories are unavailable, open a minimal issue that says you have a private
security report and wait for a maintainer response.

Do not include:

- Commercial game ROMs
- Proprietary BIOS files
- Secrets, tokens, or private keys
- Exploit details that would put public deployments at immediate risk

## Scope

Useful reports include resource exhaustion paths, unsafe file handling, LiveView
event boundary issues, dependency problems, production configuration mistakes,
and public repository hygiene issues around bundled artifacts.

This project is a local study emulator by default. Public hosting should add
authentication, upstream rate limits, and capacity controls appropriate to the
deployment.
