import numpy as np

cases = [
    (np.array([1.0, 2.0, 3.0, 4.0]), np.array([4.0, 3.0, 2.0, 1.0])),
    (np.array([1.0, 0.0, 0.0, 0.0]), np.array([0.0, 1.0, 0.0, 0.0])),
    (np.array([-1.0, 2.0, -3.0, 4.0]), np.array([1.0, -2.0, 3.0, -4.0])),
    (np.array([0.5, 0.5, 0.5, 0.5]), np.array([0.5, 0.5, 0.5, 0.5])),
]

print('test "vec4" {')
print('    const eps: f32 = 0.0001;')
for i, (a, b) in enumerate(cases):
    length = np.linalg.norm(a)
    d = a / length if length > 0 else np.zeros(4)
    denom = np.dot(b, b)
    proj = b * (np.dot(a, b) / denom) if denom > 0 else np.zeros(4)
    reject = a - proj
    lerp = a + (b - a) * 0.25
    mul = a * 2.5
    diff = a - b
    print(f'    // case {i}: a=[{", ".join(str(x) for x in a)}]  b=[{", ".join(str(x) for x in b)}]')
    print(f'    {{')
    print(f'        const a = Vec4(f32){{ .x={a[0]}, .y={a[1]}, .z={a[2]}, .w={a[3]} }};')
    print(f'        const b = Vec4(f32){{ .x={b[0]}, .y={b[1]}, .z={b[2]}, .w={b[3]} }};')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {length:.6}), a.Len(), eps);')
    print(f'        const dir = a.Dir();')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {d[0]:.6}), dir.x, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {d[1]:.6}), dir.y, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {d[2]:.6}), dir.z, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {d[3]:.6}), dir.w, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {np.dot(a,b):.6}), a.Dot(b), eps);')
    print(f'        const add = a.AddVec(b);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {(a+b)[0]:.6}), add.x, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {(a+b)[1]:.6}), add.y, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {(a+b)[2]:.6}), add.z, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {(a+b)[3]:.6}), add.w, eps);')
    print(f'        const sub = a.SubVec(b);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {(a-b)[0]:.6}), sub.x, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {(a-b)[1]:.6}), sub.y, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {(a-b)[2]:.6}), sub.z, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {(a-b)[3]:.6}), sub.w, eps);')
    print(f'        const mul = a.MulScaler(2.5);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {mul[0]:.6}), mul.x, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {mul[1]:.6}), mul.y, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {mul[2]:.6}), mul.z, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {mul[3]:.6}), mul.w, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {np.dot(diff,diff):.6}), a.DistanceSquared(b), eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {np.linalg.norm(diff):.6}), a.Distance(b), eps);')
    print(f'        const proj = a.ProjectOn(b);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {proj[0]:.6}), proj.x, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {proj[1]:.6}), proj.y, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {proj[2]:.6}), proj.z, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {proj[3]:.6}), proj.w, eps);')
    print(f'        const rej = a.RejectFrom(b);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {reject[0]:.6}), rej.x, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {reject[1]:.6}), rej.y, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {reject[2]:.6}), rej.z, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {reject[3]:.6}), rej.w, eps);')
    print(f'        const lerp = a.Lerp(b, 0.25);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {lerp[0]:.6}), lerp.x, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {lerp[1]:.6}), lerp.y, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {lerp[2]:.6}), lerp.z, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {lerp[3]:.6}), lerp.w, eps);')
    print(f'    }}')
print('}')
