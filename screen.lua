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

local ScreenBase        = require("screen_base")
local MenuHelper        = require("menu_helper")
local GenProgress       = require("gen_progress")
local TatamiBoard       = lrequire("board")
local TatamiBoardWidget = lrequire("board_widget")

local GAME_RULES_EN = _([[
Tatami — Rules

The grid is divided into straight mats, each one cell wide and N cells long (N = 3 on 6×6 and 9×9, N = 4 on 8×8). Fill every cell with a digit from 1 to N so that:

1. Each mat contains every digit from 1 to N exactly once.
2. Each row and each column contains every digit the same number of times (twice on 6×6 and 8×8, three times on 9×9).
3. Two cells that touch by a side never hold the same digit.

Digits on a grey background are given and cannot be changed. Every puzzle has exactly one solution, and it can be found by reasoning alone, without guessing.

Tap a cell to select it, then tap a digit to fill it in; tap the same digit again to clear it. With Notes on, the digits are pencil marks instead. Long-press a cell to erase it.
]])

local GAME_RULES_FR = [[
Tatami — Règles

La grille est découpée en tatamis droits, larges d'une case et longs de N cases (N = 3 en 6×6 et 9×9, N = 4 en 8×8). Remplissez chaque case avec un chiffre de 1 à N de sorte que :

1. Chaque tatami contienne une fois chaque chiffre de 1 à N.
2. Chaque ligne et chaque colonne contienne chaque chiffre le même nombre de fois (deux fois en 6×6 et 8×8, trois fois en 9×9).
3. Deux cases qui se touchent par un côté ne contiennent jamais le même chiffre.

Les chiffres sur fond gris sont donnés et ne peuvent pas être modifiés. Chaque grille a une seule solution, que l'on trouve par le raisonnement seul, sans deviner.

Appuyez sur une case pour la sélectionner, puis sur un chiffre pour la remplir ; appuyez à nouveau sur le même chiffre pour l'effacer. Avec les notes activées, les chiffres deviennent des annotations. Appui long sur une case pour l'effacer.
]]

local TatamiScreen = ScreenBase:extend{}

-- A size saved by 1.x (4×4 existed then) falls back to the default.
local function savedSize(plugin)
    local n = plugin:getSetting("grid_n", TatamiBoard.DEFAULT_N)
    return TatamiBoard.MAT_LEN[n] and n or TatamiBoard.DEFAULT_N
end

