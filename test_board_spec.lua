local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

-- Independent brute-force solution counter: plain backtracking on the three
-- rules, no shared code with the generator's solver.
local function countSolutions(p, limit)
    local n, N = p.n, p.N
    local k = n // N
    local val = {}
    for i = 1, n * n do val[i] = p.givens[i] end
    local function ok(i, v)
        local r, c = (i - 1) // n + 1, (i - 1) % n + 1
        for _, j in ipairs(p.mats[p.reg[i]]) do
            if j ~= i and val[j] == v then return false end
        end
        if c > 1 and val[i - 1] == v then return false end
        if c < n and val[i + 1] == v then return false end
        if r > 1 and val[i - n] == v then return false end
        if r < n and val[i + n] == v then return false end
        local rc, cc = 0, 0
        for x = 1, n do
            if val[(r - 1) * n + x] == v then rc = rc + 1 end
            if val[(x - 1) * n + c] == v then cc = cc + 1 end
        end
        return rc < k and cc < k
    end
    for i = 1, n * n do
        local v = val[i]
        if v ~= 0 then
            val[i] = 0
            if not ok(i, v) then return 0 end
            val[i] = v
        end
    end
    local found = 0
    local function rec(i)
        if found >= limit then return end
        while i <= n * n and val[i] ~= 0 do i = i + 1 end
        if i > n * n then found = found + 1; return end
        for v = 1, N do
            if ok(i, v) then
                val[i] = v
                rec(i + 1)
                val[i] = 0
            end
        end
    end
    rec(1)
    return found
end

local function countGivens(p)
    local k = 0
    for i = 1, p.n * p.n do if p.givens[i] ~= 0 then k = k + 1 end end
    return k
end

