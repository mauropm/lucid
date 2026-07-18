# ADR-002: Message Passing Between FPU Modules

**Status:** Accepted
**Date:** 2026-07-17

## Context

The Lucid FPU contains multiple specialized execution units (scheduler, primitive arithmetic, heap controller, GC engine, etc.). These units must communicate to coordinate graph execution, allocation, and garbage collection.

Traditional approaches include:
- Shared bus with address decoding
- Register-based interfaces
- Direct memory access
- Shared state with mutex

## Decision

All FPU modules communicate exclusively through FIFO-based message passing.

Each module has:
- One input FIFO (receiving messages)
- One output FIFO (sending messages)
- Status registers readable via Wishbone

The message dispatcher routes messages between modules based on a routing table.

## Consequences

**Benefits:**
- Complete decoupling: modules can be developed, tested, and replaced independently
- FIFO interfaces are simple to verify (push/pop handshake)
- No shared state means no mutexes or bus arbitration within the FPU
- Natural backpressure through FIFO full/empty signals
- Easy to add new execution units

**Risks:**
- Message serialization/deserialization adds latency
- FIFO depth must be carefully sized to avoid deadlock
- Broadcast messages require careful ordering semantics

## Alternatives Considered

1. **Shared Wishbone bus within FPU:** Rejected because it creates a single point of contention and couples all modules to the bus protocol.

2. **Register-based interfaces (MMIO):** Rejected because it requires the scheduler to poll or use interrupts, adding complexity.

3. **Direct module-to-module wiring:** Rejected because it creates tightly coupled modules that cannot be independently modified.
