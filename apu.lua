local bit = require("bit")
local MMU = require("mmu")

local APU = {
    sample_rate = 44100,
    buffer_size = 735,
    source = nil,
    soundData = nil,
    
    ch1_enabled = false, ch1_frequency = 0, ch1_volume = 0, ch1_duty = 0.5, ch1_phase = 0,
    ch2_enabled = false, ch2_frequency = 0, ch2_volume = 0, ch2_duty = 0.5, ch2_phase = 0,
    ch3_enabled = false, ch3_frequency = 0, ch3_volume = 0, ch3_phase = 0
}

function APU.init()
    APU.soundData = love.sound.newSoundData(APU.buffer_size, APU.sample_rate, 16, 1)
    -- Создаем очередь с запасом (8 буферов), чтобы убрать микро-паузы и треск
    APU.source = love.audio.newQueueableSource(APU.sample_rate, 16, 1, 8)
    APU.source:play()
end

local function get_duty(reg)
    local idx = bit.rshift(bit.band(reg, 0xC0), 6)
    if idx == 0 then return 0.125
    elseif idx == 1 then return 0.25
    elseif idx == 2 then return 0.5
    else return 0.75 end
end

function APU.updateRegisters()
    local nr52 = MMU.readByte(0xFF26)
    if bit.band(nr52, 0x80) == 0 then
        APU.ch1_enabled = false; APU.ch2_enabled = false; APU.ch3_enabled = false
        return
    end

    -- Канал 1
    local nr11, nr12, nr13, nr14 = MMU.readByte(0xFF11), MMU.readByte(0xFF12), MMU.readByte(0xFF13), MMU.readByte(0xFF14)
    APU.ch1_duty = get_duty(nr11)
    APU.ch1_volume = bit.rshift(bit.band(nr12, 0xF0), 4) / 15.0
    if bit.band(nr14, 0x80) ~= 0 then APU.ch1_enabled = true; MMU.writeByte(0xFF14, bit.band(nr14, 0x7F)) end
    local raw_f1 = bit.bor(nr13, bit.lshift(bit.band(nr14, 0x07), 8))
    APU.ch1_frequency = raw_f1 > 0 and (131072 / (2048 - raw_f1)) or 0
    if APU.ch1_frequency <= 0 or raw_f1 >= 2048 then APU.ch1_enabled = false end

    -- Канал 2
    local nr21, nr22, nr23, nr24 = MMU.readByte(0xFF16), MMU.readByte(0xFF17), MMU.readByte(0xFF18), MMU.readByte(0xFF19)
    APU.ch2_duty = get_duty(nr21)
    APU.ch2_volume = bit.rshift(bit.band(nr22, 0xF0), 4) / 15.0
    if bit.band(nr24, 0x80) ~= 0 then APU.ch2_enabled = true; MMU.writeByte(0xFF19, bit.band(nr24, 0x7F)) end
    local raw_f2 = bit.bor(nr23, bit.lshift(bit.band(nr24, 0x07), 8))
    APU.ch2_frequency = raw_f2 > 0 and (131072 / (2048 - raw_f2)) or 0
    if APU.ch2_frequency <= 0 or raw_f2 >= 2048 then APU.ch2_enabled = false end

    -- Канал 3
    local nr30, nr32, nr33, nr34 = MMU.readByte(0xFF1A), MMU.readByte(0xFF1C), MMU.readByte(0xFF1D), MMU.readByte(0xFF1E)
    local ch3_master_on = bit.band(nr30, 0x80) ~= 0
    if bit.band(nr34, 0x80) ~= 0 and ch3_master_on then APU.ch3_enabled = true; MMU.writeByte(0xFF1E, bit.band(nr34, 0x7F)) end
    local vol_idx = bit.rshift(bit.band(nr32, 0x60), 5)
    if vol_idx == 0 then APU.ch3_volume = 0
    elseif vol_idx == 1 then APU.ch3_volume = 1.0
    elseif vol_idx == 2 then APU.ch3_volume = 0.5
    else APU.ch3_volume = 0.25 end
    local raw_f3 = bit.bor(nr33, bit.lshift(bit.band(nr34, 0x07), 8))
    APU.ch3_frequency = raw_f3 > 0 and (65536 / (2048 - raw_f3)) or 0
    if not ch3_master_on or APU.ch3_frequency <= 0 or raw_f3 >= 2048 then APU.ch3_enabled = false end
end

function APU.generateFrameAudio()
    -- Если очередь переполнена, ждем, пока звуковая карта прожует старые сэмплы
    if APU.source:getFreeBufferCount() == 0 then return end
    
    APU.updateRegisters()

    for i = 0, APU.buffer_size - 1 do
        local mixed_sample = 0

        -- 1. Канал 1
        if APU.ch1_enabled and APU.ch1_frequency > 0 then
            local total_samples = APU.sample_rate / APU.ch1_frequency
            APU.ch1_phase = APU.ch1_phase + 1
            if APU.ch1_phase >= total_samples then APU.ch1_phase = APU.ch1_phase - total_samples end
            local s1 = (APU.ch1_phase / total_samples < APU.ch1_duty) and 1 or -1
            mixed_sample = mixed_sample + (s1 * APU.ch1_volume)
        end

        -- 2. Канал 2
        if APU.ch2_enabled and APU.ch2_frequency > 0 then
            local total_samples = APU.sample_rate / APU.ch2_frequency
            APU.ch2_phase = APU.ch2_phase + 1
            if APU.ch2_phase >= total_samples then APU.ch2_phase = APU.ch2_phase - total_samples end
            local s2 = (APU.ch2_phase / total_samples < APU.ch2_duty) and 1 or -1
            mixed_sample = mixed_sample + (s2 * APU.ch2_volume)
        end

        -- 3. Канал 3
        if APU.ch3_enabled and APU.ch3_frequency > 0 then
            local total_samples = APU.sample_rate / APU.ch3_frequency
            APU.ch3_phase = APU.ch3_phase + 1
            if APU.ch3_phase >= total_samples then APU.ch3_phase = APU.ch3_phase - total_samples end
            
            local sample_index = math.floor((APU.ch3_phase / total_samples) * 32)
            local byte_addr = 0xFF30 + math.floor(sample_index / 2)
            local ram_byte = MMU.readByte(byte_addr)
            
            local nibble = 0
            if sample_index % 2 == 0 then
                nibble = bit.rshift(bit.band(ram_byte, 0xF0), 4)
            else
                nibble = bit.band(ram_byte, 0x0F)
            end
            
            local s3 = ((nibble / 15.0) * 2.0) - 1.0
            mixed_sample = mixed_sample + (s3 * APU.ch3_volume)
        end

        -- Сглаживаем звук и закидываем в буфер (общая громкость 0.1)
        APU.soundData:setSample(i, (mixed_sample / 3.0) * 0.1)
    end

    -- Добавляем в конец непрерывной очереди звуковой карты
    APU.source:queue(APU.soundData)
    APU.source:play()
end

return APU
