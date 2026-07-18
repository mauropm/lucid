# Contributing to Lucid

## Welcome

Thank you for your interest in Lucid — an open hardware Functional Processing Unit.

This project is in its early stages. Every contribution, whether documentation, RTL, verification, or tooling, helps build the foundation for functional computing hardware.

## Code of Conduct

Be respectful, constructive, and professional. Disagreements are expected in architectural discussions; keep them technical and focused on the problem.

## Getting Started

1. Read the [Architecture Guide](docs/architecture/architecture-guide.md)
2. Read the [Developer Guide](docs/architecture/developer-guide.md)
3. Set up your development environment
4. Look for issues tagged `good-first-issue` or `help-wanted`

## How to Contribute

### Reporting Bugs

- Check existing issues first
- Include the module name, simulation tool, and error message
- Provide a minimal reproduction if possible

### Suggesting Features

- Open an issue describing the feature
- Explain why it belongs in the architecture (not just software)
- Reference any relevant architecture documents

### Documentation

- Fix typos, clarify explanations, add missing details
- Add ADRs for architectural decisions
- Improve timing and pipeline diagrams

### RTL

1. Read the relevant architecture document
2. Check for existing discussion on the approach
3. Write the specification first (if it doesn't exist)
4. Implement the RTL
5. Write or update testbenches
6. Run simulation and verify
7. Submit a pull request

### Verification

- Add test cases for edge conditions
- Add assertions to RTL for invariants
- Improve coverage of existing testbenches
- Write randomized test generators

### Frontends

- Start with the Lucid IR specification
- Understand the graph execution model
- Compile the source language to Lucid IR nodes

## Pull Request Process

1. Fork the repository
2. Create a branch: `type/description` (e.g., `feat/graph-scheduler`, `fix/heap-alignment`)
3. Make your changes
4. Run `make lint` and `make sim` to verify
5. Submit a pull request with a clear description
6. Respond to review feedback

### PR Checklist

- [ ] Code follows coding standards
- [ ] Documentation updated
- [ ] Testbenches added or updated
- [ ] Simulation passes
- [ ] No lint warnings

## Development Philosophy

- Architecture before RTL
- Documentation before code
- Verification before optimization
- Simplicity over complexity
- Correctness over speed

## Questions?

Open a discussion on GitHub or refer to the documentation in `docs/architecture/`.
