--[[
  TelemetryReporter.lua
  Captures bootstrap phase timings and chunk-fetch telemetry, then POSTs a
  consolidated payload to the Cloudflare planetary worker so the run can be
  inspected server-side without being in-game.

  Contract: the payload schema produced by Report() is consumed by the
  Cloudflare worker (`/telemetry/run`) and by the Python audit script. Do not
  reorder or rename fields without coordinating both consumers.

  Operational guarantees:
  * Report() never throws to the caller — pcall-wrapped, fire-and-forget.
  * No new require cycles: this module does NOT require BootstrapAustin.
  * Works even if HttpService is disabled — the RequestAsync call is pcall'd
    and only emits a warning on failure.
--]]

local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local TelemetryReporter = {}

local DEFAULT_ENDPOINT = "https://planetary.adpena.workers.dev"
local USER_AGENT = "arnis-planetary-runtime/0.5"

local configuredEndpoint = DEFAULT_ENDPOINT
local phaseTimestamps = {}
local phaseOrder = {}

-- ---------------------------------------------------------------------------
-- Flicker aggregate state
-- ---------------------------------------------------------------------------
-- Clients (via WorldProbe.client.lua) fire samples through an
-- UnreliableRemoteEvent; BootstrapAustin routes each sample through
-- RecordFlickerSample and the aggregates below are included in the next
-- Report() payload.
local PRESSURE_LEVEL_ORDER = {
    ok = 0,
    elevated = 1,
    high = 2,
    critical = 3,
}
local PRESSURE_LEVEL_LABELS = { [0] = "ok", [1] = "elevated", [2] = "high", [3] = "critical" }

local function freshAggregate()
    return {
        sampleCount = 0,
        stationarySampleCount = 0,
        movingSampleCount = 0,
        chunkThrashCountTotal = 0,
        chunkThrashCountPeak = 0,
        stationaryThrashTotal = 0,
        movingThrashTotal = 0,
        hrpMovementStudsTotal = 0,
        hrpMovementPeakStuds = 0,
        nearPartReversalsTotal = 0,
        nearPartUpStepsTotal = 0,
        nearPartDownStepsTotal = 0,
        stationaryReversalsTotal = 0,
        nearPartCountStdDevSum = 0,
        nearPartCountStdDevPeak = 0,
        stationaryStdDevSum = 0,
        stationaryStdDevPeak = 0,
        ringBouncesNearTotal = 0,
        ringBouncesMidTotal = 0,
        ringBouncesFarTotal = 0,
        ringDeltaNearPeak = 0,
        ringDeltaMidPeak = 0,
        ringDeltaFarPeak = 0,
        chunkFetchFailuresDeltaTotal = 0,
        peakMemoryPressureLevel = 0,
        thrashyChunkIdsSeen = {},
        stationaryThrashyChunkIdsSeen = {},
        lastSampleTimestamp = 0,
    }
end

local flickerAggregate = freshAggregate()

function TelemetryReporter.ResetFlickerAggregate()
    flickerAggregate = freshAggregate()
end

