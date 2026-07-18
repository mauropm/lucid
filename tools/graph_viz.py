#!/usr/bin/env python3
"""
Lucid IR Graph Visualizer
Converts Lucid IR graph descriptions to DOT format for visualization.

Usage:
    python3 tools/graph_viz.py < input.lir > output.dot
    dot -Tpng output.dot -o graph.png
"""

import sys
import json

def parse_lir(input_text):
    """Parse a simple Lucid IR text format into nodes and edges."""
    nodes = {}
    edges = []

    for line in input_text.split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue

        parts = line.split()
        if len(parts) < 2:
            continue

        node_id = int(parts[0])
        opcode = parts[1]
        inputs = []

        # Parse inputs from remaining parts
        for p in parts[2:]:
            if p.startswith('input='):
                inputs = [int(x) for x in p[6:].split(',')]

        nodes[node_id] = {
            'opcode': opcode,
            'inputs': inputs,
            'label': f'{node_id}: {opcode}'
        }

        for inp in inputs:
            edges.append((inp, node_id))

    return nodes, edges


def generate_dot(nodes, edges, root=None):
    """Generate DOT format graph."""
    lines = ['digraph LucidIR {']
    lines.append('    rankdir=TB;')
    lines.append('    node [shape=box, style=rounded];')

    # Node definitions
    for nid, node in nodes.items():
        label = node['label']
        lines.append(f'    n{nid} [label="{label}"];')

    # Edge definitions
    for src, dst in edges:
        lines.append(f'    n{src} -> n{dst};')

    # Root node highlight
    if root is not None and root in nodes:
        lines.append(f'    n{root} [style=rounded,bold,color=red];')

    lines.append('}')
    return '\n'.join(lines)


def main():
    input_text = sys.stdin.read()
    nodes, edges = parse_lir(input_text)

    # Find root (node with no consumers)
    all_consumers = set(d for _, d in edges)
    root = None
    for nid in nodes:
        if nid not in all_consumers:
            root = nid
            break

    dot = generate_dot(nodes, edges, root)
    print(dot)


if __name__ == '__main__':
    main()
