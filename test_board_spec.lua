local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("Tatami generator", function()
    local Board
    setup(function() Board = require("board") end)

    -- Difficulty guarantees live in test_difficulty_spec.lua.

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
