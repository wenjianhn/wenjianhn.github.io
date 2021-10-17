#!/bin/bash

# Any copyright is dedicated to the Public Domain.
# https://creativecommons.org/publicdomain/zero/1.0/

function test() {
    nr_process=$1

    whileloop_py=$(mktemp --suffix=.py)
    cat <<EOF > ${whileloop_py}
a = 0

while True:
      a += 1
EOF

    for i in $(seq ${nr_process}); do
	taskset 0x1 python ${whileloop_py} &
    done

    sleep $(echo 0.02*${nr_process} | bc) && rm ${whileloop_py}

    sched_latency_ns=$(cat /proc/sys/kernel/sched_latency_ns)
    sched_min_granularity_ns=$(cat /proc/sys/kernel/sched_min_granularity_ns)

    echo "Sched latency:      ${sched_latency_ns} ns"
    echo "No. of processes:   ${nr_process}"
    echo -n "Expected run time:  "
    if (( ${sched_latency_ns}/${nr_process} < ${sched_min_granularity_ns} )); then
	echo ${sched_min_granularity_ns} ns
    else
	echo $(( ${sched_latency_ns}/${nr_process} )) ns
    fi

    sudo perf probe -q 'sched_slice%return $retval'
    sudo perf record -q -e probe:sched_slice -C 0 -- sleep 0.1

    # Priority of the processes are the same, $retval are expected to
    # be the same as well.
    # e.g. 'arg1=0x493dfa' for every process.
    arg1=$(sudo perf script |grep -m1 $(jobs -p  | head -n 1) | grep arg1 | awk '{print $NF}')
    python -c"${arg1}; print 'Allocated run time:', arg1, 'ns'"

    sudo perf sched record -q -- sleep 1

    sudo perf probe -q -d sched_slice

    jobs_p=$(jobs -p)

    echo "Actual run time:"
    sudo perf sched timehist -p $(echo ${jobs_p} | xargs | sed "s/\ /,/g") 2>/dev/null | head -n $(( 3 + ${nr_process}*2))

    # Be quiet after killing background processes
    exec 2> /dev/null
    kill ${jobs_p}
}

idle=$(mpstat -P 0 |grep idle -A1 |grep -v idle | awk '{print int($NF)}')
if (( ${idle} < 92 )); then
    echo "ERROR: CPU 0 should be idle" >> /dev/stderr
    exit 1
fi

echo -n "Number of CPUs:  " && nproc
echo "Sched latency: " $(( $(cat /proc/sys/kernel/sched_latency_ns) / 1000 / 1000)) ms
hz=$(grep CONFIG_HZ= /boot/config-$(uname -r))
echo -n "Tick period: " && python -c "${hz}; print '   ',1000/CONFIG_HZ,'ms'"
echo

for nr in $(seq 2 4 12); do
    test ${nr}
    echo
done

# The smallest schedule slice of SCHED_HRTICK is 10000ns. See hrtick_start().
# Overhead of SCHED_HRTICK maybe too high to be really useful.
# See https://lore.kernel.org/all/20160919082158.GS5016@twins.programming.kicks-ass.net/
echo    "============="
echo -n "Enable "
echo HRTICK | sudo tee /sys/kernel/debug/sched_features

for nr in $(seq 2 4 12); do
    test ${nr}
    echo
done

echo NO_HRTICK | sudo tee /sys/kernel/debug/sched_features > /dev/null
