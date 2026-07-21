local grid_utils = require("grid_utils")
local UndoStack  = require("undo_stack")

local emptyGrid = grid_utils.emptyGrid
local shuffle   = grid_utils.shuffle

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local SIZES     = { 4, 6 }
local DEFAULT_N = 4

-- ---------------------------------------------------------------------------
-- Domino tiling generation
-- ---------------------------------------------------------------------------

-- A domino tiling has a "tatami cross" violation at the interior point
-- shared by cells (r,c),(r,c+1),(r+1,c),(r+1,c+1) when all four of those
-- cells' dominoes extend *outside* that 2x2 block -- i.e. four distinct
-- tiles meet corner-to-corner at one point, the traditional bad-luck
-- tatami-mat arrangement. (The previous implementation instead forbade a
-- 2x2 block being covered by two parallel same-orientation dominoes, which
-- is a different -- and, per an exhaustive check, mathematically
-- unsatisfiable -- constraint: every one of the 36 domino tilings of a 4x4
-- grid, and all 6728 tilings of a 6x6 grid, violated it at least once. That
-- meant this plugin could never generate anything but its hardcoded
-- fallback board, on either supported size, ever.)
local function countCrossViolations(pairs, n)
    local count = 0
    for r = 1, n - 1 do
        for c = 1, n - 1 do
            local tl, tr = pairs[r][c], pairs[r][c + 1]
            local bl, br = pairs[r + 1][c], pairs[r + 1][c + 1]
            local tl_inside = (tl[1] == r and tl[2] == c + 1) or (tl[1] == r + 1 and tl[2] == c)
            local tr_inside = (tr[1] == r and tr[2] == c) or (tr[1] == r + 1 and tr[2] == c + 1)
            local bl_inside = (bl[1] == r and bl[2] == c) or (bl[1] == r + 1 and bl[2] == c + 1)
            local br_inside = (br[1] == r and br[2] == c + 1) or (br[1] == r + 1 and br[2] == c)
            if not tl_inside and not tr_inside and not bl_inside and not br_inside then
                count = count + 1
            end
        end
    end
    return count
end

-- ---------------------------------------------------------------------------
-- Generator
-- ---------------------------------------------------------------------------

-- Recursively tile an n x n block (n even) starting at (r0,c0) with a
-- "pinwheel" domino pattern that is always cross-violation-free: tile the
-- outer 1-cell-thick frame (long sides get pairs running along the frame,
-- short sides get a single pair closing each corner), then recurse into the
-- (n-2)x(n-2) core with the *same* orientation. Exhaustive search over all
-- 36 (n=4) and 6728 (n=6) domino tilings found exactly 2 valid tilings for
-- each size -- this construction and its `horiz=false` transpose are
-- exactly those 2 -- so there is no retry/failure case to handle here; this
-- always succeeds by construction.
local function fillPinwheel(pairs, r0, c0, size, horiz)
    if size <= 0 then return end
    if size == 2 then
        if horiz then
            pairs[r0][c0]         = { r0, c0 + 1 };     pairs[r0][c0 + 1]         = { r0, c0 }
            pairs[r0 + 1][c0]     = { r0 + 1, c0 + 1 };  pairs[r0 + 1][c0 + 1]     = { r0 + 1, c0 }
        else
            pairs[r0][c0]         = { r0 + 1, c0 };      pairs[r0 + 1][c0]         = { r0, c0 }
            pairs[r0][c0 + 1]     = { r0 + 1, c0 + 1 };  pairs[r0 + 1][c0 + 1]     = { r0, c0 + 1 }
        end
        return
    end
    local last = r0 + size - 1
    if horiz then
        for c = c0, last, 2 do
            pairs[r0][c]     = { r0, c + 1 };     pairs[r0][c + 1]     = { r0, c }
            pairs[last][c]   = { last, c + 1 };   pairs[last][c + 1]   = { last, c }
        end
        for r = r0 + 1, last - 1, 2 do
            pairs[r][c0]     = { r + 1, c0 };     pairs[r + 1][c0]     = { r, c0 }
            pairs[r][last]   = { r + 1, last };   pairs[r + 1][last]   = { r, last }
        end
    else
        for r = r0, last, 2 do
            pairs[r][c0]     = { r + 1, c0 };     pairs[r + 1][c0]     = { r, c0 }
            pairs[r][last]   = { r + 1, last };   pairs[r + 1][last]   = { r, last }
        end
        for c = c0 + 1, last - 1, 2 do
            pairs[r0][c]     = { r0, c + 1 };     pairs[r0][c + 1]     = { r0, c }
            pairs[last][c]   = { last, c + 1 };   pairs[last][c + 1]   = { last, c }
        end
    end
    fillPinwheel(pairs, r0 + 1, c0 + 1, size - 2, horiz)
end

