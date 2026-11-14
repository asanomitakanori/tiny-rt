"""Build scene memory and model the RTL's fixed-point traversal exactly."""

import math

Q = 65536
NODE_BASE = 40960
TRI_BASE = 49152
MISS = 0xFFFFFFFF


def q(value):
    """Convert a floating-point scene coordinate to signed Q16.16."""
    return round(value * Q)


def mul(a, b):
    """Multiply two Q16.16 values, rounding down just like RTL >>> 16."""
    return (a * b) >> 16


def sub(a, b):
    """Subtract two three-component vectors."""
    return [x - y for x, y in zip(a, b)]


def cross(a, b):
    """Cross product with a separate shift on each multiplication."""
    return [
        mul(a[1], b[2]) - mul(a[2], b[1]),
        mul(a[2], b[0]) - mul(a[0], b[2]),
        mul(a[0], b[1]) - mul(a[1], b[0]),
    ]


def dot(a, b):
    """Dot product with the same per-product shifts as the hardware."""
    return sum(mul(x, y) for x, y in zip(a, b))


def triangle(ray, tri):
    """Return the positive (t numerator, determinant) for a hit, or None."""
    origin, direction = ray[:3], ray[3:6]
    a, b, c = tri
    edge1 = sub(b, a)
    edge2 = sub(c, a)
    pvec = cross(direction, edge2)
    det = dot(edge1, pvec)
    offset = sub(origin, a)
    u = dot(offset, pvec)
    qvec = cross(offset, edge1)
    v = dot(direction, qvec)
    t = dot(edge2, qvec)

    # Normalize the sign before testing barycentric coordinates.
    if det < 0:
        det, u, v, t = -det, -u, -v, -t
    if det > 0 and u >= 0 and v >= 0 and u + v <= det and t > 0:
        return t, det
    return None


def box(ray, node):
    """Intersect three fixed-point slab intervals with the forward ray."""
    low = 0
    high = (1 << 63) - 1
    axes = zip(ray[:3], ray[3:6], ray[6:], node[:3], node[3:6])
    for origin, direction, inverse, minimum, maximum in axes:
        if direction == 0:
            if origin < minimum or origin > maximum:
                return False
        else:
            a = mul(minimum - origin, inverse)
            b = mul(maximum - origin, inverse)
            low = max(low, min(a, b))
            high = min(high, max(a, b))
    return high >= low


def build(triangles):
    """Build a median-split BVH with adjacent siblings and contiguous leaves.

    Return nodes, reordered fixed-point triangles, and a mapping from reordered
    triangle IDs to the input IDs used for materials.
    """
    triangles = [[list(map(q, vertex)) for vertex in tri] for tri in triangles]
    nodes = [None]
    ordered = []
    order = []

    def fill(slot, ids):
        vertices = [vertex for i in ids for vertex in triangles[i]]
        bounds = [min(v[k] for v in vertices) for k in range(3)]
        bounds += [max(v[k] for v in vertices) for k in range(3)]
        if len(ids) <= 2:
            first = len(ordered)
            ordered.extend(triangles[i] for i in ids)
            order.extend(ids)
            nodes[slot] = bounds + [first, len(ids)]
        else:
            axis = max(range(3), key=lambda k: bounds[k + 3] - bounds[k])
            ids.sort(key=lambda i: sum(v[axis] for v in triangles[i]))
            middle = len(ids) // 2
            left = len(nodes)
            nodes.extend([None, None])
            nodes[slot] = bounds + [left, 0]
            fill(left, ids[:middle])
            fill(left + 1, ids[middle:])

    fill(0, list(range(len(triangles))))
    return nodes, ordered, order


def trace(ray, nodes, tris):
    """Visit left before right and compare rational distances without division."""
    stack = [0]
    best = None
    result = MISS
    while stack:
        node = nodes[stack.pop()]
        if not box(ray, node):
            continue
        if node[7] == 0:
            # The stack is LIFO, so push right first.
            stack.extend((node[6] + 1, node[6]))
        else:
            for i in range(node[6], node[6] + node[7]):
                hit = triangle(ray, tris[i])
                if hit and (best is None or hit[0] * best[1] < best[0] * hit[1]):
                    best = hit
                    result = i
    return result


def rays(width, height):
    """Generate normalized pinhole-camera rays and clamped reciprocals."""
    result = []
    for y in range(height):
        for x in range(width):
            direction = [
                (x + 0.5 - width / 2) / (width / 2) * 0.8,
                (height / 2 - y - 0.5) / (height / 2) * 0.8,
                1.0,
            ]
            norm = math.sqrt(sum(component * component for component in direction))
            direction = [q(component / norm) for component in direction]
            inverse = [
                max(-2147483648, min(2147483647, (Q * Q) // component))
                if component else 2147483647
                for component in direction
            ]
            result.append([0, 0, q(-5)] + direction + inverse)
    return result


def pack(rays, nodes, tris):
    """Serialize rays, nodes, and triangles into 32-bit scene memory."""
    memory = [0] * 65536
    for i, ray in enumerate(rays):
        memory[i * 9:i * 9 + 9] = [word & 0xFFFFFFFF for word in ray]
    for i, node in enumerate(nodes):
        memory[NODE_BASE + i * 8:NODE_BASE + i * 8 + 8] = [
            word & 0xFFFFFFFF for word in node
        ]
    for i, tri in enumerate(tris):
        memory[TRI_BASE + i * 9:TRI_BASE + i * 9 + 9] = [
            word & 0xFFFFFFFF for vertex in tri for word in vertex
        ]
    return memory


def quad(a, b, c, d):
    """Split a quadrilateral into two triangles."""
    return [(a, b, c), (a, c, d)]


def scene():
    """Create a colored room and two boxes as triangles and material colors."""
    tris = []
    colors = []

    def add(a, b, c, d, color):
        tris.extend(quad(a, b, c, d))
        colors.extend([color] * 2)

    add((-3, -3, 4), (3, -3, 4), (3, 3, 4), (-3, 3, 4), (180, 180, 180))
    add((-3, -3, -1), (-3, -3, 4), (-3, 3, 4), (-3, 3, -1), (200, 65, 55))
    add((3, -3, 4), (3, -3, -1), (3, 3, -1), (3, 3, 4), (60, 160, 75))
    add((-3, -3, -1), (3, -3, -1), (3, -3, 4), (-3, -3, 4), (190, 190, 175))
    add((-3, 3, 4), (3, 3, 4), (3, 3, -1), (-3, 3, -1), (200, 200, 190))

    def cube(x0, x1, y0, y1, z0, z1, color):
        a, b = (x0, y0, z0), (x1, y0, z0)
        c, d = (x1, y1, z0), (x0, y1, z0)
        e, f = (x0, y0, z1), (x1, y0, z1)
        g, h = (x1, y1, z1), (x0, y1, z1)
        faces = [(a, b, c, d), (e, h, g, f), (a, d, h, e),
                 (b, f, g, c), (d, c, g, h), (a, e, f, b)]
        for face in faces:
            add(*face, color)

    cube(-2, -0.5, -3, -0.3, 0.5, 2, (180, 160, 90))
    cube(0.5, 2, -3, -1.4, -0.5, 1, (100, 140, 200))
    return tris, colors
