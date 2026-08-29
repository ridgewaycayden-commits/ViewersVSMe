local WorldProbeTelemetryFlags = {}

WorldProbeTelemetryFlags.WORKSPACE_ATTR = "ArnisTelemetryFamilies"
WorldProbeTelemetryFlags.PLAYER_ATTR = "ArnisTelemetryFamilies"
WorldProbeTelemetryFlags.REPLICATED_STORAGE_ATTR = "ArnisTelemetryFamilies"

local SUPPORTED_FAMILY_ORDER = {
    "terrain",
    "roads",
    "water",
    "vegetation",
    "structures",
    "hotspots",
    "client_perf",
    "client_flicker",
    "player_local",
}
WorldProbeTelemetryFlags.SUPPORTED_FAMILY_ORDER = SUPPORTED_FAMILY_ORDER

local SUPPORTED_FAMILIES = {}
for _, familyName in ipairs(SUPPORTED_FAMILY_ORDER) do
    SUPPORTED_FAMILIES[familyName] = true
end
WorldProbeTelemetryFlags.SUPPORTED_FAMILIES = SUPPORTED_FAMILIES

local function trim(value)
    if type(value) ~= "string" then
        return ""
    end

    local trimmed = string.match(value, "^%s*(.-)%s*$")
    if trimmed == nil then
        return ""
    end
    return trimmed
end

local function normalizeFamilyName(value)
    local familyName = trim(value)
    if familyName == "" then
        return nil
    end
    familyName = string.lower(familyName)
    if not WorldProbeTelemetryFlags.SUPPORTED_FAMILIES[familyName] then
        return nil
    end
    return familyName
end

function WorldProbeTelemetryFlags.parseTelemetryFamilies(value)
    local familySet = {}

    if type(value) == "string" then
        for token in string.gmatch(value, "[^,]+") do
            local familyName = normalizeFamilyName(token)
            if familyName ~= nil then
                familySet[familyName] = true
            end
        end
    elseif type(value) == "table" then
        for _, token in ipairs(value) do
            local familyName = normalizeFamilyName(token)
            if familyName ~= nil then
                familySet[familyName] = true
            end
        end
    end

    local enabledFamilies = {}
    for _, familyName in ipairs(WorldProbeTelemetryFlags.SUPPORTED_FAMILY_ORDER) do
        if familySet[familyName] then
            enabledFamilies[#enabledFamilies + 1] = familyName
        end
    end

    return {
        familySet = familySet,
        enabledFamilies = enabledFamilies,
    }
end

function WorldProbeTelemetryFlags.isEnabled(telemetryFlags, family)
    return type(telemetryFlags) == "table"
        and type(family) == "string"
        and telemetryFlags.familySet ~= nil
        and telemetryFlags.familySet[family] == true
end

function WorldProbeTelemetryFlags.annotateMarkerPayload(payload, telemetryFlags)
    if type(payload) ~= "table" then
        return payload
    end

    local enabledFamilies = if type(telemetryFlags) == "table" then telemetryFlags.enabledFamilies else nil
    if type(enabledFamilies) ~= "table" or #enabledFamilies == 0 then
        payload.telemetryFamilies = nil
        return payload
    end

    payload.telemetryFamilies = enabledFamilies
    return payload
end

function WorldProbeTelemetryFlags.shapeLocalExperiencePayload(payload, telemetryFlags, playerLocalTelemetryEnabled)
    if type(payload) ~= "table" then
        return payload
    end

    local function compactCopy(source, allowedKeys)
        if type(source) ~= "table" then
            return nil
        end
        local compact = {}
        for _, key in ipairs(allowedKeys) do
            local value = source[key]
            if value ~= nil then
                compact[key] = value
            end
        end
        if next(compact) == nil then
            return nil
        end
        return compact
    end

    WorldProbeTelemetryFlags.annotateMarkerPayload(payload, telemetryFlags)
    payload.playerLocalTelemetryEnabled = playerLocalTelemetryEnabled == true
    if payload.playerLocalTelemetryEnabled then
        payload.localSupport = compactCopy(payload.localSupport, {
            "surfaceRole",
            "supportY",
            "terrainY",
            "supportMinusTerrainYStuds",
        })
        payload.localTerrain = compactCopy(payload.localTerrain, {
            "status",
            "convergenceStatus",
            "samplePattern",
            "sampleRadiusStuds",
            "sampleCount",
            "missingSampleCount",
            "missingEdgeSampleCount",
            "centerTerrainY",
            "minTerrainY",
            "maxTerrainY",
            "heightRangeStuds",
            "maxStepStuds",
            "meanAbsStepStuds",
            "edgeMeanTerrainY",
            "centerMinusEdgeMeanStuds",
            "edgeTerrainYRangeStuds",
            "centerEdgeMaxDeltaStuds",
            "materialKindCount",
            "dominantMaterial",
            "dominantMaterialSampleCount",
            "nonGrassSampleCount",
            "coverageRatio",
            "edgeCoverageRatio",
        })
        payload.localEnclosure = compactCopy(payload.localEnclosure, {
            "nearbyWallParts",
            "collidableWallPartsNearby",
            "nearestWallDistanceStuds",
            "readableFacadeCueParts",
        })
        payload.localRoofCover = compactCopy(payload.localRoofCover, {
            "nearbyRoofParts",
            "overheadRoofParts",
            "overheadRoofMinClearanceStuds",
        })
        payload.characterPosition = nil
        return payload
    end

    payload.localSupport = nil
    payload.localTerrain = nil
    payload.localEnclosure = nil
    payload.localRoofCover = nil
    payload.characterPosition = nil
    return payload
end

return WorldProbeTelemetryFlags
