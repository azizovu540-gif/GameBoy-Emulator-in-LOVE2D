local bit = require("bit")

local MMU = {
    rom = {}, vram = {}, eram = {}, wram = {}, oam = {}, io = {}, hram = {},
    current_rom_bank = 1,
    current_ram_bank = 0,
    mbc_type = 0,
    eram_enabled = false,
    mbc1_mode = 0,
    rom_size = 0
}

function MMU.init()
    MMU.rom = {}
    MMU.current_rom_bank = 1
    MMU.current_ram_bank = 0
    MMU.mbc_type = 0
    MMU.eram_enabled = false
    MMU.mbc1_mode = 0
    MMU.rom_size = 0
    
    for i = 1, 0x2000 do MMU.vram[i] = 0 end
    -- Выделяем память под RAM с огромным запасом (128 КБ)
    for i = 1, 0x20000 do MMU.eram[i] = 0 end
    for i = 1, 0x2000 do MMU.wram[i] = 0 end
    for i = 1, 0xA0 do MMU.oam[i] = 0 end
    for i = 1, 0x80 do MMU.io[i] = 0 end
    for i = 1, 0x80 do MMU.hram[i] = 0 end
end

function MMU.readByte(addr)
    if addr >= 0x0000 and addr <= 0x3FFF then
        return MMU.rom[addr] or 0
    elseif addr >= 0x4000 and addr <= 0x7FFF then
        -- Защита от выхода за пределы памяти картриджа
        local max_banks = math.floor(MMU.rom_size / 0x4000)
        local bank = MMU.current_rom_bank
        if max_banks > 0 then bank = bank % max_banks end
        
        local bank_offset = bank * 0x4000
        local rom_addr = bank_offset + (addr - 0x4000)
        return MMU.rom[rom_addr] or 0
    elseif addr >= 0x8000 and addr <= 0x9FFF then
        return MMU.vram[bit.band(addr, 0x1FFF) + 1] or 0
    elseif addr >= 0xA000 and addr <= 0xBFFF then
        if not MMU.eram_enabled then return 0xFF end
        
        -- Авто-поддержка встроенной RAM для маппера MBC2
        if MMU.mbc_type == 0x05 or MMU.mbc_type == 0x06 then
            return bit.band(MMU.eram[bit.band(addr, 0x01FF) + 1] or 0, 0x0F)
        end
        
        local ram_offset = MMU.current_ram_bank * 0x2000
        local ram_addr = ram_offset + bit.band(addr, 0x1FFF) + 1
        return MMU.eram[ram_addr] or 0
    elseif addr >= 0xC000 and addr <= 0xDFFF then
        return MMU.wram[bit.band(addr, 0x1FFF) + 1] or 0
    elseif addr >= 0xE000 and addr <= 0xFDFF then
        return MMU.wram[bit.band(addr, 0x1FFF) + 1] or 0
    elseif addr >= 0xFE00 and addr <= 0xFE9F then
        return MMU.oam[bit.band(addr, 0xFF) + 1] or 0
    elseif addr >= 0xFF00 and addr <= 0xFF7F then
        if addr == 0xFF26 then 
            local APU = require("apu")
            local status = 0x70
            if APU.ch1_enabled then status = bit.bor(status, 0x01) end
            if APU.ch2_enabled then status = bit.bor(status, 0x02) end
            if APU.ch3_enabled then status = bit.bor(status, 0x04) end
            status = bit.bor(status, bit.band(MMU.io[(0xFF26 - 0xFF00) + 1] or 0, 0x80))
            return status
        end
        return MMU.io[(addr - 0xFF00) + 1] or 0
    elseif addr >= 0xFF80 and addr <= 0xFFFE then
        return MMU.hram[bit.band(addr, 0x7F) + 1] or 0
    elseif addr == 0xFFFF then
        return MMU.io[0x4F + 1] or 0
    end
    return 0
end

