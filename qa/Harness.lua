-- DragonUI_NewEra/qa/Harness.lua
-- In-game QA harness (owner: QA/Harness Engineer). See CONTRACTS.md §5.
--
-- Provides:
--   * a lightweight session error capture (wraps geterrorhandler) into NE.qa.errors
--   * slash /dnetest: iterate NE.qa.modules, exercise each module's frame/open/close
--     under pcall, tally PASS/FAIL, and print captured session errors.
--
-- 3.3.5a rules obeyed: no SetShown; DEFAULT_CHAT_FRAME:AddMessage for output;
-- fully defensive (empty registry PASSES with a clear message).

local NE = DragonUI_NewEra
if not NE then return end          -- bootstrap bailed (no DragonUI) — nothing to test against.

-- The harness must work even if the base addon is disabled, so we do NOT early-return
-- on NE.disabled here; bootstrap still created NE.qa. Guard the registry instead.
NE.qa = NE.qa or { modules = {} }
NE.qa.modules = NE.qa.modules or {}

-- ---------------------------------------------------------------------------
-- Color helpers + output. All output goes through one printer so /dnetest is quiet
-- unless invoked.
-- ---------------------------------------------------------------------------
local C = {
    head  = "|cff1784d1",   -- DragonUI blue
    pass  = "|cff55ff55",
    fail  = "|cffff5555",
    warn  = "|cffffcc00",
    dim   = "|cff888888",
    r     = "|r",
}

local function out(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

-- ---------------------------------------------------------------------------
-- Session error capture. We wrap the CURRENT error handler (so we cooperate with
-- BugSack / Blizzard / anyone who set one before us) and record the last N errors.
-- ---------------------------------------------------------------------------
local MAX_ERRORS = 50
NE.qa.errors = NE.qa.errors or {}

if not NE.qa._errorHookInstalled then
    NE.qa._errorHookInstalled = true
    local prev = geterrorhandler and geterrorhandler() or nil
    local function capture(err, ...)
        -- Record defensively; never let our own bookkeeping throw.
        local ok = pcall(function()
            local list = NE.qa.errors
            list[#list + 1] = {
                msg  = tostring(err),
                when = (GetTime and GetTime()) or 0,
            }
            -- Trim to the last MAX_ERRORS (drop oldest).
            while #list > MAX_ERRORS do
                table.remove(list, 1)
            end
        end)
        -- Always chain to the previous handler so nothing is swallowed.
        if prev then
            return prev(err, ...)
        end
        return ok
    end
    if seterrorhandler then
        seterrorhandler(capture)
    end
end

-- ---------------------------------------------------------------------------
-- /dnetest — exercise every registered QA module.
-- ---------------------------------------------------------------------------
local function runTests()
    out(C.head .. "===== DragonUI_NewEra /dnetest =====" .. C.r)

    local mods = NE.qa.modules
    local n = (type(mods) == "table") and #mods or 0

    if n == 0 then
        out(C.warn .. "no modules registered yet" .. C.r ..
            C.dim .. " (panels append to NE.qa.modules as they load)" .. C.r)
        out(C.pass .. "PASS" .. C.r .. C.dim .. "  0/0 modules" .. C.r)
        -- Still report session errors below; fall through.
    else
        local pass, fail = 0, 0

        for i = 1, n do
            local m = mods[i]
            local name = (type(m) == "table" and m.name) or ("module#" .. i)
            local lineOK = true
            local notes = {}

            if type(m) ~= "table" then
                out(C.fail .. "[FAIL] " .. C.r .. tostring(name) ..
                    C.dim .. "  entry is not a table" .. C.r)
                fail = fail + 1
            else
                -- 1) frame existence
                local hasFrame = (m.frame ~= nil)
                if hasFrame then
                    notes[#notes + 1] = C.dim .. "frame:ok" .. C.r
                else
                    notes[#notes + 1] = C.warn .. "frame:nil" .. C.r
                end

                -- 2) open() under pcall
                if type(m.open) == "function" then
                    local ok, err = pcall(m.open)
                    if ok then
                        notes[#notes + 1] = C.dim .. "open:ok" .. C.r
                    else
                        lineOK = false
                        notes[#notes + 1] = C.fail .. "open:ERR(" .. tostring(err) .. ")" .. C.r
                    end
                else
                    notes[#notes + 1] = C.dim .. "open:--" .. C.r
                end

                -- 3) close() under pcall
                if type(m.close) == "function" then
                    local ok, err = pcall(m.close)
                    if ok then
                        notes[#notes + 1] = C.dim .. "close:ok" .. C.r
                    else
                        lineOK = false
                        notes[#notes + 1] = C.fail .. "close:ERR(" .. tostring(err) .. ")" .. C.r
                    end
                else
                    notes[#notes + 1] = C.dim .. "close:--" .. C.r
                end

                -- A module with no frame and no callables still "passes" structurally,
                -- but we flag a missing frame as a soft warning (not a FAIL on its own).
                local tag = lineOK and (C.pass .. "[PASS] " .. C.r) or (C.fail .. "[FAIL] " .. C.r)
                out(tag .. tostring(name) .. C.dim .. "  " .. C.r .. table.concat(notes, " "))
                if lineOK then pass = pass + 1 else fail = fail + 1 end
            end
        end

        local banner = (fail == 0) and (C.pass .. "PASS" .. C.r) or (C.fail .. "FAIL" .. C.r)
        out(banner .. C.dim .. "  " .. C.r ..
            C.pass .. tostring(pass) .. " pass" .. C.r .. C.dim .. " / " .. C.r ..
            (fail > 0 and (C.fail .. tostring(fail) .. " fail" .. C.r)
                       or (C.dim .. "0 fail" .. C.r)) ..
            C.dim .. "  (" .. tostring(n) .. " modules)" .. C.r)
    end

    -- ---- captured session errors ----
    local errs = NE.qa.errors or {}
    local en = #errs
    if en == 0 then
        out(C.dim .. "session Lua errors captured: 0" .. C.r)
    else
        out(C.warn .. "session Lua errors captured: " .. tostring(en) .. C.r ..
            C.dim .. " (showing last " .. tostring(math.min(en, 5)) .. ")" .. C.r)
        local first = math.max(1, en - 4)
        for i = first, en do
            local e = errs[i]
            out(C.fail .. "  • " .. C.r .. C.dim .. tostring(e and e.msg or "?") .. C.r)
        end
    end

    out(C.head .. "====================================" .. C.r)
end

SLASH_DNETEST1 = "/dnetest"
SlashCmdList = SlashCmdList or {}
SlashCmdList["DNETEST"] = function()
    -- Run inside pcall so a harness bug never spams the error frame mid-report.
    local ok, err = pcall(runTests)
    if not ok then
        out(C.fail .. "/dnetest harness error: " .. C.r .. tostring(err))
    end
end
