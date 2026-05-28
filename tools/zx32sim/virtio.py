from __future__ import annotations

import dataclasses
import pathlib

from .block import BLOCK_SECTOR_SIZE
from .memory import MASK32, Memory


VIRTIO_MMIO_BASE = 0x10060000
VIRTIO_MMIO_SIZE = 0x1000

VIRTIO_MAGIC = 0x74726976
VIRTIO_VERSION = 2
VIRTIO_DEVICE_BLK = 2
VIRTIO_VENDOR_ZX32 = 0x5A323032

VIRTIO_F_VERSION_1 = 32
VIRTIO_BLK_F_RO = 5

VIRTQ_DESC_F_NEXT = 1
VIRTQ_DESC_F_WRITE = 2
VIRTQ_DESC_F_INDIRECT = 4

VIRTIO_MMIO_INT_VRING = 1 << 0

VIRTIO_BLK_T_IN = 0
VIRTIO_BLK_T_OUT = 1
VIRTIO_BLK_T_FLUSH = 4
VIRTIO_BLK_T_GET_ID = 8

VIRTIO_BLK_S_OK = 0
VIRTIO_BLK_S_IOERR = 1
VIRTIO_BLK_S_UNSUPP = 2


@dataclasses.dataclass
class VirtqDesc:
    index: int
    addr: int
    length: int
    flags: int
    next: int


@dataclasses.dataclass
class VirtqState:
    num: int = 0
    ready: bool = False
    desc_addr: int = 0
    avail_addr: int = 0
    used_addr: int = 0
    last_avail_idx: int = 0


