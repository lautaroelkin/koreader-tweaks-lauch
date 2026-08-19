--[[
    2-page-scrubber.lua
    Page scrubber overlay (Kindle E-ink optimized)
    - Sacred Center Logic
    - Semaphore Protection
    - Original Fluid Slider (Restored)
    - Swipe Filter
    - Custom UI
    - Soft Retries
    - Spread Fix
    - Compact 3-Page Grid
    - Anti-Crash Shield (C-Level Blitting sin consumo de RAM)
    - RAM Micro-Nap & Timeout Extension
    - Title Formatting
    - D-Pad Chapter Navigation
    - Swipe Down to Close
    - Zombie Widget Fix
    - Sync Redraw Fix
    - UNIFIED ENGINE: Split-Screen as a 1-page Grid
    - Caché de Marcadores Descendente
    - FIX DEFINITIVO: Safe Bookmark Toggle
    - Dynamic UI Scaling
    - STATIC SPLIT LAYOUT (Anclajes Absolutos Superior/Inferior)
    - SMART MENU SWIPE (Navegación dividida por zonas asimétricas 65/35)
    - LONG PRESS TO GRID
    - FLIPPED LAYOUT (Preview L, Menu R) & Empty State
    - ROUNDED FIXED BOOKMARK (Pronounced) 
    - DYNAMIC FIXED PAGE (Captures current page on split activation)
    - OUTLINE ELEGANT ICONS
    - PERFECT PIXEL ALIGNMENT RESTORED
    - TABS IN TITLE STRIP & CENTERED BLOCK ALIGNMENT
    - MODERN CARD UI WITH DROP SHADOWS AND PILL HIGHLIGHTS
    - FORMATTED ENGLISH DATES, PANEL ICONS & DYNAMIC TAB COUNTS
    - 65/35 ASYMMETRIC SPLIT (Wider Preview)
    - INTEGRATED POLAROID STATUS (Dynamic text inside left card)
    - CLEAN RIGHT MENU (Folder Tab Illusion, clean numbers only)
    - UNIFIED DESIGN SYSTEM (3 Text Sizes + Grey Punchy Duplication)
    - FIX: EXACT UTF-8 POLAROID TEXT MEASUREMENT
    - FIX: "Pag" / "P" TAB & POLISHED FOLDER TABS
    - FIX: DYNAMIC TAB MERGING, VERTICAL ICON ALIGNMENT & ZOOMED TILE SHIELD
    - FIX: PERFECT ICON CENTERING, COMPACT TOP BUTTONS & ADAPTIVE FOLDER TAB GRID
    - FIX: ULTRA FAST GRID REUSE (TAGGED MODE CACHE) & PRECISE ICON ALIGNMENT
    - FEATURE: MULTI-GESTURE DISPATCHER ACTIONS (Direct Split/Menu & Highlights Launch)
    - FEATURE: SORT TOGGLE TAB (ASC/DESC ORDERING) & BOLD LIBRARY LABEL
    - FIX: HIGHLIGHT TAB FILTER RESET & LOWERED BOX BUTTONS ALIGNMENT
    - FIX DEFINITIVO: INSTANT CURRENT PAGE HIGHLIGHT / NOTE INCLUSION IN MENU LIST
    - FIX: CRISP SOLID FOLDER TABS & CONFIG BUTTON +1PX VERTICAL SHIFT
    - FIX: FLUSH BOTTOM EDGE (SIDE-ONLY SHADOWS, NO BOTTOM BLEED)
    - FIX: CRASH ON CLOSE (DRAW RACE CONDITION), WIDER "P" TAB & TOC SCREENSHOT HOLD
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
local SpinWidget      = require("ui/widget/spinwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local logger          = require("logger")
local _               = require("gettext")

local Screen = Device.screen

-- =========================================================================
-- USER CONFIGURATION
local SETTING_KEY = "page_scrubber_ui_scale"
local DEFAULT_UI_SCALE = 1.23

local CUSTOM_UI_SCALE = (G_reader_settings and G_reader_settings:readSetting(SETTING_KEY)) or DEFAULT_UI_SCALE
-- =========================================================================

local function S(val)
    local res = math.floor(val * CUSTOM_UI_SCALE)
    if val > 0 and res == 0 then res = 1 end
    return Screen:scaleBySize(res)
end

local function setCustomUIScale(new_scale)
    CUSTOM_UI_SCALE = new_scale
    if G_reader_settings then
        G_reader_settings:saveSetting(SETTING_KEY, new_scale)
        G_reader_settings:flush()
    end
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

-- MOTOR DE DIBUJO: Rectángulo con esquinas individuales
local function paintCornerRect(bb, x, y, w, h, r, color, round_tl, round_tr, round_bl, round_br)
    if w <= 0 or h <= 0 then return end
    r = math.min(r, math.floor(w / 2), math.floor(h / 2))
    if r <= 0 then bb:paintRect(x, y, w, h, color); return end

    bb:paintRect(x + r, y, w - 2*r, h, color)
    bb:paintRect(x, y + r, r, math.max(1, h - 2*r), color)
    bb:paintRect(x + w - r, y + r, r, math.max(1, h - 2*r), color)

    if not round_tl then bb:paintRect(x, y, r, r, color) end
    if not round_tr then bb:paintRect(x + w - r, y, r, r, color) end
    if not round_bl then bb:paintRect(x, y + h - r, r, r, color) end
    if not round_br then bb:paintRect(x + w - r, y + h - r, r, r, color) end

    for j = 0, r - 1 do
        local arc = math.ceil(math.sqrt(r*r - (r-j-0.5)*(r-j-0.5)))
        if arc > 0 then
            if round_tl then bb:paintRect(x + r - arc, y + j,         arc, 1, color) end
            if round_tr then bb:paintRect(x + w - r,   y + j,         arc, 1, color) end
            if round_bl then bb:paintRect(x + r - arc, y + h - 1 - j, arc, 1, color) end
            if round_br then bb:paintRect(x + w - r,   y + h - 1 - j, arc, 1, color) end
        end
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

-- MOTOR DE DIBUJO: Top cuadrado, Bottom redondeado
local function paintTopSquareBottomRounded(bb, x, y, w, h, r, color)
    if w <= 0 or h <= 0 then return end
    paintRoundRect(bb, x, y, w, h, r, color)
    if r > 0 and h > r and w > 0 then
        bb:paintRect(x, y, w, r, color)
    end
end

local function drawBookmarkRibbon(bb, x, y, w, h, color)
    local cut = math.floor(w / 2)
    local straight = h - cut
    if straight > 0 then
        bb:paintRect(x, y, w, straight, color)
    end
    for r = 0, cut - 1 do
        local leg = math.floor(w/2) - r
        if leg > 0 then
            bb:paintRect(x, y + straight + r, leg, 1, color)
            bb:paintRect(x + w - leg, y + straight + r, leg, 1, color)
        end
    end
end

local function processTile(tile, req_w, req_h)
    if not tile or not tile.bb then return nil end
    local w, h = tile.bb:getWidth(), tile.bb:getHeight()
    if w <= 0 or h <= 0 then return nil end
    if w > req_w + 4 or h > req_h + 4 then
        local ok, scaled = pcall(function() return tile.bb:scale(req_w, req_h) end)
        if ok and scaled then return { bb = scaled, is_scaled = true } end
    end
    return { bb = tile.bb, is_scaled = false }
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
    
    paintPill(bb, x, cy - S(2), w, S(4), Blitbuffer.COLOR_LIGHT_GRAY)
    local frac = (self.value - self.value_min) / math.max(1, self.value_max - self.value_min)
    local fw = math.floor(frac * w + 0.5)
    
    if fw > 0 then paintPill(bb, x, cy - S(2), fw, S(4), Blitbuffer.COLOR_BLACK) end

    if self.bookmarks then
        for _, bmpage in ipairs(self.bookmarks) do
            if bmpage >= self.value_min and bmpage <= self.value_max then
                local bmx = math.floor(x + self:_valueToX(bmpage))
                paintCircle(bb, bmx, cy, S(9), Blitbuffer.COLOR_WHITE)
                paintCircle(bb, bmx, cy, S(6), Blitbuffer.COLOR_BLACK)
            end
        end
    end

    if not self._dragging then
        local kx = math.floor(x + self:_valueToX(self.value))
        paintCircle(bb, kx, cy, r, Blitbuffer.COLOR_BLACK)
        paintCircle(bb, kx, cy, r - S(3), Blitbuffer.COLOR_WHITE)
    end
end

function ProgressSlider:handleTap(ges)
    if not self.dimen or not ges.pos:intersectWith(self.dimen) then return false end
    local tap_x = ges.pos.x - self.dimen.x
    local v = self:_xToValue(tap_x)
    if self.bookmarks then
        for _, bmpage in ipairs(self.bookmarks) do
            local bmx = self:_valueToX(bmpage)
            if math.abs(tap_x - bmx) < S(20) then 
                v = bmpage; break
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
    if v ~= self.value then self.value = v end
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
    
    self._view_mode = self.initial_view_mode or "grid" 
    self._active_tab = self.initial_tab or "bookmarks" 
    self._sort_order = "desc" 
    self._split_bm_page = 1  
    self._force_menu_sync = true 
    self._split_fixed_page = (self._view_mode == "split") and self._cur_page or nil 
    self._split_divider_x = nil
    self._hl_filter = nil 
    self._hl_types_present = { normal = false, invert = false, underline = false }
    self._hl_filter_dimens = {}
    self._hl_main_tab_dimen = nil
    self._tab_sort_dimen = nil

    self._cached_bms  = nil
    self._cached_hl   = nil
    self._cached_notes = nil
    self._page_data   = {}
    
    self._is_busy     = true
    self._tasks_in_flight = 0
    self._pending_grid_update = false

    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local pad = S(16)

    local S_GRANDE   = S(15)
    local S_MEDIANO  = S(13)
    local S_CHIQUITO = S(12)

    self._tw_tab_sort = TextWidget:new{ text = "", face = Font:getFace("cfont", S_CHIQUITO) }
    self._tw_tab_bm   = TextWidget:new{ text = "", face = Font:getFace("cfont", S_CHIQUITO) }
    self._tw_tab_hl   = TextWidget:new{ text = "", face = Font:getFace("cfont", S_CHIQUITO) }
    self._tw_tab_note = TextWidget:new{ text = "", face = Font:getFace("cfont", S_CHIQUITO) }

    local top_h     = S(58)
    local top_bar_y = 0
    self._top_bar_dimen = Geom:new{ x = 0, y = top_bar_y, w = sw, h = top_h }

    self.font_ch    = Font:getFace("cfont", S_GRANDE)
    self.font_title = Font:getFace("cfont", S_GRANDE) 
    self.font_info  = Font:getFace("cfont", S_MEDIANO)

    local function getBookTitle()
        local title
        if ui.doc_props and ui.doc_props.title and ui.doc_props.title ~= "" then title = ui.doc_props.title end
        if not title and ui.document and ui.document.getProps then
            local ok, props = pcall(function() return ui.document:getProps() end)
            if ok and props and props.title and props.title ~= "" then title = props.title end
        end
        if not title and ui.document and ui.document.file then
            local base = ui.document.file:match("([^/\\]+)$") or ui.document.file
            title = base:gsub("%.%w+$", "")
        end
        return title or ""
    end

    self._cbtn_sz  = S(46)
    local side_margin_btn = pad + S(6) 
    self.max_title_w = sw - (side_margin_btn * 2) - (self._cbtn_sz * 2) - S(10)
    
    self.tw_booktitle = TextWidget:new{ text = getBookTitle(), face = self.font_title, fgcolor = Blitbuffer.COLOR_BLACK, max_width = sw - pad * 3 - S(44) }
    self.tw_chapter  = TextWidget:new{ text = "", face = self.font_ch, fgcolor = Blitbuffer.COLOR_BLACK, max_width = self.max_title_w }
    self.tw_info     = TextWidget:new{ text = "", face = self.font_info, fgcolor = Blitbuffer.COLOR_DARK_GRAY }

    self.tw_chapter:setText(_("—"))
    self.tw_info:setText("100% · 9999 / 9999")

    local title_margin_top = S(14)
    local title_margin_bot = S(8)
    local title_h = self.tw_booktitle:getSize().h
    
    self._booktitle_y = top_h + title_margin_top

    local ch_h = self.tw_chapter:getSize().h
    local info_h = self.tw_info:getSize().h

    self._slider = ProgressSlider:new{ width = sw - pad * 4, value = self._cur_page, value_min = 1, value_max = self._total_pages, ticks = nil }
    
    self:_invalidateBookmarksCache()
    local slider_h = self._slider:getSize().h

    self.tw_lib       = TextWidget:new{ text = "\u{E344}", face = Font:getFace("cfont", S(24)), fgcolor = Blitbuffer.COLOR_BLACK }
    self.tw_lib_label = TextWidget:new{ text = "Library", face = Font:getFace("cfont", S_MEDIANO), fgcolor = Blitbuffer.COLOR_BLACK }
    
    self.tw_fn        = TextWidget:new{ text = "⚙",   face = Font:getFace("cfont", S(20)), fgcolor = Blitbuffer.COLOR_BLACK }
    self.tw_bm        = TextWidget:new{ text = "\u{F044}", face = Font:getFace("cfont", S(19)), fgcolor = Blitbuffer.COLOR_BLACK }
    self.tw_toc       = TextWidget:new{ text = "\u{F0CA}", face = Font:getFace("cfont", S(17)), fgcolor = Blitbuffer.COLOR_BLACK } 
    self.tw_x         = TextWidget:new{ text = "✕",   face = Font:getFace("cfont", S(22)), fgcolor = Blitbuffer.COLOR_BLACK }

    self.tw_ch_l      = TextWidget:new{ text = "\u{EBAD}",  face = Font:getFace("cfont", S(32)), fgcolor = Blitbuffer.COLOR_BLACK }
    self.tw_ch_r      = TextWidget:new{ text = "\u{EBAC}",  face = Font:getFace("cfont", S(32)), fgcolor = Blitbuffer.COLOR_BLACK }

    local font_ctrl_carets = Font:getFace("cfont", S(20))
    local font_ctrl_mark   = Font:getFace("cfont", S(24))
    
    self.tw_ctrl_prev = TextWidget:new{ text = "\u{F0D9}", face = font_ctrl_carets, fgcolor = Blitbuffer.COLOR_BLACK }
    self.tw_ctrl_mark = TextWidget:new{ text = "\u{F097}", face = font_ctrl_mark,   fgcolor = Blitbuffer.COLOR_BLACK }
    self.tw_ctrl_next = TextWidget:new{ text = "\u{F0DA}", face = font_ctrl_carets, fgcolor = Blitbuffer.COLOR_BLACK }

    self.tw_fb_l = TextWidget:new{ text = "‹", face = Font:getFace("cfont", S(48)), fgcolor = Blitbuffer.COLOR_BLACK }
    self.tw_fb_r = TextWidget:new{ text = "›", face = Font:getFace("cfont", S(48)), fgcolor = Blitbuffer.COLOR_BLACK }

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

    self._split_preview_w = math.floor(sw * 0.45)
    self._thumb_req_split_w = self._split_preview_w - S(20)
    self._thumb_req_split_h = math.floor(self._thumb_req_split_w * sh / sw)

    self._grid_tiles      = {}
    self._grid_start_page = nil
    self._grid_back_dimen = nil
    self._center_bm_touch_dimen = nil
    self._grid_batch_id   = nil
    self._grid_batch_seq  = 0
    self._grid_instance_id = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
    self._grid_disabled = not (ui.thumbnail and ui.thumbnail.getPageThumbnail)

    self._fallback_prev_dimen = Geom:new{ x = 0, y = self._grid_dimen.y, w = math.floor(sw / 3), h = self._grid_dimen.h }
    self._fallback_next_dimen = Geom:new{ x = sw - math.floor(sw / 3), y = self._grid_dimen.y, w = math.floor(sw / 3), h = self._grid_dimen.h }

    self._slider.on_change = function(v)
        self:_previewPage(v, self._slider._dragging)
    end

    self:_updateTexts()

    local btn_sz    = S(38)
    local spacing   = S(8)
    local left_base = S(16)
    local right_base = sw - S(14)
    local top_y     = top_bar_y + math.floor((top_h - btn_sz) / 2)

    self._x_dimen   = Geom:new{ x = right_base - btn_sz, y = top_y, w = btn_sz, h = btn_sz }
    self._fn_dimen  = Geom:new{ x = self._x_dimen.x - spacing - btn_sz, y = top_y, w = btn_sz, h = btn_sz }
    self._bm_dimen  = Geom:new{ x = self._fn_dimen.x - spacing - btn_sz, y = top_y, w = btn_sz, h = btn_sz }
    self._toc_dimen = Geom:new{ x = self._bm_dimen.x - spacing - btn_sz, y = top_y, w = btn_sz, h = btn_sz }

    self._lib_icon_dimen = Geom:new{ x = left_base, y = top_y, w = btn_sz, h = btn_sz }
    local lib_label_gap = S(4)
    local lib_label_sz = self.tw_lib_label:getSize()
    local lib_label_x = self._lib_icon_dimen.x + btn_sz + lib_label_gap
    self._lib_label_x = lib_label_x
    self._lib_label_y = top_bar_y + math.floor((top_h - lib_label_sz.h) / 2)
    self._lib_dimen = Geom:new{ x = left_base, y = top_y, w = (lib_label_x + lib_label_sz.w) - left_base, h = btn_sz }
    
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
    self._ctrl_row_x0 = ctrl_x
    self._ctrl_row_x1 = ctrl_x + total_ctrl_w
    self._ctrl_row_h = mark_sz

    self._ctrl_prev_dimen = Geom:new{ x = ctrl_x, y = self.ctrl_y_pos + math.floor((mark_sz - side_sz)/2), w = side_sz, h = side_sz }
    self._ctrl_mark_dimen = Geom:new{ x = ctrl_x + side_sz + ctrl_sp, y = self.ctrl_y_pos, w = mark_sz, h = mark_sz }
    self._ctrl_next_dimen = Geom:new{ x = ctrl_x + side_sz + mark_sz + ctrl_sp * 2, y = self.ctrl_y_pos + math.floor((mark_sz - side_sz)/2), w = side_sz, h = side_sz }

    self._prev_ch_dimen = Geom:new{ x = side_margin_btn, y = self.ch_y_pos + S(2), w = self._cbtn_sz, h = self._cbtn_sz }
    self._next_ch_dimen = Geom:new{ x = sw - side_margin_btn - self._cbtn_sz, y = self.ch_y_pos + S(2), w = self._cbtn_sz, h = self._cbtn_sz }

    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }

    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            PrevPage = { { Device.input.group.PgBack }, { Device.input.group.Left } },
            NextPage = { { Device.input.group.PgFwd }, { Device.input.group.Right } },
            NextChapterKey = { { Device.input.group.PrevLine }, { Device.input.group.Up } },
            PrevChapterKey = { { Device.input.group.NextLine }, { Device.input.group.Down } },
            Select = { { Device.input.group.Select }, { Device.input.group.Press } },
        }
    end

    if self._grid_disabled then
        self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = self.dimen } }, Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } }, MultiSwipe = { GestureRange:new{ ges = "multiswipe", range = self.dimen } } }
    else
        self.ges_events = {
            Tap         = { GestureRange:new{ ges = "tap",          range = self.dimen } },
            Pan         = { GestureRange:new{ ges = "pan",          range = self.dimen } },
            PanRelease  = { GestureRange:new{ pan_release = "pan_release",  range = self.dimen } },
            Swipe       = { GestureRange:new{ ges = "swipe",        range = self.dimen } },
            MultiSwipe  = { GestureRange:new{ ges = "multiswipe",   range = self.dimen } },
            Hold        = { GestureRange:new{ ges = "hold",         range = self.dimen } },
            HoldRelease = { GestureRange:new{ ges = "hold_release", range = self.dimen } },
            Release     = { GestureRange:new{ ges = "release",      range = self.dimen } },
        }
    end

    if not self._grid_disabled then
        local ok_clear, err_clear = pcall(function() DocCache:clear() end)
        if not ok_clear then logger.warn("page-scrubber: failed to clear DocCache:", err_clear) end
        UIManager:scheduleIn(self._is_comic and 0.5 or 0.15, function()
            if not self._closing then self:_updateGridPages() end
        end)
    end
