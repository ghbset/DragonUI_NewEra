-- DragonUI_NewEra/modules/talents/Loadouts.lua — talent BUILD storage + import/export (DATA LAYER).
--
-- Issue #3 (last item): saved talent profiles + export/import builds. This is Phase 1 — the data
-- layer only (no UI yet): the saved-build store, a Talented-compatible string codec, and the
-- custom-talent compatibility GUARD. The editor/UI hooks come in a later phase.
--
-- INTEROP (per user direction): be share-compatible with the *Talented* addon (and the WoWhead /
-- wotlkdb / truewow / evowow talent calculators) so players migrating from those can paste builds
-- straight in. We replicate Talented's exact codec:
--   * 2 talent ranks packed per char as  v = r1*6 + r2 + 1  (indexed into an alphabet),
--   * tabs separated by a STOP char, trailing zeros trimmed,
--   * first char encodes the class.
-- Two alphabets: INTERNAL (Talented's on-disk code) and URL (its ?talent# share links). We read
-- both, plus the plain-digit calculator format (0-5 digits, trees split by '-').
-- Talented & the calculators IGNORE everything after a ':' in a code, so we hide our own metadata
-- there — a tree FINGERPRINT (+ optional server label). That keeps our exports importable by
-- Talented while letting us detect layout mismatches on import.
--
-- CUSTOM-TALENT GUARD (per user direction): a talent string only means anything against the exact
-- tree it was built for. On a server with custom talents, importing a standard build misplaces
-- points. So: a "Server uses custom talents" flag (NE.db.talentCustom) + a fingerprint of the live
-- tree shape. T.LO_ImportString returns a compat verdict the UI turns into a confirm dialog:
--   tag fp == local fp           -> clean
--   custom flag OFF + no tag     -> clean   (standard build onto a standard server)
--   otherwise                    -> warn    (different/standard layout onto custom trees)
-- Either way the build is validated/clamped against the live tree before it can be applied.

local NE = DragonUI_NewEra
local T = NE.talents or {}
NE.talents = T

local MAX_POINTS = 71   -- WotLK level-80 talent cap

-- Talented codec alphabets (verbatim from Talented/Talented.lua so codes round-trip byte-for-byte).
local MAP_INTERNAL = "012345abcdefABCDEFmnopqrMNOPQRtuvwxy*"   -- its on-disk template.code alphabet
local MAP_URL      = "0zMcmVokRsaqbdrfwihuGINALpTjnyxtgevE"    -- its ?talent# share-link alphabet
local STOP         = "Z"
-- Class order Talented uses for the leading class char (index -> alphabet position (i-1)*3+1).
local CLASSMAP = {
  "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE",
  "SHAMAN", "WARLOCK", "WARRIOR", "DEATHKNIGHT",
}
local META_SEP = ":"   -- everything after this is our metadata (Talented/calculators ignore it)

local floor = math.floor

-- ----------------------------------------------------------------------------
-- Live tree structure (own class). tier/column/maxRank are queryable regardless of points spent.
-- struct = { class, tabs = { [tab] = { count, name, talents = { [idx] = {tier,col,maxRank,name} } } } }
-- ----------------------------------------------------------------------------
local function buildStruct()
  if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo and UnitClass) then return nil end
  local _, classFile = UnitClass("player")
  classFile = classFile or "UNKNOWN"
  local group = (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
  local s = { class = classFile, tabs = {} }
  local numTabs = GetNumTalentTabs(false, false) or 0
  for tab = 1, numTabs do
    local tabName = GetTalentTabInfo and GetTalentTabInfo(tab, false, false, group)
    local n = GetNumTalents(tab, false, false) or 0
    local td = { count = n, name = tabName, talents = {} }
    for i = 1, n do
      local name, _, tier, column, _, maxRank = GetTalentInfo(tab, i, false, false, group)
      td.talents[i] = { tier = tier or 0, col = column or 0, maxRank = maxRank or 0, name = name or "" }
    end
    s.tabs[tab] = td
  end
  return s
end

-- The live spec's current spent ranks, as ranks[tab][idx] = rank.
local function currentRanks()
  local ranks = {}
  if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return ranks end
  local group = (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
  for tab = 1, (GetNumTalentTabs(false, false) or 0) do
    local t = {}
    for i = 1, (GetNumTalents(tab, false, false) or 0) do
      local _, _, _, _, rank = GetTalentInfo(tab, i, false, false, group)
      t[i] = rank or 0
    end
    ranks[tab] = t
  end
  return ranks
end
T.LO_ReadCurrentRanks = currentRanks

-- ----------------------------------------------------------------------------
-- Fingerprint — a short hash of the live tree SHAPE (per-tab counts + each talent's
-- tier/column/maxRank/name). This is what determines whether a foreign build's points line up.
-- A talent reworked in place (same slot, different effect/name) changes the hash, so it's caught.
-- ----------------------------------------------------------------------------
local function hashString(str)
  -- djb2 (xor variant), kept inside Lua-number-safe range; returned as 8 hex chars.
  local h = 5381
  for i = 1, #str do
    h = (h * 33 + string.byte(str, i)) % 4294967296   -- mod 2^32 each step (no overflow)
  end
  return string.format("%08x", h)
end

local function fingerprintOf(struct)
  if not struct then return nil end
  local parts = { struct.class }
  for tab = 1, #struct.tabs do
    local td = struct.tabs[tab]
    parts[#parts + 1] = "T" .. tab .. "n" .. td.count
    for i = 1, td.count do
      local t = td.talents[i]
      parts[#parts + 1] = t.tier .. "," .. t.col .. "," .. t.maxRank .. "," .. t.name
    end
  end
  return hashString(table.concat(parts, "|"))
end

function T.LO_LocalFingerprint()
  return fingerprintOf(buildStruct())
end

-- ----------------------------------------------------------------------------
-- Custom-talent server flag (cog toggle in a later phase). Account-wide in NE.db.
-- ----------------------------------------------------------------------------
function T.LO_IsCustomServer()
  return (NE.db and NE.db.talentCustom) and true or false
end
function T.LO_SetCustomServer(v)
  if NE.db then NE.db.talentCustom = v and true or false end
end
-- Friendly label shown in the mismatch warning + written into our exports.
function T.LO_ServerLabel()
  if NE.db and type(NE.db.talentServerLabel) == "string" and NE.db.talentServerLabel ~= "" then
    return NE.db.talentServerLabel
  end
  return (GetRealmName and GetRealmName()) or "this server"
end

-- ----------------------------------------------------------------------------
-- Codec — port of Talented's StringToTemplate / TemplateToString (both alphabets), plus the
-- plain-digit calculator format. Operates against the LIVE tree (counts from `struct`).
-- ----------------------------------------------------------------------------
local function classChar(map, class)
  for i, c in ipairs(CLASSMAP) do
    if c == class then local p = (i - 1) * 3 + 1; return map:sub(p, p) end
  end
  return nil
end
local function classFromChar(map, ch)
  local p = map:find(ch, nil, true)
  if not p then return nil end
  local i = floor((p - 1) / 3) + 1
  return CLASSMAP[i]
end

local function rtrim(s, c)
  local l = #s
  while l >= 1 and s:sub(l, l) == c do l = l - 1 end
  return s:sub(1, l)
end

-- Encode ranks (ranks[tab][idx]) -> a packed Talented code, using `map`.
local function encodePacked(ranks, struct, map)
  local ccode = classChar(map, struct.class)
  if not ccode then return nil end
  local zero = map:sub(1, 1)
  local code = ""
  for tab = 1, #struct.tabs do
    local count = struct.tabs[tab].count
    local r = ranks[tab] or {}
    local idx = 1
    while idx <= count do
      local r1 = r[idx] or 0
      local r2 = (idx + 1 <= count) and (r[idx + 1] or 0) or 0
      local v = r1 * 6 + r2 + 1
      code = code .. map:sub(v, v)
      idx = idx + 2
    end
    local ncode = rtrim(code, zero)        -- trim trailing zero-chars across the running code
    if ncode ~= code then code = ncode .. STOP end
  end
  return ccode .. rtrim(code, STOP)
end

-- Decode a packed Talented code -> ranks[tab][idx], class. Returns nil on a bad char.
local function decodePacked(code, struct, map)
  local class = classFromChar(map, code:sub(1, 1))
  if not class then return nil end
  local ranks, tab = {}, 1
  local count = struct.tabs[tab] and struct.tabs[tab].count or 0
  ranks[tab] = {}
  local t = ranks[tab]
  for i = 2, #code do
    local ch = code:sub(i, i)
    if ch == STOP then
      if #t >= count then tab = tab + 1; ranks[tab] = {}; t = ranks[tab]; count = struct.tabs[tab] and struct.tabs[tab].count or 0 end
      tab = tab + 1; ranks[tab] = {}; t = ranks[tab]; count = struct.tabs[tab] and struct.tabs[tab].count or 0
    else
      local v = map:find(ch, nil, true)
      if not v then return nil end
      v = v - 1
      local b = v % 6
      local a = (v - b) / 6
      if #t >= count then tab = tab + 1; ranks[tab] = {}; t = ranks[tab]; count = struct.tabs[tab] and struct.tabs[tab].count or 0 end
      t[#t + 1] = a
      if #t < count then t[#t + 1] = b end
    end
  end
  -- zero-fill every tab to its full count
  for tb = 1, #struct.tabs do
    local r = ranks[tb] or {}
    ranks[tb] = r
    for i = 1, struct.tabs[tb].count do r[i] = r[i] or 0 end
  end
  return ranks, class
end

-- Plain-digit calculator format: "0123-4567-..." (one digit per talent, '-' between trees, no class).
local function decodeDigits(code, struct)
  if not code:match("^[0-5%-]+$") then return nil end
  local segs = {}
  for seg in (code .. "-"):gmatch("([^%-]*)%-") do segs[#segs + 1] = seg end
  local ranks = {}
  for tab = 1, #struct.tabs do
    local r, seg = {}, segs[tab] or ""
    for i = 1, struct.tabs[tab].count do r[i] = tonumber(seg:sub(i, i)) or 0 end
    ranks[tab] = r
  end
  return ranks, struct.class
end

local function encodeDigits(ranks, struct)
  local segs = {}
  for tab = 1, #struct.tabs do
    local r, out = ranks[tab] or {}, {}
    for i = 1, struct.tabs[tab].count do out[i] = tostring(r[i] or 0) end
    segs[tab] = (table.concat(out)):gsub("0+$", "")
  end
  return table.concat(segs, "-")
end

-- ----------------------------------------------------------------------------
-- Public encode/decode (with our metadata suffix handling).
-- ----------------------------------------------------------------------------

-- Pull a bare code out of a calculator URL / hash, and split off our ':' metadata.
local function splitMeta(text)
  text = (text or ""):gsub("%s+", "")
  -- strip a calculator URL down to the fragment/code
  local frag = text:match("[#?]talent#(.+)$") or text:match("talent%-calc[^#]*#?/?(.+)$")
    or text:match("talent%-calculator#(.+)$") or text
  local code, meta = frag, nil
  local p = frag:find(META_SEP, nil, true)
  if p then code = frag:sub(1, p - 1); meta = frag:sub(p + 1) end
  return code, meta
end

-- Parse our metadata "DUI=<fp>;S=<label>" -> fp, server.
local function parseMeta(meta)
  if not meta then return nil, nil end
  local fp = meta:match("DUI=([%w]+)")
  local server = meta:match("S=([^;]+)")
  return fp, server
end

-- Decode any supported string into a build { class, ranks, fp, server }, or nil, err.
function T.LO_Decode(text)
  local struct = buildStruct()
  if not struct then return nil, "talent data unavailable" end
  local code, meta = splitMeta(text)
  if not code or code == "" then return nil, "empty talent string" end

  local ranks, class
  -- Try packed (both alphabets), then plain digits.
  ranks, class = decodePacked(code, struct, MAP_URL)
  if not ranks then ranks, class = decodePacked(code, struct, MAP_INTERNAL) end
  if not ranks then ranks, class = decodeDigits(code, struct) end
  if not ranks then return nil, "unrecognised talent string" end

  local fp, server = parseMeta(meta)
  return { class = class or struct.class, ranks = ranks, fp = fp, server = server }
end

-- Encode a build to our share string: a Talented URL-format code + (on custom servers) our metadata.
-- Returns: code (bare, Talented-importable), url (full link), tagged (code + our ':' metadata).
function T.LO_Encode(build)
  local struct = buildStruct()
  if not struct then return nil end
  local code = encodePacked(build.ranks, struct, MAP_URL)
  if not code then return nil end
  local url = ("https://www.wotlkdb.com/?talent#%s"):format(code)
  local tagged = code
  if T.LO_IsCustomServer() then
    tagged = code .. META_SEP .. "DUI=" .. (build.fp or fingerprintOf(struct) or "")
      .. ";S=" .. T.LO_ServerLabel()
  end
  return code, url, tagged
end

-- ----------------------------------------------------------------------------
-- Validation / clamp against the LIVE tree (second safety net for foreign imports).
-- Returns a cleaned ranks table + a list of issues (dropped/clamped points).
-- ----------------------------------------------------------------------------
local function tabSpent(ranks, tab)
  local s = 0; for _, v in pairs(ranks[tab] or {}) do s = s + v end; return s
end
function T.LO_Validate(build)
  local struct = buildStruct()
  if not struct then return nil, { "talent data unavailable" } end
  local clean, issues, total = {}, {}, 0
  for tab = 1, #struct.tabs do
    local td, src, out = struct.tabs[tab], (build.ranks[tab] or {}), {}
    for i = 1, td.count do
      local want = src[i] or 0
      local cap = td.talents[i].maxRank or 0
      if want > cap then
        issues[#issues + 1] = ("%s tier %d: %d>%d, clamped"):format(td.name or ("tab" .. tab), td.talents[i].tier, want, cap)
        want = cap
      end
      out[i] = want
      total = total + want
    end
    clean[tab] = out
  end
  if total > MAX_POINTS then
    issues[#issues + 1] = ("total %d exceeds %d"):format(total, MAX_POINTS)
  end
  return clean, issues, total
end

-- ----------------------------------------------------------------------------
-- Import with the COMPATIBILITY GUARD. Returns build, verdict where verdict =
--   { ok = true }                                  -> import silently
--   { warn = true, reason = "...", server = "..." } -> UI shows a confirm dialog
-- ----------------------------------------------------------------------------
function T.LO_ImportString(text)
  local build, err = T.LO_Decode(text)
  if not build then return nil, { error = err } end

  local localFp = T.LO_LocalFingerprint()
  local custom  = T.LO_IsCustomServer()

  if build.fp and localFp and build.fp == localFp then
    return build, { ok = true }
  end
  if not build.fp and not custom then
    return build, { ok = true }   -- a standard build onto a standard server
  end
  -- otherwise: layout mismatch (or unknown) onto custom trees
  local reason
  if build.fp then
    reason = ("This build was made for %s, which uses a different talent layout. "):format(build.server or "another server")
      .. "Points may land on the wrong talents."
  else
    reason = "This looks like a standard WotLK build, but your server uses custom talents. "
      .. "Points may not line up."
  end
  return build, { warn = true, reason = reason, server = build.server }
end

-- Convenience: export the CURRENT live spec as a share string (code, url, tagged).
function T.LO_ExportCurrent()
  local struct = buildStruct()
  if not struct then return nil end
  return T.LO_Encode({ class = struct.class, ranks = currentRanks(), fp = fingerprintOf(struct) })
end

-- ----------------------------------------------------------------------------
-- Saved-build store. Account-wide, keyed by class (builds are class-specific). Each entry is a
-- plain build { name, class, ranks, fp, server }. Additive — never wipes existing data.
-- ----------------------------------------------------------------------------
local function store()
  if not NE.db then return nil end
  NE.db.talentBuilds = NE.db.talentBuilds or {}
  local _, classFile = UnitClass("player")
  classFile = classFile or "UNKNOWN"
  NE.db.talentBuilds[classFile] = NE.db.talentBuilds[classFile] or {}
  return NE.db.talentBuilds[classFile]
end

function T.LO_Save(name, build)
  if not name or name == "" or not build then return false end
  local db = store(); if not db then return false end
  db[name] = { name = name, class = build.class, ranks = build.ranks, fp = build.fp, server = build.server }
  return true
end

function T.LO_SaveCurrent(name)
  local struct = buildStruct(); if not struct then return false end
  return T.LO_Save(name, { class = struct.class, ranks = currentRanks(), fp = fingerprintOf(struct) })
end

function T.LO_List()
  local db = store(); if not db then return {} end
  local out = {}
  for name in pairs(db) do out[#out + 1] = name end
  table.sort(out)
  return out
end

function T.LO_Get(name)
  local db = store(); return db and db[name] or nil
end

function T.LO_Delete(name)
  local db = store(); if db then db[name] = nil; return true end
  return false
end

function T.LO_Rename(oldName, newName)
  local db = store()
  if not (db and db[oldName]) or not newName or newName == "" or db[newName] then return false end
  db[newName] = db[oldName]
  db[newName].name = newName
  db[oldName] = nil
  return true
end
