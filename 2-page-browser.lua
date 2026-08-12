--[[
    2-page-scrubber.lua
    Page scrubber overlay (Kindle E-ink optimized)
    - Sacred Center Logic
    - Semaphore Protection
    - Original Fluid Slider
    - Swipe Filter
    - Custom UI
    - Soft Retries
    - Spread Fix
    - Compact 3-Page Grid
    - Anti-Crash Shield
    - RAM Micro-Nap & Timeout Extension
    - Title Formatting
    - D-Pad Chapter Navigation
    - Swipe Down to Close
    - Zombie Widget Fix
    - Sync Redraw Fix
    - Dynamic UI Scaling (Custom UI Scale, border fixes, and rebalanced icons)
]]--

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local Dispatcher      = require("dispatcher")
local DocCache        = require("document/doccache")
local Event           = require("ui/event")
local Font            = require("ui/font")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local InputContainer  = require("ui/widget/container/inputcontainer")
local ReaderUI        = require("apps/reader/readerui")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local logger          = require("logger")
local _               = require("gettext")

local Screen = Device.screen

-- =========================================================================
-- CRITICAL WARNING
-- You MUST delete or disable any other "page scrubber" or "page browser" 
-- patches/plugins in your KOReader folder before using this one.
-- =========================================================================

-- =========================================================================
-- USER CONFIGURATION
-- Modify this value to scale the entire UI (icons, fonts, margins)
-- 1.0 = Default size / 0.8 = 20% smaller / 1.2 = 20% bigger
local CUSTOM_UI_SCALE = 1 
-- =========================================================================

local function S(val)
    local res = math.floor(val * CUSTOM_UI_SCALE)
    if val > 0 and res == 0 then res = 1 end
    return Screen:scaleBySize(res)
end

local function paintPill(bb, px, py, pw, ph, color)
    if pw <= 0 or ph <= 0 then return end
    local r = math.min(pw, ph) / 2.0
    for row = 0, ph - 1 do
        local dy = (row + 0.5) - ph * 0.5
        local inset = math.abs(dy) < r and math.ceil(r - math.sqrt(r*r - dy*dy)) or 0
        local rw = pw - 2 * inset
        if rw > 0 then bb:paintRect(px + inset, py + row, rw, 1, color) end
    end
end

local ENABLE_SWIPE_ANIM_OVERRIDE = true

local function paintCircle(bb, cx, cy, r, color)
    if r <= 0 then return end
    for row = -r, r do
        local half = math.floor(math.sqrt(r*r - row*row) + 0.5)
        if half > 0 then bb:paintRect(cx - half, cy + row, half * 2, 1, color) end
    end
end

local function paintRoundRect(bb, x, y, w, h, r, color)
    if w <= 0 or h <= 0 then return end
    r = math.min(r, math.floor(w / 2), math.floor(h / 2))
    if r <= 0 then bb:paintRect(x, y, w, h, color); return end
    if w - 2*r > 0 then bb:paintRect(x + r, y,         w - 2*r, h,         color) end
    bb:paintRect(x,     y + r,     r,       math.max(1, h - 2*r), color)
    bb:paintRect(x+w-r, y + r,     r,       math.max(1, h - 2*r), color)
    for j = 0, r - 1 do
        local arc = math.ceil(math.sqrt(r*r - (r-j-0.5)*(r-j-0.5)))
        if arc > 0 then
            bb:paintRect(x + r - arc, y + j,         arc, 1, color)
            bb:paintRect(x + w - r,   y + j,         arc, 1, color)
            bb:paintRect(x + r - arc, y + h - 1 - j, arc, 1, color)
            bb:paintRect(x + w - r,   y + h - 1 - j, arc, 1, color)
        end
    end
end

local ProgressSlider = {}
ProgressSlider.__index = ProgressSlider

function ProgressSlider:new(o)
    local obj = setmetatable(o or {}, self)
    obj.knob_r = S(16) 
    obj.height = obj.knob_r * 2 + S(6)
    obj.dimen   = Geom:new{ x = 0, y = 0, w = obj.width or 0, h = obj.height }
    obj._dragging = false
    return obj
end

function ProgressSlider:getSize() return self.dimen end

function ProgressSlider:_valueToX(v)
    local range = self.value_max - self.value_min
    if range == 0 then return self.knob_r end
    return self.knob_r + (v - self.value_min) / range * ((self.width or 0) - self.knob_r * 2)
end

function ProgressSlider:_xToValue(lx)
    local range = self.value_max - self.value_min
    local frac = (lx - self.knob_r) / math.max(1, (self.width or 0) - self.knob_r * 2)
    frac = math.max(0, math.min(1, frac))
    return math.floor(self.value_min + frac * range + 0.5)
end

function ProgressSlider:paintTo(bb, x, y)
    self.dimen.x = x; self.dimen.y = y
    local w, h = self.width or 0, self.height
    local r = self.knob_r
    local cy = math.floor(y + h / 2)
    
    -- Barra base
    paintPill(bb, x, cy - S(2), w, S(4), Blitbuffer.COLOR_LIGHT_GRAY)
    local frac = (self.value - self.value_min) / math.max(1, self.value_max - self.value_min)
    local fw = math.floor(frac * w + 0.5)
    
    -- Barra llena
    if fw > 0 then paintPill(bb, x, cy - S(2), fw, S(4), Blitbuffer.COLOR_BLACK) end

    -- Bookmarks
    if self.bookmarks then
        for _, bmpage in ipairs(self.bookmarks) do
            if bmpage >= self.value_min and bmpage <= self.value_max then
                local bmx = math.floor(x + self:_valueToX(bmpage))
                paintCircle(bb, bmx, cy, S(9), Blitbuffer.COLOR_WHITE)
                paintCircle(bb, bmx, cy, S(6), Blitbuffer.COLOR_BLACK)
            end
        end
    end

    -- Círculo principal
    local kx = math.floor(x + self:_valueToX(self.value))
    paintCircle(bb, kx, cy, r, Blitbuffer.COLOR_BLACK)
    paintCircle(bb, kx, cy, r - S(3), Blitbuffer.COLOR_WHITE)
end

function ProgressSlider:handleTap(ges)
    if not self.dimen or not ges.pos:intersectWith(self.dimen) then return false end
    
    local tap_x = ges.pos.x - self.dimen.x
    local v = self:_xToValue(tap_x)
    
    -- Imán para bookmarks
    if self.bookmarks then
        for _, bmpage in ipairs(self.bookmarks) do
            local bmx = self:_valueToX(bmpage)
            if math.abs(tap_x - bmx) < S(20) then 
                v = bmpage
                break
            end
        end
    end

    if v ~= self.value then 
        self.value = v
        if self.on_change then self.on_change(v) end 
    end
    return true
