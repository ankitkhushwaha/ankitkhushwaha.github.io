---
date: "2025-12-17T10:48:03+05:30"
draft: False
title: "Ankit Khushwaha"
weight: 2
comments: false
ShowReadingTime: false
ShowToc: false
hideMeta: true
---
```
/* ~/ankit_khushwaha.c */

#include <stdio.h>

struct developer {
  const char *name;
  const char *role;
  const char *university;
  const char *degree;
};

static struct developer ankit = {
    .name = "Ankit Khushwaha",
    .role = "Student",
    .university = "IIT Dharwad",
    .degree = "BS-MS Physics",
};

static const char *skills[] = {
    "C", "Linux Kernel", "Device Drivers", "Git", "QEMU",
};

static const char *interests[] = {
    "Kernel Development",
    "Operating Systems",
    "Systems Programming",
    "Computer Security",
};

static const char *links[] = {
    "github.com/ankitkhushwaha",
    "linkedin.com/in/ankitkhushwaha",
    "ankitkdev.com",
    "[ankitkhushwaha.dev@gmail.com](mailto:ankitkhushwaha.dev@gmail.com)",
};

int workflow(void) {
    printf("[+] Reading kernel source...\n"
            "[+] Writing device drivers...\n"
            "[+] Debugging kernel crashes...\n"
            "[+] Studying kernel security...\n"
            "[+] Sending patches upstream...\n\n");

    return 0;
}

const char *currently_learning(void) {
    return "Linux kernel internals, device drivers, "
            "and low-level systems programming";
}

const char *future_goal(void) {
    return "Build secure and reliable systems, "
            "contribute to the Linux kernel, and "
            "specialize in device drivers and security";
}

static void print_profile(void) {
    size_t i;

    printf("Name       : %s\n", ankit.name);
    printf("Role       : %s\n", ankit.role);
    printf("University : %s\n", ankit.university);
    printf("Degree     : %s\n", ankit.degree);

    printf("\nSkills:\n");
    for (i = 0; i < sizeof(skills) / sizeof(skills[0]); i++)
        printf("  - %s\n", skills[i]);

    printf("\nInterests:\n");
    for (i = 0; i < sizeof(interests) / sizeof(interests[0]); i++)
        printf("  - %s\n", interests[i]);

    printf("\nCurrently Learning:\n");
    printf("  %s\n", currently_learning());

    printf("\nFuture Goal:\n");
    printf("  %s\n", future_goal());

    printf("\nLinks:\n");
    for (i = 0; i < sizeof(links) / sizeof(links[0]); i++)
        printf("  - %s\n", links[i]);
}

int main(void) {
    workflow();
    print_profile();

    return 0;
}
```