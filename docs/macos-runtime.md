# macOS Runtime Design (Apple Silicon)

This project supports macOS by running the runtime stack inside an arm64 Ubuntu Minimal VM managed by [Lima](https://lima-vm.io/) with `vmType: vz` (Apple Virtualization framework).

## Why this design

- `corplink-service` is distributed as Linux binaries, so a Linux guest is required on macOS.
- Ubuntu Minimal keeps the VM lean while preserving compatibility with `privoxy`.
- `vz` keeps the runtime isolated without requiring Docker Desktop.
- The guest stack intentionally mirrors the container behavior (service set, ports, logs, NAT).

## Runtime parity with Docker

Inside the guest, we install and run:

- `/opt/Corplink/corplink-service` (from official arm64 `.deb`)
- `/opt/Corplink/corplink-headless` (built from this repo as `linux/arm64`)
- `/usr/local/bin/socks5` (built from `cmd/socks5`)
- `privoxy` on guest `8118` (forwarded to host `8888`)
- `socks5` on guest `1080` (forwarded to host `1088`)
- `systemd` manages `/startup.sh` as the top-level service lifecycle
- `supervisord` still manages `corplink-service`, `corplink-headless`, `privoxy`, and helper daemons
- Guest bootstrap masks `privoxy.service` and `supervisor.service` to avoid lifecycle conflicts with supervisor jobs.
- DNS/MTU maintenance scripts equivalent to container behavior.
- Persistent `/opt/Corplink/runtime.env` consumed by `startup.sh` so `COMPANY_CODE` is inherited by `corplink-headless`.

## Key files

- `scripts/macos/corplink-vm.sh`
  - Host-side command (`up|logs|status|shell|down|destroy|doctor`)
  - Builds artifacts, downloads arm64 package, creates/starts VM, bootstraps guest.
- `scripts/macos/lima-vz.yaml.tmpl`
  - VM definition template (`aarch64`, `vmType: vz`, Ubuntu Minimal cloud image, read-only mounts, port forwards).
- `scripts/macos/guest-bootstrap.sh`
  - Guest-side provisioning and systemd + supervisor runtime setup.

## Upgrade notes

- To upgrade corplink package, change `CORPLINK_ARM64_DEB_URL` in `scripts/macos/corplink-vm.sh` (or set env at runtime).
- To rebuild everything from scratch:
  1. `./scripts/macos/corplink-vm.sh destroy --purge-state`
  2. `./scripts/macos/corplink-vm.sh up --company-code <code>`
- If you created a VM with the old Alpine-based implementation, recreate once with:
  `./scripts/macos/corplink-vm.sh destroy --purge-state`
- If host port mappings change, destroy and recreate the VM so Lima can apply new forwarding rules.
