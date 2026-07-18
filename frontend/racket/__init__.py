#!/usr/bin/env python3
"""
Racket Frontend: reader, parser, and compiler to Lucid IR.
Supports #lang racket, define, lambda, if, let, let*, letrec,
and standard arithmetic/comparison operators.
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from frontend.scheme.compiler import IRCompiler
from frontend.scheme.reader import read as read_sexpr, Symbol, expr_str


# Racket special forms (subset of Scheme)
RACKET_FORMS = {
    'define', 'lambda', 'λ', 'if', 'cond', 'let', 'let*', 'letrec',
    'quote', 'quasiquote', 'unquote', 'set!', 'begin', 'when', 'unless',
    'case', 'and', 'or',
}


def read_racket(source):
    """Parse Racket source code using the Scheme reader.
    Racket syntax is s-expression based, same as Scheme."""
    return read_sexpr(source)


def compile_racket(source_code):
    """Compile Racket source to Lucid IR graph data."""
    from frontend.scheme.compiler import compile_scheme

    # Preprocess: remove #lang racket line if present
    lines = source_code.split('\n')
    filtered = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith('#lang'):
            continue
        filtered.append(line)
    source = '\n'.join(filtered)

    return compile_scheme(source)


def racket_to_ir(source_code):
    """High-level compile function returning IR graph data."""
    return compile_racket(source_code)


if __name__ == '__main__':
    source = sys.stdin.read()
    from frontend.scheme.compiler import compile_scheme
    result = compile_racket(source)
    print(f"Root node: {result['root_id']}")
    print(f"Nodes: {result['node_count']}")
    for nid, field, data in result['writes']:
        if field == 0:
            print(f"  Node {nid}: header=0x{data:08X}")
        elif field == 1:
            print(f"  Node {nid}: imm0={data}")
        elif field == 4:
            print(f"  Node {nid}: deps=0x{data:08X}")
