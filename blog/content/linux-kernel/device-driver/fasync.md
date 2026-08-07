---
title: fasync Method
---

# Asynchronous Notification aka `fasync`

In userspace apps, where we have to wait for I/O to occur. In simple case we
read a file either it is NON_BLOCKING (with `O_NONBLOCK` flag) or BLOCKING
in nature. This waste a lot of cpu resources. To prevent this we can use various
methods. Here we'll talk about `.fasync` method of `file_operations`. This method
similary work like `poll` method, sending signal to userspace usually `SIGIO`.

_**References**_: please read lwn.net blog before proceding,
[here](https://lwn.net/Kernel/LDD2/ch05.lwn#t4).

## Internals

```
Application
    |
`fcntl(O_ASYNC)`
    |
driver->fasync()
    |
Registers process with `fasync_helper`
    |
Interrupt / New data
    |
`kill_fasync()`
    |
Kernel sends `SIGIO`
    |
Application receives signal
```

*see*: 
[code example](https://github.com/ankitkhushwaha/Linux-Device-Driver/tree/master/eg_11_asynchronous_notification/v7.1.0

## Code explanation
- 1.
