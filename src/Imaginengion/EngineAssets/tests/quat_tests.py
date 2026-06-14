import numpy as np
from scipy.spatial.transform import Rotation

def fmt(v):
    if isinstance(v, np.ndarray):
        return ", ".join(f"{x:.6}" for x in v)
    return f"{v:.6}"

def quat_from_euler(pitch, yaw, roll):
    # XYZ extrinsic (uppercase) matches FromRadians formula
    r = Rotation.from_euler('XYZ', [pitch, yaw, roll])
    q = r.as_quat()  # [x,y,z,w]
    return q  # returns [x,y,z,w]

def print_quat(name, q_xyzw):
    print(f'        const {name} = Quat(f32){{ .w={q_xyzw[3]:.6}, .x={q_xyzw[0]:.6}, .y={q_xyzw[1]:.6}, .z={q_xyzw[2]:.6} }};')

def check_quat(name, q_xyzw):
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {q_xyzw[3]:.6}), {name}.w, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {q_xyzw[0]:.6}), {name}.x, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {q_xyzw[1]:.6}), {name}.y, eps);')
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {q_xyzw[2]:.6}), {name}.z, eps);')

euler_cases = [
    (0.0, 0.0, 0.0),
    (np.pi/2, 0.0, 0.0),
    (0.0, np.pi/2, 0.0),
    (0.0, 0.0, np.pi/2),
    (np.pi/4, np.pi/4, np.pi/4),
    (np.pi/6, np.pi/3, np.pi/4),
]

print('test "quat" {')
print('    const eps: f32 = 0.0001;')

# FromRadians
print('\n    // FromRadians')
for i, (pitch, yaw, roll) in enumerate(euler_cases):
    q = quat_from_euler(pitch, yaw, roll)
    print(f'    // case {i}: pitch={pitch:.4}, yaw={yaw:.4}, roll={roll:.4}')
    print(f'    {{')
    print(f'        const v = Vec3(f32){{ .x={pitch:.6}, .y={yaw:.6}, .z={roll:.6} }};')
    print(f'        const q = Quat(f32).FromRadians(v);')
    check_quat('q', q)
    print(f'    }}')

# MulQuat
print('\n    // MulQuat')
mul_cases = [
    (euler_cases[1], euler_cases[2]),  # pitch90 * yaw90
    (euler_cases[2], euler_cases[3]),  # yaw90 * roll90
    (euler_cases[4], euler_cases[4]),  # combined * combined
]
for i, ((p1,y1,r1), (p2,y2,r2)) in enumerate(mul_cases):
    q1 = quat_from_euler(p1, y1, r1)
    q2 = quat_from_euler(p2, y2, r2)
    r1_obj = Rotation.from_quat(q1)
    r2_obj = Rotation.from_quat(q2)
    result = (r1_obj * r2_obj).as_quat()
    print(f'    // mul case {i}')
    print(f'    {{')
    print_quat('q1', q1)
    print_quat('q2', q2)
    print(f'        const r = q1.MulQuat(q2);')
    check_quat('r', result)
    print(f'    }}')

# Conjugate
print('\n    // Conjugate')
for i, (pitch, yaw, roll) in enumerate(euler_cases[1:4]):
    q = quat_from_euler(pitch, yaw, roll)
    conj = np.array([-q[0], -q[1], -q[2], q[3]])  # [x,y,z,w] negate xyz
    print(f'    {{')
    print_quat('q', q)
    print(f'        const c = q.Conjugate();')
    check_quat('c', conj)
    print(f'    }}')

# Dot
print('\n    // Dot')
for i, ((p1,y1,r1), (p2,y2,r2)) in enumerate(mul_cases):
    q1 = quat_from_euler(p1, y1, r1)
    q2 = quat_from_euler(p2, y2, r2)
    dot = np.dot(q1, q2)
    print(f'    {{')
    print_quat('q1', q1)
    print_quat('q2', q2)
    print(f'        try std.testing.expectApproxEqAbs(@as(f32, {dot:.6}), q1.Dot(q2), eps);')
    print(f'    }}')

# Normalized
print('\n    // Normalized')
unnorm_cases = [
    np.array([0.5, 0.5, 0.5, 0.5]),
    np.array([1.0, 2.0, 3.0, 4.0]),
    np.array([0.1, 0.0, 0.0, 0.0]),
]
for i, q_wxyz in enumerate(unnorm_cases):
    # q_wxyz is [w,x,y,z]
    q_xyzw = np.array([q_wxyz[1], q_wxyz[2], q_wxyz[3], q_wxyz[0]])
    norm = q_xyzw / np.linalg.norm(q_xyzw)
    print(f'    {{')
    print(f'        const q = Quat(f32){{ .w={q_wxyz[0]:.6}, .x={q_wxyz[1]:.6}, .y={q_wxyz[2]:.6}, .z={q_wxyz[3]:.6} }};')
    print(f'        const n = q.Normalized();')
    check_quat('n', norm)
    print(f'    }}')

# Slerp
print('\n    // Slerp')
slerp_cases = [
    (euler_cases[0], euler_cases[1], 0.5),   # identity -> pitch90, t=0.5
    (euler_cases[1], euler_cases[2], 0.5),   # pitch90 -> yaw90, t=0.5
    (euler_cases[1], euler_cases[2], 0.25),  # pitch90 -> yaw90, t=0.25
]
for i, ((p1,y1,r1), (p2,y2,r2), t) in enumerate(slerp_cases):
    q1 = quat_from_euler(p1, y1, r1)
    q2 = quat_from_euler(p2, y2, r2)
    r1_obj = Rotation.from_quat(q1)
    r2_obj = Rotation.from_quat(q2)
    result = Rotation.slerp(r1_obj, r2_obj, [t]).as_quat()[0] if hasattr(Rotation, 'slerp') else None
    # Use manual slerp
    dot = np.dot(q1, q2)
    if dot < 0:
        q2 = -q2
        dot = -dot
    if dot > 0.9995:
        result = q1 + t * (q2 - q1)
        result = result / np.linalg.norm(result)
    else:
        theta = np.arccos(dot)
        result = (np.sin((1-t)*theta)*q1 + np.sin(t*theta)*q2) / np.sin(theta)
    print(f'    // slerp case {i}: t={t}')
    print(f'    {{')
    print_quat('q1', q1)
    print_quat('q2', q2)
    print(f'        const r = q1.Slerp(q2, {t});')
    check_quat('r', result)
    print(f'    }}')

# InitFromAxisAngle
print('\n    // InitFromAxisAngle')
axis_cases = [
    (np.array([1.0, 0.0, 0.0]), np.pi/2),
    (np.array([0.0, 1.0, 0.0]), np.pi/2),
    (np.array([0.0, 0.0, 1.0]), np.pi),
    (np.array([1/np.sqrt(3), 1/np.sqrt(3), 1/np.sqrt(3)]), np.pi/3),
]
for i, (axis, angle) in enumerate(axis_cases):
    r = Rotation.from_rotvec(axis * angle)
    q = r.as_quat()  # [x,y,z,w]
    print(f'    // axis=[{fmt(axis)}] angle={angle:.4}')
    print(f'    {{')
    print(f'        const axis = Vec3(f32){{ .x={axis[0]:.6}, .y={axis[1]:.6}, .z={axis[2]:.6} }};')
    print(f'        const q = Quat(f32).InitFromAxisAngle(axis, {angle:.6});')
    check_quat('q', q)
    print(f'    }}')

print('}')