end

function ProgressSlider:handlePan(ges)
    if self._dragging then
        local v = self:_xToValue(ges.pos.x - (self.dimen.x or 0))
        if v ~= self.value then 
            self.value = v
            if self.on_change then self.on_change(v) end 
        end
        return true
    end
    if not (self.dimen and ges.pos:intersectWith(self.dimen)) then return false end
    local dir = ges.direction
    if dir == "north" or dir == "south" then return false end
    self._dragging = true
    local v = self:_xToValue(ges.pos.x - self.dimen.x)
    if v ~= self.value then 
        self.value = v
        if self.on_change then self.on_change(v) end 
    end
    return true
end

function ProgressSlider:handlePanRelease(ges)
    if not self._dragging then return false end
    self._dragging = false
    local v = self:_xToValue(ges.pos.x - (self.dimen.x or 0))
    if v ~= self.value then 
        self.value = v
    end
    if self.on_change then self.on_change(self.value) end 
    return true
end

local PageScrubber = InputContainer:extend{ name = "page_scrubber", transparent = true }

function PageScrubber:init()
    local ui  = self.ui
    local doc = ui.document

    if ENABLE_SWIPE_ANIM_OVERRIDE then
        self._old_can_do = Device.canDoSwipeAnimation
        Device.canDoSwipeAnimation = function() return false end

        self._saved_swipe_animations = Screen.swipe_animations
        Screen.swipe_animations = false
    end

    self._origin_page = (ui.view and ui.view.state and ui.view.state.page) or 1
    self._cur_page    = self._origin_page
    self._total_pages = (doc and doc.getPageCount and doc:getPageCount()) or 1
    self._pressed_btn = nil
    self._closing     = false
    self._hold_token  = 0
    self._hold_active = false
    
    self._is_busy     = true
    self._tasks_in_flight = 0

    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local pad = S(16)

    local top_h     = S(62)
    local top_bar_y = 0
    self._top_bar_dimen = Geom:new{ x = 0, y = top_bar_y, w = sw, h = top_h }

    self.font_ch    = Font:getFace("cfont", S(19))
    self.font_title = Font:getFace("cfont", S(16))
    self.font_info  = Font:getFace("cfont", S(14))

    local function getBookTitle()
        local title
        if ui.doc_props and ui.doc_props.title and ui.doc_props.title ~= "" then
            title = ui.doc_props.title
        end
        if not title and ui.document and ui.document.getProps then
            local ok, props = pcall(function() return ui.document:getProps() end)
            if ok and props and props.title and props.title ~= "" then
                title = props.title
            end
        end
        if not title and ui.document and ui.document.file then
            local base = ui.document.file:match("([^/\\]+)$") or ui.document.file
            title = base:gsub("%.%w+$", "")
        end
        return title or ""
    end

    self.tw_booktitle = TextWidget:new{
        text = getBookTitle(), face = self.font_title, fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = sw - pad * 3 - S(44), 
    }
    
    local title_margin_top = S(14)
    local title_margin_bot = S(8)
    local title_h = self.tw_booktitle:getSize().h
    
    self._booktitle_y = top_h + title_margin_top

    self._cbtn_sz  = S(46)
    self.max_title_w = sw - pad * 6 - self._cbtn_sz * 2
    
    self.tw_chapter  = TextWidget:new{ text = "", face = self.font_ch, fgcolor = Blitbuffer.COLOR_BLACK, max_width = self.max_title_w }
    self.tw_info     = TextWidget:new{ text = "", face = self.font_info, fgcolor = Blitbuffer.COLOR_DARK_GRAY }

    self.tw_chapter:setText(_("—"))
    self.tw_info:setText("100% · 9999 / 9999")

    local ch_h = self.tw_chapter:getSize().h
    local info_h = self.tw_info:getSize().h

    self._slider = ProgressSlider:new{
        width     = sw - pad * 4,
        value     = self._cur_page,
        value_min = 1,
        value_max = self._total_pages,
        ticks     = nil,
    }
    local slider_h = self._slider:getSize().h

    self.tw_lib      = TextWidget:new{ text = "\u{F015}", face = Font:getFace("cfont", S(26)), fgcolor = Blitbuffer.COLOR_BLACK }
    self.tw_fn       = TextWidget:new{ text = "⚙",   face = Font:getFace("cfont", S(26)), fgcolor = Blitbuffer.COLOR_BLACK }
    self.tw_bm       = TextWidget:new{ text = "\u{F044}", face = Font:getFace("cfont", S(24)), fgcolor = Blitbuffer.COLOR_BLACK }
    self.tw_toc      = TextWidget:new{ text = "☰",   face = Font:getFace("cfont", S(28)), fgcolor = Blitbuffer.COLOR_BLACK } 
    self.tw_aa       = TextWidget:new{ text = "Aa",  face = Font:getFace("cfont", S(20)), fgcolor = Blitbuffer.COLOR_BLACK }
    self.tw_x        = TextWidget:new{ text = "✕",   face = Font:getFace("cfont", S(26)), fgcolor = Blitbuffer.COLOR_BLACK }

    self.tw_ch_l     = TextWidget:new{ text = "‹‹",  face = Font:getFace("cfont", S(32)), fgcolor = Blitbuffer.COLOR_BLACK }
    self.tw_ch_r     = TextWidget:new{ text = "››",  face = Font:getFace("cfont", S(32)), fgcolor = Blitbuffer.COLOR_BLACK }

    -- Aca reducimos el tamaño de los triangulitos para que queden finos
    local font_ctrl_carets = Font:getFace("cfont", S(20))
    local font_ctrl_mark   = Font:getFace("cfont", S(24))
    
    self.tw_ctrl_prev = TextWidget:new{ text = "\u{F0D9}", face = font_ctrl_carets, fgcolor = Blitbuffer.COLOR_BLACK }
    self.tw_ctrl_mark = TextWidget:new{ text = "\u{F097}", face = font_ctrl_mark,   fgcolor = Blitbuffer.COLOR_BLACK }
    self.tw_ctrl_next = TextWidget:new{ text = "\u{F0DA}", face = font_ctrl_carets, fgcolor = Blitbuffer.COLOR_BLACK }

    local p_top    = S(8)
    local spacing1 = S(3)
    local spacing2 = S(4)
    local spacing3 = S(10)
    local mark_sz  = S(36)
    local p_bot    = S(12) 

    local bar_h = p_top + ch_h + spacing1 + info_h + spacing2 + slider_h + spacing3 + mark_sz + p_bot
    local bar_y = sh - bar_h
    self._bar_dimen = Geom:new{ x = 0, y = bar_y, w = sw, h = bar_h }

    local grid_top = self._booktitle_y + title_h + title_margin_bot
    local grid_y_avail = bar_y - grid_top
    self._grid_dimen = Geom:new{ x = 0, y = grid_top, w = sw, h = grid_y_avail }
    self._grid_cols = 3
    self._grid_rows = 1
    self._grid_margin = S(10)

    local is_comic = false
    do
        local file = ui.document and ui.document.file
        local ext = file and file:match("%.([%a%d]+)$")
        if ext then
            ext = ext:lower()
            is_comic = (ext == "cbz" or ext == "cbr" or ext == "cb7" or ext == "cbt")
        end
    end
    self._is_comic = is_comic

    if self._is_comic then
        self._grid_item_w = math.floor((sw - 2 * self._grid_margin) / 3)
        self._grid_item_h = math.floor(self._grid_item_w * sh / sw)
    else
        self._grid_item_h = grid_y_avail - 2 * self._grid_margin
        self._grid_item_w = math.floor(self._grid_item_h * sw / sh)
    end

    self._thumb_req_w = self._grid_item_w
    self._thumb_req_h = self._grid_item_h
    self._grid_tiles      = {}
    self._grid_start_page = nil
    self._grid_batch_id   = nil
    self._grid_batch_seq  = 0
    self._grid_instance_id = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
    self._grid_disabled = not (ui.thumbnail and ui.thumbnail.getPageThumbnail)

    self._fallback_prev_dimen = Geom:new{
        x = 0, y = self._grid_dimen.y, w = math.floor(sw / 3), h = self._grid_dimen.h }
    self._fallback_next_dimen = Geom:new{
        x = sw - math.floor(sw / 3), y = self._grid_dimen.y, w = math.floor(sw / 3), h = self._grid_dimen.h }
    
    self.tw_fb_l = TextWidget:new{ text = "‹", face = Font:getFace("cfont", S(48)), fgcolor = Blitbuffer.COLOR_BLACK }
    self.tw_fb_r = TextWidget:new{ text = "›", face = Font:getFace("cfont", S(48)), fgcolor = Blitbuffer.COLOR_BLACK }

    self._slider.on_change = function(v)
        self:_previewPage(v)
    end

    self:_updateTexts()

    local top_sz    = S(46)
    local spacing   = S(18)
    local left_base = S(16)
    local right_base = sw - S(16)
    local top_y     = top_bar_y + math.floor((top_h - top_sz) / 2)

    self._x_dimen   = Geom:new{ x = right_base - top_sz, y = top_y, w = top_sz, h = top_sz }
    
    self._lib_dimen = Geom:new{ x = left_base, y = top_y, w = top_sz, h = top_sz }
    self._fn_dimen  = Geom:new{ x = self._lib_dimen.x + top_sz + spacing, y = top_y, w = top_sz, h = top_sz }
    self._bm_dimen  = Geom:new{ x = self._fn_dimen.x + top_sz + spacing, y = top_y, w = top_sz, h = top_sz }
    self._aa_dimen  = Geom:new{ x = self._bm_dimen.x + top_sz + spacing, y = top_y, w = top_sz, h = top_sz }
    self._toc_dimen = Geom:new{ x = self._aa_dimen.x + top_sz + spacing, y = top_y, w = top_sz, h = top_sz }
    
    local current_y = bar_y + p_top
    self.ch_y_pos = current_y
    current_y = current_y + ch_h + spacing1

    self.info_y_pos = current_y
    current_y = current_y + info_h + spacing2

    self.slider_y_pos = current_y
    current_y = current_y + slider_h + spacing3

    self.ctrl_y_pos = current_y

    local side_sz = S(30)
    local ctrl_sp = S(10)
    local total_ctrl_w = side_sz * 2 + mark_sz + ctrl_sp * 2
    local ctrl_x = math.floor((sw - total_ctrl_w) / 2)

    self._ctrl_prev_dimen = Geom:new{ x = ctrl_x, y = self.ctrl_y_pos + math.floor((mark_sz - side_sz)/2), w = side_sz, h = side_sz }
    self._ctrl_mark_dimen = Geom:new{ x = ctrl_x + side_sz + ctrl_sp, y = self.ctrl_y_pos, w = mark_sz, h = mark_sz }
    self._ctrl_next_dimen = Geom:new{ x = ctrl_x + side_sz + mark_sz + ctrl_sp * 2, y = self.ctrl_y_pos + math.floor((mark_sz - side_sz)/2), w = side_sz, h = side_sz }

    local text_center_x = math.floor(sw / 2)
    self._prev_ch_dimen = Geom:new{ x = text_center_x - math.floor(self.max_title_w / 2) - self._cbtn_sz - S(6), y = self.ch_y_pos, w = self._cbtn_sz, h = self._cbtn_sz }
    self._next_ch_dimen = Geom:new{ x = text_center_x + math.floor(self.max_title_w / 2) + S(6), y = self.ch_y_pos, w = self._cbtn_sz, h = self._cbtn_sz }

    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }

    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            PrevPage = { { Device.input.group.PgBack } },
            NextPage = { { Device.input.group.PgFwd } },
            NextChapterKey = { { Device.input.group.PrevLine } },
            PrevChapterKey = { { Device.input.group.NextLine } },
        }
    end

    if self._grid_disabled then
        self.ges_events = {
            Tap         = { GestureRange:new{ ges = "tap",        range = self.dimen } },
            Swipe       = { GestureRange:new{ ges = "swipe",      range = self.dimen } },
            MultiSwipe  = { GestureRange:new{ ges = "multiswipe", range = self.dimen } },
        }
    else
        self.ges_events = {
            Tap         = { GestureRange:new{ ges = "tap",          range = self.dimen } },
            Pan         = { GestureRange:new{ ges = "pan",          range = self.dimen } },
            PanRelease  = { GestureRange:new{ ges = "pan_release",  range = self.dimen } },
            Swipe       = { GestureRange:new{ ges = "swipe",        range = self.dimen } },
            MultiSwipe  = { GestureRange:new{ ges = "multiswipe",   range = self.dimen } },
            Hold        = { GestureRange:new{ ges = "hold",         range = self.dimen } },
            HoldRelease = { GestureRange:new{ ges = "hold_release", range = self.dimen } },
            Release     = { GestureRange:new{ ges = "release",      range = self.dimen } },
        }
    end

    if not self._grid_disabled then
        local ok_clear, err_clear = pcall(function() DocCache:clear() end)
        if not ok_clear then
            logger.warn("page-scrubber: failed to clear DocCache:", err_clear)
        end

        UIManager:scheduleIn(self._is_comic and 0.5 or 0.15, function()
            if not self._closing then self:_updateGridPages() end
        end)
    end
