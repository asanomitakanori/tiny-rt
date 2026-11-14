"""Record compact cycle-by-cycle snapshots for inspecting simulation runs."""

from pathlib import Path


class TraceLog:
    """A context manager that owns one trace file per simulation."""

    def __init__(self, name):
        self.path = Path("test/logs") / f"{name}.log"
        self.stream = None

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.stream = self.path.open("w", encoding="utf-8")
        self.stream.write("# cycle: core_state/traversal_state for each core\n")
        return self

    def sample(self, cycle, cores):
        """Write the visible control states after a rising clock edge."""
        values = [
            f"{int(core.core_state.value)}/{int(core.traversal_state.value)}"
            for core in cores
        ]
        self.stream.write(f"{cycle}: {' '.join(values)}\n")

    def __exit__(self, exc_type, exc_value, traceback):
        self.stream.close()
