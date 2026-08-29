local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")
local Workspace = game:GetService("Workspace")

local TerrainBuilder = {}

-- Binary base64 mesh decode (shared with BuildingBuilder).
local function decodeF32Array(b64str)
    if type(b64str) ~= "string" or #b64str == 0 then return nil end
    local ok, raw = pcall(function() return EncodingService:Base64Decode(b64str) end)
    if not ok or not raw then return nil end
    local buf = buffer.fromstring(raw)
    local count = math.floor(buffer.len(buf) / 4)
    local result = table.create(count)
    for i = 0, count - 1 do result[i + 1] = buffer.readf32(buf, i * 4) end
    return result
end

local function decodeU32Array(b64str)
    if type(b64str) ~= "string" or #b64str == 0 then return nil end
    local ok, raw = pcall(function() return EncodingService:Base64Decode(b64str) end)
    if not ok or not raw then return nil end
    local buf = buffer.fromstring(raw)
    local count = math.floor(buffer.len(buf) / 4)
    local result = table.create(count)
    for i = 0, count - 1 do result[i + 1] = buffer.readu32(buf, i * 4) end
    return result
end
local BUILD_PLAN_CACHE_KEY = "__terrainBuildPlan"
local TERRAIN_WRITE_RESOLUTION = 4

-- Budget tracker for satellite overlay EditableImages.
-- 512x512 RGBA = 1MB each; 10 chunks = ~10MB well within 32MB limit.
-- Dynamically computed from active chunk count rather than a monotonic
-- counter, so evicted chunks free their budget automatically.
local satelliteOverlayBudget = { max = 10 }

function TerrainBuilder.GetActiveSatelliteOverlayCount()
    -- Count EditableImage-backed SurfaceAppearance instances in Workspace.
    -- This is O(n) over tagged parts but runs only at allocation time.
    local count = 0
    for _, tagged in ipairs(game:GetService("CollectionService"):GetTagged("ArnisTerrainSatelliteOverlay")) do
        if tagged.Parent ~= nil then
            count += 1
        end
    end
    return count
end

-- Satellite-derived material palette: material names the Rust pipeline may emit
-- via ESRI satellite classification into terrainGrid.materials[].
-- Any valid Enum.Material name is accepted; this documents the expected set.
local SATELLITE_MATERIAL_PALETTE = {
    Grass = true,
    Sand = true,
    Mud = true,
    Pavement = true,
    Limestone = true,
    Sandstone = true,
    Slate = true,
    Asphalt = true,
    Concrete = true,
    Rock = true,
    Ground = true,
    Snow = true,
    Ice = true,
    Glacier = true,
    LeafyGrass = true,
}

TerrainBuilder.DEFAULT_CLEAR_HEIGHT = 512
TerrainBuilder._fillBlock = function(terrain, cf, size, material)
    terrain:FillBlock(cf, size, material)
end

function TerrainBuilder.Clear(chunk, plan)
    local terrainGrid = chunk.terrain
    if not terrainGrid then
        return
    end

    local terrain = Workspace.Terrain
    local resolvedPlan = plan or rawget(chunk, BUILD_PLAN_CACHE_KEY)
    local cellSize = if resolvedPlan then resolvedPlan.cellSize else terrainGrid.cellSizeStuds
    local origin = if resolvedPlan then resolvedPlan.origin else chunk.originStuds

    local footprintWidth = if resolvedPlan then resolvedPlan.totalWidth else terrainGrid.width * cellSize
    local footprintDepth = if resolvedPlan then resolvedPlan.totalDepth else terrainGrid.depth * cellSize

    local clearSize = Vector3.new(footprintWidth, TerrainBuilder.DEFAULT_CLEAR_HEIGHT, footprintDepth)
    local clearCFrame = CFrame.new(origin.x + footprintWidth * 0.5, origin.y, origin.z + footprintDepth * 0.5)
    TerrainBuilder._fillBlock(terrain, clearCFrame, clearSize, Enum.Material.Air)
end

-- Read at call time, not module load time, so runtime config changes apply.
local WorldConfig = require(game:GetService("ReplicatedStorage").Shared.WorldConfig)
local function getRequestedSampleResolution()
    return WorldConfig.VoxelSize or 1
end
local function getTerrainThickness()
    return WorldConfig.TerrainThickness or 8
end

local function snap(v, down)
    if down then
        return math.floor(v / TERRAIN_WRITE_RESOLUTION) * TERRAIN_WRITE_RESOLUTION
    else
        return math.ceil(v / TERRAIN_WRITE_RESOLUTION) * TERRAIN_WRITE_RESOLUTION
    end
end