class VirtioMmioBlockDevice:
    def __init__(self, image: bytearray, readonly: bool = False, queue_num_max: int = 128) -> None:
        self.image = image
        self.readonly = readonly
        self.queue_num_max = queue_num_max
        self.status = 0
        self.device_features_sel = 0
        self.driver_features_sel = 0
        self.driver_features = 0
        self.queue_sel = 0
        self.queues = [VirtqState()]
        self.interrupt_status = 0

    @classmethod
    def from_file(cls, path: pathlib.Path, readonly: bool = False) -> "VirtioMmioBlockDevice":
        if path.exists():
            data = bytearray(path.read_bytes())
        else:
            data = bytearray()
        if len(data) % BLOCK_SECTOR_SIZE != 0:
            data.extend(b"\0" * (BLOCK_SECTOR_SIZE - (len(data) % BLOCK_SECTOR_SIZE)))
        return cls(data, readonly=readonly)

    def write_file(self, path: pathlib.Path) -> None:
        path.write_bytes(self.image)

    @property
    def sector_capacity(self) -> int:
        return len(self.image) // BLOCK_SECTOR_SIZE

    @property
    def irq_pending(self) -> bool:
        return self.interrupt_status != 0

    def read(self, addr: int, size: int) -> int:
        if size not in (1, 2, 4):
            raise ValueError(f"bad virtio-mmio read size {size}")
        off = (addr - VIRTIO_MMIO_BASE) & 0xFFF
        if off >= 0x100:
            return self._read_config(off - 0x100, size)
        if size != 4 or (addr & 3) != 0:
            word = self._read_register(off & ~3)
            shift = (off & 3) * 8
            mask = (1 << (size * 8)) - 1
            return (word >> shift) & mask
        return self._read_register(off)

    def write(self, addr: int, size: int, value: int, mem: Memory) -> None:
        if size not in (1, 2, 4):
            raise ValueError(f"bad virtio-mmio write size {size}")
        off = (addr - VIRTIO_MMIO_BASE) & 0xFFF
        if off >= 0x100:
            return
        if size != 4 or (addr & 3) != 0:
            return
        self._write_register(off, value & MASK32, mem)

    def _selected_queue(self) -> VirtqState | None:
        if self.queue_sel >= len(self.queues):
            return None
        return self.queues[self.queue_sel]

    def _read_register(self, off: int) -> int:
        queue = self._selected_queue()
        if off == 0x000:
            return VIRTIO_MAGIC
        if off == 0x004:
            return VIRTIO_VERSION
        if off == 0x008:
            return VIRTIO_DEVICE_BLK
        if off == 0x00C:
            return VIRTIO_VENDOR_ZX32
        if off == 0x010:
            return self._device_features_word()
        if off == 0x034:
            return self.queue_num_max if queue is not None else 0
        if off == 0x038:
            return queue.num if queue is not None else 0
        if off == 0x044:
            return 1 if queue is not None and queue.ready else 0
        if off == 0x060:
            return self.interrupt_status
        if off == 0x070:
            return self.status
        if off == 0x080:
            return queue.desc_addr & MASK32 if queue is not None else 0
        if off == 0x084:
            return (queue.desc_addr >> 32) & MASK32 if queue is not None else 0
        if off == 0x090:
            return queue.avail_addr & MASK32 if queue is not None else 0
        if off == 0x094:
            return (queue.avail_addr >> 32) & MASK32 if queue is not None else 0
        if off == 0x0A0:
            return queue.used_addr & MASK32 if queue is not None else 0
        if off == 0x0A4:
            return (queue.used_addr >> 32) & MASK32 if queue is not None else 0
        if off in (0x0B0, 0x0B4, 0x0B8, 0x0BC):
            return MASK32
        if off == 0x0FC:
            return 0
        return 0

    def _write_register(self, off: int, value: int, mem: Memory) -> None:
        queue = self._selected_queue()
        if off == 0x014:
            self.device_features_sel = value
            return
        if off == 0x020:
            if self.driver_features_sel == 0:
                self.driver_features = (self.driver_features & 0xFFFFFFFF00000000) | value
            elif self.driver_features_sel == 1:
                self.driver_features = (self.driver_features & MASK32) | (value << 32)
            return
        if off == 0x024:
            self.driver_features_sel = value
            return
        if off == 0x030:
            self.queue_sel = value
            return
        if off == 0x038 and queue is not None:
            queue.num = min(value, self.queue_num_max)
            return
        if off == 0x044 and queue is not None:
            queue.ready = value != 0
            if not queue.ready:
                queue.last_avail_idx = 0
            return
        if off == 0x050:
            self._notify(value, mem)
            return
        if off == 0x064:
            self.interrupt_status &= ~value
            return
        if off == 0x070:
            if value == 0:
                self._reset()
            else:
                self.status = value & 0xFF
            return
        if queue is None:
            return
        if off == 0x080:
            queue.desc_addr = (queue.desc_addr & 0xFFFFFFFF00000000) | value
            return
        if off == 0x084:
            queue.desc_addr = (queue.desc_addr & MASK32) | (value << 32)
            return
        if off == 0x090:
            queue.avail_addr = (queue.avail_addr & 0xFFFFFFFF00000000) | value
            return
        if off == 0x094:
            queue.avail_addr = (queue.avail_addr & MASK32) | (value << 32)
            return
        if off == 0x0A0:
            queue.used_addr = (queue.used_addr & 0xFFFFFFFF00000000) | value
            return
        if off == 0x0A4:
            queue.used_addr = (queue.used_addr & MASK32) | (value << 32)
            return

    def _reset(self) -> None:
        self.status = 0
        self.device_features_sel = 0
        self.driver_features_sel = 0
        self.driver_features = 0
        self.queue_sel = 0
        self.queues = [VirtqState()]
        self.interrupt_status = 0

    def _device_features_word(self) -> int:
        features = 1 << VIRTIO_F_VERSION_1
        if self.readonly:
            features |= 1 << VIRTIO_BLK_F_RO
        if self.device_features_sel == 0:
            return features & MASK32
        if self.device_features_sel == 1:
            return (features >> 32) & MASK32
        return 0

    def _read_config(self, off: int, size: int) -> int:
        config = bytearray(64)
        capacity = self.sector_capacity
        for idx in range(8):
            config[idx] = (capacity >> (idx * 8)) & 0xFF
        out = 0
        for idx in range(size):
            pos = off + idx
            if 0 <= pos < len(config):
                out |= config[pos] << (idx * 8)
        return out

    def _notify(self, queue_index: int, mem: Memory) -> None:
        if queue_index >= len(self.queues):
            return
        queue = self.queues[queue_index]
        if not queue.ready or queue.num == 0:
            return
        avail_idx = mem.read_u16(queue.avail_addr + 2)
        while queue.last_avail_idx != avail_idx:
            ring_off = queue.avail_addr + 4 + ((queue.last_avail_idx % queue.num) * 2)
            head = mem.read_u16(ring_off)
            self._process_chain(queue, head, mem)
            queue.last_avail_idx = (queue.last_avail_idx + 1) & 0xFFFF
            avail_idx = mem.read_u16(queue.avail_addr + 2)

    def _read_desc(self, queue: VirtqState, index: int, mem: Memory) -> VirtqDesc:
        base = queue.desc_addr + index * 16
        addr = mem.read_u32(base) | (mem.read_u32(base + 4) << 32)
        return VirtqDesc(
            index=index,
            addr=addr,
            length=mem.read_u32(base + 8),
            flags=mem.read_u16(base + 12),
            next=mem.read_u16(base + 14),
        )

    def _read_chain(self, queue: VirtqState, head: int, mem: Memory) -> list[VirtqDesc]:
        chain: list[VirtqDesc] = []
        seen: set[int] = set()
        index = head
        for _ in range(queue.num):
            if index >= queue.num or index in seen:
                break
            seen.add(index)
            desc = self._read_desc(queue, index, mem)
            chain.append(desc)
            if (desc.flags & VIRTQ_DESC_F_INDIRECT) != 0:
                break
            if (desc.flags & VIRTQ_DESC_F_NEXT) == 0:
                break
            index = desc.next
        return chain

    def _process_chain(self, queue: VirtqState, head: int, mem: Memory) -> None:
        chain = self._read_chain(queue, head, mem)
        status = VIRTIO_BLK_S_IOERR
        written_len = 1
        if len(chain) >= 2:
            status_desc = chain[-1]
            if (status_desc.flags & VIRTQ_DESC_F_WRITE) != 0 and status_desc.length >= 1:
                status, written_len = self._execute_request(chain, mem)
                mem.write_u8(status_desc.addr, status)
        self._push_used(queue, head, written_len, mem)
        self.interrupt_status |= VIRTIO_MMIO_INT_VRING

    def _execute_request(self, chain: list[VirtqDesc], mem: Memory) -> tuple[int, int]:
        header = chain[0]
        status_desc = chain[-1]
        data_descs = chain[1:-1]
        if header.length < 16 or (header.flags & VIRTQ_DESC_F_WRITE) != 0:
            return VIRTIO_BLK_S_IOERR, 1
        if (status_desc.flags & VIRTQ_DESC_F_WRITE) == 0:
            return VIRTIO_BLK_S_IOERR, 1
        request_type = mem.read_u32(header.addr)
        sector = mem.read_u32(header.addr + 8) | (mem.read_u32(header.addr + 12) << 32)
        if request_type == VIRTIO_BLK_T_FLUSH:
            return VIRTIO_BLK_S_OK, 1
        if request_type == VIRTIO_BLK_T_GET_ID:
            ident = b"ZX32SIM-DISK\0\0\0\0\0\0\0\0"
            return self._write_to_descs(mem, data_descs, ident[:20])
        total_len = sum(desc.length for desc in data_descs)
        start = sector * BLOCK_SECTOR_SIZE
        end = start + total_len
        if end > len(self.image):
            return VIRTIO_BLK_S_IOERR, 1
        if request_type == VIRTIO_BLK_T_IN:
            if any((desc.flags & VIRTQ_DESC_F_WRITE) == 0 for desc in data_descs):
                return VIRTIO_BLK_S_IOERR, 1
            status, written = self._write_to_descs(mem, data_descs, bytes(self.image[start:end]))
            return status, written + 1
        if request_type == VIRTIO_BLK_T_OUT:
            if self.readonly:
                return VIRTIO_BLK_S_IOERR, 1
            if any((desc.flags & VIRTQ_DESC_F_WRITE) != 0 for desc in data_descs):
                return VIRTIO_BLK_S_IOERR, 1
            data = bytearray()
            for desc in data_descs:
                data.extend(mem.read_bytes(desc.addr, desc.length))
            self.image[start:end] = data[:total_len]
            return VIRTIO_BLK_S_OK, 1
        return VIRTIO_BLK_S_UNSUPP, 1

    @staticmethod
    def _write_to_descs(mem: Memory, descs: list[VirtqDesc], data: bytes) -> tuple[int, int]:
        pos = 0
        for desc in descs:
            if (desc.flags & VIRTQ_DESC_F_WRITE) == 0:
                return VIRTIO_BLK_S_IOERR, 1
            chunk = min(desc.length, len(data) - pos)
            if chunk > 0:
                mem.load(desc.addr, data[pos : pos + chunk])
                pos += chunk
            if pos >= len(data):
                break
        return VIRTIO_BLK_S_OK, pos

    def _push_used(self, queue: VirtqState, head: int, length: int, mem: Memory) -> None:
        used_idx = mem.read_u16(queue.used_addr + 2)
        elem = queue.used_addr + 4 + ((used_idx % queue.num) * 8)
        mem.write_u32(elem, head)
        mem.write_u32(elem + 4, length)
        mem.write_u16(queue.used_addr + 2, (used_idx + 1) & 0xFFFF)
