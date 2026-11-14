"""Render a multi-triangle room and visualize the IDs returned by hardware."""

import math

import cocotb

from .helpers.png import write
from .helpers.scene import MISS, build, rays, scene, sub
from .helpers.setup import run

WIDTH = 64
HEIGHT = 64


def shade(triangle, color):
    """Apply host-side flat Lambert lighting to a triangle's material color."""
    a, b, c = triangle
    u = sub(b, a)
    v = sub(c, a)
    normal = (
        u[1] * v[2] - u[2] * v[1],
        u[2] * v[0] - u[0] * v[2],
        u[0] * v[1] - u[1] * v[0],
    )
    length = math.sqrt(sum(component * component for component in normal))
    light = (0.3, 0.8, -0.5)
    light_length = math.sqrt(sum(component * component for component in light))
    diffuse = abs(sum(x * y for x, y in zip(normal, light)) / length)
    shade_factor = 0.3 + 0.7 * diffuse / light_length
    return tuple(int(component * shade_factor) for component in color)


def id_color(triangle_id):
    """Map the actual reordered triangle ID to a deterministic false color."""
    if triangle_id == MISS:
        return (20, 20, 30)
    # Distinct hues make the two triangles of each quad visible.
    import colorsys

    hue = (triangle_id * 0.61803398875) % 1.0
    return tuple(int(channel * 255) for channel in colorsys.hsv_to_rgb(hue, 0.7, 0.95))


@cocotb.test()
async def render(dut):
    """Trace the room, compare every hit, and write shaded and ID images."""
    source, colors = scene()
    nodes, triangles, order = build(source)
    ids = await run(dut, rays(WIDTH, HEIGHT), nodes, triangles, "scene")

    pixels = []
    for triangle_id in ids:
        if triangle_id == MISS:
            pixels.append((20, 20, 30))
        else:
            pixels.append(shade(triangles[triangle_id], colors[order[triangle_id]]))

    write("docs/images/render.png", WIDTH, HEIGHT, pixels)
    write("docs/images/render_ids.png", WIDTH, HEIGHT, [id_color(i) for i in ids])
