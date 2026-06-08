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
-- Helper: draw a domino connection line between two adjacent cells
-- The line is drawn along the shared edge (centred), inset slightly.
-- ---------------------------------------------------------------------------

local function drawDominoEdge(bb, x1, y1, x2, y2, cell, thickness, color)
    local inset = math.max(2, math.floor(cell * 0.15))
    if y1 == y2 then
        -- Horizontal domino: shared vertical edge between (r,c) and (r,c±1)
        local ex = math.floor((x1 + x2 + cell) / 2) -- shared edge x
        -- Draw a vertical line segment at shared edge
        local ey1 = math.min(y1, y2) + inset
        local ey2 = math.min(y1, y2) + math.ceil(cell) - inset
        drawLine(bb, ex - math.floor(thickness / 2), ey1, thickness, ey2 - ey1, color)
    else
        -- Vertical domino: shared horizontal edge between (r,c) and (r±1,c)
        local ey = math.floor((y1 + y2 + cell) / 2)
        local ex1 = math.min(x1, x2) + inset
        local ex2 = math.min(x1, x2) + math.ceil(cell) - inset
        drawLine(bb, ex1, ey - math.floor(thickness / 2), ex2 - ex1, thickness, color)
    end
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
        drawLine(bb, x + math.floor(i * cell), y, lw, self.dimen.h, C_LINE)
        drawLine(bb, x, y + math.floor(i * cell), self.dimen.w, lw, C_LINE)
    end

    -- Domino connections
    local given_thick = math.max(4, math.floor(cell * 0.15))
    local user_thick  = math.max(2, math.floor(cell * 0.08))
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
                        drawDominoEdge(bb, cx1, cy1, cx2, cy2, cell, thickness, color)
                    end
                end
            end
        end
    end
end

return TatamiBoardWidget
