from __future__ import annotations

import pathlib

from .memory import MASK32, Memory


BLOCK_DEVICE_BASE = 0x10050000
BLOCK_DEVICE_SIZE = 0x1000
BLOCK_SECTOR_SIZE = 512

REG_STATUS = 0x00
REG_COMMAND = 0x04
REG_LBA_LO = 0x08
REG_LBA_HI = 0x0C
REG_MEM_ADDR = 0x10
REG_SECTOR_COUNT = 0x14
REG_CAPACITY_LO = 0x18
REG_CAPACITY_HI = 0x1C

STATUS_READY = 1 << 0
STATUS_ERROR = 1 << 1
STATUS_DONE = 1 << 2
CMD_READ = 1
CMD_WRITE = 2


class BlockDevice:
    def __init__(self, image: bytearray, readonly: bool = False) -> None:
        self.image = image
        self.readonly = readonly
        self.status = STATUS_READY
        self.command = 0
        self.lba = 0
        self.mem_addr = 0
        self.sector_count = 0
        self.error_code = 0

    @classmethod
    def from_file(cls, path: pathlib.Path, readonly: bool = False) -> "BlockDevice":
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

    def read_u32(self, addr: int) -> int:
        off = (addr - BLOCK_DEVICE_BASE) & 0xFFF
        if off == REG_STATUS:
            return self.status | ((self.error_code & 0xFF) << 8)
        if off == REG_COMMAND:
            return self.command
        if off == REG_LBA_LO:
            return self.lba & MASK32
        if off == REG_LBA_HI:
            return (self.lba >> 32) & MASK32
        if off == REG_MEM_ADDR:
            return self.mem_addr
        if off == REG_SECTOR_COUNT:
            return self.sector_count
        if off == REG_CAPACITY_LO:
            return self.sector_capacity & MASK32
        if off == REG_CAPACITY_HI:
            return (self.sector_capacity >> 32) & MASK32
        return 0

    def write_u32(self, addr: int, value: int, mem: Memory) -> None:
        value &= MASK32
        off = (addr - BLOCK_DEVICE_BASE) & 0xFFF
        if off == REG_STATUS:
            if value & STATUS_DONE:
                self.status &= ~STATUS_DONE
            if value & STATUS_ERROR:
                self.status &= ~STATUS_ERROR
                self.error_code = 0
            return
        if off == REG_COMMAND:
            self.command = value
            self._execute(value, mem)
            return
        if off == REG_LBA_LO:
            self.lba = (self.lba & ~MASK32) | value
            return
        if off == REG_LBA_HI:
            self.lba = ((value & MASK32) << 32) | (self.lba & MASK32)
            return
        if off == REG_MEM_ADDR:
            self.mem_addr = value
            return
        if off == REG_SECTOR_COUNT:
            self.sector_count = value
            return

    def _execute(self, command: int, mem: Memory) -> None:
        self.status = STATUS_READY
        self.error_code = 0
        if command not in (CMD_READ, CMD_WRITE):
            self._set_error(1)
            return
        if self.sector_count == 0:
            self.status |= STATUS_DONE
            return
        start = self.lba * BLOCK_SECTOR_SIZE
        size = self.sector_count * BLOCK_SECTOR_SIZE
        end = start + size
        if start < 0 or end > len(self.image):
            self._set_error(2)
            return
        if command == CMD_READ:
            mem.load(self.mem_addr, bytes(self.image[start:end]))
            self.status |= STATUS_DONE
            return
        if self.readonly:
            self._set_error(3)
            return
        self.image[start:end] = mem.read_bytes(self.mem_addr, size)
        self.status |= STATUS_DONE

    def _set_error(self, code: int) -> None:
        self.error_code = code
        self.status |= STATUS_READY | STATUS_ERROR | STATUS_DONE
