#!/bin/bash

set -e

hash=$(git rev-parse --short HEAD)
host=$(hostname -s)
stamp=$(date -Iseconds)
bmfile="ref/bm-$host.txt"

zig build -Doptimize=ReleaseFast
echo "$stamp - $hash - $host" | tee -a $bmfile
zig-out/bin/bm-numbers 2>&1 | tee -a $bmfile

# vim:ts=2:sw=2:sts=2:et:ft=sh

