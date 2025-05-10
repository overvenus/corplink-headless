# corplink-headless

corplink-headless is a headless client for corplink VPN. It designed to run the official corplink VPN in a docker container.

## Usage

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
docker exec -it corplink-headless less -rf +F /var/log/corplink-headless/stdout.log
# Quit less if it prints "login success, company code: xxx"
```

3. Access corplink network via http proxy: localhost:8888 or socks5 proxy: localhost:1088.
  You can also route traffic to the container. The container will do SNAT for all traffic sent to it.

## Acknowledgments

* corplink-headless is inspired by [sleepymole/docker-corplink](https://github.com/sleepymole/docker-corplink).
  The Dockerfile and relevant scirpts are modified from the project.
