local Blitbuffer = require("ffi/blitbuffer")
local Geom       = require("ui/geometry")
local RenderText = require("ui/rendertext")
local Size       = require("ui/size")

local gwb            = require("grid_widget_base")
local GridWidgetBase = gwb.GridWidgetBase
local drawLine       = gwb.drawLine

-- ---------------------------------------------------------------------------
-- Colours
-- ---------------------------------------------------------------------------

local C_BG        = Blitbuffer.COLOR_WHITE
local C_LINE      = Blitbuffer.COLOR_BLACK
local C_GRID      = Blitbuffer.COLOR_GRAY_9
local C_SEL_BG    = Blitbuffer.COLOR_GRAY_D
local C_GIVEN_DOM = Blitbuffer.COLOR_BLACK       -- given domino edge: thick black
local C_USER_DOM  = Blitbuffer.COLOR_GRAY_4      -- player domino edge: medium grey

-- ---------------------------------------------------------------------------
-- TatamiBoardWidget
-- ---------------------------------------------------------------------------

local TatamiBoardWidget = GridWidgetBase:extend{
    board = nil,
}

function TatamiBoardWidget:init()
    local n   = self.board and self.board.n or 4
    self.cols = n
    self.rows = n
    GridWidgetBase.init(self)
end

function TatamiBoardWidget:onCellTap(row, col)
    if self.onCellAction then
        self.onCellAction(row, col)
    end
end

-- ---------------------------------------------------------------------------
-- Helper: draw a domino as a bar joining the centres of its two cells.
-- (It used to be a bar along their shared edge, which reads as a wall
-- *between* the cells -- the opposite of what a domino is.)
-- ---------------------------------------------------------------------------

local function drawDomino(bb, x1, y1, x2, y2, cell, thickness, color)
    local half = math.floor(cell / 2)
    local cx1, cy1 = x1 + half, y1 + half
    local cx2, cy2 = x2 + half, y2 + half
    local t2 = math.floor(thickness / 2)
    if y1 == y2 then
        local lx = math.min(cx1, cx2)
        drawLine(bb, lx, cy1 - t2, math.abs(cx2 - cx1), thickness, color)
    else
        local ly = math.min(cy1, cy2)
        drawLine(bb, cx1 - t2, ly, thickness, math.abs(cy2 - cy1), color)
    end
    -- A dot on each cell end, so the bar reads as a joined pair.
    local dot_r = math.max(thickness, math.floor(cell * 0.12))
    bb:paintCircle(cx1, cy1, dot_r, color)
    bb:paintCircle(cx2, cy2, dot_r, color)
end

-- ---------------------------------------------------------------------------
-- paintTo
-- ---------------------------------------------------------------------------

function TatamiBoardWidget:paintTo(bb, x, y)
    if not self.board then return end
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }

    local board = self.board
    local n     = board.n
    local cell  = self.dimen.w / n

    -- Background
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, C_BG)

    -- Selected cell highlight
    if board.selected then
        local sr = board.selected[1]
        local sc = board.selected[2]
        local sx = x + math.floor((sc - 1) * cell)
        local sy = y + math.floor((sr - 1) * cell)
        bb:paintRect(sx, sy, math.ceil(cell), math.ceil(cell), C_SEL_BG)
    end

    -- Grid lines
    local thin  = Size.line.thin  or 1
    local thick = math.max(2, math.floor(cell * 0.06))

    for i = 0, n do
        local lw = (i == 0 or i == n) and thick or thin
        -- The closing line sits inside the widget: drawn at i * cell it
        -- would spill lw - 1 pixels past the right and bottom edges.
        local off = (i == n) and (self.dimen.w - lw) or math.floor(i * cell)
        drawLine(bb, x + off, y, lw, self.dimen.h, C_LINE)
        drawLine(bb, x, y + off, self.dimen.w, lw, C_LINE)
    end

    -- Domino connections
    local given_thick = math.max(4, math.floor(cell * 0.12))
    local user_thick  = math.max(3, math.floor(cell * 0.08))
    local seen = {}
    for r = 1, n do seen[r] = {} end

    for r = 1, n do
        for c = 1, n do
            if not seen[r][c] then
                local up = board.user_pairs[r][c]
                if up then
                    local r2, c2 = up[1], up[2]
                    if not seen[r2][c2] then
                        seen[r][c]   = true
                        seen[r2][c2] = true
                        local cx1 = x + math.floor((c  - 1) * cell)
                        local cy1 = y + math.floor((r  - 1) * cell)
                        local cx2 = x + math.floor((c2 - 1) * cell)
                        local cy2 = y + math.floor((r2 - 1) * cell)
                        local is_given = board.given[r][c] and board.given[r2][c2]
                        local color    = is_given and C_GIVEN_DOM or C_USER_DOM
                        local thickness = is_given and given_thick or user_thick
                        drawDomino(bb, cx1, cy1, cx2, cy2, cell, thickness, color)
                    end
                end
            end
        end
    end
end

return TatamiBoardWidget
