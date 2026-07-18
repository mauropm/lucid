# Lucid Phase 10: Language Expansion

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-07-17

---

## 1. Scope

Phase 10 demonstrates the language independence of the Lucid architecture by adding frontends for multiple functional languages. It delivers:
- A Racket frontend (reader, parser, compiler to Lucid IR)
- A Common Lisp frontend (reader, parser, compiler to Lucid IR)
- An OCaml-like frontend (parser, compiler to Lucid IR)
- A Haskell-like frontend (parser, compiler to Lucid IR)
- A multi-language test suite verifying IR compatibility

---

## 2. Architecture

```
Racket Source   CL Source    OCaml Source  Haskell Source
      │             │             │             │
      ▼             ▼             ▼             ▼
 Racket Reader  CL Reader    OCaml Parser  Haskell Parser
      │             │             │             │
      └─────────────┼─────────────┼─────────────┘
                    │             │
                    ▼             ▼
              Normalized AST
                    │
                    ▼
            Lucid IR Compiler
            (shared backend)
                    │
                    ▼
            Lucid IR Graph
            (hardware execution)
```

### 2.1 Shared Compiler Backend

All frontends use the same `IRCompiler` class from Phase 6. Each frontend:
1. Parses its source language into a Python-native AST (lists, ints, bools, strings, symbols)
2. Calls `IRCompiler.compile(ast)` which returns a node ID
3. The compiler generates Lucid IR nodes with proper dependency tracking

---

## 3. Language Support

### 3.1 Racket

Racket is a Scheme dialect with additional features. The Racket frontend supports:
- `#lang racket` header
- `define`, `lambda`, `if`, `let`, `let*`, `letrec`
- `+`, `-`, `*`, `/`, `<`, `>`, `=`, `<=`, `>=`
- `cons`, `car`, `cdr`, `list`, `vector`
- `quote`, `quasiquote`, `unquote`
- First-class functions and closures

### 3.2 Common Lisp

The Common Lisp frontend supports:
- `defun`, `defparameter`, `defvar`
- `lambda`, `if`, `cond`, `when`, `unless`, `case`
- `let`, `let*`, `flet`, `labels`
- `car`, `cdr`, `cons`, `list`, `append`
- `+`, `-`, `*`, `/`, `<`, `>`, `=`
- `quote`, `'`, `` ` ``, `,`, `,@`

### 3.3 OCaml (ML Family)

The OCaml-like frontend supports:
- `let` bindings, `let rec`
- `fun` → lambda, function application
- `if-then-else`
- Pattern matching (`match-with`)
- Arithmetic and comparison operators
- List operations (`::`, `@`)
- Type annotations (ignored)

### 3.4 Haskell

The Haskell-like frontend supports:
- Function definitions with pattern matching
- `let` and `where` clauses
- `if-then-else` (expression)
- Infix operators
- List syntax `[1,2,3]`
- Lambda expressions `\x -> body`
- `case` expressions
- `do` notation (simplified)

---

## 4. Verification Plan

| Test | Description |
|------|-------------|
| Racket `(+ 2 (* 3 4))` | Same expression as Scheme, same IR output |
| CL `(* (+ 2 3) 4)` | Different syntax, same IR |
| OCaml `let x = 2 + 3 in x * 4` | ML-style, same IR |
| Haskell `(\x -> x + 1) 5` | Lambda application, same IR |
| Cross-language | Different sources, same IR structure |
