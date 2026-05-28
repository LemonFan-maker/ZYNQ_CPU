from __future__ import annotations

from .memory import MASK32
from .virtio import VirtioMmioBlockDevice


PLIC_BASE = 0x0C000000
PLIC_SIZE = 0x00400000
PLIC_VIRTIO_BLK_IRQ = 1


class Plic:
    def __init__(self, virtio_blk: VirtioMmioBlockDevice | None = None) -> None:
        self.virtio_blk = virtio_blk
        self.priorities: dict[int, int] = {}
        self.enable = 0
        self.threshold = 0

    @property
    def irq_pending(self) -> bool:
        return self._claimable_irq() != 0

    def read_u32(self, addr: int) -> int:
        off = (addr - PLIC_BASE) & (PLIC_SIZE - 1)
        if 0 <= off < 0x1000:
            irq = off // 4
            return self.priorities.get(irq, 0)
        if 0x2000 <= off < 0x2080:
            word = (off - 0x2000) // 4
            return self.enable if word == 0 else 0
        if off == 0x200000:
            return self.threshold
        if off == 0x200004:
            return self._claimable_irq()
        return 0

    def write_u32(self, addr: int, value: int) -> None:
        value &= MASK32
        off = (addr - PLIC_BASE) & (PLIC_SIZE - 1)
        if 0 <= off < 0x1000:
            irq = off // 4
            self.priorities[irq] = value
            return
        if 0x2000 <= off < 0x2080:
            word = (off - 0x2000) // 4
            if word == 0:
                self.enable = value
            return
        if off == 0x200000:
            self.threshold = value
            return
        if off == 0x200004:
            return

    def _source_pending(self, irq: int) -> bool:
        return irq == PLIC_VIRTIO_BLK_IRQ and self.virtio_blk is not None and self.virtio_blk.irq_pending

    def _claimable_irq(self) -> int:
        irq = PLIC_VIRTIO_BLK_IRQ
        priority = self.priorities.get(irq, 0)
        if priority <= self.threshold:
            return 0
        if (self.enable & (1 << irq)) == 0:
            return 0
        return irq if self._source_pending(irq) else 0
