import numpy as np

def fmt_mat(m):
    # m is column-major: m[:,col]
    return m

def print_mat4(name, m):
    # m is numpy matrix (row-major), convert to column-major for Zig
    print(f'    const {name} = Mat4(f32){{ .cols = [4]Vec4(f32){{')
    for col in range(4):
        print(f'        Vec4(f32){{ .x={m[0,col]:.6}, .y={m[1,col]:.6}, .z={m[2,col]:.6}, .w={m[3,col]:.6} }},')
    print(f'    }} }};')

def check_mat4(result_name, expected):
    for col in range(4):
        for row, comp in enumerate(['x','y','z','w']):
            print(f'    try std.testing.expectApproxEqAbs(@as(f32, {expected[row,col]:.6}), {result_name}.cols[{col}].{comp}, eps);')

# Test cases
cases = [
    # (A, B) as numpy matrices
    (
        np.array([[1,2,3,4],[5,6,7,8],[9,10,11,12],[13,14,15,16]], dtype=float),
        np.array([[16,15,14,13],[12,11,10,9],[8,7,6,5],[4,3,2,1]], dtype=float),
    ),
    (
        np.array([[1,0,0,1],[0,1,0,2],[0,0,1,3],[0,0,0,1]], dtype=float),  # translation
        np.array([[2,0,0,0],[0,2,0,0],[0,0,2,0],[0,0,0,1]], dtype=float),  # scale
    ),
    (
        np.eye(4),
        np.array([[1,2,0,0],[3,4,0,0],[0,0,1,0],[0,0,0,1]], dtype=float),
    ),
]

# Invertible matrices for inverse test
inv_cases = [
    np.array([[1,2,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]], dtype=float),
    np.array([[2,0,0,1],[0,3,0,2],[0,0,4,3],[0,0,0,1]], dtype=float),
    np.array([[1,0,0,5],[0,1,0,6],[0,0,1,7],[0,0,0,1]], dtype=float),  # translation
]

print('test "mat4" {')
print('    const eps: f32 = 0.001;')

# MulVec4 tests
print('\n    // MulVec4')
m = np.array([[1,0,0,1],[0,1,0,2],[0,0,1,3],[0,0,0,1]], dtype=float)
v = np.array([1,2,3,1], dtype=float)
result = m @ v
print_mat4('m_trans', m)
print(f'    const v = Vec4(f32){{ .x=1, .y=2, .z=3, .w=1 }};')
print(f'    const mv = m_trans.MulVec4(v);')
print(f'    try std.testing.expectApproxEqAbs(@as(f32, {result[0]:.6}), mv.x, eps);')
print(f'    try std.testing.expectApproxEqAbs(@as(f32, {result[1]:.6}), mv.y, eps);')
print(f'    try std.testing.expectApproxEqAbs(@as(f32, {result[2]:.6}), mv.z, eps);')
print(f'    try std.testing.expectApproxEqAbs(@as(f32, {result[3]:.6}), mv.w, eps);')

# Mat4MulMat4 tests
print('\n    // Mat4MulMat4')
for i, (a, b) in enumerate(cases):
    result = a @ b
    print(f'\n    // case {i}')
    print(f'    {{')
    print_mat4('a', a)
    print_mat4('b', b)
    print(f'        const r = a.Mat4MulMat4(b);')
    check_mat4('r', result)
    print(f'    }}')

# Inverse tests
print('\n    // Inverse')
for i, m in enumerate(inv_cases):
    inv = np.linalg.inv(m)
    identity = m @ inv
    print(f'\n    // inverse case {i}')
    print(f'    {{')
    print_mat4('m', m)
    print(f'        const inv = m.Inverse();')
    print(f'        // verify m * inv = identity')
    print(f'        const identity = m.Mat4MulMat4(inv);')
    for col in range(4):
        for row, comp in enumerate(['x','y','z','w']):
            expected = 1.0 if row == col else 0.0
            print(f'        try std.testing.expectApproxEqAbs(@as(f32, {expected:.1}), identity.cols[{col}].{comp}, eps);')
    print(f'    }}')

print('}')
