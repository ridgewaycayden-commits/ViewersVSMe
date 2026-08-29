--!optimize 2
--!native

local ChunkPriority = {}

local FEATURE_KEYS = table.freeze({
    "roads",
    "rails",
    "buildings",
    "water",
    "props",
    "landuse",
    "barriers",
})

local WEIGHTS = table.freeze({
    roads = 4,
    rails = 3,
    buildings = 12,
    water = 2,
    props = 1,
    landuse = 6,
    barriers = 2,
    terrain = 8,
})

local CANONICAL_LAYER_ORDER = table.freeze({
    terrain = 1,
    landuse = 2,
    roads = 3,
    rails = 4,
    barriers = 5,
    buildings = 6,
    water = 7,
    props = 8,
})

local function getListCount(value)
    if type(value) ~= "table" then
        return 0
    end
    return #value
end

local function getChunkLike(chunkLikeOrEntry)
    if type(chunkLikeOrEntry) ~= "table" then
        return nil
    end

    if type(chunkLikeOrEntry.ref) == "table" then
        return chunkLikeOrEntry.ref
    end

    return chunkLikeOrEntry
end

local function getChunkId(chunkLikeOrEntry)
    if type(chunkLikeOrEntry) ~= "table" then
        return ""
    end

    if type(chunkLikeOrEntry.chunkId) == "string" then
        return chunkLikeOrEntry.chunkId
    end

    local chunkLike = getChunkLike(chunkLikeOrEntry)
    if type(chunkLike) == "table" and type(chunkLike.id) == "string" then
        return chunkLike.id
    end

    return ""
end

local function getChunkOrigin(chunkLikeOrEntry)
    local chunkLike = getChunkLike(chunkLikeOrEntry)
    local origin = chunkLike and chunkLike.originStuds or nil
    if type(origin) == "table" then
        return origin
    end
    return {}
end

local function isFootprintBounds(bounds)
    return type(bounds) == "table"
        and type(bounds.minX) == "number"
        and type(bounds.minY) == "number"
        and type(bounds.maxX) == "number"
        and type(bounds.maxY) == "number"
end

local function getBoundsCenterXZ(bounds)
    return (bounds.minX + bounds.maxX) * 0.5, (bounds.minY + bounds.maxY) * 0.5
end

local function getPointToBoundsDistanceSq(point, bounds)
    if typeof(point) ~= "Vector3" or not isFootprintBounds(bounds) then
        return math.huge
    end

    local closestX = math.clamp(point.X, bounds.minX, bounds.maxX)
    local closestZ = math.clamp(point.Z, bounds.minY, bounds.maxY)
    local dx = point.X - closestX
    local dz = point.Z - closestZ
    return dx * dx + dz * dz
end

local function getChunkFootprintBounds(chunkLikeOrEntry)
    if type(chunkLikeOrEntry) ~= "table" then
        return nil
    end

    if isFootprintBounds(chunkLikeOrEntry.streamingFootprintBounds) then
        return chunkLikeOrEntry.streamingFootprintBounds
    end

    if isFootprintBounds(chunkLikeOrEntry.footprintBounds) then
        return chunkLikeOrEntry.footprintBounds
    end

    local chunkLike = getChunkLike(chunkLikeOrEntry)
    if type(chunkLike) ~= "table" then
        return nil
    end

    if isFootprintBounds(chunkLike.streamingFootprintBounds) then
        return chunkLike.streamingFootprintBounds
    end

    if isFootprintBounds(chunkLike.footprintBounds) then
        return chunkLike.footprintBounds
    end

    local origin = getChunkOrigin(chunkLikeOrEntry)
    local originX = origin.x or 0
    local originZ = origin.z or 0
    local subplans = chunkLike.subplans
    if type(subplans) ~= "table" then
        return nil
    end

    local minX, minZ, maxX, maxZ = nil, nil, nil, nil
    for _, subplan in ipairs(subplans) do
        local bounds = type(subplan) == "table" and subplan.bounds or nil
        if isFootprintBounds(bounds) then
            local worldMinX = originX + bounds.minX
            local worldMinZ = originZ + bounds.minY
            local worldMaxX = originX + bounds.maxX
            local worldMaxZ = originZ + bounds.maxY
            if minX == nil or worldMinX < minX then
                minX = worldMinX
            end
            if minZ == nil or worldMinZ < minZ then
                minZ = worldMinZ
            end
            if maxX == nil or worldMaxX > maxX then
                maxX = worldMaxX
            end
            if maxZ == nil or worldMaxZ > maxZ then
                maxZ = worldMaxZ
            end
        end
    end

    if minX == nil then
        return nil
    end

    return {
        minX = minX,
        minY = minZ,
        maxX = maxX,
        maxY = maxZ,
    }
