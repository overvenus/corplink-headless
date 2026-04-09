# macOS Runtime Design (Apple Silicon)

This project now supports macOS by running the Linux runtime stack inside an arm64 VM managed by [Lima](https://lima-vm.io/) with `vmType: vz` (Apple Virtualization framework).

## Why this design

- `corplink-service` is distributed as Linux binaries, so a Linux guest is required on macOS.
- `vz` keeps the runtime lean and isolated without requiring Docker Desktop.
- The guest stack intentionally mirrors the existing container contract from `Dockerfile` and `scripts/install_service.sh`.

## Runtime parity with Docker

Inside the guest, we install and run:

- `/opt/Corplink/corplink-service` (from official arm64 `.deb`)
- `/opt/Corplink/corplink-headless` (built from this repo as `linux/arm64`)
- `/usr/local/bin/socks5` (built from `cmd/socks5`)
- `privoxy` on guest `8118` (forwarded to host `8888`)
- `socks5` on guest `1080` (forwarded to host `1088`)
- Same supervisor programs and DNS/MTU maintenance scripts as container runtime.

## Key files

- `scripts/macos/corplink-vm.sh`
  - Host-side command (`up|logs|status|shell|down|destroy|doctor`)
  - Builds artifacts, downloads arm64 package, creates/starts VM, bootstraps guest.
- `scripts/macos/lima-vz.yaml.tmpl`
  - VM definition template (`aarch64`, `vmType: vz`, read-only mounts, port forwards).
- `scripts/macos/guest-bootstrap.sh`
  - Guest-side provisioning and service setup.

## Upgrade notes

- To upgrade corplink package, change `CORPLINK_ARM64_DEB_URL` in `scripts/macos/corplink-vm.sh` (or set env at runtime).
- To rebuild everything from scratch:
  1. `./scripts/macos/corplink-vm.sh destroy --purge-state`
  2. `./scripts/macos/corplink-vm.sh up --company-code <code>`
- If host port mappings change, destroy and recreate the VM so Lima can apply new forwarding rules.
