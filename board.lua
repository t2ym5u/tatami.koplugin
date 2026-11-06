-- ---------------------------------------------------------------------------
-- Tatami -- the number puzzle.
--
-- The grid is cut into straight 1xN / Nx1 regions ("mats"). The player fills
-- every cell with a digit 1..N so that:
--   1. each mat holds every digit 1..N exactly once;
--   2. every row and every column holds each digit the same number of times
--      (n / N times, n being the grid side);
--   3. two orthogonally adjacent cells never hold the same digit.
-- Some digits are given. This is the standard ruleset (puzzle sites list it
-- as "Tatami": blocks 1xN, digits 1..N, equal counts per line, no equal
-- orthogonal neighbours).
--
-- N = 2 is not offered: with two digits the no-equal-neighbour rule alone
-- forces a checkerboard, so every 2-mat grid has the same two answers.
--
-- Generation: random mat layout, random filled solution (both by
-- backtracking under node caps), then a dig that removes givens as long as a
-- no-trial human solver still finishes. The solver only makes sound
-- deductions, so a puzzle it finishes has exactly one solution. Everything
-- draws from math.random and nothing reads the clock: a seed gives the same
-- puzzle on every device (the Daily Challenge relies on it). Every loop
-- iterates arrays in index order, never pairs(), for the same reason.
-- ---------------------------------------------------------------------------

local UndoStack = require("undo_stack")
local Hint      = require("hint")

local SIZES     = { 6, 8, 9 }
local MAT_LEN   = { [6] = 3, [8] = 4, [9] = 3 }
local DEFAULT_N = 6
-- Save format. Saves from 1.x (the domino tiling game) carry no `format`
-- field and are ignored: the screen starts a new game instead.
local FORMAT    = 2

local LAYOUT_NODE_CAP = 4000
local FILL_NODE_CAP   = 800

-- Per level:
--   tier      solver tier allowed while digging;
--   attempts  digs tried per grid side, each on a new layout and solution,
--             until one needs the wanted amount of tier-2 work (a 6x6 dig
--             is cheap and often needs none, so it gets more tries);
--   min_t2    tier-2 steps wanted (per grid side);
--   max_t2    Medium: above this, givens come back (at most n/2 of them)
--             until the grid is lighter;
--   floor     Easy: share of the cells given at least (the bare tier-1 dig
--             leaves very few, which reads as hard even when it is not).
local LEVELS = {
    easy   = { tier = 1, attempts = { [6] = 1, [8] = 1, [9] = 1 }, floor = 0.25 },
    medium = { tier = 2, attempts = { [6] = 20, [8] = 6, [9] = 6 },
               min_t2 = { [6] = 1, [8] = 1, [9] = 1 },
               max_t2 = { [6] = 1, [8] = 2, [9] = 3 } },
    hard   = { tier = 2, attempts = { [6] = 24, [8] = 5, [9] = 6 },
               min_t2 = { [6] = 2, [8] = 3, [9] = 4 } },
}

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- ---------------------------------------------------------------------------
-- Mat layout: reg[i] = mat id for cell i = (r-1)*n + c; mats[g] = cell list.
-- Fills the first empty cell in reading order with a horizontal or a vertical
-- mat (random order), backtracking on dead ends. nil once the cap is spent.
-- ---------------------------------------------------------------------------

