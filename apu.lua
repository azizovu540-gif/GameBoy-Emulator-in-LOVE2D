local bit = require("bit")
local MMU = nil 

local APU = {
    sample_rate = 44100,
    buffer_size = 735, 
    source = nil,
    soundData = nil,
    
    ch1_enabled = false, ch1_frequency = 0, ch1_volume = 0, ch1_duty = 0.5, ch1_phase = 0,
    ch2_enabled = false, ch2_frequency = 0, ch2_volume = 0, ch2_duty = 0.5, ch2_phase = 0,
    ch3_enabled = false, ch3_frequency = 0, ch3_volume = 0, ch3_phase = 0,
    
    -- Канал 4 (Шум)
    ch4_enabled = false, ch4_volume = 0, ch4_phase = 0, ch4_period = 0,
    ch4_lfsr = 0x7FFF, ch4_short_mode = false,
    
    -- НЧ Фильтр
    last_lowpass_sample = 0,
    ch4_release_timer = 0
}

function APU.init()
    MMU = require("mmu")
    APU.soundData = love.sound.newSoundData(APU.buffer_size, APU.sample_rate, 16, 1)
    -- Создаем очередь из 16 буферов для защиты от задержек (Buffer Underrun)
    APU.source = love.audio.newQueueableSource(APU.sample_rate, 16, 1, 16)
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
    if bit.band(nr52, 0x80) == 0 then
        APU.ch1_enabled = false; APU.ch2_enabled = false; APU.ch3_enabled = false; APU.ch4_enabled = false
        APU.ch1_volume = 0; APU.ch2_volume = 0; APU.ch3_volume = 0; APU.ch4_volume = 0
        return
    end

    -- --- КАНАЛ 1 ---
    local nr11 = MMU.readByte(0xFF11)
    local nr12 = MMU.readByte(0xFF12)
    local nr13 = MMU.readByte(0xFF13)
    local nr14 = MMU.readByte(0xFF14)
    APU.ch1_duty = get_duty(nr11)
    APU.ch1_volume = bit.rshift(bit.band(nr12, 0xF0), 4) / 15.0
    
    if bit.band(nr14, 0x80) ~= 0 then 
        APU.ch1_enabled = true
        APU.ch1_phase = 0
        MMU.writeByte(0xFF14, bit.band(nr14, 0x7F)) 
    end
    local raw_f1 = bit.bor(nr13, bit.lshift(bit.band(nr14, 0x07), 8))
    APU.ch1_frequency = raw_f1 > 0 and (131072 / (2048 - raw_f1)) or 0
    if APU.ch1_frequency <= 0 or raw_f1 >= 2048 or APU.ch1_volume == 0 then APU.ch1_enabled = false end

    -- --- КАНАЛ 2 ---
    local nr21 = MMU.readByte(0xFF16)
    local nr22 = MMU.readByte(0xFF17)
    local nr23 = MMU.readByte(0xFF18)
    local nr24 = MMU.readByte(0xFF19)
    APU.ch2_duty = get_duty(nr21)
    APU.ch2_volume = bit.rshift(bit.band(nr22, 0xF0), 4) / 15.0
    
    if bit.band(nr24, 0x80) ~= 0 then 
        APU.ch2_enabled = true
        APU.ch2_phase = 0
        MMU.writeByte(0xFF19, bit.band(nr24, 0x7F)) 
    end
    local raw_f2 = bit.bor(nr23, bit.lshift(bit.band(nr24, 0x07), 8))
    APU.ch2_frequency = raw_f2 > 0 and (131072 / (2048 - raw_f2)) or 0
    if APU.ch2_frequency <= 0 or raw_f2 >= 2048 or APU.ch2_volume == 0 then APU.ch2_enabled = false end

    -- --- КАНАЛ 3 ---
    local nr30 = MMU.readByte(0xFF1A)
    local nr32 = MMU.readByte(0xFF1C)
    local nr33 = MMU.readByte(0xFF1D)
    local nr34 = MMU.readByte(0xFF1E)
    local ch3_master_on = bit.band(nr30, 0x80) ~= 0
    
    if bit.band(nr34, 0x80) ~= 0 and ch3_master_on then 
        APU.ch3_enabled = true
        APU.ch3_phase = 0
        MMU.writeByte(0xFF1E, bit.band(nr34, 0x7F)) 
    end
    local vol_idx = bit.rshift(bit.band(nr32, 0x60), 5)
    if vol_idx == 0 then APU.ch3_volume = 0
    elseif vol_idx == 1 then APU.ch3_volume = 1.0
    elseif vol_idx == 2 then APU.ch3_volume = 0.5
    else APU.ch3_volume = 0.25 end
    local raw_f3 = bit.bor(nr33, bit.lshift(bit.band(nr34, 0x07), 8))
    APU.ch3_frequency = raw_f3 > 0 and (65536 / (2048 - raw_f3)) or 0
    if not ch3_master_on or APU.ch3_frequency <= 0 or raw_f3 >= 2048 or APU.ch3_volume == 0 then APU.ch3_enabled = false end

    -- --- КАНАЛ 4 ---
    local nr42 = MMU.readByte(0xFF22) 
    local nr43 = MMU.readByte(0xFF23) 
    local nr44 = MMU.readByte(0xFF24) 
    
    local base_volume = bit.rshift(bit.band(nr42, 0xF0), 4) / 15.0
    
    if bit.band(nr44, 0x80) ~= 0 then 
        APU.ch4_enabled = true 
        APU.ch4_lfsr = 0x7FFF 
        APU.ch4_phase = 0
        APU.ch4_volume = base_volume
        APU.ch4_release_timer = 1.0
        MMU.writeByte(0xFF24, bit.band(nr44, 0x7F)) 
    end

    if APU.ch4_enabled then
        APU.ch4_release_timer = APU.ch4_release_timer - 0.02
        if APU.ch4_release_timer <= 0 or base_volume == 0 then
            APU.ch4_release_timer = 0
            APU.ch4_volume = 0
            APU.ch4_enabled = false
        else
            APU.ch4_volume = base_volume * APU.ch4_release_timer
        end
    end

    local div = bit.band(nr43, 0x07)
    if div == 0 then div = 0.5 end
    local shift = bit.rshift(bit.band(nr43, 0xF0), 4)
    APU.ch4_short_mode = bit.band(nr43, 0x08) ~= 0
    
    local noise_freq = 524288 / div / (bit.lshift(1, shift + 1))
    APU.ch4_period = APU.sample_rate / noise_freq
