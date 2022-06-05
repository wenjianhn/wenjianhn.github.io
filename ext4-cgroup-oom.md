# Estimated Capacity Lost within 20 minutes: 70.04 TB

Kernel logs of one of the servers:
```text
 kernel: EXT4-fs error (device sdc1) in ext4_free_blocks:4879: Out of memory
 kernel: Aborting journal on device sdc1-8.
 kernel: EXT4-fs (sdc1): Remounting filesystem read-only
 kernel: EXT4-fs error (device sdc1) in ext4_reserve_inode_write:5047: Journal has aborted
 kernel: EXT4-fs error (device sdc1) in ext4_reserve_inode_write:5047: Journal has aborted
 kernel: EXT4-fs error (device sdc1) in ext4_ext_remove_space:3042: Journal has aborted
 kernel: EXT4-fs error (device sdc1) in ext4_ext_truncate:4685: Journal has aborted
 kernel: EXT4-fs error (device sdc1) in ext4_reserve_inode_write:5047: Journal has aborted
 kernel: EXT4-fs error (device sdc1) in ext4_truncate:3928: Journal has aborted
 kernel: EXT4-fs error (device sdc1) in ext4_reserve_inode_write:5047: Journal has aborted
 kernel: EXT4-fs error (device sdc1) in ext4_orphan_del:2673: Journal has aborted
 kernel: EXT4-fs error (device sdc1) in ext4_reserve_inode_write:5047: Journal has aborted
```

Potential fixes:
```text
commit fa8a01a81af29ae9b490e29791badfb6d090eb71
Author: Konstantin Khlebnikov <khlebnikov@yandex-team.ru>
Date:   Sun Mar 13 17:29:06 2016 -0400

    ext4: use __GFP_NOFAIL in ext4_free_blocks()

    commit adb7ef600cc9d9d15ecc934cc26af5c1379777df upstream.

    This might be unexpected but pages allocated for sbi->s_buddy_cache are
    charged to current memory cgroup. So, GFP_NOFS allocation could fail if
    current task has been killed by OOM or if current memory cgroup has no
    free memory left. Block allocator cannot handle such failures here yet.

    Signed-off-by: Konstantin Khlebnikov <khlebnikov@yandex-team.ru>
    Signed-off-by: Theodore Ts'o <tytso@mit.edu>
    Signed-off-by: Willy Tarreau <w@1wt.eu>

commit 5c01f95c2048a683f56aa7c7adb4464d9c28dc2c
Author: Konstantin Khlebnikov <khlebnikov@yandex-team.ru>
Date:   Sun May 21 22:35:23 2017 -0400

    ext4: handle the rest of ext4_mb_load_buddy() ENOMEM errors


    [ Upstream commit 9651e6b2e20648d04d5e1fe6479a3056047e8781 ]

    I've got another report about breaking ext4 by ENOMEM error returned from
    ext4_mb_load_buddy() caused by memory shortage in memory cgroup.
    This time inside ext4_discard_preallocations().

    This patch replaces ext4_error() with ext4_warning() where errors returned
    from ext4_mb_load_buddy() are not fatal and handled by caller:
    * ext4_mb_discard_group_preallocations() - called before generating ENOSPC,
      we'll try to discard other group or return ENOSPC into user-space.
    * ext4_trim_all_free() - just stop trimming and return ENOMEM from ioctl.

    Some callers cannot handle errors, thus __GFP_NOFAIL is used for them:
    * ext4_discard_preallocations()
    * ext4_mb_discard_lg_preallocations()

    Fixes: adb7ef600cc9 ("ext4: use __GFP_NOFAIL in ext4_free_blocks()")
    Signed-off-by: Konstantin Khlebnikov <khlebnikov@yandex-team.ru>
    Signed-off-by: Theodore Ts'o <tytso@mit.edu>
    Signed-off-by: Sasha Levin <alexander.levin@microsoft.com>
    Signed-off-by: Greg Kroah-Hartman <gregkh@linuxfoundation.org>
```

We don't verify the fixes yet, because the kernel:
1. is not maintained by us.
2. doesn't support live patching, and upgrading the kernel is hard for the hadoop team.

A month later they hit the same issue(my assumption based on the ext4
code and upstream fixes) again.

kernel-3.10.0-1160.62.1.el7.x86_64, the latest kernel at the time, doesn't fix the issue.

## See also
1. [Using Memory Control in YARN](https://hadoop.apache.org/docs/stable/hadoop-yarn/hadoop-yarn-site/NodeManagerCGroupsMemory.html)
