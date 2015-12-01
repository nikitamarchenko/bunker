#! /usr/bin/env bash
set -x
mkdir -p /go/src/github.com/
cd /go/src/github.com/
git clone https://github.com/nikitamarchenko/registrator gliderlabs/registrator
export GOPATH=/go
cd /go/src/github.com/gliderlabs/registrator
go get
go build -ldflags "-X main.Version $(cat VERSION)" -o /bin/registrator
rm -rf /go