end

local function getChunkCenterXZ(chunkLikeOrEntry, chunkSizeStuds)
    local origin = getChunkOrigin(chunkLikeOrEntry)
    local halfSize = chunkSizeStuds * 0.5
    return (origin.x or 0) + halfSize, (origin.z or 0) + halfSize
end

local function getChunkFootprintCenterXZ(chunkLikeOrEntry, chunkSizeStuds)
    local bounds = getChunkFootprintBounds(chunkLikeOrEntry)
    if isFootprintBounds(bounds) then
        return getBoundsCenterXZ(bounds)
    end

    return getChunkCenterXZ(chunkLikeOrEntry, chunkSizeStuds)
end

local function getChunkFootprintDistanceSq(chunkLikeOrEntry, point, chunkSizeStuds)
    local bounds = getChunkFootprintBounds(chunkLikeOrEntry)
    if isFootprintBounds(bounds) then
        return getPointToBoundsDistanceSq(point, bounds)
    end

    local centerX, centerZ = getChunkFootprintCenterXZ(chunkLikeOrEntry, chunkSizeStuds)
    if typeof(point) ~= "Vector3" then
        return math.huge
    end

    local dx = centerX - point.X
    local dz = centerZ - point.Z
    return dx * dx + dz * dz
end

local function getChunkPriorityAnchorXZ(chunkLikeOrEntry)
    local origin = getChunkOrigin(chunkLikeOrEntry)
    return origin.x or 0, origin.z or 0
end

local function getChunkEntryCenterXZ(chunkLikeOrEntry, chunkSizeStuds)
    if type(chunkLikeOrEntry) == "table" then
        local centerX = chunkLikeOrEntry.centerX
        local centerZ = chunkLikeOrEntry.centerZ
        if type(centerX) == "number" and type(centerZ) == "number" then
            return centerX, centerZ
        end
    end

    return getChunkFootprintCenterXZ(chunkLikeOrEntry, chunkSizeStuds)
end

local function isNonNegativeNumber(value)
    return type(value) == "number" and value >= 0
end

function ChunkPriority.GetFeatureCount(chunkLike)
    local cached = chunkLike and chunkLike.featureCount
    if isNonNegativeNumber(cached) then
        return cached
    end

    if type(chunkLike) ~= "table" then
        return 0
    end

    local total = 0
    for _, key in ipairs(FEATURE_KEYS) do
        total += getListCount(chunkLike[key])
    end
    if chunkLike.terrain ~= nil then
        total += 1
    end

    return total
end

function ChunkPriority.GetStreamingCost(chunkLike)
    local cached = chunkLike and chunkLike.streamingCost
    if isNonNegativeNumber(cached) then
        return cached
    end

    if type(chunkLike) ~= "table" then
        return 0
    end

    local total = 0
    total += getListCount(chunkLike.roads) * WEIGHTS.roads
    total += getListCount(chunkLike.rails) * WEIGHTS.rails
    total += getListCount(chunkLike.buildings) * WEIGHTS.buildings
    total += getListCount(chunkLike.water) * WEIGHTS.water
    total += getListCount(chunkLike.props) * WEIGHTS.props
    total += getListCount(chunkLike.landuse) * WEIGHTS.landuse
    total += getListCount(chunkLike.barriers) * WEIGHTS.barriers
    if chunkLike.terrain ~= nil then
        total += WEIGHTS.terrain
    end

    return total
end

