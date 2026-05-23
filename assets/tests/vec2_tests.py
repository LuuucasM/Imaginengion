import numpy as np

def fmt(v):
    if isinstance(v, np.ndarray):
        return ", ".join(f"{x:.6}" for x in v)
    return f"{v:.6}"

cases = [
    (np.array([3.0, 4.0]), np.array([1.0, 2.0])),
    (np.array([1.0, 0.0]), np.array([0.0, 1.0])),
    (np.array([-2.0, 3.0]), np.array([4.0, -1.0])),
    (np.array([0.5, 0.5]), np.array([0.5, 0.5])),
]

print("// ========== Vec2 Reference Values ==========\n")
for a, b in cases:
    print(f"// a=[{fmt(a)}]  b=[{fmt(b)}]")
    length = np.linalg.norm(a)
    denom = np.dot(b, b)
    proj = b * (np.dot(a, b) / denom) if denom > 0 else np.zeros(2)
    print(f"//   Len:             {fmt(length)}")
    print(f"//   Dir:             {fmt(a / length if length > 0 else np.zeros(2))}")
    print(f"//   Dot:             {fmt(np.dot(a, b))}")
    print(f"//   Add:             {fmt(a + b)}")
    print(f"//   Sub:             {fmt(a - b)}")
    print(f"//   MulScaler(2.5):  {fmt(a * 2.5)}")
    print(f"//   DistSq:          {fmt(np.dot(a-b, a-b))}")
    print(f"//   Distance:        {fmt(np.linalg.norm(a - b))}")
    print(f"//   ProjectOn:       {fmt(proj)}")
    print(f"//   RejectFrom:      {fmt(a - proj)}")
    print(f"//   Lerp(t=0.25):    {fmt(a + (b - a) * 0.25)}")
    print(f"//   Lerp(t=0.75):    {fmt(a + (b - a) * 0.75)}")
    print()

print("// ========== Zig Tests ==========\n")
for i, (a, b) in enumerate(cases):
    length = np.linalg.norm(a)
    denom = np.dot(b, b)
    proj = b * (np.dot(a, b) / denom) if denom > 0 else np.zeros(2)
    reject = a - proj
    print(f'test "vec2 case {i}" {{')
    print(f'    const a = Vec2(f32){{ .x = {a[0]}, .y = {a[1]} }};')
    print(f'    const b = Vec2(f32){{ .x = {b[0]}, .y = {b[1]} }};')
    print(f'    const eps: f32 = 0.0001;')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {length:.6}), a.Len(), eps);')
    print(f'    const dir = a.Dir();')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {(a/length)[0]:.6}), dir.x, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {(a/length)[1]:.6}), dir.y, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {np.dot(a,b):.6}), a.Dot(b), eps);')
    print(f'    const add = a.AddVec(b);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {(a+b)[0]:.6}), add.x, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {(a+b)[1]:.6}), add.y, eps);')
    print(f'    const mul = a.MulScaler(2.5);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {(a*2.5)[0]:.6}), mul.x, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {(a*2.5)[1]:.6}), mul.y, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {np.dot(a-b,a-b):.6}), a.DistanceSquared(b), eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {np.linalg.norm(a-b):.6}), a.Distance(b), eps);')
    print(f'    const proj = a.ProjectOn(b);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {proj[0]:.6}), proj.x, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {proj[1]:.6}), proj.y, eps);')
    print(f'    const rej = a.RejectFrom(b);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {reject[0]:.6}), rej.x, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {reject[1]:.6}), rej.y, eps);')
    print(f'    const lerp = a.Lerp(b, 0.25);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {(a+(b-a)*0.25)[0]:.6}), lerp.x, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {(a+(b-a)*0.25)[1]:.6}), lerp.y, eps);')
    print(f'}}')
    print()