end

function PageScrubber:_freeTile(slot)
    if slot and slot.is_scaled and slot.tile_bb then
        pcall(function() slot.tile_bb:free() end)
    end
    if slot then
        slot.tile_bb = nil
        slot.is_scaled = false
    end
end

-- =================================================================================
-- SISTEMA DE EXTRACCIÓN SEGURO
-- =================================================================================
function PageScrubber:_invalidateBookmarksCache()
    self._cached_bms = nil
    self._slider.bookmarks = self:_getAllBookmarks()
    self:_extractAnnotations()
end

function PageScrubber:_getNumericalPage(v)
    if type(v) ~= "table" then return nil end
    if v.pageno and tonumber(v.pageno) then return tonumber(v.pageno) end
    
    local function try_convert(xp)
        if not xp then return nil end
        if tonumber(xp) then return tonumber(xp) end
        if self.ui.document and self.ui.document.getPageFromXPointer then
            local ok, res = pcall(function() return self.ui.document:getPageFromXPointer(xp) end)
            if ok and type(res) == "number" then return res end
        end
        return nil
    end
    
    return try_convert(v.page) or try_convert(v.pos0) or try_convert(v.xpointer)
end

function PageScrubber:_getAllBookmarks()
    if self._cached_bms then return self._cached_bms end

    local bms_map = {}
    local tp = self._total_pages or 1

    local function add_page(p)
        if type(p) == "number" and p >= 1 and p <= tp then
            bms_map[math.floor(p)] = true
        end
    end

    local function extract(list, strict_bookmark_only)
        if type(list) ~= "table" then return end
        for k, v in pairs(list) do
            if type(v) == "table" then
                local is_bm = (v.bookmark == true) or (v.type == "bookmark")
                local has_drawer = v.drawer ~= nil 
                if not strict_bookmark_only or is_bm or (not has_drawer and not v.highlight) then
                    local p = self:_getNumericalPage(v)
                    if p then add_page(p) end
                end
            else
                if type(k) == "number" and (type(v) == "string" or type(v) == "boolean") then add_page(k) end
            end
        end
    end

    pcall(function() extract(self.ui.doc_props and self.ui.doc_props.bookmarks, false) end)
    pcall(function() extract(self.ui.bookmark and self.ui.bookmark._bookmarks, false) end)
    pcall(function() extract(self.ui.bookmark and self.ui.bookmark.bookmarks, false) end)
    pcall(function() extract(self.ui.annotation and self.ui.annotation.annotations, true) end)

    local bms = {}
    for p, _ in pairs(bms_map) do table.insert(bms, p) end
    table.sort(bms, function(a, b) return tonumber(a) > tonumber(b) end)
    
    self._cached_bms = bms
    return bms
end

function PageScrubber:_extractAnnotations()
    self._cached_hl = {}
    self._cached_notes = {}
    self._page_data = {}
    self._hl_types_present = { normal = false, invert = false, underline = false }

    local hl_map = {}
    local note_map = {}
    local tp = self._total_pages or 1

    local function drawer_to_filter(drawer)
        if not drawer or drawer == "lighten" then return "normal"
        elseif drawer == "invert" then return "invert"
        elseif drawer == "underscore" or drawer == "strikeout" then return "underline"
        end
        return "normal"
    end

    local function process_item(v, k)
        if type(v) == "table" then
            local p = self:_getNumericalPage(v)
            if type(p) == "number" and p >= 1 and p <= tp then
                p = math.floor(p)
                if not self._page_data[p] then self._page_data[p] = {} end
                
                local date_val = v.datetime or v.time or v.date or v.timestamp
                if date_val and not self._page_data[p].date then
                    self._page_data[p].date = date_val
                end

                local is_real_highlight = (v.drawer ~= nil) or (v.pos0 ~= nil and v.pos1 ~= nil) or (v.highlight == true)
                local is_real_note = (v.note ~= nil and v.note ~= "")
                
                if is_real_note or is_real_highlight then
                    if is_real_highlight and v.text and v.text ~= "" then
                        if self._page_data[p].text and not string.find(self._page_data[p].text, v.text, 1, true) then
                            self._page_data[p].text = self._page_data[p].text .. " | " .. v.text
                        else
                            self._page_data[p].text = v.text
                        end
                        hl_map[p] = true

                        local filt = drawer_to_filter(v.drawer)
                        if filt then
                            if not self._page_data[p].hl_types then self._page_data[p].hl_types = {} end
                            self._page_data[p].hl_types[filt] = true
                            self._hl_types_present[filt] = true
                        end
                    end
                    
                    if is_real_note and v.note and v.note ~= "" then
                        if self._page_data[p].note and not string.find(self._page_data[p].note, v.note, 1, true) then
                            self._page_data[p].note = self._page_data[p].note .. " | " .. v.note
                        else
                            self._page_data[p].note = v.note
                        end
                        note_map[p] = true
                    end
                end
            end
        else
            local p_val = tonumber(k)
            if p_val and p_val >= 1 and p_val <= tp and (type(v) == "string" or type(v) == "number") then
                p_val = math.floor(p_val)
                if not self._page_data[p_val] then self._page_data[p_val] = {} end
                if not self._page_data[p_val].date then
                    self._page_data[p_val].date = v
                end
            end
        end
    end

    if self.ui.annotation and self.ui.annotation.annotations then
        for k, v in pairs(self.ui.annotation.annotations) do process_item(v, k) end
    end
    if self.ui.doc_props and self.ui.doc_props.bookmarks then
        for k, v in pairs(self.ui.doc_props.bookmarks) do process_item(v, k) end
    end
    if self.ui.bookmark and self.ui.bookmark._bookmarks then
        for k, v in pairs(self.ui.bookmark._bookmarks) do process_item(v, k) end
    end
    if self.ui.bookmark and self.ui.bookmark.bookmarks then
        for k, v in pairs(self.ui.bookmark.bookmarks) do process_item(v, k) end
    end
    
    for p, _ in pairs(hl_map) do table.insert(self._cached_hl, p) end
    for p, _ in pairs(note_map) do table.insert(self._cached_notes, p) end
    
    table.sort(self._cached_hl, function(a,b) return tonumber(a) > tonumber(b) end)
    table.sort(self._cached_notes, function(a,b) return tonumber(a) > tonumber(b) end)
