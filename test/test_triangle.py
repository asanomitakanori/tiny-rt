"""Compare a single-triangle render with the bit-exact reference model."""

import cocotb

from .helpers.scene import build, rays
from .helpers.setup import run


@cocotb.test()
async def triangle(dut):
    """Trace an 8 by 8 camera through a single triangle."""
    nodes, triangles, _ = build([[(-2, -2, 0), (2, -2, 0), (0, 2, 0)]])
    await run(dut, rays(8, 8), nodes, triangles, "triangle")
