---
layout: post
title: "Tweaking On Compilers: Kill the Runtime"
date: 2026-08-07
description: "What really happens before main()? A journey from C runtime and ELF entry points to building tiny executables without libc"
tags: [compilers, assembly, c, elf, linux, systems-programming, low-level, reverse-engineering]
---

I recently started a new project called mostools. It's a toolchain consisting of an assembler, linker, and object dumper that works with Zig-written MOS 6502 processors. This has given me a lot of time to read about compilers, assemblers, and linkers, and I've discovered some great things. During this time, I've also started creating, examining, dumping, and running very simple programs. Because my toolchain is quite small, or as I prefer to say, "experimental," I can only run tiny programs for now :)

Unlike my other blog posts, this one will describe experiments I conducted on a small program. In doing so, I'll delve deeper into the ELF file format and how our code travels between source code, compilers, linkers, and the operating system. If you've read my previous posts, you'll know I have a habit of never offering tutorials. I'm not changing that rule today either. This post is simply a collection of notes and results from a lighthearted experiment, which, at least for me, piqued my curiosity. Rather than answering the question of how compilers work, it contains topics that I believe will interest engineers with the expertise to write compilers. With that in mind, I wish you happy reading.

## The 11kB Problem

I needed a small ELF object file to run on my own toolchain, so I wrote this tiny program:

```c
int main()
{
    return 8;
}
```

As you can see, this program, which doesn't include any libraries, has only one purpose: to return the number 8 from `main()`.

And as you might guess, that's exactly what it did. But there was another thing that really caught my attention: this smallest code block I can think of, compiled as an ELF file, is exactly 11 kB.

```sh
~/Dev/sandbox/tiny ❯ file tinyc
tinyc: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, BuildID[sha1]=0d6460d732f447fe1a04c3bfdb124bec1a7b081d, for GNU/Linux 3.2.0, stripped

~/Dev/sandbox/tinyc ❯ wc -c tinyc
11032 tinyc
```

Despite its small size, there's a very good reason why this file is 11 kB. It doesn't just contain our tiny `main()` function; it also contains ELF metadata, startup code, dynamic linking information, and other runtime-related data required to turn our object file into an executable.

So, essentially, you're writing the `main()` function, but that's not the first piece of code called. The compiler compiles your code into an object file, and during linking, the linker combines it with startup objects and the libraries required by the program. This way, when writing C code, you don't have to deal directly with the process startup sequence, the ABI details of calling `main()`, or directly communicate with the operating system (at least not unless you specifically want to).

## CRT on Linker Side

Of course, this works differently depending on whether your program is compiled statically or dynamically. If you compile your executable dynamically, as in my small program, the CRT process works like this:

```text
tinyc
|
|- our .text segment
|- CRT startup routine
|- dynamic linker metadata
|- references to dynamically linked libraries
```

Here, the CRT doesn't include the entire libc in the executable; instead, the executable contains the information necessary to resolve calls to shared libraries such as glibc or musl at runtime. As a result, the compiled ELF file is relatively small. If you'd like, let's also compile the same source code statically and see its size:

```sh
~/Dev/sandbox/tiny ❯ file tinyc
tinyc: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, BuildID[sha1]=274214c8958d633c9ed24079835dc4a8a67b3196, for GNU/Linux 3.2.0, stripped, too many notes (256)

~/Dev/sandbox/tinyc ❯ wc -c tinyc
722216 tinyc
```

As you can see, our executable has become more than 700 kB larger because the parts of libc and the runtime support required by the program are now linked into the executable instead of being provided by shared libraries at runtime.

Everything I've tried so far has been based on basic C concepts that I already know. From here on, I wanted to write a similar program in assembly and observe its behavior.

## Assembly Re-write

The purpose of the small driver code we wrote was clear: to return the number 8. For this, I wrote the following code:

```asm
; TINY.ASM
BITS 64
GLOBAL main
SECTION .text

main:
    mov rax, 8
    ret
```

```sh
~/Dev/sandbox/tiny ❯ nasm -f elf64 tiny.asm -o tinyasm.o
~/Dev/sandbox/tiny ❯ gcc -Wall -s tinyasm.o -o tinyasm
~/Dev/sandbox/tiny ❯ wc -c tinyasm
11032 tinyasm
```

This is where the really interesting part started for me: I assembled it with NASM and linked it with GCC, but the file size is the same as the C version. My plan here was to get a program of a few bytes without any C runtime influence.

## Examining tinyasm.o

My first thought was whether NASM also creates an 11kB file, so I decided to examine the tinyasm.o object. 