function ChunkPriority.GetEstimatedMemoryCost(chunkLike)
    local cached = chunkLike and chunkLike.estimatedMemoryCost
    if isNonNegativeNumber(cached) then
        return cached
    end

    return ChunkPriority.GetStreamingCost(chunkLike)
end

function ChunkPriority.GetChunkFootprintBounds(chunkLikeOrEntry)
    return getChunkFootprintBounds(chunkLikeOrEntry)
end

function ChunkPriority.GetChunkFootprintDistanceSq(chunkLikeOrEntry, point, chunkSizeStuds)
    return getChunkFootprintDistanceSq(chunkLikeOrEntry, point, chunkSizeStuds)
end

function ChunkPriority.GetChunkFootprintCenterXZ(chunkLikeOrEntry, chunkSizeStuds)
    return getChunkFootprintCenterXZ(chunkLikeOrEntry, chunkSizeStuds)
end

local function makeMetrics(
    chunkLike,
    focusPoint,
    secondaryFocusPoint,
    chunkSizeStuds,
    distanceCenterX,
    distanceCenterZ,
    directionCenterX,
    directionCenterZ,
    streamingCost,
    featureCount,
    estimatedMemoryCost
)
    local resolvedDistanceCenterX, resolvedDistanceCenterZ = distanceCenterX, distanceCenterZ
    if resolvedDistanceCenterX == nil or resolvedDistanceCenterZ == nil then
        resolvedDistanceCenterX, resolvedDistanceCenterZ = getChunkFootprintCenterXZ(chunkLike, chunkSizeStuds)
    end

    local resolvedDirectionCenterX, resolvedDirectionCenterZ = directionCenterX, directionCenterZ
    if resolvedDirectionCenterX == nil or resolvedDirectionCenterZ == nil then
        resolvedDirectionCenterX, resolvedDirectionCenterZ = resolvedDistanceCenterX, resolvedDistanceCenterZ
    end

    local dx = resolvedDirectionCenterX - focusPoint.X
    local dz = resolvedDirectionCenterZ - focusPoint.Z
    local footprintBounds = getChunkFootprintBounds(chunkLike)
    local distSq = nil
    if isFootprintBounds(footprintBounds) then
        distSq = getPointToBoundsDistanceSq(focusPoint, footprintBounds)
    else
        local distanceDx = resolvedDistanceCenterX - focusPoint.X
        local distanceDz = resolvedDistanceCenterZ - focusPoint.Z
        distSq = distanceDx * distanceDx + distanceDz * distanceDz
    end
    local secondaryDistSq = nil
    if typeof(secondaryFocusPoint) == "Vector3" then
        if isFootprintBounds(footprintBounds) then
            secondaryDistSq = getPointToBoundsDistanceSq(secondaryFocusPoint, footprintBounds)
        else
            local secondaryDistanceDx = resolvedDistanceCenterX - secondaryFocusPoint.X
            local secondaryDistanceDz = resolvedDistanceCenterZ - secondaryFocusPoint.Z
            secondaryDistSq = secondaryDistanceDx * secondaryDistanceDx + secondaryDistanceDz * secondaryDistanceDz
        end
        distSq = math.min(distSq, secondaryDistSq)
    end
    local distanceBand = math.floor(math.sqrt(distSq) / math.max(chunkSizeStuds, 1))

    return {
        dx = dx,
        dz = dz,
        distSq = distSq,
        distanceBand = distanceBand,
        streamingCost = if streamingCost ~= nil then streamingCost else ChunkPriority.GetStreamingCost(chunkLike),
        featureCount = if featureCount ~= nil then featureCount else ChunkPriority.GetFeatureCount(chunkLike),
        estimatedMemoryCost = if estimatedMemoryCost ~= nil
            then estimatedMemoryCost
            else ChunkPriority.GetEstimatedMemoryCost(chunkLike),
    }
end

local function normalizeForwardVector(forwardVector)
    if typeof(forwardVector) ~= "Vector3" then
        return nil
    end

    local flat = Vector3.new(forwardVector.X, 0, forwardVector.Z)
    if flat.Magnitude < 0.001 then
        return nil
    end

    return flat.Unit
