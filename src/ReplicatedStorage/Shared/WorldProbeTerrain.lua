local WorldProbeTerrain = {}

local function roundTenths(value)
    if type(value) ~= "number" then
        return nil
    end
    return math.round(value * 10) / 10
end

local function buildIndexSet(indices)
    local indexSet = {}
    if type(indices) ~= "table" then
        return indexSet
    end

    for _, index in ipairs(indices) do
        if type(index) == "number" then
            indexSet[index] = true
        end
    end

    return indexSet
end

local function countSampleSlots(samples)
    local totalSlots = 0
    if type(samples) ~= "table" then
        return totalSlots
    end

    for index in pairs(samples) do
        if type(index) == "number" and index > totalSlots then
            totalSlots = index
        end
    end

    return totalSlots
end

function WorldProbeTerrain.summarizeTerrainSamples(samples, options)
    options = options or {}
    local totalSlots = countSampleSlots(samples)
    local samplePattern = if type(options.samplePattern) == "string" and options.samplePattern ~= ""
        then options.samplePattern
        else "unknown"
    local sampleRadiusStuds = roundTenths(options.sampleRadiusStuds)
    local centerIndex = if type(options.centerIndex) == "number"
        then options.centerIndex
        else math.ceil(totalSlots * 0.5)
    local neighborPairs = if type(options.neighborPairs) == "table" then options.neighborPairs else {}
    local edgeIndexSet = buildIndexSet(options.edgeIndices)
    local hasExplicitEdgeIndices = next(edgeIndexSet) ~= nil

    local sampleCount = 0
    local minTerrainY = nil
    local maxTerrainY = nil
    local materialCounts = {}

    if type(samples) == "table" then
        for _, sample in ipairs(samples) do
            local height = if type(sample) == "table" then sample.terrainY else nil
            if type(height) == "number" then
                sampleCount += 1
                local materialName = if type(sample.terrainMaterial) == "string"
                        and sample.terrainMaterial ~= ""
                    then sample.terrainMaterial
                    else "Unknown"
                materialCounts[materialName] = (materialCounts[materialName] or 0) + 1
                if minTerrainY == nil or height < minTerrainY then
                    minTerrainY = height
                end
                if maxTerrainY == nil or height > maxTerrainY then
                    maxTerrainY = height
                end
            end
        end
    end

    local missingSampleCount = math.max(totalSlots - sampleCount, 0)
    local centerTerrainY = nil
    if
        type(samples) == "table"
        and type(samples[centerIndex]) == "table"
        and type(samples[centerIndex].terrainY) == "number"
    then
        centerTerrainY = samples[centerIndex].terrainY
    end

    local missingEdgeSampleCount = 0
    local edgeMinTerrainY = nil
    local edgeMaxTerrainY = nil
    local edgeTotalTerrainY = 0
    local edgeSampleCount = 0
    local centerEdgeMaxDeltaStuds = nil
    if type(samples) == "table" then
        local function sampleEdge(index)
            if index == centerIndex then
                return
            end

            local edgeSample = samples[index]
            local edgeHeight = if type(edgeSample) == "table" then edgeSample.terrainY else nil
            if type(edgeHeight) ~= "number" then
                missingEdgeSampleCount += 1
                return
            end

            if edgeMinTerrainY == nil or edgeHeight < edgeMinTerrainY then
                edgeMinTerrainY = edgeHeight
            end
            if edgeMaxTerrainY == nil or edgeHeight > edgeMaxTerrainY then
                edgeMaxTerrainY = edgeHeight
            end
            edgeTotalTerrainY += edgeHeight
            edgeSampleCount += 1
            if type(centerTerrainY) == "number" then
                local centerEdgeDelta = math.abs(centerTerrainY - edgeHeight)
                if centerEdgeMaxDeltaStuds == nil or centerEdgeDelta > centerEdgeMaxDeltaStuds then
                    centerEdgeMaxDeltaStuds = centerEdgeDelta
                end
            end
        end

        if hasExplicitEdgeIndices then
            for index in pairs(edgeIndexSet) do
                sampleEdge(index)
            end
        else
            for index = 1, totalSlots do
                sampleEdge(index)
            end
        end
    end

    local totalStep = 0
    local stepCount = 0
    local maxStepStuds = nil
    for _, pair in ipairs(neighborPairs) do
        local firstIndex = pair[1]
        local secondIndex = pair[2]
        local firstHeight = if type(samples) == "table" and type(samples[firstIndex]) == "table"
            then samples[firstIndex].terrainY
            else nil
        local secondHeight = if type(samples) == "table" and type(samples[secondIndex]) == "table"
            then samples[secondIndex].terrainY
            else nil
        if type(firstHeight) == "number" and type(secondHeight) == "number" then
            local delta = math.abs(firstHeight - secondHeight)
            totalStep += delta
            stepCount += 1
            if maxStepStuds == nil or delta > maxStepStuds then
                maxStepStuds = delta
            end
        end
    end

    local materialKindCount = 0
    local dominantMaterial = nil
    local dominantMaterialSampleCount = 0
    local nonGrassSampleCount = sampleCount
    for materialName, count in pairs(materialCounts) do
        materialKindCount += 1
        if materialName == "Grass" then
            nonGrassSampleCount -= count
        end
        if
            count > dominantMaterialSampleCount
            or (count == dominantMaterialSampleCount and (dominantMaterial == nil or materialName < dominantMaterial))
        then
            dominantMaterial = materialName
            dominantMaterialSampleCount = count
        end
    end

    local status = "ok"
    if centerTerrainY == nil or sampleCount < 3 or stepCount <= 0 then
        status = "insufficient_samples"
    end

    local edgeMeanTerrainY = if edgeSampleCount > 0 then edgeTotalTerrainY / edgeSampleCount else nil
    local coverageRatio = if totalSlots > 0 then sampleCount / totalSlots else 0
    local edgeSlotCount = edgeSampleCount + missingEdgeSampleCount
    local edgeCoverageRatio = if edgeSlotCount > 0 then edgeSampleCount / edgeSlotCount else 0
    local convergenceStatus = status
    if convergenceStatus == "ok" and missingEdgeSampleCount > 0 then
        convergenceStatus = "edge_incomplete"
    end

    return {
        status = status,
        convergenceStatus = convergenceStatus,
        samplePattern = samplePattern,
        sampleRadiusStuds = sampleRadiusStuds,
        sampleCount = sampleCount,
        missingSampleCount = missingSampleCount,
        missingEdgeSampleCount = missingEdgeSampleCount,
        coverageRatio = roundTenths(coverageRatio),
        edgeCoverageRatio = roundTenths(edgeCoverageRatio),
        centerTerrainY = roundTenths(centerTerrainY),
        edgeMeanTerrainY = if status == "ok" then roundTenths(edgeMeanTerrainY) else nil,
        minTerrainY = roundTenths(minTerrainY),
        maxTerrainY = roundTenths(maxTerrainY),
        heightRangeStuds = if minTerrainY ~= nil and maxTerrainY ~= nil
            then roundTenths(maxTerrainY - minTerrainY)
            else nil,
        maxStepStuds = if status == "ok" then roundTenths(maxStepStuds) else nil,
        meanAbsStepStuds = if status == "ok" and stepCount > 0 then roundTenths(totalStep / stepCount) else nil,
        edgeTerrainYRangeStuds = if edgeMinTerrainY ~= nil and edgeMaxTerrainY ~= nil
            then roundTenths(edgeMaxTerrainY - edgeMinTerrainY)
            else nil,
        centerMinusEdgeMeanStuds = if status == "ok"
                and centerTerrainY ~= nil
                and edgeMeanTerrainY ~= nil
            then roundTenths(centerTerrainY - edgeMeanTerrainY)
            else nil,
        centerEdgeMaxDeltaStuds = if status == "ok" then roundTenths(centerEdgeMaxDeltaStuds) else nil,
        materialKindCount = materialKindCount,
        dominantMaterial = dominantMaterial,
        dominantMaterialSampleCount = if dominantMaterial ~= nil then dominantMaterialSampleCount else nil,
        nonGrassSampleCount = math.max(nonGrassSampleCount, 0),
    }
end

return WorldProbeTerrain
