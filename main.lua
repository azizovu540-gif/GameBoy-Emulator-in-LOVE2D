local MMU = require("mmu")
local CPU = require("cpu")
local PPU = require("ppu")
local Joypad = require("joypad")
local APU = require("apu")

local STATE_MENU = 1
local STATE_EMU = 2
local current_state = STATE_MENU

local rom_list = {}
local selected_index = 1

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
    MMU.loadROM(filename)
    
    CPU.pc = 0x0100
    CPU.sp = 0xFFFE
    CPU.a = 0; CPU.f = 0; CPU.b = 0; CPU.c = 0; CPU.d = 0; CPU.e = 0; CPU.h = 0; CPU.l = 0
    CPU.ime = true
    CPU.halted = false
    CPU.halted_by_error = false
    
    MMU.writeByte(0xFF40, 0x91)
    MMU.writeByte(0xFF47, 0xFC)
    MMU.writeByte(0xFF44, 0x00)

    current_state = STATE_EMU
    love.window.setTitle("Playing: " .. filename)
end

local function handleInterrupts()
    local flag = MMU.readByte(0xFF0F)
    local enable = MMU.readByte(0xFFFF)
    local triggered = bit.band(flag, enable)

    if triggered > 0 then
        CPU.halted = false 
        if CPU.ime then
            for bit_idx = 0, 4 do
                local mask = bit.lshift(1, bit_idx)
                if bit.band(triggered, mask) ~= 0 then
                    CPU.ime = false
                    MMU.writeByte(0xFF0F, bit.band(flag, bit.bnot(mask)))
                    
                    local high = bit.band(bit.rshift(CPU.pc, 8), 0xFF)
                    local low = bit.band(CPU.pc, 0xFF)
                    CPU.sp = bit.band(CPU.sp - 1, 0xFFFF)
                    MMU.writeByte(CPU.sp, high)
                    CPU.sp = bit.band(CPU.sp - 1, 0xFFFF)
                    MMU.writeByte(CPU.sp, low)
                    
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

    -- Ограничиваем шаг времени при лагах или перетаскивании окна
    if dt > 0.1 then dt = 0.1 end

    -- Рассчитываем точное количество тактов процессора для текущей дельты времени (4.194304 МГц)
    local cycles_to_run = math.floor(4194304 * dt)
    local cycles_spent = 0
    
    local current_ly = MMU.readByte(0xFF44)
    local line_cycles = 0

    while cycles_spent < cycles_to_run do
        Joypad.update()
        handleInterrupts()
        
        local success, cycles_or_err = pcall(CPU.step)
        if success then
            local cycles = cycles_or_err or 4
            cycles_spent = cycles_spent + cycles
            line_cycles = line_cycles + cycles

            local stat = MMU.readByte(0xFF41)
            if current_ly >= 144 then stat = bit.bor(bit.band(stat, 0xFC), 1)
            elseif line_cycles < 80 then stat = bit.bor(bit.band(stat, 0xFC), 2)
            elseif line_cycles < 252 then stat = bit.bor(bit.band(stat, 0xFC), 3)
            else stat = bit.band(stat, 0xFC) end
            MMU.writeByte(0xFF41, stat)

            if line_cycles >= 456 then
                line_cycles = line_cycles - 456
                current_ly = current_ly + 1
                if current_ly == 144 then
                    local flag = MMU.readByte(0xFF0F)
                    MMU.writeByte(0xFF0F, bit.bor(flag, 1))
                elseif current_ly > 153 then
                    current_ly = 0
                end
                MMU.writeByte(0xFF44, current_ly)
                if current_ly <= 143 then PPU.renderLine(current_ly) end
            end
        else
            CPU.halted_by_error = true
            CPU.error_message = cycles_or_err
            break
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
        end
    end
end