end

local function getObservedCostKey(chunkId, subplanId)
    if type(chunkId) ~= "string" or chunkId == "" then
        return nil
    end
    if type(subplanId) == "string" and subplanId ~= "" then
        return chunkId .. "::" .. subplanId
    end
    return chunkId
end

local function getObservedCost(observedCostById, chunkId, subplanId)
    if type(observedCostById) ~= "table" then
        return 0
    end

    local subplanKey = getObservedCostKey(chunkId, subplanId)
    if subplanKey ~= nil then
        local observed = observedCostById[subplanKey]
        if isNonNegativeNumber(observed) then
            return observed
        end
    end

    local chunkObserved = observedCostById[chunkId]
    if isNonNegativeNumber(chunkObserved) then
        return chunkObserved
    end

    return 0
end

local function compareMetrics(aId, aMetrics, bId, bMetrics, forwardVector, observedCostById)
    if aMetrics.distanceBand ~= bMetrics.distanceBand then
        return aMetrics.distanceBand < bMetrics.distanceBand
    end

    if aMetrics.distSq ~= bMetrics.distSq then
        return aMetrics.distSq < bMetrics.distSq
    end

    local normalizedForward = normalizeForwardVector(forwardVector)
    if normalizedForward then
        local aForward = aMetrics.dx * normalizedForward.X + aMetrics.dz * normalizedForward.Z
        local bForward = bMetrics.dx * normalizedForward.X + bMetrics.dz * normalizedForward.Z
        local aForwardBucket = if aForward >= 0 then 0 else 1
        local bForwardBucket = if bForward >= 0 then 0 else 1
        if aForwardBucket ~= bForwardBucket then
            return aForwardBucket < bForwardBucket
        end
    end

    if type(observedCostById) == "table" then
        local aObserved = getObservedCost(observedCostById, aId)
        local bObserved = getObservedCost(observedCostById, bId)
        if aObserved ~= bObserved then
            return aObserved < bObserved
        end
    end

    if normalizedForward then
        local aForward = aMetrics.dx * normalizedForward.X + aMetrics.dz * normalizedForward.Z
        local bForward = bMetrics.dx * normalizedForward.X + bMetrics.dz * normalizedForward.Z
        if aForward ~= bForward then
            return aForward > bForward
        end

        local aLateral = math.abs(aMetrics.dx * normalizedForward.Z - aMetrics.dz * normalizedForward.X)
        local bLateral = math.abs(bMetrics.dx * normalizedForward.Z - bMetrics.dz * normalizedForward.X)
        if aLateral ~= bLateral then
            return aLateral < bLateral
        end
    end

    if aMetrics.estimatedMemoryCost ~= bMetrics.estimatedMemoryCost then
        return aMetrics.estimatedMemoryCost < bMetrics.estimatedMemoryCost
    end

    if aMetrics.streamingCost ~= bMetrics.streamingCost then
        return aMetrics.streamingCost < bMetrics.streamingCost
    end

    if aMetrics.featureCount ~= bMetrics.featureCount then
        return aMetrics.featureCount < bMetrics.featureCount
    end

    return aId < bId
end

function ChunkPriority.BuildChunkPriorityKey(
    chunkLikeOrEntry,
    focusPoint,
    secondaryFocusPoint,
    chunkSizeStuds,
    forwardVector,
    observedCostById
)
    local chunkId = getChunkId(chunkLikeOrEntry)
    local anchorX, anchorZ = getChunkPriorityAnchorXZ(chunkLikeOrEntry)
    local centerX, centerZ = getChunkFootprintCenterXZ(chunkLikeOrEntry, chunkSizeStuds)
    local metrics = makeMetrics(
        getChunkLike(chunkLikeOrEntry),
        focusPoint,
        secondaryFocusPoint,
        chunkSizeStuds,
        centerX,
        centerZ,
        anchorX,
        anchorZ
    )

    return {
        chunkId = chunkId,
        dx = metrics.dx,
        dz = metrics.dz,
        distSq = metrics.distSq,
        distanceBand = metrics.distanceBand,
        estimatedMemoryCost = metrics.estimatedMemoryCost,
        streamingCost = metrics.streamingCost,
        featureCount = metrics.featureCount,
        observedCost = getObservedCost(observedCostById, chunkId),
        forwardVector = forwardVector,
    }
