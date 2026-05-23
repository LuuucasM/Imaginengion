import numpy as np
from scipy.spatial.transform import Rotation

def fmt(v):
    if isinstance(v, np.ndarray):
        return ", ".join(f"{x:.6}" for x in v)
    return f"{v:.6}"

cases = [
    (np.array([3.0, 4.0, 0.0]), np.array([1.0, 2.0, 3.0])),
    (np.array([1.0, 0.0, 0.0]), np.array([0.0, 1.0, 0.0])),
    (np.array([-2.0, 3.0, 1.0]), np.array([4.0, -1.0, 2.0])),
    (np.array([0.5, 0.5, 0.5]), np.array([0.5, 0.5, 0.5])),
]

print("// ========== Vec3 Reference Values ==========\n")
for a, b in cases:
    length = np.linalg.norm(a)
    denom = np.dot(b, b)
    proj = b * (np.dot(a, b) / denom) if denom > 0 else np.zeros(3)
    cross = np.cross(a, b)
    print(f"// a=[{fmt(a)}]  b=[{fmt(b)}]")
    print(f"//   Len:             {fmt(length)}")
    print(f"//   Dir:             {fmt(a / length if length > 0 else np.zeros(3))}")
    print(f"//   Dot:             {fmt(np.dot(a, b))}")
    print(f"//   Cross:           {fmt(cross)}")
    print(f"//   Add:             {fmt(a + b)}")
    print(f"//   Sub:             {fmt(a - b)}")
    print(f"//   MulScaler(2.5):  {fmt(a * 2.5)}")
    print(f"//   DistSq:          {fmt(np.dot(a-b, a-b))}")
    print(f"//   Distance:        {fmt(np.linalg.norm(a - b))}")
    print(f"//   ProjectOn:       {fmt(proj)}")
    print(f"//   RejectFrom:      {fmt(a - proj)}")
    print(f"//   Lerp(t=0.25):    {fmt(a + (b - a) * 0.25)}")
    print()

quat_cases = [
    ("x90",  np.array([1.0, 0.0, 0.0]), np.pi / 2),
    ("y90",  np.array([0.0, 1.0, 0.0]), np.pi / 2),
    ("z90",  np.array([0.0, 0.0, 1.0]), np.pi / 2),
    ("z180", np.array([0.0, 0.0, 1.0]), np.pi),
]

print("// ========== Zig Tests ==========\n")
for i, (a, b) in enumerate(cases):
    length = np.linalg.norm(a)
    denom = np.dot(b, b)
    proj = b * (np.dot(a, b) / denom) if denom > 0 else np.zeros(3)
    reject = a - proj
    cross = np.cross(a, b)
    print(f'test "vec3 case {i}" {{')
    print(f'    const a = Vec3(f32){{ .x = {a[0]}, .y = {a[1]}, .z = {a[2]} }};')
    print(f'    const b = Vec3(f32){{ .x = {b[0]}, .y = {b[1]}, .z = {b[2]} }};')
    print(f'    const eps: f32 = 0.0001;')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {length:.6}), a.Len(), eps);')
    d = a / length
    print(f'    const dir = a.Dir();')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {d[0]:.6}), dir.x, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {d[1]:.6}), dir.y, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {d[2]:.6}), dir.z, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {np.dot(a,b):.6}), a.Dot(b), eps);')
    print(f'    const cross = a.Cross(b);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {cross[0]:.6}), cross.x, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {cross[1]:.6}), cross.y, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {cross[2]:.6}), cross.z, eps);')
    print(f'    const mul = a.MulScaler(2.5);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {(a*2.5)[0]:.6}), mul.x, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {(a*2.5)[1]:.6}), mul.y, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {(a*2.5)[2]:.6}), mul.z, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {np.dot(a-b,a-b):.6}), a.DistanceSquared(b), eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {np.linalg.norm(a-b):.6}), a.Distance(b), eps);')
    print(f'    const proj = a.ProjectOn(b);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {proj[0]:.6}), proj.x, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {proj[1]:.6}), proj.y, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {proj[2]:.6}), proj.z, eps);')
    print(f'    const rej = a.RejectFrom(b);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {reject[0]:.6}), rej.x, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {reject[1]:.6}), rej.y, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {reject[2]:.6}), rej.z, eps);')
    lerp = a + (b - a) * 0.25
    print(f'    const lerp = a.Lerp(b, 0.25);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {lerp[0]:.6}), lerp.x, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {lerp[1]:.6}), lerp.y, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {lerp[2]:.6}), lerp.z, eps);')
    print(f'}}')
    print()

vec = np.array([1.0, 0.0, 0.0])
print('test "vec3 quat rotate" {')
print(f'    const v = Vec3(f32){{ .x = 1.0, .y = 0.0, .z = 0.0 }};')
print(f'    const eps: f32 = 0.0001;')
for name, axis, angle in quat_cases:
    r = Rotation.from_rotvec(axis * angle)
    q = r.as_quat()  # [x,y,z,w]
    rotated = r.apply(vec)
    # clamp near-zero values
    rotated = np.where(np.abs(rotated) < 1e-10, 0.0, rotated)
    print(f'    const q_{name} = Quat(f32){{ .w = {q[3]:.6}, .x = {q[0]:.6}, .y = {q[1]:.6}, .z = {q[2]:.6} }};')
    print(f'    const r_{name} = v.QuatRotate(q_{name});')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {rotated[0]:.6}), r_{name}.x, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {rotated[1]:.6}), r_{name}.y, eps);')
    print(f'    try std.testing.expectApproxEqAbs(@as(f32, {rotated[2]:.6}), r_{name}.z, eps);')
print('}')
