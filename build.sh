#!/bin/sh
# build.sh — compila src/BraveHardening.wxs a dist/BraveHardeningPolicies.msi
# Requiere msitools/wixl:  sudo apt-get install -y wixl
set -e
cd "$(dirname "$0")"
wixl -a x64 -o dist/BraveHardeningPolicies.msi src/BraveHardening.wxs
echo "OK -> dist/BraveHardeningPolicies.msi"