end

function ChunkPriority.CompareChunkEntries(
    left,
    right,
    focusPoint,
    secondaryFocusPoint,
    chunkSizeStuds,
    forwardVector,
    observedCostById
)
    return compareMetrics(
        getChunkId(left),
        makeMetrics(
            getChunkLike(left),
            focusPoint,
            secondaryFocusPoint,
            chunkSizeStuds,
            getChunkEntryCenterXZ(left, chunkSizeStuds)
        ),
        getChunkId(right),
        makeMetrics(
            getChunkLike(right),
            focusPoint,
            secondaryFocusPoint,
            chunkSizeStuds,
            getChunkEntryCenterXZ(right, chunkSizeStuds)
        ),
        forwardVector,
        observedCostById
    )
end

function ChunkPriority.SortChunkIdsByPriority(
    chunkIds,
    chunkRefById,
    focusPoint,
    secondaryFocusPoint,
    chunkSizeStuds,
    forwardVector,
    observedCostById
)
    local metricsById = {}
    for _, chunkId in ipairs(chunkIds or {}) do
        local chunkLike = chunkRefById and chunkRefById[chunkId]
        if chunkLike then
            local anchorX, anchorZ = getChunkPriorityAnchorXZ(chunkLike)
            local centerX, centerZ = getChunkFootprintCenterXZ(chunkLike, chunkSizeStuds)
            metricsById[chunkId] = makeMetrics(
                chunkLike,
                focusPoint,
                secondaryFocusPoint,
                chunkSizeStuds,
                centerX,
                centerZ,
                anchorX,
                anchorZ
            )
        end
    end

    table.sort(chunkIds, function(a, b)
        local aMetrics = metricsById[a]
        local bMetrics = metricsById[b]
        if aMetrics == nil or bMetrics == nil then
            return a < b
        end
        return compareMetrics(a, aMetrics, b, bMetrics, forwardVector, observedCostById)
    end)
end

function ChunkPriority.SortChunkEntriesByPriority(
    chunkEntries,
    focusPoint,
    secondaryFocusPoint,
    chunkSizeStuds,
    forwardVector,
    observedCostById
)
    local metricsById = {}
    for _, chunkEntry in ipairs(chunkEntries or {}) do
        local chunkLike = chunkEntry and chunkEntry.ref
        local chunkId = chunkLike and chunkLike.id
        if type(chunkId) == "string" then
            metricsById[chunkId] = makeMetrics(
                chunkLike,
                focusPoint,
                secondaryFocusPoint,
                chunkSizeStuds,
                getChunkEntryCenterXZ(chunkEntry, chunkSizeStuds)
            )
        end
    end

    table.sort(chunkEntries, function(a, b)
        local aId = a and a.ref and a.ref.id or ""
        local bId = b and b.ref and b.ref.id or ""
        local aMetrics = metricsById[aId]
        local bMetrics = metricsById[bId]
        if aMetrics == nil or bMetrics == nil then
            return aId < bId
        end
        return compareMetrics(aId, aMetrics, bId, bMetrics, forwardVector, observedCostById)
    end)
end

function ChunkPriority.GetCanonicalLayerRank(layerOrWorkItem)
    local layer = layerOrWorkItem
    if type(layerOrWorkItem) == "table" then
        local subplan = layerOrWorkItem.subplan
        layer = subplan and subplan.layer or nil
    end

    return CANONICAL_LAYER_ORDER[layer] or math.huge
end