describe("Tatami generator", function()
    local Board
    setup(function() Board = require("board") end)

    local SEEDS = 10
    local cache = {}
    local function gen(n, level, seed)
        local key = n .. level .. seed
        if not cache[key] then
            math.randomseed(seed)
            cache[key] = Board._generate(n, level)
        end
        return cache[key]
    end

    for _, n in ipairs({ 6, 8, 9 }) do
        for _, level in ipairs({ "easy", "medium", "hard" }) do
            it(("builds valid, unique, no-trial %dx%d %s grids"):format(n, n, level), function()
                for seed = 1, SEEDS do
                    local p = gen(n, level, seed)
                    local N = Board.MAT_LEN[n]
                    assert.are.equal(N, p.N)
                    -- Straight mats of length N tiling the grid.
                    local seen = {}
                    for g, cells in ipairs(p.mats) do
                        assert.are.equal(N, #cells)
                        local step = cells[2] - cells[1]
                        assert.is_true(step == 1 or step == n)
                        for a = 1, N do
                            local i = cells[a]
                            assert.is_nil(seen[i])
                            seen[i] = true
                            assert.are.equal(g, p.reg[i])
                            if a > 1 then assert.are.equal(step, i - cells[a - 1]) end
                            if step == 1 then
                                assert.are.equal((cells[1] - 1) // n, (i - 1) // n)
                            end
                        end
                    end
                    for i = 1, n * n do assert.is_true(seen[i]) end
                    -- Givens come from the solution.
                    for i = 1, n * n do
                        local v = p.givens[i]
                        assert.is_true(v == 0 or v == p.sol[i])
                    end
                    -- Exactly one solution (brute force), and it is the
                    -- stored one.
                    assert.are.equal(1, countSolutions(p, 2))
                    local ctx = Board._makeContext(n, N, p.reg, p.mats)
                    local ok1 = Board._solve(ctx, p.givens, 1)
                    local ok2, _, t2, vals = Board._solve(ctx, p.givens, 2)
                    assert.is_true(ok2)
                    for i = 1, n * n do assert.are.equal(p.sol[i], vals[i]) end
                    if level == "easy" then
                        assert.is_true(ok1)
                    else
                        -- Needs tier 2, never trial.
                        assert.is_false(ok1)
                        assert.is_true(t2 >= 1)
                    end
                end
            end)
        end

        it(("levels differ on %dx%d"):format(n, n), function()
            local sum = { easy = { g = 0, t2 = 0 }, medium = { g = 0, t2 = 0 }, hard = { g = 0, t2 = 0 } }
            for _, level in ipairs({ "easy", "medium", "hard" }) do
                for seed = 1, SEEDS do
                    local p = gen(n, level, seed)
                    sum[level].g  = sum[level].g + countGivens(p)
                    sum[level].t2 = sum[level].t2 + p.t2
                end
            end
            assert.are.equal(0, sum.easy.t2)
            assert.is_true(sum.medium.t2 > 0)
            assert.is_true(sum.hard.t2 > sum.medium.t2)
            assert.is_true(sum.easy.g >= sum.medium.g)
            assert.is_true(sum.medium.g >= sum.hard.g)
        end)
    end

    it("gives the same puzzle for the same seed", function()
        for _, n in ipairs({ 6, 8, 9 }) do
            for _, level in ipairs({ "easy", "hard" }) do
                math.randomseed(4242)
                local a = Board:new{ n = n, difficulty = level }
                math.randomseed(4242)
                local b = Board:new{ n = n, difficulty = level }
                assert.are.same(a:serialize(), b:serialize())
            end
        end
    end)

    it("never reads the clock", function()
        local clock, time = os.clock, os.time
        os.clock = function() error("generator read os.clock") end
        os.time  = function() error("generator read os.time") end
        local ok, err = pcall(function()
            for _, n in ipairs({ 6, 8, 9 }) do
                math.randomseed(77)
                Board:new{ n = n, difficulty = "hard" }
            end
        end)
        os.clock, os.time = clock, time
        assert.is_true(ok, err)
    end)

    it("generates within a generous time bound", function()
        -- Busted runs plain Lua, several times slower than LuaJIT; the real
        -- targets (<= ~40 ms on the Mac under LuaJIT) are measured apart.
        local worst = 0
        for _, n in ipairs({ 6, 8, 9 }) do
            for _, level in ipairs({ "medium", "hard" }) do
                for seed = 100, 104 do
                    math.randomseed(seed)
                    local t0 = os.clock()
                    Board._generate(n, level)
                    worst = math.max(worst, os.clock() - t0)
                end
            end
        end
        assert.is_true(worst < 1.5, ("worst generation %.3f s"):format(worst))
    end)

    it("reports progress up to 1", function()
        math.randomseed(5)
        local last = 0
        Board:new{ n = 8, empty = true }:generate("hard", function(f)
            assert.is_true(f >= 0 and f <= 1)
            last = f
        end)
        assert.are.equal(1, last)
    end)
end)

describe("Tatami board", function()
    local Board
    setup(function() Board = require("board") end)

    local function newBoard(n, level, seed)
        math.randomseed(seed or 3)
        return Board:new{ n = n or 6, difficulty = level or "medium" }
    end

    local function firstOpen(b)
        for r = 1, b.n do
            for c = 1, b.n do
                if not b:isGiven(r, c) then return r, c end
            end
        end
    end

    local function fillSolution(b)
        for r = 1, b.n do
            for c = 1, b.n do
                if not b:isGiven(r, c) then b:setValue(r, c, b.solution[r][c]) end
            end
        end
    end

    it("defaults to 6x6 with digits 1-3, and maps unknown sizes to it", function()
        local b = Board:new{ empty = true }
        assert.are.equal(6, b.n)
        assert.are.equal(3, b.N)
        local old = Board:new{ n = 4, empty = true }  -- 1.x had 4x4
        assert.are.equal(6, old.n)
        assert.are.equal(4, Board:new{ n = 8, empty = true }.N)
        assert.are.equal(3, Board:new{ n = 9, empty = true }.N)
    end)

    it("refuses to edit a given cell", function()
        local b = newBoard()
        for r = 1, b.n do
            for c = 1, b.n do
                if b:isGiven(r, c) then
                    local ok, err = b:setValue(r, c, 1)
                    assert.is_false(ok)
                    assert.are.equal("given", err)
                    return
                end
            end
        end
        error("no given cell")
    end)

    it("wins by the rules once the grid is correctly filled", function()
        local b = newBoard(8, "easy")
        local sol = {}
        for r = 1, b.n do sol[r] = {} for c = 1, b.n do sol[r][c] = b.solution[r][c] end end
        -- The check reads the rules, not the stored answer.
        for r = 1, b.n do for c = 1, b.n do b.solution[r][c] = 0 end end
        for r = 1, b.n do
            for c = 1, b.n do
                if not b:isGiven(r, c) then b:setValue(r, c, sol[r][c]) end
            end
        end
        assert.is_true(b.won)
    end)

    it("does not win with a rule broken", function()
        local b = newBoard(6, "easy")
        fillSolution(b)
        assert.is_true(b.won)
        b.won = false
        local r, c = firstOpen(b)
        local wrong = b.solution[r][c] % b.N + 1
        b.user[r][c] = wrong
        assert.is_false(b:isSolvedByRules())
    end)

    it("is not won while cells are empty", function()
        local b = newBoard(9, "hard")
        assert.is_false(b.won)
        assert.is_false(b:isSolvedByRules())
    end)

    it("toggles notes and undoes moves", function()
        local b = newBoard()
        local r, c = firstOpen(b)
        assert.is_true(b:toggleNote(r, c, 2))
        assert.is_true(b.notes[r][c][2])
        assert.is_true(b:setValue(r, c, 1))
        assert.are.equal(1, b.user[r][c])
        assert.is_nil(next(b.notes[r][c]))
        assert.is_true(b:undoMove())
        assert.are.equal(0, b.user[r][c])
        assert.is_true(b.notes[r][c][2])
        assert.is_true(b:undoMove())
        assert.is_nil(b.notes[r][c][2])
        assert.is_false(b:undoMove())
    end)

    it("marks wrong cells on check", function()
        local b = newBoard()
        local r, c = firstOpen(b)
        b:setValue(r, c, b.solution[r][c] % b.N + 1)
        local wrong, empty = b:check()
        assert.are.equal(1, wrong)
        assert.is_true(b.wrong[r][c])
        assert.is_true(empty > 0)
    end)

    it("gives a hint from the solution", function()
        local b = newBoard()
        local step = b:findHint()
        assert.are.equal("fill", step.kind)
        assert.are.equal(b.solution[step.r][step.c], step.value)
        assert.is_true(b:applyHint(step))
        assert.are.equal(step.value, b.user[step.r][step.c])
    end)

    it("reveals the solution", function()
        local b = newBoard(8, "hard")
        b:reveal()
        assert.is_true(b.won)
        assert.are.equal(0, b:countEmpty())
    end)

    it("round-trips a save", function()
        local b = newBoard(9, "medium")
        local r, c = firstOpen(b)
        b:setValue(r, c, 2)
        local r2, c2
        for rr = b.n, 1, -1 do
            for cc = b.n, 1, -1 do
                if not b:isGiven(rr, cc) and not r2 then r2, c2 = rr, cc end
            end
        end
        b:toggleNote(r2, c2, 1)
        b:toggleNote(r2, c2, 3)
        local data = b:serialize()
        local b2 = Board:new{ empty = true }
        assert.is_true(b2:load(data))
        assert.are.same(data, b2:serialize())
        assert.are.equal(9, b2.n)
        assert.are.equal(3, b2.N)
        assert.are.equal(2, b2.user[r][c])
        assert.is_true(b2.notes[r2][c2][1] and b2.notes[r2][c2][3])
        assert.is_true(b2:undoMove())
        assert.is_nil(b2.notes[r2][c2][3])
    end)

    it("restores a won game as won", function()
        local b = newBoard(6, "easy")
        fillSolution(b)
        local b2 = Board:new{ empty = true }
        assert.is_true(b2:load(b:serialize()))
        assert.is_true(b2.won)
    end)

    it("ignores old 1.x domino saves and damaged saves", function()
        local b = Board:new{ empty = true }
        -- What 1.x wrote: a 4x4 domino tiling, cells as r*100+c partners.
        local old = {
            n = 4, difficulty = "medium", won = false,
            sol   = { 102, 101, 104, 103, 202, 201, 204, 203, 302, 301, 304, 303, 402, 401, 404, 403 },
            given = { 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1 },
            user  = { 102, 101, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 404, 403 },
        }
        assert.is_false(b:load(old))
        old.n = 6
        assert.is_false(b:load(old))
        assert.is_false(b:load(nil))
        assert.is_false(b:load("garbage"))
        local good = newBoard():serialize()
        good.solution[3] = nil
        assert.is_false(b:load(good))
        local bad_n = newBoard():serialize()
        bad_n.n = 7
        assert.is_false(b:load(bad_n))
    end)
end)
