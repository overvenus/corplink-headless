# corplink-headless

corplink-headless is a headless client for Corplink VPN.

Supported runtimes:

- Docker on Linux hosts
- macOS (Apple Silicon) via Apple Virtualization framework + arm64 Linux guest

## Usage on Docker (Linux host)

1. Run the container as a daemon.

```bash
docker run -d \
  --name=corplink \
  --hostname=ubuntu \
  --device=/dev/net/tun \
  --cap-add=NET_ADMIN \
  --shm-size=512m \
  -p 8888:8118 \
  -p 1088:1080 \
  -e COMPANY_CODE="your_company" \
  overvenus/corplink:latest
```

2. Configure corplink.

```bash
# Scan QR code using Feilian App
docker exec -it corplink less -rf +F /var/log/corplink-headless/stdout.log
# Quit less if it prints "login success, company code: xxx"
```

3. Access corplink network via http proxy: localhost:8888 or socks5 proxy: localhost:1088.
  You can also route traffic to the container. The container will do SNAT for all traffic sent to it.

## Usage on macOS (Apple Silicon)

### Prerequisites

1. Install Lima (`limactl`) and Go:

```bash
brew install lima go
```

2. Start Corplink in one command:

```bash
./scripts/macos/corplink-vm.sh up --company-code your_company
```

This command will:

- Build `corplink-headless` and the local `socks5` helper for `linux/arm64`
- Download the official arm64 Corplink package
- Start an Ubuntu Minimal arm64 VM with Apple Virtualization (`vmType: vz`)
- Use systemd for lean top-level lifecycle management of the runtime stack
- Persist `COMPANY_CODE` in VM runtime env so `corplink-headless` always receives it

### Login and daily operations

```bash
# Watch QR code + login progress
./scripts/macos/corplink-vm.sh logs -f

# Runtime status
./scripts/macos/corplink-vm.sh status

# Open shell inside VM
./scripts/macos/corplink-vm.sh shell

# Stop VM
./scripts/macos/corplink-vm.sh down
```

After `up`, proxies are exposed on host:

- HTTP: `127.0.0.1:8888`
- SOCKS5: `127.0.0.1:1088`

If you previously used the Alpine-based VM runtime, recreate once:

```bash
./scripts/macos/corplink-vm.sh destroy --purge-state
./scripts/macos/corplink-vm.sh up --company-code your_company
```

See [`docs/macos-runtime.md`](docs/macos-runtime.md) for design and maintenance details.

## Acknowledgments

* corplink-headless is inspired by [sleepymole/docker-corplink](https://github.com/sleepymole/docker-corplink).
  The Dockerfile and relevant scripts are modified from the project.
