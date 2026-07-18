#!/usr/bin/env python3
"""
Scheme to Lucid IR Compiler
Compiles parsed Scheme AST into Lucid IR graph nodes.

Node format:
  Each node is a dict with:
    id: int
    opcode: str (LIT_INT, LIT_BOOL, ADD, SUB, MUL, etc.)
    imm0: int (for literals)
    imm1: int
    inputs: list of node IDs that this node depends on
    dependents: list of node IDs that depend on this node
    num_inputs: int
"""


class CompilerError(Exception):
    pass


# Opcode mappings
PRIMITIVE_OPS = {
    '+': 'ADD',
    '-': 'SUB',
    '*': 'MUL',
    '/': 'DIV',
    '<': 'LT',
    '>': 'GT',
    '=': 'EQ',
    '<=': 'LE',
    '>=': 'GE',
}


class IRCompiler:
    """Compiles Scheme AST to Lucid IR nodes."""

    def __init__(self):
        self.nodes = []
        self.next_id = 0
        self.env_stack = [{}]  # stack of environments (var → node_id)

    def new_node(self, opcode, imm0=0, imm1=0, num_inputs=0):
        node_id = self.next_id
        self.next_id += 1
        node = {
            'id': node_id,
            'opcode': opcode,
            'imm0': imm0,
            'imm1': imm1,
            'inputs': [],
            'dependents': [],
            'num_inputs': num_inputs,
        }
        self.nodes.append(node)
        return node_id

    def add_dependency(self, from_id, to_id):
        """Add edge: from_id → to_id (to_id depends on from_id)."""
        self.nodes[to_id]['inputs'].append(from_id)
        self.nodes[to_id]['num_inputs'] += 1
        self.nodes[from_id]['dependents'].append(to_id)

    def current_env(self):
        return self.env_stack[-1]

    def compile(self, expr):
        """Compile an expression to a node ID (returns root node ID)."""

        # Boolean literal (must check before int since bool is subclass of int)
        if isinstance(expr, bool):
            nid = self.new_node('LIT_BOOL', imm0=1 if expr else 0)
            return nid

        # Integer literal
        if isinstance(expr, int):
            nid = self.new_node('LIT_INT', imm0=expr)
            return nid

        # Symbol: variable reference
        if isinstance(expr, str):
            # Check current environment
            for env in reversed(self.env_stack):
                if expr in env:
                    return env[expr]
            raise CompilerError(f"Unbound variable: {expr}")

        # List: application or special form
        if isinstance(expr, list):
            if not expr:
                raise CompilerError("Empty application")

            head = expr[0]

            # Special forms
            if head == 'quote':
                return self._compile_quote(expr[1])

            if head == 'if':
                return self._compile_if(expr[1], expr[2], expr[3])

            if head == 'lambda':
                return self._compile_lambda(expr[1], expr[2])

            if head == 'define':
                return self._compile_define(expr[1], expr[2])

            if head == 'let':
                return self._compile_let(expr[1], expr[2])

            # Primitive application: (+ a b) or (* a b c)
            if head in PRIMITIVE_OPS:
                return self._compile_primitive(head, expr[1:])

            # General application: (f x)
            return self._compile_apply(head, expr[1:])

        raise CompilerError(f"Unsupported expression: {expr}")

    def _compile_primitive(self, op, args):
        """Compile a primitive operation like (+ a b)."""
        opcode = PRIMITIVE_OPS[op]
        # Compile arguments
        arg_ids = [self.compile(arg) for arg in args]
        # Create the operation node
        nid = self.new_node(opcode, num_inputs=len(arg_ids))
        for aid in arg_ids:
            self.add_dependency(aid, nid)
        return nid

    def _compile_if(self, cond, then_expr, else_expr):
        """Compile (if cond then else)."""
        cond_id = self.compile(cond)
        then_id = self.compile(then_expr)
        else_id = self.compile(else_expr)
        nid = self.new_node('IF', num_inputs=3)
        self.add_dependency(cond_id, nid)
        self.add_dependency(then_id, nid)
        self.add_dependency(else_id, nid)
        return nid

    def _compile_lambda(self, params, body):
        """Compile (lambda (params) body)."""
        # Create new environment scope
        self.env_stack.append(dict(self.env_stack[-1]))
        env_size = len(params)

        # Bind parameters to placeholder nodes
        param_ids = []
        for p in params:
            # LOOKUP node for parameter
            nid = self.new_node('LOOKUP', imm0=ord(p[0]) if isinstance(p, str) else 0)
            self.current_env()[p] = nid
            param_ids.append(nid)

        # Compile body
        body_id = self.compile(body)

        self.env_stack.pop()

        # Create LAMBDA node
        nid = self.new_node('LAMBDA', imm0=env_size, imm1=body_id)
        return nid

    def _compile_define(self, name, value):
        """Compile (define name value)."""
        val_id = self.compile(value)
        self.current_env()[name] = val_id
        return val_id

    def _compile_let(self, bindings, body):
        """Compile (let ((var val) ...) body)."""
        self.env_stack.append(dict(self.env_stack[-1]))
        for binding in bindings:
            var, val_expr = binding
            val_id = self.compile(val_expr)
            self.current_env()[var] = val_id
        body_id = self.compile(body)
        self.env_stack.pop()
        return body_id

    def _compile_quote(self, expr):
        """Compile (quote expr) — returns a literal."""
        if isinstance(expr, list):
            # Represent lists as pairs (simplified: use LIT_INT)
            return self.new_node('LIT_INT', imm0=0)
        return self.compile(expr)

    def _compile_apply(self, func, args):
        """Compile (f x)."""
        func_id = self.compile(func)
        arg_ids = [self.compile(arg) for arg in args]
        nid = self.new_node('APPLY', num_inputs=1 + len(arg_ids))
        self.add_dependency(func_id, nid)
        for aid in arg_ids:
            self.add_dependency(aid, nid)
        return nid

    def get_graph(self, root_id):
        """Return the compiled graph with metadata."""
        return {
            'nodes': self.nodes,
            'root': root_id,
            'count': len(self.nodes),
        }

    def encode_node(self, node_id):
        """Encode a node's header word."""
        node = self.nodes[node_id]
        # Header: {STATE(2), OPCODE(8), NUM_INPUTS(6), READY_INPUTS(6), FLAGS(10)}
        opcode_map = {
            'LIT_INT': 0x01,
            'LIT_BOOL': 0x02,
            'ADD': 0x10,
            'SUB': 0x11,
            'MUL': 0x12,
            'DIV': 0x13,
            'LT': 0x16,
            'GT': 0x17,
            'EQ': 0x15,
            'LE': 0x18,
            'GE': 0x19,
            'IF': 0x30,
            'LAMBDA': 0x20,
            'APPLY': 0x21,
            'LOOKUP': 0x23,
        }
        opcode = opcode_map.get(node['opcode'], 0x00)
        # STATE=0 (idle), READY_INPUTS=0
        return (0 << 30) | (opcode << 22) | (node['num_inputs'] << 16) | (0 << 10) | (0 << 0)

    def encode_dep_mask(self, node_id):
        """Encode dependents bitmask for a node."""
        node = self.nodes[node_id]
        mask = 0
        for dep_id in node['dependents']:
            mask |= (1 << dep_id)
        return mask


