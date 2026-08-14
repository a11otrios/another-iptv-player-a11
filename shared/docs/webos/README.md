# LG webOS Work Index

These documents are the handover and operating guide for the desktop-managed
LG webOS client. `PROJECT_NOTES.md` is the repository-level entry point.

## Documents

- [Current state](current-state.md) - exact versions, runtime state, recent
  commits, and next actions.
- [Known issues](known-issues.md) - confirmed defects, limitations,
  workarounds, and regression queue.
- [Architecture](architecture.md) - ownership boundaries, synchronization,
  storage, and playback design.
- [Development and deployment](development-and-deployment.md) - desktop and TV
  build/install procedures, version files, and rollback guidance.
- [Testing and diagnostics](testing-and-diagnostics.md) - automated tests,
  physical-TV rules, remote inspection, and failure diagnosis.
- [Client/server protocol](../webos-client-server-protocol.md) - API and
  security contract.
- [Feature parity](../webos-feature-parity.md) - desktop/webOS capability
  matrix.
- [webOS app README](../../../apps/webos/README.md) - app-local development and
  remote-control reference.

## Maintenance Rule

Update `current-state.md` after a build, installation, deployment, or runtime
switch. Update `known-issues.md` whenever a physical-TV report is confirmed or
resolved. Keep architecture and protocol details out of the current-state log
unless they affect the next resume action.
