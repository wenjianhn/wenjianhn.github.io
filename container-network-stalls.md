# Container Network Stalls
In our Docker environment, the network latency can jump to 1 second.

Theo Julienne, the Github engineer, wrote a
[blog](https://github.blog/2019-11-21-debugging-network-stalls-on-kubernetes)
about the issue.

I was more lucky than him that I managed to find out the root cause
within like an hour. I think I used the right tool, which was
flamegraph, for the job.

The blog doesn't deep dive into the code of Linux kernel packet
processing. Let me give it a try.

I was under the impression that a ksoftirqd was only utilized when the
machine was under heavy soft interrupt load.  But during the test, the
network traffic was small. And the number of packets that the softirq
context handled was way below the `net.core.netdev_budget` which
was 300. After digging deeper into the code, I found out the reason.

See the comments added to the related code of kernel/softirq.c:
```C
asmlinkage __visible void __softirq_entry __do_softirq(void)
{
...
	pending = local_softirq_pending();
	if (pending) {
		if (time_before(jiffies, end) && !need_resched() &&
		    --max_restart) /* 1. TIF_NEED_RESCHED was set by the scheduler because cadvisor had been stuck in memcg_stat_show() for too long. So "!need_resched()" was false here.*/
			goto restart;

		wakeup_softirqd(); /* 2. Wake up the softirqd on the same CPU. Stat the softirqd became TASK_RUNNING and it started waiting on the runqueue. */
	}
...

static inline void invoke_softirq(void)
{
	if (ksoftirqd_running()) /* 3. ksoftirqd was runnable. So the kernel decided to let the ksoftirqd thread handle softirq but it was blocked by the cadvisor process that was actually running. As a result, the CPU would not handle any packet/softirq until the next scheduling point. */
		return;
```

In conclusion, the CPU that the cadvisor is running on will not handle
any packet/softirq if cadvisor is still stuck in `memcg_stat_show()`
after it has used up its time slice.

The impact of the issue is:  
For every housekeeping interval of cAdvisor, some CPUs will not be
able to handle network packets for a period of time that is mostly
determined by `memcg_stat_show()`.

The maximum number of CPUs that are affected at the same time is
determined by the `--max_procs` option. For example, it is 3 on XXX:
```
/usr/bin/cadvisor --max_procs=3 --log_dir=/var/log/cadvisor --port=9189 --enable_load_reader=true
```

Its CPU has 64 threads, and the ixgbe driver allocates a queue for each thread.
Thus this issue would affect about (1 to 3)/64 of network traffic if:
1. the network flows are hash balanced
2. the chances of the cadvisor processes being scheduled on every CPU are the same.

We can add a preemption/scheduling point to memcg_stat_show() to reduce the latency to the following range(when only cadvisor and ksoftirqd are runable):
`[DIV_ROUND_UP(sched_min_granularity_ns/1000/1000, 1000/CONFIG_HZ) ms, sched_latency_ns/1000/1000/2 ms]`

This is not acceptable for the Redis container that is time-sensitive.
And the cadvisor processes would still consumes significant CPU.
Fix the issue of our kernel properly would require quite some heavy lifting AFAICS.

We have enabled the [disable_root_cgroup_stats](https://github.com/google/cadvisor/pull/2283) option as a workaround.
The fundamental issue will be gone after we rollout Linux 5.4.

## Look back on our work. How could it be better?
1. Monitoring sched latencies of both watchdog and ksoftirqd.  
    Create a Grafana dashboard for this metric. Add a alert rule if needed.  
    Depend on [runqlat](https://github.com/iovisor/bcc/blob/master/tools/runqlat.py) to produce the metrics.
2. Before rollout the above monitoring feature, manually execute `runqlat` when [pingmesh](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/11/pingmesh_sigcomm2015.pdf) detects a network latency issue.
