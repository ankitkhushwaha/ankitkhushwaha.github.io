---
title: programming concepts
weight: 19
---

In this section, I'll try to cover the programming concepts.

---

## 'Thundering Herd problem'

where hundreds of processes are woken up at once to fight for the same lock.

We can observe this situation when `wait_queue_head` is waked up by `wake_up_all`; multiple list element trying to access the same lock/resources. 
To Handle these situation its better to try exclusive wake up - `wake_up{,_nr}`.

---
