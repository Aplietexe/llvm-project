## Check that the allocation combiner combines only stack pointer adjustments
## with nothing but CFI between them, and that each function's code and CFA
## rows stay correct. The calls in _start give BOLT the code relocations that
## --relocs needs, so every function moves and its FDE cannot be confused with
## the input's copy. Each function has its own check prefix and FileCheck run,
## so its checks bind to its own symbol, code, and FDE in any function order.

# REQUIRES: system-linux

# RUN: llvm-mc -filetype=obj -triple x86_64-unknown-unknown %s -o %t.o
# RUN: %clang %cflags %t.o -o %t.exe -Wl,-q -nostdlib
# RUN: llvm-bolt %t.exe -o %t.out --relocs --frame-opt=all | \
# RUN:   FileCheck %s --check-prefix=BOLT
# RUN: llvm-nm %t.out > %t.txt
# RUN: llvm-objdump -d --no-show-raw-insn %t.out >> %t.txt
# RUN: llvm-dwarfdump --eh-frame %t.out >> %t.txt
# RUN: FileCheck %s --input-file=%t.txt --check-prefix=FP
# RUN: FileCheck %s --input-file=%t.txt --check-prefix=SP_REL
# RUN: FileCheck %s --input-file=%t.txt --check-prefix=SUB_REL
# RUN: FileCheck %s --input-file=%t.txt --check-prefix=LEA_REL
# RUN: FileCheck %s --input-file=%t.txt --check-prefix=REG
# RUN: FileCheck %s --input-file=%t.txt --check-prefix=SPLIT
# RUN: FileCheck %s --input-file=%t.txt --check-prefix=ZERO
# RUN: FileCheck %s --input-file=%t.txt --check-prefix=ADJ_ALLOC
# RUN: FileCheck %s --input-file=%t.txt --check-prefix=ADJ_LEA
# RUN: FileCheck %s --input-file=%t.txt --check-prefix=ADJ_REL
# RUN: FileCheck %s --input-file=%t.txt --check-prefix=WIDE

# BOLT: BOLT-INFO: Allocation combiner: 5 empty spaces coalesced (dyn count: 0).

  .text

## The case from https://github.com/llvm/llvm-project/issues/211356. A fold
## would leave this %rbp-addressed frame below %rsp, past the red zone.
# FP:      [[#%x,FP:]] T fp_frame
# FP:      <fp_frame>:
# FP-NEXT: pushq %rbp
# FP-NEXT: movq %rsp, %rbp
# FP-NEXT: subq $0x100, %rsp
# FP-NEXT: movq %rdi, -0x100(%rbp)
# FP-NEXT: movq %rsi, -0x8(%rbp)
# FP-NEXT: movq %rdx, %rax
# FP-NEXT: addq -0x100(%rbp), %rax
# FP-NEXT: addq -0x8(%rbp), %rax
# FP-NEXT: addq $0x100, %rsp
# FP-NEXT: popq %rbp
# FP-NEXT: retq
# FP:      FDE {{.*}}pc=[[#%.8x,FP]]...[[#%.8x,FP+0x2d]]
# FP:      0x[[#FP]]: CFA=RSP+8:
# FP-NEXT: 0x[[#FP+0x1]]: CFA=RSP+16:
# FP-NEXT: 0x[[#FP+0x4]]: CFA=RBP+16:
# FP-NEXT: 0x[[#FP+0x2c]]: CFA=RSP+8:
# FP-EMPTY:
  .globl fp_frame
  .type fp_frame, @function
fp_frame:
  .cfi_startproc
  pushq %rbp
  .cfi_def_cfa_offset 16
  .cfi_offset %rbp, -16
  movq %rsp, %rbp
  .cfi_def_cfa_register %rbp
  subq $0x100, %rsp
  movq %rdi, -0x100(%rbp)
  movq %rsi, -0x8(%rbp)
  movq %rdx, %rax
  addq -0x100(%rbp), %rax
  addq -0x8(%rbp), %rax
  addq $0x100, %rsp
  popq %rbp
  .cfi_def_cfa %rsp, 8
  retq
  .cfi_endproc
  .size fp_frame, .-fp_frame