end

function PageScrubber:_getFilteredActiveList()
    local fixed_page = self._split_fixed_page or self._origin_page
    local active_list = {}
    if self._active_tab == "bookmarks" then active_list = self:_getAllBookmarks()
    elseif self._active_tab == "highlights" then active_list = self._cached_hl or {}
    elseif self._active_tab == "notes" then active_list = self._cached_notes or {} end

    local other_items = {}
    for _, p in ipairs(active_list) do
        local is_excluded = (self._active_tab == "bookmarks") and (tonumber(p) == tonumber(fixed_page))
        if not is_excluded then
            local passes_filter = true
            if self._active_tab == "highlights" and self._hl_filter then
                local pdata = self._page_data[tonumber(p)]
                passes_filter = pdata and pdata.hl_types and pdata.hl_types[self._hl_filter] or false
            end
            if passes_filter then
                table.insert(other_items, p)
            end
        end
    end

    if self._sort_order == "asc" then
        table.sort(other_items, function(a, b) return tonumber(a) < tonumber(b) end)
    else
        table.sort(other_items, function(a, b) return tonumber(a) > tonumber(b) end)
    end
    return other_items
end

function PageScrubber:onNextChapterKey()
    if self._closing then return true end
    if self._view_mode == "split" then
        local items = self:_getFilteredActiveList()
        if #items > 0 then
            local cur_idx = nil
            for idx, p in ipairs(items) do
                if tonumber(p) == tonumber(self._cur_page) then
                    cur_idx = idx
                    break
                end
            end
            local target_idx = (cur_idx and cur_idx > 1) and (cur_idx - 1) or #items
            self._force_menu_sync = true
            self:_previewPage(items[target_idx], false)
            return true
        end
    else
        self:_prevChapter()
    end
    return true
end

