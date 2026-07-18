#!/usr/bin/env python3
"""
Common Lisp Frontend: reader, parser, and compiler to Lucid IR.
Supports defun, defparameter, lambda, if, cond, let, let*, flet,
labels, car, cdr, cons, list, and standard operators.
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from frontend.scheme.compiler import IRCompiler, CompilerError
from frontend.scheme.reader import Symbol, read
from frontend.scheme.reader import expr_str as reader_expr_str
expr_str = reader_expr_str


# CL special forms
CL_FORMS = {
    'defun', 'defparameter', 'defvar', 'defconstant',
    'lambda', 'if', 'cond', 'when', 'unless', 'case',
    'let', 'let*', 'flet', 'labels', 'macrolet',
    'quote', 'function', 'setq', 'setf', 'progn',
    'block', 'return-from', 'tagbody', 'go',
    'and', 'or', 'not',
}

# CL operators mapped to Scheme/Lucid
CL_OPS = {
    '+': '+', '-': '-', '*': '*', '/': '/',
    '<': '<', '>': '>', '=': '=', '<=': '<=', '>=': '>=',
    'car': 'car', 'cdr': 'cdr', 'cons': 'cons', 'list': 'list',
    '1+': '1+', '1-': '1-',
}


def read_cl(source):
    """Parse Common Lisp source. CL is s-expression based."""
    return read(source)


def compile_cl(source_code):
    """Compile Common Lisp source to Lucid IR.
    Uses the shared IRCompiler from the Scheme frontend,
    with CL-specific preprocessing."""
    from frontend.scheme.compiler import compile_scheme

    # Preprocess CL syntax:
    # 1. defun → define
    # 2. defparameter → define
    # 3. progn → begin
    # 4. cond → nested if

    exprs = read_cl(source_code)

    def preprocess(expr):
        """Convert CL-specific forms to Scheme-compatible forms."""
        if isinstance(expr, list) and len(expr) > 0:
            head = expr[0]

            # defun name (args) body → (define (name args) body)
            if head == 'defun' and len(expr) >= 3:
                name = expr[1]
                args = expr[2]
                body = expr[3] if len(expr) > 3 else ['quote', None]
                return preprocess(['define', [name] + args, body])

            # defparameter name val → (define name val)
            if head in ('defparameter', 'defvar', 'defconstant') and len(expr) >= 3:
                return preprocess(['define', expr[1], expr[2]])

            # progn → begin
            if head == 'progn':
                return ['begin'] + [preprocess(e) for e in expr[1:]]

            # cond → nested if
            if head == 'cond':
                result = None
                for clause in reversed(expr[1:]):
                    if len(clause) == 2:
                        test, body = clause
                        if test == 't' or test == 'else':
                            result = preprocess(body)
                        else:
                            result = ['if', preprocess(test), preprocess(body), result]
                    elif len(clause) == 1 and clause[0] == 't' or clause[0] == 'else':
                        pass  # default
                return result if result else [Symbol('quote'), None]

            # when → if
            if head == 'when' and len(expr) >= 3:
                return ['if', preprocess(expr[1]), preprocess(['begin'] + expr[2:]), [Symbol('quote'), None]]

            # unless → if (not ...)
            if head == 'unless' and len(expr) >= 3:
                return ['if', ['not', preprocess(expr[1])], preprocess(['begin'] + expr[2:]), [Symbol('quote'), None]]

            # 1+ x → (+ x 1), 1- x → (- x 1)
            if head == '1+':
                return ['+', preprocess(expr[1]), 1]
            if head == '1-':
                return ['-', preprocess(expr[1]), 1]

            # Recurse into subexpressions
            return [preprocess(e) if i > 0 else e for i, e in enumerate(expr)]

        return expr

    # Preprocess and then compile as Scheme
    processed = [preprocess(e) for e in exprs]
    source_lines = [expr_str(e) for e in processed]
    scheme_source = '\n'.join(source_lines)

    return compile_scheme(scheme_source)


def cl_to_ir(source_code):
    """High-level compile function returning IR graph data."""
    return compile_cl(source_code)


if __name__ == '__main__':
    source = sys.stdin.read()
    result = compile_cl(source)
    print(f"Root node: {result['root_id']}")
    print(f"Nodes: {result['node_count']}")
