-- Difficulty guarantees for Tatami: every size x level builds a valid,
-- unique puzzle (checked by an independent brute force) quickly, the game's
-- solver finishes it within tier 2 with no trial, Easy needs tier 1 only,
-- Medium and Hard need tier 2, Hard more tier-2 steps than Medium and fewer
-- givens, and a seed gives the same puzzle without reading the clock.
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

describe("Tatami difficulty", function()
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
end)
