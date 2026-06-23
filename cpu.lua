local bit = require("bit")
local MMU = require("mmu")

local CPU = {
    -- 8-битные регистры
    a = 0, f = 0,
    b = 0, c = 0,
    d = 0, e = 0,
    h = 0, l = 0,
    -- 16-битные указатели
    pc = 0x0100,
    sp = 0xFFFE,

    -- Прерывания и состояния
    ime = true,          
    halted = false,      
    halted_by_error = false,
    error_message = ""
}

-- Константы флагов
local FLAG_Z = 0x80
local FLAG_N = 0x40
local FLAG_H = 0x20
local FLAG_C = 0x10

-- Управление флагами
function CPU.setFlag(flag, condition)
    if condition then CPU.f = bit.bor(CPU.f, flag) else CPU.f = bit.band(CPU.f, bit.bnot(flag)) end
end
function CPU.getFlag(flag) return bit.band(CPU.f, flag) ~= 0 end

-- Работа с 16-битными регистрами
function CPU.getBC() return bit.bor(bit.lshift(CPU.b, 8), CPU.c) end
function CPU.setBC(val) CPU.b = bit.band(bit.rshift(val, 8), 0xFF) CPU.c = bit.band(val, 0xFF) end
function CPU.getDE() return bit.bor(bit.lshift(CPU.d, 8), CPU.e) end
function CPU.setDE(val) CPU.d = bit.band(bit.rshift(val, 8), 0xFF) CPU.e = bit.band(val, 0xFF) end
function CPU.getHL() return bit.bor(bit.lshift(CPU.h, 8), CPU.l) end
function CPU.setHL(val) CPU.h = bit.band(bit.rshift(val, 8), 0xFF) CPU.l = bit.band(val, 0xFF) end

-- Чтение 16-битного слова (Little Endian)
local function readWord(addr)
    return bit.bor(bit.lshift(MMU.readByte(addr + 1), 8), MMU.readByte(addr))
end

-- Запись 16-битного слова в стек
local function pushWord(val)
    CPU.sp = bit.band(CPU.sp - 1, 0xFFFF)
    MMU.writeByte(CPU.sp, bit.band(bit.rshift(val, 8), 0xFF))
    CPU.sp = bit.band(CPU.sp - 1, 0xFFFF)
    MMU.writeByte(CPU.sp, bit.band(val, 0xFF))
end

-- Чтение 16-битного слова из стека
local function popWord()
    local low = MMU.readByte(CPU.sp)
    CPU.sp = bit.band(CPU.sp + 1, 0xFFFF)
    local high = MMU.readByte(CPU.sp)
    CPU.sp = bit.band(CPU.sp + 1, 0xFFFF)
    return bit.bor(bit.lshift(high, 8), low)
end

-- Вспомогательные таблицы для автоматизации групп опкодов
local getReg = {
    function() return CPU.b end, 
    function() return CPU.c end, 
    function() return CPU.d end, 
    function() return CPU.e end, 
    function() return CPU.h end, 
    function() return CPU.l end, 
    function() return MMU.readByte(CPU.getHL()) end, 
    function() return CPU.a end
}

local setReg = {
    function(v) CPU.b = v end,
    function(v) CPU.c = v end,
    function(v) CPU.d = v end,
    function(v) CPU.e = v end,
    function(v) CPU.h = v end,
    function(v) CPU.l = v end,
    function(v) MMU.writeByte(CPU.getHL(), v) end,
    function(v) CPU.a = v end
}

local pairsGet = { CPU.getBC, CPU.getDE, CPU.getHL, function() return CPU.sp end }
local pairsSet = { CPU.setBC, CPU.setDE, CPU.setHL, function(v) CPU.sp = v end }

local pairsStackSet = { 
    CPU.setBC, 
    CPU.setDE, 
    CPU.setHL, 
    function(v) 
        CPU.a = bit.band(bit.rshift(v, 8), 0xFF) 
        CPU.f = bit.band(v, 0xF0) 
    end 
}

local ccCheck = { 
    function() return not CPU.getFlag(FLAG_Z) end, 
    function() return CPU.getFlag(FLAG_Z) end, 
    function() return not CPU.getFlag(FLAG_C) end, 
    function() return CPU.getFlag(FLAG_C) end 
}

-- Главный массив опкодов
local opcodes = {}
for i = 0, 255 do opcodes[i] = function() error(string.format("Opcode 0x%02X not wired", i)) end end