local function makeLayout(n, N)
    local reg = {}
    for i = 1, n * n do reg[i] = 0 end
    local mats = {}
    local nodes = 0

    local function rec(start)
        local i = start
        while i <= n * n and reg[i] ~= 0 do i = i + 1 end
        if i > n * n then return true end
        nodes = nodes + 1
        if nodes > LAYOUT_NODE_CAP then return false end
        local r = math.floor((i - 1) / n) + 1
        local c = (i - 1) % n + 1
        local dirs = math.random(2) == 1 and { 1, 2 } or { 2, 1 }
        for _, d in ipairs(dirs) do
            local cells = {}
            local ok = true
            for k = 0, N - 1 do
                local rr, cc = r, c
                if d == 1 then cc = c + k else rr = r + k end
                if rr > n or cc > n then ok = false; break end
                local j = (rr - 1) * n + cc
                if reg[j] ~= 0 then ok = false; break end
                cells[#cells + 1] = j
            end
            if ok then
                local g = #mats + 1
                mats[g] = cells
                for _, j in ipairs(cells) do reg[j] = g end
                if rec(i + 1) then return true end
                if nodes > LAYOUT_NODE_CAP then return false end
                for _, j in ipairs(cells) do reg[j] = 0 end
                mats[g] = nil
            end
        end
        return false
    end

    if not rec(1) then return nil end
    -- A grid of only horizontal (or only vertical) mats is dull and leans on
    -- one kind of reasoning: ask for a real mix.
    local horiz = 0
    for _, cells in ipairs(mats) do
        if cells[2] == cells[1] + 1 then horiz = horiz + 1 end
    end
    if horiz < #mats * 0.3 or horiz > #mats * 0.7 then return nil end
    return reg, mats
end

-- ---------------------------------------------------------------------------
-- Static context shared by the filler and the solver.
-- ---------------------------------------------------------------------------

local function makeContext(n, N, reg, mats)
    local ctx = { n = n, N = N, k = n / N, reg = reg, mats = mats, size = n * n }
    local row, col, nbrs = {}, {}, {}
    for i = 1, n * n do
        local r = math.floor((i - 1) / n) + 1
        local c = (i - 1) % n + 1
        row[i], col[i] = r, c
        local nb = {}
        if r > 1 then nb[#nb + 1] = i - n end
        if c > 1 then nb[#nb + 1] = i - 1 end
        if c < n then nb[#nb + 1] = i + 1 end
        if r < n then nb[#nb + 1] = i + n end
        nbrs[i] = nb
    end
    ctx.row, ctx.col, ctx.nbrs = row, col, nbrs
    -- Lines 1..n are the rows, n+1..2n the columns.
    local lines = {}
    for r = 1, n do
        local L = {}
        for c = 1, n do L[c] = (r - 1) * n + c end
        lines[r] = L
    end
    for c = 1, n do
        local L = {}
        for r = 1, n do L[r] = (r - 1) * n + c end
        lines[n + c] = L
    end
    ctx.lines = lines
    -- For every line, the mats crossing it: their cells inside and outside.
    local parts = {}
    for li = 1, 2 * n do
        local inLine = {}
        for _, i in ipairs(lines[li]) do inLine[i] = true end
        local seen, list = {}, {}
        for _, i in ipairs(lines[li]) do
            local g = reg[i]
            if not seen[g] then
                seen[g] = true
                local p = { g = g, inside = {}, outside = {} }
                for _, j in ipairs(mats[g]) do
                    if inLine[j] then p.inside[#p.inside + 1] = j
                    else p.outside[#p.outside + 1] = j end
                end
                list[#list + 1] = p
            end
        end
        parts[li] = list
    end
    ctx.parts = parts
    return ctx
end

-- ---------------------------------------------------------------------------
-- Random filled solution: cells in reading order, digits in random order,
-- checked against the mat, the line counts and the left/upper neighbours.
-- Returns sol[i] or nil once the node cap is spent.
-- ---------------------------------------------------------------------------

local function fillSolution(ctx)
    local n, N, k, reg = ctx.n, ctx.N, ctx.k, ctx.reg
    local size = n * n
    local sol = {}
    local regUsed, rowCnt, colCnt = {}, {}, {}
    for g = 1, #ctx.mats do regUsed[g] = {} end
    for r = 1, n do rowCnt[r] = {}; colCnt[r] = {} for v = 1, N do rowCnt[r][v] = 0; colCnt[r][v] = 0 end end
    local nodes = 0
    local order = {}
    for v = 1, N do order[v] = v end

    local function rec(i)
        if i > size then return true end
        nodes = nodes + 1
        if nodes > FILL_NODE_CAP then return false end
        local r, c, g = ctx.row[i], ctx.col[i], reg[i]
        local digits = {}
        for v = 1, N do digits[v] = order[v] end
        shuffle(digits)
        for _, v in ipairs(digits) do
            if not regUsed[g][v] and rowCnt[r][v] < k and colCnt[c][v] < k
                    and (c == 1 or sol[i - 1] ~= v) and (r == 1 or sol[i - n] ~= v) then
                sol[i] = v
                regUsed[g][v] = true
                rowCnt[r][v] = rowCnt[r][v] + 1
                colCnt[c][v] = colCnt[c][v] + 1
                if rec(i + 1) then return true end
                sol[i] = nil
                regUsed[g][v] = nil
                rowCnt[r][v] = rowCnt[r][v] - 1
                colCnt[c][v] = colCnt[c][v] - 1
                if nodes > FILL_NODE_CAP then return false end
            end
        end
        return false
    end

    if rec(1) then return sol end
    return nil
end

-- ---------------------------------------------------------------------------
-- Human solver (no trial, no guessing).
--
-- Tier 1:
--   * naked single: a cell with one candidate left;
--   * hidden single in a mat: a digit the mat still needs fits one cell only;
--   * line count: a row/column still needs digit v m times and exactly m of
--     its open cells can take v -- all of them are v (m = 1 is the hidden
--     single of the line).
--   Every placement removes its digit from the mat, the orthogonal
--   neighbours, and the rest of the line once the line has its n/N copies.
-- Tier 2 (only tried when tier 1 is stuck):
--   * mat-and-line counting: every mat crossing a line puts exactly one v
--     somewhere. If the mats that must put their v inside the line already
--     give all the copies the line still needs, the other mats cannot put v
--     there; if the mats that can put v inside the line are exactly as many
--     as the copies needed, each of them must, so v leaves their cells
--     outside the line;
--   * naked pair in a mat: two open cells with the same two candidates.
-- Returns solved, tier-1 step count, tier-2 step count, values.
-- ---------------------------------------------------------------------------

-- The solver is built once per context (its closures and working arrays),
-- then reset on each run: the dig runs it many times per grid, and fresh
-- tables and closures on every run cost more than the deductions themselves
-- (LuaJIT cannot compile a function that creates closures).
local function makeSolver(ctx)
    local n, N, k = ctx.n, ctx.N, ctx.k
    local size, reg, mats, lines, nbrs = ctx.size, ctx.reg, ctx.mats, ctx.lines, ctx.nbrs
    local row, col, allParts = ctx.row, ctx.col, ctx.parts
    local val, cand, cnt, lineCnt, regHas = {}, {}, {}, {}, {}
    for li = 1, 2 * n do lineCnt[li] = {} end
    local nmats = #mats
    for g = 1, nmats do regHas[g] = {} end
    local bad = false
    local open = size
    -- Cells whose candidates just dropped to one: the naked singles, found
    -- as they appear instead of by scanning the grid.
    local queue, qh, qt = {}, 1, 0

    local function elim(i, v)
        local key = (i - 1) * N + v
        if cand[key] then
            cand[key] = false
            local c = cnt[i] - 1
            cnt[i] = c
            if c == 0 then bad = true
            elseif c == 1 then qt = qt + 1; queue[qt] = i end
            return true
        end
        return false
    end

    local function place(i, v)
        local cur = val[i]
        if cur ~= 0 then
            if cur ~= v then bad = true end
            return
        end
        local base = (i - 1) * N
        if not cand[base + v] then bad = true; return end
        val[i] = v
        open = open - 1
        for w = 1, N do cand[base + w] = (w == v) end
        cnt[i] = 1
        local g = reg[i]
        if regHas[g][v] then bad = true; return end
        regHas[g][v] = true
        local m = mats[g]
        for a = 1, #m do
            local j = m[a]
            if j ~= i then
                local vj = val[j]
                if vj == v then bad = true elseif vj == 0 then elim(j, v) end
            end
        end
        local nb = nbrs[i]
        for a = 1, #nb do
            local j = nb[a]
            local vj = val[j]
            if vj == v then bad = true elseif vj == 0 then elim(j, v) end
        end
        for pass = 1, 2 do
            local li = pass == 1 and row[i] or (n + col[i])
            local t = lineCnt[li]
            local c = t[v] + 1
            t[v] = c
            if c > k then bad = true
            elseif c == k then
                local L = lines[li]
                for a = 1, n do
                    local j = L[a]
                    if val[j] == 0 then elim(j, v) end
                end
            end
        end
    end

    -- Cheapest rule first: each call returns as soon as one kind of rule
    -- made progress. The rules only ever remove candidates, so the order
    -- changes neither the grid where tier 1 gets stuck nor the tier-2 count.
    local function tier1()
        local prog = false
        while qh <= qt do
            local i = queue[qh]
            qh = qh + 1
            if val[i] == 0 and cnt[i] == 1 then
                local base = (i - 1) * N
                for v = 1, N do
                    if cand[base + v] then place(i, v); break end
                end
                prog = true
                if bad then return prog end
            end
        end
        if prog then return prog end
        for g = 1, nmats do
            local has = regHas[g]
            local m = mats[g]
            for v = 1, N do
                if not has[v] then
                    local only, c2 = nil, 0
                    for a = 1, #m do
                        local j = m[a]
                        if val[j] == 0 and cand[(j - 1) * N + v] then
                            c2 = c2 + 1; only = j
                        end
                    end
                    if c2 == 0 then bad = true; return prog end
                    if c2 == 1 then
                        place(only, v)
                        prog = true
                        if bad then return prog end
                    end
                end
            end
        end
        if prog then return prog end
        for li = 1, 2 * n do
            local t = lineCnt[li]
            local L = lines[li]
            for v = 1, N do
                local need = k - t[v]
                if need > 0 then
                    local c2 = 0
                    for a = 1, n do
                        local j = L[a]
                        if val[j] == 0 and cand[(j - 1) * N + v] then c2 = c2 + 1 end
                    end
                    if c2 < need then bad = true; return prog end
                    if c2 == need then
                        for a = 1, n do
                            local j = L[a]
                            if val[j] == 0 and cand[(j - 1) * N + v] then place(j, v) end
                        end
                        prog = true
                        if bad then return prog end
                    end
                end
            end
        end
        return prog
    end

    local function anyIn(cells, v)
        for a = 1, #cells do
            local j = cells[a]
            if val[j] == 0 and cand[(j - 1) * N + v] then return true end
        end
        return false
    end

    local function tier2()
        local prog = false
        for li = 1, 2 * n do
            local t = lineCnt[li]
            local parts = allParts[li]
            for v = 1, N do
                local need = k - t[v]
                if need > 0 then
                    local forced, possible = 0, 0
                    for a = 1, #parts do
                        local p = parts[a]
                        if not regHas[p.g][v] and anyIn(p.inside, v) then
                            possible = possible + 1
                            if not anyIn(p.outside, v) then forced = forced + 1 end
                        end
                    end
                    if possible < need or forced > need then bad = true; return prog end
                    if forced == need and possible > forced then
                        for a = 1, #parts do
                            local p = parts[a]
                            if not regHas[p.g][v] and anyIn(p.outside, v) then
                                local ins = p.inside
                                for b = 1, #ins do
                                    local j = ins[b]
                                    if val[j] == 0 and elim(j, v) then prog = true end
                                end
                            end
                        end
                    elseif possible == need then
                        for a = 1, #parts do
                            local p = parts[a]
                            if not regHas[p.g][v] and anyIn(p.inside, v) then
                                local outs = p.outside
                                for b = 1, #outs do
                                    local j = outs[b]
                                    if val[j] == 0 and elim(j, v) then prog = true end
                                end
                            end
                        end
                    end
                    if bad or prog then return prog end
                end
            end
        end
        -- Naked pair inside a mat.
        for g = 1, nmats do
            local cells = mats[g]
            for a = 1, #cells do
                local i = cells[a]
                if val[i] == 0 and cnt[i] == 2 then
                    for b = a + 1, #cells do
                        local j = cells[b]
                        if val[j] == 0 and cnt[j] == 2 then
                            local same = true
                            for v = 1, N do
                                if cand[(i - 1) * N + v] ~= cand[(j - 1) * N + v] then same = false; break end
                            end
                            if same then
                                for x = 1, #cells do
                                    local y = cells[x]
                                    if y ~= i and y ~= j and val[y] == 0 then
                                        for v = 1, N do
                                            if cand[(i - 1) * N + v] and elim(y, v) then prog = true end
                                        end
                                    end
                                end
                                if prog then return prog end
                            end
                        end
                    end
                end
            end
        end
        return prog
    end

    return function(givens, max_tier)
        bad = false
        open = size
        qh, qt = 1, 0
        for i = 1, size do
            val[i] = 0
            cnt[i] = N
        end
        for key = 1, size * N do cand[key] = true end
        for li = 1, 2 * n do
            local t = lineCnt[li]
            for v = 1, N do t[v] = 0 end
        end
        for g = 1, nmats do
            local h = regHas[g]
            for v = 1, N do h[v] = false end
        end
        for i = 1, size do
            local v = givens[i]
            if v and v ~= 0 then place(i, v) end
            if bad then return false, 0, 0 end
        end
        local t1, t2 = 0, 0
        while open > 0 do
            if tier1() then
                t1 = t1 + 1
            elseif max_tier >= 2 and tier2() then
                t2 = t2 + 1
            else
                break
            end
            if bad then return false, t1, t2 end
        end
        if bad or open > 0 then return false, t1, t2 end
        local out = {}
        for i = 1, size do out[i] = val[i] end
        return true, t1, t2, out
    end
end

local function solve(ctx, givens, max_tier)
    local run = ctx.solver
    if not run then
        run = makeSolver(ctx)
        ctx.solver = run
    end
    return run(givens, max_tier)
end

-- ---------------------------------------------------------------------------
-- Dig: remove givens in random order while the solver (up to `tier`) still
-- finishes. Returns the givens array.
--
-- Cells go in batches: a whole batch is removed at once and kept out when the
-- solver still finishes, otherwise it is split in two and each half tried in
-- turn, down to single cells. Most removals succeed early on, so this needs
-- far fewer solver runs than one per cell, and every given that stays was
-- still tried on its own.
-- ---------------------------------------------------------------------------

local DIG_BATCH = 8

local function dig(ctx, sol, tier, on_step)
    local size = ctx.size
    local givens = {}
    for i = 1, size do givens[i] = sol[i] end
    local order = {}
    for i = 1, size do order[i] = i end
    shuffle(order)

    local function try(lo, hi)
        for x = lo, hi do givens[order[x]] = 0 end
        if solve(ctx, givens, tier) then return end
        for x = lo, hi do givens[order[x]] = sol[order[x]] end
        if lo == hi then return end
        local mid = math.floor((lo + hi) / 2)
        try(lo, mid)
        try(mid + 1, hi)
    end

    for lo = 1, size, DIG_BATCH do
        try(lo, math.min(size, lo + DIG_BATCH - 1))
        if on_step then on_step(math.min(size, lo + DIG_BATCH - 1) / size) end
    end
    return givens
end

-- Builds one puzzle for `level`. Returns a table with n, N, reg, mats, sol,
-- givens, t1, t2 (solver step counts at the level's tier).
local function generatePuzzle(n, level, on_progress)
    local N = MAT_LEN[n]
    local spec = LEVELS[level] or LEVELS.medium
    local report = on_progress or function() end
    local min_t2 = spec.min_t2 and spec.min_t2[n] or 0
    local max_t2 = spec.max_t2 and spec.max_t2[n]

    -- A random layout fits the mix rule about half the time and a fill
    -- succeeds most of the time, so this loop ends after a few tries.
    local function newBase()
        while true do
            local reg, mats = makeLayout(n, N)
            if reg then
                local ctx = makeContext(n, N, reg, mats)
                local sol = fillSolution(ctx)
                if sol then return ctx, sol end
            end
        end
    end

    -- Gives back cells of the solution, in random order, until done() says
    -- the grid is right (or `limit` cells came back); a cell whose return
    -- would break accept(t2) stays empty.
    local function giveBack(ctx, sol, givens, t2, done, accept, limit)
        local empty = {}
        for i = 1, ctx.size do
            if givens[i] == 0 then empty[#empty + 1] = i end
        end
        shuffle(empty)
        local back = 0
        for _, i in ipairs(empty) do
            if done(givens, t2) or (limit and back >= limit) then break end
            givens[i] = sol[i]
            local ok, _, t2b = solve(ctx, givens, spec.tier)
            if ok and accept(t2b) then
                t2 = t2b
                back = back + 1
            else
                givens[i] = 0
            end
        end
        return t2
    end

    -- How far a grid's tier-2 work is from what the level wants.
    local function miss(t2)
        if t2 < min_t2 then return min_t2 - t2 end
        if max_t2 and t2 > max_t2 then return t2 - max_t2 end
        return 0
    end

    local attempts = spec.attempts[n]
    local best
    for attempt = 1, attempts do
        local ctx, sol = newBase()
        local base = (attempt - 1) / attempts
        local givens = dig(ctx, sol, spec.tier, function(f)
            report(base + f / attempts)
        end)
        if spec.floor then
            local want = math.floor(ctx.size * spec.floor)
            giveBack(ctx, sol, givens, 0, function(g)
                local k = 0
                for i = 1, ctx.size do if g[i] ~= 0 then k = k + 1 end end
                return k >= want
            end, function() return true end)
        end
        local _, t1, t2 = solve(ctx, givens, spec.tier)
        if max_t2 and t2 > max_t2 then
            -- Too much tier-2 work for Medium: give cells back until the
            -- grid is light enough, but still needs tier 2.
            giveBack(ctx, sol, givens, t2, function(_, cur) return cur <= max_t2 end,
                function(t) return t >= min_t2 end, math.floor(n / 2))
            _, t1, t2 = solve(ctx, givens, spec.tier)
        end
        local cand = { ctx = ctx, sol = sol, givens = givens, t1 = t1, t2 = t2 }
        if miss(t2) == 0 then best = cand; break end
        -- Closest miss; on a tie the grid with more tier-2 work, so Medium
        -- never settles for a grid that tier 1 alone can finish.
        local m, bm = miss(t2), best and miss(best.t2)
        if not best or m < bm or (m == bm and t2 > best.t2) then best = cand end
    end
    report(1)
    return {
        n = n, N = N, reg = best.ctx.reg, mats = best.ctx.mats,
        sol = best.sol, givens = best.givens, t1 = best.t1, t2 = best.t2,
    }
end

-- ---------------------------------------------------------------------------
-- TatamiBoard
-- ---------------------------------------------------------------------------

local TatamiBoard = {}
TatamiBoard.__index = TatamiBoard

local function grid(n, v)
    local g = {}
    for r = 1, n do
        g[r] = {}
        for c = 1, n do g[r][c] = v end
    end
    return g
end

local function validSize(n)
    return MAT_LEN[n] and n or DEFAULT_N
end

function TatamiBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        n          = validSize(opts.n or DEFAULT_N),
        difficulty = opts.difficulty or "medium",
        undo       = UndoStack:new{ max_size = 300 },
        selected   = nil,
        won        = false,
    }, self)
    obj.N = MAT_LEN[obj.n]
    if not opts.empty then obj:generate() end
    return obj
end

function TatamiBoard:_setPuzzle(p)
    local n = p.n
    self.n, self.N = n, p.N
    self.region   = grid(n, 0)
    self.solution = grid(n, 0)
    self.puzzle   = grid(n, 0)
    self.user     = grid(n, 0)
    self.notes    = {}
    self.wrong    = grid(n, false)
    for r = 1, n do
        self.notes[r] = {}
        for c = 1, n do
            local i = (r - 1) * n + c
            self.region[r][c]   = p.reg[i]
            self.solution[r][c] = p.sol[i]
            self.puzzle[r][c]   = p.givens[i] or 0
            self.notes[r][c]    = {}
        end
    end
    self.stats    = { t1 = p.t1, t2 = p.t2 }
    self.selected = nil
    self.won      = false
    self.revealed = false
    self.hints_used = 0
    self.undo:clear()
end

function TatamiBoard:generate(diff, on_progress)
    self.difficulty = diff or self.difficulty
    self.n = validSize(self.n)
    self:_setPuzzle(generatePuzzle(self.n, self.difficulty, on_progress))
end

function TatamiBoard:isGiven(r, c)
    return self.puzzle[r][c] ~= 0
end

function TatamiBoard:getValue(r, c)
    local g = self.puzzle[r][c]
    if g ~= 0 then return g end
    return self.user[r][c]
end

function TatamiBoard:countGivens()
    local k = 0
    for r = 1, self.n do
        for c = 1, self.n do
            if self.puzzle[r][c] ~= 0 then k = k + 1 end
        end
    end
    return k
end

local function copyNotes(t)
    local o = {}
    for d = 1, 9 do if t[d] then o[d] = true end end
    return o
end

function TatamiBoard:setSelection(r, c)
    self.selected = { r, c }
end

-- Writes digit v (0 clears). Returns true, or false + reason.
function TatamiBoard:setValue(r, c, v)
    if self.won then return false, "won" end
    if self:isGiven(r, c) then return false, "given" end
    if v < 0 or v > self.N then return false, "range" end
    local prev = self.user[r][c]
    if prev == v and v ~= 0 then return false, "same" end
    self.undo:push{ r = r, c = c, v = prev, notes = copyNotes(self.notes[r][c]) }
    self.user[r][c]  = v
    self.notes[r][c] = {}
    self.wrong[r][c] = false
    self:_checkWin()
    return true
end

function TatamiBoard:clearCell(r, c)
    if self.won then return false, "won" end
    if self:isGiven(r, c) then return false, "given" end
    if self.user[r][c] == 0 and next(self.notes[r][c]) == nil then return false, "empty" end
    return self:setValue(r, c, 0)
end

function TatamiBoard:toggleNote(r, c, d)
    if self.won then return false, "won" end
    if self:isGiven(r, c) then return false, "given" end
    if d < 1 or d > self.N then return false, "range" end
    if self.user[r][c] ~= 0 then return false, "filled" end
    self.undo:push{ r = r, c = c, v = 0, notes = copyNotes(self.notes[r][c]) }
    self.notes[r][c][d] = (not self.notes[r][c][d]) or nil
    return true
end

function TatamiBoard:canUndo()
    return self.undo:canUndo()
end

function TatamiBoard:undoMove()
    if self.won then return false end
    local e = self.undo:pop()
    if not e then return false end
    self.user[e.r][e.c]  = e.v or 0
    self.notes[e.r][e.c] = copyNotes(e.notes or {})
    self.wrong[e.r][e.c] = false
    self:_checkWin()
    return true
end

-- Marks the filled cells that differ from the solution. Returns the number
-- of wrong cells and of empty cells.
function TatamiBoard:check()
    local wrong, empty = 0, 0
    for r = 1, self.n do
        for c = 1, self.n do
            local v = self:getValue(r, c)
            local bad = v ~= 0 and v ~= self.solution[r][c]
            self.wrong[r][c] = bad
            if bad then wrong = wrong + 1 end
            if v == 0 then empty = empty + 1 end
        end
    end
    return wrong, empty
end

function TatamiBoard:countEmpty()
    local k = 0
    for r = 1, self.n do
        for c = 1, self.n do
            if self:getValue(r, c) == 0 then k = k + 1 end
        end
    end
    return k
end

-- The win check reads the rules, not the stored solution.
function TatamiBoard:isSolvedByRules()
    local n, N = self.n, self.N
    local k = n / N
    local regSeen = {}
    local rowCnt, colCnt = {}, {}
    for r = 1, n do
        rowCnt[r], colCnt[r] = {}, {}
        for v = 1, N do rowCnt[r][v] = 0; colCnt[r][v] = 0 end
    end
    for r = 1, n do
        for c = 1, n do
            local v = self:getValue(r, c)
            if v < 1 or v > N then return false end
            local g = self.region[r][c]
            regSeen[g] = regSeen[g] or {}
            if regSeen[g][v] then return false end
            regSeen[g][v] = true
            rowCnt[r][v] = rowCnt[r][v] + 1
            colCnt[c][v] = colCnt[c][v] + 1
            if c < n and self:getValue(r, c + 1) == v then return false end
            if r < n and self:getValue(r + 1, c) == v then return false end
        end
    end
    for i = 1, n do
        for v = 1, N do
            if rowCnt[i][v] ~= k or colCnt[i][v] ~= k then return false end
        end
    end
    return true
end

function TatamiBoard:_checkWin()
    self.won = self:isSolvedByRules()
    return self.won
end

function TatamiBoard:reveal()
    for r = 1, self.n do
        for c = 1, self.n do
            if not self:isGiven(r, c) then
                self.user[r][c]  = self.solution[r][c]
                self.notes[r][c] = {}
            end
            self.wrong[r][c] = false
        end
    end
    self.revealed = true
    self.undo:clear()
    self:_checkWin()
end

function TatamiBoard:clearUser()
    for r = 1, self.n do
        for c = 1, self.n do
            self.user[r][c]  = 0
            self.notes[r][c] = {}
            self.wrong[r][c] = false
        end
    end
    self.won, self.revealed = false, false
    self.undo:clear()
end

-- Thick border between (r,c) and its right / lower neighbour?
function TatamiBoard:wallRight(r, c)
    return c < self.n and self.region[r][c] ~= self.region[r][c + 1]
end

function TatamiBoard:wallBelow(r, c)
    return r < self.n and self.region[r][c] ~= self.region[r + 1][c]
end

Hint.install(TatamiBoard, {
    getUser     = function(b, r, c) return b.user[r][c] end,
    getSolution = function(b, r, c) return b.solution[r][c] end,
    isGiven     = function(b, r, c) return b:isGiven(r, c) end,
    setCell     = function(b, r, c, v) return b:setValue(r, c, v) end,
    clearCell   = function(b, r, c) return b:setValue(r, c, 0) end,
})

-- ---------------------------------------------------------------------------
-- Serialization
-- ---------------------------------------------------------------------------

local function flat(g, n)
    local out = {}
    for r = 1, n do
        for c = 1, n do out[#out + 1] = g[r][c] end
    end
    return out
end

function TatamiBoard:serialize()
    local n = self.n
    local notes = {}
    for r = 1, n do
        for c = 1, n do
            local s = ""
            for d = 1, self.N do
                if self.notes[r][c][d] then s = s .. d end
            end
            notes[#notes + 1] = s
        end
    end
    return {
        format     = FORMAT,
        n          = n,
        difficulty = self.difficulty,
        region     = flat(self.region, n),
        solution   = flat(self.solution, n),
        puzzle     = flat(self.puzzle, n),
        user       = flat(self.user, n),
        notes      = notes,
        won        = self.won,
        revealed   = self.revealed,
        hints_used = self.hints_used,
        undo       = self.undo:serialize(),
    }
end

-- Returns false (and leaves the board untouched) for anything that is not a
-- complete save of this format: no save, a 1.x domino save, a damaged one.
function TatamiBoard:load(data)
    if type(data) ~= "table" or data.format ~= FORMAT then return false end
    local n = data.n
    if not MAT_LEN[n] then return false end
    local N = MAT_LEN[n]
    local size = n * n
    for _, key in ipairs({ "region", "solution", "puzzle", "user" }) do
        if type(data[key]) ~= "table" or #data[key] ~= size then return false end
    end
    local p = { n = n, N = N, reg = {}, sol = {}, givens = {} }
    for i = 1, size do
        local g, s, q = data.region[i], data.solution[i], data.puzzle[i]
        if type(g) ~= "number" or type(s) ~= "number" or type(q) ~= "number" then return false end
        if s < 1 or s > N then return false end
        p.reg[i], p.sol[i], p.givens[i] = g, s, q
    end
    self:_setPuzzle(p)
    self.difficulty = data.difficulty or "medium"
    local i = 0
    for r = 1, n do
        for c = 1, n do
            i = i + 1
            local u = tonumber(data.user[i]) or 0
            if u < 0 or u > N or self:isGiven(r, c) then u = 0 end
            self.user[r][c] = u
            local s = type(data.notes) == "table" and data.notes[i]
            if type(s) == "string" then
                for ch in s:gmatch("%d") do
                    local d = tonumber(ch)
                    if d >= 1 and d <= N then self.notes[r][c][d] = true end
                end
            end
        end
    end
    self.stats = nil
    self.revealed   = data.revealed and true or false
    self.hints_used = tonumber(data.hints_used) or 0
    self.undo:load(data.undo)
    self:_checkWin()
    return true
end

TatamiBoard.SIZES     = SIZES
TatamiBoard.MAT_LEN   = MAT_LEN
TatamiBoard.DEFAULT_N = DEFAULT_N
TatamiBoard.FORMAT    = FORMAT

-- For the specs and measurement scripts.
TatamiBoard._solve       = solve
TatamiBoard._makeContext = makeContext
TatamiBoard._generate    = generatePuzzle

return TatamiBoard
