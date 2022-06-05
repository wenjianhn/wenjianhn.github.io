# Hundreds of agents fail to start

We depend on an agent to export environment variables to pods that are on the same K8s worker node.
I was asked to help find out why hundreds of them fail to start. 

## The core
```text
$ gdb /path/to/agent/java/bin/java core.pool-3-thread-1.2270274.1649925255
...
Program terminated with signal 11, Segmentation fault.
#0  make_request (fd=fd@entry=161, pid=2270274) at ../sysdeps/unix/sysv/linux/check_pf.c:242
242                   newp->info.flags = (((ifam->ifa_flags

alloca() is called at line 241
(gdb) l 
237                             seen_ipv6 = true;
238                         }
239                     }
240
241                   struct in6ailist *newp = alloca (sizeof (*newp));
242                   newp->info.flags = (((ifam->ifa_flags
243                                         & (IFA_F_DEPRECATED
244                                            | IFA_F_OPTIMISTIC))
245                                        ? in6ai_deprecated : 0)
246                                       | ((ifam->ifa_flags

3535 struct in6ailist
(gdb) p in6ailistlen
$1 = 3535

(gdb) print sizeof(struct in6ailist)
$3 = 32

They need about 110k stack memory:
(gdb) p 32*3535
$4 = 113120

make_request() had consumed about 170k stack memory in total:
(gdb) p newp
$6 = (struct in6ailist *) 0x7fec3bdfbff0

(gdb) info frame
Stack level 0, frame at 0x7fec3be267e0:
 rip = 0x7fed14d89186 in make_request (../sysdeps/unix/sysv/linux/check_pf.c:242); saved rip 0x7fed14d89474
 ...
  Saved registers:
  rbx at 0x7fec3be267a8, rbp at 0x7fec3be267d0, r12 at 0x7fec3be267b0, r13 at 0x7fec3be267b8, r14 at 0x7fec3be267c0, r15 at 0x7fec3be267c8, rip at 0x7fec3be267d8
  
(gdb) p 0x7fec3be267d0 - 0x7fec3bdfbff0
$7 = 174048
```

## How to reproduce
```text
$ ulimit -s 110; getent ahosts example.com
Segmentation fault
```

## The root cause
```text
Calls to getaddrinfo() can segfault with large numbers of local
ipaddrs of the kube-ipvs0 interface.

__check_pf() uses alloca() without checking input size (list of local
ipaddrs), eventually this will exceed the stack and segfault. Needs to
be converted to alloca_account with malloc fallback.
```

## The fix of glibc
[calls to getaddrinfo() can segfault with large numbers of local ipaddrs](https://sourceware.org/bugzilla/show_bug.cgi?id=16002#c6)

## The Workaround
Double the stack size of the agent with "-Xss512k".