local function summarizeTerrainMaterials(cellMaterials, gridW, gridD)
    local materialCounts = {}
    local totalCellCount = 0

    for cellZ = 1, gridD do
        local materialRow = cellMaterials[cellZ]
        if materialRow then
            for cellX = 1, gridW do
                local material = materialRow[cellX] or Enum.Material.Grass
                local materialName = material.Name
                materialCounts[materialName] = (materialCounts[materialName] or 0) + 1
                totalCellCount += 1
            end
        end
    end

    local materialNames = table.create(#materialCounts)
    for materialName in pairs(materialCounts) do
        materialNames[#materialNames + 1] = materialName
    end
    table.sort(materialNames)

    local dominantMaterial = nil
    local dominantMaterialCellCount = -1
    local nonGrassCellCount = totalCellCount
    for _, materialName in ipairs(materialNames) do
        local count = materialCounts[materialName]
        if materialName == "Grass" then
            nonGrassCellCount -= count
        end
        if
            count > dominantMaterialCellCount
            or (count == dominantMaterialCellCount and (dominantMaterial == nil or materialName < dominantMaterial))
        then
            dominantMaterial = materialName
            dominantMaterialCellCount = count
        end
    end

    return {
        materialKindCount = #materialNames,
        dominantMaterial = dominantMaterial or "Unknown",
        dominantMaterialCellCount = math.max(dominantMaterialCellCount, 0),
        nonGrassCellCount = math.max(nonGrassCellCount, 0),
        totalCellCount = totalCellCount,
    }
end

local function buildSubsampleOffsets(writeResolution, requestedSampleResolution)
    local normalizedRequestedResolution =
        math.max(1, math.min(writeResolution, requestedSampleResolution or writeResolution))
    local samplesPerAxis = math.max(1, math.floor(writeResolution / normalizedRequestedResolution + 0.5))
    local step = writeResolution / samplesPerAxis
    local startOffset = -writeResolution * 0.5 + step * 0.5
    local offsets = table.create(samplesPerAxis)
    for index = 1, samplesPerAxis do
        offsets[index] = startOffset + (index - 1) * step
    end
    return offsets
end

local function clampIndex(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function sampleTerrainGridHeight(terrainGrid, cellX, cellZ)
    if type(terrainGrid) ~= "table" then
        return nil
    end

    local width = terrainGrid.width
    local depth = terrainGrid.depth
    local heights = terrainGrid.heights
    if type(width) ~= "number" or type(depth) ~= "number" or type(heights) ~= "table" then
        return nil
    end
    if width < 1 or depth < 1 then
        return nil
    end

    local resolvedCellX = clampIndex(cellX, 0, width - 1)
    local resolvedCellZ = clampIndex(cellZ, 0, depth - 1)
    return heights[resolvedCellZ * width + resolvedCellX + 1] or 0
end

local function mapNeighborIndex(localIndex, localCount, neighborCount)
    if type(neighborCount) ~= "number" or neighborCount < 1 then
        return 0
    end

    if type(localCount) ~= "number" or localCount <= 1 or neighborCount <= 1 then
        return 0
    end

    local clampedIndex = clampIndex(localIndex, 0, localCount - 1)
    local normalized = clampedIndex / math.max(localCount - 1, 1)
    return clampIndex(math.floor(normalized * (neighborCount - 1) + 0.5), 0, neighborCount - 1)
end

local function resolveOffsetNeighborIndex(cellIndex, localCount, neighborCount, isPositiveDirection)
    if type(neighborCount) ~= "number" or neighborCount < 1 then
        return 0
    end
    if type(cellIndex) ~= "number" then
        return 0
    end

    local resolvedIndex
    if isPositiveDirection then
        if type(localCount) ~= "number" or localCount < 0 then
            return 0
        end
        resolvedIndex = cellIndex - localCount
    else
        resolvedIndex = neighborCount + cellIndex
    end

    return clampIndex(resolvedIndex, 0, neighborCount - 1)
end

local function buildTerrainNeighborDescriptorSignature(direction, descriptor)
    local neighborId = descriptor and descriptor.id or nil
    local neighborTerrain = descriptor and descriptor.terrain or nil
    if type(neighborId) ~= "string" or neighborId == "" then
        return nil
    end

    local terrainIdentityToken = tostring(neighborTerrain)
    local heightsIdentityToken = if type(neighborTerrain) == "table" then tostring(neighborTerrain.heights) else "none"
    return table.concat({
        direction .. "=" .. neighborId,
        terrainIdentityToken,
        heightsIdentityToken,
    }, "@")
end

local function buildDerivedTerrainNeighborSignature(terrainNeighbors)
    if type(terrainNeighbors) ~= "table" then
        return "none"
    end

    local directions = { "west", "east", "north", "south", "northWest", "northEast", "southWest", "southEast" }
    local tokens = {}
    for _, direction in ipairs(directions) do
        local descriptor = terrainNeighbors[direction]
        local descriptorSignature = buildTerrainNeighborDescriptorSignature(direction, descriptor)
        if descriptorSignature ~= nil then
            tokens[#tokens + 1] = descriptorSignature
        end
    end

    if #tokens == 0 then
        return "none"
    end

    return table.concat(tokens, ",")
end

local function resolveTerrainNeighborSignature(options)
    if type(options) == "table" and type(options.terrainNeighborSignature) == "string" then
        return options.terrainNeighborSignature
    end

    local terrainNeighbors = if type(options) == "table" then options.terrainNeighbors else nil
    return buildDerivedTerrainNeighborSignature(terrainNeighbors)
end

local function resolveNeighborHeightSample(terrainGrid, terrainNeighbors, gridW, gridD, cellX, cellZ)
    local localHeight = sampleTerrainGridHeight(terrainGrid, cellX, cellZ)
    if cellX >= 0 and cellX < gridW and cellZ >= 0 and cellZ < gridD then
        return localHeight or 0
    end

    if type(terrainNeighbors) ~= "table" then
        return localHeight or 0
    end

    local function sampleEdgeNeighbor(direction)
        local descriptor = terrainNeighbors[direction]
        local neighborTerrain = descriptor and descriptor.terrain or nil
        if type(neighborTerrain) ~= "table" then
            return nil
        end

        if direction == "west" then
            return sampleTerrainGridHeight(
                neighborTerrain,
                resolveOffsetNeighborIndex(cellX, gridW, neighborTerrain.width or 0, false),
                mapNeighborIndex(cellZ, gridD, neighborTerrain.depth or 0)
            )
        end
        if direction == "east" then
            return sampleTerrainGridHeight(
                neighborTerrain,
                resolveOffsetNeighborIndex(cellX, gridW, neighborTerrain.width or 0, true),
                mapNeighborIndex(cellZ, gridD, neighborTerrain.depth or 0)
            )
        end
        if direction == "north" then
            return sampleTerrainGridHeight(
                neighborTerrain,
                mapNeighborIndex(cellX, gridW, neighborTerrain.width or 0),
                resolveOffsetNeighborIndex(cellZ, gridD, neighborTerrain.depth or 0, false)
            )
        end
        if direction == "south" then
            return sampleTerrainGridHeight(
                neighborTerrain,
                mapNeighborIndex(cellX, gridW, neighborTerrain.width or 0),
                resolveOffsetNeighborIndex(cellZ, gridD, neighborTerrain.depth or 0, true)
            )
        end

        return nil
    end

    local function sampleCornerNeighbor(direction)
        local descriptor = terrainNeighbors[direction]
        local neighborTerrain = descriptor and descriptor.terrain or nil
        if type(neighborTerrain) ~= "table" then
            return nil
        end

        if direction == "northWest" then
            return sampleTerrainGridHeight(
                neighborTerrain,
                resolveOffsetNeighborIndex(cellX, gridW, neighborTerrain.width or 0, false),
                resolveOffsetNeighborIndex(cellZ, gridD, neighborTerrain.depth or 0, false)
            )
        end
        if direction == "northEast" then
            return sampleTerrainGridHeight(
                neighborTerrain,
                resolveOffsetNeighborIndex(cellX, gridW, neighborTerrain.width or 0, true),
                resolveOffsetNeighborIndex(cellZ, gridD, neighborTerrain.depth or 0, false)
            )
        end
        if direction == "southWest" then
            return sampleTerrainGridHeight(
                neighborTerrain,
                resolveOffsetNeighborIndex(cellX, gridW, neighborTerrain.width or 0, false),
                resolveOffsetNeighborIndex(cellZ, gridD, neighborTerrain.depth or 0, true)
            )
        end
        if direction == "southEast" then
            return sampleTerrainGridHeight(
                neighborTerrain,
                resolveOffsetNeighborIndex(cellX, gridW, neighborTerrain.width or 0, true),
                resolveOffsetNeighborIndex(cellZ, gridD, neighborTerrain.depth or 0, true)
            )
        end

        return nil
    end

    local function blendNeighborSamples(primarySample, secondarySample)
        if primarySample ~= nil and secondarySample ~= nil then
            return (primarySample + secondarySample) * 0.5
        end
        return primarySample or secondarySample
    end

    if cellX < 0 then
        local cornerSample = nil
        local blendedEdgeSample = nil
        if cellZ < 0 then
            cornerSample = sampleCornerNeighbor("northWest")
            blendedEdgeSample = blendNeighborSamples(sampleEdgeNeighbor("west"), sampleEdgeNeighbor("north"))
        elseif cellZ >= gridD then
            cornerSample = sampleCornerNeighbor("southWest")
            blendedEdgeSample = blendNeighborSamples(sampleEdgeNeighbor("west"), sampleEdgeNeighbor("south"))
        end
        if cornerSample ~= nil then
            return cornerSample
        end
        if blendedEdgeSample ~= nil then
            return blendedEdgeSample
        end
        local edgeSample = sampleEdgeNeighbor("west")
        if edgeSample ~= nil then
            return edgeSample
        end
    elseif cellX >= gridW then
        local cornerSample = nil
        local blendedEdgeSample = nil
        if cellZ < 0 then
            cornerSample = sampleCornerNeighbor("northEast")
            blendedEdgeSample = blendNeighborSamples(sampleEdgeNeighbor("east"), sampleEdgeNeighbor("north"))
        elseif cellZ >= gridD then
            cornerSample = sampleCornerNeighbor("southEast")
            blendedEdgeSample = blendNeighborSamples(sampleEdgeNeighbor("east"), sampleEdgeNeighbor("south"))
        end
        if cornerSample ~= nil then
            return cornerSample
        end
        if blendedEdgeSample ~= nil then
            return blendedEdgeSample
        end
        local edgeSample = sampleEdgeNeighbor("east")
        if edgeSample ~= nil then
            return edgeSample
        end
    end

    if cellZ < 0 then
        local edgeSample = sampleEdgeNeighbor("north")
        if edgeSample ~= nil then
            return edgeSample
        end
    elseif cellZ >= gridD then
        local edgeSample = sampleEdgeNeighbor("south")
        if edgeSample ~= nil then
            return edgeSample
        end
    end

    return localHeight or 0
end

local function sampleVoxelColumnProfile(plan, ix, globalIz)
    local voxelCenterX = plan.rMinX + (ix - 0.5) * TERRAIN_WRITE_RESOLUTION
    local voxelCenterZ = plan.rMinZ + (globalIz - 0.5) * TERRAIN_WRITE_RESOLUTION
    local offsets = plan.voxelSubsampleOffsets
    local materialCounts = {}
    local materialByName = {}
    local dominantMaterialName = nil
    local dominantMaterialSampleCount = -1
    local totalHeight = 0
    local sampleCount = 0
    local minHeight = math.huge
    local maxHeight = -math.huge
    local peakSampleCount = 0

    for offsetXIndex = 1, #offsets do
        local sampleWorldX = voxelCenterX + offsets[offsetXIndex]
        local rawSampleCellX = math.floor((sampleWorldX - plan.origin.x) / plan.cellSize)
        local sampleCellX = rawSampleCellX
        local materialCellX = clampIndex(rawSampleCellX, 0, plan.gridW - 1)
        local sampleCellOriginX = plan.origin.x + sampleCellX * plan.cellSize
        local fracX = math.clamp((sampleWorldX - sampleCellOriginX) / plan.cellSize, 0, 1)

        for offsetZIndex = 1, #offsets do
            local sampleWorldZ = voxelCenterZ + offsets[offsetZIndex]
            local rawSampleCellZ = math.floor((sampleWorldZ - plan.origin.z) / plan.cellSize)
            local sampleCellZ = rawSampleCellZ
            local materialCellZ = clampIndex(rawSampleCellZ, 0, plan.gridD - 1)
            local sampleCellOriginZ = plan.origin.z + sampleCellZ * plan.cellSize
            local fracZ = math.clamp((sampleWorldZ - sampleCellOriginZ) / plan.cellSize, 0, 1)
            local sampleHeight = plan.sampleInterpolatedHeight(sampleCellX, sampleCellZ, fracX, fracZ)
            local sampleMaterial = plan.cellMaterials[materialCellZ + 1][materialCellX + 1]
            local materialName = sampleMaterial.Name

            totalHeight += sampleHeight
            sampleCount += 1
            if sampleHeight < minHeight then
                minHeight = sampleHeight
            end
            if sampleHeight > maxHeight then
                maxHeight = sampleHeight
                peakSampleCount = 1
            elseif sampleHeight == maxHeight then
                peakSampleCount += 1
            end
            materialByName[materialName] = sampleMaterial
            materialCounts[materialName] = (materialCounts[materialName] or 0) + 1

            local nextCount = materialCounts[materialName]
            if
                nextCount > dominantMaterialSampleCount
                or (
                    nextCount == dominantMaterialSampleCount
                    and (dominantMaterialName == nil or materialName < dominantMaterialName)
                )
            then
                dominantMaterialName = materialName
                dominantMaterialSampleCount = nextCount
            end
        end
    end

    local averageHeight = totalHeight / sampleCount
    local heightRange = maxHeight - minHeight
    local peakSampleCoverage = peakSampleCount / sampleCount
    local normalizedPeakCoverage = if heightRange > 0
        then math.clamp((averageHeight - minHeight) / heightRange, 0, 1)
        else 1
    local heightRangeFactor = math.clamp(heightRange / TERRAIN_WRITE_RESOLUTION, 0, 1)
    local peakCoverageBias = math.max(peakSampleCoverage, normalizedPeakCoverage)
    local surfaceHeightBias = heightRangeFactor * peakCoverageBias
    local surfaceHeightCoverageDamping = math.clamp(0.5 + peakCoverageBias * 2, 0.5, 1)
    -- Very sparse peaks should stay close to the surrounding surface instead of
    -- turning one hot sample into a broad elevated plane.
    local sparsePeakCoverageDamping = math.clamp(peakSampleCoverage * 8, 0.5, 1)
    -- Extremely sparse peaks should not inflate into a broad false top plane.
    local sparsePeakPlaneDamping = math.clamp(peakSampleCoverage * 4, 0.25, 1)
    -- Isolated peaks with very little overall support should stay even closer to
    -- the surrounding surface to avoid false ridge planes in play mode.
    local isolatedPeakSupportDamping = math.clamp(0.25 + normalizedPeakCoverage * 4, 0.25, 1)
    surfaceHeightBias = surfaceHeightBias
        * surfaceHeightCoverageDamping
        * sparsePeakCoverageDamping
        * sparsePeakPlaneDamping
        * isolatedPeakSupportDamping
    local surfaceHeight = averageHeight + (maxHeight - averageHeight) * surfaceHeightBias
    local surfaceFillDepth = if heightRange > 0
        then math.max(1, getTerrainThickness() * math.clamp(normalizedPeakCoverage + peakCoverageBias * 0.25, 0, 1))
        else getTerrainThickness()
    local edgeOccupancyScale = if heightRange > 0
        then math.clamp(1 - heightRangeFactor * (1 - peakCoverageBias) * 0.5, 0.35, 1)
        else 1
    local sparsePeakEdgeOccupancyDamping = math.clamp(0.25 + peakSampleCoverage * 6, 0.25, 1)
    edgeOccupancyScale = edgeOccupancyScale * sparsePeakEdgeOccupancyDamping
    local sparseCliffCoverageBias = sparsePeakCoverageDamping * sparsePeakCoverageDamping
    local sparseCliffOccupancyScale = if heightRange > 0
        then math.clamp(edgeOccupancyScale * sparseCliffCoverageBias, 0.2, 1)
        else 1
    if heightRange > 0 then
        local ridgeCoverageBias = peakCoverageBias * peakCoverageBias
        local ridgeFillDepth =
            math.max(1, getTerrainThickness() * math.clamp(normalizedPeakCoverage * 0.5 + ridgeCoverageBias * 0.5, 0, 1))
        surfaceFillDepth = math.min(surfaceFillDepth, ridgeFillDepth)
    end

    return {
        averageHeight = averageHeight,
        heightRange = heightRange,
        peakSampleCoverage = peakSampleCoverage,
        surfaceHeight = surfaceHeight,
        surfaceFillDepth = surfaceFillDepth,
        edgeOccupancyScale = edgeOccupancyScale,
        sparseCliffOccupancyScale = sparseCliffOccupancyScale,
        dominantMaterialName = dominantMaterialName,
        material = materialByName[dominantMaterialName],
        materialSampleCount = dominantMaterialSampleCount,
        sampleCount = sampleCount,
    }
end

local function buildChunkPlan(chunk, options)
    local terrainGrid = chunk.terrain
    if not terrainGrid then
        return nil
    end

    local cellSize = terrainGrid.cellSizeStuds
    local origin = chunk.originStuds
    local totalWidth = terrainGrid.width * cellSize
    local totalDepth = terrainGrid.depth * cellSize
    local gridW = terrainGrid.width
    local gridD = terrainGrid.depth
    local heights = terrainGrid.heights
    local terrainNeighbors = if type(options) == "table" then options.terrainNeighbors else nil
    local terrainNeighborSignature = resolveTerrainNeighborSignature(options)

    local minH = 0
    local maxH = 0
    for _, h in ipairs(heights) do
        if h < minH then
            minH = h
        end
        if h > maxH then
            maxH = h
        end
    end

    local rMinX = snap(origin.x, true)
    local rMinY = snap(origin.y + minH - getTerrainThickness(), true)
    local rMinZ = snap(origin.z, true)
    local rMaxX = snap(origin.x + totalWidth, false)
    local rMaxY = snap(origin.y + maxH + TERRAIN_WRITE_RESOLUTION, false)
    local rMaxZ = snap(origin.z + totalDepth, false)

    if rMaxX <= rMinX then
        rMaxX = rMinX + TERRAIN_WRITE_RESOLUTION
    end
    if rMaxY <= rMinY then
        rMaxY = rMinY + TERRAIN_WRITE_RESOLUTION
    end
    if rMaxZ <= rMinZ then
        rMaxZ = rMinZ + TERRAIN_WRITE_RESOLUTION
    end

    local dimX = (rMaxX - rMinX) / TERRAIN_WRITE_RESOLUTION
    local dimY = (rMaxY - rMinY) / TERRAIN_WRITE_RESOLUTION
    local dimZ = (rMaxZ - rMinZ) / TERRAIN_WRITE_RESOLUTION
    local function sampleInterpolatedHeight(cellX, cellZ, fracX, fracZ)
        local h00 = resolveNeighborHeightSample(terrainGrid, terrainNeighbors, gridW, gridD, cellX, cellZ)
        local h10 = resolveNeighborHeightSample(terrainGrid, terrainNeighbors, gridW, gridD, cellX + 1, cellZ)
        local h01 = resolveNeighborHeightSample(terrainGrid, terrainNeighbors, gridW, gridD, cellX, cellZ + 1)
        local h11 = resolveNeighborHeightSample(terrainGrid, terrainNeighbors, gridW, gridD, cellX + 1, cellZ + 1)
        local h0 = h00 + (h10 - h00) * fracX
        local h1 = h01 + (h11 - h01) * fracX
        return h0 + (h1 - h0) * fracZ
    end

    local function computeSlope(cx, cz)
        local dhdx = (
            resolveNeighborHeightSample(terrainGrid, terrainNeighbors, gridW, gridD, cx + 1, cz)
            - resolveNeighborHeightSample(terrainGrid, terrainNeighbors, gridW, gridD, cx - 1, cz)
        ) / (2 * cellSize)
        local dhdz = (
            resolveNeighborHeightSample(terrainGrid, terrainNeighbors, gridW, gridD, cx, cz + 1)
            - resolveNeighborHeightSample(terrainGrid, terrainNeighbors, gridW, gridD, cx, cz - 1)
        ) / (2 * cellSize)
        return math.sqrt(dhdx * dhdx + dhdz * dhdz)
    end

    local function getMat(x, z)
        -- Satellite-derived per-cell materials are the PRIMARY source when populated.
        local baseMat
        local hasExplicitCellMaterial = false
        if terrainGrid.materials then
            local idx = z * gridW + x + 1
            local name = terrainGrid.materials[idx]
            if name then
                local ok, m = pcall(function()
                    return Enum.Material[name]
                end)
                if ok and m then
                    baseMat = m
                    hasExplicitCellMaterial = true
                end
            end
        end

        -- When satellite data provides a valid material, use it directly.
        if hasExplicitCellMaterial then
            return baseMat
        end

        -- Fallback: no satellite material available for this cell.
        if not baseMat then
            local name = terrainGrid.material
            local ok, m = pcall(function()
                return Enum.Material[name]
            end)
            if ok and m then
                baseMat = m
            else
                -- LeafyGrass is richer/more natural than plain Grass and is a
                -- first-class satellite-palette entry. Default to it so untagged
                -- cells feel closer to Google Earth / Cesium baseline ground.
                baseMat = Enum.Material.LeafyGrass
            end
        end
        -- Promote plain Grass to LeafyGrass for better foliage detail.
        if baseMat == Enum.Material.Grass then
            baseMat = Enum.Material.LeafyGrass
        end

        -- Slope-based classification is a fallback when satellite material is absent.
        local slope = computeSlope(x, z)
        if slope > (WorldConfig.SlopeRockThreshold or 1.0) then
            return Enum.Material.Rock
        elseif slope > (WorldConfig.SlopeGroundThreshold or 0.47) then
            return Enum.Material.Ground
        end
        return baseMat
    end

    local cellMaterials = table.create(gridD)
    for cellZ = 0, gridD - 1 do
        local materialRow = table.create(gridW)
        for cellX = 0, gridW - 1 do
            materialRow[cellX + 1] = getMat(cellX, cellZ)
        end
        cellMaterials[cellZ + 1] = materialRow
    end

    local terrainStats = summarizeTerrainMaterials(cellMaterials, gridW, gridD)
    local voxelSubsampleOffsets = buildSubsampleOffsets(TERRAIN_WRITE_RESOLUTION, getRequestedSampleResolution())

    plan = {
        terrainGrid = terrainGrid,
        origin = origin,
        cellSize = cellSize,
        totalWidth = totalWidth,
        totalDepth = totalDepth,
        heights = heights,
        terrainNeighbors = terrainNeighbors,
        terrainNeighborSignature = terrainNeighborSignature,
        gridW = gridW,
        gridD = gridD,
        rMinX = rMinX,
        rMinY = rMinY,
        rMinZ = rMinZ,
        rMaxX = rMaxX,
        rMaxY = rMaxY,
        rMaxZ = rMaxZ,
        dimX = dimX,
        dimY = dimY,
        dimZ = dimZ,
        writeResolution = TERRAIN_WRITE_RESOLUTION,
        requestedSampleResolution = getRequestedSampleResolution(),
        cellMaterials = cellMaterials,
        terrainStats = terrainStats,
        voxelSubsampleOffsets = voxelSubsampleOffsets,
        subsampleCount = #voxelSubsampleOffsets * #voxelSubsampleOffsets,
        sampleInterpolatedHeight = sampleInterpolatedHeight,
        sampleVoxelColumnProfile = sampleVoxelColumnProfile,
    }
    return plan
end

function TerrainBuilder.PrepareChunk(chunk, options)
    if not chunk or not chunk.terrain then
        return nil
    end

    local cachedPlan = rawget(chunk, BUILD_PLAN_CACHE_KEY)
    if
        cachedPlan ~= nil
        and options == nil
        and cachedPlan.terrainGrid == chunk.terrain
        and cachedPlan.origin == chunk.originStuds
    then
        return cachedPlan
    end

    local terrainNeighborSignature = resolveTerrainNeighborSignature(options)
    if
        cachedPlan ~= nil
        and cachedPlan.terrainGrid == chunk.terrain
        and cachedPlan.origin == chunk.originStuds
        and cachedPlan.terrainNeighborSignature == terrainNeighborSignature
    then
        return cachedPlan
    end

    local plan = buildChunkPlan(chunk, options)
    rawset(chunk, BUILD_PLAN_CACHE_KEY, plan)
    return plan
end

function TerrainBuilder.GetPreparedChunkPlan(chunk)
    return rawget(chunk, BUILD_PLAN_CACHE_KEY)
end

function TerrainBuilder.Build(_parent, chunk, preparedPlan)
    local plan = preparedPlan or TerrainBuilder.PrepareChunk(chunk)
    if not plan then
        return
    end

    TerrainBuilder.Clear(chunk, plan)

    -- After voxel terrain is built, attempt satellite texture overlay if data exists.
    -- Texture data can arrive as:
    --   (a) chunk.terrainTextureData  -- raw buffer, legacy / test path
    --   (b) chunk.terrainTextureModule -- name of a sibling ModuleScript that
    --       returns a Lua string of raw RGBA bytes (produced by the Python
    --       manifest conversion step).
    local textureData = chunk.terrainTextureData
    if not textureData and chunk.terrainTextureModule then
        local ok, loaded = pcall(function()
            local folderName = chunk.terrainTextureFolder or "AustinTerrainTextures"
            -- Texture ModuleScripts live under ServerStorage.SampleData, next to
            -- the manifest shards they were generated alongside.
            local sampleData = game:GetService("ServerStorage"):FindFirstChild("SampleData")
            local folder = sampleData and sampleData:FindFirstChild(folderName)
            if not folder then
                return nil
            end
            local mod = folder:FindFirstChild(chunk.terrainTextureModule)
            if not mod then
                return nil
            end
            local rawString = require(mod)
            if type(rawString) == "string" and #rawString > 0 then
                return buffer.fromstring(rawString)
            end
            return nil
        end)
        if ok and loaded then
            textureData = loaded
        end
    end
    if textureData and _parent then
        TerrainBuilder.BuildSatelliteOverlay(_parent, chunk, plan, textureData)
    end

    local terrain = Workspace.Terrain
    local cellSize = plan.cellSize
    local origin = plan.origin
    local rMinX = plan.rMinX
    local rMinY = plan.rMinY
    local rMinZ = plan.rMinZ
    local rMaxX = plan.rMaxX
    local rMaxY = plan.rMaxY
    local dimX = plan.dimX
    local dimY = plan.dimY
    local dimZ = plan.dimZ
    local gridW = plan.gridW
    local gridD = plan.gridD
    local cellMaterials = plan.cellMaterials
    local sampleVoxelColumnProfile = plan.sampleVoxelColumnProfile

    -- Strip-based WriteVoxels: process 16 Z-voxels at a time so peak memory is
    -- O(dimX * dimY * STRIP_DEPTH) instead of O(dimX * dimY * dimZ).
    -- Roblox terrain requires a 4-stud write resolution.
    local STRIP_DEPTH = 16

    -- Reusable strip buffers, allocated once and refilled each iteration.
    local stripMat = nil
    local stripOcc = nil

    local izBase = 1 -- 1-indexed global Z voxel, start of current strip
    while izBase <= dimZ do
        local izEnd = math.min(izBase + STRIP_DEPTH - 1, dimZ) -- inclusive, 1-indexed
        local stripLen = izEnd - izBase + 1 -- number of Z slices in this strip

        -- Allocate buffers on the first strip; reuse on subsequent strips.
        -- Inner Z dimension is always STRIP_DEPTH except possibly the last strip,
        -- so we allocate fresh when stripLen changes (only the final strip differs).
        if stripMat == nil or #stripMat[1][1] ~= stripLen then
            stripMat = table.create(dimX)
            stripOcc = table.create(dimX)
            for ix = 1, dimX do
                stripMat[ix] = table.create(dimY)
                stripOcc[ix] = table.create(dimY)
                for iy = 1, dimY do
                    stripMat[ix][iy] = table.create(stripLen, Enum.Material.Air)
                    stripOcc[ix][iy] = table.create(stripLen, 0)
                end
            end
        else
            -- Clear buffers back to Air/0 for reuse.
            for ix = 1, dimX do
                for iy = 1, dimY do
                    local mRow = stripMat[ix][iy]
                    local oRow = stripOcc[ix][iy]
                    for s = 1, stripLen do
                        mRow[s] = Enum.Material.Air
                        oRow[s] = 0
                    end
                end
            end
        end

        for ix = 1, dimX do
            for globalIz = izBase, izEnd do
                local localIz = globalIz - izBase + 1 -- 1-indexed within strip
                local columnProfile = sampleVoxelColumnProfile(plan, ix, globalIz)
                local mat = columnProfile.material
                local worldSurfY = origin.y + columnProfile.surfaceHeight
                local worldBotY = worldSurfY - columnProfile.surfaceFillDepth

                local vy0 = math.max(1, math.floor((worldBotY - rMinY) / TERRAIN_WRITE_RESOLUTION) + 1)
                local vy1 = math.min(dimY, math.ceil((worldSurfY - rMinY) / TERRAIN_WRITE_RESOLUTION))

                for iy = vy0, vy1 do
                    local voxelCenterY = rMinY + (iy - 0.5) * TERRAIN_WRITE_RESOLUTION
                    local occupancy = columnProfile.sparseCliffOccupancyScale

                    if iy == vy0 then
                        local bottomOccupancy =
                            math.clamp(0.5 + (voxelCenterY - worldBotY) / TERRAIN_WRITE_RESOLUTION, 0, 1)
                        occupancy = math.min(occupancy, bottomOccupancy * columnProfile.edgeOccupancyScale)
                    end

                    if iy == vy1 then
                        local topOccupancy =
                            math.clamp(0.5 + (worldSurfY - voxelCenterY) / TERRAIN_WRITE_RESOLUTION, 0, 1)
                        occupancy = math.min(occupancy, topOccupancy * columnProfile.edgeOccupancyScale)
                    end

                    if occupancy > 0 then
                        stripMat[ix][iy][localIz] = mat
                        stripOcc[ix][iy][localIz] = occupancy
                    end
                end
            end
        end

        -- Write this strip to Roblox terrain.
        local zWorldMin = rMinZ + (izBase - 1) * TERRAIN_WRITE_RESOLUTION
        local zWorldMax = rMinZ + izEnd * TERRAIN_WRITE_RESOLUTION
        local stripRegion = Region3.new(Vector3.new(rMinX, rMinY, zWorldMin), Vector3.new(rMaxX, rMaxY, zWorldMax))
        terrain:WriteVoxels(stripRegion, TERRAIN_WRITE_RESOLUTION, stripMat, stripOcc)

        izBase = izEnd + 1
    end
end

TerrainBuilder._buildSubsampleOffsets = buildSubsampleOffsets
TerrainBuilder._resolveNeighborHeightSample = resolveNeighborHeightSample
TerrainBuilder._sampleVoxelColumnProfile = sampleVoxelColumnProfile

function TerrainBuilder.ImprintRoads(roads, originStuds, _chunk)
    local terrain = Workspace.Terrain

    local function addRoadSegments(target, road)
        if type(road) ~= "table" then
            return
        end

        if type(road.segments) == "table" then
            local width = road.width or (road.road and road.road.widthStuds) or 10
            local material = road.material or Enum.Material.Asphalt
            for _, segment in ipairs(road.segments) do
                if segment.mode == "ground" and typeof(segment.p1) == "Vector3" and typeof(segment.p2) == "Vector3" then
                    target[#target + 1] = {
                        p1 = segment.p1,
                        p2 = segment.p2,
                        width = width,
                        material = material,
                    }
                end
            end
            return
        end

        if road.tunnel then
            return
        end -- don't imprint tunnels

        if type(road.points) ~= "table" or #road.points < 2 then
            return
        end

        local width = road.widthStuds or 10
        local roadMat = Enum.Material.Asphalt
        if road.material then
            pcall(function()
                roadMat = Enum.Material[road.material]
            end)
        end

        for i = 1, #road.points - 1 do
            local p1 = road.points[i]
            local p2 = road.points[i + 1]
            if type(p1) ~= "table" or type(p2) ~= "table" then
                continue
            end
            if type(p1.x) ~= "number" or type(p1.y) ~= "number" or type(p1.z) ~= "number" then
                continue
            end
            if type(p2.x) ~= "number" or type(p2.y) ~= "number" or type(p2.z) ~= "number" then
                continue
            end

            local worldP1 = Vector3.new(p1.x + originStuds.x, p1.y + originStuds.y, p1.z + originStuds.z)
            local worldP2 = Vector3.new(p2.x + originStuds.x, p2.y + originStuds.y, p2.z + originStuds.z)
            local segLen = (worldP2 - worldP1).Magnitude
            if segLen >= 0.1 then
                target[#target + 1] = {
                    p1 = worldP1,
                    p2 = worldP2,
                    width = width,
                    material = roadMat,
                }
            end
        end
    end

    local segments = {}
    for _, road in ipairs(roads or {}) do
        addRoadSegments(segments, road)
    end

    local function tryMergeSegment(active, nextSegment)
        if not active or not nextSegment then
            return nextSegment
        end

        if not active.p1 or not active.p2 or not nextSegment.p1 or not nextSegment.p2 then
            return nil
        end

        local activeDelta = active.p2 - active.p1
        local nextDelta = nextSegment.p2 - nextSegment.p1
        if activeDelta.Magnitude < 1e-6 or nextDelta.Magnitude < 1e-6 then
            return nil
        end

        local activeDir = activeDelta.Unit
        local nextDir = nextDelta.Unit
        local alignment = activeDir:Dot(nextDir)
        if alignment < 0.999 then
            return nil
        end

        if math.abs(active.width - nextSegment.width) > 1e-6 then
            return nil
        end

        if math.abs(active.p2.X - nextSegment.p1.X) > 1e-6 or math.abs(active.p2.Z - nextSegment.p1.Z) > 1e-6 then
            return nil
        end

        return {
            p1 = active.p1,
            p2 = nextSegment.p2,
            width = active.width,
            material = active.material,
        }
    end

    local function emitImprint(segment)
        local dir = (segment.p2 - segment.p1)
        local segLen = dir.Magnitude
        if segLen < 0.1 then
            return
        end
        -- Carve a shallow ribbon of Air above the road centerline so terrain
        -- collision cannot sit on top of the imported road mesh.
        local startPos = Vector3.new(segment.p1.X, segment.p1.Y + 1, segment.p1.Z)
        local endPos = Vector3.new(segment.p2.X, segment.p2.Y + 1, segment.p2.Z)
        local midpoint = (startPos + endPos) * 0.5
        TerrainBuilder._fillBlock(
            terrain,
            CFrame.lookAt(midpoint, endPos),
            Vector3.new(segment.width, 2, segLen),
            Enum.Material.Air
        )
    end

    local activeSegment = nil
    for _, nextSegment in ipairs(segments) do
        local merged = tryMergeSegment(activeSegment, nextSegment)
        if merged then
            activeSegment = merged
        else
            if activeSegment then
                emitImprint(activeSegment)
            end
            activeSegment = nextSegment
        end
    end

    if activeSegment then
        emitImprint(activeSegment)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Satellite texture overlay: visual-only EditableMesh heightfield with
-- SurfaceAppearance derived from per-chunk satellite imagery.
-- ═══════════════════════════════════════════════════════════════════════════════

TerrainBuilder._satelliteOverlayBudget = satelliteOverlayBudget

--[[
    BuildSatelliteOverlay(parent, chunk, plan, textureData)

    Creates an EditableMesh heightfield grid positioned just above the voxel
    terrain, with a SurfaceAppearance whose ColorMap is an EditableImage built
    from the supplied raw RGBA pixel buffer.

    Parameters:
        parent       — Instance to parent the overlay MeshPart into
        chunk        — The chunk table (must have .terrain with heights)
        plan         — Prepared terrain build plan from PrepareChunk
        textureData  — Raw RGBA pixel buffer (512*512*4 bytes) or nil to skip

    Returns true on success, false/nil on skip or failure.
]]
function TerrainBuilder.BuildSatelliteOverlay(parent, chunk, plan, textureData)
    -- Gate: config knob
    if WorldConfig.EnableTerrainSatelliteOverlay == false then
        return false
    end

    -- Gate: need actual texture data
    if not textureData then
        return false
    end

    -- Gate: need a valid plan with height data
    if not plan or not plan.heights or not plan.gridW or not plan.gridD then
        return false
    end

    -- Gate: budget (dynamically computed from active overlays, not monotonic counter)
    local activeOverlays = TerrainBuilder.GetActiveSatelliteOverlayCount()
    if activeOverlays >= satelliteOverlayBudget.max then
        warn(
            "[TerrainBuilder] Satellite overlay budget exhausted ("
                .. tostring(activeOverlays)
                .. "/"
                .. tostring(satelliteOverlayBudget.max)
                .. "); evict older chunks to free budget"
        )
        return false
    end

    local ok, err = pcall(function()
        local gridW = plan.gridW
        local gridD = plan.gridD
        local cellSize = plan.cellSize
        local origin = plan.origin
        local heights = plan.heights
        local sampleInterpolatedHeight = plan.sampleInterpolatedHeight

        -- Overlay mesh resolution: clamp to at most 64x64 for draw-call sanity.
        local meshResW = math.min(gridW, 64)
        local meshResD = math.min(gridD, 64)

        -- Create the EditableMesh
        local editMesh = AssetService:CreateEditableMesh()

        -- Build vertex grid: (meshResW+1) x (meshResD+1) vertices
        local vertexIds = table.create((meshResW + 1) * (meshResD + 1))
        local stepX = (gridW * cellSize) / meshResW
        local stepZ = (gridD * cellSize) / meshResD

        for iz = 0, meshResD do
            for ix = 0, meshResW do
                local worldX = origin.x + ix * stepX
                local worldZ = origin.z + iz * stepZ

                -- Sample terrain height at this position
                local fracX = ix / meshResW * (gridW - 1)
                local fracZ = iz / meshResD * (gridD - 1)
                local surfaceY = 0
                if sampleInterpolatedHeight then
                    surfaceY = sampleInterpolatedHeight(plan, fracX, fracZ) or 0
                else
                    -- Fallback: nearest-neighbor from heights array
                    local cx = math.floor(fracX + 0.5)
                    local cz = math.floor(fracZ + 0.5)
                    cx = math.clamp(cx, 0, gridW - 1)
                    cz = math.clamp(cz, 0, gridD - 1)
                    surfaceY = heights[cz * gridW + cx + 1] or 0
                end

                local worldY = origin.y + surfaceY + 0.05 -- just above voxel surface

                local vertId = editMesh:AddVertex(Vector3.new(worldX, worldY, worldZ))
                editMesh:SetVertexNormal(vertId, Vector3.new(0, 1, 0))

                -- UV: 0..1 linearly across the chunk (NW = 0,0; SE = 1,1)
                local u = ix / meshResW
                local v = iz / meshResD
                editMesh:SetUV(vertId, Vector2.new(u, v))

                vertexIds[iz * (meshResW + 1) + ix + 1] = vertId
            end
        end

        -- Build triangle faces from the vertex grid
        for iz = 0, meshResD - 1 do
            for ix = 0, meshResW - 1 do
                local topLeft = vertexIds[iz * (meshResW + 1) + ix + 1]
                local topRight = vertexIds[iz * (meshResW + 1) + (ix + 1) + 1]
                local bottomLeft = vertexIds[(iz + 1) * (meshResW + 1) + ix + 1]
                local bottomRight = vertexIds[(iz + 1) * (meshResW + 1) + (ix + 1) + 1]

                -- Two triangles per quad (CCW winding for upward-facing normals)
                editMesh:AddTriangle(topLeft, bottomLeft, topRight)
                editMesh:AddTriangle(topRight, bottomLeft, bottomRight)
            end
        end

        -- Create MeshPart from the EditableMesh
        local meshContent = Content.fromEditableMesh(editMesh)
        local meshPart = Instance.new("MeshPart")
        meshPart.Name = "SatelliteOverlay"
        meshPart.Anchored = true
        meshPart.CanCollide = false
        meshPart.CanQuery = false
        meshPart.CanTouch = false
        meshPart.CastShadow = false
        meshPart.MeshContent = meshContent

        -- Position at chunk center
        local centerX = origin.x + (gridW * cellSize) * 0.5
        local centerZ = origin.z + (gridD * cellSize) * 0.5
        local centerY = origin.y + (plan.rMaxY - plan.rMinY) * 0.5
        meshPart.CFrame = CFrame.new(centerX, centerY, centerZ)

        -- Create EditableImage and write the satellite texture
        local TEXTURE_SIZE = 512
        local editImage = AssetService:CreateEditableImage({
            Size = Vector2.new(TEXTURE_SIZE, TEXTURE_SIZE),
        })
        editImage:WritePixelsBuffer(Vector2.new(0, 0), Vector2.new(TEXTURE_SIZE, TEXTURE_SIZE), textureData)

        -- Create SurfaceAppearance with the texture as ColorMap
        local surfaceAppearance = Instance.new("SurfaceAppearance")
        surfaceAppearance.Name = "SatelliteTexture"
        surfaceAppearance.ColorMap = Content.fromEditableImage(editImage)
        surfaceAppearance.Parent = meshPart

        game:GetService("CollectionService"):AddTag(meshPart, "ArnisTerrainSatelliteOverlay")
        meshPart.Parent = parent
    end)

    if not ok then
        warn("[TerrainBuilder] Satellite overlay failed: " .. tostring(err))
        return false
    end

    return true
end

--[[
    ResetSatelliteOverlayBudget()

    Resets the budget counter. Useful when unloading chunks frees overlay slots.
]]
function TerrainBuilder.ResetSatelliteOverlayBudget()
    -- No-op: budget is now computed dynamically from tagged parts.
    -- Evicted chunks automatically free their overlay slot when
    -- their MeshPart is destroyed (tag removed from CollectionService).
end

-- ═══════════════════════════════════════════════════════════════════
-- TERRAIN MESH MODE: pre-computed heightfield MeshPart alternative
-- ═══════════════════════════════════════════════════════════════════

-- Telemetry counters for precomputed vs runtime terrain paths.
local terrainMeshTelemetry = {
    precomputedMeshCount = 0,
    runtimeFillBlockCount = 0,
}

function TerrainBuilder.GetMeshTelemetry()
    return {
        precomputedMeshCount = terrainMeshTelemetry.precomputedMeshCount,
        runtimeFillBlockCount = terrainMeshTelemetry.runtimeFillBlockCount,
    }
end

function TerrainBuilder.ResetMeshTelemetry()
    terrainMeshTelemetry.precomputedMeshCount = 0
    terrainMeshTelemetry.runtimeFillBlockCount = 0
end

--- Load a Rust pre-computed terrain mesh (flat arrays) into a single MeshPart.
--- terrainMesh = {
---   vertices = {x,y,z,...},
---   triangles = {v0,v1,v2,...},
---   normals = {nx,ny,nz,...},
---   materialIndices = {idx,...},   -- per-vertex or per-face material index
---   materialPalette = {"Grass", "Sand", ...}  -- index -> Roblox material name
--- }
--- originStuds = Vector3 chunk origin to convert from chunk-local to world space.
--- Rust triangle indices are 0-based; Roblox EditableMesh vertex refs are 1-based.
function TerrainBuilder.BuildPrecomputedMesh(parent, chunk)
    local terrainGrid = chunk.terrain
    if not terrainGrid then
        return false
    end

    local terrainMesh = terrainGrid.terrainMesh
    if not terrainMesh then
        return false
    end

    local verts = decodeF32Array(terrainMesh.verticesB64) or terrainMesh.vertices
    local tris = decodeU32Array(terrainMesh.trianglesB64) or terrainMesh.triangles
    local norms = decodeF32Array(terrainMesh.normalsB64) or terrainMesh.normals
    if not verts or not tris or #verts < 9 or #tris < 3 then
        return false
    end

    local meshOk, mesh = pcall(function()
        return AssetService:CreateEditableMesh()
    end)
    if not meshOk or not mesh then
        warn("[TerrainBuilder] CreateEditableMesh failed for terrain mesh: " .. tostring(mesh))
        return false
    end

    local originStuds = chunk.originStuds
    local ox, oy, oz = originStuds.x, originStuds.y, originStuds.z
    local vertexIds = table.create(#verts / 3)
    -- Load vertices (every 3 floats = one Vector3) with origin offset
    for i = 1, #verts, 3 do
        local vi = (i - 1) / 3 + 1
        local pos = Vector3.new(verts[i] + ox, verts[i + 1] + oy, verts[i + 2] + oz)
        vertexIds[vi] = mesh:AddVertex(pos)
        -- Set normals if available
        if norms and #norms >= i + 2 then
            pcall(function()
                mesh:SetVertexNormal(vertexIds[vi], Vector3.new(norms[i], norms[i + 1], norms[i + 2]))
            end)
        end
    end

    -- Load triangles (convert 0-based Rust indices to 1-based)
    for i = 1, #tris, 3 do
        local v1 = vertexIds[tris[i] + 1]
        local v2 = vertexIds[tris[i + 1] + 1]
        local v3 = vertexIds[tris[i + 2] + 1]
        if v1 and v2 and v3 then
            mesh:AddTriangle(v1, v2, v3)
        end
    end

    local partOk, part = pcall(function()
        return AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
    end)
    if not partOk or not part then
        warn("[TerrainBuilder] CreateMeshPartAsync failed for terrain mesh: " .. tostring(part))
        return false
    end

    -- Resolve material from palette: use first entry as the MeshPart's Material
    local resolvedMaterial = Enum.Material.Grass
    local materialPalette = terrainMesh.materialPalette
    if type(materialPalette) == "table" and #materialPalette > 0 then
        local firstName = materialPalette[1]
        if type(firstName) == "string" then
            local matOk, mat = pcall(function()
                return Enum.Material[firstName]
            end)
            if matOk and mat then
                resolvedMaterial = mat
            end
        end
    end

    part.Name = "TerrainMesh_precomputed"
    part.Material = resolvedMaterial
    part.Color = Color3.fromRGB(85, 120, 70) -- natural terrain base color
    part.Anchored = true
    part.CanCollide = true
    part.CastShadow = true
    pcall(function() part.DoubleSided = true end)
    part:SetAttribute("ArnisPrecomputedMesh", true)
    part:SetAttribute("ArnisTerrainMeshMode", true)
    part.Parent = parent

    return true
end

--- Attempt terrain mesh mode build if enabled and data is available.
--- Returns true if the precomputed mesh was used, false otherwise.
function TerrainBuilder.TryBuildPrecomputedMesh(parent, chunk)
    if not WorldConfig.TerrainMeshMode then
        return false
    end
    if not chunk or not chunk.terrain or not chunk.terrain.terrainMesh then
        return false
    end
    local ok = TerrainBuilder.BuildPrecomputedMesh(parent, chunk)
    if ok then
        terrainMeshTelemetry.precomputedMeshCount += 1
        return true
    end
    terrainMeshTelemetry.runtimeFillBlockCount += 1
    return false
end

return TerrainBuilder
