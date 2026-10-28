#!/usr/bin/env bash
# Сборка zembo-guard.jar (нужен JDK 17+). Результат: assets/agent/zembo-guard.jar
set -euo pipefail
cd "$(dirname "$0")"
rm -rf out && mkdir -p out/classes
javac --release 17 -Xlint:all -d out/classes src/dev/zembo/guard/*.java
printf 'Premain-Class: dev.zembo.guard.Agent\nCan-Retransform-Classes: true\nCan-Redefine-Classes: true\n' > out/MANIFEST.MF
jar --create --file out/zembo-guard.jar --manifest out/MANIFEST.MF -C out/classes .
mkdir -p ../../assets/agent
cp out/zembo-guard.jar ../../assets/agent/zembo-guard.jar
echo "Готово: assets/agent/zembo-guard.jar"
