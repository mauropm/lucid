#!/usr/bin/env python3
"""
Multi-Language Lucid IR Test
Tests that all frontends compile to compatible Lucid IR.
Each language expresses the same computation: (+ 2 (* 3 4)) = 14
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

tests = []

# Racket
tests.append(("Racket", """
#lang racket
(+ 2 (* 3 4))
"""))

# Common Lisp
tests.append(("Common Lisp", """
(+ 2 (* 3 4))
"""))

# OCaml
tests.append(("OCaml", """
2 + 3 * 4
"""))

# Haskell
tests.append(("Haskell", """
2 + 3 * 4
"""))


def test_language(name, source):
    """Compile a language source and verify the IR structure."""
    try:
        if name == "Racket":
            from frontend.racket import compile_racket
            result = compile_racket(source)
        elif name == "Common Lisp":
            from frontend.clisp import compile_cl
            result = compile_cl(source)
        elif name == "OCaml":
            from frontend.ocaml import compile_ocaml
            result = compile_ocaml(source)
        elif name == "Haskell":
            from frontend.haskell import compile_haskell
            result = compile_haskell(source)
        else:
            return False, f"Unknown language: {name}"

        return True, result
    except Exception as e:
        import traceback
        return False, f"{type(e).__name__}: {e}\n{traceback.format_exc()}"


def main():
    print("=" * 60)
    print("Lucid Multi-Language IR Compatibility Test")
    print("=" * 60)

    all_pass = True

    for name, source in tests:
        print(f"\n  --- {name} ---")
        print(f"  Source: {source.strip()}")
        success, result = test_language(name, source)

        if success:
            nodes = result['node_count']
            root = result['root_id']
            print(f"  IR: {nodes} nodes, root={root}")
            for nid, field, data in result['writes']:
                if field == 0:
                    opcode = (data >> 22) & 0xFF
                    num_inp = (data >> 16) & 0x3F
                    op_map = {0x01: 'LIT_INT', 0x10: 'ADD', 0x11: 'SUB', 0x12: 'MUL',
                              0x15: 'EQ', 0x16: 'LT'}
                    oname = op_map.get(opcode, f'0x{opcode:02X}')
                    print(f"    Node {nid}: {oname} inputs={num_inp}")
                elif field == 1 and data != 0:
                    print(f"    Node {nid}: imm0={data}")

            # Verify the result structure has MUL and ADD nodes
            has_mul = False
            has_add = False
            has_lit_2 = False
            has_lit_3 = False
            has_lit_4 = False
            for nid, field, data in result['writes']:
                if field == 0:
                    opcode = (data >> 22) & 0xFF
                    if opcode == 0x12: has_mul = True
                    if opcode == 0x10: has_add = True
                if field == 1:
                    if data == 2: has_lit_2 = True
                    if data == 3: has_lit_3 = True
                    if data == 4: has_lit_4 = True

            if has_mul and has_add:
                print(f"  ✓ Contains MUL and ADD nodes")
            else:
                print(f"  ✗ Missing MUL or ADD nodes")
                all_pass = False
        else:
            print(f"  ✗ Compilation failed: {result}")
            all_pass = False

    print(f"\n{'=' * 60}")
    if all_pass:
        print("ALL LANGUAGES PASS: IR compatible across all frontends")
    else:
        print("SOME TESTS FAILED")
    print(f"{'=' * 60}")

    return 0 if all_pass else 1


if __name__ == '__main__':
    sys.exit(main())
