#!/usr/bin/env python3
"""
OCaml Frontend: parser and compiler to Lucid IR.
Supports let, let rec, fun, if-then-else, match, list operations,
and standard arithmetic.
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from frontend.scheme.compiler import IRCompiler, CompilerError
from frontend.scheme.reader import Symbol


class OCamLTokenizer:
    """Simple OCaml tokenizer."""

    def __init__(self, source):
        self.source = source
        self.pos = 0
        self.tokens = []
        self._tokenize()

    def _tokenize(self):
        s = self.source
        i = 0
        while i < len(s):
            c = s[i]
            if c in ' \t\n\r':
                i += 1
                continue
            if c == '(':
                self.tokens.append(('LPAREN', '(')); i += 1; continue
            if c == ')':
                self.tokens.append(('RPAREN', ')')); i += 1; continue
            if c == '[':
                self.tokens.append(('LBRACK', '[')); i += 1; continue
            if c == ']':
                self.tokens.append(('RBRACK', ']')); i += 1; continue
            if c == ';':
                self.tokens.append(('SEMI', ';')); i += 1; continue
            if c == '|':
                self.tokens.append(('PIPE', '|')); i += 1; continue
            if c == ',':
                self.tokens.append(('COMMA', ',')); i += 1; continue
            if c == '=' and i+1 < len(s) and s[i+1] == '>':
                self.tokens.append(('ARROW', '=>')); i += 2; continue
            if c == '=':
                self.tokens.append(('EQ', '=')); i += 1; continue
            if c == '_':
                self.tokens.append(('WILDCARD', '_')); i += 1; continue
            if c == '\'':
                start = i; i += 1
                while i < len(s) and s[i].isalpha():
                    i += 1
                self.tokens.append(('QUOTED', s[start:i])); continue
            if c == '"':
                i += 1; start = i
                while i < len(s) and s[i] != '"':
                    i += 1
                self.tokens.append(('STRING', s[start:i])); i += 1; continue
            if c.isdigit() or (c == '-' and i+1 < len(s) and s[i+1].isdigit()):
                start = i; i += 1
                while i < len(s) and s[i].isdigit():
                    i += 1
                self.tokens.append(('INT', int(s[start:i]))); continue
            if c.isalpha() or c in '_':
                start = i
                while i < len(s) and (s[i].isalnum() or s[i] in "_-'"):
                    i += 1
                word = s[start:i]
                if word in ('let', 'rec', 'in', 'fun', 'if', 'then', 'else',
                            'match', 'with', 'true', 'false', 'mod'):
                    self.tokens.append((word.upper(), word))
                else:
                    self.tokens.append(('IDENT', word))
                continue
            # Operators
            for op in ['::', '++', '->', '<-', '>=', '<=', '<>', '::']:
                if s[i:i+len(op)] == op:
                    self.tokens.append(('OP', op))
                    i += len(op)
                    break
            else:
                if c in '+-*/<>!@$%^&~':
                    self.tokens.append(('OP', c)); i += 1; continue
                raise SyntaxError(f"Unexpected: {c!r} at pos {i}")
        self.tokens.append(('EOF', None))


def make_binop(left, op, right):
    op_map = {'+': '+', '-': '-', '*': '*', '/': '/', '<': '<', '>': '>',
              '=': '=', '<=': '<=', '>=': '>=', 'mod': 'mod', '::': 'cons'}
    mapped = op_map.get(op, op)
    return [Symbol(mapped), left, right]


def parse_ocaml(source):
    """Parse OCaml source into a normalized AST (Scheme-like lists)."""

    tokens = OCamLTokenizer(source).tokens
    pos = [0]

    def peek():
        return tokens[pos[0]] if pos[0] < len(tokens) else ('EOF', None)

    def consume(expected=None):
        tok = peek()
        if expected and tok[1] != expected:
            raise SyntaxError(f"Expected {expected}, got {tok}")
        pos[0] += 1
        return tok

    def parse_expr():
        tok = peek()
        ttype, tval = tok

        # Integer literal
        if ttype == 'INT':
            consume()
            # Check for following infix operator
            if peek()[0] == 'OP':
                op = consume()[1]
                right = parse_expr()
                return make_binop(tval, op, right)
            return tval

        # Boolean
        if tval in ('true', 'false'):
            consume()
            return tval == 'true'

        # After parsing a primary expression, check for infix operators

        # Parenthesized expression
            consume('(')
            if peek()[1] == ')':
                consume(')')
                return [Symbol('quote'), None]  # ()
            expr = parse_expr()
            # Check for tuple or semicolons
            if peek()[1] == ',':
                consume(',')
                rest = parse_expr()
                consume(')')
                return [Symbol('list'), expr, rest]  # simplified
            consume(')')
            return expr

        # List literal [1;2;3]
        if tval == '[':
            consume('[')
            items = []
            while peek()[1] != ']':
                items.append(parse_expr())
                if peek()[1] == ';':
                    consume(';')
            consume(']')
            if not items:
                return [Symbol('quote'), None]
            result = items[-1]
            for item in reversed(items[:-1]):
                result = [Symbol('cons'), item, result]
            return result

        # Identifier or keyword
        if ttype == 'IDENT':
            word = tval
            consume()

            # let ... = ... in ...
            if word == 'let':
                rec = False
                if peek()[1] == 'rec':
                    consume('rec')
                    rec = True
                name = parse_expr()  # should be IDENT
                args = []
                while peek()[1] not in ('=', 'in'):
                    args.append(parse_expr())
                if args:
                    # let f x y = body → (define (f x y) body)
                    consume('=')
                    body = parse_expr()
                    consume('in')
                    rest = parse_expr()
                    return ['let', [[name] + args, body], rest]
                else:
                    consume('=')
                    val = parse_expr()
                    consume('in')
                    rest = parse_expr()
                    return ['let', [[name, val]], rest]

            # fun x -> body
            if word == 'fun':
                params = []
                while peek()[1] != '->':
                    params.append(parse_expr())
                consume('->')
                body = parse_expr()
                result = body
                for p in reversed(params):
                    result = [Symbol('lambda'), [p], result]
                return result

            # if ... then ... else ...
            if word == 'if':
                cond = parse_expr()
                consume('then')
                then_expr = parse_expr()
                if peek()[1] == 'else':
                    consume('else')
                    else_expr = parse_expr()
                else:
                    else_expr = [Symbol('quote'), None]
                return ['if', cond, then_expr, else_expr]

            # match ... with ...
            if word == 'match':
                expr = parse_expr()
                consume('with')
                patterns = []
                while peek()[1] != ';' and peek()[0] != 'EOF':
                    pat = parse_expr()
                    if peek()[1] == '->':
                        consume('->')
                        body = parse_expr()
                        patterns.append([pat, body])
                    elif peek()[1] == ';':
                        break
                return ['match', expr] + patterns

            # Function application: f x or x + y
            # Check for infix operator
            if peek()[0] == 'OP':
                op = consume()[1]
                right = parse_expr()
                op_map = {'+': '+', '-': '-', '*': '*', '/': '/',
                          '<': '<', '>': '>', '=': '=', '<=': '<=', '>=': '>=',
                          '::': 'cons', '++': 'append', 'mod': 'mod'}
                return [Symbol(op_map.get(op, op)), Symbol(word) if isinstance(word, str) and word.isalpha() else word, right]

            # Simple identifier or function call
            if peek()[1] == '(' or peek()[0] == 'INT' or peek()[0] == 'IDENT' or peek()[1] in ("'",):
                args = [parse_expr()]
                args.insert(0, Symbol(word))
                return args

            return Symbol(word)

        if ttype == 'QUOTED':
            word = tval
            consume()
            return Symbol(word)

        raise SyntaxError(f"Unexpected token: {tok}")

    # Parse all expressions
    exprs = []
    while pos[0] < len(tokens) - 1:  # skip EOF
        try:
            exprs.append(parse_expr())
        except SyntaxError:
            break
    return exprs


def compile_ocaml(source_code):
    """Compile OCaml source to Lucid IR."""
    from frontend.scheme.reader import expr_str
    from frontend.scheme.compiler import compile_scheme

    exprs = parse_ocaml(source_code)
    lines = [expr_str(e) for e in exprs]
    return compile_scheme('\n'.join(lines))


def ocaml_to_ir(source_code):
    return compile_ocaml(source_code)


if __name__ == '__main__':
    from frontend.scheme.reader import expr_str
    source = sys.stdin.read()
    result = compile_ocaml(source)
    print(f"Root node: {result['root_id']}")
    print(f"Nodes: {result['node_count']}")
    for nid, field, data in result['writes']:
        if field == 0:
            print(f"  Node {nid}: header=0x{data:08X}")
        elif field == 1:
            print(f"  Node {nid}: imm0={data}")