-- Generate a valid domino tiling for an n x n grid with no tatami cross
-- violations. pairs[r][c] = {partner_r, partner_c}
local function generateTiling(n)
    local pairs = {}
    for r = 1, n do pairs[r] = {} end
    fillPinwheel(pairs, 1, 1, n, math.random(2) == 1)
    return pairs
end

-- ---------------------------------------------------------------------------
-- Clue selection: reveal a fraction of dominoes as given
-- ---------------------------------------------------------------------------

local function selectGivens(pairs, n, difficulty)
    local ratio
    if     difficulty == "easy"   then ratio = 0.50
    elseif difficulty == "hard"   then ratio = 0.20
    else                               ratio = 0.35
    end

    -- Collect all unique domino ids (one entry per domino)
    local dominos = {}
    local seen    = emptyGrid(n, n, false)
    for r = 1, n do
        for c = 1, n do
            if not seen[r][c] then
                local p = pairs[r][c]
                seen[r][c]    = true
                seen[p[1]][p[2]] = true
                dominos[#dominos + 1] = { r, c, p[1], p[2] }
            end
        end
    end

    shuffle(dominos)
    local total  = #dominos
    local n_give = math.max(1, math.floor(total * ratio))
    local given  = emptyGrid(n, n, false)
    for i = 1, n_give do
        local d = dominos[i]
        given[d[1]][d[2]] = true
        given[d[3]][d[4]] = true
    end
    return given
end

-- ---------------------------------------------------------------------------
-- TatamiBoard
-- ---------------------------------------------------------------------------

local TatamiBoard = {}
TatamiBoard.__index = TatamiBoard

function TatamiBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        n          = opts.n          or DEFAULT_N,
        difficulty = opts.difficulty or "medium",
        sol_pairs  = nil,  -- solution: sol_pairs[r][c] = {r2, c2}
        given      = nil,  -- given[r][c] = true if pre-revealed
        user_pairs = nil,  -- user's domino connections
        selected   = nil,  -- currently selected cell {r, c}
        won        = false,
        undo       = UndoStack:new{ max_size = 500 },
    }, self)
    obj:generate()
    return obj
end

function TatamiBoard:generate(diff)
    self.difficulty = diff or self.difficulty
    local n = self.n
    local pairs = generateTiling(n)
    self.sol_pairs  = pairs
    self.given      = selectGivens(pairs, n, self.difficulty)
    -- Pre-fill user_pairs with given connections
    self.user_pairs = {}
    for r = 1, n do
        self.user_pairs[r] = {}
        for c = 1, n do
            if self.given[r][c] then
                self.user_pairs[r][c] = { self.sol_pairs[r][c][1], self.sol_pairs[r][c][2] }
            else
                self.user_pairs[r][c] = nil
            end
        end
    end
    self.selected = nil
    self.won      = false
    self.undo:clear()
end

-- Tap a cell: if no selection, select it. If selection exists, try to connect.
function TatamiBoard:tapCell(r, c)
    if self.won then return "won" end
    if self.given[r][c] then
        -- If the tapped cell is given, just update selection
        self.selected = { r, c }
        return "selected"
    end
    if self.selected == nil then
        self.selected = { r, c }
        return "selected"
    end
    local sr, sc = self.selected[1], self.selected[2]
    if sr == r and sc == c then
        -- Deselect
        self.selected = nil
        return "deselected"
    end
    -- Check adjacency
    local dr = math.abs(r - sr)
    local dc = math.abs(c - sc)
    if (dr == 1 and dc == 0) or (dr == 0 and dc == 1) then
        -- Adjacent: connect or disconnect
        local existing_r = self.user_pairs[r][c]
        local existing_s = self.user_pairs[sr][sc]
        if existing_r and existing_r[1] == sr and existing_r[2] == sc then
            -- Already connected — remove
            if not self.given[r][c] and not self.given[sr][sc] then
                self.undo:push{ type="disconnect", r1=sr,c1=sc, r2=r,c2=c }
                self.user_pairs[sr][sc] = nil
                self.user_pairs[r][c]   = nil
                self.selected = nil
                self:_checkWin()
                return "disconnected"
            end
        else
            -- Remove old connections if any
            local old_s = nil
            local old_rc = nil
            if existing_s and not self.given[sr][sc] then
                local or2, oc2 = existing_s[1], existing_s[2]
                if not self.given[or2][oc2] then
                    old_s = { r1=sr,c1=sc, r2=or2,c2=oc2,
                              was_s=existing_s, was_other=self.user_pairs[or2][oc2] }
                    self.user_pairs[sr][sc]  = nil
                    self.user_pairs[or2][oc2] = nil
                end
            end
            if existing_r and not self.given[r][c] then
                local or2, oc2 = existing_r[1], existing_r[2]
                if not self.given[or2][oc2] then
                    old_rc = { r1=r,c1=c, r2=or2,c2=oc2,
                               was_rc=existing_r, was_other=self.user_pairs[or2][oc2] }
                    self.user_pairs[r][c]     = nil
                    self.user_pairs[or2][oc2] = nil
                end
            end
            -- Connect
            self.undo:push{ type="connect", r1=sr,c1=sc, r2=r,c2=c,
                            old_s=old_s, old_rc=old_rc }
            self.user_pairs[sr][sc] = { r, c }
            self.user_pairs[r][c]   = { sr, sc }
            self.selected = nil
            self:_checkWin()
            return "connected"
        end
    end
    -- Not adjacent: update selection
    self.selected = { r, c }
    return "selected"
