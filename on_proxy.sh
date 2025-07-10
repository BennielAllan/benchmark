#!/bin/bash
apt update
apt install -y git
apt install -y sed

git clone https://gh-proxy.com/https://github.com/wnlen/clash-for-linux.git

cd clash-for-linux

sed -i "s|^export CLASH_URL=.*$|export CLASH_URL='https://c8728336.jego.vip/subscribe/clash/1a4e6a2902d1522a7c552f695a24f49e'|" .env

chmod +x start.sh
./start.sh