function TatamiScreen:init()
    local state = self.plugin:loadState()
    self.board  = TatamiBoard:new{ n = savedSize(self.plugin), empty = true }
    -- load() refuses a 1.x domino save (and anything damaged): a new game
    -- starts instead.
    if not self.board:load(state) then
        local diff = self.plugin:getSetting("difficulty", "easy")
        self.board.difficulty = diff
        GenProgress.run(function(on_progress) self.board:generate(diff, on_progress) end)
    end
    self.note_mode = false
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
            self:makeDailyButtonConfig(),
            { text = self:getSizeButtonText(), callback = function() self:openSizeMenu() end },
            { text = self:getDiffButtonText(), callback = function() self:openDifficultyMenu() end },
            { text = _("Reveal"),              callback = function() self:onReveal() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    local keys = {}
    for d = 1, self.board.N do
        local dv = d
        keys[#keys + 1] = { id = "digit_" .. d, text = tostring(d),
                            callback = function() self:onDigit(dv) end }
    end
    local number_pad = self:buildNumberPad(keys)

    local note_btn  = { id = "note_button", text = self:getNoteButtonText(),
                        callback = function() self:toggleNoteMode() end }
    local erase_btn = { text = _("Erase"), callback = function() self:onErase() end }
    local check_btn = { text = _("Check"), callback = function() self:onCheck() end }
    local hint_btn  = { text = _("Hint"),  callback = function() self:onHint() end }
    local undo_btn  = { text = _("Undo"),  callback = function() self:onUndo() end }
    -- Five labels do not fit the landscape side panel on one row.
    local action_bar = self:buildActionBar(is_landscape
        and { { note_btn, erase_btn, undo_btn }, { check_btn, hint_btn } }
        or  { note_btn, erase_btn, check_btn, hint_btn, undo_btn })
    self.note_button = action_bar:getButtonById("note_button")

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        number_pad,
        VerticalSpan:new{ width = Size.span.vertical_default },
        action_bar,
    }

    -- The widget draws its own thick outer border, so the frame only pads.
    local frame_pad = Size.padding.large
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = TatamiBoardWidget:new{
        board         = self.board,
        max_size      = math.min(budget_w, budget_h) - 2 * frame_pad,
        onCellTap_cb  = function(r, c) self:onCellTap(r, c) end,
        onCellHold_cb = function(r, c) self:onCellHold(r, c) end,
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

-- ---------------------------------------------------------------------------
-- Cell interaction
-- ---------------------------------------------------------------------------

function TatamiScreen:_saveAndRefresh(msg)
    self.plugin:saveState(self.board:serialize())
    self.board_widget:refresh()
    self:updateStatus(msg)
end

function TatamiScreen:onCellTap(r, c)
    self.board:setSelection(r, c)
    self.board_widget:refresh()
    self:updateStatus()
end

function TatamiScreen:onCellHold(r, c)
    self.board:setSelection(r, c)
    self:onErase()
end

function TatamiScreen:onDigit(d)
    local sel = self.board.selected
    if self.board.won then return end
    if not sel then
        self:updateStatus(_("Tap a cell first."))
        return
    end
    local r, c = sel[1], sel[2]
    if self.board:isGiven(r, c) then
        self:updateStatus(_("Cannot edit a given cell."))
        return
    end
    local ok
    if self.note_mode then
        ok = self.board:toggleNote(r, c, d)
    elseif self.board.user[r][c] == d then
        ok = self.board:setValue(r, c, 0)
    else
        ok = self.board:setValue(r, c, d)
    end
    if ok then self:_saveAndRefresh() end
end

function TatamiScreen:onErase()
    local sel = self.board.selected
    if not sel or self.board.won then
        self.board_widget:refresh()
        return
    end
    local ok, err = self.board:clearCell(sel[1], sel[2])
    if ok then
        self:_saveAndRefresh()
    else
        self.board_widget:refresh()
        if err == "given" then self:updateStatus(_("Cannot edit a given cell.")) end
    end
end

function TatamiScreen:onUndo()
    if self.board:undoMove() then self:_saveAndRefresh() end
end

function TatamiScreen:onCheck()
    local wrong, empty = self.board:check()
    self.board_widget:refresh()
    if self.board.won then
        self:updateStatus()
    elseif wrong > 0 then
        self:updateStatus(_("Some cells have errors."))
    else
        self:updateStatus(T(_("Check done. Empty: %1"), empty))
    end
end

function TatamiScreen:onReveal()
    self.board:reveal()
    self:_saveAndRefresh(_("Solution revealed."))
end

function TatamiScreen:toggleNoteMode()
    self.note_mode = not self.note_mode
    if self.note_button then
        self.note_button:setText(self:getNoteButtonText(), self.note_button.width)
    end
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function TatamiScreen:getNoteButtonText()
    return self.note_mode and _("Note: On") or _("Note: Off")
end

-- ---------------------------------------------------------------------------
-- Game / menus
-- ---------------------------------------------------------------------------

function TatamiScreen:onNewGame()
    local diff = self.plugin:getSetting("difficulty", "easy")
    self.board = TatamiBoard:new{ n = savedSize(self.plugin), difficulty = diff, empty = true }
    GenProgress.run(function(on_progress) self.board:generate(diff, on_progress) end)
    self.note_mode = false
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function TatamiScreen:openSizeMenu()
    local sizes = {}
    for _, sz in ipairs(TatamiBoard.SIZES) do
        sizes[#sizes + 1] = {
            id   = sz,
            text = T("%1×%1 (1–%2)", sz, TatamiBoard.MAT_LEN[sz]),
        }
    end
    MenuHelper.openSizeMenu{
        title     = _("Select size"),
        sizes     = sizes,
        current   = savedSize(self.plugin),
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
        local n     = self.board.n
        local diff  = self.board.difficulty or self.plugin:getSetting("difficulty", "easy")
        local label = MenuHelper.DIFFICULTY_LABELS[diff] or diff
        status = self:joinStatus(T("%1×%1", n), label, T(_("Empty: %1"), self.board:countEmpty()))
    end
    ScreenBase.updateStatus(self, status)
    -- Every move, hint, undo and reveal ends with a status update, so this
    -- is where the bar learns that the round ended (or was undone).
    self:refreshActionBar()
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

function TatamiScreen:isRoundOver()
    return self.board.won
end

return TatamiScreen
