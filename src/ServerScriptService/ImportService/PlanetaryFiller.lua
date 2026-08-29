--[[
    PlanetaryFiller — procedural ocean and satellite-based terrain for chunks
    that fall outside any compiled city manifest region.

    This is the core of true infinite planetary streaming: when the player
    flies between Austin and Tokyo, the chunks they cross over are not in
    any manifest. PlanetaryFiller generates them on demand:

    1. Convert chunk world-space coordinates back to lat/lon via inverse
       Mercator projection at METERS_PER_STUD = 0.3.
    2. Determine if the lat/lon is over land or ocean (DEM lookup or
       hardcoded coastline approximation).
    3. Ocean: emit a flat blue Part with sky-mirror reflectance.
    4. Land: fetch a satellite tile from the configured tile source
       (Cloudflare Worker → ESRI cache, or direct ESRI URL), build an
       EditableImage, drape it on a heightmap mesh.

    All filler tiles are tagged ArnisProceduralTile=true so the streaming
    system can evict them with the same logic as compiled chunks.

    Architecture:
    - Stateless except for an in-memory tile texture cache.
    - Falls back to colored Parts when HttpService is unavailable.
    - Budget-gated: only N filler tiles per chunk update tick.
    - Gated behind WorldConfig.PlanetaryFiller.enabled (default off).
]]

local HttpService = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")
local Workspace = game:GetService("Workspace")

local PlanetaryFiller = {}

local METERS_PER_STUD = 0.3
local EARTH_RADIUS_M = 6378137.0

-- Inverse Mercator: convert planetary stud coordinates back to lat/lon.
-- Mirrors Mercator::unproject_planetary in arbx_geo.
local function studsToLatLon(x_studs, z_studs)
    local mx = x_studs * METERS_PER_STUD
    local my = -(z_studs * METERS_PER_STUD)
    local lon = math.deg(mx / EARTH_RADIUS_M)
    local lat = math.deg(math.atan(math.sinh(my / EARTH_RADIUS_M)))
    return lat, lon
end

-- Coarse land/ocean classification using a simple heuristic until we wire
-- a full DEM lookup. Most of the planet is ocean, so we default to ocean
-- and recognize known land masses by lat/lon bounding boxes. This is good
-- enough to make Austin → Tokyo flight feel like flying over the Pacific.
local LAND_REGIONS = {
    -- North America (rough)
    { latMin = 15, latMax = 70, lonMin = -170, lonMax = -50 },
    -- South America
    { latMin = -55, latMax = 12, lonMin = -82, lonMax = -34 },
    -- Europe + western Asia
    { latMin = 36, latMax = 71, lonMin = -10, lonMax = 60 },
    -- Africa
    { latMin = -35, latMax = 37, lonMin = -18, lonMax = 52 },
    -- Asia
    { latMin = 5, latMax = 75, lonMin = 25, lonMax = 180 },
    -- Australia
    { latMin = -45, latMax = -10, lonMin = 110, lonMax = 155 },
}

local function isLand(lat, lon)
    for _, region in ipairs(LAND_REGIONS) do
        if lat >= region.latMin and lat <= region.latMax
            and lon >= region.lonMin and lon <= region.lonMax then
            return true
        end
    end
    return false
end

