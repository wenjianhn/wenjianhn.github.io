# k8s kernel panic

We have a Grafana dashboard to monitor kernel crash events.
Our test environment of k8s was badly over-committed. 
The grafana dashboard shows that kernel crashes daily.

## Root cause analysis

Sargun who worked for Netflix reported a [crash](https://lkml.org/lkml/2019/1/9/1090):

> I picked up c40f7d74c741a907cfaeb73a7697081881c497d0 sched/fair: Fix
>        infinite loop in update_blocked_averages() by reverting a9e7f6544b9c
>        and put it on top of 4.19.13. In addition to this, I uninlined
>        list_add_leaf_cfs_rq for debugging.
>        This revealed a new bug that we didn't get to because we kept getting
>        crashes from the previous issue. When we are running with cgroups that
>        are rapidly changing, with CFS bandwidth control, and in addition
>        using the cpusets cgroup, we see this crash. Specifically, it seems to
>        occur with cgroups that are throttled and we change the allowed
>        cpuset.

This matches our crash pattern:  
We backported the same commit to x.y.z. Like Netflix, processes of
our k8s environment are running with cgroups with CFS bandwidth
control and the cpuset cgroups. In our vmcores, malformed
tmp_alone_branch pointers triggered the crash as well. Their panic
message is more friendly than ours since they have enabled
CONFIG_LIST_DEBUG which is used by distributions like RHEL and CentOS.

The [fix](https://git.kernel.org/pub/scm/linux/kernel/git/tip/tip.git/commit/?id=f6783319737f28e4436a69611853a5a098cbe974) for the issue is simple. Its commit message says that the root cause is as below:

> The algorithm used to order cfs_rq in rq->leaf_cfs_rq_list assumes that
>     it will walk down to root the 1st time a cfs_rq is used and we will finish
>     to add either a cfs_rq without parent or a cfs_rq with a parent that is
>     already on the list. But this is not always true in presence of throttling.
>     Because a cfs_rq can be throttled even if it has never been used but other CPUs
>     of the cgroup have already used all the bandwdith, we are not sure to go down to
>     the root and add all cfs_rq in the list.

And the issue is fixed by:
>    Ensure that all cfs_rq will be added in the list even if they are throttled.

## The fix

Backport the following commits:
```
039ae8bcf7a5 sched/fair: Fix O(nr_cgroups) in the load balancing path
31bc6aeaab1d sched/fair: Optimize update_blocked_averages()
f6783319737f sched/fair: Fix insertion in rq->leaf_cfs_rq_list
5d299eabea5a sched/fair: Add tmp_alone_branch assertion
```

## VMCore analysis
```
crash> bt
PID: 0      TASK: ffff8d52f8990000  CPU: 33  COMMAND: "swapper/33"
 #0 [ffff8d5300143b10] machine_kexec at ffffffff90063443
 #1 [ffff8d5300143b70] __crash_kexec at ffffffff9012a6a9
 #2 [ffff8d5300143c38] crash_kexec at ffffffff9012b411
 #3 [ffff8d5300143c58] oops_end at ffffffff90030d58
 #4 [ffff8d5300143c80] no_context at ffffffff9007404c
 #5 [ffff8d5300143ce8] __bad_area_nosemaphore at ffffffff90074403
 #6 [ffff8d5300143d28] bad_area_nosemaphore at ffffffff900744d4
 #7 [ffff8d5300143d38] __do_page_fault at ffffffff900748d4
 #8 [ffff8d5300143db0] do_page_fault at ffffffff90074cfe
 #9 [ffff8d5300143de0] page_fault at ffffffff90a015c5
    [exception RIP: enqueue_entity+532]
    RIP: ffffffff900c5f74  RSP: ffff8d5300143e90  RFLAGS: 00010046
    RAX: ffff8d5300162880  RBX: ffff8d350f1c5e00  RCX: ffff8d4716211340
    RDX: ffff8d350f1c5f40  RSI: 0000000000000000  RDI: 0000000000000000
    RBP: ffff8d5300143ec8   R8: ffff8d5512d9bc00   R9: 0000000000000000
    R10: 0000000000000256  R11: 0000000000000000  R12: ffff8d5512d9bc00
    R13: 0000000000000000  R14: 0000000000000001  R15: 0000000000000001
    ORIG_RAX: ffffffffffffffff  CS: 0010  SS: 0018
#10 [ffff8d5300143ed0] enqueue_task_fair at ffffffff900c647c
#11 [ffff8d5300143f30] activate_task at ffffffff900b8664
#12 [ffff8d5300143f58] ttwu_do_activate at ffffffff900b89f9
#13 [ffff8d5300143f88] sched_ttwu_pending at ffffffff900b9e3e
#14 [ffff8d5300143fc0] scheduler_ipi at ffffffff900ba04c
#15 [ffff8d5300143fd8] smp_reschedule_interrupt at ffffffff90a02b19
#16 [ffff8d5300143ff0] reschedule_interrupt at ffffffff90a023e4

crash> dis -l enqueue_entity | grep push | nl -v 2 | grep r12
     6  0xffffffff900c5d74 <enqueue_entity+20>: push   %r12

crash> bt -f |grep -B 3 enqueue_task_fair
    ffff8d5300143ea8: ffff8d5512d9bc00 0000000000000049
                          ^^^--- R12
    ffff8d5300143eb8: ffff8d5300143f90 0000000000000000
    ffff8d5300143ec8: ffff8d5300143f28 ffffffff900c647c
#10 [ffff8d5300143ed0] enqueue_task_fair at ffffffff900c647c

crash> struct sched_entity.cfs_rq ffff8d5512d9bc00
  cfs_rq = 0xffff8d350f1c5e00

crash> struct cfs_rq.leaf_cfs_rq_list,rq 0xffff8d350f1c5e00
  leaf_cfs_rq_list = {
    next = 0x0,
    prev = 0xffff8d4716211340
  }
  rq = 0xffff8d5300162880

crash> struct rq.tmp_alone_branch 0xffff8d5300162880
  tmp_alone_branch = 0xffff8d4716211340

tmp_alone_branch was a list_head:
#ifdef CONFIG_FAIR_GROUP_SCHED
	/* list of leaf cfs_rq on this cpu: */
	struct list_head leaf_cfs_rq_list;
	struct list_head *tmp_alone_branch;
#endif /* CONFIG_FAIR_GROUP_SCHED */

crash> list 0xffff8d4716211340
ffff8d4716211340
ffff8d350f1c5f40
crash>

crash> rd 0xffff8d4716211340
ffff8d4716211340:  ffff8d350f1c5f40                    @_..5...
crash> rd ffff8d350f1c5f40
ffff8d350f1c5f40:  0000000000000000                    ........
                          ^^^---- *next of __list_add_rcu was NULL.

crash> struct list_head.prev -o
struct list_head {
   [8] struct list_head *prev;
}

include/linux/rculist.h:
static inline void __list_add_rcu(struct list_head *new,
		struct list_head *prev, struct list_head *next)
{
        ...
	next->prev = new; 	/* next was ffff8d350f1c5f40. *next was 0. */
}

As a result, the following instruction triggered the panic:
crash> dis -rl enqueue_entity+532 | tail -n 2
include/linux/rculist.h: 58
0xffffffff900c5f74 <enqueue_entity+532>:        mov    %rdx,0x8(%rsi)
```
