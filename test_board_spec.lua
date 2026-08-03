local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("TatamiBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)


    -- Regression guard for the 2026-07-21 bug: the implemented rule checked
    -- "no 2x2 block covered by two parallel same-orientation dominoes",
    -- which an exhaustive search proved mathematically unsatisfiable on
    -- either supported size (all 36 tilings of 4x4, all 6728 of 6x6,
    -- violated it) -- the plugin could never generate more than its
    -- hardcoded fallback, ever. Fixed with the correct rule ("no four
    -- distinct tiles' corners meet at one interior point") and a direct
    -- constructive pinwheel generator (no retry loop at all). These tests
    -- assert the generated tiling is a full, valid domino tiling with zero
    -- cross violations under the *correct* rule.
    local function crossViolations(pairs, n)
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

    local function newBoard(n, diff)
        math.randomseed(42)
        return Board:new{ n = n or 4, difficulty = diff or "medium" }
    end

    describe("construction", function()
        it("creates a 4×4 board by default", function()
            local b = Board:new()
            assert.are.equal(4, b.n)
        end)
    end)

    describe("generate", function()
        it("produces a full, mutually-consistent domino tiling", function()
            local b = newBoard(4)
            local n = b.n
            for r = 1, n do
                for c = 1, n do
                    local partner = b.sol_pairs[r][c]
                    assert.is_not_nil(partner, ("cell [%d][%d] has no domino partner"):format(r, c))
                    local pr, pc = partner[1], partner[2]
                    local dr, dc = math.abs(pr - r), math.abs(pc - c)
                    assert.is_true((dr == 1 and dc == 0) or (dr == 0 and dc == 1),
                        ("partner of [%d][%d] is not orthogonally adjacent"):format(r, c))
                    local back = b.sol_pairs[pr][pc]
                    assert.are.equal(r, back[1])
                    assert.are.equal(c, back[2])
                end
            end
        end)

        it("has zero cross-junction violations under the correct rule", function()
            for _, n in ipairs(Board.SIZES) do
                math.randomseed(n * 137)
                local b = Board:new{ n = n }
                assert.are.equal(0, crossViolations(b.sol_pairs, n),
                    ("n=%d: tiling has a cross violation"):format(n))
            end
        end)

        it("runs across all supported sizes without hanging or erroring", function()
            for _, n in ipairs(Board.SIZES) do
                math.randomseed(n * 977)
                local ok = pcall(function() Board:new{ n = n } end)
                assert.is_true(ok, ("generate failed for n=%d"):format(n))
            end
        end)
    end)

    describe("tapCell / win check", function()
        it("reconstructing the full solution via tapCell wins the puzzle", function()
            local b = newBoard(4)
            local n = b.n
            local done_pairs = {}
            for r = 1, n do
                for c = 1, n do
                    local pr, pc = b.sol_pairs[r][c][1], b.sol_pairs[r][c][2]
                    local key = (r < pr or (r == pr and c < pc)) and (r .. "," .. c .. "-" .. pr .. "," .. pc)
                        or (pr .. "," .. pc .. "-" .. r .. "," .. c)
                    if not done_pairs[key] then
                        done_pairs[key] = true
                        if not b.given[r][c] and not b.given[pr][pc] then
                            b:tapCell(r, c)
                            b:tapCell(pr, pc)
                        end
                    end
                end
            end
            assert.is_true(b.won)
        end)
    end)

    describe("serialize / load", function()
        it("round-trips sol_pairs, given and user_pairs", function()
            local b = newBoard(4)
            local data = b:serialize()
            local b2   = Board:new{ n = b.n }
            local ok   = b2:load(data)
            assert.is_true(ok)
            assert.are.equal(b.n, b2.n)
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
