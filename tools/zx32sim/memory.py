from __future__ import annotations


MASK32 = 0xFFFFFFFF
PAGE_BITS = 12
PAGE_SIZE = 1 << PAGE_BITS
PAGE_MASK = PAGE_SIZE - 1


class Memory:
    def __init__(self) -> None:
        self._pages: dict[int, bytearray] = {}

    def _page(self, addr: int, create: bool = False) -> bytearray | None:
        page_no = (addr & MASK32) >> PAGE_BITS
        page = self._pages.get(page_no)
        if page is None and create:
            page = bytearray(PAGE_SIZE)
            self._pages[page_no] = page
        return page

    def load(self, addr: int, data: bytes) -> None:
        base = addr & MASK32
        written = 0
        while written < len(data):
            cur = (base + written) & MASK32
            page = self._page(cur, create=True)
            assert page is not None
            page_off = cur & PAGE_MASK
            chunk = min(len(data) - written, PAGE_SIZE - page_off)
            page[page_off : page_off + chunk] = data[written : written + chunk]
            written += chunk

    def read_bytes(self, addr: int, size: int) -> bytes:
        base = addr & MASK32
        out = bytearray(size)
        read = 0
        while read < size:
            cur = (base + read) & MASK32
            page_off = cur & PAGE_MASK
            chunk = min(size - read, PAGE_SIZE - page_off)
            page = self._pages.get(cur >> PAGE_BITS)
            if page is not None:
                out[read : read + chunk] = page[page_off : page_off + chunk]
            read += chunk
        return bytes(out)

    def read_u8(self, addr: int) -> int:
        addr &= MASK32
        page = self._pages.get(addr >> PAGE_BITS)
        if page is None:
            return 0
        return page[addr & PAGE_MASK]

    def read_u16(self, addr: int) -> int:
        addr &= MASK32
        if (addr & PAGE_MASK) <= PAGE_SIZE - 2:
            page = self._pages.get(addr >> PAGE_BITS)
            if page is None:
                return 0
            off = addr & PAGE_MASK
            return page[off] | (page[off + 1] << 8)
        return self.read_u8(addr) | (self.read_u8(addr + 1) << 8)

    def read_u32(self, addr: int) -> int:
        addr &= MASK32
        if (addr & PAGE_MASK) <= PAGE_SIZE - 4:
            page = self._pages.get(addr >> PAGE_BITS)
            if page is None:
                return 0
            off = addr & PAGE_MASK
            return page[off] | (page[off + 1] << 8) | (page[off + 2] << 16) | (page[off + 3] << 24)
        return (
            self.read_u8(addr)
            | (self.read_u8(addr + 1) << 8)
            | (self.read_u8(addr + 2) << 16)
            | (self.read_u8(addr + 3) << 24)
        )

    def write_u8(self, addr: int, value: int) -> None:
        addr &= MASK32
        page_no = addr >> PAGE_BITS
        page = self._pages.get(page_no)
        if page is None:
            page = bytearray(PAGE_SIZE)
            self._pages[page_no] = page
        page[addr & PAGE_MASK] = value & 0xFF

    def write_u16(self, addr: int, value: int) -> None:
        addr &= MASK32
        if (addr & PAGE_MASK) <= PAGE_SIZE - 2:
            page_no = addr >> PAGE_BITS
            page = self._pages.get(page_no)
            if page is None:
                page = bytearray(PAGE_SIZE)
                self._pages[page_no] = page
            off = addr & PAGE_MASK
            page[off] = value & 0xFF
            page[off + 1] = (value >> 8) & 0xFF
            return
        self.write_u8(addr, value)
        self.write_u8(addr + 1, value >> 8)

    def write_u32(self, addr: int, value: int) -> None:
        addr &= MASK32
        if (addr & PAGE_MASK) <= PAGE_SIZE - 4:
            page_no = addr >> PAGE_BITS
            page = self._pages.get(page_no)
            if page is None:
                page = bytearray(PAGE_SIZE)
                self._pages[page_no] = page
            off = addr & PAGE_MASK
            page[off] = value & 0xFF
            page[off + 1] = (value >> 8) & 0xFF
            page[off + 2] = (value >> 16) & 0xFF
            page[off + 3] = (value >> 24) & 0xFF
            return
        self.write_u8(addr, value)
        self.write_u8(addr + 1, value >> 8)
        self.write_u8(addr + 2, value >> 16)
        self.write_u8(addr + 3, value >> 24)


def sext(value: int, bits: int) -> int:
    sign = 1 << (bits - 1)
    value &= (1 << bits) - 1
    return (value ^ sign) - sign


def u32(value: int) -> int:
    return value & MASK32


def s32(value: int) -> int:
    value &= MASK32
    return value if value < 0x80000000 else value - 0x100000000
