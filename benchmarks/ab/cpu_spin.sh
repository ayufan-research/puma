#!/bin/bash

set -eo pipefail

CPU_TIME=1
URL=http://localhost:9292/cpu/$CPU_TIME

MIN_WORKERS=2
MAX_WORKERS=4

MIN_THREADS=4
MAX_THREADS=4

REQUESTS_PER_TEST=4
MIN_CONCURRENT=1
MAX_CONCURRENT=8

retry() {
  local tries="$1"
  local sleep="$2"
  shift 2

  for i in $(seq 1 $tries); do
    if eval "$@"; then
      return 0
    fi

    sleep "$sleep"
  done

  return 1
}

run_ab() {
  result=$(ab -n "$requests" -c "$concurrent" "$@")
  time_taken=$(echo "$result" | grep "Time taken for tests:" | cut -d" " -f7)
  time_per_req=$(echo "$result" | grep "Time per request:" | grep "(mean)" | cut -d" " -f10)

  if [[ "$workers" == "0" ]]; then
    # we are saturating a single-mode
    time_ref_per_req_ms=$((1000*CPU_TIME*concurrent))
  elif [[ $concurrent -le $workers ]]; then
    # we are not saturating service, as we have more available workers
    time_ref_per_req_ms=$((1000*CPU_TIME))
  else
    # we do saturate all workers
    time_ref_per_req_ms=$((1000*CPU_TIME*concurrent/workers))
  fi

  echo -e "$workers\t$threads\t$requests\t$concurrent\t$time_taken\t$time_per_req\t$time_ref_per_req_ms"
}

run_concurrency_tests() {
  echo
  echo -e "PUMA_W\tPUMA_T\tAB_R\tAB_C\tT_TOTAL\tT_PER_REQ\tT_REF_PER_REQ_MS"
  for concurrent in $(seq $MIN_CONCURRENT $MAX_CONCURRENT); do
    requests="$((concurrent*$REQUESTS_PER_TEST))"
    eval "$@"
    sleep 1
  done
  echo
}

with_puma() {
  # start puma and wait for 10s for it to start
  bundle exec bin/puma -w "$workers" -t "$threads" test/rackup/cpu_spin.ru &
  local puma_pid=$!

  if ! retry 10 1s curl --fail "$URL" &>/dev/null; then
    echo "Failed to connect to $URL."
    kill $puma_pid
    return 1
  fi

  # execute testing command
  eval "$@"

  kill $puma_pid || true
}

for workers in $(seq $MIN_WORKERS $MAX_WORKERS); do
  for threads in $(seq $MIN_THREADS $MAX_THREADS); do
    with_puma \
      run_concurrency_tests \
      run_ab "$URL"
  done
done
