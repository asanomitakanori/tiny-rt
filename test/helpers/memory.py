"""In-process word-addressed memory attached to the accelerator's ports."""


class Memory:
    """Service packed channel signals with immediate valid/ready responses.

    The testbench calls ``drive`` while the clock is low. Scene words are
    immutable during a launch; framebuffer words are updated on valid writes.
    The default device has one channel per port, but packed channels are
    decoded independently using their integer values and declared widths.
    """

    def __init__(self, words, result_count):
        self.scene = words
        self.results = [0xFFFFFFFF] * result_count

    @staticmethod
    def _word(bus, channel, width):
        """Extract one little-endian packed channel from a signal integer."""
        return (bus >> (channel * width)) & ((1 << width) - 1)

    def drive(self, dut):
        """Provide read data and ready bits and collect framebuffer writes."""
        read_requests = int(dut.scene_mem_read_valid.value)
        read_addresses = int(dut.scene_mem_read_address.value)
        read_channels = len(dut.scene_mem_read_valid)
        read_width = len(dut.scene_mem_read_address) // read_channels
        read_data = 0

        for channel in range(read_channels):
            if read_requests & (1 << channel):
                address = self._word(read_addresses, channel, read_width)
                read_data |= self.scene[address] << (32 * channel)

        dut.scene_mem_read_data.value = read_data
        dut.scene_mem_read_ready.value = read_requests

        write_requests = int(dut.fb_mem_write_valid.value)
        write_addresses = int(dut.fb_mem_write_address.value)
        write_words = int(dut.fb_mem_write_data.value)
        write_channels = len(dut.fb_mem_write_valid)
        write_width = len(dut.fb_mem_write_address) // write_channels

        for channel in range(write_channels):
            if write_requests & (1 << channel):
                address = self._word(write_addresses, channel, write_width)
                self.results[address] = self._word(write_words, channel, 32)

        dut.fb_mem_write_ready.value = write_requests