end

function PageScrubber:onPrevPage() self:_previewPage(self._cur_page - 1); return true end
function PageScrubber:onNextPage() self:_previewPage(self._cur_page + 1); return true end
function PageScrubber:onNextChapterKey() self:_nextChapter(); return true end
function PageScrubber:onPrevChapterKey() self:_prevChapter(); return true end

function PageScrubber:_getChapter(page)
    if self.ui.toc then
        local t = self.ui.toc:getTocTitleByPage(page)
        if t and t ~= "" then return t end
    end
    return _("—")
end

function PageScrubber:_getAllBookmarks()
    local bms_map = {}
    local tp = self._total_pages or 1

    local function add_page(p)
        if not p then return end
        if type(p) == "number" and p >= 1 and p <= tp then
            bms_map[math.floor(p)] = true
        elseif type(p) == "string" then
            local n = tonumber(p)
            if n and n >= 1 and n <= tp then
                bms_map[math.floor(n)] = true
            elseif self.ui.document and self.ui.document.getPageFromXPointer then
                pcall(function()
                    local xp = self.ui.document:getPageFromXPointer(p)
                    if type(xp) == "number" and xp >= 1 and xp <= tp then
                        bms_map[math.floor(xp)] = true
                    end
                end)
            end
        end
    end

    local function extract(list, strict_bookmark_only)
        if type(list) ~= "table" then return end
        for k, v in pairs(list) do
            if type(v) == "table" then
                local is_bm = (v.bookmark == true) or (v.type == "bookmark")
                local has_drawer = v.drawer ~= nil 
                
                if not strict_bookmark_only or is_bm or (not has_drawer and not v.highlight) then
                    add_page(v.page)
                    add_page(v.pos0)
                    add_page(v.xpointer)
                end
            else
                if type(k) == "string" then add_page(k) end
                if type(k) == "number" and (type(v) == "string" or type(v) == "boolean") then add_page(k) end
                if type(v) == "number" then add_page(v) end
                if type(v) == "string" then add_page(v) end
            end
        end
    end

    pcall(function() extract(self.ui.doc_props and self.ui.doc_props.bookmarks, false) end)
    pcall(function() extract(self.ui.bookmark and self.ui.bookmark._bookmarks, false) end)
    pcall(function() extract(self.ui.bookmark and self.ui.bookmark.bookmarks, false) end)
    pcall(function() extract(self.ui.annotation and self.ui.annotation.annotations, true) end)

    local bms = {}
    for p, _ in pairs(bms_map) do table.insert(bms, p) end
    return bms
