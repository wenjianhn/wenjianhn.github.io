# A memory leak issue of the i40e driver
## Unaccounted pages
Pages that are directly allocated by `alloc_pages()` are unaccounted unless a kernel module/driver adds a counter for it.
For example, there is a counter for the slab pages:
```shellsession
$ grep -i slab /proc/meminfo
Slab:             446832 kB
```
The total memory calculation is:
```
MemTotal = MemFree + MemKernel + (Cached + AnonPages + Buffers + (HugePages_Total * Hugepagesize))
```
We can get the memory used by the kernel by the following command(use DirectMap2M instead of DirectMap1G if needed):
```
cat /proc/meminfo | awk '{ val[$1]=$2 } /DirectMap1G/ { print val["MemTotal:"] - val["Buffers:"] - val["Cached:"] - val["AnonPages:"] - val["HugePages_Total:"] * 2048 - val["MemFree:"]; }'
```

To get the unaccounted pages:
```
UnaccountedPages = MemKernel - (Slab + VmallocUsed + PageTables + KernelStack + HardwareCorrupted + Bounce)
```

VmallocUsed has been zeroed by [this](https://github.com/torvalds/linux/commit/a5ad88ce8c7fae7ddc72ee49a11a75aa837788e0) commit.
We may need to caculate VmallocUsed by analysing /proc/vmallocinfo.

## The memory leak issue
Unaccounted pages of a server were insane. It was likely a memory leak issue.
We triggerred a crash to get a core dump.

Most of the kernel memory were unaccounted pages. A simple random sample showed that the content of the pages started with XXXX383e43966e24.
We verified that the most of the unaccounted pages had this pattern by using the search command:
```
crash> search 0000383e43966e24 -m 0xffff000000000000
```
Another server with a different NIC didn't hit the issue, it looked like pages were allocated by the i40e driver.
The content of the pages were pure data. There were no virtual addresses(e.g. ffff8824679b4c00).
It seemed data were written via DMA. If so the data should start with a MAC address.

24:6e:96:43:3e:38 was the MAC address of bond0:
```
crash> log |grep bond0 |grep Adding
[   25.712054] bond0: Adding slave em1
[   25.813152] bond0: Adding slave em2

crash> log |grep -e em1 -e em2 |grep mac
[   25.712175] i40e 0000:01:00.0 em1: already using mac address 24:6e:96:43:3e:38
[   25.813168] i40e 0000:01:00.1 em2: set new mac address 24:6e:96:43:3e:38
```

Converted it to the network byte order.
```
$ python -c  "mac='24:6e:96:43:3e:38'; print(''.join(reversed(mac.split(':'))))"
383e43966e24
```
There were more than tens of millions of pages contain the MAC address of bond0.
```
crash> search 0000383e43966e24 -m 0xffff000000000000 | awk 'BEGIN {T=0} (T!=systime()) { printf "%s %s\n",NR,$0 ; T=systime()} END { print NR}'
1 ffff880100400000: 2200383e43966e24
...
30181742 ffff883766d6f000: 2200383e43966e24
^C
```

It's indeed an issue of the i40e driver.
## The fix
Commit 2b9478ffc550 ("i40e: Fix memory leak related filter programming status")

