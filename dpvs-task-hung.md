# DPVS task hung
[Shopee](https://github.com/iqiyi/dpvs#community) depends on [DPVS](https://github.com/iqiyi/dpvs) to manage a lots of network traffic.
Unfortunately, both of the control plane and the data plane of more than 10 servers were down due to a kernel issue.

## Root cause analysis

cpu.cfs_quota_us of node-exporter was set as 7000 in the live env.
``` shellsession
$ grep -i Quota /lib/systemd/system/node-exporter.service
CPUQuota=7%
```

A node-exporter thread tried to get the network interface info of mlx5 from /sys/class/net/.
It got the rtnl_mutex and executed an mlx5 command.
It started waiting(kernel function: wait_for_completion_timeout) for a response from the firmware.
The firmware interrupted the CPU and then the mlx5 driver woke up the node-exporter thread.

The CPUQuota of the node-exporter service was low, it triggered a [kernel scheduler bug](https://lore.kernel.org/patchwork/patch/1008788/).
It lead to the starvation of the node-exporter thread.
As a result, the other threads like dpvs and bird that were waiting for the rtnl_mutex were blocked forever.

Hung task warnings occurred after the threads had been blocked for more than 120 seconds:
```
[3894199.404305] INFO: task lldpd:3611 blocked for more than 120 seconds.
[3894199.426890] INFO: task dpvs:88984 blocked for more than 120 seconds.
[3894199.449372] INFO: task bird:89463 blocked for more than 120 seconds.
[3894199.471888] INFO: task sp-mesos-dp:92041 blocked for more than 120 seconds.
[3894199.495400] INFO: task lshw:195093 blocked for more than 120 seconds.
[3894199.517978] INFO: task ip:195220 blocked for more than 120 seconds.
[3894199.540394] INFO: task tocex-agent:195221 blocked for more than 120 seconds.
[3894320.229341] INFO: task lldpd:3611 blocked for more than 120 seconds.
[3894320.251934] INFO: task dpvs:88984 blocked for more than 120 seconds.
[3894320.274442] INFO: task bird:89463 blocked for more than 120 seconds.
```

## Workaround

Remove the CPUQuota limit or increase the quota.

## Crash dump analysis
```
crash> p /x rtnl_mutex.owner
$1 = {
  counter = 0xffff9aed86ee8003
}

crash> kmem 0xffff9aed86ee8003
CACHE             OBJSIZE  ALLOCATED     TOTAL  SLABS  SSIZE  NAME
ffff9aedbf404300     7560       1237      1572    393    32k  task_struct
  SLAB              MEMORY            NODE  TOTAL  ALLOCATED  FREE
  ffffea60be1bba00  ffff9aed86ee8000     0      4          4     0
  FREE / [ALLOCATED]
  [ffff9aed86ee8000]

    PID: 5113
COMMAND: "node-exporter"
   TASK: ffff9aed86ee8000  [THREAD_INFO: ffff9aed86ee8000]
    CPU: 39
  STATE: TASK_RUNNING

      PAGE         PHYSICAL      MAPPING       INDEX CNT FLAGS
ffffea60be1bba00 1f86ee8000                0        0  1 17ffffc0008100 slab,head

crash> bt 5113
PID: 5113   TASK: ffff9aed86ee8000  CPU: 39  COMMAND: "node-exporter"
 #0 [ffffb20de0137740] __schedule at ffffffffad598af1
 #1 [ffffb20de01377d8] schedule at ffffffffad59912c
 #2 [ffffb20de01377e8] schedule_timeout at ffffffffad59d02d
 #3 [ffffb20de0137868] wait_for_completion_timeout at ffffffffad599f13
 #4 [ffffb20de01378c0] cmd_exec at ffffffffc0c01077 [mlx5_core]
 #5 [ffffb20de0137948] mlx5_cmd_exec at ffffffffc0c01223 [mlx5_core]
 #6 [ffffb20de0137980] mlx5_core_access_reg at ffffffffc0c0accd [mlx5_core]
 #7 [ffffb20de01379d8] mlx5_query_port_ptys at ffffffffc0c0ad75 [mlx5_core]
 #8 [ffffb20de0137a40] mlx5_port_query_eth_proto at ffffffffc0c48161 [mlx5_core]
 #9 [ffffb20de0137aa8] mlx5e_port_linkspeed at ffffffffc0c48423 [mlx5_core]
#10 [ffffb20de0137ae8] mlx5e_get_fec_caps at ffffffffc0c489dd [mlx5_core]
#11 [ffffb20de0137b48] get_fec_supported_advertised at ffffffffc0c3645f [mlx5_core]
#12 [ffffb20de0137ba0] mlx5e_ethtool_get_link_ksettings at ffffffffc0c3875c [mlx5_core]
#13 [ffffb20de0137c58] mlx5e_get_link_ksettings at ffffffffc0c388b5 [mlx5_core]
#14 [ffffb20de0137c68] __ethtool_get_link_ksettings at ffffffffad4564f6
#15 [ffffb20de0137cc0] vlan_ethtool_get_link_ksettings at ffffffffc0653545 [8021q]
#16 [ffffb20de0137cd0] __ethtool_get_link_ksettings at ffffffffad4564f6
#17 [ffffb20de0137d28] speed_show at ffffffffad474a64
#18 [ffffb20de0137da0] dev_attr_show at ffffffffad247dc3
#19 [ffffb20de0137dc0] sysfs_kf_seq_show at ffffffffacf05233
#20 [ffffb20de0137de0] kernfs_seq_show at ffffffffacf03847
#21 [ffffb20de0137df0] seq_read at ffffffffacea0005
#22 [ffffb20de0137e60] kernfs_fop_read at ffffffffacf04067
#23 [ffffb20de0137ea0] __vfs_read at fffffffface7722b
#24 [ffffb20de0137eb0] vfs_read at fffffffface772de
#25 [ffffb20de0137ee8] sys_read at fffffffface77745
#26 [ffffb20de0137f30] do_syscall_64 at ffffffffacc03af3
#27 [ffffb20de0137f50] entry_SYSCALL_64_after_hwframe at ffffffffad600081
    RIP: 00000000004ba9fb  RSP: 000000c001379550  RFLAGS: 00000206
    RAX: ffffffffffffffda  RBX: 000000c00003d000  RCX: 00000000004ba9fb
    RDX: 0000000000000080  RSI: 000000c0013795f0  RDI: 0000000000000018
    RBP: 000000c0013795a0   R8: 0000000000bfd700   R9: 000000c001c5cae0
    R10: 000000c00003e698  R11: 0000000000000206  R12: 0000000000000032
    R13: 0000000000000000  R14: 0000000000c8ce1c  R15: 0000000000000000
    ORIG_RAX: 0000000000000000  CS: 0033  SS: 002b

crash> task_struct.se.cfs_rq ffff9aed86ee8000
  se.cfs_rq = 0xffff9aed86f7b200,
crash> struct cfs_rq.throttled,runtime_remaining 0xffff9aed86f7b200
  throttled = 1
  runtime_remaining = -15683

crash> struct cfs_rq.tg 0xffff9aed86f7b200
  tg = 0xffff9b0db4c74800

crash> struct task_group.cfs_bandwidth.quota,cfs_bandwidth.period 0xffff9b0db4c74800
  cfs_bandwidth.quota = 7000000,
  cfs_bandwidth.period = 100000000

crash> struct cfs_rq.throttled_list -o 0xffff9aed86f7b200
struct cfs_rq {
  [ffff9aed86f7b390] struct list_head throttled_list;
}

crash> list cfs_rq.throttled_list -H ffff9aed86f7b390 -s cfs_rq.runtime_remaining | paste - - | awk '{print $1"  "$4}' | pr -t -n3
  1     ffff9aed86f7be00  -156588
  2     ffff9b0daaff6e00  -37755
  3     ffff9b0db4c74880  78214705012889
  4     ffff9aed86f7aa00  -3999217
  5     ffff9aed86f7ba00  -1003264
  6     ffff9aed86f7b000  -2005307
  7     ffff9aed86f79400  -3958262
  8     ffff9aed86f78600  -3943892
  9     ffff9aed86f7b400  -5606
 10     ffff9b0daaff5e00  -3389083
 11     ffff9aed86f78000  -3599973
 12     ffff9aed86f7a600  -1427228
 13     ffff9aed86f79e00  -1377771
 14     ffff9b0daaff7e00  -450810
 15     ffff9aed86f78a00  -128941
 16     ffff9aed86f7a400  -92463
 17     ffff9aed86f7bc00  -20887
```

## Look back on our work. How could it be better?

Currently, we have the following options to trigger a crash.
1. the 'kernel.hung_task_panic=1' option
2. the magic SysRq key
3. triggering an NMI

Option 1 doesn't work for every server.
For example, some of the tasks get blocked maybe not important at
all. Sometimes the issue is temporary, it will be gone after a while.
It's better to not trigger a panic for them during a big sale like 11.11.

Both option 2 and option 3 are not automatic. They are passive
responses and do require human involvement. Recovery time is affected.

I think we could use a daemon to monitor the essential services. If
one of the essential services get blocked the daemon triggers a crash.
For example, the following core services got blocked during the issue
period.
```
task bird:89802 blocked for more than 120 seconds.
task dpvs:95548 blocked for more than 120 seconds.
```
As a result, the whole data plane was down. It was safe to trigger a crash then.

This idea comes from Oracle database.
`cssdagent/cssdmonitor`, which is a process with realtime priority, of
Oracle Clusterware would trigger a crash dump via `/proc/sysrq-trigger`
when the CSS daemon hung.
