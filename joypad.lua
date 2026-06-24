local bit = require("bit")

local Joypad = {
    state_arrows = 0x0F,
    state_buttons = 0x0F
}

function Joypad.update()
    local MMU = require("mmu")
    local joysticks = love.joystick.getJoysticks()
    local gamepad = joysticks[1]

    local arrows = 0x0F
    local buttons = 0x0F

    -------------------------------------------------------------------
    -- 1. СБОР НАПРАВЛЕНИЙ (D-Pad / Стрелки)
    -------------------------------------------------------------------
    if love.keyboard.isDown("right") or (gamepad and (gamepad:isGamepadDown("dpright") or gamepad:getGamepadAxis("leftx") > 0.5)) then 
        arrows = bit.band(arrows, bit.bnot(0x01)) 
    end
    if love.keyboard.isDown("left") or (gamepad and (gamepad:isGamepadDown("dpleft") or gamepad:getGamepadAxis("leftx") < -0.5)) then 
        arrows = bit.band(arrows, bit.bnot(0x02)) 
    end
    if love.keyboard.isDown("up") or (gamepad and (gamepad:isGamepadDown("dpup") or gamepad:getGamepadAxis("lefty") < -0.5)) then 
        arrows = bit.band(arrows, bit.bnot(0x04)) 
    end
    if love.keyboard.isDown("down") or (gamepad and (gamepad:isGamepadDown("dpdown") or gamepad:getGamepadAxis("lefty") > 0.5)) then 
        arrows = bit.band(arrows, bit.bnot(0x08)) 
    end

    -------------------------------------------------------------------
    -- 2. СБОР КНОПОК ДЕЙСТВИЯ (A, B, Select, Start)
    -------------------------------------------------------------------
    if love.keyboard.isDown("z") or (gamepad and gamepad:isGamepadDown("a")) then 
        buttons = bit.band(buttons, bit.bnot(0x01)) 
    end
    if love.keyboard.isDown("x") or (gamepad and gamepad:isGamepadDown("x")) then 
        buttons = bit.band(buttons, bit.bnot(0x02)) 
    end
    if love.keyboard.isDown("rshift") or (gamepad and gamepad:isGamepadDown("back")) then 
        buttons = bit.band(buttons, bit.bnot(0x04)) 
    end
    if love.keyboard.isDown("space") or (gamepad and gamepad:isGamepadDown("start")) then 
        buttons = bit.band(buttons, bit.bnot(0x08)) 
    end

    -- Проверяем, изменилось ли состояние (нажали ли новую кнопку?)
    local old_arrows = Joypad.state_arrows
    local old_buttons = Joypad.state_buttons

    Joypad.state_arrows = arrows
    Joypad.state_buttons = buttons

    -- Если какой-то бит перешел из 1 (отпущено) в 0 (нажато) — дергаем прерывание джойпада (Бит 4)
    local pressed_arrows = bit.band(bit.bnot(arrows), old_arrows)
    local pressed_buttons = bit.band(bit.bnot(buttons), old_buttons)
    
    if pressed_arrows > 0 or pressed_buttons > 0 then
        local flag = MMU.readByte(0xFF0F)
        MMU.writeStandard(0xFF0F, bit.bor(flag, 0x10))
    end
end

return Joypad