local function getSubplanMetrics(workItem, focusPoint, secondaryFocusPoint, chunkSizeStuds)
    local chunkLike = getChunkLike(workItem)
    local chunkId = getChunkId(workItem)
    local subplan = type(workItem) == "table" and workItem.subplan or nil
    local bounds = type(subplan) == "table" and subplan.bounds or nil
    local origin = getChunkOrigin(workItem)

    local centerX, centerZ
    if type(bounds) == "table" then
        centerX = (origin.x or 0) + (((bounds.minX or 0) + (bounds.maxX or 0)) * 0.5)
        centerZ = (origin.z or 0) + (((bounds.minY or 0) + (bounds.maxY or 0)) * 0.5)
    end

    local metricChunkLike = chunkLike
    if type(bounds) == "table" then
        metricChunkLike = {
            originStuds = origin,
            streamingFootprintBounds = {
                minX = (origin.x or 0) + (bounds.minX or 0),
                minY = (origin.z or 0) + (bounds.minY or 0),
                maxX = (origin.x or 0) + (bounds.maxX or 0),
                maxY = (origin.z or 0) + (bounds.maxY or 0),
            },
        }
    end

    local streamingCost = if type(subplan) == "table" and isNonNegativeNumber(subplan.streamingCost)
        then subplan.streamingCost
        else nil
    local featureCount = if type(subplan) == "table" and isNonNegativeNumber(subplan.featureCount)
        then subplan.featureCount
        else nil
    local estimatedMemoryCost = if type(subplan) == "table" and isNonNegativeNumber(subplan.estimatedMemoryCost)
        then subplan.estimatedMemoryCost
        else nil

    return chunkId,
        subplan,
        makeMetrics(
            metricChunkLike,
            focusPoint,
            secondaryFocusPoint,
            chunkSizeStuds,
            centerX,
            centerZ,
            centerX,
            centerZ,
            streamingCost,
            featureCount,
            estimatedMemoryCost
        )
end

function ChunkPriority.GetObservedCostKey(chunkId, subplanId)
    return getObservedCostKey(chunkId, subplanId)
end

function ChunkPriority.BuildPriorityKey(
    workItem,
    focusPoint,
    secondaryFocusPoint,
    chunkSizeStuds,
    forwardVector,
    observedCostById,
    sourceOrder
)
    local chunkId, subplan, metrics = getSubplanMetrics(workItem, focusPoint, secondaryFocusPoint, chunkSizeStuds)

    return {
        chunkId = chunkId,
        dx = metrics.dx,
        dz = metrics.dz,
        distSq = metrics.distSq,
        distanceBand = metrics.distanceBand,
        estimatedMemoryCost = metrics.estimatedMemoryCost,
        streamingCost = metrics.streamingCost,
        featureCount = metrics.featureCount,
        observedCost = getObservedCost(observedCostById, chunkId, type(subplan) == "table" and subplan.id or nil),
        layerRank = ChunkPriority.GetCanonicalLayerRank(workItem),
        sourceOrder = sourceOrder,
        subplanId = type(subplan) == "table" and subplan.id or "",
        highDetailWholeChunkPriority = type(workItem) == "table" and workItem.highDetailWholeChunkPriority == true,
        highDetailStructurePriority = type(workItem) == "table" and workItem.highDetailStructurePriority == true,
        forwardVector = forwardVector,
    }
end

