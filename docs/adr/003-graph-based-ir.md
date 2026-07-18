# ADR-003: Graph-Based Intermediate Representation

**Status:** Accepted
**Date:** 2026-07-17

## Context

The Lucid FPU needs an intermediate representation (IR) that:
- Can represent functional programs from multiple source languages
- Is directly executable by hardware
- Exposes parallelism naturally
- Supports closures, continuations, and lazy evaluation

Options considered: bytecode, AST, SSA, graph-based IR.

## Decision

Lucid IR is a graph-based intermediate representation where:
- Each node represents a unit of computation (literal, primitive, application, etc.)
- Each directed edge represents a data dependency
- The graph is a DAG (directed acyclic graph) for any single execution
- Execution order is determined by data readiness, not node position

Lucid IR is not bytecode (no sequential interpretation). It is not an AST (no tree walking). It is a dependency graph that maps directly to the scheduler's execution model.

## Consequences

**Benefits:**
- Natural parallelism: nodes with no dependencies execute concurrently
- Language neutrality: any functional language can be compiled to dependency graphs
- Hardware-friendly: the node structure maps directly to graph memory entries
- Scheduler simplicity: dependency tracking is just counting ready inputs
- Composability: graphs can be combined, inlined, and fused

**Risks:**
- Graph size: large programs may exceed on-chip graph memory (requires paging)
- Construction overhead: compiling ASTs to graphs is more work than emitting bytecode
- Tooling: debugging at the graph level requires visualization tools

## Alternatives Considered

1. **Bytecode (register-based VM):** Rejected because bytecode implies sequential interpretation, losing the natural parallelism of functional programs.

2. **AST with tree-walking:** Rejected because tree walking is inherently sequential and doesn't map well to hardware execution units.

3. **SSA form:** Considered but rejected as too close to imperative semantics. Lucid IR is SSA-inspired but adapted for functional computation with explicit closures and environments.

4. **Combinator-based (SKI, STG):** Considered as inspiration. The graph model is influenced by STG (Spineless Tagless G-machine) but adapted for hardware execution.
