local bit = require("bit")
local MMU = require("mmu")

local Joypad = {
    matrix = 0xFF
}

function Joypad.update()
    -- Получаем первый подключенный геймпад (если он есть)
    local joysticks = love.joystick.getJoysticks()
    local gamepad = joysticks[1]

    local io_val = MMU.readByte(0xFF00)
    local res = bit.bor(bit.band(io_val, 0x30), 0x0F)

    -------------------------------------------------------------------
    -- 1. ОПРОС НАПРАВЛЕНИЙ (D-Pad / Стрелки)
    -------------------------------------------------------------------
    if bit.band(io_val, 0x10) == 0 then
        local mask = 0x0F
        
        -- Проверка клавиатуры ИЛИ геймпада (крестовины или левого стика)
        if love.keyboard.isDown("right") or (gamepad and (gamepad:isGamepadDown("dpright") or gamepad:getGamepadAxis("leftx") > 0.5)) then 
            mask = bit.band(mask, bit.bnot(0x01)) 
        end
        if love.keyboard.isDown("left") or (gamepad and (gamepad:isGamepadDown("dpleft") or gamepad:getGamepadAxis("leftx") < -0.5)) then 
            mask = bit.band(mask, bit.bnot(0x02)) 
        end
        if love.keyboard.isDown("up") or (gamepad and (gamepad:isGamepadDown("dpup") or gamepad:getGamepadAxis("lefty") < -0.5)) then 
            mask = bit.band(mask, bit.bnot(0x04)) 
        end
        if love.keyboard.isDown("down") or (gamepad and (gamepad:isGamepadDown("dpdown") or gamepad:getGamepadAxis("lefty") > 0.5)) then 
            mask = bit.band(mask, bit.bnot(0x08)) 
        end
        
        res = bit.band(res, mask)
    end

    -------------------------------------------------------------------
    -- 2. ОПРОС КНОПОК ДЕЙСТВИЯ (A, B, Start, Select)
    -------------------------------------------------------------------
    if bit.band(io_val, 0x20) == 0 then
        local mask = 0x0F
        
        -- START: Пробел на клавиатуре ИЛИ кнопка Start на геймпаде
        if love.keyboard.isDown("space") or (gamepad and gamepad:isGamepadDown("start")) then 
            mask = bit.band(mask, bit.bnot(0x01)) 
        end
        
        -- SELECT: Правый Shift ИЛИ кнопка Back/Select/Share на геймпаде
        if love.keyboard.isDown("rshift") or (gamepad and gamepad:isGamepadDown("back")) then 
            mask = bit.band(mask, bit.bnot(0x02)) 
        end
        
        -- КНОПКА B: Клавиша X ИЛИ кнопка X (на Xbox) / Квадрат (на PS) / Y (на Switch)
        if love.keyboard.isDown("x") or (gamepad and gamepad:isGamepadDown("x")) then 
            mask = bit.band(mask, bit.bnot(0x04)) 
        end
        
        -- КНОПКА A: Клавиша Z ИЛИ кнопка A (на Xbox) / Крестик (на PS) / B (на Switch)
        if love.keyboard.isDown("z") or (gamepad and gamepad:isGamepadDown("a")) then 
            mask = bit.band(mask, bit.bnot(0x08)) 
        end
        
        res = bit.band(res, mask)
    end

    MMU.writeByte(0xFF00, res)
end

return Joypad
