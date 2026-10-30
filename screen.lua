local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase          = require("screen_base")
local MenuHelper          = require("menu_helper")
local TatamiBoard         = lrequire("board")
local TatamiBoardWidget   = lrequire("board_widget")

local GAME_RULES_EN = _([[
Tatami — Rules

Cover the whole grid with dominoes: pair every cell with one orthogonally adjacent cell.

Rules:
• Every cell belongs to exactly one domino.
• No four dominoes may meet corner-to-corner at a single point — the "cross" joint that real tatami mat floors avoid.
• Dominoes drawn in thick black are given clues and cannot be changed.

Tap a cell to select it, then tap an adjacent cell to join them into a domino. Join a cell to a different neighbour to move its domino; select one half of a domino and tap the other half to remove it. Tap the selected cell again to deselect it.
]])

local GAME_RULES_FR = [[
Tatami — Règles

Couvrez toute la grille de dominos : associez chaque case à une case orthogonalement adjacente.

Règles :
• Chaque case appartient à exactement un domino.
• Quatre dominos ne peuvent pas se rejoindre par leurs coins en un même point — le joint « en croix » qu'évitent les vrais sols en tatamis.
• Les dominos tracés en noir épais sont des indices donnés et ne peuvent pas être modifiés.

Appuyez sur une case pour la sélectionner, puis sur une case adjacente pour les réunir en un domino. Reliez une case à un autre voisin pour déplacer son domino ; sélectionnez une moitié d'un domino puis appuyez sur l'autre moitié pour le retirer. Appuyez à nouveau sur la case sélectionnée pour la désélectionner.
]]

local TatamiScreen = ScreenBase:extend{}

function TatamiScreen:init()
    local state = self.plugin:loadState()
    local n     = self.plugin:getSetting("grid_n", TatamiBoard.DEFAULT_N)
    self.board  = TatamiBoard:new{ n = n }
    if not self.board:load(state) then
        self.board:generate(self.plugin:getSetting("difficulty", "easy"))
    end
    ScreenBase.init(self)
end

function TatamiScreen:serializeState()
    return self.board:serialize()
end

function TatamiScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Tatami"), function()
        return {
            { text = _("New game"),            callback = function() self:onNewGame() end },
            { text = self:getSizeButtonText(), callback = function() self:openSizeMenu() end },
            { text = self:getDiffButtonText(), callback = function() self:openDifficultyMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    -- Controls first: the board is sized from whatever room they leave.
    self.status_text:setMaxWidth(self:getControlsWidth())
    local action_bar = self:buildActionBar({
        { text = _("Undo"),   callback = function() self:onUndo() end },
        { text = _("Clear"),  callback = function() self:onClear() end },
        { text = _("Reveal"), callback = function() self:onReveal() end },
    })
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        action_bar,
    }

    -- The widget draws its own thick outer border, so the frame only pads.
    local frame_pad   = Size.padding.large
    local frame_extra = 2 * frame_pad
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = TatamiBoardWidget:new{
        board        = self.board,
        max_size     = math.min(budget_w, budget_h) - frame_extra,
        onCellAction = function(r, c) self:onCellAction(r, c) end,
    }
    local board_frame = FrameContainer:new{
        padding    = frame_pad,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

function TatamiScreen:onCellAction(r, c)
    local result = self.board:tapCell(r, c)
    self.board_widget:refresh()
    if result == "connected" then
        self:updateStatus()
        self.plugin:saveState(self.board:serialize())
    elseif result == "disconnected" then
        self:updateStatus()
        self.plugin:saveState(self.board:serialize())
    elseif result == "selected" then
        -- The selection is shaded on the board; how to join it is in the rules.
        self:updateStatus()
    elseif result == "deselected" then
        self:updateStatus()
    elseif result == "won" then
        self:updateStatus(_("Congratulations! Puzzle solved!"))
    end
    self:refreshActionBar()
end

function TatamiScreen:onUndo()
    if self.board:undoMove() then
        self.board_widget:refresh()
        self:updateStatus()
        self.plugin:saveState(self.board:serialize())
        self:refreshActionBar()
    end
end

function TatamiScreen:onClear()
    self.board:clearUser()
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
    self:refreshActionBar()
end

function TatamiScreen:onReveal()
    self.board:reveal()
    self.board_widget:refresh()
    self:updateStatus(_("Solution revealed."))
    self.plugin:saveState(self.board:serialize())
    self:refreshActionBar()
end

function TatamiScreen:isRoundOver()
    return self.board.won
end

function TatamiScreen:onNewGame()
    local diff = self.plugin:getSetting("difficulty", "easy")
    local n    = self.plugin:getSetting("grid_n", TatamiBoard.DEFAULT_N)
    self.board = TatamiBoard:new{ n = n }
    self.board:generate(diff)
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function TatamiScreen:openSizeMenu()
    local sizes = {}
    for _, sz in ipairs(TatamiBoard.SIZES) do
        sizes[#sizes + 1] = { id = sz, text = sz .. "\xC3\x97" .. sz }
    end
    MenuHelper.openSizeMenu{
        title     = _("Select size"),
        sizes     = sizes,
        current   = self.plugin:getSetting("grid_n", TatamiBoard.DEFAULT_N),
        parent    = self,
        on_select = function(sz)
            if sz ~= self.board.n then
                self.plugin:saveSetting("grid_n", sz)
                self:onNewGame()
            end
        end,
    }
end

function TatamiScreen:openDifficultyMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "easy"),
        parent    = self,
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            if self.diff_button then
                self.diff_button:setText(self:getDiffButtonText(), self.diff_button.width)
            end
            self:onNewGame()
        end,
    }
end

function TatamiScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board.won then
        status = _("Congratulations! Puzzle solved!")
    else
        local placed = self.board:countPlaced()
        local total  = self.board:totalDominoes()
        local n      = self.board.n
        local diff   = self.plugin:getSetting("difficulty", "easy")
        local label  = MenuHelper.DIFFICULTY_LABELS[diff] or diff
        status = self:joinStatus(
            T("%1×%1", n), label, T(_("Dominoes: %1/%2"), placed, total))
    end
    ScreenBase.updateStatus(self, status)
end

function TatamiScreen:getSizeButtonText()
    local n = self.board.n
    return T(_("Size: %1"), n .. "\xC3\x97" .. n)
end

function TatamiScreen:getDiffButtonText()
    local diff  = self.plugin:getSetting("difficulty", "easy")
    local label = MenuHelper.DIFFICULTY_LABELS[diff] or diff
    return T(_("Difficulty: %1"), label)
end

return TatamiScreen
