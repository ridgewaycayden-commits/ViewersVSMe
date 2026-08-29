local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local MinimapService = {}

local WORLD_ROOT_ATTR = "ArnisWorldRootName"
local MINIMAP_WORLD_ROOT_ATTR = "ArnisMinimapWorldRootName"
local ENABLED_ATTR = "ArnisMinimapEnabled"
local CHUNK_JSON_ATTR = "ArnisMinimapChunkJson"
local CHUNK_ID_ATTR = "ArnisMinimapChunkId"
local CHUNK_BUILDING_BOUNDS_MIN_X_ATTR = "ArnisMinimapChunkBuildingBoundsMinX"
local CHUNK_BUILDING_BOUNDS_MAX_X_ATTR = "ArnisMinimapChunkBuildingBoundsMaxX"
local CHUNK_BUILDING_BOUNDS_MIN_Z_ATTR = "ArnisMinimapChunkBuildingBoundsMinZ"
local CHUNK_BUILDING_BOUNDS_MAX_Z_ATTR = "ArnisMinimapChunkBuildingBoundsMaxZ"

local function updateBounds(bounds, x, z)
    if x < bounds.minX then
        bounds.minX = x
    end
    if x > bounds.maxX then
        bounds.maxX = x
    end
    if z < bounds.minZ then
        bounds.minZ = z
    end
    if z > bounds.maxZ then
        bounds.maxZ = z
    end
end

local function computeBuildingBounds(chunkData)
    local buildings = chunkData and chunkData.buildings
    if type(buildings) ~= "table" then
        return nil
    end

    local origin = chunkData.originStuds or {}
    local ox = tonumber(origin.x or origin.X) or 0
    local oz = tonumber(origin.z or origin.Z) or 0
    local bounds = nil

    for _, building in ipairs(buildings) do
        local footprint = building and building.footprint
        if type(footprint) == "table" and #footprint > 0 then
            if bounds == nil then
                bounds = {
                    minX = math.huge,
                    maxX = -math.huge,
                    minZ = math.huge,
                    maxZ = -math.huge,
                }
            end
            for _, point in ipairs(footprint) do
                local px = tonumber(point and point.x) or 0
                local pz = tonumber(point and point.z) or 0
                updateBounds(bounds, ox + px, oz + pz)
            end
        end
    end

    if bounds == nil or bounds.minX == math.huge then
        return nil
    end
    return bounds
end

local function setChunkBuildingBounds(chunkFolder, buildingBounds)
    if buildingBounds ~= nil then
        chunkFolder:SetAttribute(CHUNK_BUILDING_BOUNDS_MIN_X_ATTR, buildingBounds.minX)
        chunkFolder:SetAttribute(CHUNK_BUILDING_BOUNDS_MAX_X_ATTR, buildingBounds.maxX)
        chunkFolder:SetAttribute(CHUNK_BUILDING_BOUNDS_MIN_Z_ATTR, buildingBounds.minZ)
        chunkFolder:SetAttribute(CHUNK_BUILDING_BOUNDS_MAX_Z_ATTR, buildingBounds.maxZ)
        return
    end

    chunkFolder:SetAttribute(CHUNK_BUILDING_BOUNDS_MIN_X_ATTR, nil)
    chunkFolder:SetAttribute(CHUNK_BUILDING_BOUNDS_MAX_X_ATTR, nil)
    chunkFolder:SetAttribute(CHUNK_BUILDING_BOUNDS_MIN_Z_ATTR, nil)
    chunkFolder:SetAttribute(CHUNK_BUILDING_BOUNDS_MAX_Z_ATTR, nil)
end

