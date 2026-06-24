if jit then jit.on() jit.opt.start("hotloop=10", "hotexit=2") end

local MMU = require("mmu")
local CPU = require("cpu")
local PPU = require("ppu")
local Joypad = require("joypad")
local APU = require("apu")

-- Быстрые локальные ссылки для критического цикла процессора
local cpu_step = CPU.step
local mmu_read = MMU.readByte
local mmu_write = MMU.writeByte
local ppu_render = PPU.renderLine

local STATE_MENU = 1
local STATE_EMU = 2
local current_state = STATE_MENU

local rom_list = {}
local selected_index = 1
local current_rom_filename = ""

function love.load()
    -- Включаем vsync для идеальной плавности кадров
    love.window.setMode(640, 576, { resizable = false, vsync = true })
    love.window.setTitle("Lua GB Emulator - ROM Selector")
    
    APU.init()

    local files = love.filesystem.getDirectoryItems("")
    for _, file in ipairs(files) do
        if file:match("%.gb$") then
            table.insert(rom_list, file)
        end
    end
end

local function startEmulation(filename)
    current_rom_filename = filename
    MMU.loadROM(filename)
    
    CPU.pc = 0x0100
    CPU.sp = 0xFFFE
    CPU.a = 0; CPU.f = 0; CPU.b = 0; CPU.c = 0; CPU.d = 0; CPU.e = 0; CPU.h = 0; CPU.l = 0
    CPU.ime = true
    CPU.halted = false
    CPU.halted_by_error = false
    
    mmu_write(0xFF40, 0x91)
    mmu_write(0xFF47, 0xFC)
    mmu_write(0xFF44, 0x00)

    current_state = STATE_EMU
    love.window.setTitle("Playing: " .. filename)
end

-- Вспомогательная функция физической записи файла быстрого сохранения (Save State)
local function executeSave()
    local cpuState = {
        a = CPU.a, f = CPU.f, b = CPU.b, c = CPU.c,
        d = CPU.d, e = CPU.e, h = CPU.h, l = CPU.l,
        pc = CPU.pc, sp = CPU.sp, ime = CPU.ime and 1 or 0,
        halted = CPU.halted and 1 or 0
    }
    
    local mmuData = MMU.saveState()
    
    -- Упаковываем состояние процессора в текстовый заголовок в начале файла
    local cpuHeader = string.format("%02X|%02X|%02X|%02X|%02X|%02X|%02X|%02X|%04X|%04X|%d|%d\n",
        cpuState.a, cpuState.f, cpuState.b, cpuState.c,
        cpuState.d, cpuState.e, cpuState.h, cpuState.l,
        cpuState.pc, cpuState.sp, cpuState.ime, cpuState.halted
    )
    
    local save_name = current_rom_filename:gsub("%.gb$", "") .. ".state"
    local success = love.filesystem.write(save_name, cpuHeader .. mmuData)
    if success then
        print("Save State успешно создан: " .. save_name)
    end
end

-- Вспомогательная функция чтения файла быстрого сохранения (Load State)
local function executeLoad()
    local save_name = current_rom_filename:gsub("%.gb$", "") .. ".state"
    if love.filesystem.getInfo(save_name) then
        local fileData = love.filesystem.read(save_name)
        local newlineIndex = fileData:find("\n")
        
        if newlineIndex then
            local header = fileData:sub(1, newlineIndex - 1)
            local mmuData = fileData:sub(newlineIndex + 1)
            
            -- Восстанавливаем массивы оперативной памяти через MMU
            local mmuSuccess = MMU.loadState(mmuData)
            
            if mmuSuccess then
                -- Восстанавливаем внутреннее состояние регистров процессора
                local parts = {}
                for token in string.gmatch(header, "[^|]+") do
                    table.insert(parts, token)
                end
                
                CPU.a = tonumber(parts[1], 16)
                CPU.f = tonumber(parts[2], 16)
                CPU.b = tonumber(parts[3], 16)
                CPU.c = tonumber(parts[4], 16)
                CPU.d = tonumber(parts[5], 16)
                CPU.e = tonumber(parts[6], 16)
                CPU.h = tonumber(parts[7], 16)
                CPU.l = tonumber(parts[8], 16)
                CPU.pc = tonumber(parts[9], 16)
                CPU.sp = tonumber(parts[10], 16)
                CPU.ime = (tonumber(parts[11]) == 1)
                CPU.halted = (tonumber(parts[12]) == 1)
                
                print("Save State успешно загружен!")
            end
        end
    else
        print("Файл сохранения не найден!")
    end
end

local function handleInterrupts()
    local flag = mmu_read(0xFF0F)
    local enable = mmu_read(0xFFFF)
    local triggered = bit.band(flag, enable)

    if triggered > 0 then
        CPU.halted = false 
        if CPU.ime then
            for bit_idx = 0, 4 do
                local mask = bit.lshift(1, bit_idx)
                if bit.band(triggered, mask) ~= 0 then
                    CPU.ime = false
                    mmu_write(0xFF0F, bit.band(flag, bit.bnot(mask)))
                    
                    local high = bit.band(bit.rshift(CPU.pc, 8), 0xFF)
                    local low = bit.band(CPU.pc, 0xFF)
                    CPU.sp = bit.band(CPU.sp - 1, 0xFFFF)
                    mmu_write(CPU.sp, high)
                    CPU.sp = bit.band(CPU.sp - 1, 0xFFFF)
                    mmu_write(CPU.sp, low)
                    
                    CPU.pc = 0x0040 + (bit_idx * 8)
                    break
                end
            end
        end
    end
