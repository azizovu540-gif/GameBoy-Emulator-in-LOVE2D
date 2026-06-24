local bit = require("bit")
-- Используем ленивую загрузку MMU, чтобы избежать зацикливания require, 
-- так как mmu и apu ссылаются друг на друга.
local MMU = nil 

local APU = {
    sample_rate = 44100,
    buffer_size = 735, -- Ровно 1/60 секунды для 44100 Гц
    source = nil,
    soundData = nil,
    
    ch1_enabled = false, ch1_frequency = 0, ch1_volume = 0, ch1_duty = 0.5, ch1_phase = 0,
    ch2_enabled = false, ch2_frequency = 0, ch2_volume = 0, ch2_duty = 0.5, ch2_phase = 0,
    ch3_enabled = false, ch3_frequency = 0, ch3_volume = 0, ch3_phase = 0
}

function APU.init()
    MMU = require("mmu")
    APU.soundData = love.sound.newSoundData(APU.buffer_size, APU.sample_rate, 16, 1)
    -- Очередь из 8 буферов предотвращает микропаузы, когда кадры отрисовываются неравномерно
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
    if not MMU then MMU = require("mmu") end
    
    local nr52 = MMU.readByte(0xFF26)
    -- Если аудиочип выключен главным битом
    if bit.band(nr52, 0x80) == 0 then
        APU.ch1_enabled = false; APU.ch2_enabled = false; APU.ch3_enabled = false
        return
    end

    -- --- КАНАЛ 1 (Прямоугольная волна + Свип) ---
    local nr11 = MMU.readByte(0xFF11)
    local nr12 = MMU.readByte(0xFF12)
    local nr13 = MMU.readByte(0xFF13)
    local nr14 = MMU.readByte(0xFF14)
    
    APU.ch1_duty = get_duty(nr11)
    APU.ch1_volume = bit.rshift(bit.band(nr12, 0xF0), 4) / 15.0
    
    -- Проверяем триггер перезапуска канала
    if bit.band(nr14, 0x80) ~= 0 then 
        APU.ch1_enabled = true 
        MMU.writeByte(0xFF14, bit.band(nr14, 0x7F)) -- Сбрасываем триггер
    end
    
    local raw_f1 = bit.bor(nr13, bit.lshift(bit.band(nr14, 0x07), 8))
    APU.ch1_frequency = raw_f1 > 0 and (131072 / (2048 - raw_f1)) or 0
    if APU.ch1_frequency <= 0 or raw_f1 >= 2048 then APU.ch1_enabled = false end

    -- --- КАНАЛ 2 (Прямоугольная волна) ---
    local nr21 = MMU.readByte(0xFF16)
    local nr22 = MMU.readByte(0xFF17)
    local nr23 = MMU.readByte(0xFF18)
    local nr24 = MMU.readByte(0xFF19)
    
    APU.ch2_duty = get_duty(nr21)
    APU.ch2_volume = bit.rshift(bit.band(nr22, 0xF0), 4) / 15.0
    
    if bit.band(nr24, 0x80) ~= 0 then 
        APU.ch2_enabled = true 
        MMU.writeByte(0xFF19, bit.band(nr24, 0x7F)) 
    end
    
    local raw_f2 = bit.bor(nr23, bit.lshift(bit.band(nr24, 0x07), 8))
    APU.ch2_frequency = raw_f2 > 0 and (131072 / (2048 - raw_f2)) or 0
    if APU.ch2_frequency <= 0 or raw_f2 >= 2048 then APU.ch2_enabled = false end

    -- --- КАНАЛ 3 (Произвольная волна / Wave RAM) ---
    local nr30 = MMU.readByte(0xFF1A)
    local nr32 = MMU.readByte(0xFF1C)
    local nr33 = MMU.readByte(0xFF1D)
    local nr34 = MMU.readByte(0xFF1E)
    
    local ch3_master_on = bit.band(nr30, 0x80) ~= 0
    if bit.band(nr34, 0x80) ~= 0 and ch3_master_on then 
        APU.ch3_enabled = true 
        MMU.writeByte(0xFF1E, bit.band(nr34, 0x7F)) 
    end
    
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
    -- Предотвращаем переполнение звуковой очереди Love2D
    if APU.source:getFreeBufferCount() == 0 then return end
    
    -- Считываем свежие данные из регистров Game Boy перед генерацией пачки сэмплов
    APU.updateRegisters()

    for i = 0, APU.buffer_size - 1 do
        local mixed_sample = 0
        local active_channels = 0

        -- 1. Эмуляция Канала 1 (Square 1)
        if APU.ch1_enabled and APU.ch1_frequency > 0 then
            local total_samples = APU.sample_rate / APU.ch1_frequency
            APU.ch1_phase = APU.ch1_phase + 1
            if APU.ch1_phase >= total_samples then APU.ch1_phase = APU.ch1_phase - total_samples end
            
            local s1 = (APU.ch1_phase / total_samples < APU.ch1_duty) and 1.0 or -1.0
            mixed_sample = mixed_sample + (s1 * APU.ch1_volume)
            active_channels = active_channels + 1
        end

        -- 2. Эмуляция Канала 2 (Square 2)
        if APU.ch2_enabled and APU.ch2_frequency > 0 then
            local total_samples = APU.sample_rate / APU.ch2_frequency
            APU.ch2_phase = APU.ch2_phase + 1
            if APU.ch2_phase >= total_samples then APU.ch2_phase = APU.ch2_phase - total_samples end
            
            local s2 = (APU.ch2_phase / total_samples < APU.ch2_duty) and 1.0 or -1.0
            mixed_sample = mixed_sample + (s2 * APU.ch2_volume)
            active_channels = active_channels + 1
        end

        -- 3. Эмуляция Канала 3 (Wave)
        if APU.ch3_enabled and APU.ch3_frequency > 0 then
            local total_samples = APU.sample_rate / APU.ch3_frequency
            APU.ch3_phase = APU.ch3_phase + 1
            if APU.ch3_phase >= total_samples then APU.ch3_phase = APU.ch3_phase - total_samples end
            
            -- В Wave RAM хранится 32 4-битных сэмпла (16 байт)
            local sample_index = math.floor((APU.ch3_phase / total_samples) * 32)
            if sample_index > 31 then sample_index = 31 end
            
            local byte_addr = 0xFF30 + math.floor(sample_index / 2)
            local ram_byte = MMU.readByte(byte_addr)
            
            local nibble = 0
            if sample_index % 2 == 0 then
                nibble = bit.rshift(bit.band(ram_byte, 0xF0), 4)
            else
                nibble = bit.band(ram_byte, 0x0F)
            end
            
            -- Переводим 4 бита (0..15) в диапазон от -1.0 до 1.0
            local s3 = ((nibble / 15.0) * 2.0) - 1.0
            mixed_sample = mixed_sample + (s3 * APU.ch3_volume)
            active_channels = active_channels + 1
        end

        -- Правильное микширование: делим не на жесткую тройку (чтобы тихие одиночные звуки не глохли),
        -- а динамически нормализуем громкость и умножаем на мастер-громкость (0.2)
        if active_channels > 0 then
            mixed_sample = (mixed_sample / active_channels) * 0.2
        end

        -- Защита от клиппинга (жесткое ограничение диапазона PCM)
        if mixed_sample > 1.0 then mixed_sample = 1.0
        elseif mixed_sample < -1.0 then mixed_sample = -1.0 end

        APU.soundData:setSample(i, mixed_sample)
    end

    -- Закидываем сгенерированный буфер кадра в звуковую карту
    APU.source:queue(APU.soundData)
    APU.source:play()
end

return APU