function TelemetryReporter.RecordFlickerSample(sample)
    if type(sample) ~= "table" then
        return
    end
    flickerAggregate.sampleCount = flickerAggregate.sampleCount + 1
    flickerAggregate.lastSampleTimestamp = os.time()

    local isStationary = sample.isStationary == true
    if isStationary then
        flickerAggregate.stationarySampleCount = flickerAggregate.stationarySampleCount + 1
    else
        flickerAggregate.movingSampleCount = flickerAggregate.movingSampleCount + 1
    end

    local movement = tonumber(sample.hrpMovementStuds) or 0
    flickerAggregate.hrpMovementStudsTotal = flickerAggregate.hrpMovementStudsTotal + movement
    local movementPeak = tonumber(sample.hrpMovementPeakStuds) or 0
    if movementPeak > flickerAggregate.hrpMovementPeakStuds then
        flickerAggregate.hrpMovementPeakStuds = movementPeak
    end

    -- Near-part-count direction-change metrics. `reversals` is the signal
    -- we actually care about — it's the number of times the part count
    -- switched direction within the sample's rolling ring. upSteps and
    -- downSteps let us compute an up-vs-down ratio to distinguish import
    -- progress (lots of up, few down, few reversals) from flicker
    -- (up ≈ down, many reversals).
    local reversals = tonumber(sample.nearPartReversals) or 0
    local upSteps = tonumber(sample.nearPartUpSteps) or 0
    local downSteps = tonumber(sample.nearPartDownSteps) or 0
    flickerAggregate.nearPartReversalsTotal = flickerAggregate.nearPartReversalsTotal + reversals
    flickerAggregate.nearPartUpStepsTotal = flickerAggregate.nearPartUpStepsTotal + upSteps
    flickerAggregate.nearPartDownStepsTotal = flickerAggregate.nearPartDownStepsTotal + downSteps
    if isStationary then
        flickerAggregate.stationaryReversalsTotal = flickerAggregate.stationaryReversalsTotal + reversals
    end

    local thrash = tonumber(sample.chunkThrashCount) or 0
    flickerAggregate.chunkThrashCountTotal = flickerAggregate.chunkThrashCountTotal + thrash
    if thrash > flickerAggregate.chunkThrashCountPeak then
        flickerAggregate.chunkThrashCountPeak = thrash
    end
    if isStationary then
        flickerAggregate.stationaryThrashTotal = flickerAggregate.stationaryThrashTotal + thrash
    else
        flickerAggregate.movingThrashTotal = flickerAggregate.movingThrashTotal + thrash
    end

    local stdDev = tonumber(sample.nearPartCountStdDev) or 0
    flickerAggregate.nearPartCountStdDevSum = flickerAggregate.nearPartCountStdDevSum + stdDev
    if stdDev > flickerAggregate.nearPartCountStdDevPeak then
        flickerAggregate.nearPartCountStdDevPeak = stdDev
    end
    if isStationary then
        flickerAggregate.stationaryStdDevSum = flickerAggregate.stationaryStdDevSum + stdDev
        if stdDev > flickerAggregate.stationaryStdDevPeak then
            flickerAggregate.stationaryStdDevPeak = stdDev
        end
    end

    flickerAggregate.ringBouncesNearTotal = flickerAggregate.ringBouncesNearTotal
        + (tonumber(sample.ringBouncesNear) or 0)
    flickerAggregate.ringBouncesMidTotal = flickerAggregate.ringBouncesMidTotal
        + (tonumber(sample.ringBouncesMid) or 0)
    flickerAggregate.ringBouncesFarTotal = flickerAggregate.ringBouncesFarTotal
        + (tonumber(sample.ringBouncesFar) or 0)

    local deltaNear = tonumber(sample.ringDeltaNear) or 0
    if deltaNear > flickerAggregate.ringDeltaNearPeak then
        flickerAggregate.ringDeltaNearPeak = deltaNear
    end
    local deltaMid = tonumber(sample.ringDeltaMid) or 0
    if deltaMid > flickerAggregate.ringDeltaMidPeak then
        flickerAggregate.ringDeltaMidPeak = deltaMid
    end
    local deltaFar = tonumber(sample.ringDeltaFar) or 0
    if deltaFar > flickerAggregate.ringDeltaFarPeak then
        flickerAggregate.ringDeltaFarPeak = deltaFar
    end

    flickerAggregate.chunkFetchFailuresDeltaTotal = flickerAggregate.chunkFetchFailuresDeltaTotal
        + (tonumber(sample.chunkFetchFailuresDelta) or 0)

    local pressure = sample.memoryPressure
    local pressureLevel = PRESSURE_LEVEL_ORDER[tostring(pressure)] or 0
    if pressureLevel > flickerAggregate.peakMemoryPressureLevel then
        flickerAggregate.peakMemoryPressureLevel = pressureLevel
    end

    if type(sample.thrashyChunkIds) == "table" then
        for _, id in ipairs(sample.thrashyChunkIds) do
            if type(id) == "string" and id ~= "" then
                flickerAggregate.thrashyChunkIdsSeen[id] =
                    (flickerAggregate.thrashyChunkIdsSeen[id] or 0) + 1
                if isStationary then
                    flickerAggregate.stationaryThrashyChunkIdsSeen[id] =
                        (flickerAggregate.stationaryThrashyChunkIdsSeen[id] or 0) + 1
                end
            end
        end
    end
end