end

function PageScrubber:_isCurrentPageBookmarked()
    local bms = self:_getAllBookmarks()
    for _, p in ipairs(bms) do
        if tonumber(p) == tonumber(self._cur_page) then
            return true
        end
    end
    
    local actual_bg_page = (self.ui.view and self.ui.view.state and self.ui.view.state.page) or self._origin_page
    if self._cur_page == actual_bg_page then
        if self.ui.view and self.ui.view.dogear_visible then
            return true
        end
    end
    
    return false
end

function PageScrubber:_findPrevBookmark()
    local bms = self:_getAllBookmarks()
    local target = nil
    for _, p in ipairs(bms) do
        local num = tonumber(p)
        if num and num < self._cur_page then
            if not target or num > target then
                target = num
            end
        end
    end
    return target
end

function PageScrubber:_findNextBookmark()
    local bms = self:_getAllBookmarks()
    local target = nil
    for _, p in ipairs(bms) do
        local num = tonumber(p)
        if num and num > self._cur_page then
            if not target or num < target then
                target = num
            end
        end
    end
    return target
end

function PageScrubber:_updateTexts()
    local pct = math.floor(self._cur_page / math.max(1, self._total_pages) * 100)
    self.tw_chapter:setText(self:_getChapter(self._cur_page))
    self.tw_info:setText(pct .. "%  ·  " .. self._cur_page .. " / " .. self._total_pages)
end

function PageScrubber:_gridSlotDimen(idx)
    local gd, m = self._grid_dimen, self._grid_margin
    local w, h  = self._grid_item_w, self._grid_item_h
    local mid_x = gd.x + math.floor((gd.w - w) / 2)
    local y     = gd.y + math.floor((gd.h - h) / 2)
    local offsets = { -(w + m), 0, (w + m) }
    return Geom:new{ x = mid_x + offsets[idx], y = y, w = w, h = h }
end

