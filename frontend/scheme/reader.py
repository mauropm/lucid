#!/usr/bin/env python3
"""
Scheme Tokenizer and S-Expression Reader
Converts Scheme source code into an AST of nested Python lists/symbols.
"""

import sys
import re


class Symbol(str):
    """A Scheme symbol (interned string)."""
    pass


class SExpr:
    """Base class for s-expressions."""
    pass


# Token types
TOKEN_OPEN = 'OPEN'      # (
TOKEN_CLOSE = 'CLOSE'    # )
TOKEN_QUOTE = 'QUOTE'    # '
TOKEN_NUMBER = 'NUMBER'  # 42
TOKEN_BOOL = 'BOOL'      # #t #f
TOKEN_SYMBOL = 'SYMBOL'  # x, define, lambda, +
TOKEN_STRING = 'STRING'  # "hello"
TOKEN_EOF = 'EOF'


def tokenize(source):
    """Tokenize Scheme source code into a list of tokens."""
    tokens = []
    i = 0
    while i < len(source):
        c = source[i]

        # Whitespace
        if c in ' \t\n\r,':
            i += 1
            continue

        # Comment (;)
        if c == ';':
            while i < len(source) and source[i] != '\n':
                i += 1
            continue

        # Parentheses
        if c == '(':
            tokens.append((TOKEN_OPEN, '('))
            i += 1
            continue
        if c == ')':
            tokens.append((TOKEN_CLOSE, ')'))
            i += 1
            continue

        # Quote
        if c == "'":
            tokens.append((TOKEN_QUOTE, "'"))
            i += 1
            continue

        # Number
        if c.isdigit() or (c == '-' and i + 1 < len(source) and source[i + 1].isdigit()):
            start = i
            if c == '-':
                i += 1
            while i < len(source) and source[i].isdigit():
                i += 1
            tokens.append((TOKEN_NUMBER, int(source[start:i])))
            continue

        # Boolean (#t, #f)
        if c == '#' and i + 1 < len(source) and source[i + 1] in 'tf':
            tokens.append((TOKEN_BOOL, source[i] == '#t'))
            i += 2
            continue

        # String
        if c == '"':
            i += 1
            start = i
            while i < len(source) and source[i] != '"':
                i += 1
            tokens.append((TOKEN_STRING, source[start:i]))
            i += 1
            continue

        # Symbol (or keyword)
        if c.isalpha() or c in '+-*/<=>!?@$%^&_~.':
            start = i
            while i < len(source) and (source[i].isalnum() or source[i] in '+-*/<=>!?@$%^&_~.'):
                i += 1
            tokens.append((TOKEN_SYMBOL, Symbol(source[start:i])))
            continue

        raise SyntaxError(f"Unexpected character: {c!r} at position {i}")

    tokens.append((TOKEN_EOF, None))
    return tokens


def parse(tokens, pos=0):
    """Parse tokens into an s-expression AST.
    Returns (ast, new_pos)."""

    if pos >= len(tokens):
        raise SyntaxError("Unexpected end of input")

    tok_type, tok_val = tokens[pos]

    if tok_type == TOKEN_OPEN:
        # List: (item1 item2 ...)
        items = []
        pos += 1
        while pos < len(tokens) and tokens[pos][0] != TOKEN_CLOSE:
            item, pos = parse(tokens, pos)
            items.append(item)
        if pos >= len(tokens) or tokens[pos][0] != TOKEN_CLOSE:
            raise SyntaxError("Unclosed parenthesis")
        return items, pos + 1

    elif tok_type == TOKEN_CLOSE:
        raise SyntaxError("Unexpected ')'")

    elif tok_type == TOKEN_QUOTE:
        # Quote: 'expr → (quote expr)
        expr, pos = parse(tokens, pos + 1)
        return [Symbol('quote'), expr], pos

    elif tok_type == TOKEN_NUMBER:
        return tok_val, pos + 1

    elif tok_type == TOKEN_BOOL:
        return tok_val, pos + 1

    elif tok_type == TOKEN_SYMBOL:
        return tok_val, pos + 1

    elif tok_type == TOKEN_STRING:
        return tok_val, pos + 1

    elif tok_type == TOKEN_EOF:
        raise SyntaxError("Unexpected end of input")

    return None, pos + 1


def parse_all(tokens):
    """Parse all s-expressions in the token stream."""
    results = []
    pos = 0
    while pos < len(tokens) and tokens[pos][0] != TOKEN_EOF:
        expr, pos = parse(tokens, pos)
        results.append(expr)
    return results


def read(source):
    """Read Scheme source code, return list of parsed s-expressions."""
    tokens = tokenize(source)
    return parse_all(tokens)


def expr_str(expr, depth=0):
    """Convert a parsed expression back to string form."""
    indent = '  ' * depth
    if isinstance(expr, list):
        if not expr:
            return '()'
        if len(expr) <= 8:
            items = ' '.join(expr_str(e) for e in expr)
            return f'({items})'
        else:
            items = '\n'.join(expr_str(e, depth + 1) for e in expr)
            return f'(\n{items}\n{indent})'
    elif isinstance(expr, bool):
        return '#t' if expr else '#f'
    else:
        return str(expr)


if __name__ == '__main__':
    for line in sys.stdin:
        if line.strip():
            exprs = read(line)
            for e in exprs:
                print(expr_str(e))
