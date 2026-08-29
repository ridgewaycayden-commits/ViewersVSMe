local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ImportService = require(script.Parent)
local ChunkLoader = require(script.Parent.ChunkLoader)
local ChunkPriority = require(script.Parent.ChunkPriority)
local ImportSignatures = require(script.Parent.ImportSignatures)
local MemoryGuardrail = require(script.Parent.MemoryGuardrail)
local SubplanRollout = require(script.Parent.SubplanRollout)
local DefaultWorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local Logger = require(ReplicatedStorage.Shared.Logger)
local WorldProbeGeometry = require(ReplicatedStorage.Shared.WorldProbeGeometry)

local StreamingService = {}

local streamingManifest = nil
local streamingChunkRefs = nil
local streamingChunkRefsById = nil
local streamingChunkRefsByOrigin = nil
local streamingOptions = nil
local streamingChunkIndex = nil
local streamingResolvedRings = nil
local heartbeatConn = nil
local lastUpdate = 0
local DEFAULT_UPDATE_INTERVAL = 0.25 -- seconds between distance checks
local HYSTERESIS_RATIO = 0.15

-- LOD detail toggle: runs at a lower frequency to keep per-frame cost cheap.
local LOD_UPDATE_INTERVAL = 2 -- seconds
local LOD_MOVEMENT_REFRESH_THRESHOLD_STUDS = 24

-- Building LOD re-import: detail rank for comparison (higher = more detail).
local BUILDING_LOD_DETAIL_RANK = {
    minimal = 1,
    reduced = 2,
    full = 3,
}
local lastLODUpdate = 0

-- Ring-based transparency: far-ring chunks get a slight transparency boost
-- to sell atmospheric depth without per-ring fog (Roblox Atmosphere is global-only).
local FAR_RING_TRANSPARENCY_BOOST = 0.15
local MID_RING_TRANSPARENCY_BOOST = 0.05

local LOD_HIGH = "High"
local LOD_LOW = "Low"

-- Resolve the building LOD level (full/reduced/minimal) for a given streaming ring.
local function resolveBuildingLodLevel(ringName, config)
    local policy = type(config) == "table" and config.BuildingLodPolicy or nil
    if type(policy) ~= "table" then
        return "full"
    end
    if ringName == "near" then
        return policy.NearRingLod or "full"
    elseif ringName == "mid" then
        return policy.MidRingLod or "full"
    elseif ringName == "far" then
        return policy.FarRingLod or "full"
    end
    return "full"
end

-- Registry of chunkId -> current LOD level
local loadedChunkLods = {}
-- Registry of chunkId -> current ring name ("near" | "mid" | "far") so the
-- per-ring memory guardrail can attribute resident bytes back to a ring and
-- evict from the right pool when a ring exceeds its budget. Far-ring minimal
-- LOD chunks must never be allowed to compete with near-ring full-detail
-- chunks for the same memory dollars.
local loadedChunkRings = {}
-- Chunk not-desired hysteresis: chunkId -> os.clock() timestamp of the
-- FIRST tick that chunk transitioned from desired to not-desired. While
-- a chunk is still in the desired set the stamp is cleared. Only when
-- the stamp age exceeds STREAMING_EVICTION_COOLDOWN_SECONDS does the
-- not-desired sweep actually unload the chunk.
--
-- Why: a moving player crosses chunk boundaries repeatedly, and on each
-- recompute the "just left" chunks flip to not-desired for one tick
-- before the next recompute brings them back. Without hysteresis the
-- sweep unloads them immediately → next tick re-imports them → visible
-- flicker (admit/evict churn). The client_flicker telemetry family
-- measures this as chunkThrashCount; the walk harness captured 88
-- thrashes per 25s walk before this cooldown landed. A 3s window is
-- enough to absorb the typical re-desire bounce without inflating
-- steady-state memory use for a chunk that's truly left behind.
local chunkFirstNotDesiredAt = {}
-- Post-osm2world: chunks now take 2-3s to fetch (3.3MB avg). A 3s cooldown
-- means a chunk can be evicted right as it finishes loading. 8s ensures a
-- chunk survives at least one full streaming update cycle after admission.
local STREAMING_EVICTION_COOLDOWN_SECONDS = 8.0
-- Registry of chunkId -> building LOD level at which chunk geometry was imported
local importedBuildingLodById = {}
-- Registry of chunkId -> true while an import work item is queued/in-flight.
-- Prevents repeated re-queuing of the same chunk across consecutive Update()
-- ticks while a prior import (especially an LOD upgrade) has not completed.
local inflightChunkImports = {}
-- Cumulative count of LOD upgrade re-imports since streaming started
local lodUpgradeCount = 0
local lodConfigCache = setmetatable({}, { __mode = "k" })
local lodGroupFootprintBoundsCache = setmetatable({}, { __mode = "k" })
local streamingChunkOptionsByLod = nil
local streamingLastFocalPoint = nil
local streamingLastFocalAt = nil
local streamingPreferredForward = nil
-- Aircraft / high-velocity streaming: per-update velocity-class state. Declared
-- here at top scope so resetStreamingResidencyTelemetry/updateStreamingResidencyTelemetry
-- can read them as upvalues even though they live earlier in the file than
-- resolveSchedulerFocusPoint where they are written.
local streamingVelocityMagnitude = 0
local streamingVelocityClass = "walking"
local streamingAdaptiveLookaheadStuds = 0
local streamingForceMinimalLodForPrefetch = false
local observedChunkImportMsById = {}
local streamingSubplanRollout = nil
local streamingMemoryGuardrail = nil
local streamingResidentEstimatedCostById = {}
local streamingUpdateInProgress = false
local streamingLastPrefetchReason = ""
local streamingLastEvictionReason = ""
local getChunkCenter

-- ─── MULTIPLAYER STREAMING STATE ───
-- Per-player focus registry. Keyed by player UserId so it survives Player
-- object reference churn during character respawn / leave races. Each entry
-- holds the most recently reported camera position, optional velocity, and
-- the wall-clock timestamp the report landed so we can age out stale focuses
-- when a client stops reporting (network drop, disconnect, etc.).
--
-- The single-player path never reads this registry; it remains entirely
-- opt-in via config.MultiplayerStreaming.enabled. The server-authoritative
-- path consults this registry inside Update() to compute the union of
-- desired chunks across all players and to set per-chunk LOD as the maximum
-- demanded by any player.
local playerFocusRegistry = {}
local playerLifecycleConnections = nil
local clientPositionRemote = nil
local clientPositionRemoteConnection = nil
local CLIENT_POSITION_REMOTE_NAME = "ArnisClientStreamingPosition"

local function isMultiplayerStreamingEnabled(config)
    if type(config) ~= "table" then
        return false
    end
    local mp = config.MultiplayerStreaming
    if type(mp) ~= "table" then
        return false
    end
    return mp.enabled == true
end

local function resolveMultiplayerConfig(config)
    if type(config) == "table" and type(config.MultiplayerStreaming) == "table" then
        return config.MultiplayerStreaming
    end
    return nil
end

local MEMORY_GUARDRAIL_ATTR_PREFIX = "ArnisStreamingMemoryGuardrail"
local HOST_PROBE_AVAILABLE_ATTR = "ArnisStreamingHostProbeAvailableBytes"
local HOST_PROBE_PRESSURE_ATTR = "ArnisStreamingHostProbePressureLevel"
local DEFAULT_WORLD_ROOT_NAME = "GeneratedWorld"
local STREAMING_RING_ORDER = { "near", "mid", "far" }
local STARTUP_NEARBY_BUILDING_RADIUS = 260
local STARTUP_NEARBY_WALL_RADIUS = 180
local STARTUP_OVERHEAD_ROOF_RADIUS = 220
local STARTUP_OVERHEAD_MIN_DELTA_Y = 12

local function normalizePositiveNumber(value)
    if type(value) ~= "number" then
        return nil
    end
    if value <= 0 then
        return nil
    end
    return value
end

local function normalizeNonNegativeNumber(value)
    if type(value) ~= "number" or value < 0 then
        return 0
    end
    return value
end

local function normalizePositiveInteger(value, fallback)
    if type(value) ~= "number" or value < 1 then
        return fallback
    end
    return math.max(1, math.floor(value))
end

local function buildChunkRefById(chunkRefs)
    local byId = {}
    for _, chunkRef in ipairs(chunkRefs or {}) do
        if type(chunkRef) == "table" and type(chunkRef.id) == "string" and chunkRef.id ~= "" then
            byId[chunkRef.id] = chunkRef
        end
    end
    return byId
end

local function makeChunkOriginKey(x, z)
    return ("%s:%s"):format(tostring(x or 0), tostring(z or 0))
end

local function buildChunkRefByOrigin(chunkRefs)
    local byOrigin = {}
    for _, chunkRef in ipairs(chunkRefs or {}) do
        local origin = chunkRef.originStuds or {}
        byOrigin[makeChunkOriginKey(origin.x or 0, origin.z or 0)] = chunkRef
    end
    return byOrigin
end

local function resolveStreamingRings(config)
    local highRadius = normalizePositiveNumber(config.HighDetailRadius) or 1024
    local targetRadius = normalizePositiveNumber(config.StreamingTargetRadius) or math.max(highRadius, 2048)
    local guardrailBudget = normalizeNonNegativeNumber(
        type(config.MemoryGuardrails) == "table" and config.MemoryGuardrails.EstimatedBudgetBytes or 0
    )
    local configuredRings = if type(config.StreamingRings) == "table" then config.StreamingRings else {}
    local fallbackMidRadius = math.max(highRadius, (highRadius + targetRadius) * 0.5)
    local fallbackBudgets = {
        near = if guardrailBudget > 0 then math.floor(guardrailBudget * 0.4) else 0,
        mid = if guardrailBudget > 0 then math.floor(guardrailBudget * 0.35) else 0,
        far = if guardrailBudget > 0 then math.floor(guardrailBudget * 0.25) else 0,
    }
    local fallbackChunkCounts = {
        near = 64,
        mid = 96,
        far = 128,
    }
    local fallbackRadii = {
        near = highRadius,
        mid = fallbackMidRadius,
        far = targetRadius,
    }
    local resolved = {}
    local previousRadius = 0

    for _, ringName in ipairs(STREAMING_RING_ORDER) do
        local ringConfig = if type(configuredRings[ringName]) == "table" then configuredRings[ringName] else {}
        local resolvedRadius = normalizePositiveNumber(ringConfig.MaxRadiusStuds) or fallbackRadii[ringName]
        resolvedRadius = math.max(previousRadius, resolvedRadius)
        previousRadius = resolvedRadius

        local configuredBudget = ringConfig.EstimatedBudgetBytes
        local resolvedBudget = if type(configuredBudget) == "number" and configuredBudget >= 0
            then configuredBudget
            else fallbackBudgets[ringName]

        resolved[ringName] = {
            Name = ringName,
            MaxRadiusStuds = resolvedRadius,
            MaxRadiusSq = resolvedRadius * resolvedRadius,
            EstimatedBudgetBytes = normalizeNonNegativeNumber(resolvedBudget),
            MaxChunkCount = normalizePositiveInteger(ringConfig.MaxChunkCount, fallbackChunkCounts[ringName]),
        }
    end

    return resolved
end

local function setMemoryGuardrailTelemetry(snapshot, deferredAdmissions, residentCost, inFlightCost)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "Enabled", snapshot.enabled)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "State", snapshot.state)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "BudgetBytes", snapshot.budgetBytes)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "ResidentEstimatedCost", residentCost)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "InFlightEstimatedCost", inFlightCost)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "ProjectedUsageBytes", snapshot.projectedUsageBytes)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "ResumeThresholdBytes", snapshot.resumeThresholdBytes)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "HostProbeEnabled", snapshot.hostProbe.enabled)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "HostAvailableBytes", snapshot.hostProbe.availableBytes)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "HostPressureLevel", snapshot.hostProbe.pressureLevel)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "HostCritical", snapshot.hostProbe.critical)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "DeferredAdmissions", deferredAdmissions)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "LastPauseReason", snapshot.pauseReason)
end

local function clearMemoryGuardrailTelemetry()
    setMemoryGuardrailTelemetry({
        enabled = false,
        state = "active",
        budgetBytes = 0,
        projectedUsageBytes = 0,
        resumeThresholdBytes = 0,
        residentBytes = 0,
        inFlightBytes = 0,
        pauseReason = nil,
        hostProbe = {
            enabled = false,
            availableBytes = nil,
            pressureLevel = nil,
            critical = false,
        },
    }, 0, 0, 0)
end

local function resetStreamingResidencyTelemetry()
    Workspace:SetAttribute("ArnisStreamingSchedulerState", "idle")
    Workspace:SetAttribute("ArnisStreamingLoadedChunkCount", 0)
    Workspace:SetAttribute("ArnisStreamingDesiredChunkCount", 0)
    Workspace:SetAttribute("ArnisStreamingCandidateChunkCount", 0)
    Workspace:SetAttribute("ArnisStreamingProcessedWorkItems", 0)
    Workspace:SetAttribute("ArnisStreamingLastFocalX", 0)
    Workspace:SetAttribute("ArnisStreamingLastFocalZ", 0)
    Workspace:SetAttribute("ArnisStreamingPredictedFocalX", 0)
    Workspace:SetAttribute("ArnisStreamingPredictedFocalZ", 0)
    Workspace:SetAttribute("ArnisStreamingMovementDeltaStuds", 0)
    Workspace:SetAttribute("ArnisStreamingMovementLookaheadStuds", 0)
    Workspace:SetAttribute("ArnisStreamingVelocityMagnitude", 0)
    Workspace:SetAttribute("ArnisStreamingAdaptiveLookaheadStuds", 0)
    Workspace:SetAttribute("ArnisStreamingVelocityClass", "walking")
    Workspace:SetAttribute("ArnisStreamingRingNearResidentChunkCount", 0)
    Workspace:SetAttribute("ArnisStreamingRingMidResidentChunkCount", 0)
    Workspace:SetAttribute("ArnisStreamingRingFarResidentChunkCount", 0)
    Workspace:SetAttribute("ArnisStreamingRingNearDesiredChunkCount", 0)
    Workspace:SetAttribute("ArnisStreamingRingMidDesiredChunkCount", 0)
    Workspace:SetAttribute("ArnisStreamingRingFarDesiredChunkCount", 0)
    Workspace:SetAttribute("ArnisStreamingRingNearResidentEstimatedCost", 0)
    Workspace:SetAttribute("ArnisStreamingRingMidResidentEstimatedCost", 0)
    Workspace:SetAttribute("ArnisStreamingRingFarResidentEstimatedCost", 0)
    Workspace:SetAttribute("ArnisStreamingRingNearDesiredEstimatedCost", 0)
    Workspace:SetAttribute("ArnisStreamingRingMidDesiredEstimatedCost", 0)
    Workspace:SetAttribute("ArnisStreamingRingFarDesiredEstimatedCost", 0)
    Workspace:SetAttribute("ArnisStreamingRingNearBudgetBytes", 0)
    Workspace:SetAttribute("ArnisStreamingRingMidBudgetBytes", 0)
    Workspace:SetAttribute("ArnisStreamingRingFarBudgetBytes", 0)
    Workspace:SetAttribute("ArnisStreamingRingNearMaxChunkCount", 0)
    Workspace:SetAttribute("ArnisStreamingRingMidMaxChunkCount", 0)
    Workspace:SetAttribute("ArnisStreamingRingFarMaxChunkCount", 0)
    Workspace:SetAttribute("ArnisStreamingRingNearResidentBytes", 0)
    Workspace:SetAttribute("ArnisStreamingRingMidResidentBytes", 0)
    Workspace:SetAttribute("ArnisStreamingRingFarResidentBytes", 0)
    Workspace:SetAttribute("ArnisStreamingRingNearPressureLevel", 0)
    Workspace:SetAttribute("ArnisStreamingRingMidPressureLevel", 0)
    Workspace:SetAttribute("ArnisStreamingRingFarPressureLevel", 0)
    Workspace:SetAttribute("ArnisStreamingRingNearOverBudget", false)
    Workspace:SetAttribute("ArnisStreamingRingMidOverBudget", false)
    Workspace:SetAttribute("ArnisStreamingRingFarOverBudget", false)
    Workspace:SetAttribute("ArnisStreamingRingNearDeferredAdmissions", 0)
    Workspace:SetAttribute("ArnisStreamingRingMidDeferredAdmissions", 0)
    Workspace:SetAttribute("ArnisStreamingRingFarDeferredAdmissions", 0)
    Workspace:SetAttribute("ArnisStreamingQueuedEstimatedCost", 0)
    Workspace:SetAttribute("ArnisStreamingQueuedWorkItemCount", 0)
    Workspace:SetAttribute("ArnisStreamingEvictedEstimatedCost", 0)
    Workspace:SetAttribute("ArnisStreamingEvictedChunkCount", 0)
    Workspace:SetAttribute("ArnisStreamingLastPrefetchReason", "")
    Workspace:SetAttribute("ArnisStreamingLastEvictionReason", "")
    Workspace:SetAttribute("ArnisStreamingLodUpgradeCount", 0)
end

local function getResidentEstimatedCostForChunkId(chunkId)
    local prefix = chunkId .. "::"
    local total = 0
    for residentKey, cost in pairs(streamingResidentEstimatedCostById) do
        if residentKey == chunkId or string.sub(residentKey, 1, #prefix) == prefix then
            total += cost
        end
    end
    return total
end

-- Compute current resident bytes per ring by attributing each loaded chunk's
-- estimated cost to the ring it currently belongs to (per loadedChunkRings).
-- Chunks that have not yet been classified into a ring (e.g. a brand-new
-- candidate that was admitted earlier this tick before classification) fall
-- through into an "unclassified" bucket which is intentionally not reported.
local function computeRingResidentBytes()
    local bytes = { near = 0, mid = 0, far = 0 }
    for chunkId, ringName in pairs(loadedChunkRings) do
        if ringName == "near" or ringName == "mid" or ringName == "far" then
            bytes[ringName] += getResidentEstimatedCostForChunkId(chunkId)
        end
    end
    return bytes
end

local function computeRingPressureLevel(residentBytes, budgetBytes)
    if type(budgetBytes) ~= "number" or budgetBytes <= 0 then
        return 0
    end
    local level = residentBytes / budgetBytes
    if level < 0 then
        return 0
    end
    if level > 1 then
        return 1
    end
    return level
end

local function getChunkRingName(distSq, resolvedRings)
    for _, ringName in ipairs(STREAMING_RING_ORDER) do
        local ring = resolvedRings and resolvedRings[ringName] or nil
        if ring and distSq <= ring.MaxRadiusSq then
            return ringName
        end
    end
    return nil
end

local function buildStreamingRingTelemetry(playerPos, resolvedRings)
    local telemetry = {
        near = { residentChunkCount = 0, residentEstimatedCost = 0 },
        mid = { residentChunkCount = 0, residentEstimatedCost = 0 },
        far = { residentChunkCount = 0, residentEstimatedCost = 0 },
    }

    if typeof(playerPos) ~= "Vector3" or type(streamingChunkRefsById) ~= "table" then
        return telemetry
    end

    for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks(streamingOptions.worldRootName)) do
        local chunkRef = streamingChunkRefsById[chunkId]
        if chunkRef then
            local chunkFootprintDistanceSq =
                ChunkPriority.GetChunkFootprintDistanceSq(chunkRef, playerPos, streamingOptions.config.ChunkSizeStuds)
            local ringName = getChunkRingName(chunkFootprintDistanceSq, resolvedRings)
            if ringName then
                local ringTelemetry = telemetry[ringName]
                ringTelemetry.residentChunkCount += 1
                ringTelemetry.residentEstimatedCost += getResidentEstimatedCostForChunkId(chunkId)
            end
        end
    end

    return telemetry