function PageScrubber:onPrevChapterKey()
    if self._closing then return true end
    if self._view_mode == "split" then
        local items = self:_getFilteredActiveList()
        if #items > 0 then
            local cur_idx = nil
            for idx, p in ipairs(items) do
                if tonumber(p) == tonumber(self._cur_page) then
                    cur_idx = idx
                    break
                end
            end
            local target_idx = (cur_idx and cur_idx < #items) and (cur_idx + 1) or 1
            self._force_menu_sync = true
            self:_previewPage(items[target_idx], false)
            return true
        end
    else
        self:_nextChapter()
    end
    return true
end

function PageScrubber:onPrevPage() 
    if self._closing then return true end
    if self._view_mode == "split" then
        if self._active_tab == "notes" then
            self._active_tab = "highlights"
        elseif self._active_tab == "highlights" then
            self._active_tab = "bookmarks"
        else
            self._active_tab = "notes"
        end
        self._split_bm_page = 1
        self:_extractAnnotations()
        UIManager:setDirty(self, "ui", self.dimen)
        return true
    else
        self:_previewPage(self._cur_page - 1, false) 
    end
    return true 
end

function PageScrubber:onNextPage() 
    if self._closing then return true end
    if self._view_mode == "split" then
        if self._active_tab == "bookmarks" then
            self._active_tab = "highlights"
        elseif self._active_tab == "highlights" then
            self._active_tab = "notes"
        else
            self._active_tab = "bookmarks"
        end
        self._split_bm_page = 1
        self:_extractAnnotations()
        UIManager:setDirty(self, "ui", self.dimen)
        return true
    else
        self:_previewPage(self._cur_page + 1, false) 
    end
    return true 
end

function PageScrubber:onSelect()
    if self._closing then return true end
    self:_gotoPage(self._cur_page)
    self:_closeStay()
    return true
end

function PageScrubber:_safeBookmarkToggle(target_page)
    self:_waitForIdle(function()
        if self._closing then return end
        
        self:_invalidateGridTilesForPage(target_page)

        local ok, err = pcall(function()
            self.ui:handleEvent(Event:new("GotoPage", target_page))
            self.ui:handleEvent(Event:new("ToggleBookmark"))
        end)

        if not ok then logger.warn("page-scrubber: safe toggle failed:", err) end

        self:_invalidateBookmarksCache()

        if not self._closing then
            self:_updateGridPages()
            UIManager:setDirty(self, "ui", self.dimen)
        end
    end)
end

function PageScrubber:_getChapter(page)
    if self.ui.toc then
        local t = self.ui.toc:getTocTitleByPage(page)
        if t and t ~= "" then return t end
    end
    return _("—")
end

function PageScrubber:_isCurrentPageBookmarked(check_page)
    local target = check_page or self._cur_page
    local bms = self:_getAllBookmarks()
    for _, p in ipairs(bms) do
        if tonumber(p) == tonumber(target) then
            return true
        end
    end
    
    local actual_bg_page = (self.ui.view and self.ui.view.state and self.ui.view.state.page) or self._origin_page
    if target == actual_bg_page then
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

    if self._view_mode == "split" then
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local available_h = self._grid_dimen.h
        local status_h = S(32)
        local fx_h = S(56)
        local gap_x = S(28)
        
        local max_pr_w_allowed = math.floor((sw - S(40) - gap_x) * 0.65)
        local target_pr_w = max_pr_w_allowed
        local target_pr_h = math.floor(target_pr_w * (sh / sw))
        local max_left_h_allowed = available_h - S(10)
        
        if target_pr_h + status_h > max_left_h_allowed then
            target_pr_h = max_left_h_allowed - status_h
            target_pr_w = math.floor(target_pr_h * (sw / sh))
        end
        
        local left_total_h = target_pr_h + status_h
        local available_menu_h = left_total_h - S(12) - fx_h
        
        if available_menu_h < S(100) then
            left_total_h = S(100) + S(12) + fx_h
            target_pr_h = left_total_h - status_h
            target_pr_w = math.floor(target_pr_h * (sw / sh))
        end
        
        self._thumb_req_split_w = target_pr_w
        self._thumb_req_split_h = target_pr_h
    end

    self._grid_batch_seq = self._grid_batch_seq + 1
    local batch_id = "page_scrubber_grid_" .. self._grid_instance_id .. "_" .. tostring(self._grid_batch_seq)
    self._grid_batch_id = batch_id

    local old_tiles = self._grid_tiles or {}
    self._grid_tiles = {}
    local missing = {}

    local expected_req_w = (self._view_mode == "split") and self._thumb_req_split_w or self._grid_item_w
    local expected_req_h = (self._view_mode == "split") and self._thumb_req_split_h or self._grid_item_h

    if self._view_mode == "grid" then
        local nb_items = self._grid_cols * self._grid_rows
        for idx = 1, nb_items do
            local page = self._cur_page + (idx - 2)
            local valid = page >= 1 and page <= self._total_pages
            
            self._grid_tiles[idx] = { page = valid and page or nil, loading = valid, is_scaled = false, mode = "grid" }
            
            if valid then
                for old_idx, old_slot in pairs(old_tiles) do
                    if old_slot.page == page and old_slot.tile_bb and old_slot.mode == "grid" then
                        self._grid_tiles[idx].tile_bb = old_slot.tile_bb
                        self._grid_tiles[idx].is_scaled = old_slot.is_scaled
                        self._grid_tiles[idx].loading = false
                        old_tiles[old_idx] = nil 
                        break
                    end
                end
            end
        end
        for _, idx in ipairs({ 2, 3, 1 }) do
            local slot = self._grid_tiles[idx]
            if slot and slot.page and not slot.tile_bb then
                missing[#missing + 1] = idx
            end
        end
    else
        local page = self._cur_page
        local valid = page >= 1 and page <= self._total_pages
        self._grid_tiles[2] = { page = valid and page or nil, loading = valid, is_scaled = false, mode = "split" }
        
        if valid then
            for old_idx, old_slot in pairs(old_tiles) do
                if old_slot.page == page and old_slot.tile_bb and old_slot.mode == "split" then
                    self._grid_tiles[2].tile_bb = old_slot.tile_bb
                    self._grid_tiles[2].is_scaled = old_slot.is_scaled
                    self._grid_tiles[2].loading = false
                    old_tiles[old_idx] = nil 
                    break
                end
            end
        end
        if self._grid_tiles[2] and self._grid_tiles[2].page and not self._grid_tiles[2].tile_bb then
            missing[#missing + 1] = 2
        end
    end

    for _, old_slot in pairs(old_tiles) do
        self:_freeTile(old_slot)
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
    
    local inter_request_delay = (self._is_comic and self._grid_batch_seq == 1) and 0.45 or 0.01

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
            if self._tasks_in_flight == 0 then
                self._is_busy = false
                if self._pending_grid_update and not self._closing then
                    self._pending_grid_update = false
                    self:_updateGridPages()
                end
            end
            if not self._closing then
                UIManager:scheduleIn(inter_request_delay, function() requestOne(pos + 1) end)
            end
        end

        local retry_count = 0
        local RETRY_DELAYS = { 0.3, 1.2, 3.0, 6.0 }
        local MAX_RETRIES = #RETRY_DELAYS
        
        local base_req_w = (self._view_mode == "split") and self._thumb_req_split_w or self._grid_item_w
        local current_req_w = base_req_w
        local current_req_h = (self._view_mode == "split") and self._thumb_req_split_h or self._grid_item_h

        local function dispatch()
            if self._closing or self._grid_batch_id ~= batch_id then return end

            local timed_out = false
            UIManager:scheduleIn(6.9, function()
                if self._closing then return end
                if not advanced and self._grid_batch_id == batch_id then
                    timed_out = true
                    if retry_count < MAX_RETRIES then
                        retry_count = retry_count + 1
                        current_req_w = (current_req_w == base_req_w) and (base_req_w + 1) or base_req_w
                        if not self._closing then
                            self:_nudgeDecoder(req_page)
                            UIManager:scheduleIn(RETRY_DELAYS[retry_count], dispatch)
                        end
                        return
                    end

                    if slot then
                        slot.loading = false
                        slot.error = true
                        UIManager:setDirty(self, "ui", self._grid_dimen)
                    end
                    advance()
                end
            end)

            thumbnail:getPageThumbnail(req_page, current_req_w, current_req_h, batch_id,
                function(tile, resp_batch_id, async_response)
                    if self._closing then return end
                    if timed_out then return end
                    if resp_batch_id ~= batch_id or self._grid_batch_id ~= batch_id then return end

                    local processed = processTile(tile, current_req_w, current_req_h)
                    local corrupted = false
                    if not processed or not processed.bb then corrupted = true end

                    if corrupted and retry_count < MAX_RETRIES then
                        retry_count = retry_count + 1
                        current_req_w = (current_req_w == base_req_w) and (base_req_w + 1) or base_req_w
                        if not self._closing then
                            self:_nudgeDecoder(req_page)
                            UIManager:scheduleIn(RETRY_DELAYS[retry_count], dispatch)
                        end
                        return
                    end

                    if corrupted and self._is_comic then pcall(function() DocCache:clear() end) end

                    if not self._closing then
                        if not corrupted and processed then
                            slot.tile_bb = processed.bb
                            slot.is_scaled = processed.is_scaled
                            slot.loading = false
                        elseif corrupted then
                            slot.loading = false
                            slot.error = true
                        end
                        UIManager:setDirty(self, "ui", self._grid_dimen)
                    end
                    advance()
                end)
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

function PageScrubber:_invalidateGridTilesForPage(page)
    for idx, slot in pairs(self._grid_tiles) do
        if slot.page == page then
            self:_freeTile(slot)
            slot.loading = true
            slot.error = nil
        end
    end
end

function PageScrubber:_clearGridTiles()
    for idx, slot in pairs(self._grid_tiles) do
        self:_freeTile(slot)
        slot.loading = true
        slot.error = nil
    end
end

function PageScrubber:_nudgeDecoder(page)
    if self._closing or not self._is_comic then return end
    local thumbnail = self.ui.thumbnail
    if not thumbnail or not thumbnail.getPageThumbnail then return end

    local neighbor = page + 3
    if neighbor > self._total_pages then neighbor = page - 3 end
    if neighbor < 1 or neighbor > self._total_pages or neighbor == page then return end

    pcall(function()
        thumbnail:getPageThumbnail(neighbor, self._thumb_req_w, self._thumb_req_h,
            "page_scrubber_nudge_" .. tostring(neighbor), function() end)
    end)
end

function PageScrubber:_forceRefreshCurrentTile()
    if self._grid_disabled or self._closing then return end
    local page = self._cur_page

    self._grid_flash_idx = 2
    UIManager:setDirty(self, "ui", self:_gridSlotDimen(2))

    UIManager:scheduleIn(0.12, function()
        if self._closing then return end
        self._grid_flash_idx = nil

        self:_nudgeDecoder(page)
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
    local all_bms = self:_getAllBookmarks()
    self._center_bm_touch_dimen = nil

    local sw, sh = Screen:getWidth(), Screen:getHeight()

    for idx = 1, nb_items do
        local slot = self._grid_tiles[idx]
        local rect = self:_gridSlotDimen(idx)
        local is_cur = (idx == 2)
        local border = is_cur and S(3) or S(1)

        bb:paintRect(rect.x, rect.y, rect.w, rect.h, Blitbuffer.COLOR_WHITE)
        
        if slot and slot.page then
            if slot.tile_bb then
                local tw, th = slot.tile_bb:getWidth(), slot.tile_bb:getHeight()
                local src_x, src_y = 0, 0
                local blit_w, blit_h = tw, th
                
                if blit_w > rect.w then
                    src_x = math.floor((blit_w - rect.w) / 2)
                    blit_w = rect.w
                end
                if blit_h > rect.h then
                    src_y = math.floor((blit_h - rect.h) / 2)
                    blit_h = rect.h
                end

                local ox = rect.x + math.floor((rect.w - blit_w) / 2)
                local oy = rect.y + math.floor((rect.h - blit_h) / 2)
                
                if ox < 0 then src_x = src_x - ox; blit_w = blit_w + ox; ox = 0 end
                if oy < 0 then src_y = src_y - oy; blit_h = blit_h + oy; oy = 0 end
                if ox + blit_w > sw then blit_w = sw - ox end
                if oy + blit_h > sh then blit_h = sh - oy end
                
                if blit_w > 0 and blit_h > 0 then
                    bb:blitFrom(slot.tile_bb, ox, oy, src_x, src_y, blit_w, blit_h)
                end
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
            
            if self._grid_flash_idx == idx then
                bb:paintRect(rect.x, rect.y, rect.w, rect.h, Blitbuffer.COLOR_BLACK)
            end
            
            local is_bmed = false
            for _, bmp in ipairs(all_bms) do
                if tonumber(bmp) == tonumber(slot.page) then
                    is_bmed = true
                    break
                end
            end
            
            if is_cur then
                local bw, bh = S(28), S(46)
                local bx = rect.x + rect.w - bw - S(16) - border
                local by = rect.y + border
                self._center_bm_touch_dimen = Geom:new{ x = bx - S(10), y = by, w = bw + S(20), h = bh + S(20) }
            end
            
            if is_bmed then
                local bw, bh = S(28), S(46)
                local bx = rect.x + rect.w - bw - S(16) - border
                local by = rect.y + border
                
                local mask_x = bx - S(2)
                local mask_y = by
                local mask_w = (rect.x + rect.w - border) - mask_x
                local mask_h = S(26)
                
                bb:paintRect(mask_x, mask_y, mask_w, mask_h, Blitbuffer.COLOR_WHITE)
                drawBookmarkRibbon(bb, bx, by, bw, bh, Blitbuffer.COLOR_BLACK)
            end

            bb:paintBorder(rect.x, rect.y, rect.w, rect.h, border, Blitbuffer.COLOR_BLACK, 0)
        end
    end
end

function PageScrubber:_paintSplitView(bb, title_strip_y, title_strip_h)
    local gd = self._grid_dimen
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    
    bb:paintRect(gd.x, gd.y, gd.w, gd.h, Blitbuffer.COLOR_WHITE)
    
    local shadow_offset = S(4)
    local box_radius = S(12)
    local font_sz_chiquito = S(12)
    local S_MEDIANO = S(13)
    
    -- ==========================================
    -- 1. LAYOUT MATEMÁTICO: 65/35 Y BLOQUE UNIFICADO
    -- ==========================================
    local available_h = gd.h
    local status_h = S(32) 
    local fx_h = S(56)
    local gap_x = S(28)
    local target_gap = S(12)
    
    local max_pr_w_allowed = math.floor((sw - S(40) - gap_x) * 0.65)
    local target_pr_w = max_pr_w_allowed
    local target_pr_h = math.floor(target_pr_w * (sh / sw))
    
    local max_left_h_allowed = available_h - S(10)
    
    if target_pr_h + status_h > max_left_h_allowed then
        target_pr_h = max_left_h_allowed - status_h
        target_pr_w = math.floor(target_pr_h * (sw / sh))
    end
    
    local pr_w = target_pr_w
    local pr_h = target_pr_h
    local lm_w = math.floor(pr_w * (35 / 65))
    
    self._thumb_req_split_w = pr_w
    self._thumb_req_split_h = pr_h
    
    local left_total_h = pr_h + status_h
    local available_menu_h = left_total_h - target_gap - fx_h
    
    if available_menu_h < S(100) then
        available_menu_h = S(100)
        left_total_h = available_menu_h + target_gap + fx_h
        pr_h = left_total_h - status_h
        pr_w = math.floor(pr_h * (sw / sh))
        lm_w = math.floor(pr_w * (35 / 65))
    end
    
    local header_h = S(30)
    local black_line_thickness = S(0)
    local available_list_h = available_menu_h - header_h - black_line_thickness
    if available_list_h < S(70) then available_list_h = S(70) end
    
    local target_row_h = S(50)
    local num_rows = math.max(2, math.floor(available_list_h / target_row_h + 0.5))
    local row_h = math.floor(available_list_h / num_rows)
    local exact_menu_h = header_h + black_line_thickness + num_rows * row_h
    
    local gap_y = left_total_h - exact_menu_h - fx_h
    
    local block_total_w = pr_w + gap_x + lm_w
    local pr_x = math.floor((sw - block_total_w) / 2)
    if pr_x < S(12) then pr_x = S(12) end
    
    local lm_x = pr_x + pr_w + gap_x
    
    self._split_divider_x = lm_x - math.floor(gap_x / 2)

    local total_content_h = exact_menu_h + gap_y + fx_h
    local top_box_y = gd.y + math.floor((available_h - total_content_h) / 2)
    
    local pr_y = top_box_y
    local menu_y = top_box_y
    local fx_y = menu_y + exact_menu_h + gap_y
    
    self._split_preview_dimen = Geom:new{ x = pr_x, y = pr_y, w = pr_w, h = pr_h }

    -- ==========================================
    -- 2. PESTAÑAS PRINCIPALES (CON TEXTO (x) 1PX MÁS ARRIBA)
    -- ==========================================
    local bm_count = #(self:_getAllBookmarks() or {})
    local hl_count = #(self._cached_hl or {})
    local note_count = #(self._cached_notes or {})

    local tab_sp = S(6)
    local tab_h = S(32)
    local actual_top_space = top_box_y - title_strip_y
    
    local ratio = (actual_top_space > tab_h * 1.5) and 0.8 or 0.5
    local tab_draw_y = title_strip_y + math.floor((actual_top_space - tab_h) * ratio)
    
    local current_tab_x = pr_x
    local r = math.floor(tab_h / 2)

    -- BOTÓN DE SORTING (Ascendente / Descendente)
    local sort_icon = (self._sort_order == "asc") and "\u{EBBB}" or "\u{EBBC}"
    self._tw_tab_sort:setText(sort_icon)
    local sort_tsz = self._tw_tab_sort:getSize()
    local sort_tab_w = sort_tsz.w + S(16)

    paintRoundRect(bb, current_tab_x, tab_draw_y, sort_tab_w, tab_h, r, Blitbuffer.COLOR_BLACK)
    paintRoundRect(bb, current_tab_x + S(2), tab_draw_y + S(2), sort_tab_w - S(4), tab_h - S(4), math.max(1, r - S(2)), Blitbuffer.COLOR_WHITE)

    self._tw_tab_sort.fgcolor = Blitbuffer.COLOR_BLACK
    local stx = current_tab_x + math.floor((sort_tab_w - sort_tsz.w) / 2)
    local sty = tab_draw_y + math.floor((tab_h - sort_tsz.h) / 2)

    self._tw_tab_sort:paintTo(bb, stx, sty)
    self._tw_tab_sort:paintTo(bb, stx + 1, sty)
    self._tw_tab_sort:paintTo(bb, stx, sty + 1)
    self._tw_tab_sort:paintTo(bb, stx + 1, sty + 1)

    self._tab_sort_dimen = Geom:new{ x = current_tab_x, y = tab_draw_y, w = sort_tab_w, h = tab_h }
    current_tab_x = current_tab_x + sort_tab_w + tab_sp

    -- DIBUJO DE PESTAÑAS SEPARANDO ÍCONO Y CONTADOR (x) PARA SUBIR EL TEXTO 1PX
    local function drawTabWithShift(id, icon_char, count_num)
        local is_active = (self._active_tab == id)
        local bg = is_active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
        local fg = is_active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK

        local tw_ic = TextWidget:new{ text = icon_char, face = Font:getFace("cfont", S_CHIQUITO), fgcolor = fg }
        local tw_cnt = TextWidget:new{ text = "(" .. tostring(count_num) .. ")", face = Font:getFace("cfont", S_CHIQUITO), fgcolor = fg }
        local isz = tw_ic:getSize()
        local csz = tw_cnt:getSize()
        local gap = S(4)
        local content_w = isz.w + gap + csz.w
        local tab_w = content_w + S(18)

        paintRoundRect(bb, current_tab_x, tab_draw_y, tab_w, tab_h, r, Blitbuffer.COLOR_BLACK)
        if not is_active then
            paintRoundRect(bb, current_tab_x + S(2), tab_draw_y + S(2), tab_w - S(4), tab_h - S(4), math.max(1, r - S(2)), Blitbuffer.COLOR_WHITE)
        end

        local ix = current_tab_x + math.floor((tab_w - content_w) / 2)
        local cx = ix + isz.w + gap

        local iy = tab_draw_y + math.floor((tab_h - isz.h) / 2)
        local cy = tab_draw_y + math.floor((tab_h - csz.h) / 2) - S(1)

        tw_ic:paintTo(bb, ix, iy)
        tw_ic:paintTo(bb, ix + 1, iy)
        tw_ic:paintTo(bb, ix, iy + 1)
        tw_ic:paintTo(bb, ix + 1, iy + 1)
        tw_ic:free()

        tw_cnt:paintTo(bb, cx, cy)
        tw_cnt:paintTo(bb, cx + 1, cy)
        tw_cnt:paintTo(bb, cx, cy + 1)
        tw_cnt:paintTo(bb, cx + 1, cy + 1)
        tw_cnt:free()

        local dimen = Geom:new{ x = current_tab_x, y = tab_draw_y, w = tab_w, h = tab_h }
        current_tab_x = current_tab_x + tab_w + tab_sp 
        return dimen
    end
    
    self._tab_bm_dimen   = drawTabWithShift("bookmarks", "\u{E7B9}", bm_count)
    self._tab_hl_dimen   = drawTabWithShift("highlights", "\u{E931}", hl_count)
    self._tab_note_dimen = drawTabWithShift("notes", "\u{F075}", note_count)

    -- ==========================================
    -- 3. RENDERIZADO POLAROID
    -- ==========================================
    local card_x = pr_x
    local card_y = pr_y
    local card_w = pr_w
    local card_h = pr_h + status_h
    
    paintTopSquareBottomRounded(bb, card_x + shadow_offset, card_y, card_w, card_h, box_radius, Blitbuffer.COLOR_DARK_GRAY)
    paintTopSquareBottomRounded(bb, card_x, card_y, card_w, card_h, box_radius, Blitbuffer.COLOR_BLACK)
    local b_thick = S(2)
    paintTopSquareBottomRounded(bb, card_x + b_thick, card_y + b_thick, card_w - b_thick*2, card_h - b_thick*2, math.max(1, box_radius - b_thick), Blitbuffer.COLOR_WHITE)

    local tile = self._grid_tiles[2] or {}
    if tile.tile_bb then
        local target_w = pr_w - b_thick*2
        local target_h = pr_h - b_thick
        local tw, th = tile.tile_bb:getWidth(), tile.tile_bb:getHeight()

        local render_bb = tile.tile_bb
        local must_free_render_bb = false
        if math.abs(tw - target_w) > 6 or math.abs(th - target_h) > 6 then
            local ok, sc = pcall(function() return tile.tile_bb:scale(target_w, target_h) end)
            if ok and sc then
                render_bb = sc
                must_free_render_bb = true
                tw, th = render_bb:getWidth(), render_bb:getHeight()
            end
        end

        local src_x, src_y = 0, 0
        local blit_w, blit_h = tw, th
        
        if blit_w > target_w then
            src_x = math.floor((blit_w - target_w) / 2)
            blit_w = target_w
        end
        if blit_h > target_h then
            src_y = math.floor((blit_h - target_h) / 2)
            blit_h = target_h
        end

        local ox = card_x + b_thick + math.floor((target_w - blit_w) / 2)
        local oy = card_y + b_thick + math.floor((target_h - blit_h) / 2)
        
        if ox < 0 then src_x = src_x - ox; blit_w = blit_w + ox; ox = 0 end
        if oy < 0 then src_y = src_y - oy; blit_h = blit_h + oy; oy = 0 end
        if ox + blit_w > sw then blit_w = sw - ox end
        if oy + blit_h > sh then blit_h = sh - oy end
        
        if blit_w > 0 and blit_h > 0 then
            bb:blitFrom(render_bb, ox, oy, src_x, src_y, blit_w, blit_h)
        end

        if must_free_render_bb then
            pcall(function() render_bb:free() end)
        end
    elseif tile.error then
        local err_tw = TextWidget:new{ text = "!", face = Font:getFace("cfont", S(32)), fgcolor = Blitbuffer.COLOR_BLACK }
        local etsz = err_tw:getSize()
        err_tw:paintTo(bb, card_x + math.floor((card_w - etsz.w) / 2), card_y + math.floor((pr_h - etsz.h) / 2))
        err_tw:free()
    elseif tile.loading then
        bb:paintRect(card_x + math.floor(card_w / 2) - 1, card_y + math.floor(pr_h / 2) - 1, 2, 2, Blitbuffer.COLOR_GRAY)
    end
    
    local icon_char = "\u{F02E}"
    local text_str = "—"
    local pd = self._page_data[self._cur_page]
    
    local function safe_string(str, max_len)
        if string.len(str) > max_len then return string.sub(str, 1, max_len - 3) .. "..." end
        return str
    end

    if self._active_tab == "highlights" then
        icon_char = "\u{ED51}"
        if pd and pd.text then text_str = '“' .. safe_string(pd.text, 500) .. '”' end
    elseif self._active_tab == "notes" then
        icon_char = "\u{F448}"
        if pd and pd.note then text_str = safe_string(pd.note, 500) end
    elseif self._active_tab == "bookmarks" then
        icon_char = "\u{F02E}"
        local is_bmed = false
        local raw_date = nil
        
        local function find_deep_date()
            local target_p = tonumber(self._cur_page)
            local possible_sources = {
                self.ui.annotation and self.ui.annotation.annotations,
                self.ui.doc_props and self.ui.doc_props.bookmarks,
                self.ui.bookmark and self.ui.bookmark._bookmarks,
                self.ui.bookmark and self.ui.bookmark.bookmarks
            }
            for _, src in ipairs(possible_sources) do
                if type(src) == "table" then
                    for k, v in pairs(src) do
                        if type(v) == "table" then
                            local p = tonumber(v.pageno) or tonumber(v.page) or tonumber(v.pos0)
                            if not p and type(v.page) == "string" and self.ui.document and self.ui.document.getPageFromXPointer then
                                pcall(function() p = self.ui.document:getPageFromXPointer(v.page) end)
                            end
                            if p == target_p then
                                local d = v.datetime or v.time or v.date or v.timestamp
                                if d then return d end
                            end
                        else
                            if tonumber(k) == target_p and (type(v) == "string" or type(v) == "number") then
                                return v
                            end
                        end
                    end
                end
            end
            return nil
        end
        
        raw_date = find_deep_date()
        if raw_date then is_bmed = true end
        if not is_bmed then
            for _, bmp in ipairs(self:_getAllBookmarks()) do
                if tonumber(bmp) == tonumber(self._cur_page) then is_bmed = true; break end
            end
        end
        
        if is_bmed then
            if raw_date then
                local y, m, d
                if type(raw_date) == "number" then
                    y = os.date("%Y", raw_date); m = os.date("%m", raw_date); d = os.date("%d", raw_date)
                else
                    local raw_s = tostring(raw_date)
                    y, m, d = raw_s:match("(%d%d%d%d)[%-%/%.%s_](%d%d)[%-%/%.%s_](%d%d)")
                    if not y then d, m, y = raw_s:match("(%d%d)[%-%/%.%s_](%d%d)[%-%/%.%s_](%d%d%d%d)") end
                end
                if y and m and d then
                    local months = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
                    text_str = "Added on " .. (months[tonumber(m)] or m) .. " " .. tonumber(d) .. ", " .. y
                else
                    text_str = "Added on " .. tostring(raw_date)
                end
            else
                text_str = "Bookmarked"
            end
        end
    end

    local icon_sz = S(12)
    local pad_x = S(14)
    local gap = S(8)
    
    local icon_tw = TextWidget:new{ text = icon_char, face = Font:getFace("cfont", icon_sz), fgcolor = Blitbuffer.COLOR_BLACK }
    local isz = icon_tw:getSize()
    
    local text_max_w = card_w - (pad_x * 2) - isz.w - gap
    local clean_str = text_str:gsub("\n", " "):gsub("\r", "")
    
    local measure_tw = TextWidget:new{ text = clean_str, face = Font:getFace("cfont", font_sz_chiquito) }
    local raw_text_w = measure_tw:getSize().w
    measure_tw:free()
    
    local function utf8_sub(s, len)
        local count = 0
        local res = ""
        for uchar in string.gmatch(s, "[%z\1-\127\194-\244][\128-\191]*") do
            res = res .. uchar
            count = count + 1
            if count >= len then break end
        end
        return res
    end
    
    local print_str = clean_str
    if raw_text_w > text_max_w then
        local total_chars = 0
        for _ in string.gmatch(clean_str, "[%z\1-\127\194-\244][\128-\191]*") do total_chars = total_chars + 1 end
        
        local trunc_len = total_chars - 3
        while trunc_len > 0 do
            local test_str = utf8_sub(clean_str, trunc_len) .. "..."
            local temp_tw = TextWidget:new{ text = test_str, face = Font:getFace("cfont", font_sz_chiquito) }
            local test_w = temp_tw:getSize().w
            temp_tw:free()
            if test_w <= text_max_w then
                print_str = test_str
                break
            end
            trunc_len = trunc_len - 2
        end
    end
    
    local ix = card_x + pad_x
    local iy = card_y + pr_h + math.floor((status_h - isz.h) / 2)
    icon_tw:paintTo(bb, ix, iy)
    icon_tw:free()
    
    local tx = ix + isz.w + gap
    local tw_st = TextWidget:new{ text = print_str, face = Font:getFace("cfont", font_sz_chiquito), fgcolor = Blitbuffer.COLOR_BLACK, max_width = text_max_w }
    local tsz = tw_st:getSize()
    local ty = card_y + pr_h + math.floor((status_h - tsz.h) / 2) - S(1)
    
    tw_st:paintTo(bb, tx, ty)
    tw_st:paintTo(bb, tx + 1, ty)
    tw_st:paintTo(bb, tx, ty + 1)
    tw_st:paintTo(bb, tx + 1, ty + 1)
    tw_st:free()

    -- ==========================================
    -- 4. CAJA FIJA ORIGEN (PIE DEL MENÚ DERECHO)
    -- ==========================================
    local fixed_page = self._split_fixed_page or self._origin_page
    local fx_w = lm_w
    local is_f_sel = (self._cur_page == fixed_page)
    local fg_f = is_f_sel and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK

    local is_page_bmed = false
    for _, b in ipairs(self:_getAllBookmarks()) do
        if tonumber(b) == tonumber(fixed_page) then is_page_bmed = true end
    end

    paintRoundRect(bb, lm_x + shadow_offset, fx_y, lm_w, fx_h, box_radius, Blitbuffer.COLOR_DARK_GRAY)
    paintRoundRect(bb, lm_x, fx_y, lm_w, fx_h, box_radius, Blitbuffer.COLOR_BLACK)
    paintRoundRect(bb, lm_x + S(2), fx_y + S(2), lm_w - S(4), fx_h - S(4), math.max(1, box_radius - S(2)), Blitbuffer.COLOR_WHITE)

    if is_f_sel then
        paintRoundRect(bb, lm_x + S(4), fx_y + S(4), lm_w - S(8), fx_h - S(8), S(8), Blitbuffer.COLOR_BLACK)
    end
    
    local tw_pg_f = TextWidget:new{ text = tostring(fixed_page), face = Font:getFace("cfont", S_MEDIANO), fgcolor = fg_f }
    local pt_sz = tw_pg_f:getSize()
    local ptx = lm_x + S(15)
    local pty = fx_y + math.floor((fx_h - pt_sz.h) / 2) + S(2)
    
    tw_pg_f:paintTo(bb, ptx, pty)
    if is_f_sel then
        tw_pg_f:paintTo(bb, ptx + 1, pty)
        tw_pg_f:paintTo(bb, ptx, pty + 1)
        tw_pg_f:paintTo(bb, ptx + 1, pty + 1)
    end
    tw_pg_f:free()

    local btn_icon = is_page_bmed and "\u{F146}" or "\u{F196}"
    local tw_btn_f = TextWidget:new{ text = btn_icon, face = Font:getFace("cfont", S(26)), fgcolor = fg_f }
    local bsz_f = tw_btn_f:getSize()
    local btn_xf = lm_x + lm_w - bsz_f.w - S(15)
    tw_btn_f:paintTo(bb, btn_xf, fx_y + math.floor((fx_h - bsz_f.h)/2) + S(1))
    tw_btn_f:free()

    local row_clickable_w = (btn_xf - S(10)) - lm_x
    self._split_fixed_row_dimen = Geom:new{ x = lm_x, y = fx_y, w = row_clickable_w, h = fx_h }
    self._split_fixed_toggle_dimen = Geom:new{ x = btn_xf - S(10), y = fx_y, w = bsz_f.w + S(20), h = fx_h }

    -- ==========================================
    -- 5. RENDERIZADO DEL MENÚ DERECHO: SOLAPAS Y FILTROS INTELIGENTES
    -- ==========================================
    local filter_defs = {
        { key = "normal",    icon = "\u{E932}" },
        { key = "underline", icon = nil }, 
        { key = "invert",    icon = "\u{F043}" },
    }
    local present_filters = {}
    if self._active_tab == "highlights" then
        for _, fd in ipairs(filter_defs) do
            if self._hl_types_present[fd.key] then
                table.insert(present_filters, fd)
            end
        end
    end

    local other_items = self:_getFilteredActiveList()

    local ITEMS_PER_PAGE
    local needs_pagination = false
    
    if #other_items <= num_rows then
        ITEMS_PER_PAGE = num_rows
        needs_pagination = false
    else
        ITEMS_PER_PAGE = num_rows - 1
        needs_pagination = true
    end

    if ITEMS_PER_PAGE < 1 then ITEMS_PER_PAGE = 1 end

    if self._force_menu_sync then
        local target_idx = nil
        for i, p in ipairs(other_items) do
            if tonumber(p) == tonumber(self._cur_page) then
                target_idx = i
                break
            end
        end
        if target_idx then
            local required_page = math.ceil(target_idx / ITEMS_PER_PAGE)
            self._split_bm_page = required_page
        end
        self._force_menu_sync = false
    end
    
    local total_pages = math.max(1, math.ceil(#other_items / ITEMS_PER_PAGE))
    local cur_page = self._split_bm_page or 1
    if cur_page > total_pages then cur_page = total_pages end
    if cur_page < 1 then cur_page = 1 end
    self._split_bm_page = cur_page
    
    local start_idx, end_idx = 1, 0
    if #other_items > 0 then
        start_idx = (cur_page - 1) * ITEMS_PER_PAGE + 1
        end_idx = math.min(cur_page * ITEMS_PER_PAGE, #other_items)
    end

    self._split_rows = {}

    -- "P" (mayúscula) si hay >=2 tipos de highlights; "Pag" si hay 1 o menos
    local is_multi_hl = (self._active_tab == "highlights" and #present_filters >= 2)
    local main_label_str = is_multi_hl and "P" or "Pag"

    local tw_hdr = TextWidget:new{ text = main_label_str, face = Font:getFace("cfont", font_sz_chiquito), fgcolor = Blitbuffer.COLOR_BLACK }
    local hsz = tw_hdr:getSize()
    local has_active_filter = (self._active_tab == "highlights" and self._hl_filter ~= nil)

    local hdr_left_pad = is_multi_hl and S(11) or S(10)
    local hdr_right_pad = is_multi_hl and (has_active_filter and S(8) or S(11)) or S(8)

    local active_icon_w = 0
    local active_fd = nil
    if has_active_filter then
        for _, fd in ipairs(filter_defs) do
            if fd.key == self._hl_filter then active_fd = fd; break end
        end
        if active_fd then
            active_icon_w = S(13) + S(4)
        end
    end

    local pag_tab_w = hdr_left_pad + hsz.w + active_icon_w + hdr_right_pad
    local body_y = menu_y + header_h
    local body_h = exact_menu_h - header_h

    -- 1. SOLAPA ACTIVA
    bb:paintRect(lm_x, menu_y, pag_tab_w, header_h, Blitbuffer.COLOR_BLACK)

    -- 2. CUERPO DEL MENÚ (SOMBRA SOLO LATERAL)
    local inner_r = math.max(1, box_radius - S(2))
    paintCornerRect(bb, lm_x + shadow_offset, body_y, lm_w, body_h, box_radius, Blitbuffer.COLOR_DARK_GRAY, false, true, true, true)
    paintCornerRect(bb, lm_x, body_y, lm_w, body_h, box_radius, Blitbuffer.COLOR_BLACK, false, true, true, true)

    local list_y = body_y + S(2)
    local list_h = body_h - S(4)
    paintCornerRect(bb, lm_x + S(2), list_y, lm_w - S(4), list_h, inner_r, Blitbuffer.COLOR_WHITE, false, true, true, true)

    -- Apertura interior de la solapa activa (unida al cuerpo en blanco puro)
    bb:paintRect(lm_x + S(2), menu_y + S(2), pag_tab_w - S(4), header_h, Blitbuffer.COLOR_WHITE)

    -- TEXTO PRINCIPAL ("Pag" o "P") EN NEGRITA
    local start_x = lm_x + hdr_left_pad
    local hty = menu_y + S(2) + math.floor((header_h - S(2) - hsz.h) / 2)

    tw_hdr:paintTo(bb, start_x, hty)
    tw_hdr:paintTo(bb, start_x + 1, hty)
    tw_hdr:paintTo(bb, start_x, hty + 1)
    tw_hdr:paintTo(bb, start_x + 1, hty + 1)
    tw_hdr:free()

    self._hl_main_tab_dimen = Geom:new{ x = lm_x, y = menu_y, w = pag_tab_w, h = header_h }

    -- ÍCONO DENTRO DE LA SOLAPA PRINCIPAL (si hay filtro activo)
    if active_fd then
        local icon_offset_x = (active_fd.key == "underline") and S(4) or -S(2)
        local icon_x = start_x + hsz.w + icon_offset_x
        if active_fd.key == "underline" then
            local ul_w = S(11)
            local cy = menu_y + S(2) + math.floor((header_h - S(2)) / 2)
            bb:paintRect(icon_x, cy - S(3), ul_w, S(2), Blitbuffer.COLOR_BLACK)
            bb:paintRect(icon_x, cy + S(3), ul_w, S(2), Blitbuffer.COLOR_BLACK)
        else
            local y_extra = (active_fd.key == "normal") and S(3) or S(2)
            local tw_ic = TextWidget:new{ text = active_fd.icon, face = Font:getFace("cfont", S(12)), fgcolor = Blitbuffer.COLOR_BLACK }
            local tw_ic_sz = tw_ic:getSize()
            local icon_y = menu_y + S(2) + math.floor((header_h - S(2) - tw_ic_sz.h) / 2) + y_extra
            tw_ic:paintTo(bb, icon_x, icon_y)
            tw_ic:paintTo(bb, icon_x + 1, icon_y)
            tw_ic:free()
        end
    end

    -- 3. CARPETITAS/PESTAÑAS SECUNDARIAS PULIDAS
    self._hl_filter_dimens = {}
    if is_multi_hl then
        local unselected_filters = {}
        for _, fd in ipairs(present_filters) do
            if fd.key ~= self._hl_filter then
                table.insert(unselected_filters, fd)
            end
        end

        local num_unselected = #unselected_filters
        if num_unselected > 0 then
            local tab_start_x = lm_x + pag_tab_w + S(6)
            local folder_w = S(27)
            local folder_h = header_h - S(4)
            local folder_r = S(5)
            local folder_gap = S(4)
            local curr_folder_x = tab_start_x
            local curr_folder_y = menu_y + S(4)

            for _, fd in ipairs(unselected_filters) do
                -- Contorno cerrado con base apoyada en el marco
                paintCornerRect(bb, curr_folder_x, curr_folder_y, folder_w, folder_h, folder_r, Blitbuffer.COLOR_BLACK, true, true, false, false)
                paintCornerRect(bb, curr_folder_x + S(2), curr_folder_y + S(2), folder_w - S(4), folder_h - S(2), math.max(1, folder_r - S(2)), Blitbuffer.COLOR_WHITE, true, true, false, false)

                if fd.key == "underline" then
                    local ul_w = S(11)
                    local cx = curr_folder_x + math.floor((folder_w - ul_w) / 2)
                    local cy = curr_folder_y + math.floor(folder_h / 2)
                    bb:paintRect(cx, cy - S(3), ul_w, S(2), Blitbuffer.COLOR_BLACK)
                    bb:paintRect(cx, cy + S(3), ul_w, S(2), Blitbuffer.COLOR_BLACK)
                else
                    local tw_f = TextWidget:new{ text = fd.icon, face = Font:getFace("cfont", S(12)), fgcolor = Blitbuffer.COLOR_BLACK }
                    local tw_f_sz = tw_f:getSize()
                    local paint_x = curr_folder_x + math.floor((folder_w - tw_f_sz.w) / 2)
                    local paint_y = curr_folder_y + math.floor((folder_h - tw_f_sz.h) / 2)
                    tw_f:paintTo(bb, paint_x, paint_y)
                    tw_f:paintTo(bb, paint_x + 1, paint_y)
                    tw_f:free()
                end

                table.insert(self._hl_filter_dimens, {
                    key = fd.key,
                    dimen = Geom:new{ x = curr_folder_x, y = menu_y, w = folder_w, h = header_h }
                })
                curr_folder_x = curr_folder_x + folder_w + folder_gap
            end
        end
    end

    if #other_items == 0 then
        local n_tw = TextWidget:new{ text = "—", face = Font:getFace("cfont", S_MEDIANO), fgcolor = Blitbuffer.COLOR_DARK_GRAY }
        local n_sz = n_tw:getSize()
        n_tw:paintTo(bb, lm_x + math.floor((lm_w - n_sz.w)/2), list_y + math.floor((list_h - n_sz.h)/2))
        n_tw:free()
    else
        local row_y_float = list_y
        for i = start_idx, end_idx do
            local current_row_y = math.floor(row_y_float)
            local p = other_items[i]
            local is_r_sel = (self._cur_page == p)
            local fg_r = is_r_sel and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    
            if is_r_sel then
                paintRoundRect(bb, lm_x + S(4), current_row_y + S(4), lm_w - S(8), row_h - S(8), S(8), Blitbuffer.COLOR_BLACK)
            end
            
            if not is_r_sel and i < end_idx then
                bb:paintRect(lm_x + S(15), current_row_y + row_h - 1, lm_w - S(30), 1, Blitbuffer.COLOR_GRAY)
            end
            
            local icon_str = (self._active_tab == "bookmarks") and "\u{F147}" or "\u{F105}" 
            local tw_rm = TextWidget:new{ text = icon_str, face = Font:getFace("cfont", S(24)), fgcolor = fg_r }
            local rm_sz = tw_rm:getSize()
            local rm_x = lm_x + lm_w - rm_sz.w - S(15)
            
            local icon_y_offset = (self._active_tab == "bookmarks") and 0 or S(1)
            tw_rm:paintTo(bb, rm_x, current_row_y + math.floor((row_h - rm_sz.h)/2) - icon_y_offset + S(1))
            tw_rm:free()
            
            local text_max_w_menu = lm_w - rm_sz.w - S(30)

            local tw_pg = TextWidget:new{ text = tostring(p), face = Font:getFace("cfont", S_MEDIANO), fgcolor = fg_r, max_width = text_max_w_menu }
            local tw_pg_sz = tw_pg:getSize()
            local pg_x = lm_x + S(15)
            local pg_y = current_row_y + math.floor((row_h - tw_pg_sz.h) / 2) + S(2)
            
            tw_pg:paintTo(bb, pg_x, pg_y)
            if is_r_sel then
                tw_pg:paintTo(bb, pg_x + 1, pg_y)
                tw_pg:paintTo(bb, pg_x, pg_y + 1)
                tw_pg:paintTo(bb, pg_x + 1, pg_y + 1)
            end
            tw_pg:free()
            
            local t_dim = Geom:new{ x = rm_x - S(10), y = current_row_y, w = rm_sz.w + S(20), h = row_h }
            local dyn_clickable_w = (rm_x - S(10)) - lm_x
            local r_dim = Geom:new{ x = lm_x, y = current_row_y, w = dyn_clickable_w, h = row_h }
            
            table.insert(self._split_rows, { dimen = r_dim, toggle_dimen = t_dim, page = p })
            
            row_y_float = row_y_float + row_h
        end
        
        self._split_prev_dimen = nil
        self._split_next_dimen = nil
        
        if needs_pagination then
            local pag_h = row_h
            local pag_y = list_y + (num_rows - 1) * row_h
            
            bb:paintRect(lm_x + S(15), pag_y, lm_w - S(30), S(1), Blitbuffer.COLOR_GRAY)
            
            local pag_str = cur_page .. " / " .. total_pages
            local pag_tw = TextWidget:new{ text = pag_str, face = Font:getFace("cfont", S(12)), fgcolor = Blitbuffer.COLOR_DARK_GRAY }
            local pag_sz = pag_tw:getSize()
            
            local text_y = pag_y + math.floor((pag_h - pag_sz.h)/2) + S(2)
            pag_tw:paintTo(bb, lm_x + math.floor((lm_w - pag_sz.w)/2), text_y)
            pag_tw:free()
            
            local btn_w = S(60) 
            if cur_page > 1 then
                self._split_prev_dimen = Geom:new{ x = lm_x, y = pag_y, w = btn_w, h = pag_h }
                local is_pressed = (self._pressed_btn == "split_prev")
                if is_pressed then
                    paintRoundRect(bb, self._split_prev_dimen.x + S(4), self._split_prev_dimen.y + S(4), self._split_prev_dimen.w - S(8), self._split_prev_dimen.h - S(8), S(8), Blitbuffer.COLOR_BLACK)
                end
                local fg = is_pressed and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
                local p_tw = TextWidget:new{ text = "‹", face = Font:getFace("cfont", S(20)), fgcolor = fg }
                local p_sz = p_tw:getSize()
                p_tw:paintTo(bb, lm_x + S(20), pag_y + math.floor((pag_h - p_sz.h)/2))
                p_tw:free()
            end
            if cur_page < total_pages then
                self._split_next_dimen = Geom:new{ x = lm_x + lm_w - btn_w, y = pag_y, w = btn_w, h = pag_h }
                local is_pressed = (self._pressed_btn == "split_next")
                if is_pressed then
                    paintRoundRect(bb, self._split_next_dimen.x + S(4), self._split_next_dimen.y + S(4), self._split_next_dimen.w - S(8), self._split_next_dimen.h - S(8), S(8), Blitbuffer.COLOR_BLACK)
                end
                local fg = is_pressed and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
                local n_tw = TextWidget:new{ text = "›", face = Font:getFace("cfont", S(20)), fgcolor = fg }
                local n_sz = n_tw:getSize()
                n_tw:paintTo(bb, lm_x + lm_w - n_sz.w - S(20), pag_y + math.floor((pag_h - n_sz.h)/2))
                n_tw:free()
            end
        end
    end
end

function PageScrubber:_paintBackLabel(bb)
    self._grid_back_dimen = nil
    local BACK_LABEL_THRESHOLD = 10
    if math.abs(self._cur_page - self._origin_page) < BACK_LABEL_THRESHOLD then return end

    local ahead = self._cur_page > self._origin_page
    local arrow_char = ahead and "\u{F104}" or "\u{F105}"

    if not self._tw_grid_back_icon then
        self._tw_grid_back_icon = TextWidget:new{
            text = arrow_char, face = Font:getFace("cfont", S(13)),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }
    else
        self._tw_grid_back_icon:setText(arrow_char)
    end

    local label_text = _("page") .. " " .. self._origin_page
    if not self._tw_grid_back then
        self._tw_grid_back = TextWidget:new{
            text = label_text, face = Font:getFace("cfont", S(13)),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }
    else
        self._tw_grid_back:setText(label_text)
    end

    local isz = self._tw_grid_back_icon:getSize()
    local tsz = self._tw_grid_back:getSize()
    local gap = S(10)
    local pad_x, pad_y = S(7), S(5)

    local content_h = math.max(isz.h, tsz.h)
    local lbl_w = pad_x * 2 + isz.w + gap + tsz.w
    local lbl_h = pad_y * 2 + content_h

    local text_y_shift = ahead and S(4) or S(1)
    local group_y_shift = ahead and 0 or S(3)
    local icon_y = self.ctrl_y_pos + math.floor((self._ctrl_row_h - isz.h) / 2) - group_y_shift
    local text_y = self.ctrl_y_pos + math.floor((self._ctrl_row_h - tsz.h) / 2) - text_y_shift - group_y_shift

    local lbl_x
    if ahead then
        lbl_x = math.floor((self._ctrl_row_x0 - lbl_w) / 2)
    else
        local sw = Screen:getWidth()
        lbl_x = self._ctrl_row_x1 + math.floor((sw - self._ctrl_row_x1 - lbl_w) / 2)
    end

    local function paintGrisPunchy(tw, px, py)
        tw:paintTo(bb, px, py)
        tw:paintTo(bb, px + 1, py)
        tw:paintTo(bb, px, py + 1)
    end

    if ahead then
        paintGrisPunchy(self._tw_grid_back_icon, lbl_x + pad_x, icon_y)
        paintGrisPunchy(self._tw_grid_back, lbl_x + pad_x + isz.w + gap, text_y)
    else
        paintGrisPunchy(self._tw_grid_back, lbl_x + pad_x, text_y)
        paintGrisPunchy(self._tw_grid_back_icon, lbl_x + pad_x + tsz.w + gap, icon_y)
    end

    self._grid_back_dimen = Geom:new{ x = lbl_x, y = math.min(icon_y, text_y),
        w = lbl_w, h = math.max(icon_y + isz.h, text_y + tsz.h) - math.min(icon_y, text_y) }
end

function PageScrubber:_gotoPage(page)
    if self._closing then return end
    self._cur_page = math.max(1, math.min(self._total_pages, page))
    self._slider.value = self._cur_page
    self:_updateTexts()

    self._grid_batch_seq = (self._grid_batch_seq or 0) + 1
    self._grid_batch_id = "page_scrubber_cancelled_" .. tostring(self._grid_instance_id) .. "_" .. tostring(self._grid_batch_seq)
    self._is_busy = false
    self._tasks_in_flight = 0

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

function PageScrubber:_previewPage(page, is_dragging)
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
    if self._closing then return end
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
    bb:paintRect(bd.x, bd.y, bd.w, S(2), Blitbuffer.COLOR_BLACK)

    local title_strip_y = td.y + td.h
    local title_strip_h = self._grid_dimen.y - title_strip_y
    bb:paintRect(0, title_strip_y, sw, title_strip_h, Blitbuffer.COLOR_WHITE)
    
    if self._view_mode == "grid" then
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
    elseif self._view_mode == "split" then
        self:_paintSplitView(bb, title_strip_y, title_strip_h)
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
            elseif tw.text == "\u{EBAD}" or tw.text == "\u{EBAC}" then
                y_offset = -S(1)
            elseif tw.text == "\u{F0D9}" or tw.text == "\u{F0DA}" then
                y_offset = -S(2)
            end
            tw:paintTo(bb, cx - math.floor(tsz.w / 2), cy - math.floor(tsz.h / 2) + y_offset)
            return
        end

        if btn_id == "x" or btn_id == "bm" or btn_id == "toc" or btn_id == "fn" or btn_id == "lib" then
            local bg_color = (is_pressed and not is_disabled) and Blitbuffer.COLOR_BLACK or nil
            
            if bg_color then
                paintRoundRect(bb, dimen.x, dimen.y, dimen.w, dimen.h, S(8), bg_color)
            end
            
            tw.fgcolor = fg_color
            local tsz = tw:getSize()
            local y_offset = 0
            if tw.text == "\u{F015}" or tw.text == "\u{F0F6}" or tw.text == "\u{F02D}" or tw.text == "\u{F044}" or tw.text == "\u{F44E}" or tw.text == "\u{F0CA}" or tw.text == "\u{E344}" then
                y_offset = S(1)
            elseif tw.text == "⚙" then
                y_offset = -S(1)
            end
            tw:paintTo(bb, cx - math.floor(tsz.w / 2), cy - math.floor(tsz.h / 2) + y_offset)
            return
        end
    end

    drawFloatingBtn("lib", self._lib_icon_dimen, self.tw_lib)
    
    self.tw_lib_label:paintTo(bb, self._lib_label_x, self._lib_label_y)
    self.tw_lib_label:paintTo(bb, self._lib_label_x + 1, self._lib_label_y)
    self.tw_lib_label:paintTo(bb, self._lib_label_x, self._lib_label_y + 1)
    self.tw_lib_label:paintTo(bb, self._lib_label_x + 1, self._lib_label_y + 1)

    drawFloatingBtn("toc", self._toc_dimen, self.tw_toc)
    drawFloatingBtn("bm", self._bm_dimen, self.tw_bm)
    drawFloatingBtn("fn", self._fn_dimen, self.tw_fn)
    drawFloatingBtn("x", self._x_dimen, self.tw_x)

    local current_display = self._cur_page

    local can_prev_ch = self.ui.toc and self.ui.toc:getPreviousChapter(current_display) ~= nil
    local can_next_ch = self.ui.toc and self.ui.toc:getNextChapter(current_display) ~= nil

    drawFloatingBtn("ch_l", self._prev_ch_dimen, self.tw_ch_l, not can_prev_ch)
    drawFloatingBtn("ch_r", self._next_ch_dimen, self.tw_ch_r, not can_next_ch)

    local is_marked = self:_isCurrentPageBookmarked(current_display)
    self.tw_ctrl_mark:setText(is_marked and "\u{F02E}" or "\u{F097}")

    local has_prev_bm = self:_findPrevBookmark() ~= nil
    local has_next_bm = self:_findNextBookmark() ~= nil

    drawFloatingBtn("ctrl_prev", self._ctrl_prev_dimen, self.tw_ctrl_prev, not has_prev_bm)
    drawFloatingBtn("ctrl_mark", self._ctrl_mark_dimen, self.tw_ctrl_mark, false)
    drawFloatingBtn("ctrl_next", self._ctrl_next_dimen, self.tw_ctrl_next, not has_next_bm)

    self:_paintBackLabel(bb)

    self:_updateTexts()
    
    local csz_tw = self.tw_chapter:getSize()
    local ctx = math.floor((sw - csz_tw.w) / 2)
    self.tw_chapter:paintTo(bb, ctx, self.ch_y_pos)
    self.tw_chapter:paintTo(bb, ctx + 1, self.ch_y_pos)
    self.tw_chapter:paintTo(bb, ctx, self.ch_y_pos + 1)
    self.tw_chapter:paintTo(bb, ctx + 1, self.ch_y_pos + 1)

    local isz = self.tw_info:getSize()
    local infox = math.floor((sw - isz.w) / 2)
    self.tw_info:paintTo(bb, infox, self.info_y_pos)
    self.tw_info:paintTo(bb, infox + 1, self.info_y_pos)
    self.tw_info:paintTo(bb, infox + 1, self.info_y_pos + 1)

    local slider_x = pad * 2
    self._slider.value = current_display
    self._slider:paintTo(bb, slider_x, self.slider_y_pos)
end

function PageScrubber:_closeReturn()
    if self._closing then return end
    self._closing = true
    self:_cancelHold()
    UIManager:nextTick(function()
        if self._cur_page ~= self._origin_page then
            self.ui:handleEvent(Event:new("GotoPage", self._origin_page))
        end
        UIManager:close(self)
    end)
end

function PageScrubber:_closeStay()
    if self._closing then return end
    self._closing = true
    self:_cancelHold()
    UIManager:nextTick(function()
        UIManager:close(self)
    end)
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

local function showUIScaleSpinner(on_saved, on_cancel)
    local spin = SpinWidget:new{
        title_text = _("Page Scrubber UI scale"),
        info_text = _("Changes the size of buttons, text and icons in the Page Scrubber. 1.0 is normal size. Takes effect the next time you open the scrubber."),
        value = CUSTOM_UI_SCALE,
        value_min = 0.5,
        value_max = 2.0,
        value_step = 0.1,
        value_hold_step = 0.5,
        precision = "%.1f",
        ok_text = _("Save"),
        callback = function(spin_widget)
            setCustomUIScale(spin_widget.value)
            if on_saved then on_saved() end
        end,
        cancel_callback = function()
            if on_cancel then on_cancel() end
        end,
    }
    UIManager:show(spin)
end

function PageScrubber:_showUIScaleSpinner()
    self:_closeStay()
    
    local function reopen()
        UIManager:scheduleIn(0.1, function()
            if self.ui then self.ui:handleEvent(Event:new("PageScrubber")) end
        end)
    end
    
    showUIScaleSpinner(reopen, reopen)
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
        
        local target_page = self._cur_page
        
        if action == "prev" then 
            if target_page > 1 then 
                self._force_menu_sync = true
                self:_previewPage(self._cur_page - 1, false) 
            else 
                self:_cancelHold(); return 
            end
        elseif action == "next" then 
            if target_page < self._total_pages then 
                self._force_menu_sync = true
                self:_previewPage(self._cur_page + 1, false) 
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
        if p then 
            self._force_menu_sync = true
            self:_previewPage(p, false) 
        end
    end
end

function PageScrubber:_nextChapter()
    local ui = self.ui
    if ui.toc then
        local p = ui.toc:getNextChapter(self._cur_page)
        if p then 
            self._force_menu_sync = true
            self:_previewPage(p, false) 
        end
    end
end

function PageScrubber:onTap(_, ges)
    self:_cancelHold()
    if self._closing then return true end

    if self._bm_dimen and ges.pos:intersectWith(self._bm_dimen) then
        self:_flashAndDo("bm", self._bm_dimen, function() 
            self._view_mode = "split"
            self._active_tab = "bookmarks"
            self._split_fixed_page = self._cur_page
            self._split_bm_page = 1
            self._force_menu_sync = true
            self:_clearGridTiles()
            self:_previewPage(self._cur_page, false)
        end)
        return true
    end

    if self._view_mode == "grid" then
        if self._center_bm_touch_dimen and ges.pos:intersectWith(self._center_bm_touch_dimen) then
            local tgt = self._cur_page
            self:_waitForIdle(function()
                if self._closing then return end
                self:_invalidateGridTilesForPage(tgt)
                pcall(function()
                    self.ui:handleEvent(Event:new("GotoPage", tgt))
                    self.ui:handleEvent(Event:new("ToggleBookmark"))
                end)
                self:_invalidateBookmarksCache()
                if not self._closing then
                    self:_updateGridPages()
                    UIManager:setDirty(self, "ui", self.dimen)
                end
            end)
            return true
        end
    end

    if self._view_mode == "split" then
        if self._tab_sort_dimen and ges.pos:intersectWith(self._tab_sort_dimen) then
            self._sort_order = (self._sort_order == "asc") and "desc" or "asc"
            self._split_bm_page = 1
            UIManager:setDirty(self, "ui", self.dimen)
            return true
        end

        if self._tab_hl_dimen and ges.pos:intersectWith(self._tab_hl_dimen) then
            self._active_tab = "highlights"
            self._hl_filter = nil
            self._split_bm_page = 1
            self:_extractAnnotations()
            UIManager:setDirty(self, "ui", self.dimen)
            return true
        end

        if self._active_tab == "highlights" and self._hl_main_tab_dimen and ges.pos:intersectWith(self._hl_main_tab_dimen) then
            if self._hl_filter ~= nil then
                self._hl_filter = nil
                self._split_bm_page = 1
                UIManager:setDirty(self, "ui", self.dimen)
                return true
            end
        end

        if self._active_tab == "highlights" and self._hl_filter_dimens then
            for _, f in ipairs(self._hl_filter_dimens) do
                if ges.pos:intersectWith(f.dimen) then
                    if self._hl_filter == f.key then
                        self._hl_filter = nil
                    else
                        self._hl_filter = f.key
                    end
                    self._split_bm_page = 1
                    UIManager:setDirty(self, "ui", self.dimen)
                    return true
                end
            end
        end
        
        if self._tab_bm_dimen and ges.pos:intersectWith(self._tab_bm_dimen) then
            self._active_tab = "bookmarks"
            self._split_bm_page = 1
            self:_extractAnnotations()
            UIManager:setDirty(self, "ui", self.dimen)
            return true
        end

        if self._tab_note_dimen and ges.pos:intersectWith(self._tab_note_dimen) then
            self._active_tab = "notes"
            self._split_bm_page = 1
            self:_extractAnnotations()
            UIManager:setDirty(self, "ui", self.dimen)
            return true
        end
        
        if self._split_fixed_row_dimen and ges.pos:intersectWith(self._split_fixed_row_dimen) then
            self._force_menu_sync = true
            self:_previewPage(self._split_fixed_page or self._origin_page, false)
            return true
        end
        
        if self._split_fixed_toggle_dimen and ges.pos:intersectWith(self._split_fixed_toggle_dimen) then
            local tgt = self._split_fixed_page or self._origin_page
            self:_waitForIdle(function()
                if self._closing then return end
                self:_invalidateGridTilesForPage(tgt)
                
                local ok, err = pcall(function()
                    self.ui:handleEvent(Event:new("GotoPage", tgt))
                    self.ui:handleEvent(Event:new("ToggleBookmark"))
                end)
                if not ok then logger.warn("page-scrubber: fixed toggle failed:", err) end
                
                self:_invalidateBookmarksCache()
                if not self._closing then
                    self:_updateGridPages()
                    UIManager:setDirty(self, "ui", self.dimen)
                end
            end)
            return true
        end
        
        if self._split_prev_dimen and ges.pos:intersectWith(self._split_prev_dimen) then
            self:_flashAndDo("split_prev", self._split_prev_dimen, function()
                self._split_bm_page = math.max(1, (self._split_bm_page or 1) - 1)
                UIManager:setDirty(self, "ui", self.dimen)
            end)
            return true
        end
        if self._split_next_dimen and ges.pos:intersectWith(self._split_next_dimen) then
            self:_flashAndDo("split_next", self._split_next_dimen, function()
                self._split_bm_page = (self._split_bm_page or 1) + 1
                UIManager:setDirty(self, "ui", self.dimen)
            end)
            return true
        end
        
        if self._split_rows then
            for _, row in ipairs(self._split_rows) do
                if ges.pos:intersectWith(row.toggle_dimen) then
                    if self._active_tab == "bookmarks" then
                        local p = row.page
                        self:_waitForIdle(function()
                            if self._closing then return end
                            self:_invalidateGridTilesForPage(p)
                            
                            local ok, err = pcall(function()
                                self.ui:handleEvent(Event:new("GotoPage", p))
                                self.ui:handleEvent(Event:new("ToggleBookmark"))
                            end)
                            if not ok then logger.warn("page-scrubber: dynamic toggle failed:", err) end
                            
                            self:_invalidateBookmarksCache()
                            if not self._closing then
                                self:_updateGridPages()
                                UIManager:setDirty(self, "ui", self.dimen)
                            end
                        end)
                        return true
                    else
                        self:_gotoPage(row.page)
                        self:_closeStay()
                        return true
                    end
                end
                
                if ges.pos:intersectWith(row.dimen) then
                    self._force_menu_sync = true
                    self:_previewPage(row.page, false)
                    return true
                end
            end
        end
        
        if self._split_preview_dimen and ges.pos:intersectWith(self._split_preview_dimen) then
            self._view_mode = "grid"
            self:_clearGridTiles()
            self:_previewPage(self._cur_page, false)
            return true
        end
    end

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
    if self._x_dimen and ges.pos:intersectWith(self._x_dimen) then
        self:_flashAndDo("x", self._x_dimen, function() self:_closeReturn() end)
        return true
    end

    if self._ctrl_prev_dimen and ges.pos:intersectWith(self._ctrl_prev_dimen) then
        local target = self:_findPrevBookmark()
        if target then
            self:_flashAndDo("ctrl_prev", self._ctrl_prev_dimen, function()
                self._force_menu_sync = true
                self:_previewPage(target, false)
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
                if not ok then logger.warn("page-scrubber: ToggleBookmark failed:", err) end

                self:_invalidateBookmarksCache()
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
                self._force_menu_sync = true
                self:_previewPage(target, false)
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
    
    if self._slider:handleTap(ges) then
        self._force_menu_sync = true
        return true 
    end

    if self._grid_back_dimen and ges.pos:intersectWith(self._grid_back_dimen) then
        self._force_menu_sync = true
        self:_previewPage(self._origin_page, false)
        return true
    end

    if self._bar_dimen and ges.pos:intersectWith(self._bar_dimen) then
        return true
    end

    if self._top_bar_dimen and ges.pos:intersectWith(self._top_bar_dimen) then
        return true
    end

    if self._view_mode == "grid" and not self._grid_disabled and self._grid_dimen and ges.pos:intersectWith(self._grid_dimen) then
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
                        self:_previewPage(slot.page, false)
                    end
                end
                return true
            end
        end
        return true
    end

    if self._grid_disabled and self._grid_dimen and ges.pos:intersectWith(self._grid_dimen) then
        if ges.pos.intersectWith and ges.pos:intersectWith(self._fallback_prev_dimen) then
            self:_previewPage(self._cur_page - 1, false)
        elseif ges.pos.intersectWith and ges.pos:intersectWith(self._fallback_next_dimen) then
            self:_previewPage(self._cur_page + 1, false)
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
        self._force_menu_sync = true
        if self._slider._dragging then
            self._drag_watchdog_gen = (self._drag_watchdog_gen or 0) + 1
            local my_gen = self._drag_watchdog_gen
            UIManager:scheduleIn(1.0, function()
                if self._closing then return end
                if self._drag_watchdog_gen == my_gen and self._slider._dragging then
                    logger.warn("page-scrubber: drag watchdog -- no llegó el release, forzando reset")
                    self._slider._dragging = false
                    if not self._grid_disabled then self:_updateGridPages() end
                    UIManager:setDirty(self, "ui", self.dimen)
                end
            end)
        end
        return true 
    end
    self:_cancelHold()
    return true
end

function PageScrubber:onPanRelease(_, ges)
    self:_cancelHold()
    if self._closing then return true end
    if self._slider:handlePanRelease(ges) then 
        UIManager:setDirty(self, "ui", self.dimen)
        return true 
    end
    return true
end

function PageScrubber:onSwipe(_, ges)
    if self._closing then return true end
    
    if self._slider._dragging then
        self._slider._dragging = false
        UIManager:setDirty(self, "ui", self.dimen)
    end

    if self._bar_dimen and ges.pos and ges.pos.y >= self._bar_dimen.y then
        return true
    end

    if self._view_mode == "split" and ges.pos then
        local sw = Screen:getWidth()
        local div_x = self._split_divider_x or math.floor(sw * 0.65)
        
        if ges.pos.x > div_x then
            if ges.direction == "west" then
                self._split_bm_page = (self._split_bm_page or 1) + 1
                UIManager:setDirty(self, "ui", self.dimen)
                return true
            elseif ges.direction == "east" then
                self._split_bm_page = math.max(1, (self._split_bm_page or 1) - 1)
                UIManager:setDirty(self, "ui", self.dimen)
                return true
            end
        else
            if ges.direction == "west" then
                self._force_menu_sync = false
                self:_previewPage(self._cur_page + 1, false) 
                return true
            elseif ges.direction == "east" then
                self._force_menu_sync = false
                self:_previewPage(self._cur_page - 1, false) 
                return true
            end
        end
    end

    if ges.direction == "west" then
        self._force_menu_sync = true
        self:_previewPage(self._cur_page + 1, false) 
        return true
    elseif ges.direction == "east" then
        self._force_menu_sync = true
        self:_previewPage(self._cur_page - 1, false) 
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

    if self._fn_dimen and ges.pos:intersectWith(self._fn_dimen) then
        self:_showUIScaleSpinner()
        return true
    end
    
    if self._ctrl_mark_dimen and ges.pos:intersectWith(self._ctrl_mark_dimen) then
        if self._view_mode == "grid" then
            self._view_mode = "split"
            self._active_tab = "bookmarks"
            self._split_fixed_page = self._cur_page
            self._split_bm_page = 1
            self._force_menu_sync = true
            self:_clearGridTiles()
            self:_previewPage(self._cur_page, false)
        else
            self._view_mode = "grid"
            self:_clearGridTiles()
            self:_previewPage(self._cur_page, false)
        end
        return true
    end
    
    if self._toc_dimen and ges.pos:intersectWith(self._toc_dimen) then
        pcall(function()
            if UIManager.takeScreenshot then
                UIManager:takeScreenshot()
            elseif self.ui and self.ui.onTakeScreenshot then
                self.ui:onTakeScreenshot()
            elseif self.ui and self.ui.handleEvent then
                self.ui:handleEvent(Event:new("TakeScreenshot"))
            end
        end)
        return true
    end

    if self._view_mode == "split" then
        if self._split_rows then
            for _, row in ipairs(self._split_rows) do
                if ges.pos:intersectWith(row.dimen) and not ges.pos:intersectWith(row.toggle_dimen) then
                    self._view_mode = "grid"
                    self:_clearGridTiles()
                    self._force_menu_sync = true
                    self:_previewPage(row.page, false)
                    return true
                end
            end
        end
        
        local fixed_page = self._split_fixed_page or self._origin_page
        if self._split_fixed_row_dimen and ges.pos:intersectWith(self._split_fixed_row_dimen) and not ges.pos:intersectWith(self._split_fixed_toggle_dimen) then
            self._view_mode = "grid"
            self:_clearGridTiles()
            self._force_menu_sync = true
            self:_previewPage(fixed_page, false)
            return true
        end

        if self._split_preview_dimen and ges.pos:intersectWith(self._split_preview_dimen) then
            self:_gotoPage(self._cur_page)
            self:_closeStay()
            return true
        end

        return true 
    end

    if not self._grid_disabled and self._grid_dimen then
        if ges.pos:intersectWith(self:_gridSlotDimen(1)) then
            self:_startHold("prev"); return true
        end
        if ges.pos:intersectWith(self:_gridSlotDimen(3)) then
            self:_startHold("next"); return true
        end
        if ges.pos:intersectWith(self:_gridSlotDimen(2)) then
            self._view_mode = "split"
            self._active_tab = "bookmarks"
            self._split_fixed_page = self._cur_page
            self._split_bm_page = 1
            self._force_menu_sync = true
            self:_clearGridTiles()
            self:_previewPage(self._cur_page, false)
            return true
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
    if self._slider._dragging then
        self._slider._dragging = false
        if not self._grid_disabled then self:_updateGridPages() end
        UIManager:setDirty(self, "ui", self.dimen)
    end
    return true
end

function PageScrubber:onCloseWidget()
    self._closing = true
    self:_cancelHold()

    if not self._grid_disabled then
        for _, slot in pairs(self._grid_tiles) do
            self:_freeTile(slot)
        end
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

    if self._tw_tab_sort then self._tw_tab_sort:free() end

    if self.tw_chapter then self.tw_chapter:free() end
    if self.tw_booktitle then self.tw_booktitle:free() end
    if self._tw_grid_error then self._tw_grid_error:free() end
    if self.tw_info then self.tw_info:free() end
    if self.tw_toc then self.tw_toc:free() end
    if self.tw_bm then self.tw_bm:free() end
    if self.tw_fn then self.tw_fn:free() end
    if self.tw_lib then self.tw_lib:free() end
    if self.tw_lib_label then self.tw_lib_label:free() end
    if self.tw_x then self.tw_x:free() end
    if self.tw_fb_l then self.tw_fb_l:free() end
    if self.tw_fb_r then self.tw_fb_r:free() end
    if self._tw_grid_back then self._tw_grid_back:free() end
    if self._tw_grid_back_icon then self._tw_grid_back_icon:free() end
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

-- =========================================================================
-- REGISTRO DE ACCIONES EN EL DISPATCHER DE KOREADER (GESTOR DE GESTOS)
-- =========================================================================
Dispatcher:registerAction("page_scrubber_action", {
    category = "none",
    event    = "PageScrubber",
    title    = _("Page Scrubber"),
    reader   = true,
})

Dispatcher:registerAction("page_scrubber_menu_action", {
    category = "none",
    event    = "PageScrubberMenu",
    title    = _("Page Scrubber (Menú / Dividido)"),
    reader   = true,
})

Dispatcher:registerAction("page_scrubber_hl_action", {
    category = "none",
    event    = "PageScrubberHighlights",
    title    = _("Page Scrubber (Highlights)"),
    reader   = true,
})

function ReaderUI:onPageScrubber(mode, tab)
    local ui = self
    if not ui.document then return end

    UIManager:nextTick(function()
        if not ui or not ui.document then return end
        UIManager:show(PageScrubber:new{
            ui = ui,
            document = ui.document,
            initial_view_mode = mode or "grid",
            initial_tab = tab or "bookmarks",
        })
        if Device:isKindle() then
            UIManager:setDirty(nil, "full")
        end
    end)
end

function ReaderUI:onPageScrubberMenu()
    self:onPageScrubber("split", "bookmarks")
end

function ReaderUI:onPageScrubberHighlights()
    self:onPageScrubber("split", "highlights")
end

local orig_addToMainMenu = ReaderUI.addToMainMenu
function ReaderUI:addToMainMenu(menu_items)
    if orig_addToMainMenu then orig_addToMainMenu(self, menu_items) end

    local scrubber_menu_item = {
        text_func = function()
            return _("Page Scrubber scale") .. ": " .. tostring(CUSTOM_UI_SCALE) .. "x"
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            showUIScaleSpinner(function()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end)
        end,
    }

    if menu_items.more_tools and menu_items.more_tools.sub_item_table then
        table.insert(menu_items.more_tools.sub_item_table, scrubber_menu_item)
    else
        menu_items.page_scrubber_scale = scrubber_menu_item
    end
end

logger.info("page-scrubber patch: loaded")
