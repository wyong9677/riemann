#!/usr/bin/env bash
set -euo pipefail

IMG="openquantumsafe/oqs-ossl3:latest"
NET="pqcnet"
PORT="4433"
TIMESEC="20"

# 先跑经典与混合两组；如果混合组名不被支持，后面会在日志里给出可用列表
GROUPS=("X25519" "X25519MLKEM768")

echo "=== Environment (inside image) ==="
docker run --rm "$IMG" sh -lc 'openssl version -a; echo; openssl list -providers'

echo
echo "=== Supported TLS groups (if available) ==="
docker run --rm "$IMG" sh -lc 'openssl list -tls-groups -provider oqsprovider -provider default 2>/dev/null || openssl list -groups || true'

echo
echo "=== Start benchmarks ==="
docker network rm "$NET" >/dev/null 2>&1 || true
docker network create "$NET" >/dev/null

for G in "${GROUPS[@]}"; do
  echo
  echo "--------------------------------------"
  echo "TLS 1.3 handshake benchmark: group=$G"
  echo "--------------------------------------"

  docker rm -f pqc-server >/dev/null 2>&1 || true

  # 启动服务端并固定 group
  docker run -d --rm --name pqc-server --network "$NET" "$IMG" sh -lc "
    set -e
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
      -keyout /tmp/key.pem -out /tmp/cert.pem \
      -subj '/CN=localhost' -days 1 >/dev/null 2>&1

    openssl s_server -accept $PORT -tls1_3 \
      -cert /tmp/cert.pem -key /tmp/key.pem \
      -groups $G -quiet
  " >/dev/null

  # 等待 server 起好
  sleep 1

  # 客户端跑 s_time（-new 强制 full handshake）
  set +e
  docker run --rm --network "$NET" "$IMG" sh -lc "
    openssl s_time -connect pqc-server:$PORT \
      -tls1_3 -new -time $TIMESEC \
      -provider oqsprovider -provider default
  "
  rc=$?
  set -e

  if [ $rc -ne 0 ]; then
    echo "!! Benchmark failed for group=$G (exit=$rc)"
    echo "!! Server log:"
    docker logs pqc-server || true
    echo "!! Client sanity list groups again:"
    docker run --rm "$IMG" sh -lc 'openssl list -tls-groups -provider oqsprovider -provider default 2>/dev/null || true'
  fi

  docker rm -f pqc-server >/dev/null 2>&1 || true
done

docker network rm "$NET" >/dev/null 2>&1 || true
echo
echo "=== Done ==="
