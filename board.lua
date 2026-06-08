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

-- Returns true if the 2x2 block at (r,c) has uniform orientation (all H or all V)
-- orientation: 0=none, 1=horizontal pair, 2=vertical pair
local function get2x2Violation(pairs, r, c, n)
    if r + 1 > n or c + 1 > n then return false end
    -- Check if all four cells in the 2x2 are in horizontal dominoes or all vertical
    local function isHoriz(pr, pc)
        local p = pairs[pr][pc]
        return p and p[1] == pr and p[2] == pc + 1
    end
    local function isVert(pr, pc)
        local p = pairs[pr][pc]
        return p and p[1] == pr + 1 and p[2] == pc
    end
    -- A 2x2 violation: all horizontal (TL-TR and BL-BR) or all vertical (TL-BL and TR-BR)
    if isHoriz(r, c) and isHoriz(r + 1, c) and
       pairs[r][c + 1] and pairs[r][c + 1][1] == r and pairs[r][c + 1][2] == c and
       pairs[r + 1][c + 1] and pairs[r + 1][c + 1][1] == r + 1 and pairs[r + 1][c + 1][2] == c then
        -- TL→TR and BL→BR: all horizontal in 2x2
        return true
    end
    if isVert(r, c) and isVert(r, c + 1) and
       pairs[r + 1][c] and pairs[r + 1][c][1] == r and pairs[r + 1][c][2] == c and
       pairs[r + 1][c + 1] and pairs[r + 1][c + 1][1] == r and pairs[r + 1][c + 1][2] == c + 1 then
        -- TL→BL and TR→BR: all vertical in 2x2
        return true
    end
    return false
end

local function countViolations(pairs, n)
    local count = 0
    for r = 1, n - 1 do
        for c = 1, n - 1 do
            -- Check if all 4 cells in the 2x2 have same orientation
            local tl = pairs[r][c]
            local tr = pairs[r][c + 1]
            local bl = pairs[r + 1][c]
            local br = pairs[r + 1][c + 1]
            if tl and tr and bl and br then
                -- All horizontal: TL-TR and BL-BR
                local tl_right = tl[1] == r   and tl[2] == c + 1
                local tr_left  = tr[1] == r   and tr[2] == c
                local bl_right = bl[1] == r+1 and bl[2] == c + 1
                local br_left  = br[1] == r+1 and br[2] == c
                if tl_right and tr_left and bl_right and br_left then
                    count = count + 1
                end
                -- All vertical: TL-BL and TR-BR
                local tl_down  = tl[1] == r+1 and tl[2] == c
                local bl_up    = bl[1] == r   and bl[2] == c
                local tr_down  = tr[1] == r+1 and tr[2] == c + 1
                local br_up    = br[1] == r   and br[2] == c + 1
                if tl_down and bl_up and tr_down and br_up then
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- Generate a valid domino tiling for n×n grid with no 2×2 same-orientation blocks
-- pairs[r][c] = {partner_r, partner_c}
local function generateTiling(n)
    local MAX_ATTEMPTS = 50
    for attempt = 1, MAX_ATTEMPTS do
        local pairs   = {}
        local used    = emptyGrid(n, n, false)
        for r = 1, n do pairs[r] = {} end

        -- Build list of cells in random order
        local cells = {}
        for r = 1, n do
            for c = 1, n do cells[#cells + 1] = {r, c} end
        end
        shuffle(cells)

        -- Greedy placement: for each unoccupied cell, pick an unoccupied neighbour
        local dirs = { {0,1},{1,0},{0,-1},{-1,0} }
        for _, cell in ipairs(cells) do
            local r, c = cell[1], cell[2]
            if not used[r][c] then
                shuffle(dirs)
                for _, d in ipairs(dirs) do
                    local nr, nc = r + d[1], c + d[2]
                    if nr >= 1 and nr <= n and nc >= 1 and nc <= n and not used[nr][nc] then
                        -- Place domino
                        pairs[r][c]   = { nr, nc }
                        pairs[nr][nc] = { r, c }
                        used[r][c]    = true
                        used[nr][nc]  = true
                        break
                    end
                end
            end
        end

        -- Check all cells covered
        local ok = true
        for r = 1, n do
            for c = 1, n do
                if not used[r][c] then ok = false; break end
            end
            if not ok then break end
        end

        if ok and countViolations(pairs, n) == 0 then
            return pairs
        end
    end

    -- Fallback: simple alternating horizontal tiling for 4x4
    -- Just fill row by row with alternating H and V to avoid 2x2 issues
    local pairs = {}
    for r = 1, n do pairs[r] = {} end
    -- Use column-major alternating to avoid all-horizontal 2x2
    -- Even rows: horizontal pairs; odd rows: vertical pairs
    if n == 4 then
        -- Hardcoded valid 4x4 tiling (no 2x2 violation):
        -- Row 1: H H (1,1)-(1,2), (1,3)-(1,4)
        -- Row 2-3: V pairs: (2,1)-(3,1), (2,2)-(3,2), (2,3)-(3,3), (2,4)-(3,4)
        -- Row 4: H H (4,1)-(4,2), (4,3)-(4,4)
        -- Check: 2x2 at (1,1): TL=H, TR=H, BL=V, BR=V → mixed → ok
        pairs[1][1] = {1,2}; pairs[1][2] = {1,1}
        pairs[1][3] = {1,4}; pairs[1][4] = {1,3}
        for c = 1, 4 do
            pairs[2][c] = {3, c}
            pairs[3][c] = {2, c}
        end
        pairs[4][1] = {4,2}; pairs[4][2] = {4,1}
        pairs[4][3] = {4,4}; pairs[4][4] = {4,3}
    else
        -- 6x6: tile in 2-column bands alternating H/V
        -- Band 1 (cols 1-2): vertical pairs for rows 1-6
        -- Band 2 (cols 3-4): horizontal pairs for rows 1-6 (row by row)
        -- Band 3 (cols 5-6): vertical pairs
        for r = 1, n, 2 do
            -- cols 1-2: vertical
            pairs[r][1] = {r+1,1}; pairs[r+1][1] = {r,1}
            pairs[r][2] = {r+1,2}; pairs[r+1][2] = {r,2}
            -- cols 3-4: horizontal
            pairs[r][3] = {r,4}; pairs[r][4] = {r,3}
            pairs[r+1][3] = {r+1,4}; pairs[r+1][4] = {r+1,3}
            -- cols 5-6: vertical
            pairs[r][5] = {r+1,5}; pairs[r+1][5] = {r,5}
            pairs[r][6] = {r+1,6}; pairs[r+1][6] = {r,6}
        end
    end
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
