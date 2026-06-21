-- DragonUI_NewEra/compat/C_Texture.lua
-- Ensures C_Texture.GetAtlasInfo / GetAtlasExists exist (atlas QUERY only).
--
-- DOWNPORT: 3.3.5a has no native atlas system and no C_Texture. NewEra queries
-- C_Texture.GetAtlasInfo("<name>") to discover atlas slice coords; on retail these
-- come from the client's atlas DB. Here the atlas DATA is registered by the Asset
-- agent (Core/Texture.lua -> NE.tex), not by the client. This shim therefore:
--   * leaves ClassicAPI's C_Texture in place if loaded (it has a full atlas registry
--     incl. RegisterAtlas/RegisterAtlasTable and the same GetAtlasInfo return shape),
--   * otherwise provides a minimal registry compatible with ClassicAPI's API so the
--     Asset/Core agents can register atlases through the same calls, and GetAtlasInfo
--     answers queries NewEra makes directly.
-- The v1 modules guard all of these (`if C_Texture and C_Texture.GetAtlasInfo`), so a
-- registry that's simply empty until populated is safe (returns nil = "no atlas").

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local type = type
local pairs = pairs
local gsub = string.gsub
local match = string.match

C_Texture = C_Texture or {}

-- Backing store. If ClassicAPI already created C_Texture with AtlasData, reuse it so
-- both registries share the same table; otherwise create our own.
C_Texture.AtlasData = C_Texture.AtlasData or {}
local AtlasData = C_Texture.AtlasData

-- RegisterAtlas(name, info, path[, silent])
--   info = { width, height, leftTexCoord, rightTexCoord, topTexCoord,
--            bottomTexCoord, tilesHorizontally, tilesVertically }
--   info[9] is set to the normalized texture path. Mirrors ClassicAPI's shape so the
--   Core/Asset agents can target either backend identically.
if not C_Texture.RegisterAtlas then
    function C_Texture.RegisterAtlas(name, info, path, silent)
        if type(name) ~= "string" or type(info) ~= "table" then return false end
        if AtlasData[name] and not silent then return false end
        if type(path) == "string" then
            info[9] = gsub(path, "/", "\\")
        end
        AtlasData[name] = info
        return true
    end
end

-- RegisterAtlasTable(atlasTable) : bulk register (see ClassicAPI C_Texture docs).
if not C_Texture.RegisterAtlasTable then
    function C_Texture.RegisterAtlasTable(atlasTable)
        if type(atlasTable) ~= "table" then return end
        local root = atlasTable.directory or atlasTable.rootDirectory or ""
        for path, atlases in pairs(atlasTable) do
            if path ~= "directory" and path ~= "rootDirectory" and type(atlases) == "table" then
                local full = root .. path
                for atlasName, info in pairs(atlases) do
                    C_Texture.RegisterAtlas(atlasName, info, full, true)
                end
            end
        end
    end
end

-- GetAtlasExists(name) -> bool
if not C_Texture.GetAtlasExists then
    function C_Texture.GetAtlasExists(name)
        return AtlasData[name] ~= nil
    end
end

-- GetAtlasInfo(name) -> table | nil  (retail-shaped: width/height/*TexCoord/...)
if not C_Texture.GetAtlasInfo then
    function C_Texture.GetAtlasInfo(name)
        local data = AtlasData[name]
        if not data then return nil end
        local filename = data[9]
        return {
            width             = data[1],
            height            = data[2],
            leftTexCoord      = data[3],
            rightTexCoord     = data[4],
            topTexCoord       = data[5],
            bottomTexCoord    = data[6],
            tilesHorizontally = data[7],
            tilesVertically   = data[8],
            filename          = filename,
            elementName       = filename and (match(filename, "([^\\]+)$") or filename) or nil,
        }
    end
end

NE.compat.texture = true