function MMU.writeByte(addr, value)
    value = bit.band(value, 0xFF)

    -- Если игра вообще без маппера (размер 32КБ), игнорируем любые попытки переключения банков
    if MMU.rom_size <= 0x8000 then
        -- Но позволяем стандартную запись в оперативку/видеопамять
        if addr >= 0x8000 then MMU.writeStandard(addr, value) end
        return
    end

    -- 1. Активация внешней оперативной памяти (0x0000 - 0x1FFF)
    if addr >= 0x0000 and addr <= 0x1FFF then
        if MMU.mbc_type == 0x05 or MMU.mbc_type == 0x06 then
            if bit.band(addr, 0x0100) == 0 then
                MMU.eram_enabled = (bit.band(value, 0x0F) == 0x0A)
            end
            return
        end
        MMU.eram_enabled = (bit.band(value, 0x0F) == 0x0A)
        return
    end

    -- 2. Переключение банков РОМа (0x2000 - 0x3FFF)
    if addr >= 0x2000 and addr <= 0x3FFF then
        -- Если это продвинутый MBC5
        if MMU.mbc_type >= 0x19 and MMU.mbc_type <= 0x1E then
            if addr <= 0x2FFF then
                MMU.current_rom_bank = bit.bor(bit.band(MMU.current_rom_bank, 0x0100), value)
            else
                local bit9 = bit.band(value, 0x01)
                MMU.current_rom_bank = bit.bor(bit.band(MMU.current_rom_bank, 0xFF), bit.lshift(bit9, 8))
            end
        else
            -- Универсальный переключатель для MBC1, MBC3 и всех неофициальных пиратских мапперов (включая Соника 0xEA)
            local bank = bit.band(value, 0x7F) -- Берем расширенную маску до 128 банков
            if bank == 0 then bank = 1 end
            MMU.current_rom_bank = bank
        end
        return
    end

    -- 3. Переключение банков оперативной памяти SRAM (0x4000 - 0x5FFF)
    if addr >= 0x4000 and addr <= 0x5FFF then
        if MMU.mbc_type >= 0x19 and MMU.mbc_type <= 0x1E then
            MMU.current_ram_bank = bit.band(value, 0x0F) -- MBC5 поддерживает до 16 банков RAM
        else
            -- Универсально для MBC1 и MBC3 (до 4 банков оперативной памяти)
            local bank = bit.band(value, 0x03)
            MMU.current_ram_bank = bank
            if MMU.mbc1_mode == 0 then
                MMU.current_rom_bank = bit.bor(bit.band(MMU.current_rom_bank, 0x1F), bit.lshift(bank, 5))
            end
        end
        return
    end

    -- 4. Переключение режимов работы (0x6000 - 0x7FFF)
    if addr >= 0x6000 and addr <= 0x7FFF then
        MMU.mbc1_mode = bit.band(value, 0x01)
        return
    end

    -- Запись во все остальные стандартные регистры
    MMU.writeStandard(addr, value)
end

-- Вспомогательная функция стандартной записи
function MMU.writeStandard(addr, value)
    if addr >= 0x8000 and addr <= 0x9FFF then
        MMU.vram[bit.band(addr, 0x1FFF) + 1] = value
    elseif addr >= 0xA000 and addr <= 0xBFFF then
        if MMU.eram_enabled then
            if MMU.mbc_type == 0x05 or MMU.mbc_type == 0x06 then
                MMU.eram[bit.band(addr, 0x01FF) + 1] = bit.band(value, 0x0F)
                return
            end
            local ram_offset = MMU.current_ram_bank * 0x2000
            local ram_addr = ram_offset + bit.band(addr, 0x1FFF) + 1
            MMU.eram[ram_addr] = value
        end
    elseif addr >= 0xC000 and addr <= 0xDFFF then
        MMU.wram[bit.band(addr, 0x1FFF) + 1] = value
    elseif addr >= 0xE000 and addr <= 0xFDFF then
        MMU.wram[bit.band(addr, 0x1FFF) + 1] = value
    elseif addr >= 0xFE00 and addr <= 0xFE9F then
        MMU.oam[bit.band(addr, 0xFF) + 1] = value
    elseif addr >= 0xFF00 and addr <= 0xFF7F then
        local io_addr = addr - 0xFF00
        MMU.io[io_addr + 1] = value
        
        if addr == 0xFF43 then
            MMU.io[0x43 + 1] = value
        elseif addr == 0xFF46 then
            local src_base = bit.lshift(value, 8)
            for i = 0, 0x9F do MMU.oam[i + 1] = MMU.readByte(src_base + i) end
        end
    elseif addr >= 0xFF80 and addr <= 0xFFFE then
        MMU.hram[bit.band(addr, 0x7F) + 1] = value
    elseif addr == 0xFFFF then
        MMU.io[0x4F + 1] = value
    end
end

function MMU.loadROM(filename)
    MMU.init()
    local data, size = love.filesystem.read(filename)
    if not data then error("ROM не найден: " .. filename) end
    
    MMU.rom_size = size
    for i = 1, size do MMU.rom[i - 1] = string.byte(data, i) end
    
    -- Считываем тип маппера
    local raw_mbc = MMU.rom[0x0147] or 0
    
    -- УМНАЯ АВТО-ПОДСТРОЙКА:
    -- Если игра большая (больше 32КБ), но заявляет мусорный тип маппера (как Соник 0xEA)
    -- или заявляет тип 0 (ROM ONLY), мы принудительно переводим её на универсальный MBC1,
    -- чтобы переключение банков физически работало и игра не зависала.
    if size > 0x8000 and (raw_mbc == 0 or raw_mbc == 0xEA or raw_mbc == 0x88) then
        MMU.mbc_type = 0x01 -- Включаем режим совместимости с MBC1
    else
        MMU.mbc_type = raw_mbc
    end
    
    print(string.format("ROM Загружен. Размер: %d байт. Режим маппера: 0x%02X", size, MMU.mbc_type))
end

return MMU