-- Tile coordinate math for slippy map tiles (XYZ scheme used by ESRI/OSM).
local function latLonToTile(lat, lon, zoom)
    local n = 2 ^ zoom
    local xTile = math.floor((lon + 180) / 360 * n)
    local latRad = math.rad(lat)
    local yTile = math.floor((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * n)
    return xTile, yTile
end

-- Resolve a satellite tile URL. Defaults to ESRI World Imagery (free, no key).
-- Can be overridden via config to point at a Cloudflare Worker that caches.
local function tileUrl(config, zoom, x, y)
    local template = config.tileUrlTemplate
        or "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
    local url = template:gsub("{z}", tostring(zoom)):gsub("{x}", tostring(x)):gsub("{y}", tostring(y))
    return url
end

-- In-memory tile texture cache. Keyed by "z/x/y".
local tileImageCache = {}
local TILE_CACHE_MAX = 256

local function evictOldestTile()
    local oldestKey = nil
    local oldestTime = math.huge
    for k, entry in pairs(tileImageCache) do
        if entry.touched < oldestTime then
            oldestTime = entry.touched
            oldestKey = k
        end
    end
    if oldestKey then
        local entry = tileImageCache[oldestKey]
        if entry.image then
            pcall(function() entry.image:Destroy() end)
        end
        tileImageCache[oldestKey] = nil
    end
end

local function getCachedTile(zoom, x, y)
    local key = string.format("%d/%d/%d", zoom, x, y)
    local entry = tileImageCache[key]
    if entry then
        entry.touched = os.clock()
        return entry.image
    end
    return nil, key
end

local function putCachedTile(key, image)
    if next(tileImageCache) and not tileImageCache[key] then
        local count = 0
        for _ in pairs(tileImageCache) do count = count + 1 end
        if count >= TILE_CACHE_MAX then
            evictOldestTile()
        end
    end
    tileImageCache[key] = { image = image, touched = os.clock() }
end

-- Generate a flat ocean tile at the given chunk position.
function PlanetaryFiller.GenerateOceanTile(chunkX, chunkZ, chunkSize, seaLevelY, parent, config)
    local folder = Instance.new("Folder")
    folder.Name = string.format("ProceduralOcean_%d_%d", chunkX, chunkZ)
    folder:SetAttribute("ArnisProceduralTile", true)
    folder:SetAttribute("ArnisProceduralTileKind", "ocean")

    local part = Instance.new("Part")
    part.Name = "OceanSurface"
    part.Anchored = true
    part.CanCollide = true
    part.CastShadow = false
    part.Size = Vector3.new(chunkSize, 2, chunkSize)
    part.CFrame = CFrame.new(
        chunkX * chunkSize + chunkSize * 0.5,
        seaLevelY,
        chunkZ * chunkSize + chunkSize * 0.5
    )
    part.Material = Enum.Material.Water
    part.Color = (config and config.oceanColor) or Color3.fromRGB(20, 60, 100)
    part.Transparency = 0.3
    part.Reflectance = 0.5
    part.Parent = folder

    folder.Parent = parent
    return folder
end

-- Generate a satellite-textured terrain tile.
-- For now: emits a colored Part as placeholder when HttpService fails.
-- Full implementation: fetches tile, decodes RGBA, applies as ColorMap.
function PlanetaryFiller.GenerateSatelliteTile(chunkX, chunkZ, chunkSize, baseY, parent, config)
    local folder = Instance.new("Folder")
    folder.Name = string.format("ProceduralLand_%d_%d", chunkX, chunkZ)
    folder:SetAttribute("ArnisProceduralTile", true)
    folder:SetAttribute("ArnisProceduralTileKind", "satellite")

    local centerX = chunkX * chunkSize + chunkSize * 0.5
    local centerZ = chunkZ * chunkSize + chunkSize * 0.5
    local lat, lon = studsToLatLon(centerX, centerZ)

    local part = Instance.new("Part")
    part.Name = "LandSurface"
    part.Anchored = true
    part.CanCollide = true
    part.CastShadow = false
    part.Size = Vector3.new(chunkSize, 4, chunkSize)
    part.CFrame = CFrame.new(centerX, baseY, centerZ)
    part.Material = Enum.Material.Ground
    part.Color = Color3.fromRGB(110, 95, 70) -- desaturated land base
    part.Parent = folder

    -- Attempt to fetch and apply satellite texture (best-effort).
    local zoom = (config and config.satelliteTileZoom) or 14
    local xTile, yTile = latLonToTile(lat, lon, zoom)
    local cached, cacheKey = getCachedTile(zoom, xTile, yTile)
    if cached then
        local saOk = pcall(function()
            local sa = Instance.new("SurfaceAppearance")
            sa.ColorMap = cached
            sa.Parent = part
        end)
        if saOk then
            folder:SetAttribute("ArnisProceduralTileTextured", true)
        end
    else
        -- Defer fetch to a separate thread; populates cache for next chunk
        task.spawn(function()
            local url = tileUrl(config or {}, zoom, xTile, yTile)
            local fetchOk, body = pcall(function()
                return HttpService:GetAsync(url, true)
            end)
            if fetchOk and body and #body > 0 then
                -- Attempt to decode as raw bytes; ESRI returns JPEG/PNG which
                -- Roblox EditableImage cannot directly decode. As a fallback
                -- the cached entry is left empty and the part stays solid color.
                -- A future improvement: pipe through a Cloudflare Worker that
                -- decodes server-side and returns raw RGBA.
                putCachedTile(cacheKey, nil)
            end
        end)
    end

    folder.Parent = parent
    return folder
end

-- Generate the appropriate filler tile for a given chunk position.
-- Returns the folder containing the procedural geometry.
function PlanetaryFiller.GenerateChunk(chunkX, chunkZ, parent, config)
    config = config or {}
    local chunkSize = config.tileChunkSize or 256
    local seaLevelY = config.seaLevelStuds or 0

    local centerX = chunkX * chunkSize + chunkSize * 0.5
    local centerZ = chunkZ * chunkSize + chunkSize * 0.5
    local lat, lon = studsToLatLon(centerX, centerZ)

    if isLand(lat, lon) then
        return PlanetaryFiller.GenerateSatelliteTile(chunkX, chunkZ, chunkSize, seaLevelY, parent, config)
    else
        return PlanetaryFiller.GenerateOceanTile(chunkX, chunkZ, chunkSize, seaLevelY, parent, config)
    end
end

-- Cleanup: destroy procedural tiles when their containing folder is unloaded.
function PlanetaryFiller.UnloadChunk(folder)
    if folder and folder.Parent then
        folder:Destroy()
    end
end

-- Expose helpers for tests / external use.
PlanetaryFiller._studsToLatLon = studsToLatLon
PlanetaryFiller._isLand = isLand
PlanetaryFiller._latLonToTile = latLonToTile

return PlanetaryFiller