```sh
~/Dev/sandbox/tiny ❯ wc -c tinyasm.o                                                                 ≡ 23:28:42
560 tinyasm.o

~/Dev/sandbox/tiny ❯ readelf -S tinyasm.o                                                            ≡ 23:28:45
There are 5 section headers, starting at offset 0x40:

Section Headers:
  [Nr] Name              Type             Address           Offset
       Size              EntSize          Flags  Link  Info  Align
  [ 0]                   NULL             0000000000000000  00000000
       0000000000000000  0000000000000000           0     0     0
  [ 1] .text             PROGBITS         0000000000000000  00000180
       0000000000000006  0000000000000000  AX       0     0     16
  [ 2] .shstrtab         STRTAB           0000000000000000  00000190
       0000000000000021  0000000000000000           0     0     1
  [ 3] .symtab           SYMTAB           0000000000000000  000001c0
       0000000000000060  0000000000000018           4     3     8
  [ 4] .strtab           STRTAB           0000000000000000  00000220
       000000000000000f  0000000000000000           0     0     1
Key to Flags:
  W (write), A (alloc), X (execute), M (merge), S (strings), I (info),
  L (link order), O (extra OS processing required), G (group), T (TLS),
  C (compressed), x (unknown), o (OS specific), E (exclude),
  D (mbind), l (large), p (processor specific)
```

So as you can see, `tinyasm.o` is still an object file that needed to be figured out by linker and nothning extra added by NASM itself.

Let's check what GCC actually calls while linking: 

```sh
~/Dev/sandbox/tiny ❯ gcc -### tinyasm.o -o tinyasm | grep crt | xc                                   ≡ 23:33:02

...
/lib64 -L/lib/../lib64 -L/usr/lib/../lib64 -L/usr/lib/gcc/x86_64-redhat-linux/15/../../.. -L/lib -L/usr/lib tinyasm.o -lgcc --push-state --as-needed -lgcc_s --pop-state -lc -lgcc --push-state --as-needed -lgcc_s --pop-state /usr/lib/gcc/x86_64-redhat-linux/15/crtend.o /usr/lib/gcc/x86_64-redhat-linux/15/../../../../lib64/crtn.o
COLLECT_GCC_OPTIONS='-o' 'tinyasm' '-mtune=generic' '-march=x86-64' '-dumpdir' 'tinyasm.'
...
```

Voila, Even though we assembled our code with NASM, linking it with GCC pulls the C runtime startup objects and standard libraries into the link.

## Kill The Runtime

At this point, the problem was pretty clear. NASM was doing exactly what I wanted: it was producing a tiny relocatable object file with only 6 bytes of actual machine code. The extra code was being introduced when I handed that object file to GCC for linking.

So instead of asking GCC to link it, why not just use the linker directly?

```sh
~/Dev/sandbox/tiny ❯ ld tinyasm.o -o tinyasm                                                         ≡ 23:36:16
ld: warning: cannot find entry symbol _start; defaulting to 0000000000400080
```

Interesting.

The linker is looking for `_start`, not main.

This is actually the first indication that `main()` was never the real entry point of our executable. GCC had been hiding this detail from us by providing the startup code that eventually calls `main()`.

Let's make the entry point explicit and remove `main()` altogether:
```asm
    ; TINY.ASM
BITS 64
GLOBAL _start
SECTION .text
_start:
    mov rax, 60
    mov rdi, 8
    syscall
```

There are two things worth noticing here.

First, 60 is the Linux x86-64 system call number for exit. Second, the first argument to the system call is passed in RDI, so we put 8 there as the exit status.

We can now assemble and link the program without GCC:

```sh 
~/Dev/sandbox/tiny ❯ nasm -f elf64 tiny.asm -o tiny.o
~/Dev/sandbox/tiny ❯ ld tiny.o -o tiny
~/Dev/sandbox/tiny ❯ wc -c tiny
...
~/Dev/sandbox/tiny ❯ wc -c tinyasm                                                                   ≡ 23:39:47
680 tinyasm
```



And just like that, we've removed the C runtime from the picture.

There is no main(), no libc, and no compiler-generated startup code involved anymore. The executable starts at _start, performs a system call directly, and terminates.

The execution path is now much simpler:

```sh

Linux kernel
     |
     v
  _start
     |
     v
  syscall
     |
     v
  sys_exit
```

This is much closer to what I originally had in mind when I wrote a six-byte program. But there is still one question that bothered me.

Why did `_start` work?

Why does Linux start execution there, while main() required all that machinery around it?

To answer that, we need to look at the ELF header itself.

## Where Does a Program Actually Start?

We now have a working executable without the C runtime. But there is still one thing I wanted to understand: why does `_start` work?

