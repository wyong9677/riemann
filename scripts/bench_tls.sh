#!/usr/bin/env bash
set -euo pipefail

IMG=openquantumsafe/oqs-ossl3:latest
NET=pqcnet
PORT=4433
TIMESEC=20

# 对照组：经典 vs 混合（先保证跑通，再扩展更多组）
GROUPS=("X25519" "X25519MLKEM768")

docker network rm $NET >/dev/null 2>&1 || true
docker network create $NET >/dev/null

for G in "${GROUPS[@]}"; do
  echo "=============================="
  echo "TLS 1.3 handshake test: $G"
  echo "=============================="

  docker rm -f pqc-server >/dev/null 2>&1 || true

  docker run -d --name pqc-server --network $NET $IMG sh -lc "
    set -e
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
      -keyout /tmp/key.pem -out /tmp/cert.pem \
      -subj '/CN=localhost' -days 1 >/dev/null 2>&1

    # 固定使用指定 group（server 端固定最稳妥）
    openssl s_server -accept $PORT -tls1_3 \
      -cert /tmp/cert.pem -key /tmp/key.pem \
      -groups $G -quiet
  " >/dev/null

  sleep 1

  # -new 强制每次新会话（全握手）
  docker run --rm --network $NET $IMG sh -lc "
    openssl s_time -connect pqc-server:$PORT \
      -tls1_3 -new -time $TIMESEC \
      -provider oqsprovider -provider default
  "

  echo
done

docker rm -f pqc-server >/dev/null 2>&1 || true
docker network rm $NET >/dev/null 2>&1 || true
