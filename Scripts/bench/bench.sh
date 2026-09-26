#!/bin/zsh
# Runs one scenario of the bench build and prints, at each MARK, the memory
# (phys_footprint, what Activity Monitor calls Memory) and CPU time of Wake plus
# every WebKit process it is responsible for.
#
#   Scripts/bench/build.sh
#   Scripts/bench/bench.sh <cold|browse|threads|idle|deck|devtools|onboarding> [results.tsv]
#
# The "idle" and "onboarding" scenarios also report CPU and GPU time spent between
# their start and end marks. The dev test site must be up for browse/devtools:
#   python3 -m http.server 8765 -d Scripts/devtools-test-site
set -uo pipefail
root="${0:A:h}/../.."
scenario=$1
out=${2:-/dev/null}
# BENCH_VARIANT=BenchBase runs a baseline built with `build.sh BenchBase`.
variant=${BENCH_VARIANT:-Bench}
app="$root/build/$variant/Build/Products/Release/Wake.app"
resp="$root/build/$variant/responsible"
log=$(mktemp -t wakebench)

pkill -f "/build/Bench[A-Za-z]*/Build/Products/Release/Wake.app/Contents/MacOS/Wake" 2>/dev/null; sleep 1

# Every run starts from an empty store (threads, history) in the bench container.
store="$HOME/Library/Containers/app.wake.Wake.bench/Data/Library/Application Support"
rm -f "$store"/default.store "$store"/default.store-shm "$store"/default.store-wal
rm -rf "$store"/Thumbnails "$store"/Moments

onboarded=YES
[[ $scenario == onboarding ]] && onboarded=NO
# Through `open`, so launchd makes Wake responsible for its WebKit processes (run
# straight from a shell, the shell would be).
open -g -n --env WAKE_BENCH=$scenario --stdout "$log" -a "$app" --args \
  -browsing.restoreThread NO -onboarding.completed $onboarded -NSQuitAlwaysKeepsWindows NO
wake=""
until [[ -n $wake ]]; do sleep 0.3; wake=$(pgrep -f "build/$variant/Build/Products/Release/Wake.app/Contents/MacOS/Wake"); done

pids() {
  echo $wake
  local webkit=($(pgrep -f 'com.apple.WebKit\.(WebContent|Networking|GPU)'))
  (( ${#webkit} )) && "$resp" "${webkit[@]}" | awk -v w=$wake '$2==w {print $1}'
}

# CPU seconds (user+sys) of a pid, from ps's cumulative time.
cputime() { ps -o time= -p $1 | awk -F'[:.]' '{ if (NF==4) print $1*3600+$2*60+$3+$4/100; else print $1*60+$2+$3/100 }' }

# Accumulated GPU nanoseconds charged to a pid, from the Metal driver's user clients.
gputime() {
  # ioreg sorts keys, so a client's "AppUsage" comes before its "IOUserClientCreator".
  ioreg -r -c IOAccelerator -l 2>/dev/null | awk -v p="pid $1," '
    /"AppUsage"/ { pending = 0; line = $0
      while (match(line, /"accumulatedGPUTime"=[0-9]+/)) { pending += substr(line, RSTART+21, RLENGTH-21); line = substr(line, RSTART+RLENGTH) } }
    /IOUserClientCreator/ { if (index($0, p) > 0) s += pending; pending = 0 }
    END { printf "%.0f\n", s }'
}

typeset -A cpu0 gpu0
measure() {
  local mark=$1 note=${2:-} total=0 line="" cpu_total=0 gpu_total=0
  local list=($(pids))
  for p in $list; do
    local fp=$(footprint --noCategories -f bytes -p $p 2>/dev/null | awk '/phys_footprint:/ {print $2; exit}')
    local name=$(ps -o comm= -p $p | sed 's#.*/##; s/com.apple.WebKit.//')
    local mb=$(( ${fp:-0} / 1048576 ))
    total=$(( total + mb ))
    line+="$name=${mb}MB "
    if [[ $mark == *_start ]]; then cpu0[$p]=$(cputime $p); gpu0[$p]=$(gputime $p); fi
    if [[ $mark == *_end ]]; then
      local mine=$(echo "$(cputime $p) - ${cpu0[$p]:-0}" | bc)
      line+="(cpu ${mine}s) "
      cpu_total=$(echo "$cpu_total + $mine" | bc)
      gpu_total=$(echo "$gpu_total + $(gputime $p) - ${gpu0[$p]:-0}" | bc)
    fi
  done
  local extra=""
  [[ $mark == *_end ]] && extra="  cpu=${cpu_total}s gpu=$(echo "scale=2; $gpu_total/1000000000" | bc)s"
  printf "%-20s total=%5dMB procs=%d %s  %s%s\n" $mark $total ${#list} "$note" "$line" "$extra"
  printf "%s\t%s\t%d\t%d\t%s\t%s\t%s\n" "$(date +%H:%M:%S)" $mark $total ${#list} "$note" "$line" "$extra" >>"$out"
}

seen=0
while kill -0 $wake 2>/dev/null; do
  lines=("${(@f)$(tail -n +$((seen + 1)) "$log")}")
  for l in $lines; do
    [[ -z $l ]] && continue
    seen=$((seen + 1))
    case $l in
      "MARK "*) set -- ${=l#MARK }; measure $1 "$2" ;;
      DONE) break 2 ;;
      TIME*) echo "  $l"; printf "\t%s\n" "$l" >>"$out" ;;
      unknown*) echo $l; break 2 ;;
    esac
  done
  sleep 0.5
done
kill $wake 2>/dev/null
rm -f "$log"
