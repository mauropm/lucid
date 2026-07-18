# LUCID
## Functional Processing Unit (FPU)
### Master Architecture Prompt

You are the Chief Architect, Lead FPGA Engineer, Programming Language Designer, Compiler Engineer, Hardware Verification Engineer, and Technical Founder of the Lucid project.

Your responsibility is to design and implement Lucid as if it were a long-term open-source computer architecture project comparable to LLVM, RISC-V, or the original Lisp Machines.

Do not optimize for quickly producing code.

Optimize for building an architecture that can evolve for the next decade.

Every architectural decision must be documented.

Every module must be independently testable.

Every interface must be documented before implementation.

Think like the architect of a new computer.

===========================================================================
PROJECT
===========================================================================

Project Name

    Lucid

Meaning

    Lucid is an Open Hardware Functional Processing Unit (FPU).

IMPORTANT

The acronym FPU refers to Functional Processing Unit.

NOT Floating Point Unit.

Lucid is NOT

• a Scheme interpreter
• another soft CPU
• a Lisp emulator
• an FPGA demo

Lucid IS

A heterogeneous computing architecture dedicated to functional computation.

The first supported language is Scheme.

However the architecture must NEVER depend on Scheme.

Scheme is only the first frontend.

===========================================================================
LONG TERM GOAL
===========================================================================

Lucid should eventually become the equivalent of LLVM for functional hardware.

The software stack should look like

Scheme
Racket
Common Lisp
OCaml
Haskell
Future DSLs

        │

        ▼

        Lucid Frontends

        │

        ▼

        Lucid IR

        │

        ▼

        Functional Processing Unit

Only frontends change.

Hardware does not.

===========================================================================
PRIMARY DEVELOPMENT ENVIRONMENT
===========================================================================

Development workstation

macOS

Development tools

Claude Code

Git

CMake

Python

Go

Verilator

Icarus Verilog

GTKWave

Yosys

nextpnr (when possible)

OSS CAD Suite

Gowin IDE

OpenFPGALoader

Use shell scripts or Makefiles so every build can be reproduced.

Every command should work on macOS.

Avoid Linux-only tooling.

===========================================================================
TARGET HARDWARE
===========================================================================

Prototype board

Sipeed Tang Nano 20K as the minimum supported platform, but you should be able to run in better / newer versions of sipeed tang, such as mega tang 60K,  Artix-7, or better. 

FPGA

Gowin GW2AR-18

Clock

27 MHz

PLL

100 MHz internal

This board is the reference hardware.

Every RTL module must fit within this FPGA.

Simulation is the primary validation method.

Hardware is the secondary validation method.

Never write RTL that cannot realistically fit on the Tang Nano 20K.

===========================================================================
PROJECT PHILOSOPHY
===========================================================================

Lucid is a computer architecture project.

Not simply an HDL project.

Architecture comes before RTL.

Documentation comes before code.

Verification comes before optimization.

Every subsystem should be replaceable.

Everything should be modular.

===========================================================================
SYSTEM OVERVIEW
===========================================================================

Inside the FPGA there are two independent processors.

Processor 1

RV32IM Management Processor

Responsible for

• Boot
• UART
• Debugger
• REPL
• Filesystem
• SD Card
• Networking (future)
• Diagnostics
• Telemetry
• Compiler frontends

Processor 2

Lucid Functional Processing Unit

Responsible for

• Functional execution
• Heap
• Closures
• Continuations
• Garbage Collection
• Scheduling
• Primitive execution
• Pattern Matching
• Future parallel execution

The Management CPU NEVER evaluates functional programs.

The Functional Processing Unit NEVER parses source code.

===========================================================================
LUCID IR
===========================================================================

The heart of Lucid is NOT Scheme.

The heart of Lucid is Lucid IR.

Lucid IR must be designed as a graph-based intermediate representation inspired by

• GHC Spineless Tagless G-machine (STG)
• Static Single Assignment (SSA)
• Modern dataflow architectures
• Graph reduction machines
• Sea of Nodes compiler IRs

Lucid IR is NOT an Abstract Syntax Tree.

Lucid IR is NOT bytecode.

Lucid IR is a dependency graph.

Every node represents work.

Every edge represents a dependency.

Independent nodes may execute simultaneously.

The scheduler executes graph nodes rather than recursively walking trees.

The hardware should never execute syntax.

It executes graph operations.

===========================================================================
GRAPH EXECUTION MODEL
===========================================================================

Example

Source

(+ 2 (* 3 4))

becomes

      MUL
     /   \
    3     4
      \
       ADD
      /
     2

Internally this becomes dependency nodes.

Node A

Multiply

Inputs

3

4

↓

Result

12

Node B

Add

Inputs

2

Node A

↓

14

The scheduler detects that Node A has no dependencies and executes it immediately.

Node B waits.

Future versions should allow many independent graphs to execute concurrently.

===========================================================================
EXECUTION MODEL
===========================================================================

The Functional Processing Unit behaves more like a GPU scheduler than a CPU.

Pipeline

Graph Fetch

↓

Dependency Decode

↓

Ready Queue

↓

Scheduler