The answer is sitting inside the ELF header.

```sh
~/Dev/sandbox/tiny ❯ readelf -h tinyasm

ELF Header:
  ...
  Entry point address:               0x400080
  ...
```

The ELF format has a field called `e_entry`. It contains the virtual address where execution should begin after the executable has been loaded.

In our case, that address points directly to `_start`.

We can verify this with `objdump`:

```sh
~/Dev/sandbox/tiny ❯ objdump -d tinyasm                                                              ≡ 23:43:05

tinyasm:     file format elf64-x86-64


Disassembly of section .text:

0000000000400080 <_start>:
  400080:	b8 3c 00 00 00       	mov    $0x3c,%eax
  400085:	bf 08 00 00 00       	mov    $0x8,%edi
  40008a:	0f 05                	syscall
~/Dev/sandbox/tiny ❯   
```

There is no special meaning attached to the name `_start` here. The kernel doesn't search for a function called `_start`. The important thing is that the ELF entry point points to its address.

This also explains why `main()` was never the actual beginning of our program.

When we used GCC, the executable contained startup code supplied by the C runtime. The entry point led into that startup machinery, which performed the work necessary to establish the C runtime environment and eventually call `main()`.

Conceptually, the path looked something like this:

```text
                         dynamically linked program

Linux
  |
  v
ELF entry point
  |
  v
dynamic linker / loader
  |
  v
_start
  |
  v
C runtime
  |
  v
__libc_start_main
  |
  v
main()
```

Our tiny program takes a much shorter path:

```text
Linux
  |
  v
ELF entry point
  |
  v
_start
  |
  v
syscall
  |
  v
exit
```

This is the distinction I was looking for from the beginning.

`main()` is a C abstraction. It is part of the interface provided by the C runtime, not something the Linux kernel requires from an executable.

The kernel only needs an executable with a valid ELF format, loadable segments, and an entry point.

## So, What Was the 11 kB?

Let's go back to where we started.

Our original C program was:

```c
int main()
{
    return 8;
}
```

The source itself is tiny. Even the machine code representing its actual logic is tiny.

Yet the dynamically linked executable was:

```text
11032 bytes
```

The reason is that an executable is much more than its instructions.

It contains ELF metadata, program headers, sections and segments, dynamic linking information, startup code, symbol and relocation information, alignment, and other pieces required by the particular toolchain and linking configuration.

Then we tried assembly:

```asm
_start:
    mov rax, 60
    mov rdi, 8
    syscall
```

The actual instructions are only a handful of bytes.

But when we linked the object with GCC, we got the same 11 kB executable because GCC was still adding the same startup and runtime machinery.

Once we bypassed GCC's default linking behavior and linked the object directly with `ld`, that machinery disappeared.

The important lesson wasn't that C produces large programs or that assembly magically produces small ones.

The interesting part was **where the extra code came from**.

The compiler wasn't secretly making our six-byte program huge. The toolchain was building a complete executable around it.

## One Last Look at the Binary

At this point, we can compare the three different things we created:

```text
tinyasm.o
    |
    +-- 6 bytes of machine code
    +-- ELF relocatable-object metadata
    +-- symbol/string tables
    |
    v
    560 bytes


gcc tinyasm.o -o tinyasm
    |
    +-- machine code
    +-- CRT
    +-- dynamic linking information
    +-- ELF executable metadata
    |
    v
    11032 bytes


ld tiny.o -o tiny
    |
    +-- machine code
    +-- minimal executable structure
    +-- ELF entry point
    |
    v
    tiny executable
```

The exact final size is not particularly important. It depends on the linker, linker script, ELF layout, alignment, and whether the binary is stripped or otherwise optimized.

What matters is that we can now account for the layers between the code we wrote and the executable we run.

And that was really what I wanted to find out.

## Closing the Runtime

When we write:

```c
int main()
{
    return 8;
}
```

it is tempting to imagine that the operating system simply loads the program and calls `main()`.

It doesn't.

There is a whole world between those two points.

The compiler turns our source into machine code. The assembler turns assembly into relocatable object files. The linker turns those objects into an executable. The ELF file describes how that executable should be loaded. The operating system loads it and begins execution at the address specified by the ELF entry point. The C runtime then provides the abstractions that eventually make `main()` possible.

And none of that is mandatory.

We can remove the layers we don't need.

We can skip `main()`.
We can skip libc.
We can skip the C runtime.
We can talk directly to the kernel.

At that point, there isn't much left between our code and the machine.

Maybe that's the most interesting thing I learned from this experiment: **the program we write is not necessarily the program that gets executed.**

There is a whole toolchain between the two.

And sometimes, it's fun to take it apart.