local function copyPoints(points)
    local result = table.create(#(points or {}))
    for index, point in ipairs(points or {}) do
        result[index] = {
            x = point.x,
            z = point.z,
        }
    end
    return result
end

local function copyLanduse(landuse)
    local result = table.create(#(landuse or {}))
    for index, entry in ipairs(landuse or {}) do
        result[index] = {
            kind = entry.kind,
            footprint = copyPoints(entry.footprint),
        }
    end
    return result
end

local function copyRoads(roads)
    local result = table.create(#(roads or {}))
    for index, road in ipairs(roads or {}) do
        result[index] = {
            kind = road.kind,
            widthStuds = road.widthStuds,
            points = copyPoints(road.points),
        }
    end
    return result
end

local function copyBuildings(buildings)
    local result = table.create(#(buildings or {}))
    for index, building in ipairs(buildings or {}) do
        -- Building metadata beyond footprint lets the minimap colour
        -- buildings by kind / wall color / height rather than a single
        -- flat "building" hue. Previously the feed was footprint-only,
        -- so every building rendered identically and the minimap
        -- looked jagged and unvaried.
        local wallColor = building.wallColor
        result[index] = {
            footprint = copyPoints(building.footprint),
            kind = building.kind or building.usage or nil,
            height = building.height or nil,
            wallColor = type(wallColor) == "table"
                and { r = wallColor.r, g = wallColor.g, b = wallColor.b }
                or nil,
        }
    end
    return result
end

local function copyWater(water)
    local result = table.create(#(water or {}))
    for index, entry in ipairs(water or {}) do
        result[index] = {
            kind = entry.kind,
            footprint = copyPoints(entry.footprint),
            points = copyPoints(entry.points),
            widthStuds = entry.widthStuds,
        }
    end
    return result
end

-- Railway tracks as a first-class minimap layer. The chunk data
-- carries `rails[]` with the same point-list shape as roads; publishing
-- them here lets the controller draw a distinct color so transit maps
-- actually show the rail network.
local function copyRails(rails)
    local result = table.create(#(rails or {}))
    for index, rail in ipairs(rails or {}) do
        result[index] = {
            kind = rail.kind,
            widthStuds = rail.widthStuds,
            points = copyPoints(rail.points),
        }
    end
    return result
end

-- Walls, fences, and other linear barriers. Same shape as roads.
local function copyBarriers(barriers)
    local result = table.create(#(barriers or {}))
    for index, barrier in ipairs(barriers or {}) do
        result[index] = {
            kind = barrier.kind,
            widthStuds = barrier.widthStuds,
            points = copyPoints(barrier.points),
        }
    end
    return result
end

local function buildChunkSnapshot(chunkData)
    local origin = chunkData.originStuds or {}
    return {
        id = chunkData.id,
        originStuds = {
            x = origin.x or 0,
            z = origin.z or 0,
        },
        landuse = copyLanduse(chunkData.landuse),
        roads = copyRoads(chunkData.roads),
        rails = copyRails(chunkData.rails),
        buildings = copyBuildings(chunkData.buildings),
        water = copyWater(chunkData.water),
        barriers = copyBarriers(chunkData.barriers),
    }
end

function MinimapService.RegisterChunk(chunkFolder, chunkData)
    if not chunkFolder or type(chunkData) ~= "table" then
        return
    end

    chunkFolder:SetAttribute(CHUNK_ID_ATTR, chunkData.id or chunkFolder.Name)
    chunkFolder:SetAttribute(CHUNK_JSON_ATTR, HttpService:JSONEncode(buildChunkSnapshot(chunkData)))
    local buildingBounds = computeBuildingBounds(chunkData)
    setChunkBuildingBounds(chunkFolder, buildingBounds)
end

function MinimapService.ClearChunk(chunkFolder)
    if not chunkFolder then
        return
    end

    chunkFolder:SetAttribute(CHUNK_JSON_ATTR, nil)
    chunkFolder:SetAttribute(CHUNK_ID_ATTR, nil)
    setChunkBuildingBounds(chunkFolder, nil)
end

function MinimapService.Start(options)
    local resolvedOptions = options or {}
    local worldRootName = Workspace:GetAttribute(WORLD_ROOT_ATTR)
        or resolvedOptions.worldRootName
        or "GeneratedWorld"
    Workspace:SetAttribute(ENABLED_ATTR, true)
    Workspace:SetAttribute(MINIMAP_WORLD_ROOT_ATTR, Workspace:GetAttribute(WORLD_ROOT_ATTR) or worldRootName)
end

function MinimapService.Stop()
    Workspace:SetAttribute(ENABLED_ATTR, false)
    Workspace:SetAttribute(MINIMAP_WORLD_ROOT_ATTR, nil)
end

return MinimapService
