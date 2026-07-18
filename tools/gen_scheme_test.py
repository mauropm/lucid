#!/usr/bin/env python3
"""
Generate Verilog testbench code from compiled Scheme.
Outputs register write sequences for the graph_scheduler.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from frontend.scheme.compiler import compile_scheme


def generate_verilog_writes(compiled, indent=8):
    """Generate Verilog node_write calls for a compiled graph."""
    lines = []
    prefix = ' ' * indent

    for nid, field, data in compiled['writes']:
        lines.append(f'{prefix}node_write({nid}, {field}, 32\'h{data:08X});')

    lines.append(f'{prefix}reg_write(32\'h08, 32\'d{compiled["root_id"]});  // root')
    lines.append(f'{prefix}reg_write(32\'h0C, 32\'d{compiled["node_count"]});  // node_count')

    return '\n'.join(lines)


def main():
    if len(sys.argv) < 2:
        print("Usage: python gen_test.py <scheme-expr>")
        print("Example: python gen_test.py '(+ 2 (* 3 4))'")
        sys.exit(1)

    source = sys.argv[1]
    try:
        compiled = compile_scheme(source)
        print(generate_verilog_writes(compiled))
    except Exception as e:
        print(f"// Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
