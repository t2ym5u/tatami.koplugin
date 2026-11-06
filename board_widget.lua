local Blitbuffer = require("ffi/blitbuffer")
local Font       = require("ui/font")
local Geom       = require("ui/geometry")
local RenderText = require("ui/rendertext")
local Size       = require("ui/size")

local gwb            = require("grid_widget_base")
local GridWidgetBase = gwb.GridWidgetBase
local drawLine       = gwb.drawLine

-- ---------------------------------------------------------------------------
-- Colours
-- ---------------------------------------------------------------------------

local C_BG       = Blitbuffer.COLOR_WHITE
local C_GIVEN_BG = Blitbuffer.COLOR_GRAY_E
local C_SEL      = Blitbuffer.COLOR_LIGHT_GRAY
local C_WRONG    = Blitbuffer.COLOR_GRAY
local C_LINE     = Blitbuffer.COLOR_BLACK
local C_GRID     = Blitbuffer.COLOR_GRAY_9
local C_GIVEN_FG = Blitbuffer.COLOR_BLACK
local C_USER_FG  = Blitbuffer.COLOR_GRAY_3
local C_NOTE_FG  = Blitbuffer.COLOR_GRAY_4

-- ---------------------------------------------------------------------------
-- TatamiBoardWidget: digits, notes, and the mats drawn as thick outlines.
-- ---------------------------------------------------------------------------

local TatamiBoardWidget = GridWidgetBase:extend{
    board = nil,
}

function TatamiBoardWidget:init()
    local n   = self.board and self.board.n or 6
    self.cols = n
    self.rows = n
    GridWidgetBase.init(self)
    -- The base fit fills the cell edge to edge; the thick mat walls need a
    -- margin, so the digits are drawn a little smaller.
    self.number_face = Font:getFace("cfont",
        math.max(10, math.floor(self.number_face.orig_size * 0.75)))
end

function TatamiBoardWidget:onCellTap(row, col)
    if self.onCellTap_cb then self.onCellTap_cb(row, col) end
end

function TatamiBoardWidget:onCellHold(row, col)
    if self.onCellHold_cb then self.onCellHold_cb(row, col) end
end

local function drawText(bb, face, text, x, y, w, h, color)
    local m = RenderText:sizeUtf8Text(0, w, face, text, true, false)
    local baseline = y + math.floor((h + m.y_top - m.y_bottom) / 2)
    local tx = x + math.floor((w - m.x) / 2)
    RenderText:renderUtf8Text(bb, tx, baseline, face, text, true, false, color)
end

function TatamiBoardWidget:paintTo(bb, x, y)
    local board = self.board
    if not board then return end
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }

    local n, N = board.n, board.N
    local cell = self.dimen.w / n
    local function cx(c) return x + math.floor((c - 1) * cell) end
    local function cy(r) return y + math.floor((r - 1) * cell) end

    bb:paintRect(x, y, self.dimen.w, self.dimen.h, C_BG)

    -- Cell backgrounds
    local sel = board.selected
    for r = 1, n do
        for c = 1, n do
            local color
            if sel and sel[1] == r and sel[2] == c then
                color = C_SEL
            elseif board.wrong[r][c] then
                color = C_WRONG
            elseif board:isGiven(r, c) then
                color = C_GIVEN_BG
            end
            if color then
                bb:paintRect(cx(c), cy(r), cx(c + 1) - cx(c), cy(r + 1) - cy(r), color)
            end
        end
    end

    -- Thin grid lines between every cell
    local thin = Size.line.thin or 1
    for i = 1, n - 1 do
        local p = math.floor(i * cell)
        drawLine(bb, x + p, y, thin, self.dimen.h, C_GRID)
        drawLine(bb, x, y + p, self.dimen.w, thin, C_GRID)
    end

    -- Mat outlines: a thick wall wherever two neighbouring cells belong to
    -- different mats, centred on the shared edge, plus the outer border.
    local thick = math.max(Size.line.thick or 2, math.floor(cell * 0.07))
    local half  = math.floor(thick / 2)
    local w, h = self.dimen.w, self.dimen.h
    -- Walls run half a line past each end so corners close; clipped to the
    -- board so none pokes out of the outer border.
    local function wall(x0, y0, ww, hh)
        local x1, y1 = math.min(x0 + ww, x + w), math.min(y0 + hh, y + h)
        x0, y0 = math.max(x0, x), math.max(y0, y)
        if x1 > x0 and y1 > y0 then drawLine(bb, x0, y0, x1 - x0, y1 - y0, C_LINE) end
    end
    for r = 1, n do
        for c = 1, n do
            if board:wallRight(r, c) then
                wall(cx(c + 1) - half, cy(r) - half, thick, cy(r + 1) - cy(r) + thick)
            end
            if board:wallBelow(r, c) then
                wall(cx(c) - half, cy(r + 1) - half, cx(c + 1) - cx(c) + thick, thick)
            end
        end
    end
    drawLine(bb, x, y, w, thick, C_LINE)
    drawLine(bb, x, y + h - thick, w, thick, C_LINE)
    drawLine(bb, x, y, thick, h, C_LINE)
    drawLine(bb, x + w - thick, y, thick, h, C_LINE)

    -- Digits and notes
    local pad = self.number_padding or 2
    local note_cols = (N == 4) and 2 or 3
    local note_rows = math.ceil(N / note_cols)
    for r = 1, n do
        for c = 1, n do
            local x0, y0 = cx(c), cy(r)
            local cw, ch = cx(c + 1) - x0, cy(r + 1) - y0
            local v = board:getValue(r, c)
            if v ~= 0 then
                drawText(bb, self.number_face, tostring(v), x0 + pad, y0 + pad,
                    cw - 2 * pad, ch - 2 * pad,
                    board:isGiven(r, c) and C_GIVEN_FG or C_USER_FG)
            else
                local notes = board.notes[r][c]
                local mw = (cw - 2 * thick) / note_cols
                local mh = (ch - 2 * thick) / 3
                for d = 1, N do
                    if notes[d] then
                        local mc = (d - 1) % note_cols
                        local mr = math.floor((d - 1) / note_cols)
                        -- Two note rows (N = 4) sit in the top and bottom
                        -- thirds; one row (N = 3) sits in the top third.
                        local row_slot = note_rows == 2 and mr * 2 or mr
                        drawText(bb, self.note_face, tostring(d),
                            x0 + thick + math.floor(mc * mw), y0 + thick + math.floor(row_slot * mh),
                            math.floor(mw), math.floor(mh), C_NOTE_FG)
                    end
                end
            end
        end
    end
end

return TatamiBoardWidget