end

local function updateStreamingResidencyTelemetry(
    playerPos,
    predictedFocalPoint,
    movementDeltaStuds,
    movementLookaheadStuds,
    resolvedRings,
    desiredRingStats,
    candidateChunkEntries,
    desiredChunkCount,
    processedWorkItems,
    queuedEstimatedCost,
    queuedWorkItemCount,
    evictedEstimatedCost,
    evictedChunkCount,
    lastPrefetchReason,
    lastEvictionReason,
    schedulerState
)
    local focalX = 0
    local focalZ = 0
    if typeof(playerPos) == "Vector3" then
        focalX = playerPos.X
        focalZ = playerPos.Z
    end
    local predictedFocalX = focalX
    local predictedFocalZ = focalZ
    if typeof(predictedFocalPoint) == "Vector3" then
        predictedFocalX = predictedFocalPoint.X
        predictedFocalZ = predictedFocalPoint.Z
    end

    local ringBudgets = resolvedRings or {}
    local ringDesiredStats = desiredRingStats or {}
    local worldRootName = if type(streamingOptions) == "table"
            and type(streamingOptions.worldRootName) == "string"
            and streamingOptions.worldRootName ~= ""
        then streamingOptions.worldRootName
        else DEFAULT_WORLD_ROOT_NAME
    Workspace:SetAttribute("ArnisStreamingLoadedChunkCount", #ChunkLoader.ListLoadedChunks(worldRootName))
    Workspace:SetAttribute("ArnisStreamingSchedulerState", schedulerState or "active")
    Workspace:SetAttribute("ArnisStreamingCandidateChunkCount", #candidateChunkEntries)
    Workspace:SetAttribute("ArnisStreamingDesiredChunkCount", desiredChunkCount)
    Workspace:SetAttribute("ArnisStreamingProcessedWorkItems", processedWorkItems)
    Workspace:SetAttribute("ArnisStreamingLastFocalX", focalX)
    Workspace:SetAttribute("ArnisStreamingLastFocalZ", focalZ)
    Workspace:SetAttribute("ArnisStreamingPredictedFocalX", predictedFocalX)
    Workspace:SetAttribute("ArnisStreamingPredictedFocalZ", predictedFocalZ)
    Workspace:SetAttribute("ArnisStreamingMovementDeltaStuds", normalizeNonNegativeNumber(movementDeltaStuds))
    Workspace:SetAttribute("ArnisStreamingMovementLookaheadStuds", normalizeNonNegativeNumber(movementLookaheadStuds))
    -- Aircraft / high-velocity streaming telemetry: published every update so
    -- the harness can prove velocity-adaptive lookahead is firing for jetpacks,
    -- planes, parachutes, etc.
    Workspace:SetAttribute("ArnisStreamingVelocityMagnitude", normalizeNonNegativeNumber(streamingVelocityMagnitude))
    Workspace:SetAttribute(
        "ArnisStreamingAdaptiveLookaheadStuds",
        normalizeNonNegativeNumber(streamingAdaptiveLookaheadStuds)
    )
    Workspace:SetAttribute("ArnisStreamingVelocityClass", streamingVelocityClass or "walking")
    local ringTelemetry = buildStreamingRingTelemetry(playerPos, streamingResolvedRings)
    Workspace:SetAttribute("ArnisStreamingRingNearResidentChunkCount", ringTelemetry.near.residentChunkCount)
    Workspace:SetAttribute("ArnisStreamingRingMidResidentChunkCount", ringTelemetry.mid.residentChunkCount)
    Workspace:SetAttribute("ArnisStreamingRingFarResidentChunkCount", ringTelemetry.far.residentChunkCount)
    Workspace:SetAttribute(
        "ArnisStreamingRingNearDesiredChunkCount",
        normalizeNonNegativeNumber(ringDesiredStats.near and ringDesiredStats.near.chunkCount or 0)
    )
    Workspace:SetAttribute(
        "ArnisStreamingRingMidDesiredChunkCount",
        normalizeNonNegativeNumber(ringDesiredStats.mid and ringDesiredStats.mid.chunkCount or 0)
    )
    Workspace:SetAttribute(
        "ArnisStreamingRingFarDesiredChunkCount",
        normalizeNonNegativeNumber(ringDesiredStats.far and ringDesiredStats.far.chunkCount or 0)
    )
    Workspace:SetAttribute("ArnisStreamingRingNearResidentEstimatedCost", ringTelemetry.near.residentEstimatedCost)
    Workspace:SetAttribute("ArnisStreamingRingMidResidentEstimatedCost", ringTelemetry.mid.residentEstimatedCost)
    Workspace:SetAttribute("ArnisStreamingRingFarResidentEstimatedCost", ringTelemetry.far.residentEstimatedCost)
    Workspace:SetAttribute(
        "ArnisStreamingRingNearDesiredEstimatedCost",
        normalizeNonNegativeNumber(ringDesiredStats.near and ringDesiredStats.near.estimatedCost or 0)
    )
    Workspace:SetAttribute(
        "ArnisStreamingRingMidDesiredEstimatedCost",
        normalizeNonNegativeNumber(ringDesiredStats.mid and ringDesiredStats.mid.estimatedCost or 0)
    )
    Workspace:SetAttribute(
        "ArnisStreamingRingFarDesiredEstimatedCost",
        normalizeNonNegativeNumber(ringDesiredStats.far and ringDesiredStats.far.estimatedCost or 0)
    )
    Workspace:SetAttribute(
        "ArnisStreamingRingNearBudgetBytes",
        normalizeNonNegativeNumber(ringBudgets.near and ringBudgets.near.EstimatedBudgetBytes or 0)
    )
    Workspace:SetAttribute(
        "ArnisStreamingRingMidBudgetBytes",
        normalizeNonNegativeNumber(ringBudgets.mid and ringBudgets.mid.EstimatedBudgetBytes or 0)
    )
    Workspace:SetAttribute(
        "ArnisStreamingRingFarBudgetBytes",
        normalizeNonNegativeNumber(ringBudgets.far and ringBudgets.far.EstimatedBudgetBytes or 0)
    )
    Workspace:SetAttribute(
        "ArnisStreamingRingNearMaxChunkCount",
        normalizeNonNegativeNumber(ringBudgets.near and ringBudgets.near.MaxChunkCount or 0)
    )
    Workspace:SetAttribute(
        "ArnisStreamingRingMidMaxChunkCount",
        normalizeNonNegativeNumber(ringBudgets.mid and ringBudgets.mid.MaxChunkCount or 0)
    )
    Workspace:SetAttribute(
        "ArnisStreamingRingFarMaxChunkCount",
        normalizeNonNegativeNumber(ringBudgets.far and ringBudgets.far.MaxChunkCount or 0)
    )
    local ringResidentBytes = computeRingResidentBytes()
    local nearBudget = normalizeNonNegativeNumber(ringBudgets.near and ringBudgets.near.EstimatedBudgetBytes or 0)
    local midBudget = normalizeNonNegativeNumber(ringBudgets.mid and ringBudgets.mid.EstimatedBudgetBytes or 0)
    local farBudget = normalizeNonNegativeNumber(ringBudgets.far and ringBudgets.far.EstimatedBudgetBytes or 0)
    Workspace:SetAttribute("ArnisStreamingRingNearResidentBytes", ringResidentBytes.near)
    Workspace:SetAttribute("ArnisStreamingRingMidResidentBytes", ringResidentBytes.mid)
    Workspace:SetAttribute("ArnisStreamingRingFarResidentBytes", ringResidentBytes.far)
    Workspace:SetAttribute(
        "ArnisStreamingRingNearPressureLevel",
        computeRingPressureLevel(ringResidentBytes.near, nearBudget)
    )
    Workspace:SetAttribute(
        "ArnisStreamingRingMidPressureLevel",
        computeRingPressureLevel(ringResidentBytes.mid, midBudget)
    )
    Workspace:SetAttribute(
        "ArnisStreamingRingFarPressureLevel",
        computeRingPressureLevel(ringResidentBytes.far, farBudget)
    )
    Workspace:SetAttribute(
        "ArnisStreamingRingNearOverBudget",
        nearBudget > 0 and ringResidentBytes.near > nearBudget
    )
    Workspace:SetAttribute(
        "ArnisStreamingRingMidOverBudget",
        midBudget > 0 and ringResidentBytes.mid > midBudget
    )
    Workspace:SetAttribute(
        "ArnisStreamingRingFarOverBudget",
        farBudget > 0 and ringResidentBytes.far > farBudget
    )
    Workspace:SetAttribute("ArnisStreamingQueuedEstimatedCost", normalizeNonNegativeNumber(queuedEstimatedCost))
    Workspace:SetAttribute("ArnisStreamingQueuedWorkItemCount", normalizeNonNegativeNumber(queuedWorkItemCount))
    Workspace:SetAttribute("ArnisStreamingEvictedEstimatedCost", normalizeNonNegativeNumber(evictedEstimatedCost))
    Workspace:SetAttribute("ArnisStreamingEvictedChunkCount", normalizeNonNegativeNumber(evictedChunkCount))
    Workspace:SetAttribute("ArnisStreamingLastPrefetchReason", lastPrefetchReason or "")
    Workspace:SetAttribute("ArnisStreamingLastEvictionReason", lastEvictionReason or "")
end

local function observeHostProbeSample()
    if not streamingMemoryGuardrail then
        return
    end

    local guardrailConfig = streamingMemoryGuardrail:GetConfig()
    local hostProbeConfig = guardrailConfig and guardrailConfig.HostProbe or nil
    if type(hostProbeConfig) ~= "table" or hostProbeConfig.Enabled ~= true then
        streamingMemoryGuardrail:ObserveHostProbe(nil)
        return
    end

    streamingMemoryGuardrail:ObserveHostProbe({
        availableBytes = Workspace:GetAttribute(HOST_PROBE_AVAILABLE_ATTR),
        pressureLevel = Workspace:GetAttribute(HOST_PROBE_PRESSURE_ATTR),
    })
end

local resolveLivePlayerRootMotion

local function resolveStreamingLookahead(config)
    local chunkSizeStuds = normalizePositiveNumber(config.ChunkSizeStuds) or DefaultWorldConfig.ChunkSizeStuds or 256
    local lookaheadSeconds = normalizePositiveNumber(config.StreamingLookaheadSeconds) or 0
    local maxLookaheadStuds = normalizePositiveNumber(config.StreamingMaxLookaheadStuds) or (chunkSizeStuds * 2)
    return lookaheadSeconds, maxLookaheadStuds
end

-- Aircraft/jetpack streaming: classify a horizontal speed (studs/sec) into a
-- velocity class so we can scale the streaming lookahead and force minimal LOD
-- for high-velocity prefetch chunks.
local function resolveAircraftStreamingPolicy(config)
    local policy = type(config) == "table" and config.AircraftStreamingPolicy or nil
    if type(policy) ~= "table" then
        policy = DefaultWorldConfig.AircraftStreamingPolicy or {}
    end
    local walkingThreshold = normalizePositiveNumber(policy.WalkingSpeedThreshold) or 32
    local vehicleThreshold = normalizePositiveNumber(policy.VehicleSpeedThreshold) or 128
    if vehicleThreshold <= walkingThreshold then
        vehicleThreshold = walkingThreshold + 1
    end
    local vehicleMultiplier = normalizePositiveNumber(policy.VehicleLookaheadMultiplier) or 2
    local aircraftMultiplier = normalizePositiveNumber(policy.AircraftLookaheadMultiplier) or 4
    local forceMinimalLod = policy.HighVelocityForcesMinimalLod ~= false
    return walkingThreshold, vehicleThreshold, vehicleMultiplier, aircraftMultiplier, forceMinimalLod
end

local function classifyVelocity(speed, config)
    local walkingThreshold, vehicleThreshold, vehicleMultiplier, aircraftMultiplier, forceMinimalLod =
        resolveAircraftStreamingPolicy(config)
    if type(speed) ~= "number" or speed <= walkingThreshold then
        return "walking", 1, forceMinimalLod
    elseif speed <= vehicleThreshold then
        return "vehicle", vehicleMultiplier, forceMinimalLod
    end
    return "aircraft", aircraftMultiplier, forceMinimalLod
end

-- Scale base lookahead by velocity-class multiplier and update per-update
-- velocity-class state. Walking speeds use 1x. Vehicles and aircraft scale up
-- so the streaming queue stays ahead of fast-moving players (jetpacks, planes,
-- parachutes) and they don't outrun the queue and fall through empty chunks.
local function applyVelocityClassToLookahead(speed, lookaheadSeconds, maxLookaheadStuds, config)
    local class, multiplier, forceMinimalLod = classifyVelocity(speed, config)
    streamingVelocityMagnitude = if type(speed) == "number" then math.max(0, speed) else 0
    streamingVelocityClass = class
    streamingForceMinimalLodForPrefetch = forceMinimalLod and class ~= "walking"
    local scaledLookaheadSeconds = lookaheadSeconds * multiplier
    local scaledLookaheadStuds = math.min(maxLookaheadStuds, streamingVelocityMagnitude * scaledLookaheadSeconds)
    streamingAdaptiveLookaheadStuds = math.max(0, scaledLookaheadStuds)
    return scaledLookaheadStuds
end

local function resolveSchedulerFocusPoint(playerPos, config)
    local movementForward = nil
    local movementDeltaStuds = 0
    local movementLookaheadStuds = 0
    local predictedFocalPoint = playerPos

    -- Reset per-update velocity state — overwritten below if motion is observed.
    streamingVelocityMagnitude = 0
    streamingVelocityClass = "walking"
    streamingAdaptiveLookaheadStuds = 0
    streamingForceMinimalLodForPrefetch = false

    if typeof(streamingLastFocalPoint) ~= "Vector3" then
        local liveMotionForward, liveMotionSpeed = resolveLivePlayerRootMotion()
        local lookaheadSeconds, maxLookaheadStuds = resolveStreamingLookahead(config)
        if typeof(liveMotionForward) == "Vector3" and lookaheadSeconds > 0 and maxLookaheadStuds > 0 then
            movementForward = liveMotionForward
            movementLookaheadStuds =
                applyVelocityClassToLookahead(liveMotionSpeed, lookaheadSeconds, maxLookaheadStuds, config)
            if movementLookaheadStuds > 0 then
                predictedFocalPoint = playerPos + liveMotionForward.Unit * movementLookaheadStuds
            end
        end
        return movementForward, predictedFocalPoint, movementDeltaStuds, movementLookaheadStuds
    end

    local horizontalDelta =
        Vector3.new(playerPos.X - streamingLastFocalPoint.X, 0, playerPos.Z - streamingLastFocalPoint.Z)
    movementDeltaStuds = horizontalDelta.Magnitude
    if movementDeltaStuds < 1 then
        local liveMotionForward, liveMotionSpeed = resolveLivePlayerRootMotion()
        local lookaheadSeconds, maxLookaheadStuds = resolveStreamingLookahead(config)
        if typeof(liveMotionForward) == "Vector3" and lookaheadSeconds > 0 and maxLookaheadStuds > 0 then
            movementForward = liveMotionForward
            movementLookaheadStuds =
                applyVelocityClassToLookahead(liveMotionSpeed, lookaheadSeconds, maxLookaheadStuds, config)
            if movementLookaheadStuds > 0 then
                predictedFocalPoint = playerPos + liveMotionForward.Unit * movementLookaheadStuds
            end
        end
        return movementForward, predictedFocalPoint, movementDeltaStuds, movementLookaheadStuds
    end

    movementForward = horizontalDelta
    local lookaheadSeconds, maxLookaheadStuds = resolveStreamingLookahead(config)
    if lookaheadSeconds <= 0 or maxLookaheadStuds <= 0 then
        return movementForward, predictedFocalPoint, movementDeltaStuds, movementLookaheadStuds
    end

    local elapsedSeconds = DEFAULT_UPDATE_INTERVAL
    if type(streamingLastFocalAt) == "number" and streamingLastFocalAt < os.clock() then
        elapsedSeconds = math.max(1 / 60, os.clock() - streamingLastFocalAt)
    end
    local movementSpeedStudsPerSecond = movementDeltaStuds / elapsedSeconds

    -- Live root velocity beats positional delta when faster: a sudden aircraft
    -- burst lands in AssemblyLinearVelocity a tick before it shows up in the
    -- next focal-point sample, and we want classification to react immediately.
    local liveMotionForward, liveMotionSpeed = resolveLivePlayerRootMotion()
    local classificationSpeed = movementSpeedStudsPerSecond
    if typeof(liveMotionForward) == "Vector3" and liveMotionSpeed > classificationSpeed then
        classificationSpeed = liveMotionSpeed
        movementForward = liveMotionForward
    end
    movementLookaheadStuds =
        applyVelocityClassToLookahead(classificationSpeed, lookaheadSeconds, maxLookaheadStuds, config)

    if movementLookaheadStuds <= 0 then
        return movementForward, predictedFocalPoint, movementDeltaStuds, movementLookaheadStuds
    end

    predictedFocalPoint = playerPos + movementForward.Unit * movementLookaheadStuds
    return movementForward, predictedFocalPoint, movementDeltaStuds, movementLookaheadStuds
end

local function sumEstimatedCosts(costById)
    local total = 0
    for _, cost in pairs(costById) do
        total += cost
    end
    return total
end

local function getEstimatedWorkItemCost(workItem)
    local subplan = workItem.subplan
    local chunkRef = workItem.chunkEntry and workItem.chunkEntry.ref or nil

    local function deriveChunkLevelSubplanCost(chunkCost)
        if type(subplan) ~= "table" or type(chunkRef) ~= "table" then
            return nil
        end

        local siblingSubplans = chunkRef.subplans
        if type(siblingSubplans) ~= "table" or #siblingSubplans == 0 then
            return nil
        end

        local totalFeatureCount = 0
        local targetFeatureCount = nil
        for _, candidate in ipairs(siblingSubplans) do
            if type(candidate) == "table" then
                local candidateFeatureCount = normalizeNonNegativeNumber(candidate.featureCount)
                totalFeatureCount += candidateFeatureCount
                if candidate == subplan or candidate.id == subplan.id then
                    targetFeatureCount = candidateFeatureCount
                end
            end
        end

        if totalFeatureCount > 0 and targetFeatureCount ~= nil then
            return chunkCost * (targetFeatureCount / totalFeatureCount)
        end

        return chunkCost / #siblingSubplans
    end

    if type(subplan) == "table" and type(subplan.estimatedMemoryCost) == "number" then
        return normalizeNonNegativeNumber(subplan.estimatedMemoryCost)
    end

    if type(chunkRef) == "table" and type(chunkRef.estimatedMemoryCost) == "number" then
        local chunkEstimatedCost = normalizeNonNegativeNumber(chunkRef.estimatedMemoryCost)
        return if type(subplan) == "table"
            then deriveChunkLevelSubplanCost(chunkEstimatedCost) or chunkEstimatedCost
            else chunkEstimatedCost
    end

    if type(subplan) == "table" and type(subplan.streamingCost) == "number" then
        return normalizeNonNegativeNumber(subplan.streamingCost)
    end

    if type(chunkRef) == "table" and type(chunkRef.streamingCost) == "number" then
        local chunkStreamingCost = normalizeNonNegativeNumber(chunkRef.streamingCost)
        return if type(subplan) == "table"
            then deriveChunkLevelSubplanCost(chunkStreamingCost) or chunkStreamingCost
            else chunkStreamingCost
    end

    return 0
end

local function getEstimatedChunkOrSubplanCost(chunkRef, subplan)
    return getEstimatedWorkItemCost({
        chunkEntry = {
            ref = chunkRef,
        },
        subplan = subplan,
    })
end

local function getResidentCostKey(workItem)
    local chunkId = workItem.chunkId
    local subplanId = type(workItem.subplan) == "table" and workItem.subplan.id or nil
    return ChunkPriority.GetObservedCostKey(chunkId, subplanId) or chunkId
end

local function getCompletedSubplanWorkId(chunkId, subplan)
    if type(chunkId) ~= "string" or chunkId == "" or type(subplan) ~= "table" then
        return nil
    end

    local subplanId = subplan.id
    if type(subplanId) ~= "string" or subplanId == "" then
        subplanId = subplan.layer
    end
    if type(subplanId) ~= "string" or subplanId == "" then
        return nil
    end

    return ("%s:%s"):format(chunkId, subplanId)
end

local function clearResidentEstimatedCostForChunk(chunkId)
    local prefix = chunkId .. "::"
    local toRemove = {}
    for residentKey, _ in pairs(streamingResidentEstimatedCostById) do
        if residentKey == chunkId or string.sub(residentKey, 1, #prefix) == prefix then
            toRemove[#toRemove + 1] = residentKey
        end
    end

    for _, residentKey in ipairs(toRemove) do
        streamingResidentEstimatedCostById[residentKey] = nil
    end
end

local function clearObservedImportCostForChunk(chunkId)
    local prefix = chunkId .. "::"
    local toRemove = {}
    for observedKey, _ in pairs(observedChunkImportMsById) do
        if observedKey == chunkId or string.sub(observedKey, 1, #prefix) == prefix then
            toRemove[#toRemove + 1] = observedKey
        end
    end

    for _, observedKey in ipairs(toRemove) do
        observedChunkImportMsById[observedKey] = nil
    end
end

local function clearResidentEstimatedCost(workItem)
    local residentKey = getResidentCostKey(workItem)
    if residentKey == workItem.chunkId then
        clearResidentEstimatedCostForChunk(workItem.chunkId)
        return
    end
    streamingResidentEstimatedCostById[residentKey] = nil
end

local function recordResidentEstimatedCost(workItem, cost)
    local residentKey = getResidentCostKey(workItem)
    if residentKey == workItem.chunkId then
        clearResidentEstimatedCostForChunk(workItem.chunkId)
    end
    streamingResidentEstimatedCostById[residentKey] = cost
end

local function getResidentEstimatedCostToReplace(workItem)
    local residentKey = getResidentCostKey(workItem)
    if residentKey == workItem.chunkId then
        local total = 0
        local prefix = workItem.chunkId .. "::"
        for existingKey, cost in pairs(streamingResidentEstimatedCostById) do
            if existingKey == workItem.chunkId or string.sub(existingKey, 1, #prefix) == prefix then
                total += cost
            end
        end
        return total
    end

    return streamingResidentEstimatedCostById[residentKey] or 0
end

local function getEffectiveGuardrailResidentCost(config)
    if not streamingMemoryGuardrail or config.CountResidentChunkCost == false then
        return 0
    end
    return sumEstimatedCosts(streamingResidentEstimatedCostById)
end

local function getEffectiveGuardrailInFlightCost(config)
    if not streamingMemoryGuardrail or config.CountInFlightCost == false then
        return 0
    end
    return streamingMemoryGuardrail:GetCounters().inFlightBytes
end

local function chunkEntryBelongsToWorldRoot(chunkEntry, worldRootName)
    local resolvedWorldRootName = if type(worldRootName) == "string" and worldRootName ~= ""
        then worldRootName
        else DEFAULT_WORLD_ROOT_NAME

    local folder = chunkEntry and chunkEntry.folder
    local parent = folder and folder.Parent
    local expectedWorldRoot = Workspace:FindFirstChild(resolvedWorldRootName)
    return parent ~= nil and expectedWorldRoot ~= nil and parent == expectedWorldRoot
end

local function chunkEntryHasStartupOwnership(chunkEntry, chunkId)
    if type(chunkEntry) ~= "table" or type(chunkId) ~= "string" or chunkId == "" then
        return false
    end

    local folder = chunkEntry.folder
    if folder == nil or folder:GetAttribute("ArnisChunkId") ~= chunkId then
        return false
    end

    return true
end

local function isChunkLoadedInWorldRoot(chunkId, worldRootName)
    local chunkEntry = ChunkLoader.GetChunkEntry(chunkId, worldRootName)
    return chunkEntry ~= nil and chunkEntryBelongsToWorldRoot(chunkEntry, worldRootName)
end

local function selectPressureReplacementChunk(
    workItem,
    projectedUsage,
    desiredChunkIds,
    focusPoint,
    chunkSizeStuds,
    forwardVector,
    memoryGuardrailConfig
)
    if memoryGuardrailConfig.CountResidentChunkCost == false then
        return nil, 0
    end

    local budgetBytes = normalizeNonNegativeNumber(memoryGuardrailConfig.EstimatedBudgetBytes)
    if budgetBytes <= 0 then
        return nil, 0
    end

    local selectedChunkId = nil
    local selectedResidentCost = 0

    for _, residentChunkId in ipairs(ChunkLoader.ListLoadedChunks(streamingOptions.worldRootName)) do
        if
            residentChunkId ~= workItem.chunkId
            and desiredChunkIds[residentChunkId] == true
            and isChunkLoadedInWorldRoot(residentChunkId, streamingOptions.worldRootName)
        then
            local residentChunkRef = streamingChunkRefsById and streamingChunkRefsById[residentChunkId] or nil
            local residentCost = getResidentEstimatedCostForChunkId(residentChunkId)
            if residentChunkRef ~= nil and residentCost > 0 and projectedUsage - residentCost <= budgetBytes then
                local residentWorkItem = {
                    chunkEntry = {
                        ref = residentChunkRef,
                    },
                    chunkId = residentChunkId,
                    originStuds = residentChunkRef.originStuds,
                    targetLod = loadedChunkLods[residentChunkId],
                }
                if
                    ChunkPriority.CompareWorkItems(
                        workItem,
                        residentWorkItem,
                        focusPoint,
                        chunkSizeStuds,
                        forwardVector,
                        observedChunkImportMsById
                    )
                    and (selectedChunkId == nil or residentCost > selectedResidentCost)
                then
                    selectedChunkId = residentChunkId
                    selectedResidentCost = residentCost
                end
            end
        end
    end

    return selectedChunkId, selectedResidentCost
end

local function pruneStaleResidentEstimatedCosts(worldRootName)
    local staleChunkIds = {}
    local seenChunkIds = {}
    for residentKey in pairs(streamingResidentEstimatedCostById) do
        local chunkId = string.match(residentKey, "^(.-)::") or residentKey
        if not seenChunkIds[chunkId] then
            seenChunkIds[chunkId] = true
            if not isChunkLoadedInWorldRoot(chunkId, worldRootName) then
                staleChunkIds[#staleChunkIds + 1] = chunkId
            end
        end
    end

    for _, chunkId in ipairs(staleChunkIds) do
        clearResidentEstimatedCostForChunk(chunkId)
        clearObservedImportCostForChunk(chunkId)
        loadedChunkLods[chunkId] = nil
        loadedChunkRings[chunkId] = nil
        importedBuildingLodById[chunkId] = nil
        inflightChunkImports[chunkId] = nil
        ImportService.ResetSubplanState(chunkId, worldRootName)
    end
end

local function reconcileLoadedChunksForStart(chunkRefs, worldRootName)
    local chunkRefById = {}
    for _, chunkRef in ipairs(chunkRefs or {}) do
        if type(chunkRef) == "table" and type(chunkRef.id) == "string" and chunkRef.id ~= "" then
            chunkRefById[chunkRef.id] = chunkRef
        end
    end

    for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks(worldRootName)) do
        local chunkEntry = ChunkLoader.GetChunkEntry(chunkId, worldRootName)
        if chunkEntry ~= nil and chunkEntryBelongsToWorldRoot(chunkEntry, worldRootName) then
            local chunkRef = chunkRefById[chunkId]
            local chunkSignature = if type(chunkRef) == "table"
                then ImportSignatures.GetChunkSignature(chunkRef)
                else ""
            if chunkRef == nil or chunkEntry.chunkSignature ~= chunkSignature then
                ChunkLoader.UnloadChunk(chunkId, nil, worldRootName)
                ImportService.ResetSubplanState(chunkId, worldRootName)
                clearResidentEstimatedCostForChunk(chunkId)
                clearObservedImportCostForChunk(chunkId)
                loadedChunkLods[chunkId] = nil
                importedBuildingLodById[chunkId] = nil
                inflightChunkImports[chunkId] = nil
                loadedChunkRings[chunkId] = nil
            end
        end
    end

    for chunkId in pairs(chunkRefById) do
        if not isChunkLoadedInWorldRoot(chunkId, worldRootName) then
            ImportService.ResetSubplanState(chunkId, worldRootName)
            clearObservedImportCostForChunk(chunkId)
        end
    end
end

local function seedLoadedChunkLods(chunkOptionsByLod, worldRootName)
    for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks(worldRootName)) do
        local chunkEntry = ChunkLoader.GetChunkEntry(chunkId, worldRootName)
        if chunkEntry ~= nil and chunkEntryBelongsToWorldRoot(chunkEntry, worldRootName) then
            if chunkEntry.configSignature == chunkOptionsByLod[LOD_LOW].configSignature then
                loadedChunkLods[chunkId] = LOD_LOW
            else
                loadedChunkLods[chunkId] = LOD_HIGH
            end
        end
    end
end

local function seedResidentEstimatedCosts(chunkRefs, config, worldRootName)
    if not streamingMemoryGuardrail then
        return
    end

    local chunkRefsById = {}
    for _, chunkRef in ipairs(chunkRefs or {}) do
        if type(chunkRef) == "table" and type(chunkRef.id) == "string" and chunkRef.id ~= "" then
            chunkRefsById[chunkRef.id] = chunkRef
        end
    end

    for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks(worldRootName)) do
        local chunkEntry = ChunkLoader.GetChunkEntry(chunkId, worldRootName)
        if chunkEntry ~= nil and chunkEntryBelongsToWorldRoot(chunkEntry, worldRootName) then
            local chunkRef = chunkRefsById[chunkId]
            if chunkRef ~= nil then
                local allowedSubplans = SubplanRollout.GetFullySchedulableSubplans(chunkRef, config)
                if allowedSubplans == nil then
                    recordResidentEstimatedCost({
                        chunkId = chunkId,
                        chunkEntry = {
                            ref = chunkRef,
                        },
                    }, getEstimatedChunkOrSubplanCost(chunkRef, nil))
                else
                    local state = ImportService.GetSubplanState(chunkId, worldRootName)
                    local completedWorkItems = state.completedWorkItems or {}
                    local seededSubplan = false
                    for _, subplan in ipairs(allowedSubplans) do
                        local completedWorkId = getCompletedSubplanWorkId(chunkId, subplan)
                        if type(completedWorkId) == "string" and completedWorkItems[completedWorkId] then
                            recordResidentEstimatedCost({
                                chunkId = chunkId,
                                chunkEntry = {
                                    ref = chunkRef,
                                },
                                subplan = subplan,
                            }, getEstimatedChunkOrSubplanCost(chunkRef, subplan))
                            seededSubplan = true
                        end
                    end

                    if not seededSubplan then
                        recordResidentEstimatedCost({
                            chunkId = chunkId,
                            chunkEntry = {
                                ref = chunkRef,
                            },
                        }, getEstimatedChunkOrSubplanCost(chunkRef, nil))
                    end
                end
            end
        end
    end
end

local function refreshMemoryGuardrailTelemetry(config, deferredAdmissions, projectedUsage)
    if not streamingMemoryGuardrail then
        clearMemoryGuardrailTelemetry()
        return
    end

    local residentCost = getEffectiveGuardrailResidentCost(config)
    local inFlightCost = getEffectiveGuardrailInFlightCost(config)
    streamingMemoryGuardrail:SetResidentBytes(residentCost)
    streamingMemoryGuardrail:SetProjectedUsageBytes(
        if type(projectedUsage) == "number"
            then normalizeNonNegativeNumber(projectedUsage)
            else residentCost + inFlightCost
    )

    local snapshot = streamingMemoryGuardrail:Snapshot()
    if
        snapshot.pauseOrigin ~= "manual"
        and streamingMemoryGuardrail:IsPaused()
        and streamingMemoryGuardrail:CanResume()
    then
        streamingMemoryGuardrail:Resume()
        streamingMemoryGuardrail:SetProjectedUsageBytes(
            if type(projectedUsage) == "number"
                then normalizeNonNegativeNumber(projectedUsage)
                else residentCost + inFlightCost
        )
        snapshot = streamingMemoryGuardrail:Snapshot()
    end

    setMemoryGuardrailTelemetry(snapshot, normalizeNonNegativeNumber(deferredAdmissions), residentCost, inFlightCost)
end

getChunkCenter = function(chunkRef, chunkSizeStuds)
    local originData = chunkRef.originStuds or { x = 0, y = 0, z = 0 }
    local halfSize = chunkSizeStuds * 0.5
    return originData.x + halfSize, originData.z + halfSize
end

local function resolveWorldRootName(worldRootName)
    if type(worldRootName) == "string" and worldRootName ~= "" then
        return worldRootName
    end

    if type(streamingOptions) == "table" then
        local configuredWorldRootName = streamingOptions.worldRootName
        if type(configuredWorldRootName) == "string" and configuredWorldRootName ~= "" then
            return configuredWorldRootName
        end
    end

    return DEFAULT_WORLD_ROOT_NAME
end

local function isRoofClosureDeckPart(part)
    if part == nil then
        return false
    end

    if part:GetAttribute("ArnisRoofClosureDeck") == true then
        return true
    end

    return string.find(string.lower(part.Name), "roof_closure", 1, true) ~= nil
end

local function newStartupEnvelopeTelemetry(sourceId)
    return {
        sourceId = sourceId,
        nearbyBuildingModels = 0,
        nearbyMergedBuildingMeshParts = 0,
        nearbyReadableFacadeCueParts = 0,
        nearbyWallParts = 0,
        nearbyRoofParts = 0,
        overheadRoofParts = 0,
        collidableWallPartsNearby = 0,
        nearestWallDistanceStuds = nil,
    }
end

local function isStartupReadableFacadeCuePart(part)
    if part == nil or not part:IsA("BasePart") then
        return false
    end

    local name = part.Name
    return name == "MergedShellWallPresenceCue"
        or name == "MergedShellStreetFacadeCue"
        or name == "MergedShellWindowPaneCue"
        or name == "MergedShellDoorCue"
        or name == "FacadeBeltline"
        or name == "CornerAccent"
end

local function isStartupRoofCuePart(part)
    if part == nil or not part:IsA("BasePart") then
        return false
    end

    local name = part.Name
    return name == "MergedShellRooflineCue" or name == "MergedShellPerimeterCue"
end

local function isStartupEnvelopeReady(envelopeTelemetry)
    local hasDirectWallEnvelope = envelopeTelemetry.nearbyWallParts > 0
        and envelopeTelemetry.collidableWallPartsNearby > 0
    local hasMergedReadableEnvelope = envelopeTelemetry.nearbyMergedBuildingMeshParts > 0
        and envelopeTelemetry.nearbyReadableFacadeCueParts > 0
    local hasRoofEnvelope = envelopeTelemetry.nearbyRoofParts > 0 and envelopeTelemetry.overheadRoofParts > 0
    return type(envelopeTelemetry) == "table"
        and envelopeTelemetry.nearbyBuildingModels > 0
        and (hasDirectWallEnvelope or hasMergedReadableEnvelope)
        and hasRoofEnvelope
end

local function selectStartupEnvelopeTelemetry(candidateTelemetryBySourceId)
    local selectedEnvelopeTelemetry = nil
    local selectedScore = -1
    local selectedSourceId = nil
    local candidateSourceIds = {}

    for sourceId in pairs(candidateTelemetryBySourceId or {}) do
        candidateSourceIds[#candidateSourceIds + 1] = sourceId
    end
    table.sort(candidateSourceIds)

    for _, sourceId in ipairs(candidateSourceIds) do
        local candidateTelemetry = candidateTelemetryBySourceId[sourceId]
        if isStartupEnvelopeReady(candidateTelemetry) then
            local score = candidateTelemetry.nearbyBuildingModels * 100
                + candidateTelemetry.nearbyWallParts * 20
                + candidateTelemetry.collidableWallPartsNearby * 20
                + candidateTelemetry.nearbyRoofParts * 20
                + candidateTelemetry.overheadRoofParts * 10
                + candidateTelemetry.nearbyMergedBuildingMeshParts * 4
                + candidateTelemetry.nearbyReadableFacadeCueParts * 12
            if
                selectedEnvelopeTelemetry == nil
                or score > selectedScore
                or (score == selectedScore and tostring(sourceId) < tostring(selectedSourceId))
            then
                selectedEnvelopeTelemetry = candidateTelemetry
                selectedScore = score
                selectedSourceId = sourceId
            end
        end
    end

    return selectedEnvelopeTelemetry
end

local function countStartupEnvelopeCandidates(candidateTelemetryBySourceId)
    local candidateCount = 0
    for _, candidateTelemetry in pairs(candidateTelemetryBySourceId or {}) do
        if isStartupEnvelopeReady(candidateTelemetry) then
            candidateCount += 1
        end
    end

    return candidateCount
end

local function buildStartupStructureTelemetry(spawnPoint, worldRootName)
    local structureTelemetry = {
        nearbyBuildingModels = 0,
        nearbyMergedBuildingMeshParts = 0,
        nearbyReadableFacadeCueParts = 0,
        nearbyWallParts = 0,
        nearbyRoofParts = 0,
        overheadRoofParts = 0,
        collidableWallPartsNearby = 0,
        nearestWallDistanceStuds = nil,
        coherentEnvelopeNearbyBuildingModels = 0,
        coherentEnvelopeNearbyMergedBuildingMeshParts = 0,
        coherentEnvelopeNearbyReadableFacadeCueParts = 0,
        coherentEnvelopeNearbyWallParts = 0,
        coherentEnvelopeNearbyRoofParts = 0,
        coherentEnvelopeOverheadRoofParts = 0,
        coherentEnvelopeCollidableWallPartsNearby = 0,
        coherentEnvelopeNearestWallDistanceStuds = nil,
        coherentEnvelopeSourceId = nil,
        coherentEnvelopeCandidateCount = 0,
    }
    local envelopeTelemetryBySourceId = {}

    if typeof(spawnPoint) ~= "Vector3" then
        return structureTelemetry
    end

    local worldRoot = Workspace:FindFirstChild(resolveWorldRootName(worldRootName))
    if not worldRoot then
        return structureTelemetry
    end

    local resolvedWorldRootName = worldRoot.Name
    for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks(resolvedWorldRootName)) do
        local chunkEntry = ChunkLoader.GetChunkEntry(chunkId, resolvedWorldRootName)
        if not chunkEntryBelongsToWorldRoot(chunkEntry, resolvedWorldRootName) then
            continue
        end
        if not chunkEntryHasStartupOwnership(chunkEntry, chunkId) then
            continue
        end

        local chunkFolder = chunkEntry.folder
        if not chunkFolder or chunkFolder:GetAttribute("ArnisChunkId") ~= chunkId then
            continue
        end
        local buildingsFolder = chunkFolder:FindFirstChild("Buildings")
        if not buildingsFolder or buildingsFolder:GetAttribute("ArnisChunkId") ~= chunkId then
            continue
        end

        for _, model in ipairs(buildingsFolder:GetDescendants()) do
            if not model:IsA("Model") or model:GetAttribute("ArnisImportBuildingHeight") == nil then
                continue
            end
            if model:GetAttribute("ArnisChunkId") ~= chunkId then
                continue
            end

            local sourceId = model:GetAttribute("ArnisImportSourceId")
            if type(sourceId) ~= "string" or sourceId == "" then
                continue
            end

            local pivotPosition = model:GetPivot().Position
            local offset = pivotPosition - spawnPoint
            local horizontalDistance = Vector2.new(offset.X, offset.Z).Magnitude
            if horizontalDistance > STARTUP_NEARBY_BUILDING_RADIUS then
                continue
            end

            structureTelemetry.nearbyBuildingModels += 1
            local envelopeTelemetry = envelopeTelemetryBySourceId[sourceId]
            if envelopeTelemetry == nil then
                envelopeTelemetry = newStartupEnvelopeTelemetry(sourceId)
                envelopeTelemetryBySourceId[sourceId] = envelopeTelemetry
            end
            envelopeTelemetry.nearbyBuildingModels += 1
            local roofIncludedByShellMesh = model:GetAttribute("ArnisImportRoofIncluded") == true
            local buildingTopY = model:GetAttribute("ArnisImportBuildingTopY")
            local countedMergedRoofEvidence = false

            local shellFolder = model:FindFirstChild("Shell")
            if not shellFolder then
                continue
            end

            for _, descendant in ipairs(shellFolder:GetDescendants()) do
                if not descendant:IsA("BasePart") then
                    continue
                end

                local partOffset = descendant.Position - spawnPoint
                local horizontalPartDistance = Vector2.new(partOffset.X, partOffset.Z).Magnitude
                local nameLower = string.lower(descendant.Name)
                local roofClosureDeck = isRoofClosureDeckPart(descendant)
                local roofPart = string.find(nameLower, "roof", 1, true) ~= nil and not roofClosureDeck

                if
                    descendant:IsA("MeshPart")
                    and horizontalPartDistance <= STARTUP_NEARBY_BUILDING_RADIUS
                    and not roofPart
                    and not roofClosureDeck
                then
                    structureTelemetry.nearbyMergedBuildingMeshParts += 1
                    envelopeTelemetry.nearbyMergedBuildingMeshParts += 1
                    if roofIncludedByShellMesh and not countedMergedRoofEvidence then
                        countedMergedRoofEvidence = true
                        structureTelemetry.nearbyRoofParts += 1
                        envelopeTelemetry.nearbyRoofParts += 1
                        local overheadDeltaY = if type(buildingTopY) == "number"
                            then buildingTopY - spawnPoint.Y
                            else partOffset.Y
                        if
                            horizontalPartDistance <= STARTUP_OVERHEAD_ROOF_RADIUS
                            and overheadDeltaY >= STARTUP_OVERHEAD_MIN_DELTA_Y
                        then
                            structureTelemetry.overheadRoofParts += 1
                            envelopeTelemetry.overheadRoofParts += 1
                        end
                    end
                end

                if roofPart then
                    structureTelemetry.nearbyRoofParts += 1
                    envelopeTelemetry.nearbyRoofParts += 1
                    if
                        horizontalPartDistance <= STARTUP_OVERHEAD_ROOF_RADIUS
                        and partOffset.Y >= STARTUP_OVERHEAD_MIN_DELTA_Y
                    then
                        structureTelemetry.overheadRoofParts += 1
                        envelopeTelemetry.overheadRoofParts += 1
                    end
                    continue
                end

                if roofClosureDeck then
                    continue
                end

                local isNearbyShellWall, nearestShellWallDistanceStuds =
                    WorldProbeGeometry.isNearbyShellWall(descendant, spawnPoint, STARTUP_NEARBY_WALL_RADIUS)
                if isNearbyShellWall then
                    structureTelemetry.nearbyWallParts += 1
                    envelopeTelemetry.nearbyWallParts += 1
                    if descendant.CanCollide then
                        structureTelemetry.collidableWallPartsNearby += 1
                        envelopeTelemetry.collidableWallPartsNearby += 1
                    end
                    if
                        structureTelemetry.nearestWallDistanceStuds == nil
                        or nearestShellWallDistanceStuds < structureTelemetry.nearestWallDistanceStuds
                    then
                        structureTelemetry.nearestWallDistanceStuds = nearestShellWallDistanceStuds
                    end
                    if
                        envelopeTelemetry.nearestWallDistanceStuds == nil
                        or nearestShellWallDistanceStuds < envelopeTelemetry.nearestWallDistanceStuds
                    then
                        envelopeTelemetry.nearestWallDistanceStuds = nearestShellWallDistanceStuds
                    end
                end
            end

            local detailFolder = model:FindFirstChild("Detail")
            if detailFolder then
                for _, descendant in ipairs(detailFolder:GetDescendants()) do
                    if not isStartupReadableFacadeCuePart(descendant) or descendant.Transparency >= 0.99 then
                        continue
                    end

                    local partOffset = descendant.Position - spawnPoint
                    local horizontalPartDistance = Vector2.new(partOffset.X, partOffset.Z).Magnitude
                    if horizontalPartDistance > STARTUP_NEARBY_WALL_RADIUS then
                        continue
                    end

                    structureTelemetry.nearbyReadableFacadeCueParts += 1
                    envelopeTelemetry.nearbyReadableFacadeCueParts += 1
                end
            end

            local detailFolder = model:FindFirstChild("Detail")
            if detailFolder then
                for _, descendant in ipairs(detailFolder:GetDescendants()) do
                    if
                        not descendant:IsA("BasePart")
                        or descendant.Transparency >= 0.99
                        or not isStartupRoofCuePart(descendant)
                    then
                        continue
                    end

                    local partOffset = descendant.Position - spawnPoint
                    local horizontalPartDistance = Vector2.new(partOffset.X, partOffset.Z).Magnitude
                    if horizontalPartDistance > STARTUP_NEARBY_BUILDING_RADIUS then
                        continue
                    end

                    structureTelemetry.nearbyRoofParts += 1
                    envelopeTelemetry.nearbyRoofParts += 1
                    if
                        horizontalPartDistance <= STARTUP_OVERHEAD_ROOF_RADIUS
                        and partOffset.Y >= STARTUP_OVERHEAD_MIN_DELTA_Y
                    then
                        structureTelemetry.overheadRoofParts += 1
                        envelopeTelemetry.overheadRoofParts += 1
                    end
                end
            end
        end
    end

    local coherentEnvelopeTelemetry = selectStartupEnvelopeTelemetry(envelopeTelemetryBySourceId)
    if coherentEnvelopeTelemetry ~= nil then
        structureTelemetry.coherentEnvelopeNearbyBuildingModels = coherentEnvelopeTelemetry.nearbyBuildingModels
        structureTelemetry.coherentEnvelopeNearbyMergedBuildingMeshParts =
            coherentEnvelopeTelemetry.nearbyMergedBuildingMeshParts
        structureTelemetry.coherentEnvelopeNearbyReadableFacadeCueParts =
            coherentEnvelopeTelemetry.nearbyReadableFacadeCueParts
        structureTelemetry.coherentEnvelopeNearbyWallParts = coherentEnvelopeTelemetry.nearbyWallParts
        structureTelemetry.coherentEnvelopeNearbyRoofParts = coherentEnvelopeTelemetry.nearbyRoofParts
        structureTelemetry.coherentEnvelopeOverheadRoofParts = coherentEnvelopeTelemetry.overheadRoofParts
        structureTelemetry.coherentEnvelopeCollidableWallPartsNearby =
            coherentEnvelopeTelemetry.collidableWallPartsNearby
        structureTelemetry.coherentEnvelopeNearestWallDistanceStuds = coherentEnvelopeTelemetry.nearestWallDistanceStuds
        structureTelemetry.coherentEnvelopeSourceId = coherentEnvelopeTelemetry.sourceId
    end
    structureTelemetry.coherentEnvelopeCandidateCount = countStartupEnvelopeCandidates(envelopeTelemetryBySourceId)

    return structureTelemetry
end

function StreamingService.GetStartupResidencySnapshot(spawnPoint, worldRootName)
    local nearResident = tonumber(Workspace:GetAttribute("ArnisStreamingRingNearResidentChunkCount")) or 0
    local nearDesired = tonumber(Workspace:GetAttribute("ArnisStreamingRingNearDesiredChunkCount")) or 0
    local queuedWorkItems = tonumber(Workspace:GetAttribute("ArnisStreamingQueuedWorkItemCount")) or 0
    local schedulerState = Workspace:GetAttribute("ArnisStreamingSchedulerState")
    local structureTelemetry = buildStartupStructureTelemetry(spawnPoint, worldRootName)
    local requiredNearChunks = math.max(1, nearDesired)
    local coherentEnvelopeReady = isStartupEnvelopeReady({
        nearbyBuildingModels = structureTelemetry.coherentEnvelopeNearbyBuildingModels,
        nearbyMergedBuildingMeshParts = structureTelemetry.coherentEnvelopeNearbyMergedBuildingMeshParts,
        nearbyReadableFacadeCueParts = structureTelemetry.coherentEnvelopeNearbyReadableFacadeCueParts,
        nearbyWallParts = structureTelemetry.coherentEnvelopeNearbyWallParts,
        collidableWallPartsNearby = structureTelemetry.coherentEnvelopeCollidableWallPartsNearby,
        nearbyRoofParts = structureTelemetry.coherentEnvelopeNearbyRoofParts,
        overheadRoofParts = structureTelemetry.coherentEnvelopeOverheadRoofParts,
    })
    local ready = nearResident >= requiredNearChunks
        and queuedWorkItems <= 0
        and schedulerState == "steady_state"
        and coherentEnvelopeReady

    return {
        nearResidentChunkCount = nearResident,
        nearDesiredChunkCount = nearDesired,
        queuedWorkItemCount = queuedWorkItems,
        schedulerState = schedulerState,
        nearbyBuildingModels = structureTelemetry.nearbyBuildingModels,
        nearbyMergedBuildingMeshParts = structureTelemetry.nearbyMergedBuildingMeshParts,
        nearbyReadableFacadeCueParts = structureTelemetry.nearbyReadableFacadeCueParts,
        nearbyWallParts = structureTelemetry.nearbyWallParts,
        nearbyRoofParts = structureTelemetry.nearbyRoofParts,
        overheadRoofParts = structureTelemetry.overheadRoofParts,
        collidableWallPartsNearby = structureTelemetry.collidableWallPartsNearby,
        nearestWallDistanceStuds = structureTelemetry.nearestWallDistanceStuds,
        coherentEnvelopeNearbyBuildingModels = structureTelemetry.coherentEnvelopeNearbyBuildingModels,
        coherentEnvelopeNearbyMergedBuildingMeshParts = structureTelemetry.coherentEnvelopeNearbyMergedBuildingMeshParts,
        coherentEnvelopeNearbyReadableFacadeCueParts = structureTelemetry.coherentEnvelopeNearbyReadableFacadeCueParts,
        coherentEnvelopeNearbyWallParts = structureTelemetry.coherentEnvelopeNearbyWallParts,
        coherentEnvelopeNearbyRoofParts = structureTelemetry.coherentEnvelopeNearbyRoofParts,
        coherentEnvelopeOverheadRoofParts = structureTelemetry.coherentEnvelopeOverheadRoofParts,
        coherentEnvelopeCollidableWallPartsNearby = structureTelemetry.coherentEnvelopeCollidableWallPartsNearby,
        coherentEnvelopeNearestWallDistanceStuds = structureTelemetry.coherentEnvelopeNearestWallDistanceStuds,
        coherentEnvelopeSourceId = structureTelemetry.coherentEnvelopeSourceId,
        coherentEnvelopeCandidateCount = structureTelemetry.coherentEnvelopeCandidateCount,
        coherentEnvelopeReady = coherentEnvelopeReady,
        ready = ready,
    }
end

local function getIndexCoord(value, cellSize)
    return math.floor(value / cellSize)
end

local function getChunkEntryCellRange(chunkEntry, cellSize)
    local chunkRef = type(chunkEntry) == "table" and chunkEntry.ref or nil
    local footprintBounds = ChunkPriority.GetChunkFootprintBounds(chunkRef)
    if footprintBounds ~= nil then
        return getIndexCoord(footprintBounds.minX, cellSize),
            getIndexCoord(footprintBounds.maxX, cellSize),
            getIndexCoord(footprintBounds.minY, cellSize),
            getIndexCoord(footprintBounds.maxY, cellSize)
    end

    local centerX = type(chunkEntry) == "table" and chunkEntry.centerX or 0
    local centerZ = type(chunkEntry) == "table" and chunkEntry.centerZ or 0
    local cellX = getIndexCoord(centerX, cellSize)
    local cellZ = getIndexCoord(centerZ, cellSize)
    return cellX, cellX, cellZ, cellZ
end

local function buildChunkSpatialIndex(chunkRefs, config)
    local targetRadius = config.StreamingTargetRadius or 2048
    local cellSize = math.max(config.ChunkSizeStuds or 256, targetRadius)
    local buckets = {}

    for _, chunkRef in ipairs(chunkRefs or {}) do
        local chunkFootprintBounds = ChunkPriority.GetChunkFootprintBounds(chunkRef)
        if chunkFootprintBounds ~= nil then
            chunkRef.streamingFootprintBounds = chunkFootprintBounds
        end
        local centerX, centerZ = ChunkPriority.GetChunkFootprintCenterXZ(chunkRef, config.ChunkSizeStuds)
        local chunkEntry = {
            ref = chunkRef,
            centerX = centerX,
            centerZ = centerZ,
            materializedChunk = nil,
        }
        local minCellX, maxCellX, minCellZ, maxCellZ = getChunkEntryCellRange(chunkEntry, cellSize)
        for cellX = minCellX, maxCellX do
            local row = buckets[cellX]
            if not row then
                row = {}
                buckets[cellX] = row
            end
            for cellZ = minCellZ, maxCellZ do
                local bucket = row[cellZ]
                if not bucket then
                    bucket = {}
                    row[cellZ] = bucket
                end
                bucket[#bucket + 1] = chunkEntry
            end
        end
    end

    return {
        cellSize = cellSize,
        buckets = buckets,
    }
end

local function getCandidateChunkRefs(index, playerPos, targetRadius)
    if not index then
        return {}
    end

    local minCellX = getIndexCoord(playerPos.X - targetRadius, index.cellSize)
    local maxCellX = getIndexCoord(playerPos.X + targetRadius, index.cellSize)
    local minCellZ = getIndexCoord(playerPos.Z - targetRadius, index.cellSize)
    local maxCellZ = getIndexCoord(playerPos.Z + targetRadius, index.cellSize)
    local candidates = {}
    local seenChunkIds = {}

    for cellX = minCellX, maxCellX do
        local row = index.buckets[cellX]
        if row then
            for cellZ = minCellZ, maxCellZ do
                local bucket = row[cellZ]
                if bucket then
                    for _, chunkEntry in ipairs(bucket) do
                        local chunkId = type(chunkEntry) == "table" and chunkEntry.ref and chunkEntry.ref.id or nil
                        if type(chunkId) == "string" and not seenChunkIds[chunkId] then
                            seenChunkIds[chunkId] = true
                            candidates[#candidates + 1] = chunkEntry
                        end
                    end
                end
            end
        end
    end

    return candidates
end

local function getSchedulerCandidateChunkRefs(index, playerPos, schedulerFocusPoint, targetRadius)
    local primaryCandidates = getCandidateChunkRefs(index, playerPos, targetRadius)
    if typeof(schedulerFocusPoint) ~= "Vector3" then
        return primaryCandidates
    end

    local dx = schedulerFocusPoint.X - playerPos.X
    local dz = schedulerFocusPoint.Z - playerPos.Z
    if dx * dx + dz * dz < 1 then
        return primaryCandidates
    end

    local mergedCandidates = table.clone(primaryCandidates)
    local seenChunkIds = {}
    for _, chunkEntry in ipairs(primaryCandidates) do
        seenChunkIds[chunkEntry.ref.id] = true
    end

    for _, chunkEntry in ipairs(getCandidateChunkRefs(index, schedulerFocusPoint, targetRadius)) do
        local chunkId = chunkEntry.ref.id
        if not seenChunkIds[chunkId] then
            seenChunkIds[chunkId] = true
            mergedCandidates[#mergedCandidates + 1] = chunkEntry
        end
    end

    return mergedCandidates
end

local function getChunkDistanceSqToPoint(chunkEntry, point)
    if type(chunkEntry) ~= "table" or type(chunkEntry.ref) ~= "table" then
        return math.huge
    end

    return ChunkPriority.GetChunkFootprintDistanceSq(
        chunkEntry.ref,
        point,
        streamingOptions and streamingOptions.config and streamingOptions.config.ChunkSizeStuds or nil
    )
end

local function getMaterializedChunk(chunkEntry)
    if chunkEntry.materializedChunk then
        return chunkEntry.materializedChunk
    end

    local chunkRef = chunkEntry.ref
    local chunk = if streamingManifest and type(streamingManifest.GetChunk) == "function"
        then streamingManifest:GetChunk(chunkRef.id)
        else chunkRef
    chunkEntry.materializedChunk = chunk
    return chunk
end

local function describeStreamingTerrainNeighborChunk(chunkRef)
    if type(chunkRef) ~= "table" then
        return nil
    end

    local chunk = if streamingManifest and type(streamingManifest.GetChunk) == "function"
        then streamingManifest:GetChunk(chunkRef.id)
        else chunkRef
    local terrain = chunk and chunk.terrain or nil
    if type(chunk) ~= "table" or type(terrain) ~= "table" or type(terrain.heights) ~= "table" then
        return nil
    end

    return {
        id = chunk.id or chunkRef.id,
        terrain = terrain,
    }
end

local function buildStreamingTerrainNeighborContext(chunkRef)
    if type(chunkRef) ~= "table" then
        return nil
    end

    local chunkSizeStuds = if type(streamingOptions) == "table"
            and type(streamingOptions.config) == "table"
            and type(streamingOptions.config.ChunkSizeStuds) == "number"
        then streamingOptions.config.ChunkSizeStuds
        elseif
            streamingManifest
            and streamingManifest.meta
            and type(streamingManifest.meta.chunkSizeStuds) == "number"
        then streamingManifest.meta.chunkSizeStuds
        else DefaultWorldConfig.ChunkSizeStuds or 256
    local origin = chunkRef.originStuds or {}
    local originX = origin.x or 0
    local originZ = origin.z or 0

    local function resolveNeighbor(offsetX, offsetZ)
        local neighborRef = streamingChunkRefsByOrigin
                and streamingChunkRefsByOrigin[makeChunkOriginKey(
                    originX + offsetX * chunkSizeStuds,
                    originZ + offsetZ * chunkSizeStuds
                )]
            or nil
        return describeStreamingTerrainNeighborChunk(neighborRef)
    end

    local neighbors = {
        west = resolveNeighbor(-1, 0),
        east = resolveNeighbor(1, 0),
        north = resolveNeighbor(0, -1),
        south = resolveNeighbor(0, 1),
        northWest = resolveNeighbor(-1, -1),
        northEast = resolveNeighbor(1, -1),
        southWest = resolveNeighbor(-1, 1),
        southEast = resolveNeighbor(1, 1),
    }

    local function buildStreamingTerrainNeighborContextSignature(neighbors)
        if type(neighbors) ~= "table" then
            return "none"
        end

        local directions = { "west", "east", "north", "south", "northWest", "northEast", "southWest", "southEast" }
        local tokens = {}
        for _, direction in ipairs(directions) do
            local descriptor = neighbors[direction]
            local neighborId = descriptor and descriptor.id or "none"
            local neighborTerrain = descriptor and descriptor.terrain or nil
            local terrainIdentityToken = tostring(neighborTerrain)
            local heightsIdentityToken = if type(neighborTerrain) == "table"
                then tostring(neighborTerrain.heights)
                else "none"
            tokens[#tokens + 1] = table.concat({
                direction .. "=" .. tostring(neighborId),
                terrainIdentityToken,
                heightsIdentityToken,
            }, "@")
        end

        return table.concat(tokens, ",")
    end

    return {
        neighbors = neighbors,
        signature = buildStreamingTerrainNeighborContextSignature(neighbors),
    }
end

local hasPendingBuildingSubplans
local shouldBypassHighDetailSubplanRollout

local function appendStreamingWorkItems(workItems, chunkEntry, chunkOptions, config, targetLod, buildingLodLevel)
    -- chunkRef must be declared BEFORE the inner closure below so the
    -- closure captures it as an upvalue. In Lua/Luau, local declarations
    -- are only visible from the next statement, so a closure defined
    -- earlier in the same block sees `chunkRef` as a global (nil) and
    -- crashes at invocation with "attempt to index nil with 'id'". This
    -- was a latent bug in the eager-embedded path that only manifested
    -- once the lazy external_url fetcher exercised the code path.
    local chunkRef = chunkEntry and chunkEntry.ref or nil
    if chunkRef == nil then
        warn("[StreamingService] appendStreamingWorkItems: chunkEntry.ref is nil; skipping")
        return
    end

    local function appendWholeChunkWorkItem(wholeChunkOptions)
        workItems[#workItems + 1] = {
            chunkEntry = chunkEntry,
            chunkOptions = wholeChunkOptions,
            chunkId = chunkRef.id,
            originStuds = chunkRef.originStuds,
            targetLod = targetLod,
            buildingLodLevel = buildingLodLevel,
            highDetailWholeChunkPriority = wholeChunkOptions.highDetailWholeChunkPriority == true,
            highDetailStructurePriority = wholeChunkOptions.highDetailStructurePriority == true,
        }
    end
    if shouldBypassHighDetailSubplanRollout(chunkEntry, chunkOptions, targetLod) then
        appendWholeChunkWorkItem({
            worldRootName = chunkOptions.worldRootName,
            frameBudgetSeconds = chunkOptions.frameBudgetSeconds,
            nonBlocking = chunkOptions.nonBlocking,
            shouldCancel = chunkOptions.shouldCancel,
            config = chunkOptions.config,
            configSignature = chunkOptions.configSignature,
            layerSignatures = chunkOptions.layerSignatures,
            highDetailWholeChunkPriority = true,
            highDetailStructurePriority = true,
        })
        return false
    end

    local allowedSubplans = SubplanRollout.GetFullySchedulableSubplans(chunkRef, config)
    if allowedSubplans == nil then
        appendWholeChunkWorkItem({
            worldRootName = chunkOptions.worldRootName,
            frameBudgetSeconds = chunkOptions.frameBudgetSeconds,
            nonBlocking = chunkOptions.nonBlocking,
            shouldCancel = chunkOptions.shouldCancel,
            config = chunkOptions.config,
            configSignature = chunkOptions.configSignature,
            layerSignatures = chunkOptions.layerSignatures,
            highDetailStructurePriority = shouldPrioritizeHighDetailStructures(chunkRef, targetLod),
        })
        return false
    end

    for _, subplan in ipairs(allowedSubplans) do
        workItems[#workItems + 1] = {
            chunkEntry = chunkEntry,
            chunkOptions = chunkOptions,
            chunkId = chunkRef.id,
            originStuds = chunkRef.originStuds,
            subplan = subplan,
            targetLod = targetLod,
            buildingLodLevel = buildingLodLevel,
            highDetailStructurePriority = targetLod == LOD_HIGH
                and type(subplan) == "table"
                and subplan.layer == "buildings",
        }
    end
    return true
end

local function getPendingSubplans(chunkRef, config)
    local allowedSubplans = SubplanRollout.GetFullySchedulableSubplans(chunkRef, config)
    if allowedSubplans == nil then
        return nil
    end

    local state = ImportService.GetSubplanState(chunkRef.id, streamingOptions.worldRootName)
    local completedWorkItems = state.completedWorkItems or {}
    local pending = {}
    for _, subplan in ipairs(allowedSubplans) do
        local completedWorkId = getCompletedSubplanWorkId(chunkRef.id, subplan)
        if type(completedWorkId) == "string" and not completedWorkItems[completedWorkId] then
            pending[#pending + 1] = subplan
        end
    end
    return pending
end

local function chunkRefHasBuildingContent(chunkRef)
    return type(chunkRef) == "table" and type(chunkRef.buildings) == "table" and #chunkRef.buildings > 0
end

local function shouldPrioritizeHighDetailStructures(chunkRef, targetLod)
    return targetLod == LOD_HIGH and chunkRefHasBuildingContent(chunkRef)
end

hasPendingBuildingSubplans = function(chunkRef, config)
    local pendingSubplans = getPendingSubplans(chunkRef, config)
    if pendingSubplans == nil then
        return false
    end

    for _, subplan in ipairs(pendingSubplans) do
        if type(subplan) == "table" and subplan.layer == "buildings" then
            return true
        end
    end

    return false
end

shouldBypassHighDetailSubplanRollout = function(chunkEntry, chunkOptions, targetLod)
    return targetLod == LOD_HIGH
        and type(chunkEntry) == "table"
        and type(chunkOptions) == "table"
        and hasPendingBuildingSubplans(chunkEntry.ref, chunkOptions.config)
end

local function queuePendingSubplans(workItems, chunkEntry, chunkOptions, targetLod, buildingLodLevel)
    if shouldBypassHighDetailSubplanRollout(chunkEntry, chunkOptions, targetLod) then
        workItems[#workItems + 1] = {
            chunkEntry = chunkEntry,
            chunkOptions = {
                worldRootName = chunkOptions.worldRootName,
                frameBudgetSeconds = chunkOptions.frameBudgetSeconds,
                nonBlocking = chunkOptions.nonBlocking,
                shouldCancel = chunkOptions.shouldCancel,
                config = chunkOptions.config,
                configSignature = chunkOptions.configSignature,
                layerSignatures = chunkOptions.layerSignatures,
                highDetailWholeChunkPriority = true,
                highDetailStructurePriority = true,
            },
            chunkId = chunkEntry.ref.id,
            originStuds = chunkEntry.ref.originStuds,
            targetLod = targetLod,
            buildingLodLevel = buildingLodLevel,
            highDetailWholeChunkPriority = true,
            highDetailStructurePriority = true,
        }
        return true
    end

    local pendingSubplans = getPendingSubplans(chunkEntry.ref, chunkOptions.config)
    if pendingSubplans == nil or #pendingSubplans == 0 then
        return false
    end

    for _, subplan in ipairs(pendingSubplans) do
        workItems[#workItems + 1] = {
            chunkEntry = chunkEntry,
            chunkOptions = chunkOptions,
            chunkId = chunkEntry.ref.id,
            originStuds = chunkEntry.ref.originStuds,
            subplan = subplan,
            targetLod = targetLod,
            buildingLodLevel = buildingLodLevel,
            highDetailStructurePriority = targetLod == LOD_HIGH
                and type(subplan) == "table"
                and subplan.layer == "buildings",
        }
    end
    return true
end

local function computeChangedLayers(currentLayerSignatures, targetLayerSignatures)
    local changed = nil
    for layerName, targetSignature in pairs(targetLayerSignatures) do
        local currentSignature = currentLayerSignatures and currentLayerSignatures[layerName] or nil
        if currentSignature ~= targetSignature then
            if changed == nil then
                changed = {}
            end
            changed[layerName] = true
        end
    end
    return changed
end

local function getExitRadius(enterRadius, maxRadius)
    local expanded = enterRadius * (1 + HYSTERESIS_RATIO)
    if maxRadius ~= nil then
        return math.min(expanded, maxRadius)
    end
    return expanded
end

local function chooseTargetLod(distSq, currentLod, highRadiusSq, highExitRadiusSq, targetRadiusSq, targetExitRadiusSq)
    if currentLod == LOD_HIGH then
        if distSq <= highExitRadiusSq then
            return LOD_HIGH
        end
        if distSq <= targetRadiusSq then
            return LOD_LOW
        end
        return nil
    end

    if currentLod == LOD_LOW then
        if distSq <= highRadiusSq then
            return LOD_HIGH
        end
        if distSq <= targetExitRadiusSq then
            return LOD_LOW
        end
        return nil
    end

    if distSq <= highRadiusSq then
        return LOD_HIGH
    end
    if distSq <= targetRadiusSq then
        return LOD_LOW
    end
    return nil
end

local function getLodConfig(level, baseConfig)
    local cachedByLevel = lodConfigCache[baseConfig]
    if not cachedByLevel then
        cachedByLevel = {}
        lodConfigCache[baseConfig] = cachedByLevel
    end

    local cached = cachedByLevel[level]
    if cached then
        return cached
    end

    -- Low LOD is residency-driven; grouped detail/interior handle visual downgrade
    -- while macro layers remain resident and rebuild-free.
    local config = table.clone(baseConfig)

    cachedByLevel[level] = config
    return config
end

local function buildChunkOptionsByLod(options, baseConfig)
    local frameBudgetSeconds = normalizePositiveNumber(options.frameBudgetSeconds)
        or normalizePositiveNumber(baseConfig.StreamingImportFrameBudgetSeconds)
    local nonBlocking = options.nonBlocking
    if nonBlocking == nil then
        nonBlocking = frameBudgetSeconds ~= nil
    end

    return {
        [LOD_HIGH] = {
            worldRootName = options.worldRootName,
            frameBudgetSeconds = frameBudgetSeconds,
            nonBlocking = nonBlocking,
            shouldCancel = options.shouldCancel,
            config = getLodConfig(LOD_HIGH, baseConfig),
            configSignature = ImportSignatures.GetConfigSignature(getLodConfig(LOD_HIGH, baseConfig)),
            layerSignatures = ImportSignatures.GetLayerSignatures(getLodConfig(LOD_HIGH, baseConfig)),
        },
        [LOD_LOW] = {
            worldRootName = options.worldRootName,
            frameBudgetSeconds = frameBudgetSeconds,
            nonBlocking = nonBlocking,
            shouldCancel = options.shouldCancel,
            config = getLodConfig(LOD_LOW, baseConfig),
            configSignature = ImportSignatures.GetConfigSignature(getLodConfig(LOD_LOW, baseConfig)),
            layerSignatures = ImportSignatures.GetLayerSignatures(getLodConfig(LOD_LOW, baseConfig)),
        },
    }
end

local function setInstanceVisible(instance, visible)
    if instance:IsA("BasePart") then
        instance.Transparency = if visible
            then (instance:GetAttribute("BaseTransparency") or instance:GetAttribute("ArnisBaseTransparency") or 0)
            else 1
    elseif instance:IsA("BillboardGui") then
        instance.Enabled = visible
    end
end

local function setGroupVisible(group, visible)
    if group:GetAttribute("ArnisLodVisible") == visible then
        return
    end

    for _, descendant in ipairs(group:GetDescendants()) do
        setInstanceVisible(descendant, visible)
    end
    group:SetAttribute("ArnisLodVisible", visible)
end

-- Apply ring-based transparency boost to all visible BaseParts in a chunk folder.
-- Parts remember their authored transparency via ArnisBaseTransparency so the boost
-- is additive and reversible when the chunk moves back to a nearer ring.
local function applyRingTransparency(chunkEntry, ringName)
    local folder = chunkEntry and chunkEntry.folder
    if not folder or not folder.Parent then
        return
    end

    local boost = 0
    if ringName == "far" then
        boost = FAR_RING_TRANSPARENCY_BOOST
    elseif ringName == "mid" then
        boost = MID_RING_TRANSPARENCY_BOOST
    end

    local currentBoost = folder:GetAttribute("ArnisRingTransparencyBoost") or 0
    if currentBoost == boost then
        return
    end

    for _, descendant in ipairs(folder:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local base = descendant:GetAttribute("ArnisBaseTransparency") or descendant:GetAttribute("BaseTransparency")
            if base == nil then
                -- First time: snapshot the authored transparency
                base = descendant.Transparency
                descendant:SetAttribute("ArnisBaseTransparency", base)
            end
            -- Only apply boost to visible parts (not hidden LOD parts)
            if base < 0.99 then
                descendant.Transparency = math.min(base + boost, 0.99)
            end
        end
    end
    folder:SetAttribute("ArnisRingTransparencyBoost", boost)
end

local function getLodGroupFootprintBounds(group, fallbackPosition)
    if group == nil then
        return nil
    end

    local cachedBounds = lodGroupFootprintBoundsCache[group]
    if cachedBounds ~= nil then
        return cachedBounds
    end

    local minX, maxX, minZ, maxZ = nil, nil, nil, nil

    for _, descendant in ipairs(group:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local partCFrame = descendant.CFrame
            local halfSize = descendant.Size * 0.5
            local rightVector = partCFrame.RightVector
            local upVector = partCFrame.UpVector
            local lookVector = partCFrame.LookVector
            local center = partCFrame.Position
            local extentX = math.abs(rightVector.X) * halfSize.X
                + math.abs(upVector.X) * halfSize.Y
                + math.abs(lookVector.X) * halfSize.Z
            local extentZ = math.abs(rightVector.Z) * halfSize.X
                + math.abs(upVector.Z) * halfSize.Y
                + math.abs(lookVector.Z) * halfSize.Z
            local partMinX = center.X - extentX
            local partMaxX = center.X + extentX
            local partMinZ = center.Z - extentZ
            local partMaxZ = center.Z + extentZ

            if minX == nil or partMinX < minX then
                minX = partMinX
            end
            if maxX == nil or partMaxX > maxX then
                maxX = partMaxX
            end
            if minZ == nil or partMinZ < minZ then
                minZ = partMinZ
            end
            if maxZ == nil or partMaxZ > maxZ then
                maxZ = partMaxZ
            end
        end
    end

    if minX == nil then
        if typeof(fallbackPosition) == "Vector3" then
            cachedBounds = {
                minX = fallbackPosition.X,
                maxX = fallbackPosition.X,
                minZ = fallbackPosition.Z,
                maxZ = fallbackPosition.Z,
            }
            lodGroupFootprintBoundsCache[group] = cachedBounds
            return cachedBounds
        end
        return nil
    end

    cachedBounds = {
        minX = minX,
        maxX = maxX,
        minZ = minZ,
        maxZ = maxZ,
    }
    lodGroupFootprintBoundsCache[group] = cachedBounds
    return cachedBounds
end

local function getLodGroupFootprintDistanceSq(group, fallbackPosition, point)
    local bounds = getLodGroupFootprintBounds(group, fallbackPosition)
    if type(bounds) ~= "table" or typeof(point) ~= "Vector3" then
        return math.huge
    end

    local closestX = math.clamp(point.X, bounds.minX, bounds.maxX)
    local closestZ = math.clamp(point.Z, bounds.minZ, bounds.maxZ)
    local dx = point.X - closestX
    local dz = point.Z - closestZ
    return dx * dx + dz * dz
end

local function updateChunkEntryLodGroups(
    chunkEntry,
    primaryFocusPos,
    secondaryFocusPos,
    highDetailRadius,
    interiorRadius
)
    if not chunkEntry or not chunkEntry.lodGroups then
        return
    end

    local cameraFocusPos = primaryFocusPos
    local avatarFocusPos = secondaryFocusPos
    local folder = chunkEntry.folder
    local chunkCenter = nil
    if folder and folder.Parent then
        local chunkPos = folder:GetAttribute("ArnisChunkCenter")
        if typeof(chunkPos) == "Vector3" then
            chunkCenter = chunkPos
        end
    end
    if chunkCenter == nil and chunkEntry.chunk then
        local origin = chunkEntry.chunk.originStuds or { x = 0, y = 0, z = 0 }
        local chunkSize = streamingOptions and streamingOptions.config and streamingOptions.config.ChunkSizeStuds
            or DefaultWorldConfig.ChunkSizeStuds
            or 256
        chunkCenter = Vector3.new(origin.x + chunkSize * 0.5, origin.y or 0, origin.z + chunkSize * 0.5)
    end
    if chunkCenter == nil then
        return
    end

    local highDetailRadiusSq = highDetailRadius * highDetailRadius
    local interiorRadiusSq = interiorRadius * interiorRadius

    local function isLodGroupVisibleForFocus(group, fallbackPosition, focusPos, radiusSq)
        if typeof(focusPos) ~= "Vector3" then
            return false
        end

        return getLodGroupFootprintDistanceSq(group, fallbackPosition, focusPos) <= radiusSq
    end

    for _, group in ipairs(chunkEntry.lodGroups.detail or {}) do
        if group:IsDescendantOf(Workspace) then
            local detailVisible = isLodGroupVisibleForFocus(group, chunkCenter, cameraFocusPos, highDetailRadiusSq)
            if not detailVisible and typeof(avatarFocusPos) == "Vector3" then
                detailVisible = isLodGroupVisibleForFocus(group, chunkCenter, avatarFocusPos, highDetailRadiusSq)
            end
            setGroupVisible(group, detailVisible)
        end
    end
    for _, group in ipairs(chunkEntry.lodGroups.interior or {}) do
        if group:IsDescendantOf(Workspace) then
            local interiorVisible = isLodGroupVisibleForFocus(group, chunkCenter, avatarFocusPos, interiorRadiusSq)
            setGroupVisible(group, interiorVisible)
        end
    end
end

local function resolveLivePlayerRootFocusPosition()
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            local rootPart = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
            if rootPart and rootPart:IsA("BasePart") then
                return rootPart.Position
            end
        end
    end

    return nil
end

local LIVE_PLAYER_ROOT_MOTION_THRESHOLD = 4

resolveLivePlayerRootMotion = function()
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            local rootPart = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
            if rootPart and rootPart:IsA("BasePart") then
                local velocity = rootPart.AssemblyLinearVelocity
                local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
                local speed = horizontalVelocity.Magnitude
                if speed >= LIVE_PLAYER_ROOT_MOTION_THRESHOLD then
                    return horizontalVelocity.Unit, speed
                end
            end
        end
    end

    return nil, 0
end

local function resolveCurrentCameraFocusPosition()
    local camera = Workspace.CurrentCamera
    if camera then
        return camera.CFrame.Position
    end

    return nil
end

-- ─── MULTIPLAYER FOCUS REGISTRY HELPERS ───

local function getPlayerUserIdKey(player)
    if type(player) == "number" then
        return player
    end
    if typeof(player) == "Instance" and player:IsA("Player") then
        return player.UserId
    end
    return nil
end

-- Resolve the live HumanoidRootPart for a specific player. Used as a fallback
-- when the client has not (yet) reported its camera position via remote.
local function resolvePlayerRootPosition(player)
    if typeof(player) ~= "Instance" or not player:IsA("Player") then
        return nil, nil
    end
    local character = player.Character
    if not character then
        return nil, nil
    end
    local rootPart = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
    if rootPart and rootPart:IsA("BasePart") then
        local horizontalVelocity = Vector3.new(
            rootPart.AssemblyLinearVelocity.X,
            0,
            rootPart.AssemblyLinearVelocity.Z
        )
        return rootPart.Position, horizontalVelocity
    end
    return nil, nil
end

-- Public: register or update a player's reported focus point. Called from:
--  • Players.PlayerAdded handler with the spawn point seed
--  • The client→server position RemoteEvent handler
--  • Test harnesses that drive multiplayer streaming deterministically
function StreamingService.RegisterPlayerFocus(player, position, velocity)
    local key = getPlayerUserIdKey(player)
    if key == nil then
        return false
    end
    if typeof(position) ~= "Vector3" then
        return false
    end
    local resolvedVelocity = if typeof(velocity) == "Vector3" then velocity else Vector3.zero
    playerFocusRegistry[key] = {
        player = if typeof(player) == "Instance" then player else nil,
        userId = key,
        position = position,
        velocity = resolvedVelocity,
        updatedAt = os.clock(),
    }
    return true
end

-- Public: drop a player from the focus registry. Called on PlayerRemoving and
-- by tests. After removal the next Update() tick will recompute desired chunks
-- as the union over the remaining players, naturally evicting any chunks that
-- were only kept alive by the departing player.
function StreamingService.UnregisterPlayerFocus(player)
    local key = getPlayerUserIdKey(player)
    if key == nil then
        return false
    end
    if playerFocusRegistry[key] == nil then
        return false
    end
    playerFocusRegistry[key] = nil
    return true
end

-- Public: snapshot the current set of per-player focus points as an array of
-- {player, position, velocity, userId, updatedAt} tuples. Stale focuses (older
-- than MultiplayerStreaming.staleFocusTimeoutSeconds) are excluded; if a stale
-- entry has a still-connected Player object with a HumanoidRootPart, that root
-- position is substituted as a best-effort fallback so the player keeps
-- streaming chunks even when the client position remote stops reporting.
function StreamingService.GetAllPlayerFocusPoints(config)
    local resolvedConfig = config or (streamingOptions and streamingOptions.config) or DefaultWorldConfig
    local mpConfig = resolveMultiplayerConfig(resolvedConfig)
    local staleTimeout = if type(mpConfig) == "table"
            and type(mpConfig.staleFocusTimeoutSeconds) == "number"
            and mpConfig.staleFocusTimeoutSeconds > 0
        then mpConfig.staleFocusTimeoutSeconds
        else 5
    local maxPlayers = if type(mpConfig) == "table"
            and type(mpConfig.maxPlayers) == "number"
            and mpConfig.maxPlayers > 0
        then math.floor(mpConfig.maxPlayers)
        else math.huge

    local now = os.clock()
    local focusPoints = {}
    for userId, entry in pairs(playerFocusRegistry) do
        local position = entry.position
        local velocity = entry.velocity or Vector3.zero
        local updatedAt = entry.updatedAt or now
        if (now - updatedAt) > staleTimeout then
            -- Try fallback to live HumanoidRootPart before discarding.
            local fallbackPos, fallbackVelocity = resolvePlayerRootPosition(entry.player)
            if typeof(fallbackPos) == "Vector3" then
                position = fallbackPos
                velocity = fallbackVelocity or Vector3.zero
            else
                position = nil
            end
        end
        if typeof(position) == "Vector3" then
            focusPoints[#focusPoints + 1] = {
                player = entry.player,
                userId = userId,
                position = position,
                velocity = velocity,
                updatedAt = updatedAt,
            }
        end
    end

    if #focusPoints > maxPlayers then
        -- Deterministic cap: keep the maxPlayers most recently updated entries.
        table.sort(focusPoints, function(a, b)
            return (a.updatedAt or 0) > (b.updatedAt or 0)
        end)
        for index = #focusPoints, maxPlayers + 1, -1 do
            focusPoints[index] = nil
        end
    end

    return focusPoints
end

-- Public: project a player's reported position forward by the configured
-- velocity prediction window so the streaming scheduler prefetches chunks
-- ahead of where each player is heading.
function StreamingService.PredictPlayerFocusPosition(focus, config)
    if type(focus) ~= "table" or typeof(focus.position) ~= "Vector3" then
        return nil
    end
    local mpConfig = resolveMultiplayerConfig(config)
    local predictionSeconds = if type(mpConfig) == "table"
            and type(mpConfig.velocityPredictionSeconds) == "number"
        then math.max(0, mpConfig.velocityPredictionSeconds)
        else 2
    if predictionSeconds <= 0 or typeof(focus.velocity) ~= "Vector3" then
        return focus.position
    end
    return focus.position + focus.velocity * predictionSeconds
end

-- Public: bind Players.PlayerAdded / PlayerRemoving so player focus tracking
-- stays in sync with connection lifecycle. Idempotent; subsequent calls
-- replace any previously bound connections.
function StreamingService.BindPlayerLifecycle(spawnPoint)
    if playerLifecycleConnections then
        for _, connection in ipairs(playerLifecycleConnections) do
            if typeof(connection) == "RBXScriptConnection" then
                connection:Disconnect()
            end
        end
        playerLifecycleConnections = nil
    end

    local seedPosition = if typeof(spawnPoint) == "Vector3" then spawnPoint else nil

    local function onPlayerAdded(player)
        if seedPosition then
            -- Pre-seed the focus registry so the streaming scheduler will load
            -- chunks around the player's spawn point BEFORE the character
            -- materializes. Without this seed, brand-new players would briefly
            -- look at empty geometry while their first client position report
            -- propagates to the server.
            StreamingService.RegisterPlayerFocus(player, seedPosition, Vector3.zero)
        end
        player.CharacterAdded:Connect(function(character)
            local rootPart = character:WaitForChild("HumanoidRootPart", 5)
            if rootPart and rootPart:IsA("BasePart") then
                StreamingService.RegisterPlayerFocus(player, rootPart.Position, Vector3.zero)
            end
        end)
    end

    playerLifecycleConnections = {}
    playerLifecycleConnections[#playerLifecycleConnections + 1] = Players.PlayerAdded:Connect(onPlayerAdded)
    playerLifecycleConnections[#playerLifecycleConnections + 1] = Players.PlayerRemoving:Connect(function(player)
        StreamingService.UnregisterPlayerFocus(player)
    end)
    -- Seed every player already connected at bind time.
    for _, player in ipairs(Players:GetPlayers()) do
        onPlayerAdded(player)
    end
end

-- Public: install a server-side RemoteEvent that clients invoke at
-- MultiplayerStreaming.clientReportIntervalSeconds cadence with their current
-- camera position and velocity. The remote is created lazily under
-- ReplicatedStorage so both server and client can resolve it by name.
function StreamingService.BindClientPositionRemote()
    if clientPositionRemoteConnection then
        clientPositionRemoteConnection:Disconnect()
        clientPositionRemoteConnection = nil
    end
    if clientPositionRemote == nil or clientPositionRemote.Parent == nil then
        local existing = ReplicatedStorage:FindFirstChild(CLIENT_POSITION_REMOTE_NAME)
        if existing and existing:IsA("RemoteEvent") then
            clientPositionRemote = existing
        else
            clientPositionRemote = Instance.new("RemoteEvent")
            clientPositionRemote.Name = CLIENT_POSITION_REMOTE_NAME
            clientPositionRemote.Parent = ReplicatedStorage
        end
    end
    clientPositionRemoteConnection = clientPositionRemote.OnServerEvent:Connect(function(player, position, velocity)
        if typeof(position) ~= "Vector3" then
            return
        end
        if typeof(velocity) ~= "Vector3" then
            velocity = Vector3.zero
        end
        StreamingService.RegisterPlayerFocus(player, position, velocity)
    end)
    return clientPositionRemote
end

function StreamingService.GetClientPositionRemoteName()
    return CLIENT_POSITION_REMOTE_NAME
end

-- Test/diagnostics helper: clear the entire focus registry. Used by harness
-- specs to reset state between cases.
function StreamingService.ResetPlayerFocusRegistry()
    playerFocusRegistry = {}
end

local function shouldForceMovementLodRefresh()
    if typeof(streamingLastFocalPoint) ~= "Vector3" then
        return false
    end

    local livePlayerRootFocusPos = resolveLivePlayerRootFocusPosition()
    if typeof(livePlayerRootFocusPos) ~= "Vector3" then
        return false
    end

    local movementDelta = Vector3.new(
        livePlayerRootFocusPos.X - streamingLastFocalPoint.X,
        0,
        livePlayerRootFocusPos.Z - streamingLastFocalPoint.Z
    )
    if movementDelta.Magnitude < LOD_MOVEMENT_REFRESH_THRESHOLD_STUDS then
        return false
    end

    return true
end

-- Toggle visibility of LOD-tagged detail and interior parts based on camera plus live avatar/root focus.
-- Runs at LOD_UPDATE_INTERVAL cadence — cheap: iterates CollectionService lists,
-- not the full workspace tree.
local function updateLOD()
    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end
    local camPos = camera.CFrame.Position
    local avatarFocusPos = streamingLastFocalPoint
    local livePlayerRootFocusPos = resolveLivePlayerRootFocusPosition()
    if typeof(livePlayerRootFocusPos) == "Vector3" then
        avatarFocusPos = livePlayerRootFocusPos
    end
    local config = streamingOptions and (streamingOptions.config or DefaultWorldConfig) or DefaultWorldConfig
    local highDetailRadius = config.HighDetailRadius or 2048
    local interiorRadius = highDetailRadius * 0.25 -- interiors only very close

    local resolvedRings = streamingResolvedRings
    for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks(streamingOptions.worldRootName)) do
        local chunkEntry = ChunkLoader.GetChunkEntry(chunkId, streamingOptions.worldRootName)
        updateChunkEntryLodGroups(chunkEntry, camPos, avatarFocusPos, highDetailRadius, interiorRadius)

        -- Ring-based transparency ramping: far chunks fade slightly to sell depth
        if resolvedRings and chunkEntry then
            local chunkRef = streamingChunkRefsById and streamingChunkRefsById[chunkId]
            if chunkRef then
                local chunkSizeStuds = config.ChunkSizeStuds or 256
                local distSq = ChunkPriority.GetChunkFootprintDistanceSq(chunkRef, camPos, chunkSizeStuds)
                local ringName = getChunkRingName(distSq, resolvedRings)
                applyRingTransparency(chunkEntry, ringName or "near")
            end
        end
    end
end

function StreamingService.Start(manifest, options)
    if heartbeatConn then
        StreamingService.Stop()
    end

    local worldRootName = if type(options) == "table" then options.worldRootName else nil
    if type(worldRootName) ~= "string" or worldRootName == "" then
        worldRootName = DEFAULT_WORLD_ROOT_NAME
    end

    if #ChunkLoader.ListLoadedChunks(worldRootName) == 0 then
        ImportService.ResetSubplanState(nil, worldRootName)
    end

    streamingManifest = manifest
    streamingChunkRefs = manifest and (manifest.chunkRefs or manifest.chunks) or nil
    streamingChunkRefsById = buildChunkRefById(streamingChunkRefs)
    streamingChunkRefsByOrigin = buildChunkRefByOrigin(streamingChunkRefs)
    streamingOptions = table.clone(options or {})
    streamingOptions.worldRootName = worldRootName
    local config = streamingOptions.config or DefaultWorldConfig
    streamingResolvedRings = resolveStreamingRings(config)
    reconcileLoadedChunksForStart(streamingChunkRefs, streamingOptions.worldRootName)
    streamingSubplanRollout = SubplanRollout.Describe(config)
    streamingPreferredForward = if typeof(streamingOptions.preferredLookVector) == "Vector3"
        then streamingOptions.preferredLookVector
        else nil
    streamingLastFocalPoint = nil
    streamingLastFocalAt = nil
    -- Fresh starts should not inherit stale heartbeat cadence from prior runs.
    -- Tests and harnesses explicitly drive the first Update() when they need it.
    lastUpdate = os.clock()
    streamingChunkOptionsByLod = buildChunkOptionsByLod(streamingOptions, config)
    streamingChunkIndex = buildChunkSpatialIndex(streamingChunkRefs, config)
    seedLoadedChunkLods(streamingChunkOptionsByLod, streamingOptions.worldRootName)
    streamingMemoryGuardrail = MemoryGuardrail.New(MemoryGuardrail.ResolveConfig(config.MemoryGuardrails))
    table.clear(lodGroupFootprintBoundsCache)
    table.clear(streamingResidentEstimatedCostById)
    importedBuildingLodById = {}
    inflightChunkImports = {}
    lodUpgradeCount = 0
    seedResidentEstimatedCosts(streamingChunkRefs, config, streamingOptions.worldRootName)

    if not config.StreamingEnabled then
        Logger.warn("StreamingService.Start called but StreamingEnabled is false in config")
        return
    end

    Workspace:SetAttribute("ArnisStreamingSubplanRolloutEnabled", streamingSubplanRollout.enabled)
    Workspace:SetAttribute("ArnisStreamingSubplanRolloutMode", streamingSubplanRollout.mode)
    Workspace:SetAttribute("ArnisStreamingSubplanRolloutAllowedLayerCount", streamingSubplanRollout.allowedLayerCount)
    Workspace:SetAttribute(
        "ArnisStreamingSubplanRolloutAllowlistedChunkCount",
        streamingSubplanRollout.allowlistedChunkCount
    )
    refreshMemoryGuardrailTelemetry(streamingMemoryGuardrail:GetConfig(), 0)
    resetStreamingResidencyTelemetry()
    Logger.info("StreamingService started for world:", manifest.meta.worldName)
    Logger.info(
        "StreamingService subplan rollout:",
        streamingSubplanRollout.mode,
        "enabled=" .. tostring(streamingSubplanRollout.enabled),
        "layers=" .. tostring(streamingSubplanRollout.allowedLayerCount),
        "chunks=" .. tostring(streamingSubplanRollout.allowlistedChunkCount)
    )
    StreamingService.Update()
    updateLOD()

    heartbeatConn = RunService.Heartbeat:Connect(function(dt)
        local now = os.clock()
        local updateInterval = normalizePositiveNumber(config.StreamingUpdateIntervalSeconds) or DEFAULT_UPDATE_INTERVAL
        if now - lastUpdate >= updateInterval then
            lastUpdate = now
            StreamingService.Update()
        end

        lastLODUpdate = lastLODUpdate + dt
        if shouldForceMovementLodRefresh() then
            lastLODUpdate = LOD_UPDATE_INTERVAL
        end
        if lastLODUpdate >= LOD_UPDATE_INTERVAL then
            lastLODUpdate = 0
            updateLOD()
        end
    end)
end

function StreamingService.Stop()
    if heartbeatConn then
        heartbeatConn:Disconnect()
        heartbeatConn = nil
    end
    streamingManifest = nil
    streamingChunkRefs = nil
    streamingChunkIndex = nil
    streamingOptions = nil
    streamingChunkOptionsByLod = nil
    streamingLastFocalPoint = nil
    streamingLastFocalAt = nil
    streamingPreferredForward = nil
    streamingSubplanRollout = nil
    streamingMemoryGuardrail = nil
    streamingChunkRefsById = nil
    streamingChunkRefsByOrigin = nil
    streamingResolvedRings = nil
    table.clear(lodGroupFootprintBoundsCache)
    table.clear(observedChunkImportMsById)
    table.clear(streamingResidentEstimatedCostById)
    loadedChunkLods = {}
    loadedChunkRings = {}
    chunkFirstNotDesiredAt = {}
    importedBuildingLodById = {}
    inflightChunkImports = {}
    lodUpgradeCount = 0
    streamingUpdateInProgress = false
    streamingLastPrefetchReason = ""
    streamingLastEvictionReason = ""
    lastUpdate = 0
    lastLODUpdate = 0
    clearMemoryGuardrailTelemetry()
    resetStreamingResidencyTelemetry()
    -- Drop multiplayer lifecycle bindings on stop. The focus registry itself
    -- is preserved so a subsequent Start() inherits any focuses that were
    -- pre-seeded by external bootstrap code; tests can call
    -- ResetPlayerFocusRegistry() to wipe it explicitly.
    if playerLifecycleConnections then
        for _, connection in ipairs(playerLifecycleConnections) do
            if typeof(connection) == "RBXScriptConnection" then
                connection:Disconnect()
            end
        end
        playerLifecycleConnections = nil
    end
    if clientPositionRemoteConnection then
        clientPositionRemoteConnection:Disconnect()
        clientPositionRemoteConnection = nil
    end
end

function StreamingService.Update(focalPoint)
    if streamingUpdateInProgress then
        return
    end

    streamingUpdateInProgress = true
    local ok, err = xpcall(function()
        if not streamingManifest or not streamingChunkRefs then
            return
        end

        local config = streamingOptions.config or DefaultWorldConfig

        -- Multiplayer focus selection. When MultiplayerStreaming is enabled the
        -- server picks one player as the "primary" focus (the closest to the
        -- world origin among reported focuses, falling back to whichever player
        -- has the freshest report) and remembers the rest as `secondaryFocuses`.
        -- The primary drives the existing single-player Update() body verbatim;
        -- secondaries are processed by the multiplayer sweep below the main
        -- candidate loop, which expands desiredChunkIds and queues additional
        -- import work items so chunks around every player stay loaded.
        local multiplayerEnabled = isMultiplayerStreamingEnabled(config)
        local secondaryFocuses = nil

        local playerPos = focalPoint
        if multiplayerEnabled and not playerPos then
            local mpFocusPoints = StreamingService.GetAllPlayerFocusPoints(config)
            if #mpFocusPoints > 0 then
                -- Pick the focus with the freshest update as primary so the
                -- camera-tracking heuristics (movement prediction, lookahead)
                -- still see continuous deltas tick-to-tick. The remaining
                -- focuses are processed in the multiplayer sweep.
                table.sort(mpFocusPoints, function(a, b)
                    return (a.updatedAt or 0) > (b.updatedAt or 0)
                end)
                local primaryFocus = mpFocusPoints[1]
                playerPos = StreamingService.PredictPlayerFocusPosition(primaryFocus, config)
                if #mpFocusPoints > 1 then
                    secondaryFocuses = {}
                    for index = 2, #mpFocusPoints do
                        secondaryFocuses[#secondaryFocuses + 1] = mpFocusPoints[index]
                    end
                end
            end
        end

        if not playerPos then
            local player = Players:GetPlayers()[1]
            local character = player and player.Character
            local rootPart = character and character:FindFirstChild("HumanoidRootPart")
            if not rootPart then
                return
            end
            playerPos = rootPart.Position
        end

        -- (config already resolved above so multiplayer detection runs first)
        pruneStaleResidentEstimatedCosts(streamingOptions.worldRootName)
        observeHostProbeSample()
        local resolvedRings = streamingResolvedRings or resolveStreamingRings(config)
        local targetRadius = resolvedRings.far.MaxRadiusStuds
        local highRadius = resolvedRings.near.MaxRadiusStuds
        local chunkSizeStuds = config.ChunkSizeStuds or DefaultWorldConfig.ChunkSizeStuds or 256

        local targetRadiusSq = targetRadius * targetRadius
        local highRadiusSq = highRadius * highRadius
        local highExitRadius = getExitRadius(highRadius, targetRadius)
        local targetExitRadius = getExitRadius(targetRadius, nil)
        local highExitRadiusSq = highExitRadius * highExitRadius
        local targetExitRadiusSq = targetExitRadius * targetExitRadius
        local interiorRadius = highRadius * 0.25
        local movementForward, schedulerFocusPoint, movementDeltaStuds, movementLookaheadStuds =
            resolveSchedulerFocusPoint(playerPos, config)
        local forwardVector = movementForward or streamingPreferredForward

        local desiredChunkIds = {}
        -- Incrementally maintained count of `desiredChunkIds` so we can skip
        -- an O(n) `for _, _ in pairs(...)` sweep later in this function. The
        -- main candidate loop and the multiplayer secondary sweep both mark
        -- chunks desired through the helper below; callers that previously
        -- assigned `desiredChunkIds[id] = true` go through setDesiredChunkId
        -- to keep the count in sync.
        local desiredChunkCount = 0
        local function setDesiredChunkId(chunkId)
            if not desiredChunkIds[chunkId] then
                desiredChunkIds[chunkId] = true
                desiredChunkCount += 1
            end
        end
        local desiredRingStats = {
            near = { chunkCount = 0, estimatedCost = 0 },
            mid = { chunkCount = 0, estimatedCost = 0 },
            far = { chunkCount = 0, estimatedCost = 0 },
        }
        -- Track resident bytes per ring for the per-ring memory guardrail.
        -- We seed from the current `loadedChunkRings` snapshot and then mutate
        -- this table as we admit and evict chunks during this tick so admission
        -- decisions for later candidates see an accurate, up-to-date pressure
        -- level. This is the mechanism that prevents far-ring minimal LOD
        -- chunks from competing with near-ring full-detail chunks for the same
        -- memory pool.
        local ringResidentBytes = computeRingResidentBytes()
        local ringDeferredAdmissions = { near = 0, mid = 0, far = 0 }
        local queuedEstimatedCost = 0
        local queuedWorkItemCount = 0
        local evictedEstimatedCost = 0
        local evictedChunkCount = 0
        local lastPrefetchReason = ""
        local lastEvictionReason = ""
        local candidateChunkEntries =
            getSchedulerCandidateChunkRefs(streamingChunkIndex, playerPos, schedulerFocusPoint, targetExitRadius)
        local importWorkItems = {}
        ChunkPriority.SortChunkEntriesByPriority(
            candidateChunkEntries,
            schedulerFocusPoint,
            playerPos,
            chunkSizeStuds,
            forwardVector,
            observedChunkImportMsById
        )

        for _, chunkEntry in ipairs(candidateChunkEntries) do
            local chunkRef = chunkEntry.ref
            local actualDistSq = getChunkDistanceSqToPoint(chunkEntry, playerPos)
            local schedulerDistSq = actualDistSq
            if typeof(schedulerFocusPoint) == "Vector3" then
                schedulerDistSq = math.min(actualDistSq, getChunkDistanceSqToPoint(chunkEntry, schedulerFocusPoint))
            end

            local currentLod = loadedChunkLods[chunkRef.id]
            local targetLod = chooseTargetLod(
                schedulerDistSq,
                currentLod,
                highRadiusSq,
                highExitRadiusSq,
                targetRadiusSq,
                targetExitRadiusSq
            )
            local ringName = getChunkRingName(actualDistSq, resolvedRings)
            local chunkBuildingLodLevel = resolveBuildingLodLevel(ringName, streamingOptions.config)

            -- High-velocity prefetch: when the player is moving fast (jetpack,
            -- aircraft, parachute), brand-new prefetched chunks come in at the
            -- minimal LOD so they can land before the player flies over them.
            -- Already-loaded chunks keep whatever LOD they have — the existing
            -- LOD re-import path will upgrade them once the player slows down
            -- and the velocity class drops back to walking.
            if
                streamingForceMinimalLodForPrefetch
                and currentLod == nil
                and importedBuildingLodById[chunkRef.id] == nil
                and (BUILDING_LOD_DETAIL_RANK[chunkBuildingLodLevel] or 0)
                    > (BUILDING_LOD_DETAIL_RANK.minimal or 0)
            then
                chunkBuildingLodLevel = "minimal"
            end

            if targetLod then
                local ring = if ringName then resolvedRings[ringName] else nil
                local estimatedChunkCost = getEstimatedChunkOrSubplanCost(chunkRef, nil)
                local ringStats = if ringName then desiredRingStats[ringName] else nil
                local exceedsRingChunkLimit = ring ~= nil
                    and ring.MaxChunkCount > 0
                    and ringStats.chunkCount >= ring.MaxChunkCount
                -- Ring byte budgets are planning targets published through scheduler telemetry.
                -- The hard admission stop line is the memory guardrail, so do not filter in-ring
                -- work here purely for exceeding a ring's estimated-byte target.
                if ring == nil or exceedsRingChunkLimit then
                    if
                        currentLod ~= nil
                        or ChunkLoader.GetChunkEntry(chunkRef.id, streamingOptions.worldRootName) ~= nil
                    then
                        -- Let the cooldown-based not-desired sweep handle resident chunks.
                        -- Immediate unload here causes visible add/remove churn before the
                        -- existing hysteresis window has a chance to absorb the bounce.
                        continue
                    end
                    if ring ~= nil then
                        queuedEstimatedCost += estimatedChunkCost
                        queuedWorkItemCount += 1
                    end
                    continue
                end

                -- Per-ring memory budget admission gate. Each ring owns a
                -- private byte budget; far-ring chunks must NOT be allowed
                -- to crowd out near-ring chunks just because the global
                -- guardrail still has headroom. If admitting this chunk would
                -- push the target ring over its EstimatedBudgetBytes, and the
                -- chunk is not already resident in this ring, defer it for
                -- this tick. The chunk is intentionally NOT marked desired,
                -- so the final not-desired sweep will leave existing chunks
                -- in other rings alone and only this chunk's slot is held
                -- back.
                local ringBudgetBytes = normalizeNonNegativeNumber(ring.EstimatedBudgetBytes)
                if ringBudgetBytes > 0 then
                    local chunkResidentInRing = loadedChunkRings[chunkRef.id] == ringName
                    local currentResident = if chunkResidentInRing
                        then getResidentEstimatedCostForChunkId(chunkRef.id)
                        else 0
                    local projected = ringResidentBytes[ringName] + estimatedChunkCost - currentResident
                    if projected > ringBudgetBytes and not chunkResidentInRing then
                        ringDeferredAdmissions[ringName] += 1
                        queuedEstimatedCost += estimatedChunkCost
                        queuedWorkItemCount += 1
                        lastPrefetchReason = ringName .. "_ring_budget_deferred"
                        continue
                    end
                end

                ringStats.chunkCount += 1
                ringStats.estimatedCost += estimatedChunkCost
                -- Attribute this chunk's resident bytes to the target ring.
                -- For chunks already resident in this ring, the per-ring
                -- snapshot is unchanged; for chunks moving in from another
                -- ring (or being newly admitted), shift / add the bytes.
                local previousRingForChunk = loadedChunkRings[chunkRef.id]
                if previousRingForChunk ~= ringName then
                    local existingResident = getResidentEstimatedCostForChunkId(chunkRef.id)
                    if previousRingForChunk == "near"
                        or previousRingForChunk == "mid"
                        or previousRingForChunk == "far"
                    then
                        ringResidentBytes[previousRingForChunk] = math.max(
                            0,
                            ringResidentBytes[previousRingForChunk] - existingResident
                        )
                    end
                    local addedBytes = if existingResident > 0 then existingResident else estimatedChunkCost
                    ringResidentBytes[ringName] += addedBytes
                    loadedChunkRings[chunkRef.id] = ringName
                end
                local chunkOptions = streamingChunkOptionsByLod[targetLod]
                local currentEntry = ChunkLoader.GetChunkEntry(chunkRef.id, streamingOptions.worldRootName)
                -- Skip chunks that already have an import work item in flight from a
                -- prior tick; the ongoing import will land soon and setting desired
                -- keeps eviction logic happy without burning redundant work items.
                if inflightChunkImports[chunkRef.id] then
                    setDesiredChunkId(chunkRef.id)
                    continue
                end
                if currentEntry then
                    -- LOD re-import: if the chunk's building LOD differs from what the
                    -- current ring demands, tear down and re-import. This handles both
                    -- upgrades (far→near) and downgrades (near→far), freeing memory
                    -- when the player moves away from a full-detail chunk.
                    local enableLodReimport = config.EnableLodReimport ~= false
                    local previousBuildingLod = importedBuildingLodById[chunkRef.id]
                    local previousRank = BUILDING_LOD_DETAIL_RANK[previousBuildingLod] or 0
                    local targetRank = BUILDING_LOD_DETAIL_RANK[chunkBuildingLodLevel] or 0
                    -- Downgrades are handled by ordinary eviction instead of in-place re-import.
                    -- Re-importing a resident chunk downward in detail tears out visible geometry
                    -- even when the chunk is still desired, which shows up as parity/fidelity loss
                    -- and near-part-count churn in live client_flicker telemetry.
                    local needsLodUpgrade = enableLodReimport
                        and previousBuildingLod ~= nil
                        and chunkBuildingLodLevel ~= nil
                        and targetRank > previousRank
                    if needsLodUpgrade then
                        -- Clear existing geometry IN PLACE and re-queue at the
                        -- new building LOD. Critical: pass preserveFolder=true
                        -- so the chunk's Folder Instance stays parented to
                        -- the worldRoot. If we let UnloadChunk destroy the
                        -- folder, the worldRoot fires ChildRemoved + ChildAdded
                        -- events on every LOD transition, and the
                        -- client_flicker detector counts each one as a thrash.
                        -- The walk harness captured ~90 such thrashes per
                        -- 25s walk session — that's the visible pop-in/pop-out
                        -- "flickering" the user sees in the live game.
                        -- With preserveFolder=true the folder lives across
                        -- the re-import, so ChildRemoved never fires and
                        -- the flicker detector stays quiet.
                        ChunkLoader.UnloadChunk(chunkRef.id, true, streamingOptions.worldRootName)
                        ImportService.ResetSubplanState(chunkRef.id, streamingOptions.worldRootName)
                        clearResidentEstimatedCostForChunk(chunkRef.id)
                        clearObservedImportCostForChunk(chunkRef.id)
                        loadedChunkLods[chunkRef.id] = nil
                        loadedChunkRings[chunkRef.id] = nil
                        importedBuildingLodById[chunkRef.id] = nil
                        lodUpgradeCount += 1
                        Workspace:SetAttribute("ArnisStreamingLodUpgradeCount", lodUpgradeCount)
                        appendStreamingWorkItems(importWorkItems, chunkEntry, chunkOptions, chunkOptions.config, targetLod, chunkBuildingLodLevel)
                        inflightChunkImports[chunkRef.id] = true
                        setDesiredChunkId(chunkRef.id)
                        lastPrefetchReason = "lod_upgrade"
                        continue
                    end

                    local changedLayers =
                        computeChangedLayers(currentEntry.layerSignatures, chunkOptions.layerSignatures)
                    if not changedLayers and currentEntry.configSignature == chunkOptions.configSignature then
                        loadedChunkLods[chunkRef.id] = targetLod
                        setDesiredChunkId(chunkRef.id)
                        if queuePendingSubplans(importWorkItems, chunkEntry, chunkOptions, targetLod, chunkBuildingLodLevel) then
                            lastPrefetchReason = "subplan_backfill"
                        end
                        continue
                    end
                    if not changedLayers then
                        if not queuePendingSubplans(importWorkItems, chunkEntry, chunkOptions, targetLod, chunkBuildingLodLevel) then
                            loadedChunkLods[chunkRef.id] = targetLod
                        else
                            lastPrefetchReason = "subplan_backfill"
                        end
                        setDesiredChunkId(chunkRef.id)
                        continue
                    end
                    chunkOptions = {
                        worldRootName = chunkOptions.worldRootName,
                        frameBudgetSeconds = chunkOptions.frameBudgetSeconds,
                        nonBlocking = chunkOptions.nonBlocking,
                        shouldCancel = chunkOptions.shouldCancel,
                        config = chunkOptions.config,
                        configSignature = chunkOptions.configSignature,
                        layerSignatures = chunkOptions.layerSignatures,
                        layers = changedLayers,
                    }
                end

                appendStreamingWorkItems(importWorkItems, chunkEntry, chunkOptions, chunkOptions.config, targetLod, chunkBuildingLodLevel)
                inflightChunkImports[chunkRef.id] = true
                setDesiredChunkId(chunkRef.id)
                if movementLookaheadStuds > 0 then
                    lastPrefetchReason = "movement_lookahead"
                elseif movementForward ~= nil then
                    lastPrefetchReason = "movement_heading"
                else
                    lastPrefetchReason = "ring_backfill"
                end
            else
                local currentEntry = ChunkLoader.GetChunkEntry(chunkRef.id, streamingOptions.worldRootName)
                if currentLod == nil and currentEntry == nil then
                    continue
                end
                -- Unload
                ChunkLoader.UnloadChunk(chunkRef.id, nil, streamingOptions.worldRootName)
                ImportService.ResetSubplanState(chunkRef.id, streamingOptions.worldRootName)
                clearResidentEstimatedCostForChunk(chunkRef.id)
                loadedChunkLods[chunkRef.id] = nil
                loadedChunkRings[chunkRef.id] = nil
                importedBuildingLodById[chunkRef.id] = nil
                inflightChunkImports[chunkRef.id] = nil
                lastEvictionReason = "outside_target_radius"
            end
        end

        -- desiredChunkCount is now maintained incrementally via setDesiredChunkId.

        ChunkPriority.SortWorkItems(
            importWorkItems,
            schedulerFocusPoint,
            playerPos,
            chunkSizeStuds,
            forwardVector,
            observedChunkImportMsById
        )

        local maxWorkItemsPerUpdate = config.StreamingMaxWorkItemsPerUpdate
        if type(maxWorkItemsPerUpdate) ~= "number" or maxWorkItemsPerUpdate < 1 then
            maxWorkItemsPerUpdate = #importWorkItems
        else
            maxWorkItemsPerUpdate = math.max(1, math.floor(maxWorkItemsPerUpdate))
        end

        local processedWorkItems = 0
        local deferredAdmissions = 0
        local deferredProjectedUsage = nil
        local memoryGuardrailConfig = if streamingMemoryGuardrail
            then streamingMemoryGuardrail:GetConfig()
            else MemoryGuardrail.ResolveConfig(nil)
        updateStreamingResidencyTelemetry(
            playerPos,
            schedulerFocusPoint,
            movementDeltaStuds,
            movementLookaheadStuds,
            resolvedRings,
            desiredRingStats,
            candidateChunkEntries,
            desiredChunkCount,
            processedWorkItems,
            queuedEstimatedCost,
            queuedWorkItemCount,
            evictedEstimatedCost,
            evictedChunkCount,
            lastPrefetchReason,
            lastEvictionReason,
            "planning"
        )
        refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions)
        for workItemIndex, workItem in ipairs(importWorkItems) do
            if processedWorkItems >= maxWorkItemsPerUpdate then
                break
            end

            local workItemCost = getEstimatedWorkItemCost(workItem)
            local residentCostToReplace = if memoryGuardrailConfig.CountResidentChunkCost == false
                then 0
                else getResidentEstimatedCostToReplace(workItem)
            local effectiveWorkItemCost = if memoryGuardrailConfig.CountInFlightCost == false then 0 else workItemCost
            local projectedUsage = (getEffectiveGuardrailResidentCost(memoryGuardrailConfig) - residentCostToReplace)
                + getEffectiveGuardrailInFlightCost(memoryGuardrailConfig)
                + effectiveWorkItemCost
            refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions, projectedUsage)
            if streamingMemoryGuardrail and streamingMemoryGuardrail:IsPaused() then
                local pressureReplacementChunkId, pressureReplacementCost = selectPressureReplacementChunk(
                    workItem,
                    projectedUsage,
                    desiredChunkIds,
                    schedulerFocusPoint,
                    chunkSizeStuds,
                    forwardVector,
                    memoryGuardrailConfig
                )
                if pressureReplacementChunkId ~= nil and pressureReplacementCost > 0 then
                    ChunkLoader.UnloadChunk(pressureReplacementChunkId, nil, streamingOptions.worldRootName)
                    ImportService.ResetSubplanState(pressureReplacementChunkId, streamingOptions.worldRootName)
                    clearResidentEstimatedCostForChunk(pressureReplacementChunkId)
                    clearObservedImportCostForChunk(pressureReplacementChunkId)
                    loadedChunkLods[pressureReplacementChunkId] = nil
                    evictedEstimatedCost += pressureReplacementCost
                    evictedChunkCount += 1
                    lastEvictionReason = "pressure_replacement"
                    projectedUsage -= pressureReplacementCost
                    refreshMemoryGuardrailTelemetry(
                        memoryGuardrailConfig,
                        deferredAdmissions,
                        projectedUsage
                    )
                    if not streamingMemoryGuardrail or not streamingMemoryGuardrail:IsPaused() then
                        refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions, projectedUsage)
                    else
                        updateStreamingResidencyTelemetry(
                            playerPos,
                            schedulerFocusPoint,
                            movementDeltaStuds,
                            movementLookaheadStuds,
                            resolvedRings,
                            desiredRingStats,
                            candidateChunkEntries,
                            desiredChunkCount,
                            processedWorkItems,
                            queuedEstimatedCost,
                            queuedWorkItemCount,
                            evictedEstimatedCost,
                            evictedChunkCount,
                            lastPrefetchReason,
                            lastEvictionReason,
                            "guardrail_paused"
                        )
                        break
                    end
                end
                if streamingMemoryGuardrail and streamingMemoryGuardrail:IsPaused() then
                deferredAdmissions = math.max(1, maxWorkItemsPerUpdate - processedWorkItems)
                if #importWorkItems >= workItemIndex then
                    deferredAdmissions = math.min(deferredAdmissions, #importWorkItems - workItemIndex + 1)
                end
                for queuedWorkItemIndex = workItemIndex, #importWorkItems do
                    queuedEstimatedCost += getEstimatedWorkItemCost(importWorkItems[queuedWorkItemIndex])
                end
                queuedWorkItemCount += #importWorkItems - workItemIndex + 1
                lastPrefetchReason = "memory_guardrail_paused"
                deferredProjectedUsage = projectedUsage
                refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions, projectedUsage)
                updateStreamingResidencyTelemetry(
                    playerPos,
                    schedulerFocusPoint,
                    movementDeltaStuds,
                    movementLookaheadStuds,
                    resolvedRings,
                    desiredRingStats,
                    candidateChunkEntries,
                    desiredChunkCount,
                    processedWorkItems,
                    queuedEstimatedCost,
                    queuedWorkItemCount,
                    evictedEstimatedCost,
                    evictedChunkCount,
                    lastPrefetchReason,
                    lastEvictionReason,
                        "guardrail_paused"
                    )
                break
                end
            end

            local chunkEntry = workItem.chunkEntry
            local chunkRef = chunkEntry.ref
            local chunk = getMaterializedChunk(chunkEntry)
            local terrainNeighborContext = buildStreamingTerrainNeighborContext(chunkRef)
            local importStartedAt = os.clock()
            if streamingMemoryGuardrail then
                streamingMemoryGuardrail:AdmitInFlightBytes(workItemCost)
                refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions, projectedUsage)
            end
            local importOk, importResult = xpcall(function()
                if workItem.subplan then
                    local subplanOptions = table.clone(workItem.chunkOptions)
                    subplanOptions.registrationChunk = chunkRef
                    subplanOptions.chunkSignature = ImportSignatures.GetChunkSignature(chunkRef)
                    subplanOptions.buildingLodLevel = workItem.buildingLodLevel
                    if terrainNeighborContext ~= nil then
                        subplanOptions.terrainNeighbors = terrainNeighborContext.neighbors
                        subplanOptions.terrainNeighborSignature = terrainNeighborContext.signature
                    end
                    return ImportService.ImportChunkSubplan(chunk, workItem.subplan, subplanOptions)
                else
                    local importOptions = table.clone(workItem.chunkOptions)
                    importOptions.chunkSignature = ImportSignatures.GetChunkSignature(chunkRef)
                    importOptions.buildingLodLevel = workItem.buildingLodLevel
                    if terrainNeighborContext ~= nil then
                        importOptions.terrainNeighbors = terrainNeighborContext.neighbors
                        importOptions.terrainNeighborSignature = terrainNeighborContext.signature
                    end
                    return ImportService.ImportChunk(chunk, importOptions)
                end
            end, debug.traceback)
            if streamingMemoryGuardrail then
                streamingMemoryGuardrail:CompleteInFlightBytes(workItemCost)
            end
            if not importOk then
                refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions)
                error(importResult, 0)
            end
            if importResult == nil then
                ImportService.RollbackCancelledImport(chunk, {
                    config = workItem.chunkOptions.config,
                    configSignature = workItem.chunkOptions.configSignature,
                    layerSignatures = workItem.chunkOptions.layerSignatures,
                    layers = workItem.chunkOptions.layers,
                    subplan = workItem.subplan,
                    worldRootName = workItem.chunkOptions.worldRootName,
                })
                clearResidentEstimatedCost(workItem)
                loadedChunkLods[chunkRef.id] = nil
                loadedChunkRings[chunkRef.id] = nil
                importedBuildingLodById[chunkRef.id] = nil
                inflightChunkImports[chunkRef.id] = nil
                refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions)
                break
            end
            recordResidentEstimatedCost(workItem, workItemCost)
            refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions)
            local elapsedMs = (os.clock() - importStartedAt) * 1000
            local observedCostKey = ChunkPriority.GetObservedCostKey(
                chunkRef.id,
                type(workItem.subplan) == "table" and workItem.subplan.id or nil
            ) or chunkRef.id
            local previous = observedChunkImportMsById[observedCostKey]
            if previous == nil then
                observedChunkImportMsById[observedCostKey] = elapsedMs
            else
                observedChunkImportMsById[observedCostKey] = previous * 0.7 + elapsedMs * 0.3
            end
            loadedChunkLods[chunkRef.id] = workItem.targetLod or loadedChunkLods[chunkRef.id]
            -- Track the building LOD level the chunk was imported at for re-import detection.
            -- Subplan imports don't replace the whole chunk, so only record for whole-chunk imports.
            if workItem.buildingLodLevel and not workItem.subplan then
                importedBuildingLodById[chunkRef.id] = workItem.buildingLodLevel
            elseif workItem.buildingLodLevel and importedBuildingLodById[chunkRef.id] == nil then
                importedBuildingLodById[chunkRef.id] = workItem.buildingLodLevel
            end
            -- Import is no longer in-flight; allow future re-imports / LOD upgrades.
            inflightChunkImports[chunkRef.id] = nil
            local importedChunkEntry = ChunkLoader.GetChunkEntry(chunkRef.id, streamingOptions.worldRootName)
            if importedChunkEntry ~= nil then
                local immediateCameraFocusPos = resolveCurrentCameraFocusPosition()
                updateChunkEntryLodGroups(
                    importedChunkEntry,
                    immediateCameraFocusPos,
                    playerPos,
                    highRadius,
                    interiorRadius
                )
                -- Smooth chunk transition: fade in newly imported geometry over 0.3s
                -- to eliminate pop-in. Runs on a deferred thread so it doesn't block
                -- the import work loop.
                if importedChunkEntry.folder and config.EnableChunkFadeIn ~= false then
                    task.defer(function()
                        local folder = importedChunkEntry.folder
                        if not folder or not folder.Parent then
                            return
                        end
                        for _, desc in ipairs(folder:GetDescendants()) do
                            if desc:IsA("BasePart") and not desc:GetAttribute("ArnisBaseTransparency") then
                                local baseT = desc.Transparency
                                desc:SetAttribute("ArnisBaseTransparency", baseT)
                                desc.Transparency = 1
                                local TweenService = game:GetService("TweenService")
                                TweenService:Create(desc, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                                    Transparency = baseT,
                                }):Play()
                            end
                        end
                    end)
                end
            end
            processedWorkItems += 1
        end

        -- ─── MULTIPLAYER SECONDARY-PLAYER SWEEP ───
        -- For every player beyond the primary focus, expand desiredChunkIds
        -- with chunks within MultiplayerStreaming.perPlayerStreamingRadius of
        -- that player and queue extra import work items for any chunks that
        -- are not yet resident. Per-chunk LOD ends up as the maximum demanded
        -- by any player because chunks already loaded for the primary at
        -- "near"/"full" detail are simply marked desired here and skipped;
        -- chunks that the primary placed at "far"/"minimal" but a secondary
        -- now needs at "full" will be upgraded on a subsequent tick by the
        -- existing LOD re-import path once that secondary becomes the primary
        -- (or via an explicit upgrade pass below).
        if multiplayerEnabled and secondaryFocuses ~= nil and #secondaryFocuses > 0 then
            local mpConfig = resolveMultiplayerConfig(config)
            local perPlayerRadius = if type(mpConfig) == "table"
                    and type(mpConfig.perPlayerStreamingRadius) == "number"
                    and mpConfig.perPlayerStreamingRadius > 0
                then mpConfig.perPlayerStreamingRadius
                else 1024
            local perPlayerRadiusSq = perPlayerRadius * perPlayerRadius
            local secondaryWorkItems = {}
            local seenSecondaryChunks = {}
            for _, focus in ipairs(secondaryFocuses) do
                local predicted = StreamingService.PredictPlayerFocusPosition(focus, config) or focus.position
                local secondaryCandidates =
                    getSchedulerCandidateChunkRefs(streamingChunkIndex, predicted, predicted, perPlayerRadius)
                for _, chunkEntry in ipairs(secondaryCandidates) do
                    local chunkRef = chunkEntry.ref
                    if seenSecondaryChunks[chunkRef.id] then
                        continue
                    end
                    seenSecondaryChunks[chunkRef.id] = true
                    local distSq = getChunkDistanceSqToPoint(chunkEntry, predicted)
                    if distSq > perPlayerRadiusSq then
                        continue
                    end
                    -- Always mark this chunk as desired so the not-desired
                    -- eviction sweep below leaves it alone.
                    setDesiredChunkId(chunkRef.id)
                    -- Determine the LOD this secondary player demands. Use the
                    -- closest player's distance for this chunk so per-chunk
                    -- LOD is correctly the max across all players.
                    local schedulerDistSq = distSq
                    local currentLod = loadedChunkLods[chunkRef.id]
                    local targetLod = chooseTargetLod(
                        schedulerDistSq,
                        currentLod,
                        highRadiusSq,
                        highExitRadiusSq,
                        targetRadiusSq,
                        targetExitRadiusSq
                    )
                    if not targetLod then
                        continue
                    end
                    local ringName = getChunkRingName(distSq, resolvedRings)
                    local chunkBuildingLodLevel = resolveBuildingLodLevel(ringName, streamingOptions.config)
                    if inflightChunkImports[chunkRef.id] then
                        continue
                    end
                    local chunkOptions = streamingChunkOptionsByLod[targetLod]
                    local currentEntry = ChunkLoader.GetChunkEntry(chunkRef.id, streamingOptions.worldRootName)
                    if currentEntry then
                        -- Already resident; skip queuing additional work. The
                        -- LOD upgrade for this secondary will run on a future
                        -- tick if/when the primary focus rotates to this
                        -- player.
                        loadedChunkLods[chunkRef.id] = loadedChunkLods[chunkRef.id] or targetLod
                        loadedChunkRings[chunkRef.id] = loadedChunkRings[chunkRef.id] or ringName
                        continue
                    end
                    appendStreamingWorkItems(
                        secondaryWorkItems,
                        chunkEntry,
                        chunkOptions,
                        chunkOptions.config,
                        targetLod,
                        chunkBuildingLodLevel
                    )
                    inflightChunkImports[chunkRef.id] = true
                    loadedChunkRings[chunkRef.id] = ringName
                    lastPrefetchReason = "multiplayer_secondary"
                end
            end
            -- Process secondary work items under the same per-update budget.
            ChunkPriority.SortWorkItems(
                secondaryWorkItems,
                playerPos,
                playerPos,
                chunkSizeStuds,
                forwardVector,
                observedChunkImportMsById
            )
            for _, workItem in ipairs(secondaryWorkItems) do
                if processedWorkItems >= maxWorkItemsPerUpdate then
                    break
                end
                local workItemCost = getEstimatedWorkItemCost(workItem)
                if streamingMemoryGuardrail and streamingMemoryGuardrail:IsPaused() then
                    break
                end
                local chunkEntry = workItem.chunkEntry
                local chunkRef = chunkEntry.ref
                local chunk = getMaterializedChunk(chunkEntry)
                local terrainNeighborContext = buildStreamingTerrainNeighborContext(chunkRef)
                if streamingMemoryGuardrail then
                    streamingMemoryGuardrail:AdmitInFlightBytes(workItemCost)
                end
                local importOk, importResult = xpcall(function()
                    if workItem.subplan then
                        local subplanOptions = table.clone(workItem.chunkOptions)
                        subplanOptions.registrationChunk = chunkRef
                        subplanOptions.chunkSignature = ImportSignatures.GetChunkSignature(chunkRef)
                        subplanOptions.buildingLodLevel = workItem.buildingLodLevel
                        if terrainNeighborContext ~= nil then
                            subplanOptions.terrainNeighbors = terrainNeighborContext.neighbors
                            subplanOptions.terrainNeighborSignature = terrainNeighborContext.signature
                        end
                        return ImportService.ImportChunkSubplan(chunk, workItem.subplan, subplanOptions)
                    else
                        local importOptions = table.clone(workItem.chunkOptions)
                        importOptions.chunkSignature = ImportSignatures.GetChunkSignature(chunkRef)
                        importOptions.buildingLodLevel = workItem.buildingLodLevel
                        if terrainNeighborContext ~= nil then
                            importOptions.terrainNeighbors = terrainNeighborContext.neighbors
                            importOptions.terrainNeighborSignature = terrainNeighborContext.signature
                        end
                        return ImportService.ImportChunk(chunk, importOptions)
                    end
                end, debug.traceback)
                if streamingMemoryGuardrail then
                    streamingMemoryGuardrail:CompleteInFlightBytes(workItemCost)
                end
                if not importOk then
                    inflightChunkImports[chunkRef.id] = nil
                    error(importResult, 0)
                end
                if importResult == nil then
                    inflightChunkImports[chunkRef.id] = nil
                else
                    recordResidentEstimatedCost(workItem, workItemCost)
                    loadedChunkLods[chunkRef.id] = workItem.targetLod or loadedChunkLods[chunkRef.id]
                    if workItem.buildingLodLevel and not workItem.subplan then
                        importedBuildingLodById[chunkRef.id] = workItem.buildingLodLevel
                    end
                    inflightChunkImports[chunkRef.id] = nil
                    processedWorkItems += 1
                end
            end
        end

        local sweepNow = os.clock()
        for chunkId, _ in pairs(loadedChunkLods) do
            if desiredChunkIds[chunkId] then
                -- Chunk is desired again (or still desired) — clear any
                -- lingering not-desired stamp. This resets the cooldown
                -- so a chunk that flaps in and out many times doesn't
                -- accumulate credit toward eviction.
                if chunkFirstNotDesiredAt[chunkId] ~= nil then
                    chunkFirstNotDesiredAt[chunkId] = nil
                end
            else
                local firstSeenAt = chunkFirstNotDesiredAt[chunkId]
                if firstSeenAt == nil then
                    -- First tick this chunk dropped out of the desired
                    -- set. Stamp it and DO NOT evict yet — give the
                    -- player a chance to cross back over the boundary
                    -- and re-desire it. Without this grace period, a
                    -- moving player thrashes chunks at ~88 admits+evicts
                    -- per 25s walk (captured via client_flicker telemetry).
                    chunkFirstNotDesiredAt[chunkId] = sweepNow
                elseif sweepNow - firstSeenAt >= STREAMING_EVICTION_COOLDOWN_SECONDS then
                    local resolvedEvictionReason = "not_desired_for_ring_budget"
                    local chunkRef = streamingChunkRefsById and streamingChunkRefsById[chunkId] or nil
                    if chunkRef ~= nil then
                        local chunkFootprintDistanceSq =
                            ChunkPriority.GetChunkFootprintDistanceSq(chunkRef, playerPos, chunkSizeStuds)
                        if chunkFootprintDistanceSq > targetExitRadiusSq then
                            resolvedEvictionReason = "outside_target_radius"
                        end
                    end
                    ChunkLoader.UnloadChunk(chunkId, nil, streamingOptions.worldRootName)
                    ImportService.ResetSubplanState(chunkId, streamingOptions.worldRootName)
                    evictedEstimatedCost += getResidentEstimatedCostForChunkId(chunkId)
                    evictedChunkCount += 1
                    clearResidentEstimatedCostForChunk(chunkId)
                    loadedChunkLods[chunkId] = nil
                    loadedChunkRings[chunkId] = nil
                    importedBuildingLodById[chunkId] = nil
                    inflightChunkImports[chunkId] = nil
                    chunkFirstNotDesiredAt[chunkId] = nil
                    lastEvictionReason = resolvedEvictionReason
                end
                -- else: still in cooldown window → skip eviction this tick
            end
        end

        -- Per-ring forced eviction. Recompute resident bytes per ring after
        -- the in-tick admission and not-desired sweeps, then for each ring
        -- that is still over its EstimatedBudgetBytes, evict the FURTHEST
        -- chunk(s) from THAT ring until the ring fits its budget. This keeps
        -- far-ring minimal LOD chunks from monopolising memory that the near
        -- ring needs.
        local function evictChunkForRingBudget(chunkId, ringName)
            ChunkLoader.UnloadChunk(chunkId, nil, streamingOptions.worldRootName)
            ImportService.ResetSubplanState(chunkId, streamingOptions.worldRootName)
            local cost = getResidentEstimatedCostForChunkId(chunkId)
            evictedEstimatedCost += cost
            evictedChunkCount += 1
            clearResidentEstimatedCostForChunk(chunkId)
            clearObservedImportCostForChunk(chunkId)
            loadedChunkLods[chunkId] = nil
            loadedChunkRings[chunkId] = nil
            importedBuildingLodById[chunkId] = nil
            inflightChunkImports[chunkId] = nil
            if desiredChunkIds[chunkId] then
                desiredChunkIds[chunkId] = nil
                desiredChunkCount -= 1
            end
            lastEvictionReason = ringName .. "_ring_budget_exceeded"
            return cost
        end

        ringResidentBytes = computeRingResidentBytes()
        for _, ringName in ipairs(STREAMING_RING_ORDER) do
            local ring = resolvedRings[ringName]
            local budget = ring and normalizeNonNegativeNumber(ring.EstimatedBudgetBytes) or 0
            if budget > 0 and ringResidentBytes[ringName] > budget then
                -- Collect this ring's chunks ordered by descending distance.
                local ringChunks = {}
                for chunkId, chunkRingName in pairs(loadedChunkRings) do
                    if chunkRingName == ringName then
                        local chunkRef = streamingChunkRefsById and streamingChunkRefsById[chunkId] or nil
                        local distSq = if chunkRef ~= nil
                            then ChunkPriority.GetChunkFootprintDistanceSq(chunkRef, playerPos, chunkSizeStuds)
                            else math.huge
                        ringChunks[#ringChunks + 1] = { id = chunkId, distSq = distSq }
                    end
                end
                table.sort(ringChunks, function(a, b)
                    return a.distSq > b.distSq
                end)
                for _, entry in ipairs(ringChunks) do
                    if ringResidentBytes[ringName] <= budget then
                        break
                    end
                    local removedBytes = evictChunkForRingBudget(entry.id, ringName)
                    ringResidentBytes[ringName] = math.max(0, ringResidentBytes[ringName] - removedBytes)
                end
            end
        end

        refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions, deferredProjectedUsage)
        updateStreamingResidencyTelemetry(
            playerPos,
            schedulerFocusPoint,
            movementDeltaStuds,
            movementLookaheadStuds,
            resolvedRings,
            desiredRingStats,
            candidateChunkEntries,
            desiredChunkCount,
            processedWorkItems,
            queuedEstimatedCost,
            queuedWorkItemCount,
            evictedEstimatedCost,
            evictedChunkCount,
            lastPrefetchReason,
            lastEvictionReason,
            if deferredAdmissions > 0 then "guardrail_paused" else "steady_state"
        )
        Workspace:SetAttribute("ArnisStreamingRingNearDeferredAdmissions", ringDeferredAdmissions.near)
        Workspace:SetAttribute("ArnisStreamingRingMidDeferredAdmissions", ringDeferredAdmissions.mid)
        Workspace:SetAttribute("ArnisStreamingRingFarDeferredAdmissions", ringDeferredAdmissions.far)

        local immediateCameraFocusPos = resolveCurrentCameraFocusPosition()
        for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks(streamingOptions.worldRootName)) do
            local chunkEntry = ChunkLoader.GetChunkEntry(chunkId, streamingOptions.worldRootName)
            updateChunkEntryLodGroups(chunkEntry, immediateCameraFocusPos, playerPos, highRadius, interiorRadius)
        end

        streamingLastFocalPoint = playerPos
        streamingLastFocalAt = os.clock()
    end, debug.traceback)
    streamingUpdateInProgress = false
    if not ok then
        error(err, 0)
    end
end

return StreamingService