def compile_scheme(source_code):
    """Compile Scheme source code to Lucid IR graph data.
    Returns list of (addr, data) writes for graph memory."""
    from frontend.scheme.reader import read
    exprs = read(source_code)

    compiler = IRCompiler()
    root_id = None
    for expr in exprs:
        root_id = compiler.compile(expr)

    graph = compiler.get_graph(root_id)

    # Generate register write data
    writes = []
    for node in graph['nodes']:
        nid = node['id']
        # Field 0: header (state, opcode, num_inputs, ready_inputs, flags)
        writes.append((nid, 0, compiler.encode_node(nid)))
        # Field 1: imm0
        writes.append((nid, 1, node['imm0']))
        # Field 2: imm1
        writes.append((nid, 2, node['imm1']))
        # Field 3: result (0 initially)
        writes.append((nid, 3, 0))
        # Field 4: dep_mask
        writes.append((nid, 4, compiler.encode_dep_mask(nid)))

    return {
        'writes': writes,
        'node_count': len(graph['nodes']),
        'root_id': root_id,
    }


if __name__ == '__main__':
    import sys
    from frontend.scheme.reader import read, expr_str

    source = sys.stdin.read()
    exprs = read(source)

    compiler = IRCompiler()
    root_id = None
    for expr in exprs:
        print(f"; Compiling: {expr_str(expr)}")
        root_id = compiler.compile(expr)

    graph = compiler.get_graph(root_id)
    print(f"; Root node: {root_id}")
    print(f"; Node count: {len(graph['nodes'])}")
    print()
    for node in graph['nodes']:
        deps = ','.join(str(d) for d in node['dependents']) if node['dependents'] else '-'
        inputs = ','.join(str(d) for d in node['inputs']) if node['inputs'] else '-'
        print(f"  Node {node['id']}: {node['opcode']:8s} imm0={node['imm0']:4d}  "
              f"inputs=[{inputs}]  deps=[{deps}]")