end

function love.update(dt)
    if current_state == STATE_MENU then return end
    if CPU.halted_by_error then return end

    -- Жестко ограничиваем шаг времени во избежание зависаний (макс 30 FPS на шаг)
    if dt > 0.033 then dt = 0.033 end

    -- Рассчитываем точное количество тактов процессора для текущей дельты времени (4.194304 МГц)
    local cycles_to_run = math.floor(4194304 * dt)
    local cycles_spent = 0
    
    local current_ly = mmu_read(0xFF44)
    local line_cycles = 0

    while cycles_spent < cycles_to_run do
        handleInterrupts()
        
        -- Прямой вызов без pcall ради максимальной скорости (Full 60 FPS)
        local cycles = cpu_step() or 4
        cycles_spent = cycles_spent + cycles
        line_cycles = line_cycles + cycles

        local stat = mmu_read(0xFF41)
        if current_ly >= 144 then stat = bit.bor(bit.band(stat, 0xFC), 1)
        elseif line_cycles < 80 then stat = bit.bor(bit.band(stat, 0xFC), 2)
        elseif line_cycles < 252 then stat = bit.bor(bit.band(stat, 0xFC), 3)
        else stat = bit.band(stat, 0xFC) end
        mmu_write(0xFF41, stat)

        if line_cycles >= 456 then
            -- Опрашиваем джойпад один раз на отрисовку строки, а не на каждый такт
            Joypad.update()

            line_cycles = line_cycles - 456
            current_ly = current_ly + 1
            if current_ly == 144 then
                local flag = mmu_read(0xFF0F)
                mmu_write(0xFF0F, bit.bor(flag, 1))
            elseif current_ly > 153 then
                current_ly = 0
            end
            mmu_write(0xFF44, current_ly)
            if current_ly <= 143 then ppu_render(current_ly) end
        end
    end

    if current_state == STATE_EMU then
        APU.generateFrameAudio()
    end
end

function love.draw()
    if current_state == STATE_MENU then
        love.graphics.clear(0.08, 0.12, 0.08)
        love.graphics.setColor(0.3, 0.8, 0.3)
        love.graphics.printf("LUA GAME BOY EMULATOR", 0, 40, 640, "center", 0, 1.5, 1.5, 213)
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.printf("Select a game using UP/DOWN and press ENTER to play", 0, 90, 640, "center")
        
        love.graphics.setColor(0.15, 0.22, 0.15)
        love.graphics.rectangle("fill", 50, 130, 540, 360, 10, 10)

        if #rom_list == 0 then
            love.graphics.setColor(0.8, 0.3, 0.3)
            love.graphics.printf("NO .GB GAMES FOUND IN PROJECT FOLDER!", 0, 280, 640, "center")
        else
            for i, rom in ipairs(rom_list) do
                local y_pos = 150 + (i * 30)
                if i == selected_index then
                    love.graphics.setColor(0.3, 1, 0.3)
                    love.graphics.rectangle("fill", 60, y_pos - 4, 520, 24, 4, 4)
                    love.graphics.setColor(0, 0, 0)
                    love.graphics.print("> " .. rom, 70, y_pos)
                else
                    love.graphics.setColor(0.6, 0.8, 0.6)
                    love.graphics.print("  " .. rom, 70, y_pos)
                end
            end
        end
        love.graphics.setColor(0.4, 0.4, 0.4)
        love.graphics.printf("Press ESC to exit", 0, 520, 640, "center")
    else
        love.graphics.clear(0.1, 0.1, 0.1)
        PPU.draw()
        if CPU.halted_by_error then
            love.graphics.setColor(0.8, 0.2, 0.2, 0.8)
            love.graphics.rectangle("fill", 10, 10, 620, 60)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print("CPU HALTED: " .. tostring(CPU.error_message), 20, 20)
            love.graphics.print("Press ESC to return to menu", 20, 45)
        end
    end
end

-- Обработка управления с клавиатуры ПК
function love.keypressed(key)
    if current_state == STATE_MENU then
        if key == "up" then
            selected_index = selected_index - 1
            if selected_index < 1 then selected_index = #rom_list end
        elseif key == "down" then
            selected_index = selected_index + 1
            if selected_index > #rom_list then selected_index = 1 end
        elseif key == "return" and #rom_list > 0 then
            startEmulation(rom_list[selected_index])
        elseif key == "escape" then
            love.event.quit()
        end
    else
        if key == "escape" then
            current_state = STATE_MENU
            love.window.setTitle("Lua GB Emulator - ROM Selector")
        elseif key == "f5" then
            executeSave()
        elseif key == "f6" then
            executeLoad()
        end
    end
end

-- Обработка управления с внешнего геймпада (XInput / Xbox / DualShock)
function love.gamepadpressed(joystick, button)
    if current_state == STATE_MENU then
        if button == "dpup" then
            selected_index = selected_index - 1
            if selected_index < 1 then selected_index = #rom_list end
        elseif button == "dpdown" then
            if selected_index > #rom_list then selected_index = 1 end
        elseif button == "a" and #rom_list > 0 then
            startEmulation(rom_list[selected_index])
        end
    else
        -- Горячие кнопки сохранения/загрузки для геймпада во время игры
        if joystick:isGamepadDown("leftshoulder") then -- Удерживаем L1
            if button == "y" then
                executeSave() -- L1 + Y -> Быстрое сохранение
            elseif button == "x" then
                executeLoad() -- L1 + X -> Быстрая загрузка
            end
        end
    end
end