local function buildFlickerBlock()
    if flickerAggregate.sampleCount <= 0 then
        return nil
    end
    local avgStdDev = flickerAggregate.nearPartCountStdDevSum / flickerAggregate.sampleCount
    local stationaryAvgStdDev = 0
    if flickerAggregate.stationarySampleCount > 0 then
        stationaryAvgStdDev = flickerAggregate.stationaryStdDevSum / flickerAggregate.stationarySampleCount
    end
    local function topKIds(map, k)
        local list = {}
        for id, count in pairs(map) do
            list[#list + 1] = { id = id, count = count }
        end
        table.sort(list, function(a, b)
            return a.count > b.count
        end)
        local ids = {}
        for i = 1, math.min(k, #list) do
            ids[i] = list[i].id
        end
        return ids
    end
    return {
        sampleCount = flickerAggregate.sampleCount,
        stationarySampleCount = flickerAggregate.stationarySampleCount,
        movingSampleCount = flickerAggregate.movingSampleCount,
        hrpMovementStudsTotal = math.round(flickerAggregate.hrpMovementStudsTotal * 10) / 10,
        hrpMovementPeakStuds = flickerAggregate.hrpMovementPeakStuds,
        nearPartReversals = flickerAggregate.nearPartReversalsTotal,
        nearPartUpSteps = flickerAggregate.nearPartUpStepsTotal,
        nearPartDownSteps = flickerAggregate.nearPartDownStepsTotal,
        stationaryReversals = flickerAggregate.stationaryReversalsTotal,
        chunkThrashCount = flickerAggregate.chunkThrashCountTotal,
        chunkThrashCountPeak = flickerAggregate.chunkThrashCountPeak,
        stationaryThrashCount = flickerAggregate.stationaryThrashTotal,
        movingThrashCount = flickerAggregate.movingThrashTotal,
        nearPartCountStdDevAvg = math.round(avgStdDev * 10) / 10,
        nearPartCountStdDevPeak = flickerAggregate.nearPartCountStdDevPeak,
        stationaryStdDevAvg = math.round(stationaryAvgStdDev * 10) / 10,
        stationaryStdDevPeak = flickerAggregate.stationaryStdDevPeak,
        ringBouncesNear = flickerAggregate.ringBouncesNearTotal,
        ringBouncesMid = flickerAggregate.ringBouncesMidTotal,
        ringBouncesFar = flickerAggregate.ringBouncesFarTotal,
        ringDeltaNearPeak = flickerAggregate.ringDeltaNearPeak,
        ringDeltaMidPeak = flickerAggregate.ringDeltaMidPeak,
        ringDeltaFarPeak = flickerAggregate.ringDeltaFarPeak,
        chunkFetchFailuresDelta = flickerAggregate.chunkFetchFailuresDeltaTotal,
        peakMemoryPressure = PRESSURE_LEVEL_LABELS[flickerAggregate.peakMemoryPressureLevel] or "ok",
        topThrashyChunkIds = topKIds(flickerAggregate.thrashyChunkIdsSeen, 5),
        topStationaryThrashyChunkIds = topKIds(flickerAggregate.stationaryThrashyChunkIdsSeen, 5),
        lastSampleTimestamp = flickerAggregate.lastSampleTimestamp,
    }
end

function TelemetryReporter.Configure(endpointUrl)
    if type(endpointUrl) == "string" and endpointUrl ~= "" then
        configuredEndpoint = endpointUrl
    end
end

function TelemetryReporter.RecordPhase(phaseName)
    if type(phaseName) ~= "string" or phaseName == "" then
        return
    end
    if phaseTimestamps[phaseName] == nil then
        table.insert(phaseOrder, phaseName)
    end
    phaseTimestamps[phaseName] = os.clock()
end

local function resolveSourceUrl()
    local manifestSourceConfig = WorldConfig.ManifestSource or {}
    if manifestSourceConfig.mode == "external_url" then
        return tostring(manifestSourceConfig.externalUrl or "")
    elseif manifestSourceConfig.mode == "roblox_asset" then
        return ("roblox_asset://%s"):format(tostring(manifestSourceConfig.robloxAssetId or 0))
    end
    return tostring(manifestSourceConfig.mode or "embedded")
end

local function buildPhaseDeltas()
    local deltas = {}
    if #phaseOrder == 0 then
        return deltas, 0
    end
    local firstPhase = phaseOrder[1]
    local firstTs = phaseTimestamps[firstPhase] or 0
    local lastTs = firstTs
    for _, name in ipairs(phaseOrder) do
        local ts = phaseTimestamps[name] or firstTs
        deltas[name] = ts - firstTs
        if ts > lastTs then
            lastTs = ts
        end
    end
    return deltas, lastTs - firstTs
end

local function buildPayload(payloadOverrides)
    payloadOverrides = payloadOverrides or {}

    local phases, totalElapsed = buildPhaseDeltas()

    local runId
    local okGuid, guidOrErr = pcall(function()
        return HttpService:GenerateGUID(false)
    end)
    if okGuid then
        runId = guidOrErr
    else
        runId = string.format("local-%d-%04x", math.floor(os.clock() * 1000), math.random(0, 0xFFFF))
    end

    local payload = {
        runId = runId,
        timestamp = os.time(),
        place = {
            placeId = game.PlaceId,
            universeId = game.GameId,
            serverJobId = game.JobId,
        },
        bootstrap = {
            status = payloadOverrides.status or "success",
            totalElapsedSeconds = totalElapsed,
            errorMessage = payloadOverrides.errorMessage,
            errorDetail = payloadOverrides.errorDetail,
            phases = phases,
        },
        chunkFetch = {
            sourceUrl = Workspace:GetAttribute("ArnisChunkFetchSourceUrl") or "",
            fetchCount = Workspace:GetAttribute("ArnisChunkFetchCount") or 0,
            failureCount = Workspace:GetAttribute("ArnisChunkFetchFailures") or 0,
            totalBytes = Workspace:GetAttribute("ArnisChunkFetchBytes") or 0,
            avgLatencyMs = Workspace:GetAttribute("ArnisChunkFetchAvgLatencyMs") or 0,
            slowestLatencyMs = Workspace:GetAttribute("ArnisChunkFetchSlowestLatencyMs") or 0,
            slowestChunkId = Workspace:GetAttribute("ArnisChunkFetchSlowestChunkId") or "",
        },
        import = {
            chunksImported = payloadOverrides.chunksImported or 0,
            totalInstances = payloadOverrides.totalInstances or 0,
            totalFeatures = payloadOverrides.totalFeatures or 0,
        },
        environment = {
            placeVersion = game.PlaceVersion,
            sourceUrl = resolveSourceUrl(),
        },
    }

    local flickerBlock = buildFlickerBlock()
    if flickerBlock ~= nil then
        payload.flicker = flickerBlock
    end

    return payload
end

local function postPayload(payload)
    local okEncode, body = pcall(function()
        return HttpService:JSONEncode(payload)
    end)
    if not okEncode then
        warn(("[TelemetryReporter] JSONEncode failed: %s"):format(tostring(body)))
        return
    end

    local url = ("%s/telemetry/run"):format(configuredEndpoint)
    local request = {
        Url = url,
        Method = "POST",
        -- Restricted headers (User-Agent, Accept-Encoding, Host, Origin, etc.)
        -- are blocked by HttpService:RequestAsync with the error "Header X is
        -- not allowed!". Only set Content-Type here; the engine supplies its
        -- own User-Agent. The USER_AGENT constant is still exposed for tests
        -- and documentation but is NOT sent on the wire.
        Headers = {
            ["Content-Type"] = "application/json",
        },
        Body = body,
    }

    local okRequest, response = pcall(function()
        return HttpService:RequestAsync(request)
    end)
    if not okRequest then
        warn(("[TelemetryReporter] RequestAsync failed: %s"):format(tostring(response)))
        return
    end
    if type(response) == "table" and response.Success ~= true then
        warn(
            ("[TelemetryReporter] POST %s returned status=%s %s"):format(
                url,
                tostring(response.StatusCode),
                tostring(response.StatusMessage)
            )
        )
    end
end

function TelemetryReporter.Report(payloadOverrides)
    -- Fire-and-forget: never block or throw to the bootstrap caller. We
    -- pcall everything inside the spawned task as well so a failure to even
    -- assemble the payload (e.g. attribute read race) cannot crash the
    -- background task chain.
    task.spawn(function()
        local okBuild, payloadOrErr = pcall(buildPayload, payloadOverrides)
        if not okBuild then
            warn(("[TelemetryReporter] buildPayload failed: %s"):format(tostring(payloadOrErr)))
            return
        end
        local okPost, postErr = pcall(postPayload, payloadOrErr)
        if not okPost then
            warn(("[TelemetryReporter] postPayload failed: %s"):format(tostring(postErr)))
        end
    end)
end

return TelemetryReporter
