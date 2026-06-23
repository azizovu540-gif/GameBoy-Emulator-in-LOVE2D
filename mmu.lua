local bit = require("bit")

local MMU = {
    rom = {}, vram = {}, eram = {}, wram = {}, oam = {}, io = {}, hram = {},
    current_rom_bank = 1,
    mbc_type = 0
}

function MMU.init()
    MMU.rom = {}
    MMU.current_rom_bank = 1
    MMU.mbc_type = 0
    for i = 0, 0x1FFF do MMU.vram[i] = 0 end
    for i = 0, 0x1FFF do MMU.eram[i] = 0 end
    for i = 0, 0x1FFF do MMU.wram[i] = 0 end
    for i = 0, 0x9F do MMU.oam[i] = 0 end
    for i = 0, 0x7F do MMU.io[i] = 0 end
    for i = 0, 0x7F do MMU.hram[i] = 0 end
end

function MMU.readByte(addr)
    if addr >= 0x0000 and addr <= 0x3FFF then
        return MMU.rom[addr] or 0
    elseif addr >= 0x4000 and addr <= 0x7FFF then
        local bank_offset = MMU.current_rom_bank * 0x4000
        local rom_addr = bank_offset + (addr - 0x4000)
        return MMU.rom[rom_addr] or 0
    elseif addr >= 0x8000 and addr <= 0x9FFF then
        return MMU.vram[bit.band(addr, 0x1FFF)]
    elseif addr >= 0xA000 and addr <= 0xBFFF then
        return MMU.eram[bit.band(addr, 0x1FFF)]
    elseif addr >= 0xC000 and addr <= 0xDFFF then
        return MMU.wram[bit.band(addr, 0x1FFF)]
    elseif addr >= 0xE000 and addr <= 0xFDFF then
        return MMU.wram[bit.band(addr, 0x1FFF)]
    elseif addr >= 0xFE00 and addr <= 0xFE9F then
        return MMU.oam[bit.band(addr, 0xFF)]
    elseif addr >= 0xFF00 and addr <= 0xFF7F then
        if addr == 0xFF26 then return 0xF1 end
        return MMU.io[addr - 0xFF00] or 0
    elseif addr >= 0xFF80 and addr <= 0xFFFE then
        return MMU.hram[bit.band(addr, 0x7F)]
    elseif addr == 0xFFFF then
        return MMU.io[0x4F]
    end
    return 0
end

function MMU.writeByte(addr, value)
    value = bit.band(value, 0xFF)

    if addr >= 0x2000 and addr <= 0x3FFF then
        if MMU.mbc_type > 0 then
            local bank = bit.band(value, 0x1F)
            if bank == 0 then bank = 1 end
            MMU.current_rom_bank = bank
            return
        end
    end

    if addr >= 0x8000 and addr <= 0x9FFF then
        MMU.vram[bit.band(addr, 0x1FFF)] = value
    elseif addr >= 0xA000 and addr <= 0xBFFF then
        MMU.eram[bit.band(addr, 0x1FFF)] = value
    elseif addr >= 0xC000 and addr <= 0xDFFF then
        MMU.wram[bit.band(addr, 0x1FFF)] = value
    elseif addr >= 0xE000 and addr <= 0xFDFF then
        MMU.wram[bit.band(addr, 0x1FFF)] = value
    elseif addr >= 0xFE00 and addr <= 0xFE9F then
        MMU.oam[bit.band(addr, 0xFF)] = value
    elseif addr >= 0xFF00 and addr <= 0xFF7F then
        local io_addr = addr - 0xFF00
        MMU.io[io_addr] = value
        
        -- Фиксация скроллинга
        if addr == 0xFF43 then
            MMU.io[0x43] = value
        elseif addr == 0xFF46 then
            local src_base = bit.lshift(value, 8)
            for i = 0, 0x9F do MMU.oam[i] = MMU.readByte(src_base + i) end
        end
    elseif addr >= 0xFF80 and addr <= 0xFFFE then
        MMU.hram[bit.band(addr, 0x7F)] = value
    elseif addr == 0xFFFF then
        MMU.io[0x4F] = value
    end
end

function MMU.loadROM(filename)
    MMU.init()
    local data, size = love.filesystem.read(filename)
    if not data then error("ROM не найден: " .. filename) end
    for i = 1, size do MMU.rom[i - 1] = string.byte(data, i) end
    MMU.mbc_type = MMU.rom[0x0147] or 0
    print(string.format("ROM Загружен. Размер: %d байт. Тип MBC: 0x%02X", size, MMU.mbc_type))
end

return MMU
