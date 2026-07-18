#!/usr/bin/env python3
"""
Lucid IR Graph Example Generator
Generates example Lucid IR graphs for testing and documentation.

Usage:
    python3 tools/graph_examples.py
"""

def example_add_mul():
    """(+ 2 (* 3 4))"""
    return """\
# (+ 2 (* 3 4))
0 LIT_INT imm=2
1 LIT_INT imm=3
2 LIT_INT imm=4
3 MUL input=1,2
4 ADD input=0,3
"""


def example_lambda():
    """(lambda (x) (+ x 1))"""
    return """\
# (lambda (x) (+ x 1))
0 LAMBDA params=x body=3
1 LOOKUP name=x
2 LIT_INT imm=1
3 ADD input=1,2
"""


def example_let():
    """(let ((x 5) (y 10)) (+ x y))"""
    return """\
# (let ((x 5) (y 10)) (+ x y))
0 LIT_INT imm=5
1 LIT_INT imm=10
2 LET bindings=0,1 body=3
3 ADD input=0,1
"""


def example_if():
    """(if (> x 0) x (- x))"""
    return """\
# (if (> x 0) x (- x))
0 LOOKUP name=x
1 LIT_INT imm=0
2 GT input=0,1
3 LOOKUP name=x
4 LOOKUP name=x
5 SUB literal=0 input=4
6 IF cond=2 then=3 else=5
"""


def example_fib():
    """(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))"""
    return """\
# (define (fib n) ...)
0 LOOKUP name=n
1 LIT_INT imm=2
2 LT input=0,1
3 LOOKUP name=n
4 LOOKUP name=n
5 LIT_INT imm=1
6 SUB input=4,5
7 APPLY func=fib arg=6
8 LOOKUP name=n
9 LIT_INT imm=2
10 SUB input=8,9
11 APPLY func=fib arg=10
12 ADD input=7,11
13 IF cond=2 then=3 else=12
"""


def main():
    examples = {
        'add_mul': example_add_mul,
        'lambda': example_lambda,
        'let': example_let,
        'if': example_if,
        'fib': example_fib,
    }

    for name, func in examples.items():
        print(f"=== {name} ===")
        print(func())
        print()


if __name__ == '__main__':
    main()
