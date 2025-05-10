# Stage 1: Build
FROM golang:1.24 AS builder

# Extract corplink-service
RUN wget -q -O corplink.deb \
        https://oss-s3.ifeilian.com/linux/FeiLian_Linux_v2.0.9_r615_97b98b.deb && \
    dpkg-deb -x ./corplink.deb /

WORKDIR /app

COPY go.mod go.sum ./
ENV GOPROXY=https://goproxy.cn
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build .

# Stage 2: Final image
FROM ubuntu:20.04

ENV CONTAINER=1

# Install socks5
COPY --from=serjs/go-socks5-proxy /socks5 /usr/local/bin/socks5
# Install corplink-headless
RUN mkdir -p /opt/Corplink
COPY --from=builder /app/corplink-headless /opt/Corplink
# Install corplink-service
COPY --from=builder /opt/Corplink/corplink-service /opt/Corplink/
# Install services
COPY ./scripts/install_service.sh /opt/Corplink
RUN bash /opt/Corplink/install_service.sh  && rm /opt/Corplink/install_service.sh
COPY ./scripts/startup.sh /

WORKDIR /opt/Corplink
USER root

ENV COMPANY_CODE=""

ENTRYPOINT ["/startup.sh"]
