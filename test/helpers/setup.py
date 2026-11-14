"""Drive a launch and check its framebuffer against the integer model."""

from cocotb.triggers import Timer

from .logger import TraceLog
from .memory import Memory
from .scene import MISS, pack, trace


class Simulation:
    """Advance the DUT and its memory together in explicit half-cycles."""

    def __init__(self, dut, memory):
        self.dut = dut
        self.memory = memory

    async def tick(self):
        """Settle requests, respond from memory, then advance the clock."""
        self.dut.clk.value = 0
        await Timer(5, units="ns")
        self.memory.drive(self.dut)
        await Timer(5, units="ns")
        self.dut.clk.value = 1
        await Timer(5, units="ns")

    async def launch(self, count):
        """Reset, write the batch size, and assert the launch signal."""
        dut = self.dut
        dut.clk.value = 0
        dut.reset.value = 1
        dut.start.value = 0
        dut.device_control_write_enable.value = 0
        dut.scene_mem_read_ready.value = 0
        dut.scene_mem_read_data.value = 0
        dut.fb_mem_write_ready.value = 0
        await self.tick()

        dut.reset.value = 0
        dut.device_control_data.value = count
        dut.device_control_write_enable.value = 1
        await self.tick()
        dut.device_control_write_enable.value = 0
        dut.start.value = 1


async def run(dut, rays, nodes, tris, name):
    """Trace a batch, compare every result, and return the framebuffer."""
    memory = Memory(pack(rays, nodes, tris), len(rays))
    simulation = Simulation(dut, memory)
    await simulation.launch(len(rays))

    with TraceLog(name) as log:
        for cycle in range(3000000):
            await simulation.tick()
            log.sample(cycle, dut.cores)
            if int(dut.done.value):
                break
        else:
            raise AssertionError("Timed out waiting for the device")

    for index, (ray, actual) in enumerate(zip(rays, memory.results)):
        expected = trace(ray, nodes, tris)
        assert actual == expected, (
            f"ray {index}: got {actual:#x}, expected {expected:#x}"
        )

    hits = sum(result != MISS for result in memory.results)
    dut._log.info("Completed in %d cycles; hits %d/%d", cycle + 1, hits, len(rays))
    return memory.results
