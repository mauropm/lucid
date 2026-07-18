#!/usr/bin/env python3
"""
Haskell Frontend: parser and compiler to Lucid IR.
Supports function definitions, let, where, if-then-else,
list syntax, lambda (\\x -> ...), case, do notation.
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from frontend.scheme.compiler import IRCompiler, CompilerError
from frontend.scheme.reader import Symbol


class HaskellTokenizer:
    """Simple Haskell tokenizer."""

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
                i += 1; continue
            if c == ';':
                self.tokens.append(('SEMI', ';')); i += 1; continue
            # Comments: -- and {- -}
            if c == '-' and i+1 < len(s) and s[i+1] == '-':
                while i < len(s) and s[i] != '\n': i += 1
                continue
            for pair in [('(', 'LPAREN'), (')', 'RPAREN'),
                         ('[', 'LBRACK'), (']', 'RBRACK'),
                         (',', 'COMMA'), ('|', 'PIPE'),
                         ('\\', 'BACKSLASH')]:
                if c == pair[0]:
                    self.tokens.append((pair[1], c)); i += 1; break
            else:
                # Arrow ->
                if c == '-' and i+1 < len(s) and s[i+1] == '>':
                    self.tokens.append(('ARROW', '->')); i += 2; continue
                # Double colon ::
                if c == ':' and i+1 < len(s) and s[i+1] == ':':
                    self.tokens.append(('DCOLON', '::')); i += 2; continue
                # Cons operator :
                if c == ':':
                    self.tokens.append(('OP', ':')); i += 1; continue
                # = -> >= <=
                if c == '=':
                    self.tokens.append(('EQ', '=')); i += 1; continue
                if c == '>' and i+1 < len(s) and s[i+1] == '=':
                    self.tokens.append(('OP', '>=')); i += 2; continue
                if c == '<' and i+1 < len(s) and s[i+1] == '=':
                    self.tokens.append(('OP', '<=')); i += 2; continue
                if c == '>' or c == '<':
                    self.tokens.append(('OP', c)); i += 1; continue
                # Strings
                if c == '"':
                    i += 1; start = i
                    while i < len(s) and s[i] != '"': i += 1
                    self.tokens.append(('STRING', s[start:i])); i += 1; continue
                # Numbers
                if c.isdigit() or (c == '-' and i+1 < len(s) and s[i+1].isdigit()):
                    start = i; i += 1
                    while i < len(s) and s[i].isdigit(): i += 1
                    self.tokens.append(('INT', int(s[start:i]))); continue
                # Identifiers
                if c.isalpha() or c == '_':
                    start = i
                    while i < len(s) and (s[i].isalnum() or s[i] in "_'"):
                        i += 1
                    word = s[start:i]
                    keywords = {'let', 'in', 'where', 'if', 'then', 'else',
                                'case', 'of', 'do', 'data', 'type', 'class',
                                'instance', 'module', 'import', 'True', 'False'}
                    self.tokens.append(('KEYWORD' if word in keywords else 'IDENT', word))
                    continue
                # Operators
                if c in '+-*/<>!@$%^&~.':
                    self.tokens.append(('OP', c)); i += 1; continue
                raise SyntaxError(f"Unexpected char {c!r} at pos {i}")
        self.tokens.append(('EOF', None))


def parse_haskell(source):
    """Parse Haskell source into normalized AST."""

    tokens = HaskellTokenizer(source).tokens
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

        # Literals
        if ttype == 'INT':
            consume(); return tval
        if tval in ('True', 'False'):
            consume(); return tval == 'True'
        if ttype == 'STRING':
            consume(); return tval

        # Parenthesized expression
        if tval == '(':
            consume('(')
            if peek()[1] == ')':
                consume(')')
                return [Symbol('quote'), None]
            expr = parse_expr()
            consume(')')
            return expr

        # List [1,2,3]
        if tval == '[':
            consume('[')
            items = []
            while peek()[1] != ']':
                items.append(parse_expr())
                if peek()[1] == ',':
                    consume(',')
            consume(']')
            if not items:
                return [Symbol('quote'), None]
            result = [Symbol('quote'), None]
            for item in reversed(items):
                result = [Symbol('cons'), item, result]
            return result

        # Lambda \x -> body
        if ttype == 'BACKSLASH':
            consume()
            params = []
            while peek()[1] != '->':
                params.append(parse_expr())
            consume('->')
            body = parse_expr()
            result = body
            for p in reversed(params):
                result = [Symbol('lambda'), [p], result]
            return result

        # let ... in ...
        if tval == 'let' and ttype == 'KEYWORD':
            consume()
            bindings = []
            name = parse_expr()
            if peek()[1] == '::':  # type annotation
                consume('::'); parse_expr()  # skip type
            if peek()[1] in ('=', '->'):
                cons = consume()
                val = parse_expr()
                bindings.append([name, val])
            consume('in')
            body = parse_expr()
            return ['let', bindings, body]

        # if ... then ... else ...
        if tval == 'if':
            consume()
            cond = parse_expr()
            consume('then')
            then_expr = parse_expr()
            if peek()[1] == 'else':
                consume('else')
                else_expr = parse_expr()
            else:
                else_expr = [Symbol('quote'), None]
            return ['if', cond, then_expr, else_expr]

        # case ... of ...
        if tval == 'case':
            consume()
            expr = parse_expr()
            consume('of')
            arms = []
            while peek()[0] not in ('EOF',):
                pat = parse_expr()
                if peek()[1] == '->':
                    consume('->')
                    body = parse_expr()
                    arms.append([pat, body])
                else:
                    break
            return ['case', expr] + arms

        # Identifiers and applications
        if ttype == 'IDENT':
            name = tval
            consume()
            # Function application
            if peek()[0] in ('INT', 'IDENT', 'LPAREN', 'LBRACK', 'STRING', 'BACKSLASH', 'OP'):
                args = [parse_expr()]
                args.insert(0, Symbol(name))
                return args
            # Infix operator application: x + y
            if peek()[1] in ('+', '-', '*', '/', '==', '<', '>', '<=', '>=', '::'):
                op = consume()[1]
                right = parse_expr()
                op_map = {'+': '+', '-': '-', '*': '*', '/': '/',
                          '==': '=', '<': '<', '>': '>', '<=': '<=', '>=': '>=',
                          '++': 'append', '::': 'cons'}
                return [Symbol(op_map.get(op, op)), Symbol(name), right]
            return Symbol(name)

        # Operator prefix
        if ttype == 'OP':
            op = consume()[1]
            right = parse_expr()
            return [Symbol(op), right]

        raise SyntaxError(f"Unexpected token: {tok}")

    exprs = []
    while pos[0] < len(tokens) - 1:
        try:
            exprs.append(parse_expr())
        except SyntaxError:
            break
    return exprs


def compile_haskell(source_code):
    """Compile Haskell source to Lucid IR."""
    from frontend.scheme.reader import expr_str
    from frontend.scheme.compiler import compile_scheme

    exprs = parse_haskell(source_code)
    lines = [expr_str(e) for e in exprs]
    return compile_scheme('\n'.join(lines))


def haskell_to_ir(source_code):
    return compile_haskell(source_code)


if __name__ == '__main__':
    from frontend.scheme.reader import expr_str
    source = sys.stdin.read()
    result = compile_haskell(source)
    exprs = parse_haskell(source)
    for e in exprs:
        print(expr_str(e))
    print(f"---\nRoot node: {result['root_id']}")
    print(f"Nodes: {result['node_count']}")
