#!/bin/zsh
# Runs every scenario into one results file: Scripts/bench/all.sh build/bench-results/<name>.tsv
root="${0:A:h}/../.."
out=${1:?results file}
for s in ${=SCENARIOS:-cold browse browse threads idle deck devtools devtools onboarding}; do
  echo "== $s"
  "$root/Scripts/bench/bench.sh" $s "$out"
done