local function compareWorkItemKeys(leftKey, rightKey)
    if leftKey.highDetailWholeChunkPriority ~= rightKey.highDetailWholeChunkPriority then
        return leftKey.highDetailWholeChunkPriority == true
    end

    if leftKey.highDetailStructurePriority ~= rightKey.highDetailStructurePriority then
        return leftKey.highDetailStructurePriority == true
    end

    if leftKey.chunkId == rightKey.chunkId and leftKey.layerRank ~= rightKey.layerRank then
        return leftKey.layerRank < rightKey.layerRank
    end

    local normalizedForward = normalizeForwardVector(leftKey.forwardVector)
    local leftIsWholeChunk = leftKey.subplanId == ""
    local rightIsWholeChunk = rightKey.subplanId == ""
    local bothWholeChunks = leftIsWholeChunk and rightIsWholeChunk

    if bothWholeChunks and leftKey.chunkId ~= rightKey.chunkId and leftKey.sourceOrder ~= rightKey.sourceOrder then
        -- Whole-chunk work is already emitted from chunk-priority order. Preserve that admission order here
        -- so the work-item sorter does not reshuffle chunk-level scheduling decisions.
        return leftKey.sourceOrder < rightKey.sourceOrder
    end

    if leftKey.distanceBand ~= rightKey.distanceBand then
        return leftKey.distanceBand < rightKey.distanceBand
    end

    if bothWholeChunks and leftKey.distSq ~= rightKey.distSq then
        return leftKey.distSq < rightKey.distSq
    end

    if normalizedForward then
        local leftForward = leftKey.dx * normalizedForward.X + leftKey.dz * normalizedForward.Z
        local rightForward = rightKey.dx * normalizedForward.X + rightKey.dz * normalizedForward.Z
        local leftForwardBucket = if leftForward >= 0 then 0 else 1
        local rightForwardBucket = if rightForward >= 0 then 0 else 1
        if leftForwardBucket ~= rightForwardBucket then
            return leftForwardBucket < rightForwardBucket
        end
        if leftForward ~= rightForward then
            return leftForward > rightForward
        end
    end

    if leftKey.distSq ~= rightKey.distSq then
        return leftKey.distSq < rightKey.distSq
    end

    if leftKey.layerRank ~= rightKey.layerRank then
        return leftKey.layerRank < rightKey.layerRank
    end

    if leftKey.observedCost ~= rightKey.observedCost then
        return leftKey.observedCost < rightKey.observedCost
    end

    if normalizedForward then
        local leftLateral = math.abs(leftKey.dx * normalizedForward.Z - leftKey.dz * normalizedForward.X)
        local rightLateral = math.abs(rightKey.dx * normalizedForward.Z - rightKey.dz * normalizedForward.X)
        if leftLateral ~= rightLateral then
            return leftLateral < rightLateral
        end
    end

    if leftKey.estimatedMemoryCost ~= rightKey.estimatedMemoryCost then
        return leftKey.estimatedMemoryCost < rightKey.estimatedMemoryCost
    end

    if leftKey.streamingCost ~= rightKey.streamingCost then
        return leftKey.streamingCost < rightKey.streamingCost
    end

    if leftKey.featureCount ~= rightKey.featureCount then
        return leftKey.featureCount < rightKey.featureCount
    end

    if leftKey.chunkId ~= rightKey.chunkId then
        return leftKey.chunkId < rightKey.chunkId
    end

    if leftKey.sourceOrder ~= rightKey.sourceOrder then
        return leftKey.sourceOrder < rightKey.sourceOrder
    end

    return leftKey.subplanId < rightKey.subplanId
end

function ChunkPriority.CompareWorkItems(
    left,
    right,
    focusPoint,
    secondaryFocusPoint,
    chunkSizeStuds,
    forwardVector,
    observedCostById
)
    return compareWorkItemKeys(
        ChunkPriority.BuildPriorityKey(
            left,
            focusPoint,
            secondaryFocusPoint,
            chunkSizeStuds,
            forwardVector,
            observedCostById,
            0
        ),
        ChunkPriority.BuildPriorityKey(
            right,
            focusPoint,
            secondaryFocusPoint,
            chunkSizeStuds,
            forwardVector,
            observedCostById,
            0
        )
    )
end

function ChunkPriority.SortWorkItems(
    workItems,
    focusPoint,
    secondaryFocusPoint,
    chunkSizeStuds,
    forwardVector,
    observedCostById
)
    local decorated = table.create(#(workItems or {}))
    for index, workItem in ipairs(workItems or {}) do
        decorated[index] = {
            item = workItem,
            sourceOrder = index,
        }
    end

    table.sort(decorated, function(left, right)
        return compareWorkItemKeys(
            ChunkPriority.BuildPriorityKey(
                left.item,
                focusPoint,
                secondaryFocusPoint,
                chunkSizeStuds,
                forwardVector,
                observedCostById,
                left.sourceOrder
            ),
            ChunkPriority.BuildPriorityKey(
                right.item,
                focusPoint,
                secondaryFocusPoint,
                chunkSizeStuds,
                forwardVector,
                observedCostById,
                right.sourceOrder
            )
        )
    end)

    for index, entry in ipairs(decorated) do
        workItems[index] = entry.item
    end

    return workItems
end

return ChunkPriority
