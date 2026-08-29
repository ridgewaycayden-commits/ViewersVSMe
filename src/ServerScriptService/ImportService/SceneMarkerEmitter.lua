local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local SceneMarkerEmitter = {}

local function cloneStatsWithoutSourceIds(stats)
    local cloned = {}
    if typeof(stats) ~= "table" then
        return cloned
    end
    for statsKey, statsValue in pairs(stats) do
        if statsKey ~= "sourceIds" and statsKey ~= "_sourceIdSet" then
            cloned[statsKey] = statsValue
        end
    end
    return cloned
end

local function emitSourceIdBatches(marker, suffix, phase, rootName, bucket, sourceIds)
    if typeof(sourceIds) ~= "table" or #sourceIds == 0 then
        return
    end

    local maxSceneIdBatchChars = 700
    local batch = {}
    for _, sourceId in ipairs(sourceIds) do
        batch[#batch + 1] = sourceId
        local candidatePayload = {
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            sourceIds = batch,
        }
        local candidateJson = HttpService:JSONEncode(candidatePayload)
        if string.len(candidateJson) > maxSceneIdBatchChars and #batch > 1 then
            table.remove(batch, #batch)
            print(marker .. suffix .. " " .. HttpService:JSONEncode({
                phase = phase,
                rootName = rootName,
                bucket = bucket,
                sourceIds = batch,
            }))
            batch = { sourceId }
        end
    end

    if #batch > 0 then
        print(marker .. suffix .. " " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            sourceIds = batch,
        }))
    end
end