function PageScrubber:_updateGridPages()
    if self._grid_disabled or self._closing then return end
    self._pending_grid_update = false
    local thumbnail = self.ui.thumbnail

    self._grid_batch_seq = self._grid_batch_seq + 1
    local batch_id = "page_scrubber_grid_" .. self._grid_instance_id .. "_" .. tostring(self._grid_batch_seq)
    self._grid_batch_id = batch_id

    local nb_items = self._grid_cols * self._grid_rows
    
    local old_tiles = self._grid_tiles or {}
    self._grid_tiles = {}
    
    for idx = 1, nb_items do
        local page = self._cur_page + (idx - 2)
        local valid = page >= 1 and page <= self._total_pages
        
        self._grid_tiles[idx] = { 
            page = valid and page or nil, 
            loading = valid
        }
        
        if valid then
            for _, old_slot in pairs(old_tiles) do
                if old_slot.page == page and old_slot.tile_bb then
                    self._grid_tiles[idx].tile_bb = old_slot.tile_bb
                    self._grid_tiles[idx].loading = false
                    break
                end
            end
        end
    end

    local request_order = { 2, 1, 3 }
    local missing = {}

    for _, idx in ipairs(request_order) do
        local slot = self._grid_tiles[idx]
        if slot and slot.page and not slot.tile_bb then
            missing[#missing + 1] = idx
        end
    end

    if #missing == 0 then
        self._is_busy = false
        self._tasks_in_flight = 0
        UIManager:setDirty(self, "ui", self._grid_dimen)
        if self._pending_grid_update and not self._closing then
            self._pending_grid_update = false
            self:_updateGridPages()
        end
        return
    end

    self._is_busy = true
    self._tasks_in_flight = #missing
    logger.info("page-scrubber: req batch", batch_id, "cur_page", self._cur_page, "missing", #missing)

    local inter_request_delay = (self._is_comic and self._grid_batch_seq == 1) and 0.45 or 0.15

    local function requestOne(pos)
        if self._closing or self._grid_batch_id ~= batch_id then return end

        local idx = missing[pos]
        if not idx then
            self._is_busy = false
            self._tasks_in_flight = 0
            if self._closing and self.ui.thumbnail and self.ui.thumbnail.tidyCache then
                self.ui.thumbnail:tidyCache()
            end
            if self._pending_grid_update and not self._closing then
                self._pending_grid_update = false
                self:_updateGridPages()
            end
            return
        end

        local slot = self._grid_tiles[idx]
        local req_page = slot and slot.page
        if not req_page then
            requestOne(pos + 1)
            return
        end

        local advanced = false
        local function advance()
            if advanced then return end
            advanced = true
            self._tasks_in_flight = math.max(0, self._tasks_in_flight - 1)
            if not self._closing then
                UIManager:scheduleIn(inter_request_delay, function() requestOne(pos + 1) end)
            end
        end

        local retry_count = 0
        local RETRY_DELAYS = { 0.3, 1.2, 3.0, 6.0 }
        local MAX_RETRIES = #RETRY_DELAYS

        local function dispatch()
            if self._closing or self._grid_batch_id ~= batch_id then return end

            local timed_out = false
            UIManager:scheduleIn(6.9, function()
                if self._closing then return end
                if not advanced and self._grid_batch_id == batch_id then
                    timed_out = true
                    logger.warn("page-scrubber: TIMEOUT page", req_page, "batch", batch_id)

                    if slot then
                        slot.loading = false
                        slot.error = true
                        UIManager:setDirty(self, "ui", self:_gridSlotDimen(idx))
                    end

                    advance()
                end
            end)

            local delayed = thumbnail:getPageThumbnail(req_page, self._thumb_req_w, self._thumb_req_h, batch_id,
                function(tile, resp_batch_id, async_response)
                    if self._closing then return end
                    if timed_out then return end
                    
                    if resp_batch_id ~= batch_id or self._grid_batch_id ~= batch_id then
                        return
                    end

                    local w, h = nil, nil
                    if tile and tile.bb then w, h = tile.bb:getWidth(), tile.bb:getHeight() end

                    local corrupted = false
                    if not tile or not tile.bb or not w or not h or w <= 0 or h <= 0 then
                        corrupted = true
                    end

                    if corrupted and retry_count < MAX_RETRIES then
                        retry_count = retry_count + 1
                        self._thumb_req_w = (self._thumb_req_w == self._grid_item_w) 
                                            and (self._grid_item_w + 1) or self._grid_item_w
                        
                        if not self._closing then
                            UIManager:scheduleIn(RETRY_DELAYS[retry_count], dispatch)
                        end
                        return
                    end

                    if not corrupted then
                        if tile and tile.bb and (w > self._thumb_req_w + 4 or h > self._thumb_req_h + 4) then
                            local ok_scale, scaled = pcall(function()
                                return tile.bb:scale(self._thumb_req_w, self._thumb_req_h)
                            end)
                            if ok_scale and scaled then
                                tile = { bb = scaled }
                            end
                        end
                    else
                        logger.warn("page-scrubber: failed page", req_page)
                    end
                    
                    if corrupted and self._is_comic then
                        pcall(function() DocCache:clear() end)
                    end

                    if not self._closing then
                        if not corrupted and tile then
                            self:_setGridTile(idx, tile)
                        elseif corrupted then
                            slot.loading = false
                            slot.error = true
                        end
                        UIManager:setDirty(self, "ui", self:_gridSlotDimen(idx))
                    end

                    advance()
                end)
            slot.loading = delayed and true or false
        end

        dispatch()
    end

    requestOne(1)

    UIManager:setDirty(self, "ui", self._grid_dimen)
end

function PageScrubber:_waitForIdle(callback)
    if not self._is_busy and (self._tasks_in_flight or 0) == 0 then
        callback()
        return
    end
    UIManager:scheduleIn(0.05, function() self:_waitForIdle(callback) end)
end

function PageScrubber:_setGridTile(idx, tile)
    local slot = self._grid_tiles[idx]
    if not slot then return end
    slot.tile_bb = tile.bb
    slot.loading = false
end

function PageScrubber:_invalidateGridTilesForPage(page)
    for idx, slot in pairs(self._grid_tiles) do
        if slot.page == page then
            slot.tile_bb = nil
            slot.loading = true
            slot.error = nil
        end
    end
end

function PageScrubber:_forceRefreshCurrentTile()
    if self._grid_disabled or self._closing then return end
    local page = self._cur_page
    logger.info("page-scrubber: force refresh requested, page", page)

    self._grid_flash_idx = 2
    UIManager:setDirty(self, "ui", self:_gridSlotDimen(2))

    UIManager:scheduleIn(0.12, function()
        if self._closing then return end
        self._grid_flash_idx = nil

        self:_invalidateGridTilesForPage(page)

        self._thumb_req_w = (self._thumb_req_w == self._grid_item_w)
                            and (self._grid_item_w + 1) or self._grid_item_w

        if self._is_comic then
            pcall(function() DocCache:clear() end)
        end

        UIManager:setDirty(self, "ui", self._grid_dimen)
        self:_updateGridPages()
    end)
end

function PageScrubber:_paintGrid(bb)
    local nb_items = self._grid_cols * self._grid_rows
    for idx = 1, nb_items do
        local slot = self._grid_tiles[idx]
        local rect = self:_gridSlotDimen(idx)
        bb:paintRect(rect.x, rect.y, rect.w, rect.h, Blitbuffer.COLOR_WHITE)
        if slot and slot.page then
            if slot.tile_bb then
                local tw, th = slot.tile_bb:getWidth(), slot.tile_bb:getHeight()
                local ox = rect.x + math.floor((rect.w - tw) / 2)
                local oy = rect.y + math.floor((rect.h - th) / 2)
                bb:blitFrom(slot.tile_bb, ox, oy, 0, 0, tw, th)
            elseif slot.error then
                if not self._tw_grid_error then
                    self._tw_grid_error = TextWidget:new{
                        text = "!", face = Font:getFace("cfont", S(32)),
                        fgcolor = Blitbuffer.COLOR_BLACK,
                    }
                end
                local etsz = self._tw_grid_error:getSize()
                self._tw_grid_error:paintTo(bb, rect.x + math.floor((rect.w - etsz.w) / 2),
                    rect.y + math.floor((rect.h - etsz.h) / 2))
            elseif slot.loading then
                bb:paintRect(rect.x + math.floor(rect.w / 2) - 1, rect.y + math.floor(rect.h / 2) - 1,
                    2, 2, Blitbuffer.COLOR_GRAY)
            end
            
            local is_cur = (idx == 2)
            local border = is_cur and S(3) or S(1)
            bb:paintBorder(rect.x, rect.y, rect.w, rect.h, border, Blitbuffer.COLOR_BLACK, 0)

            if self._grid_flash_idx == idx then
                bb:paintRect(rect.x, rect.y, rect.w, rect.h, Blitbuffer.COLOR_BLACK)
            end
        end
    end
end

function PageScrubber:_gotoPage(page)
    if self._closing then return end
    self._cur_page = math.max(1, math.min(self._total_pages, page))
    self._slider.value = self._cur_page
    self:_updateTexts()

    self._nav_token = (self._nav_token or 0) + 1
    local my_token = self._nav_token
    local target_page = self._cur_page

    self:_waitForIdle(function()
        if self._nav_token == my_token then
            self.ui:handleEvent(Event:new("GotoPage", target_page))
        end
    end)

    if not self._grid_disabled then
        self:_updateGridPages()
    end

    UIManager:setDirty(self, "ui", self.dimen)
end

function PageScrubber:_previewPage(page)
    if self._closing then return end
    
    self._cur_page = math.max(1, math.min(self._total_pages, page))
    self._slider.value = self._cur_page
    self:_updateTexts()
    
    UIManager:setDirty(self, "ui", self.dimen)

    if self._is_busy then 
        self._pending_grid_update = true
        return 
    end

    if not self._grid_disabled then
        self:_updateGridPages()
    end
end

function PageScrubber:_flashAndDo(btn_id, rect, action_func)
    if self._closing then return end
    self._pressed_btn = btn_id
    UIManager:setDirty(self, "ui", rect)
    UIManager:scheduleIn(0.05, function()
        self._pressed_btn = nil
        action_func()
    end)
end

function PageScrubber:paintTo(bb, x, y)
    local ok, err = pcall(function() self:_paintToImpl(bb, x, y) end)
    if not ok then logger.warn("page-scrubber paintTo error:", err) end
end

function PageScrubber:_paintToImpl(bb, x, y)
    local sw   = Screen:getWidth()
    local pad  = S(16)
    local bd   = self._bar_dimen
    local td   = self._top_bar_dimen

    bb:paintRect(td.x, td.y, td.w, td.h, Blitbuffer.COLOR_WHITE)
    bb:paintRect(td.x, td.y + td.h - S(1), td.w, S(1), Blitbuffer.COLOR_BLACK)

    bb:paintRect(bd.x, bd.y, bd.w, bd.h, Blitbuffer.COLOR_WHITE)
    bb:paintRect(bd.x, bd.y, bd.w, S(1), Blitbuffer.COLOR_BLACK)

    local title_strip_y = td.y + td.h
    local title_strip_h = self._grid_dimen.y - title_strip_y
    bb:paintRect(0, title_strip_y, sw, title_strip_h, Blitbuffer.COLOR_WHITE)
    
    local title_x = pad
    
    self.tw_booktitle:paintTo(bb, title_x,     self._booktitle_y)
    self.tw_booktitle:paintTo(bb, title_x + 1, self._booktitle_y)
    self.tw_booktitle:paintTo(bb, title_x,     self._booktitle_y + 1)
    self.tw_booktitle:paintTo(bb, title_x + 1, self._booktitle_y + 1)

    if not self._grid_disabled then
        local gd = self._grid_dimen
        bb:paintRect(gd.x, gd.y, gd.w, gd.h, Blitbuffer.COLOR_WHITE)
        self:_paintGrid(bb)
    else
        local gd = self._grid_dimen
        bb:paintRect(gd.x, gd.y, gd.w, gd.h, Blitbuffer.COLOR_WHITE)
        local pd = self._fallback_prev_dimen
        local nd = self._fallback_next_dimen
        local ptsz = self.tw_fb_l:getSize()
        self.tw_fb_l:paintTo(bb, pd.x + math.floor((pd.w - ptsz.w) / 2), pd.y + math.floor((pd.h - ptsz.h) / 2))
        local ntsz = self.tw_fb_r:getSize()
        self.tw_fb_r:paintTo(bb, nd.x + math.floor((nd.w - ntsz.w) / 2), nd.y + math.floor((nd.h - ntsz.h) / 2))
    end

    local function drawFloatingBtn(btn_id, dimen, tw, is_disabled)
        local is_pressed = (self._pressed_btn == btn_id)
        local fg_color = is_pressed and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        
        if is_disabled then
            fg_color = Blitbuffer.COLOR_LIGHT_GRAY
        end
        
        local cx = dimen.x + math.floor(dimen.w / 2)
        local cy = dimen.y + math.floor(dimen.h / 2)
        
        if btn_id == "ctrl_prev" or btn_id == "ctrl_mark" or btn_id == "ctrl_next" or btn_id == "ch_l" or btn_id == "ch_r" then
            tw.fgcolor = fg_color
            local tsz = tw:getSize()
            local y_offset = 0
            if tw.text == "\u{F097}" or tw.text == "\u{F02E}" then
                y_offset = S(1)
            elseif tw.text == "‹‹" or tw.text == "››" then
                y_offset = -S(1)
            end
            tw:paintTo(bb, cx - math.floor(tsz.w / 2), cy - math.floor(tsz.h / 2) + y_offset)
            return
        end

        if btn_id == "x" or btn_id == "bm" or btn_id == "toc" or btn_id == "aa" or btn_id == "fn" or btn_id == "lib" then
            local bg_color = (is_pressed and not is_disabled) and Blitbuffer.COLOR_BLACK or nil
            
            if bg_color then
                paintRoundRect(bb, dimen.x, dimen.y, dimen.w, dimen.h, S(8), bg_color)
            end
            
            tw.fgcolor = fg_color
            local tsz = tw:getSize()
            local y_offset = 0
            if tw.text == "\u{F015}" or tw.text == "\u{F0F6}" or tw.text == "\u{F02D}" or tw.text == "\u{F044}" then
                y_offset = S(1)
            end
            tw:paintTo(bb, cx - math.floor(tsz.w / 2), cy - math.floor(tsz.h / 2) + y_offset)
            return
        end
    end

    drawFloatingBtn("lib", self._lib_dimen, self.tw_lib)
    drawFloatingBtn("fn", self._fn_dimen, self.tw_fn)
    drawFloatingBtn("bm", self._bm_dimen, self.tw_bm)
    drawFloatingBtn("toc", self._toc_dimen, self.tw_toc)
    drawFloatingBtn("aa", self._aa_dimen, self.tw_aa)
    drawFloatingBtn("x", self._x_dimen, self.tw_x)

    local can_prev_ch = self.ui.toc and self.ui.toc:getPreviousChapter(self._cur_page) ~= nil
    local can_next_ch = self.ui.toc and self.ui.toc:getNextChapter(self._cur_page) ~= nil

    drawFloatingBtn("ch_l", self._prev_ch_dimen, self.tw_ch_l, not can_prev_ch)
    drawFloatingBtn("ch_r", self._next_ch_dimen, self.tw_ch_r, not can_next_ch)

    local is_marked = self:_isCurrentPageBookmarked()
    self.tw_ctrl_mark:setText(is_marked and "\u{F02E}" or "\u{F097}")

    local has_prev_bm = self:_findPrevBookmark() ~= nil
    local has_next_bm = self:_findNextBookmark() ~= nil

    drawFloatingBtn("ctrl_prev", self._ctrl_prev_dimen, self.tw_ctrl_prev, not has_prev_bm)
    drawFloatingBtn("ctrl_mark", self._ctrl_mark_dimen, self.tw_ctrl_mark, false)
    drawFloatingBtn("ctrl_next", self._ctrl_next_dimen, self.tw_ctrl_next, not has_next_bm)

    local csz_tw = self.tw_chapter:getSize()
    self.tw_chapter:paintTo(bb, math.floor((sw - csz_tw.w) / 2), self.ch_y_pos)

    local isz = self.tw_info:getSize()
    self.tw_info:paintTo(bb, math.floor((sw - isz.w) / 2), self.info_y_pos)

    local slider_x = pad * 2
    
    self._slider.bookmarks = self:_getAllBookmarks()
    self._slider.value = self._cur_page
    self._slider:paintTo(bb, slider_x, self.slider_y_pos)
end

function PageScrubber:_closeReturn()
    if self._closing then return end
    self._closing = true
    self:_cancelHold()
    if self._cur_page ~= self._origin_page then
        self.ui:handleEvent(Event:new("GotoPage", self._origin_page))
    end
    UIManager:close(self)
end

function PageScrubber:_closeStay()
    if self._closing then return end
    self._closing = true
    self:_cancelHold()
    UIManager:close(self)
end

function PageScrubber:_closeAndShow(event_name)
    if self._closing then return end
    self._closing = true
    self:_cancelHold()
    UIManager:close(self)

    UIManager:scheduleIn(0.15, function()
        local ok, err = pcall(function() self.ui:handleEvent(Event:new(event_name)) end)
        if not ok then
            logger.warn("page-scrubber: failed event", event_name)
        end
    end)
end

function PageScrubber:_closeAndOpenMenu()
    if self._closing then return end
    self._closing = true
    self:_cancelHold()
    local ui = self.ui
    UIManager:close(self)
    
    UIManager:scheduleIn(0.15, function()
        if ui and ui.menu and ui.menu.onShowMenu then
            ui.menu:onShowMenu()
        end
    end)
end

function PageScrubber:_startHold(action)
    self._hold_active = true
    self._hold_token = self._hold_token + 1
    local current_token = self._hold_token
    
    local delay = 0.55
    local max_steps = 20
    local steps = 0

    local function rep()
        if not self._hold_active or self._closing or self._hold_token ~= current_token then 
            self:_cancelHold()
            return 
        end
        
        steps = steps + 1
        if steps > max_steps then
            self:_cancelHold()
            return
        end
        
        if action == "prev" then 
            if self._cur_page > 1 then 
                self:_previewPage(self._cur_page - 1) 
            else 
                self:_cancelHold(); return 
            end
        elseif action == "next" then 
            if self._cur_page < self._total_pages then 
                self:_previewPage(self._cur_page + 1) 
            else 
                self:_cancelHold(); return 
            end
        end
        
        UIManager:scheduleIn(delay, rep)
    end
    
    UIManager:scheduleIn(delay, rep)
end

function PageScrubber:_cancelHold()
    self._hold_active = false
    self._hold_token = self._hold_token + 1
end

function PageScrubber:onHide()
    self:_cancelHold()
end

function PageScrubber:_prevChapter()
    local ui = self.ui
    if ui.toc then
        local p = ui.toc:getPreviousChapter(self._cur_page)
        if p then self:_previewPage(p) end
    end
end

function PageScrubber:_nextChapter()
    local ui = self.ui
    if ui.toc then
        local p = ui.toc:getNextChapter(self._cur_page)
        if p then self:_previewPage(p) end
    end
end

function PageScrubber:onTap(_, ges)
    self:_cancelHold()
    if self._closing then return true end

    if self._lib_dimen and ges.pos:intersectWith(self._lib_dimen) then
        self:_flashAndDo("lib", self._lib_dimen, function() self:_closeAndShow("Home") end)
        return true
    end
    if self._fn_dimen and ges.pos:intersectWith(self._fn_dimen) then
        self:_flashAndDo("fn", self._fn_dimen, function() self:_closeAndOpenMenu() end)
        return true
    end
    if self._toc_dimen and ges.pos:intersectWith(self._toc_dimen) then
        self:_flashAndDo("toc", self._toc_dimen, function() self:_closeAndShow("ShowToc") end)
        return true
    end
    if self._aa_dimen and ges.pos:intersectWith(self._aa_dimen) then
        self:_flashAndDo("aa", self._aa_dimen, function() self:_closeAndShow("ShowConfigMenu") end)
        return true
    end
    if self._bm_dimen and ges.pos:intersectWith(self._bm_dimen) then
        self:_flashAndDo("bm", self._bm_dimen, function() self:_closeAndShow("ShowBookmark") end)
        return true
    end
    if self._x_dimen and ges.pos:intersectWith(self._x_dimen) then
        self:_flashAndDo("x", self._x_dimen, function() self:_closeReturn() end)
        return true
    end

    if self._ctrl_prev_dimen and ges.pos:intersectWith(self._ctrl_prev_dimen) then
        local target = self:_findPrevBookmark()
        if target then
            self:_flashAndDo("ctrl_prev", self._ctrl_prev_dimen, function()
                self:_previewPage(target)
            end)
        end
        return true
    end
    
    if self._ctrl_mark_dimen and ges.pos:intersectWith(self._ctrl_mark_dimen) then
        local target_page = self._cur_page
        self:_flashAndDo("ctrl_mark", self._ctrl_mark_dimen, function()
            self:_waitForIdle(function()
                if self._closing then return end

                self:_invalidateGridTilesForPage(target_page)

                local ok, err = pcall(function()
                    self.ui:handleEvent(Event:new("GotoPage", target_page))
                    self.ui:handleEvent(Event:new("ToggleBookmark"))
                end)
                if not ok then
                    logger.warn("page-scrubber: ToggleBookmark failed:", err)
                end

                if not self._closing then
                    self:_updateGridPages()
                    UIManager:setDirty(self, "ui", self.dimen)
                end
            end)
        end)
        return true
    end
    
    if self._ctrl_next_dimen and ges.pos:intersectWith(self._ctrl_next_dimen) then
        local target = self:_findNextBookmark()
        if target then
            self:_flashAndDo("ctrl_next", self._ctrl_next_dimen, function()
                self:_previewPage(target)
            end)
        end
        return true
    end
    
    if self._prev_ch_dimen and ges.pos:intersectWith(self._prev_ch_dimen) then
        self:_flashAndDo("ch_l", self._prev_ch_dimen, function() self:_prevChapter() end)
        return true
    end
    if self._next_ch_dimen and ges.pos:intersectWith(self._next_ch_dimen) then
        self:_flashAndDo("ch_r", self._next_ch_dimen, function() self:_nextChapter() end)
        return true
    end
    if self._slider:handleTap(ges) then return true end
    
    if self._bar_dimen and ges.pos:intersectWith(self._bar_dimen) then
        return true
    end

    if self._top_bar_dimen and ges.pos:intersectWith(self._top_bar_dimen) then
        return true
    end

    if not self._grid_disabled and self._grid_dimen and ges.pos:intersectWith(self._grid_dimen) then
        local nb_items = self._grid_cols * self._grid_rows
        for idx = 1, nb_items do
            local rect = self:_gridSlotDimen(idx)
            if ges.pos:intersectWith(rect) then
                local slot = self._grid_tiles[idx]
                if slot and slot.page then
                    
                    if idx == 2 then
                        if slot.error then
                            pcall(function() DocCache:clear() end)
                        end
                        self:_gotoPage(slot.page)
                        self:_closeStay()
                        
                    elseif slot.error then
                        slot.error = false
                        slot.loading = true
                        UIManager:setDirty(self, "ui", rect)

                        self._thumb_req_w = (self._thumb_req_w == self._grid_item_w) 
                                            and (self._grid_item_w + 1) or self._grid_item_w
                        
                        self:_updateGridPages()
                    else
                        self:_previewPage(slot.page)
                    end
                    
                end
                return true
            end
        end
        return true
    end

    if self._grid_disabled and self._grid_dimen and ges.pos:intersectWith(self._grid_dimen) then
        if ges.pos.intersectWith and ges.pos:intersectWith(self._fallback_prev_dimen) then
            self:_previewPage(self._cur_page - 1)
        elseif ges.pos.intersectWith and ges.pos:intersectWith(self._fallback_next_dimen) then
            self:_previewPage(self._cur_page + 1)
        else
            self:_gotoPage(self._cur_page)
            self:_closeStay()
        end
        return true
    end

    return true
end

function PageScrubber:onPan(_, ges)
    if self._closing then return true end
    if self._slider:handlePan(ges) then 
        return true 
    end
    self:_cancelHold()
    return true
end

function PageScrubber:onPanRelease(_, ges)
    self:_cancelHold()
    if self._closing then return true end
    if self._slider:handlePanRelease(ges) then return true end
    return true
end

function PageScrubber:onSwipe(_, ges)
    if self._closing then return true end

    if self._bar_dimen and ges.pos and ges.pos.y >= self._bar_dimen.y then
        return true
    end

    if ges.direction == "west" then
        self:_previewPage(self._cur_page + 1)
        return true
    elseif ges.direction == "east" then
        self:_previewPage(self._cur_page - 1)
        return true
    elseif ges.direction == "south" then
        self:_closeReturn()
        return true
    end
    return false
end

function PageScrubber:onMultiSwipe(_, ges)
    if self._closing then return true end
    if ges.direction == "south" then
        self:_closeReturn()
        return true
    end
    return false
end

function PageScrubber:onHold(_, ges)
    if self._closing then return true end
    if not self._grid_disabled and self._grid_dimen then
        if ges.pos:intersectWith(self:_gridSlotDimen(1)) then
            self:_startHold("prev"); return true
        end
        if ges.pos:intersectWith(self:_gridSlotDimen(3)) then
            self:_startHold("next"); return true
        end
        if ges.pos:intersectWith(self:_gridSlotDimen(2)) then
            self:_forceRefreshCurrentTile(); return true
        end
    elseif self._grid_disabled and self._grid_dimen then
        if ges.pos and ges.pos.intersectWith and ges.pos:intersectWith(self._fallback_prev_dimen) then
            self:_startHold("prev"); return true
        end
        if ges.pos and ges.pos.intersectWith and ges.pos:intersectWith(self._fallback_next_dimen) then
            self:_startHold("next"); return true
        end
    end
    return true
end

function PageScrubber:onHoldRelease(_, ges)
    self:_cancelHold()
    return true
end

function PageScrubber:onRelease(_, ges)
    self:_cancelHold()
    return true
end

function PageScrubber:onCloseWidget()
    self._closing = true
    self:_cancelHold()

    if not self._grid_disabled then
        self._grid_tiles = {}
        if (self._tasks_in_flight or 0) == 0 and self.ui.thumbnail and self.ui.thumbnail.tidyCache then
            self.ui.thumbnail:tidyCache()
        end
    end

    if self._old_can_do then
        Device.canDoSwipeAnimation = self._old_can_do
    end
    if self._saved_swipe_animations ~= nil then
        Screen.swipe_animations = self._saved_swipe_animations
    end

    if self.tw_chapter then self.tw_chapter:free() end
    if self.tw_booktitle then self.tw_booktitle:free() end
    if self._tw_grid_error then self._tw_grid_error:free() end
    if self.tw_info then self.tw_info:free() end
    if self.tw_toc then self.tw_toc:free() end
    if self.tw_bm then self.tw_bm:free() end
    if self.tw_aa then self.tw_aa:free() end
    if self.tw_fn then self.tw_fn:free() end
    if self.tw_lib then self.tw_lib:free() end
    if self.tw_x then self.tw_x:free() end
    if self.tw_fb_l then self.tw_fb_l:free() end
    if self.tw_fb_r then self.tw_fb_r:free() end
    if self.tw_ctrl_prev then self.tw_ctrl_prev:free() end
    if self.tw_ctrl_mark then self.tw_ctrl_mark:free() end
    if self.tw_ctrl_next then self.tw_ctrl_next:free() end
    if self.tw_ch_l then self.tw_ch_l:free() end
    if self.tw_ch_r then self.tw_ch_r:free() end
end

function PageScrubber:onClose()
    self:_closeStay()
    return true
end

Dispatcher:registerAction("page_scrubber_action", {
    category = "none",
    event    = "PageScrubber",
    title    = _("Page Scrubber"),
    reader   = true,
})

function ReaderUI:onPageScrubber()
    local ui = self
    if not ui.document then return end

    UIManager:nextTick(function()
        if not ui or not ui.document then return end
        UIManager:show(PageScrubber:new{ ui = ui, document = ui.document })
        if Device:isKindle() then
            UIManager:setDirty(nil, "full")
        end
    end)
end

logger.info("page-scrubber patch: loaded")