end

function APU.generateFrameAudio()
    APU.updateRegisters()

    -- ИСПРАВЛЕНИЕ: Если звуковая карта «сожрала» слишком много звука, 
    -- мы насильно скармливаем ей новые кадры, пока свободная очередь не заполнится.
    while APU.source:getFreeBufferCount() > 0 do
        for i = 0, APU.buffer_size - 1 do
            local mixed_sample = 0
            local active_channels = 0

            -- 1. Канал 1
            if APU.ch1_enabled and APU.ch1_volume > 0 and APU.ch1_frequency > 0 then
                local total_samples = APU.sample_rate / APU.ch1_frequency
                APU.ch1_phase = APU.ch1_phase + 1
                if APU.ch1_phase >= total_samples then APU.ch1_phase = APU.ch1_phase - total_samples end
                local s1 = (APU.ch1_phase / total_samples < APU.ch1_duty) and 1.0 or -1.0
                mixed_sample = mixed_sample + (s1 * APU.ch1_volume)
                active_channels = active_channels + 1
            end

            -- 2. Канал 2
            if APU.ch2_enabled and APU.ch2_volume > 0 and APU.ch2_frequency > 0 then
                local total_samples = APU.sample_rate / APU.ch2_frequency
                APU.ch2_phase = APU.ch2_phase + 1
                if APU.ch2_phase >= total_samples then APU.ch2_phase = APU.ch2_phase - total_samples end
                local s2 = (APU.ch2_phase / total_samples < APU.ch2_duty) and 1.0 or -1.0
                mixed_sample = mixed_sample + (s2 * APU.ch2_volume)
                active_channels = active_channels + 1
            end

            -- 3. Канал 3
            if APU.ch3_enabled and APU.ch3_volume > 0 and APU.ch3_frequency > 0 then
                local total_samples = APU.sample_rate / APU.ch3_frequency
                APU.ch3_phase = APU.ch3_phase + 1
                if APU.ch3_phase >= total_samples then APU.ch3_phase = APU.ch3_phase - total_samples end
                local sample_index = math.floor((APU.ch3_phase / total_samples) * 32)
                if sample_index > 31 then sample_index = 31 end
                local byte_addr = 0xFF30 + math.floor(sample_index / 2)
                local ram_byte = MMU.readByte(byte_addr)
                local nibble = (sample_index % 2 == 0) and bit.rshift(bit.band(ram_byte, 0xF0), 4) or bit.band(ram_byte, 0x0F)
                local s3 = ((nibble / 15.0) * 2.0) - 1.0
                mixed_sample = mixed_sample + (s3 * APU.ch3_volume)
                active_channels = active_channels + 1
            end

            -- 4. Канал 4
            if APU.ch4_enabled and APU.ch4_volume > 0 and APU.ch4_period > 0 then
                APU.ch4_phase = APU.ch4_phase + 1
                if APU.ch4_phase >= APU.ch4_period then
                    APU.ch4_phase = APU.ch4_phase - APU.ch4_period
                    
                    local b1 = bit.band(APU.ch4_lfsr, 1)
                    local b2 = bit.band(bit.rshift(APU.ch4_lfsr, 1), 1)
                    local xor_bit = bit.bxor(b1, b2)
                    
                    APU.ch4_lfsr = bit.bor(bit.rshift(APU.ch4_lfsr, 1), bit.lshift(xor_bit, 14))
                    if APU.ch4_short_mode then
                        APU.ch4_lfsr = bit.band(APU.ch4_lfsr, bit.bnot(0x40))
                        APU.ch4_lfsr = bit.bor(APU.ch4_lfsr, bit.lshift(xor_bit, 6))
                    end
                end
                
                local s4 = (bit.band(APU.ch4_lfsr, 1) == 0) and 1.0 or -1.0
                mixed_sample = mixed_sample + (s4 * APU.ch4_volume)
                active_channels = active_channels + 1
            end

            if active_channels > 0 then
                mixed_sample = (mixed_sample / active_channels) * 0.22
            else
                mixed_sample = 0
            end

            if mixed_sample > 1.0 then mixed_sample = 1.0
            elseif mixed_sample < -1.0 then mixed_sample = -1.0 end

            -- Мягкий фильтр (0.28) для баланса деталей звука и отсутствия свиста
            local filter_factor = 0.28
            mixed_sample = APU.last_lowpass_sample + filter_factor * (mixed_sample - APU.last_lowpass_sample)
            APU.last_lowpass_sample = mixed_sample

            APU.soundData:setSample(i, mixed_sample)
        end

        APU.source:queue(APU.soundData)
    end
    
    -- Всегда форсируем воспроизведение, чтобы аудио-поток не засыпал
    if not APU.source:isPlaying() then
        APU.source:play()
    end
end

return APU