function SceneMarkerEmitter.emitSceneMarkers(marker, phase, rootName, radius, sceneSummary, metadata)
    local compactScene = {}
    local chunkIds = {}
    local roofCoverageByUsage = {}
    local roofCoverageByShape = {}
    local scalarValues = {}
    local propInstanceCountByKind = {}
    local ambientPropInstanceCountByKind = {}
    local treeInstanceCountBySpecies = {}
    local vegetationInstanceCountByKind = {}
    local waterSurfacePartCountByType = {}
    local waterSurfacePartCountByKind = {}
    local railReceiptCountByKind = {}
    local roadSurfacePartCountByKind = {}
    local roadSurfacePartCountBySubkind = {}
    local buildingModelCountByWallMaterial = {}
    local buildingModelCountByRoofMaterial = {}
    local extraPayload = {}

    if typeof(metadata) == "table" then
        for key, value in pairs(metadata) do
            extraPayload[key] = value
        end
    end

    if typeof(sceneSummary) == "table" then
        for key, value in pairs(sceneSummary) do
            if key == "chunkIds" and typeof(value) == "table" then
                chunkIds = value
            elseif key == "buildingRoofCoverageByUsage" and typeof(value) == "table" then
                roofCoverageByUsage = value
            elseif key == "buildingRoofCoverageByShape" and typeof(value) == "table" then
                roofCoverageByShape = value
            elseif key == "propInstanceCountByKind" and typeof(value) == "table" then
                propInstanceCountByKind = value
            elseif key == "ambientPropInstanceCountByKind" and typeof(value) == "table" then
                ambientPropInstanceCountByKind = value
            elseif key == "treeInstanceCountBySpecies" and typeof(value) == "table" then
                treeInstanceCountBySpecies = value
            elseif key == "vegetationInstanceCountByKind" and typeof(value) == "table" then
                vegetationInstanceCountByKind = value
            elseif key == "waterSurfacePartCountByType" and typeof(value) == "table" then
                waterSurfacePartCountByType = value
            elseif key == "waterSurfacePartCountByKind" and typeof(value) == "table" then
                waterSurfacePartCountByKind = value
            elseif key == "railReceiptCountByKind" and typeof(value) == "table" then
                railReceiptCountByKind = value
            elseif key == "roadSurfacePartCountByKind" and typeof(value) == "table" then
                roadSurfacePartCountByKind = value
            elseif key == "roadSurfacePartCountBySubkind" and typeof(value) == "table" then
                roadSurfacePartCountBySubkind = value
            elseif key == "buildingModelCountByWallMaterial" and typeof(value) == "table" then
                buildingModelCountByWallMaterial = value
            elseif key == "buildingModelCountByRoofMaterial" and typeof(value) == "table" then
                buildingModelCountByRoofMaterial = value
            elseif key ~= "chunkIds"
                and key ~= "buildingRoofCoverageByUsage"
                and key ~= "buildingRoofCoverageByShape"
                and key ~= "propInstanceCountByKind"
                and key ~= "ambientPropInstanceCountByKind"
                and key ~= "treeInstanceCountBySpecies"
                and key ~= "vegetationInstanceCountByKind"
                and key ~= "waterSurfacePartCountByType"
                and key ~= "waterSurfacePartCountByKind"
                and key ~= "railReceiptCountByKind"
                and key ~= "roadSurfacePartCountByKind"
                and key ~= "roadSurfacePartCountBySubkind"
                and key ~= "buildingModelCountByWallMaterial"
                and key ~= "buildingModelCountByRoofMaterial"
            then
                if typeof(value) == "table" then
                    compactScene[key] = value
                else
                    scalarValues[key] = value
                end
            end
        end
    end

    local chunkPayload = {
        phase = phase,
        rootName = rootName,
        chunkIds = chunkIds,
    }
    for key, value in pairs(extraPayload) do
        chunkPayload[key] = value
    end
    print(marker .. "_CHUNKS " .. HttpService:JSONEncode(chunkPayload))

    for key, value in pairs(scalarValues) do
        print(marker .. "_SCALAR " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            key = key,
            value = value,
        }))
    end

    for bucket, stats in pairs(roofCoverageByUsage) do
        print(marker .. "_ROOF_USAGE_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = stats,
        }))
    end

    print(marker .. "_ROOF_SHAPES " .. HttpService:JSONEncode({
        phase = phase,
        rootName = rootName,
        buildingRoofCoverageByShape = roofCoverageByShape,
    }))

    for bucket, stats in pairs(propInstanceCountByKind) do
        print(marker .. "_PROP_KIND_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_PROP_KIND_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end

    for bucket, stats in pairs(ambientPropInstanceCountByKind) do
        print(marker .. "_AMBIENT_PROP_KIND_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = stats,
        }))
    end

    for bucket, stats in pairs(treeInstanceCountBySpecies) do
        print(marker .. "_TREE_SPECIES_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_TREE_SPECIES_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end

    for bucket, stats in pairs(vegetationInstanceCountByKind) do
        print(marker .. "_VEGETATION_KIND_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_VEGETATION_KIND_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end

    for bucket, stats in pairs(waterSurfacePartCountByType) do
        print(marker .. "_WATER_TYPE_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = stats,
        }))
    end

    for bucket, stats in pairs(waterSurfacePartCountByKind) do
        print(marker .. "_WATER_KIND_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_WATER_KIND_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end

    for bucket, stats in pairs(railReceiptCountByKind) do
        print(marker .. "_RAIL_KIND_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_RAIL_KIND_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end

    for bucket, stats in pairs(roadSurfacePartCountByKind) do
        print(marker .. "_ROAD_KIND_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_ROAD_KIND_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end

    for bucket, stats in pairs(roadSurfacePartCountBySubkind) do
        print(marker .. "_ROAD_SUBKIND_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_ROAD_SUBKIND_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end

    for bucket, stats in pairs(buildingModelCountByWallMaterial) do
        print(marker .. "_BUILDING_WALL_MATERIAL_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_BUILDING_WALL_MATERIAL_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end

    for bucket, stats in pairs(buildingModelCountByRoofMaterial) do
        print(marker .. "_BUILDING_ROOF_MATERIAL_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_BUILDING_ROOF_MATERIAL_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end

    local payload = {
        phase = phase,
        rootName = rootName,
        focus = {
            x = Workspace:GetAttribute("VertigoAustinFocusX"),
            z = Workspace:GetAttribute("VertigoAustinFocusZ"),
        },
        radius = radius,
        scene = compactScene,
    }
    for key, value in pairs(extraPayload) do
        payload[key] = value
    end
    print(marker .. " " .. HttpService:JSONEncode(payload))
end

return SceneMarkerEmitter
