local bit = require("bit")
local MMU = require("mmu")

local PPU = {
    imageData = love.image.newImageData(160, 144),
    image = nil,
    palette = {
        [0] = {224, 248, 208},
        [1] = {136, 192, 112},
        [2] = {52, 104, 86},
        [3] = {8, 24, 32}
    }
}

PPU.image = love.graphics.newImage(PPU.imageData)
PPU.image:setFilter("nearest", "nearest")

function PPU.renderLine(ly)
    local lcdc = MMU.readByte(0xFF40)
    if bit.band(lcdc, 0x80) == 0 then return end

    local bgp = MMU.readByte(0xFF47)

    if bit.band(lcdc, 0x01) ~= 0 then
        local wy = MMU.readByte(0xFF4A)
        local wx = MMU.readByte(0xFF4B)
        if wx >= 7 then wx = wx - 7 else wx = 0 end

        local is_window_visible = bit.band(lcdc, 0x20) ~= 0 and ly >= wy

        local scy = MMU.readByte(0xFF42)
        local scx = MMU.readByte(0xFF43)

        local bg_map_base = bit.band(lcdc, 0x08) ~= 0 and 0x1C00 or 0x1800
        local win_map_base = bit.band(lcdc, 0x40) ~= 0 and 0x1C00 or 0x1800

        for cx = 0, 159 do
            local use_window = is_window_visible and cx >= wx
            local x_pos, y_pos, map_base
            if use_window then
                x_pos = cx - wx
                y_pos = ly - wy
                map_base = win_map_base
            else
                x_pos = bit.band(cx + scx, 0xFF)
                y_pos = bit.band(ly + scy, 0xFF)
                map_base = bg_map_base
            end

            local tile_row = bit.rshift(y_pos, 3)
            local tile_col = bit.rshift(x_pos, 3)
            local tile_line = bit.band(y_pos, 7)
            local tile_pixel = 7 - bit.band(x_pos, 7)

            local map_addr = map_base + (tile_row * 32) + tile_col
            local tile_index = MMU.readByte(0x8000 + map_addr)

            local tile_addr = 0
            if bit.band(lcdc, 0x10) ~= 0 then
                tile_addr = tile_index * 16
            else
                if tile_index >= 128 then tile_index = tile_index - 256 end
                tile_addr = 0x1000 + (tile_index * 16)
            end
            
            local addr = tile_addr + (tile_line * 2)
            local byte1 = MMU.readByte(0x8000 + addr)
            local byte2 = MMU.readByte(0x8000 + addr + 1)

            local bit1 = bit.band(bit.rshift(byte1, tile_pixel), 1)
            local bit2 = bit.band(bit.rshift(byte2, tile_pixel), 1)
            local color_idx = bit.bor(bit1, bit.lshift(bit2, 1))

            local actual_color_idx = bit.band(bit.rshift(bgp, color_idx * 2), 3)
            local color = PPU.palette[actual_color_idx]
            PPU.imageData:setPixel(cx, ly, color[1]/255, color[2]/255, color[3]/255, 1)
        end
    end

    if bit.band(lcdc, 0x02) ~= 0 then
        for i = 0, 39 do
            local oam_base = i * 4
            local sprite_y = MMU.readByte(0xFE00 + oam_base) - 16
            local sprite_x = MMU.readByte(0xFE00 + oam_base + 1) - 8
            local tile_index = MMU.readByte(0xFE00 + oam_base + 2)
            local attributes = MMU.readByte(0xFE00 + oam_base + 3)
            local sprite_height = bit.band(lcdc, 0x04) ~= 0 and 16 or 8

            if ly >= sprite_y and ly < (sprite_y + sprite_height) then
                local palette_addr = bit.band(attributes, 0x10) ~= 0 and 0xFF49 or 0xFF48
                local obp = MMU.readByte(palette_addr)
                local tile_line = ly - sprite_y
                if bit.band(attributes, 0x40) ~= 0 then tile_line = sprite_height - 1 - tile_line end
                if sprite_height == 16 then tile_index = bit.band(tile_index, 0xFE) end

                local addr = (tile_index * 16) + (tile_line * 2)
                local byte1 = MMU.readByte(0x8000 + addr)
                local byte2 = MMU.readByte(0x8000 + addr + 1)

                for cx = 0, 7 do
                    local pixel_x = sprite_x + cx
                    if pixel_x >= 0 and pixel_x < 160 then
                        local tile_pixel = 7 - cx
                        if bit.band(attributes, 0x20) ~= 0 then tile_pixel = cx end

                        local bit1 = bit.band(bit.rshift(byte1, tile_pixel), 1)
                        local bit2 = bit.band(bit.rshift(byte2, tile_pixel), 1)
                        local color_idx = bit.bor(bit1, bit.lshift(bit2, 1))

                        if color_idx ~= 0 then
                            local actual_color_idx = bit.band(bit.rshift(obp, color_idx * 2), 3)
                            local color = PPU.palette[actual_color_idx]
                            PPU.imageData:setPixel(pixel_x, ly, color[1]/255, color[2]/255, color[3]/255, 1)
                        end
                    end
                end
            end
        end
    end
end

function PPU.draw()
    PPU.image:replacePixels(PPU.imageData)
    love.graphics.draw(PPU.image, 0, 0, 0, 4, 4)
end

return PPU