# SP_REL:      [[#%x,SP_REL:]] T sp_release
# SP_REL:      <sp_release>:
# SP_REL-NEXT: subq $0x8, %rsp
# SP_REL-NEXT: leaq 0x1(%rdi), %rax
# SP_REL-NEXT: addq $0x8, %rsp
# SP_REL-NEXT: retq
# SP_REL:      FDE {{.*}}pc=[[#%.8x,SP_REL]]...[[#%.8x,SP_REL+0xd]]
# SP_REL:      0x[[#SP_REL]]: CFA=RSP+8:
# SP_REL-NEXT: 0x[[#SP_REL+0x4]]: CFA=RSP+16:
# SP_REL-NEXT: 0x[[#SP_REL+0xc]]: CFA=RSP+8:
# SP_REL-EMPTY:
  .globl sp_release
  .type sp_release, @function
sp_release:
  .cfi_startproc
  subq $0x8, %rsp
  .cfi_def_cfa_offset 16
  leaq 1(%rdi), %rax
  addq $0x8, %rsp
  .cfi_def_cfa_offset 8
  retq
  .cfi_endproc
  .size sp_release, .-sp_release

# SUB_REL:      [[#%x,SUB_REL:]] T sub_release
# SUB_REL:      <sub_release>:
# SUB_REL-NEXT: subq $0x8, %rsp
# SUB_REL-NEXT: leaq 0x1(%rdi), %rax
# SUB_REL-NEXT: subq $-0x8, %rsp
# SUB_REL-NEXT: retq
# SUB_REL:      FDE {{.*}}pc=[[#%.8x,SUB_REL]]...[[#%.8x,SUB_REL+0xd]]
# SUB_REL:      0x[[#SUB_REL]]: CFA=RSP+8:
# SUB_REL-NEXT: 0x[[#SUB_REL+0x4]]: CFA=RSP+16:
# SUB_REL-NEXT: 0x[[#SUB_REL+0xc]]: CFA=RSP+8:
# SUB_REL-EMPTY:
  .globl sub_release
  .type sub_release, @function
sub_release:
  .cfi_startproc
  subq $0x8, %rsp
  .cfi_def_cfa_offset 16
  leaq 1(%rdi), %rax
  subq $-0x8, %rsp
  .cfi_def_cfa_offset 8
  retq
  .cfi_endproc
  .size sub_release, .-sub_release

# LEA_REL:      [[#%x,LEA_REL:]] T lea_release
# LEA_REL:      <lea_release>:
# LEA_REL-NEXT: subq $0x8, %rsp
# LEA_REL-NEXT: leaq 0x1(%rdi), %rax
# LEA_REL-NEXT: leaq 0x8(%rsp), %rsp
# LEA_REL-NEXT: retq
# LEA_REL:      FDE {{.*}}pc=[[#%.8x,LEA_REL]]...[[#%.8x,LEA_REL+0xe]]
# LEA_REL:      0x[[#LEA_REL]]: CFA=RSP+8:
# LEA_REL-NEXT: 0x[[#LEA_REL+0x4]]: CFA=RSP+16:
# LEA_REL-NEXT: 0x[[#LEA_REL+0xd]]: CFA=RSP+8:
# LEA_REL-EMPTY:
  .globl lea_release
  .type lea_release, @function
lea_release:
  .cfi_startproc
  subq $0x8, %rsp
  .cfi_def_cfa_offset 16
  leaq 1(%rdi), %rax
  leaq 0x8(%rsp), %rsp
  .cfi_def_cfa_offset 8
  retq
  .cfi_endproc
  .size lea_release, .-lea_release

# REG:      [[#%x,REG:]] T reg_between
# REG:      <reg_between>:
# REG-NEXT: subq $0x8, %rsp
# REG-NEXT: movq %rdi, %rax
# REG-NEXT: subq $0x10, %rsp
# REG-NEXT: movq %rax, (%rsp)
# REG-NEXT: addq $0x18, %rsp
# REG-NEXT: retq
# REG:      FDE {{.*}}pc=[[#%.8x,REG]]...[[#%.8x,REG+0x14]]
# REG:      0x[[#REG]]: CFA=RSP+8:
# REG-NEXT: 0x[[#REG+0x4]]: CFA=RSP+16:
# REG-NEXT: 0x[[#REG+0xb]]: CFA=RSP+32:
# REG-NEXT: 0x[[#REG+0x13]]: CFA=RSP+8:
# REG-EMPTY:
  .globl reg_between
  .type reg_between, @function
reg_between:
  .cfi_startproc
  subq $0x8, %rsp
  .cfi_def_cfa_offset 16
  movq %rdi, %rax
  subq $0x10, %rsp
  .cfi_def_cfa_offset 32
  movq %rax, (%rsp)
  addq $0x18, %rsp
  .cfi_def_cfa_offset 8
  retq
  .cfi_endproc
  .size reg_between, .-reg_between

