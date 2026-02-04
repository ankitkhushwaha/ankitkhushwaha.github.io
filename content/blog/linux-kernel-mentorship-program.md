---
date: '2025-12-08T10:35:09+05:30'
draft: False
title: 'Linux Kernel Mentorship Program'
tags: ["kernel", "linux", "lfx", "linux-kernel", "mentorship"]
---
### Introduction

I have been using Linux for the last two years and gradually developed an interest in systems programming and C. The mentorship prerequisites includes tasks like building and booting the Linux kernel, writing a basic kernel module, decoding stack traces, and modifying and booting a custom kernel build.

Somehow, my application was accepted ;-). 
![alt text](/lfx-acceptance.png)

At first, the Linux Kernel seemed quite difficult to understand what was going on. We were initially told to choose two subsystems to work on.


I initially attempted to work on syzbot-reported [bug](https://syzkaller.appspot.com/bug?id=194151be8eaebd826005329b2e123aecae714bdb) in the trace subsystem and submitted a [patch](https://lore.kernel.org/all/20251008172516.20697-1-ankitkhushwaha.linux@gmail.com/) for the kernel ring buffer. However, I later realized that starting directly with complex bugs without understanding subsystem internals slows progress.

And I **personally advise** not to do this.

I instead focused on beginner-friendly tasks such as fixing warnings in kselftest, addressing build issues with W=1, and backporting small fixes. These helped me understand the workflow and codebase more effectively.
Backporting can also be considered as beginner task -- see **Hanne-Lotta's Blog -** [link](https://hannis.link/linux-kernel/backporting.html).

When submitting patches, it is important to clearly explain:

- what the patch changes
- why the change is needed
- how it fixes the issue

### The Patch Submission Flow

1. **Create the Patch:**  
```
git format-patch HEAD~1
```

**Check style:** (Run the check and then apply fixes if needed)  
```
./scripts/checkpatch.pl --strict --fix-inplace hello.patch
./scripts/checkpatch.pl --strict --fix-inplace -f --fix hello.patch  
```

2. **Find maintainers:**  
```
./scripts/get_maintainer.pl --separator=, --no-rolestats hello.patch  
```

3. **Sending the patch**
```
git send-email --to=<Maintainer Email> --cc=<Mailing list> hello.patch  
```
   *(**Note:** Replace `<Maintainer Email>` and `<CC Emails>` with the actual emails obtained from `get_maintainer.pl`.)*
  
**Note**: Always make sure to **double check the patch** before sending it to the mailing list. I will recommend first sending the patch to your email or use `git send-email` using the `--dry-run` option.  

4. **Writing a Changelog for Previous Versions:**  
Always write the changelog in patches except for the first version.

see:  [https://lore.kernel.org/all/20251106095532.15185-1-ankitkhushwaha.linux@gmail.com/](https://lore.kernel.org/all/20251106095532.15185-1-ankitkhushwaha.linux@gmail.com/)

5. **Subsystem-specific rules**
Each subsystem have different preference. 

for example: Networking subsystem: [netdev](https://docs.kernel.org/process/maintainer-netdev.html)

For the `kselftest` subsystem, it is helpful to mention the compiler details with which you are getting the error/warning. Installing the `uapi` header before compiling the test.

```
make headers_install
```

see: [discussion](https://lore.kernel.org/all/aRs6EbV2gnkertzA@google.com/)

### Contributions

During the mentorship total of 8 patch was accepted in mainline kernel. 

```
2fa98059fd5a0936d0951bd14f8990ae0aa5272a selftests: mptcp: Mark xerror and die_perror __noreturn
9580f6d47dd6156c6d16e988d28faa74e5a0b8ba selftests: tls: fix warning of uninitialized variable
0384c8ea96bfe49e82e624e53bfd5f80c3230ea9 selftests/mm/uffd: initialize char variable to Null
af7273cc7ae01f5b3e34e62f59588ce79fe50f79 selftests/net: initialize char variable to null
3b12a53b64d0c86cf68cab772bd4137e451b17a5 selftest/mm: fix pointer comparison in mremap_test
6ae0f2072768fb3db7846cee08b611a96310930d docs: parse-headers.rst: Fix a typo
216158f063fe24fb003bd7da0cd92cd6e2c4d48b selftests/user_events: fix type cast for write_index packed member in perf_test
afb8f6567a5b4bb4e673608048939fef854b8709 selftest: net: fix socklen_t type mismatch in sctp_collision test
de4cbd704731778a2dc833ce5a24b38e5d672c05 ring buffer: Propagate __rb_map_vma return value to caller
```

### Tools

**Cscope:**  
```
cd linux/

# Generate Cscope Database:
make cscope -j8  

# This will generate files like
ls csocpe*
cscope.files cscope.out cscope.out.in cscope.out.po

# Enter Cscope Interactive Mode
cscope -d
```
This significantly improves symbol lookup compared to standard editor indexing.

**Closing Thoughts**

The learning was very rewarding, especially the Office Hours meetings and Discord discussions. I learned that kernel development and becoming a kernel hacker isn't an easy task that you can just pick up quickly. It requires consistent, dedicated effort. We need to acquire a deeper understanding of systems programming, architecture, and a willingness to troubleshoot complex issues. 

It's certainly a long but ultimately rewarding journey. I also learned about the development cycle of the Linux kernel. This program was a strong beginning, and the work will continue.

I will recommend this mentorship program to anyone interested in Linux kernel development. You'll learn the basics and find out if kernel development interests you in the long term. What I find most valuable is that you get a feel for the supportive open source community.

I am very thankful to Shuah, David and Khalid for this wonderful mentorship program.