end

function TatamiBoard:undoMove()
    local entry = self.undo:pop()
    if not entry then return false end
    if entry.type == "connect" then
        self.user_pairs[entry.r1][entry.c1] = nil
        self.user_pairs[entry.r2][entry.c2] = nil
        -- Restore old connections
        if entry.old_s then
            local e = entry.old_s
            self.user_pairs[e.r1][e.c1] = e.was_s
            self.user_pairs[e.r2][e.c2] = e.was_other
        end
        if entry.old_rc then
            local e = entry.old_rc
            self.user_pairs[e.r1][e.c1] = e.was_rc
            self.user_pairs[e.r2][e.c2] = e.was_other
        end
    elseif entry.type == "disconnect" then
        self.user_pairs[entry.r1][entry.c1] = { entry.r2, entry.c2 }
        self.user_pairs[entry.r2][entry.c2] = { entry.r1, entry.c1 }
    end
    self.won = false
    return true
end

function TatamiBoard:_checkWin()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            local up = self.user_pairs[r][c]
            local sp = self.sol_pairs[r][c]
            if not up then
                self.won = false
                return
            end
            if up[1] ~= sp[1] or up[2] ~= sp[2] then
                self.won = false
                return
            end
        end
    end
    self.won = true
end

function TatamiBoard:countPlaced()
    local n, count = self.n, 0
    local seen = emptyGrid(n, n, false)
    for r = 1, n do
        for c = 1, n do
            if self.user_pairs[r][c] and not seen[r][c] then
                local p = self.user_pairs[r][c]
                seen[r][c]    = true
                seen[p[1]][p[2]] = true
                count = count + 1
            end
        end
    end
    return count
end

function TatamiBoard:totalDominoes()
    return (self.n * self.n) / 2
end

function TatamiBoard:reveal()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            local p = self.sol_pairs[r][c]
            self.user_pairs[r][c] = { p[1], p[2] }
        end
    end
    self.won = true
end

function TatamiBoard:clearUser()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            if not self.given[r][c] then
                self.user_pairs[r][c] = nil
            end
        end
    end
    -- Re-break partner links for given dominoes
    for r = 1, n do
        for c = 1, n do
            if self.given[r][c] then
                local p = self.sol_pairs[r][c]
                self.user_pairs[r][c] = { p[1], p[2] }
            end
        end
    end
    self.won     = false
    self.selected = nil
    self.undo:clear()
end

-- ---------------------------------------------------------------------------
-- Serialization
-- ---------------------------------------------------------------------------

function TatamiBoard:serialize()
    local n = self.n
    local sol_flat, given_flat, user_flat = {}, {}, {}
    for r = 1, n do
        for c = 1, n do
            local sp = self.sol_pairs[r][c]
            sol_flat[#sol_flat + 1] = sp and (sp[1] * 100 + sp[2]) or 0
            given_flat[#given_flat + 1] = self.given[r][c] and 1 or 0
            local up = self.user_pairs[r][c]
            user_flat[#user_flat + 1] = up and (up[1] * 100 + up[2]) or 0
        end
    end
    return {
        n          = self.n,
        difficulty = self.difficulty,
        sol        = sol_flat,
        given      = given_flat,
        user       = user_flat,
        won        = self.won,
    }
end

function TatamiBoard:load(data)
    if type(data) ~= "table" or not data.sol then return false end
    local n = data.n or DEFAULT_N
    self.n          = n
    self.difficulty = data.difficulty or "medium"
    self.sol_pairs  = {}
    self.given      = emptyGrid(n, n, false)
    self.user_pairs = {}
    for r = 1, n do
        self.sol_pairs[r]  = {}
        self.user_pairs[r] = {}
    end
    local idx = 1
    for r = 1, n do
        for c = 1, n do
            local sv = data.sol[idx] or 0
            if sv > 0 then
                self.sol_pairs[r][c] = { math.floor(sv / 100), sv % 100 }
            end
            self.given[r][c] = (data.given[idx] or 0) == 1
            local uv = data.user[idx] or 0
            if uv > 0 then
                self.user_pairs[r][c] = { math.floor(uv / 100), uv % 100 }
            end
            idx = idx + 1
        end
    end
    self.won      = data.won or false
    self.selected = nil
    self.undo:clear()
    return true
end

TatamiBoard.SIZES     = SIZES
TatamiBoard.DEFAULT_N = DEFAULT_N

return TatamiBoard