# SPLIT:      [[#%x,SPLIT:]] T split_alloc
# SPLIT:      <split_alloc>:
# SPLIT-NEXT: subq $0x8, %rsp
# SPLIT-NEXT: leaq 0x1(%rdi), %rax
# SPLIT-NEXT: subq $0x10, %rsp
# SPLIT-NEXT: leaq 0x2(%rax), %rax
# SPLIT-NEXT: addq $0x18, %rsp
# SPLIT-NEXT: retq
# SPLIT:      FDE {{.*}}pc=[[#%.8x,SPLIT]]...[[#%.8x,SPLIT+0x15]]
# SPLIT:      0x[[#SPLIT]]: CFA=RSP+8:
# SPLIT-NEXT: 0x[[#SPLIT+0x4]]: CFA=RSP+16:
# SPLIT-NEXT: 0x[[#SPLIT+0xc]]: CFA=RSP+32:
# SPLIT-NEXT: 0x[[#SPLIT+0x14]]: CFA=RSP+8:
# SPLIT-EMPTY:
  .globl split_alloc
  .type split_alloc, @function
split_alloc:
  .cfi_startproc
  subq $0x8, %rsp
  .cfi_def_cfa_offset 16
  leaq 1(%rdi), %rax
  subq $0x10, %rsp
  .cfi_def_cfa_offset 32
  leaq 2(%rax), %rax
  addq $0x18, %rsp
  .cfi_def_cfa_offset 8
  retq
  .cfi_endproc
  .size split_alloc, .-split_alloc

## Folding the subq $0x10 into the subq $0x0 would leave the first leaq under
## the inherited rule CFA=RSP+8.
# ZERO:      [[#%x,ZERO:]] T zero_alloc
# ZERO:      <zero_alloc>:
# ZERO-NEXT: subq $0x0, %rsp
# ZERO-NEXT: leaq 0x1(%rdi), %rax
# ZERO-NEXT: subq $0x10, %rsp
# ZERO-NEXT: leaq 0x2(%rax), %rax
# ZERO-NEXT: addq $0x10, %rsp
# ZERO-NEXT: retq
# ZERO:      FDE {{.*}}pc=[[#%.8x,ZERO]]...[[#%.8x,ZERO+0x15]]
# ZERO:      0x[[#ZERO]]: CFA=RSP+8:
# ZERO-NEXT: 0x[[#ZERO+0xc]]: CFA=RSP+24:
# ZERO-NEXT: 0x[[#ZERO+0x14]]: CFA=RSP+8:
# ZERO-EMPTY:
  .globl zero_alloc
  .type zero_alloc, @function
zero_alloc:
  .cfi_startproc
  subq $0x0, %rsp
  leaq 1(%rdi), %rax
  subq $0x10, %rsp
  .cfi_def_cfa_offset 24
  leaq 2(%rax), %rax
  addq $0x10, %rsp
  .cfi_def_cfa_offset 8
  retq
  .cfi_endproc
  .size zero_alloc, .-zero_alloc

# ADJ_ALLOC:      [[#%x,ADJ_ALLOC:]] T adjacent_alloc
# ADJ_ALLOC:      <adjacent_alloc>:
# ADJ_ALLOC-NEXT: subq $0x18, %rsp
# ADJ_ALLOC-NEXT: leaq 0x1(%rdi), %rax
# ADJ_ALLOC-NEXT: addq $0x18, %rsp
# ADJ_ALLOC-NEXT: retq
# ADJ_ALLOC:      FDE {{.*}}pc=[[#%.8x,ADJ_ALLOC]]...[[#%.8x,ADJ_ALLOC+0xd]]
# ADJ_ALLOC:      0x[[#ADJ_ALLOC]]: CFA=RSP+8:
# ADJ_ALLOC-NEXT: 0x[[#ADJ_ALLOC+0x4]]: CFA=RSP+32:
# ADJ_ALLOC-NEXT: 0x[[#ADJ_ALLOC+0xc]]: CFA=RSP+8:
# ADJ_ALLOC-EMPTY:
  .globl adjacent_alloc
  .type adjacent_alloc, @function
adjacent_alloc:
  .cfi_startproc
  subq $0x8, %rsp
  .cfi_def_cfa_offset 16
  subq $0x10, %rsp
  .cfi_def_cfa_offset 32
  leaq 1(%rdi), %rax
  addq $0x18, %rsp
  .cfi_def_cfa_offset 8
  retq
  .cfi_endproc
  .size adjacent_alloc, .-adjacent_alloc

