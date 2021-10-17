# The elephant in the room

I've managed to understand the root cause of a kernel bug that has
been bugging me since 2008.

## Description of the issue
Artem S. Tashkinov:

> Once you hit a situation when opening a new tab requires more RAM
> than is currently available, the system will stall hard. You will
> barely be able to move the mouse pointer. Your disk LED will be
> flashing incessantly (I'm not entirely sure why). You will not be
> able to run new applications or close currently running ones.

See [here](https://lkml.org/lkml/2019/8/4/15) for more details.

## The root cause
Vlastimil Babka:

> Yeah that's a known problem, made worse SSD's in fact, as they are
> able to keep refaulting the last remaining file pages fast enough, so
> there is still apparent progress in reclaim and OOM doesn't kick in.
>
> At this point, the likely solution will be probably based on
> pressure stall monitoring (PSI). I don't know how far we are from a
> built-in monitor with reasonable defaults for a desktop workload, so
> CCing relevant folks.

I created a flamegraph for the issue.
It shows that the kernel kept handling page faults and reclaiming.  
OOM didn't kick in.

## Refaulting for which file(s)?
The conclusion is that the kernel robs Chrome to pay Chrome.

##### 1. Add a probe to get inodes of the files
Unlike xfs, ext4 doesn't have a built-in trace point for readpages.

```shellsession
$ perf probe -k /usr/lib/debug/boot/vmlinux-$(uname -r) -L ext4_readpages
<ext4_readpages@/build/linux-teTg6M/linux-4.15.0/fs/ext4/inode.c:0>
      0  ext4_readpages(struct file *file, struct address_space *mapping,
                        struct list_head *pages, unsigned nr_pages)
      2  {
      3         struct inode *inode = mapping->host;
         
                /* If the file has inline data, no need to do readpages. */
      6         if (ext4_has_inline_data(inode))
      7                 return 0;
         
      9         return ext4_mpage_readpages(mapping, pages, NULL, nr_pages);
     10  }
         
         static void ext4_invalidatepage(struct page *page, unsigned int offset,
                                        unsigned int length)
```

Add a probe at line 6.
```shellsession
$ perf probe -k /usr/lib/debug/boot/vmlinux-$(uname -r) --definition 'ext4_readpages:6 inode inode->i_ino nr_pages'
p:probe/ext4_readpages ext4_readpages+11 inode=%si:u64 i_ino=+64(%si):u64 nr_pages=%cx:u32
```
inode is an address, so use 'x64' instead of 'u64'.

```shellsession
$ sudo perf probe 'ext4_readpages+11 inode=%si:x64 i_ino=+64(%si):u64 nr_pages=%cx:u32'
Added new event:
  probe:ext4_readpages (on ext4_readpages+11 with inode=%si:x64 i_ino=+64(%si):u64 nr_pages=%cx:u32)

You can now use it in all perf tools, such as:

        perf record -e probe:ext4_readpages -aR sleep 1
```

##### 2. Starts recording
```shellsession
$ sudo perf record -e probe:ext4_readpages -aR -F 997
```

##### 3. Open several Chrome tabs and then stop perf recording by ctrl-c.

#### The answer
Among the 25358 events, 15865 events were reading pages of inode 1051192.
```shellsession
$ sudo perf script |grep i_ino=1051192 | head -n1
          chrome 26089 [006]   861.218520: probe:ext4_readpages: (ffffffffa4334166) inode=0xffff8d74e29b00e8 i_ino=1051192 nr_pages=23

$ sudo perf script |grep i_ino=1051192 | wc -l
15865
```

Find the file that has inode 1051192.
```shellsession
$ sudo find / -inum 1051192 -exec echo {} \;
/opt/google/chrome/chrome
```

It is chrome itself. So this is a livelock issue that the kernel robs
Chrome to pay Chrome.

## How to avoid such stalls?
Android depends on the Low Memory Killer Daemon that uses kernel
pressure stall information (PSI) monitors for memory pressure
detection. It kills the least essential processes to keep the system
performing at acceptable levels.

Facebook uses oomd that also leverages PSI. It works with cgroup2 and
provides more granular OOM-kill options. 
[Here](https://facebookincubator.github.io/oomd/docs/oomd-casestudy.html) is a case study.

## How to avoid paging for real-time applications?
Use mlockall() to prevent delays on page faults. Locked pages will not be:
1. put to the swap area
2. reclaimed
3. migrated if /proc/sys/vm/compact_unevictable_allowed is 0
