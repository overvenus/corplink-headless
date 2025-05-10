#!/usr/bin/env bash

set -e

SCRIPTS_DIR=$(dirname "$0")

pushd "$SCRIPTS_DIR"/..
HEADLESS_ROOT=$(pwd)
popd

PROGRAM=$(basename "$0")
GOPATH=$(go env GOPATH)
if [ -z $GOPATH ]; then
    printf "Error: the environment variable GOPATH is not set, please set it before running %s\n" $PROGRAM > /dev/stderr
    exit 1
fi
export PATH=$HEADLESS_ROOT/_tools/bin:$GOPATH/bin:$PATH
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
go install golang.org/x/tools/cmd/goimports@latest

protoc \
    --go_out=. --go_opt=paths=source_relative \
    --go-grpc_out=. --go-grpc_opt=paths=source_relative \
    pkg/proto/server.proto
goimports -w pkg/proto/*.pb.go