# ADJ_LEA:      [[#%x,ADJ_LEA:]] T adjacent_lea
# ADJ_LEA:      <adjacent_lea>:
# ADJ_LEA-NEXT: leaq -0x18(%rsp), %rsp
# ADJ_LEA-NEXT: movq %rdi, (%rsp)
# ADJ_LEA-NEXT: addq $0x18, %rsp
# ADJ_LEA-NEXT: retq
# ADJ_LEA:      FDE {{.*}}pc=[[#%.8x,ADJ_LEA]]...[[#%.8x,ADJ_LEA+0xe]]
# ADJ_LEA:      0x[[#ADJ_LEA]]: CFA=RSP+8:
# ADJ_LEA-NEXT: 0x[[#ADJ_LEA+0x5]]: CFA=RSP+32:
# ADJ_LEA-NEXT: 0x[[#ADJ_LEA+0xd]]: CFA=RSP+8:
# ADJ_LEA-EMPTY:
  .globl adjacent_lea
  .type adjacent_lea, @function
adjacent_lea:
  .cfi_startproc
  leaq -0x10(%rsp), %rsp
  .cfi_def_cfa_offset 24
  subq $0x8, %rsp
  .cfi_def_cfa_offset 32
  movq %rdi, (%rsp)
  addq $0x18, %rsp
  .cfi_def_cfa_offset 8
  retq
  .cfi_endproc
  .size adjacent_lea, .-adjacent_lea

# ADJ_REL:      [[#%x,ADJ_REL:]] T adjacent_release
# ADJ_REL:      <adjacent_release>:
# ADJ_REL-NEXT: subq $0x18, %rsp
# ADJ_REL-NEXT: movq %rdi, (%rsp)
# ADJ_REL-NEXT: addq $0x18, %rsp
# ADJ_REL-NEXT: retq
# ADJ_REL:      FDE {{.*}}pc=[[#%.8x,ADJ_REL]]...[[#%.8x,ADJ_REL+0xd]]
# ADJ_REL:      0x[[#ADJ_REL]]: CFA=RSP+8:
# ADJ_REL-NEXT: 0x[[#ADJ_REL+0x4]]: CFA=RSP+32:
# ADJ_REL-NEXT: 0x[[#ADJ_REL+0xc]]: CFA=RSP+8:
# ADJ_REL-EMPTY:
  .globl adjacent_release
  .type adjacent_release, @function
adjacent_release:
  .cfi_startproc
  subq $0x18, %rsp
  .cfi_def_cfa_offset 32
  movq %rdi, (%rsp)
  addq $0x8, %rsp
  .cfi_def_cfa_offset 24
  addq $0x10, %rsp
  .cfi_def_cfa_offset 8
  retq
  .cfi_endproc
  .size adjacent_release, .-adjacent_release

## The combined immediate is outside the signed 8-bit range.
# WIDE:      [[#%x,WIDE:]] T wide_chain
# WIDE:      <wide_chain>:
# WIDE-NEXT: subq $0xc0, %rsp
# WIDE-NEXT: movq %rdi, (%rsp)
# WIDE-NEXT: addq $0xc0, %rsp
# WIDE-NEXT: retq
# WIDE:      FDE {{.*}}pc=[[#%.8x,WIDE]]...[[#%.8x,WIDE+0x13]]
# WIDE:      0x[[#WIDE]]: CFA=RSP+8:
# WIDE-NEXT: 0x[[#WIDE+0x7]]: CFA=RSP+200:
# WIDE-NEXT: 0x[[#WIDE+0x12]]: CFA=RSP+8:
# WIDE-EMPTY:
  .globl wide_chain
  .type wide_chain, @function
wide_chain:
  .cfi_startproc
  subq $0x40, %rsp
  .cfi_def_cfa_offset 72
  subq $0x40, %rsp
  .cfi_def_cfa_offset 136
  subq $0x40, %rsp
  .cfi_def_cfa_offset 200
  movq %rdi, (%rsp)
  addq $0xc0, %rsp
  .cfi_def_cfa_offset 8
  retq
  .cfi_endproc
  .size wide_chain, .-wide_chain

  .globl _start
  .type _start, @function
_start:
  callq fp_frame
  callq sp_release
  callq sub_release
  callq lea_release
  callq reg_between
  callq split_alloc
  callq zero_alloc
  callq adjacent_alloc
  callq adjacent_lea
  callq adjacent_release
  callq wide_chain
  retq
  .size _start, .-_start
