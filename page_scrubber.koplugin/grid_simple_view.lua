
--[[
    page_scrubber.koplugin/grid_simple_view.lua
]]--

local Blitbuffer = require("ffi/blitbuffer")
local Font       = require("ui/font")
local Geom       = require("ui/geometry")
local TextWidget = require("ui/widget/textwidget")
local os         = require("os")

local GridSimpleView = {}

function GridSimpleView.paint(scrubber, bb)
    local sw, sh = scrubber._sw, scrubber._sh
    local S = scrubber.S
    local available_y = scrubber._bar_dimen.y

    local max_p_w = math.floor(sw * 0.72)
    local max_p_h = math.floor(available_y * 0.78)

    local target_h = max_p_h
    local target_w = math.floor(target_h * (sw / sh))
    if target_w > max_p_w then
        target_w = max_p_w
        target_h = math.floor(target_w * (sh / sw))
    end

    -- Ajuste de anchura: un punto intermedio, ni tan ancho como el original ni tan apretado
    local pad_x = S(8)
    local arrow_area_w = S(38)
    local top_offset = S(55) 
    local bot_offset = S(12)

    local panel_w = target_w + (arrow_area_w * 2) + (pad_x * 2)
    local panel_h = target_h + top_offset + bot_offset
    local panel_x = math.floor((sw - panel_w) / 2)
    local panel_y = math.floor((available_y - panel_h) / 2)

    local page_x = panel_x + pad_x + arrow_area_w
    local page_y = panel_y + top_offset

    scrubber._gs_panel_dimen = Geom:new{ x = panel_x, y = panel_y, w = panel_w, h = panel_h }

    bb:paintRect(panel_x, panel_y, panel_w, panel_h, Blitbuffer.COLOR_WHITE)
    -- Contorno exterior de 3px de grosor
    bb:paintBorder(panel_x, panel_y, panel_w, panel_h, S(3), Blitbuffer.COLOR_BLACK, 0)

    local time_str = os.date("%H:%M")
    local tw_clock = TextWidget:new{ text = time_str, face = Font:getFace("cfont", S(13)), fgcolor = Blitbuffer.COLOR_BLACK }
    local csz = tw_clock:getSize()
    local clock_x = panel_x + math.floor((panel_w - csz.w) / 2)
    local clock_y = panel_y + S(15)

    tw_clock:paintTo(bb, clock_x, clock_y)
    tw_clock:paintTo(bb, clock_x + 1, clock_y)
    tw_clock:paintTo(bb, clock_x, clock_y + 1)
    tw_clock:paintTo(bb, clock_x + 1, clock_y + 1)
    tw_clock:free()

    local slot = scrubber._grid_tiles[2]
    if slot and slot.page then
        if slot.tile_bb then
            local tw, th = slot.tile_bb:getWidth(), slot.tile_bb:getHeight()
            local render_bb = slot.tile_bb
            local must_free = false

            if math.abs(tw - target_w) > 6 or math.abs(th - target_h) > 6 then
                local ok, sc = pcall(function() return slot.tile_bb:scale(target_w, target_h) end)
                if ok and sc then
                    render_bb = sc
                    must_free = true
                    tw, th = render_bb:getWidth(), render_bb:getHeight()
                end
            end

            local src_x, src_y = 0, 0
            local blit_w, blit_h = tw, th
            if blit_w > target_w then src_x = math.floor((blit_w - target_w) / 2); blit_w = target_w end
            if blit_h > target_h then src_y = math.floor((blit_h - target_h) / 2); blit_h = target_h end

            local ox = page_x + math.floor((target_w - blit_w) / 2)
            local oy = page_y + math.floor((target_h - blit_h) / 2)

            if blit_w > 0 and blit_h > 0 then
                bb:blitFrom(render_bb, ox, oy, src_x, src_y, blit_w, blit_h)
            end
            if must_free then pcall(function() render_bb:free() end) end
        elseif slot.error then
            local err_tw = TextWidget:new{ text = "!", face = Font:getFace("cfont", S(32)), fgcolor = Blitbuffer.COLOR_BLACK }
            local etsz = err_tw:getSize()
            err_tw:paintTo(bb, page_x + math.floor((target_w - etsz.w) / 2), page_y + math.floor((target_h - etsz.h) / 2))
            err_tw:free()
        elseif slot.loading then
            bb:paintRect(page_x + math.floor(target_w / 2) - 1, page_y + math.floor(target_h / 2) - 1, 2, 2, Blitbuffer.COLOR_GRAY)
        end
    end

    local arr_font = Font:getFace("cfont", S(40))
    local tw_l = TextWidget:new{ text = "‹", face = arr_font, fgcolor = Blitbuffer.COLOR_BLACK }
    local tw_r = TextWidget:new{ text = "›", face = arr_font, fgcolor = Blitbuffer.COLOR_BLACK }
    local lsz = tw_l:getSize()
    local rsz = tw_r:getSize()

    local left_arrow_x = panel_x + pad_x + math.floor((arrow_area_w - lsz.w) / 2)
    local right_arrow_x = page_x + target_w + math.floor((arrow_area_w - rsz.w) / 2)
    
    -- Flechas centradas verticalmente respecto al panel general (para que no se vean caídas)
    local arrow_y = panel_y + math.floor((panel_h - lsz.h) / 2)

    tw_l:paintTo(bb, left_arrow_x, arrow_y)
    tw_r:paintTo(bb, right_arrow_x, arrow_y)
    tw_l:free()
    tw_r:free()

    -- Ajuste milimétrico de la X
    local tw_x = TextWidget:new{ text = "✕", face = Font:getFace("cfont", S(19)), fgcolor = Blitbuffer.COLOR_BLACK }
    local xsz = tw_x:getSize()
    
    -- X anclada a la derecha del panel con margen seguro y a la altura de la hora
    local xx = panel_x + panel_w - xsz.w - S(16)
    local xy = clock_y + math.floor((csz.h - xsz.h) / 2)

    local touch_btn_size = math.max(xsz.w, xsz.h) + S(20)
    scrubber._gs_close_dimen = Geom:new{
        x = xx - math.floor((touch_btn_size - xsz.w)/2),
        y = xy - math.floor((touch_btn_size - xsz.h)/2),
        w = touch_btn_size,
        h = touch_btn_size
    }

    tw_x:paintTo(bb, xx, xy)
    tw_x:free()

    scrubber._gs_prev_dimen = Geom:new{ x = panel_x, y = panel_y, w = pad_x + arrow_area_w, h = panel_h }
    local next_y_start = scrubber._gs_close_dimen.y + scrubber._gs_close_dimen.h
    scrubber._gs_next_dimen = Geom:new{ 
        x = page_x + target_w, 
        y = next_y_start, 
        w = panel_x + panel_w - (page_x + target_w), 
        h = panel_y + panel_h - next_y_start 
    }
    scrubber._gs_page_dimen = Geom:new{ x = page_x, y = page_y, w = target_w, h = target_h }
end

return GridSimpleView