-- Оставляем место для подгрузки остальных частей кода
-- 1. Группа опкодов загрузки (LD r, r') — всего 64 штуки (0x40 - 0x7F)
for r = 0, 7 do
    for r_prime = 0, 7 do
        local op = 0x40 + (r * 8) + r_prime
        if op ~= 0x76 then -- Кроме HALT
            opcodes[op] = function()
                local val = getReg[r_prime + 1]()
                setReg[r + 1](val)
                return (r == 6 or r_prime == 6) and 8 or 4
            end
        end
    end
end

-- Вспомогательные функции для вычислений
local function do_add(v, c)
    local carry = c and (CPU.getFlag(FLAG_C) and 1 or 0) or 0
    local res = CPU.a + v + carry
    CPU.setFlag(FLAG_H, bit.band(CPU.a, 0x0F) + bit.band(v, 0x0F) + carry > 0x0F)
    CPU.setFlag(FLAG_C, res > 0xFF)
    CPU.a = bit.band(res, 0xFF)
    CPU.setFlag(FLAG_Z, CPU.a == 0)
    CPU.setFlag(FLAG_N, false)
end

local function do_sub(v, c)
    local carry = c and (CPU.getFlag(FLAG_C) and 1 or 0) or 0
    local res = CPU.a - v - carry
    CPU.setFlag(FLAG_H, bit.band(CPU.a, 0x0F) - bit.band(v, 0x0F) - carry < 0)
    CPU.setFlag(FLAG_C, res < 0)
    CPU.a = bit.band(res, 0xFF)
    CPU.setFlag(FLAG_Z, CPU.a == 0)
    CPU.setFlag(FLAG_N, true)
end

-- 2. Группа опкодов 8-битной арифметики — еще 64 штуки (0x80 - 0xBF)
for r = 0, 7 do
    opcodes[0x80 + r] = function() do_add(getReg[r + 1](), false) return r==6 and 8 or 4 end -- ADD
    opcodes[0x88 + r] = function() do_add(getReg[r + 1](), true) return r==6 and 8 or 4 end  -- ADC
    opcodes[0x90 + r] = function() do_sub(getReg[r + 1](), false) return r==6 and 8 or 4 end -- SUB
    opcodes[0x98 + r] = function() do_sub(getReg[r + 1](), true) return r==6 and 8 or 4 end  -- SBC
    opcodes[0xA0 + r] = function() CPU.a = bit.band(CPU.a, getReg[r + 1]()) CPU.setFlag(FLAG_Z, CPU.a==0) CPU.setFlag(FLAG_N, false) CPU.setFlag(FLAG_H, true) CPU.setFlag(FLAG_C, false) return r==6 and 8 or 4 end -- AND
    opcodes[0xA8 + r] = function() CPU.a = bit.bxor(CPU.a, getReg[r + 1]()) CPU.setFlag(FLAG_Z, CPU.a==0) CPU.setFlag(FLAG_N, false) CPU.setFlag(FLAG_H, false) CPU.setFlag(FLAG_C, false) return r==6 and 8 or 4 end -- XOR
    opcodes[0xB0 + r] = function() CPU.a = bit.bor(CPU.a, getReg[r + 1]()) CPU.setFlag(FLAG_Z, CPU.a==0) CPU.setFlag(FLAG_N, false) CPU.setFlag(FLAG_H, false) CPU.setFlag(FLAG_C, false) return r==6 and 8 or 4 end  -- OR
    opcodes[0xB8 + r] = function() -- CP (Сравнение)
        local v = getReg[r + 1]()
        CPU.setFlag(FLAG_Z, CPU.a == v)
        CPU.setFlag(FLAG_N, true)
        CPU.setFlag(FLAG_H, bit.band(CPU.a, 0x0F) < bit.band(v, 0x0F))
        CPU.setFlag(FLAG_C, CPU.a < v)
        return r==6 and 8 or 4
    end
end

-- 1. Специфические одиночные инструкции
opcodes[0x00] = function() return 4 end -- NOP
opcodes[0x76] = function() CPU.halted = true return 4 end -- HALT
opcodes[0xF3] = function() CPU.ime = false return 4 end -- DI
opcodes[0xFB] = function() CPU.ime = true return 4 end  -- EI

-- 2. Загрузки и инкременты 16-битных пар регистров
for i = 0, 3 do
    opcodes[0x01 + i*16] = function() pairsSet[i + 1](readWord(CPU.pc)) CPU.pc = CPU.pc + 2 return 12 end
    opcodes[0x03 + i*16] = function() pairsSet[i + 1](bit.band(pairsGet[i + 1]() + 1, 0xFFFF)) return 8 end
    opcodes[0x0B + i*16] = function() pairsSet[i + 1](bit.band(pairsGet[i + 1]() - 1, 0xFFFF)) return 8 end
end

-- 3. 8-битные инкременты и декременты (INC r / DEC r)
for r = 0, 7 do
    opcodes[0x04 + r*8] = function()
        local v = bit.band(getReg[r + 1]() + 1, 0xFF)
        setReg[r + 1](v)
        CPU.setFlag(FLAG_Z, v == 0)
        CPU.setFlag(FLAG_N, false)
        CPU.setFlag(FLAG_H, bit.band(v, 0x0F) == 0)
        return r == 6 and 12 or 4
    end
    opcodes[0x05 + r*8] = function()
        local v = bit.band(getReg[r + 1]() - 1, 0xFF)
        setReg[r + 1](v)
        CPU.setFlag(FLAG_Z, v == 0)
        CPU.setFlag(FLAG_N, true)
        CPU.setFlag(FLAG_H, bit.band(v, 0x0F) == 0x0F)
        return r == 6 and 12 or 4
    end
    opcodes[0x06 + r*8] = function()
        setReg[r + 1](MMU.readByte(CPU.pc))
        CPU.pc = CPU.pc + 1
        return r == 6 and 12 or 8
    end
end

-- 4. Относительные переходы JR
opcodes[0x18] = function() 
    local s = MMU.readByte(CPU.pc) CPU.pc = CPU.pc + 1 
    if s >= 128 then s = s - 256 end 
    CPU.pc = CPU.pc + s return 12 
end
for i = 0, 3 do
    opcodes[0x20 + i*8] = function()
        local s = MMU.readByte(CPU.pc) CPU.pc = CPU.pc + 1 
        if s >= 128 then s = s - 256 end
        if ccCheck[i + 1]() then CPU.pc = CPU.pc + s return 12 end
        return 8
    end
end

-- 5. Абсолютные переходы JP, CALL и RET
opcodes[0xC3] = function() CPU.pc = readWord(CPU.pc) return 16 end
opcodes[0xC9] = function() CPU.pc = popWord() return 16 end
opcodes[0xCD] = function() 
    local n = readWord(CPU.pc) CPU.pc = CPU.pc + 2 
    pushWord(CPU.pc) CPU.pc = n return 24 
end

for i = 0, 3 do
    opcodes[0xC2 + i*8] = function() local n = readWord(CPU.pc) CPU.pc = CPU.pc + 2 if ccCheck[i + 1]() then CPU.pc = n return 16 end return 12 end
    opcodes[0xC4 + i*8] = function() local n = readWord(CPU.pc) CPU.pc = CPU.pc + 2 if ccCheck[i + 1]() then pushWord(CPU.pc) CPU.pc = n return 24 end return 12 end
    opcodes[0xC0 + i*8] = function() if ccCheck[i + 1]() then CPU.pc = popWord() return 20 end return 8 end
end

-- 6. Работа со стеком PUSH / POP
for i = 0, 3 do
    opcodes[0xC1 + i*16] = function() pairsStackSet[i + 1](popWord()) return 12 end
    opcodes[0xC5 + i*16] = function() pushWord(i == 3 and bit.bor(bit.lshift(CPU.a, 8), CPU.f) or pairsGet[i + 1]()) return 16 end
end

-- 7. Команды быстрого ввода-вывода (LDH) и запись аккумулятора
opcodes[0xE0] = function() MMU.writeByte(0xFF00 + MMU.readByte(CPU.pc), CPU.a) CPU.pc = CPU.pc + 1 return 12 end
opcodes[0xF0] = function() CPU.a = MMU.readByte(0xFF00 + MMU.readByte(CPU.pc)) CPU.pc = CPU.pc + 1 return 12 end
opcodes[0xE2] = function() MMU.writeByte(0xFF00 + CPU.c, CPU.a) return 8 end
opcodes[0xF2] = function() CPU.a = MMU.readByte(0xFF00 + CPU.c) return 8 end
opcodes[0xEA] = function() MMU.writeByte(readWord(CPU.pc), CPU.a) CPU.pc = CPU.pc + 2 return 16 end
opcodes[0xFA] = function() CPU.a = MMU.readByte(readWord(CPU.pc)) CPU.pc = CPU.pc + 2 return 16 end

opcodes[0x02] = function() MMU.writeByte(CPU.getBC(), CPU.a) return 8 end
opcodes[0x12] = function() MMU.writeByte(CPU.getDE(), CPU.a) return 8 end
opcodes[0x0A] = function() CPU.a = MMU.readByte(CPU.getBC()) return 8 end
opcodes[0x1A] = function() CPU.a = MMU.readByte(CPU.getDE()) return 8 end

opcodes[0x22] = function() local hl = CPU.getHL() MMU.writeByte(hl, CPU.a) CPU.setHL(hl + 1) return 8 end
opcodes[0x32] = function() local hl = CPU.getHL() MMU.writeByte(hl, CPU.a) CPU.setHL(hl - 1) return 8 end
opcodes[0x2A] = function() local hl = CPU.getHL() CPU.a = MMU.readByte(hl) CPU.setHL(hl + 1) return 8 end
opcodes[0x3A] = function() local hl = CPU.getHL() CPU.a = MMU.readByte(hl) CPU.setHL(hl - 1) return 8 end
-- 1. Непосредственные вызовы арифметики (ADD A, d8; SUB d8 и т.д.)
opcodes[0xC6] = function() do_add(MMU.readByte(CPU.pc), false) CPU.pc = CPU.pc + 1 return 8 end
opcodes[0xCE] = function() do_add(MMU.readByte(CPU.pc), true) CPU.pc = CPU.pc + 1 return 8 end
opcodes[0xD6] = function() do_sub(MMU.readByte(CPU.pc), false) CPU.pc = CPU.pc + 1 return 8 end
opcodes[0xDE] = function() do_sub(MMU.readByte(CPU.pc), true) CPU.pc = CPU.pc + 1 return 8 end
opcodes[0xE6] = function() CPU.a = bit.band(CPU.a, MMU.readByte(CPU.pc)) CPU.pc = CPU.pc + 1 CPU.setFlag(FLAG_Z, CPU.a==0) CPU.setFlag(FLAG_N, false) CPU.setFlag(FLAG_H, true) CPU.setFlag(FLAG_C, false) return 8 end
opcodes[0xEE] = function() CPU.a = bit.bxor(CPU.a, MMU.readByte(CPU.pc)) CPU.pc = CPU.pc + 1 CPU.setFlag(FLAG_Z, CPU.a==0) CPU.setFlag(FLAG_N, false) CPU.setFlag(FLAG_H, false) CPU.setFlag(FLAG_C, false) return 8 end
opcodes[0xF6] = function() CPU.a = bit.bor(CPU.a, MMU.readByte(CPU.pc)) CPU.pc = CPU.pc + 1 CPU.setFlag(FLAG_Z, CPU.a==0) CPU.setFlag(FLAG_N, false) CPU.setFlag(FLAG_H, false) CPU.setFlag(FLAG_C, false) return 8 end
opcodes[0xFE] = function() local v = MMU.readByte(CPU.pc) CPU.pc = CPU.pc + 1 CPU.setFlag(FLAG_Z, CPU.a == v) CPU.setFlag(FLAG_N, true) CPU.setFlag(FLAG_H, bit.band(CPU.a, 0x0F) < bit.band(v, 0x0F)) CPU.setFlag(FLAG_C, CPU.a < v) return 8 end

-- 2. Команды перезагрузки процессора RST и выход из прерываний RETI
for i = 0, 7 do opcodes[0xC7 + i*8] = function() pushWord(CPU.pc) CPU.pc = i * 8 return 16 end end
opcodes[0xD9] = function() CPU.pc = popWord() CPU.ime = true return 16 end

-- 3. Сдвиги аккумулятора, инверсия флагов и DAA (десятичная коррекция для Тетриса)
opcodes[0x07] = function() local c = bit.band(CPU.a, 0x80) ~= 0 CPU.a = bit.band(bit.bor(bit.lshift(CPU.a, 1), c and 1 or 0), 0xFF) CPU.f = 0 CPU.setFlag(FLAG_C, c) return 4 end
opcodes[0x17] = function() local c = bit.band(CPU.a, 0x80) ~= 0 local old_c = CPU.getFlag(FLAG_C) and 1 or 0 CPU.a = bit.band(bit.bor(bit.lshift(CPU.a, 1), old_c), 0xFF) CPU.f = 0 CPU.setFlag(FLAG_C, c) return 4 end
opcodes[0x0F] = function() local c = bit.band(CPU.a, 0x01) ~= 0 CPU.a = bit.band(bit.bor(bit.rshift(CPU.a, 1), c and 0x80 or 0), 0xFF) CPU.f = 0 CPU.setFlag(FLAG_C, c) return 4 end
opcodes[0x1F] = function() local c = bit.band(CPU.a, 0x01) ~= 0 local old_c = CPU.getFlag(FLAG_C) and 0x80 or 0 CPU.a = bit.band(bit.bor(bit.rshift(CPU.a, 1), old_c), 0xFF) CPU.f = 0 CPU.setFlag(FLAG_C, c) return 4 end
opcodes[0x2F] = function() CPU.a = bit.band(bit.bnot(CPU.a), 0xFF) CPU.setFlag(FLAG_N, true) CPU.setFlag(FLAG_H, true) return 4 end
opcodes[0x3F] = function() CPU.setFlag(FLAG_N, false) CPU.setFlag(FLAG_H, false) CPU.setFlag(FLAG_C, not CPU.getFlag(FLAG_C)) return 4 end
opcodes[0x37] = function() CPU.setFlag(FLAG_N, false) CPU.setFlag(FLAG_H, false) CPU.setFlag(FLAG_C, true) return 4 end
opcodes[0x27] = function()
    local a = CPU.a
    if not CPU.getFlag(FLAG_N) then
        if CPU.getFlag(FLAG_H) or bit.band(a, 0x0F) > 9 then a = a + 0x06 end
        if CPU.getFlag(FLAG_C) or a > 0x9F then a = a + 0x60 CPU.setFlag(FLAG_C, true) end
    else
        if CPU.getFlag(FLAG_H) then a = bit.band(a - 6, 0xFF) end
        if CPU.getFlag(FLAG_C) then a = a - 0x60 end
    end
    CPU.a = bit.band(a, 0xFF) CPU.setFlag(FLAG_Z, CPU.a == 0) CPU.setFlag(FLAG_H, false) return 4
end

-------------------------------------------------------------------
-- ГЕНЕРАЦИЯ ВТОРОЙ ТАБЛИЦЫ: PREFIX CB (Исправлено!)
-------------------------------------------------------------------
local opcodes_CB = {}
local function cb_get(r) return getReg[r + 1]() end
local function cb_set(r, v) setReg[r + 1](bit.band(v, 0xFF)) end

for r = 0, 7 do
    for b = 0, 7 do
        -- Проверки битов (BIT b, r)
        opcodes_CB[0x40 + b*8 + r] = function()
            local bit_set = bit.band(cb_get(r), bit.lshift(1, b)) ~= 0
            CPU.setFlag(FLAG_Z, not bit_set) CPU.setFlag(FLAG_N, false) CPU.setFlag(FLAG_H, true)
            return r == 6 and 12 or 8
        end
        -- Сброс битов (RES b, r)
        opcodes_CB[0x80 + b*8 + r] = function() cb_set(r, bit.band(cb_get(r), bit.bnot(bit.lshift(1, b)))) return r == 6 and 16 or 8 end
        -- Установка битов (SET b, r)
        opcodes_CB[0xC0 + b*8 + r] = function() cb_set(r, bit.bor(cb_get(r), bit.lshift(1, b))) return r == 6 and 16 or 8 end
    end

    -- Битовые сдвиги и SWAP (Все группы добавлены корректно!)
    opcodes_CB[0x00 + r] = function() local v = cb_get(r) local c = bit.band(v, 0x80) ~= 0 v = bit.bor(bit.lshift(v, 1), c and 1 or 0) cb_set(r, v) CPU.f = 0 CPU.setFlag(FLAG_Z, bit.band(v,0xFF)==0) CPU.setFlag(FLAG_C, c) return r==6 and 15 or 8 end
    opcodes_CB[0x08 + r] = function() local v = cb_get(r) local c = bit.band(v, 0x01) ~= 0 v = bit.bor(bit.rshift(v, 1), c and 0x80 or 0) cb_set(r, v) CPU.f = 0 CPU.setFlag(FLAG_Z, bit.band(v,0xFF)==0) CPU.setFlag(FLAG_C, c) return r==6 and 15 or 8 end
    opcodes_CB[0x10 + r] = function() local v = cb_get(r) local c = bit.band(v, 0x80) ~= 0 local old_c = CPU.getFlag(FLAG_C) and 1 or 0 v = bit.bor(bit.lshift(v, 1), old_c) cb_set(r, v) CPU.f = 0 CPU.setFlag(FLAG_Z, bit.band(v,0xFF)==0) CPU.setFlag(FLAG_C, c) return r==6 and 15 or 8 end
    opcodes_CB[0x18 + r] = function() local v = cb_get(r) local c = bit.band(v, 0x01) ~= 0 local old_c = CPU.getFlag(FLAG_C) and 0x80 or 0 v = bit.bor(bit.rshift(v, 1), old_c) cb_set(r, v) CPU.f = 0 CPU.setFlag(FLAG_Z, bit.band(v,0xFF)==0) CPU.setFlag(FLAG_C, c) return r==6 and 15 or 8 end
    
    -- SLA r
    opcodes_CB[0x20 + r] = function() local v = cb_get(r) local c = bit.band(v, 0x80) ~= 0 v = bit.lshift(v, 1) cb_set(r, v) CPU.f = 0 CPU.setFlag(FLAG_Z, bit.band(v,0xFF)==0) CPU.setFlag(FLAG_C, c) return r==6 and 15 or 8 end
    -- SRA r
    opcodes_CB[0x28 + r] = function() local v = cb_get(r) local c = bit.band(v, 0x01) ~= 0 local sign = bit.band(v, 0x80) v = bit.bor(bit.rshift(v, 1), sign) cb_set(r, v) CPU.f = 0 CPU.setFlag(FLAG_Z, bit.band(v,0xFF)==0) CPU.setFlag(FLAG_C, c) return r==6 and 15 or 8 end
    
    -- SWAP r (Половинки байта меняются местами)
    opcodes_CB[0x30 + r] = function()
        local v = cb_get(r)
        local low = bit.band(v, 0x0F)
        local high = bit.band(v, 0xF0)
        local res = bit.bor(bit.lshift(low, 4), bit.rshift(high, 4))
        cb_set(r, res)
        CPU.f = 0
        CPU.setFlag(FLAG_Z, res == 0)
        return r==6 and 15 or 8
    end
    
    -- SRL r
    opcodes_CB[0x38 + r] = function() local v = cb_get(r) local c = bit.band(v, 0x01) ~= 0 v = bit.rshift(v, 1) cb_set(r, v) CPU.f = 0 CPU.setFlag(FLAG_Z, v==0) CPU.setFlag(FLAG_C, c) return r==6 and 15 or 8 end
end

-- Исправленная фиксация опкодов 0x08 и префикса CB
opcodes[0x08] = function() 
    local addr = readWord(CPU.pc) CPU.pc = CPU.pc + 2 
    MMU.writeByte(addr, bit.band(CPU.sp, 0xFF)) 
    MMU.writeByte(addr + 1, bit.band(bit.rshift(CPU.sp, 8), 0xFF)) 
    return 20 
end

opcodes[0x10] = function() CPU.halted = true CPU.pc = CPU.pc + 1 return 4 end -- STOP

opcodes[0xCB] = function()
    local cb_op = MMU.readByte(CPU.pc)
    CPU.pc = CPU.pc + 1
    local func = opcodes_CB[cb_op]
    if func then return func() else error(string.format("Unknown CB opcode 0x%02X", cb_op)) end
end

    -- 16-битное сложение (ADD HL, BC/DE/HL/SP)
for i = 0, 3 do
    opcodes[0x09 + i*16] = function()
        local hl = CPU.getHL()
        local val = pairsGet[i + 1]()
        local res = hl + val
        
        CPU.setFlag(FLAG_N, false)
        CPU.setFlag(FLAG_H, bit.band(hl, 0x0FFF) + bit.band(val, 0x0FFF) > 0x0FFF)
        CPU.setFlag(FLAG_C, res > 0xFFFF)
        
        CPU.setHL(bit.band(res, 0xFFFF))
        return 8
    end
end



-- [0xE9] JP (HL): Прыгнуть по адресу, записанному в HL
opcodes[0xE9] = function()
    CPU.pc = CPU.getHL()
    return 4
end

-------------------------------------------------------------------
-- ГЛАВНЫЙ ШАГ СИМУЛЯЦИИ
-------------------------------------------------------------------


function CPU.step()
    if CPU.halted then return 4 end



    local current_pc = CPU.pc
    local opcode = MMU.readByte(CPU.pc)
    CPU.pc = CPU.pc + 1

    local func = opcodes[opcode]
    if func then
        return func()
    else
        error(string.format("Unknown opcode 0x%02X at PC 0x%04X", opcode, current_pc))
    end
end

return CPU