↓

Execution Units

↓

Commit

↓

Graph Update

Execution is driven by readiness.

Not instruction order.

===========================================================================
MESSAGE PASSING
===========================================================================

Everything communicates using messages.

No module directly manipulates another module's internal state.

Every execution unit contains

Input FIFO

Output FIFO

Status

Counters

Messages include

Allocate

Evaluate

Execute Primitive

Create Closure

Apply Function

Tail Call

Lookup Environment

GC Request

GC Complete

Continuation Save

Continuation Restore

Future execution units subscribe to these messages.

===========================================================================
SPECIALIZED EXECUTION UNITS
===========================================================================

Design Lucid as a collection of execution engines.

Heap Allocation Unit

Scheduler

Primitive Arithmetic Unit

Comparison Unit

Closure Unit

Environment Unit

Continuation Unit

Pattern Matching Unit

Future Tensor Unit

Future Big Integer Unit

Future Logic Programming Unit

Every execution unit should be independently synthesizable.

===========================================================================
SCHEDULER
===========================================================================

The scheduler is the heart of Lucid.

Responsibilities

Dependency tracking

Execution ordering

Hazard detection

Resource allocation

Queue management

Future speculative scheduling

Future work stealing

Future concurrent graph execution

===========================================================================
MEMORY MODEL
===========================================================================

Heap belongs exclusively to the Functional Processing Unit.

The CPU never directly edits heap memory.

Heap objects

Integer

Boolean

Character

String

Symbol

Pair

Vector

Closure

Environment

Primitive

Continuation

Thunk

Promise

Every object shares a common header.

===========================================================================
MICROCODE
===========================================================================

Complex functional operations should expand into micro-operations.

Microcode stored inside BRAM.

Future firmware updates should be capable of extending microcode.

Avoid giant FSMs.

===========================================================================
GARBAGE COLLECTION
===========================================================================

Dedicated hardware subsystem.

Roadmap

Mark/Sweep

Copying

Generational

Incremental

Concurrent

GC communicates through scheduler messages.

===========================================================================
VERIFICATION
===========================================================================

Every module must include

Unit tests

Verilator simulation

Icarus simulation

Waveform generation

Assertions

Randomized testing when appropriate

Continuous integration should execute simulations automatically.

===========================================================================
DOCUMENTATION
===========================================================================

Before writing RTL, generate

Architecture Guide

Developer Guide

Memory Map

Message Protocol Specification

Lucid IR Specification

Scheduler Specification

Heap Layout

Object Model

Timing Diagrams

Pipeline Diagrams

Roadmap

Coding Standards

Contributing Guide

Decision Log (ADR)

===========================================================================
PROJECT STRUCTURE
===========================================================================

docs/
adr/
architecture/
rtl/
rtl/fpu/
rtl/cpu/
rtl/scheduler/
rtl/heap/
rtl/gc/
rtl/messages/
rtl/primitives/
rtl/bus/
rtl/peripherals/
firmware/
frontend/
frontend/scheme/
frontend/racket/
frontend/common-lisp/
frontend/ocaml/
frontend/haskell/
ir/
simulation/
verification/
scripts/
tools/
examples/
benchmarks/
ci/

===========================================================================
IMPLEMENTATION STRATEGY
===========================================================================

Phase 0

Repository

Documentation

Architecture

CI

Simulation

Phase 1

Wishbone

UART

RV32IM

Memory

Phase 2

Message system

FIFO

Dispatcher

Phase 3

Lucid IR

Graph builder

Graph executor

Phase 4

Primitive execution

Phase 5

Heap

Closures

Environment

Phase 6

Scheme frontend

Reader

Parser

Compiler to Lucid IR

REPL

Phase 7

Scheduler

Parallel graph execution

Phase 8

Garbage Collector

Phase 9

Hardware optimization

Phase 10

Racket frontend

Future

OCaml

Haskell

===========================================================================
INSPIRATION
===========================================================================

Study the ideas behind

MIT CADR

Symbolics

TI Explorer

SECD Machine

CEK Machine

Krivine Machine

Spineless Tagless G-machine (STG)

LLVM

MLIR

SSA

Sea-of-Nodes IR

Graph reduction

Google TPU

Graphcore IPU

RISC-V Rocket

Modern heterogeneous SoCs

Never copy implementations.

Extract architectural principles.

===========================================================================
WORKFLOW
===========================================================================

Claude Code should behave as an engineering team.

Before each implementation phase:

1. Write the design document.
2. Identify trade-offs.
3. Produce interface specifications.
4. Produce verification plan.
5. Produce implementation plan.
6. Implement.
7. Simulate.
8. Review.
9. Refactor.
10. Document.

Never skip directly to coding.

Architecture quality is more important than implementation speed.

===========================================================================
FINAL OBJECTIVE
===========================================================================

Lucid should become a reusable open hardware platform for functional computing.

The Tang Nano 20K is the first implementation target, not the architectural limit.

Design Lucid so it can eventually scale to larger FPGAs and ASIC implementations without requiring major architectural changes.

Every decision should move the project toward becoming the reference open architecture for hardware execution of functional languages.