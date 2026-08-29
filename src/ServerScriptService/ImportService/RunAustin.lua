local ImportService = require(script.Parent)
local AustinSpawn = require(script.Parent.AustinSpawn)
local CanonicalWorldContract = require(script.Parent.CanonicalWorldContract)
local Profiler = require(script.Parent.Profiler)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local DefaultWorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local StreamingRuntimeConfig = require(ReplicatedStorage.Shared.StreamingRuntimeConfig)

local RunAustin = {}
-- LOAD_RADIUS is the synchronous spawn ring — chunks within this radius
-- are materialized BEFORE the player spawns. Everything outside streams
-- in afterwards via StreamingService.Update on the heartbeat. With
-- chunkSizeStuds=256:
--   radius  320 → 1-4 chunks  (fast but player sees a sparse pocket)
--   radius  768 → 9-18 chunks (reasonable: visible city, ~5s spawn)
--   radius 1024 → 16-28 chunks (denser: ~8s spawn)
--   radius 1500 → 30+ chunks  (dense but 20s+ spawn block)
-- 768 is the sweet spot for "player spawns into a recognizably populated
-- area" without blowing past 10s total bootstrap. Parallel lazy fetch
-- keeps network time flat regardless of radius.
RunAustin.LOAD_RADIUS = 768
RunAustin.FRAME_BUDGET_SECONDS = 1 / 240
RunAustin.STARTUP_CHUNK_COUNT = 1
RunAustin.MANIFEST_WAIT_TIMEOUT_SECONDS = 30
RunAustin.CANONICAL_MANIFEST_INDEX_NAME = CanonicalWorldContract.resolveCanonicalManifestFamily()
RunAustin.ROUTE_CATALOG_ATTR = "VertigoRouteCatalogName"
RunAustin.ROUTE_LANE_ATTR = "VertigoRouteLane"
RunAustin.ROUTE_STEP_INDEX_ATTR = "VertigoRouteStepIndex"

local function reportPhase(options, phase)
    if type(options) ~= "table" then
        return
    end
    local reporter = options.phaseReporter
    if type(reporter) == "function" then
        reporter(phase)
    end
end

local function setPerfAttribute(name, value)
    Workspace:SetAttribute("VertigoAustin" .. name, value)
end

local function emitRunProfile(stats, phaseSummary, manifestSource, focusPoint)
    local chunkRefs = manifestSource.chunkRefs or manifestSource.chunks or {}
    local slowest = phaseSummary.slowest
    local byLabel = phaseSummary.byLabel or {}
    local hottestPhase = byLabel[1]

    setPerfAttribute("ChunkRefs", #chunkRefs)
    setPerfAttribute("ImportedChunks", stats.chunksImported or 0)
    setPerfAttribute("ImportedRoads", stats.roadsImported or 0)
    setPerfAttribute("ImportedBuildings", stats.buildingsImported or 0)
    setPerfAttribute("ImportedProps", stats.propsImported or 0)
    setPerfAttribute("FocusX", math.round(focusPoint.X))
    setPerfAttribute("FocusZ", math.round(focusPoint.Z))
    setPerfAttribute("ProfilerActivities", phaseSummary.totalActivities or 0)
    setPerfAttribute("ProfilerTotalMs", phaseSummary.totalElapsedMs or 0)
    setPerfAttribute("HotPhaseLabel", hottestPhase and hottestPhase.label or "")
    setPerfAttribute("HotPhaseTotalMs", hottestPhase and hottestPhase.totalMs or 0)
    setPerfAttribute("HotPhaseAvgMs", hottestPhase and hottestPhase.avgMs or 0)
    setPerfAttribute("HotPhaseCount", hottestPhase and hottestPhase.count or 0)
    setPerfAttribute("SlowestLabel", slowest and slowest.label or "")
    setPerfAttribute("SlowestMs", slowest and slowest.elapsedMs or 0)

    print(
        string.format(
            "[RunAustin] Perf summary: refs=%d imported=%d total=%.1fms hot=%s %.1fms slowest=%s %.1fms",
            #chunkRefs,
            stats.chunksImported or 0,
            phaseSummary.totalElapsedMs or 0,
            hottestPhase and hottestPhase.label or "n/a",
            hottestPhase and hottestPhase.totalMs or 0,
            slowest and slowest.label or "n/a",
            slowest and slowest.elapsedMs or 0
        )
    )
end

function RunAustin.getManifestName()
    return RunAustin.CANONICAL_MANIFEST_INDEX_NAME
end

function RunAustin.getRuntimeManifestCandidates()
    return CanonicalWorldContract.resolveCanonicalMaterializationCandidates("play")
end

local function resolveRouteSelectionOptions(options)
    local resolved = {}
    options = options or {}

    local routeCatalogName = options.routeCatalogName
    if type(routeCatalogName) ~= "string" or routeCatalogName == "" then
        local workspaceRouteCatalogName = Workspace:GetAttribute(RunAustin.ROUTE_CATALOG_ATTR)
        if type(workspaceRouteCatalogName) == "string" and workspaceRouteCatalogName ~= "" then
            routeCatalogName = workspaceRouteCatalogName
        end
    end
    if type(routeCatalogName) == "string" and routeCatalogName ~= "" then
        resolved.routeCatalogName = routeCatalogName
    end

    local routeLane = options.routeLane
    if type(routeLane) ~= "string" or routeLane == "" then
        local workspaceRouteLane = Workspace:GetAttribute(RunAustin.ROUTE_LANE_ATTR)
        if type(workspaceRouteLane) == "string" and workspaceRouteLane ~= "" then
            routeLane = workspaceRouteLane
        end
    end
    if type(routeLane) == "string" and routeLane ~= "" then
        resolved.routeLane = routeLane
    end

    local routeStepIndex = options.routeStepIndex
    if type(routeStepIndex) ~= "number" then
        local workspaceRouteStepIndex = Workspace:GetAttribute(RunAustin.ROUTE_STEP_INDEX_ATTR)
        if type(workspaceRouteStepIndex) == "number" then
            routeStepIndex = workspaceRouteStepIndex
        end
    end
    if type(routeStepIndex) == "number" then
        resolved.routeStepIndex = math.floor(routeStepIndex)
    end

    return resolved
end

function RunAustin.loadManifestSource(options)
    options = options or {}
    local routeSelectionOptions = resolveRouteSelectionOptions(options)
    setPerfAttribute("RouteCatalogName", routeSelectionOptions.routeCatalogName or "")
    setPerfAttribute("RouteLane", routeSelectionOptions.routeLane or "")
    setPerfAttribute("RouteStepIndex", routeSelectionOptions.routeStepIndex or -1)
    setPerfAttribute(
        "ManifestSourceKind",
        routeSelectionOptions.routeCatalogName and "route_catalog" or "canonical_manifest"
    )
    local materializationFamily = CanonicalWorldContract.resolveCanonicalMaterializationFamily("play")
    print(
        ("[RunAustin] Loading canonical manifest source %s via %s"):format(
            RunAustin.CANONICAL_MANIFEST_INDEX_NAME,
            materializationFamily
        )
    )
    local manifestSource, resolvedManifestName =
        CanonicalWorldContract.loadCanonicalManifestSource("play", RunAustin.MANIFEST_WAIT_TIMEOUT_SECONDS, {
            routeCatalogName = routeSelectionOptions.routeCatalogName,
            routeLane = routeSelectionOptions.routeLane,
            routeStepIndex = routeSelectionOptions.routeStepIndex,
        })
    return manifestSource, resolvedManifestName
end

function RunAustin.run(options)
    options = options or {}
    local runtimeWorldConfig = options.config
    if type(runtimeWorldConfig) ~= "table" then
        local runtimeConfigSource = DefaultWorldConfig
        if not RunService:IsStudio() then
            local configuredProfile = DefaultWorldConfig.StreamingProfile
            if type(configuredProfile) ~= "string" or configuredProfile == "" or configuredProfile == "local_dev" then
                runtimeConfigSource = table.clone(DefaultWorldConfig)
                runtimeConfigSource.StreamingProfile = "production_server"
            end
        end
        runtimeWorldConfig = StreamingRuntimeConfig.Resolve(runtimeConfigSource)
    end
    setPerfAttribute("Status", "loading")
    reportPhase(options, "loading_manifest")
    print(("[RunAustin] Starting run for manifest %s"):format(RunAustin.getManifestName()))
    local success, manifestOrErr, resolvedManifestName = pcall(function()
        return RunAustin.loadManifestSource(options)
    end)

    if not success then
        setPerfAttribute("Status", "load_failed")
        warn(("[RunAustin] Failed to load %s:"):format(RunAustin.getManifestName()), manifestOrErr)
        return nil, tostring(manifestOrErr)
    end

    local manifestSource = manifestOrErr
    setPerfAttribute("ManifestName", resolvedManifestName or RunAustin.getManifestName())
    setPerfAttribute("ManifestSourceName", resolvedManifestName or RunAustin.getManifestName())
    print(("[RunAustin] Manifest source loaded from %s"):format(resolvedManifestName or RunAustin.getManifestName()))
    print("[RunAustin] Manifest source loaded")
    reportPhase(options, "importing_startup")
    local boundedEnvelope = CanonicalWorldContract.resolveBoundedEnvelope(manifestSource, RunAustin.LOAD_RADIUS)
    local loadCenter = boundedEnvelope.focusPoint
    local runtimeAnchor = AustinSpawn.resolveRuntimeAnchor(manifestSource, RunAustin.LOAD_RADIUS, loadCenter)
    local spawnPoint = runtimeAnchor.spawnPoint
    setPerfAttribute("FocusX", math.round(loadCenter.X))
    setPerfAttribute("FocusY", math.round(loadCenter.Y))
    setPerfAttribute("FocusZ", math.round(loadCenter.Z))
    setPerfAttribute("SpawnX", math.round(spawnPoint.X))
    setPerfAttribute("SpawnY", math.round(spawnPoint.Y))
    setPerfAttribute("SpawnZ", math.round(spawnPoint.Z))
    print(
        string.format(
            "[RunAustin] Austin anchor: focus=(%.1f, %.1f, %.1f) spawn=(%.1f, %.1f, %.1f)",
            loadCenter.X,
            loadCenter.Y,
            loadCenter.Z,
            spawnPoint.X,
            spawnPoint.Y,
            spawnPoint.Z
        )
    )
    local initialChunks = boundedEnvelope.selectedChunks
    if type(initialChunks) ~= "table" or #initialChunks == 0 then
        initialChunks = manifestSource:LoadChunksWithinRadius(loadCenter, RunAustin.LOAD_RADIUS)
    end
    local startupChunkRefsById = {}
    for _, chunk in ipairs(initialChunks) do
        local chunkId = chunk and chunk.id
        if type(chunkId) == "string" and chunkId ~= "" then
            startupChunkRefsById[chunkId] = manifestSource:ResolveChunkRef(chunkId)
        end
    end
    local initialManifest = {
        schemaVersion = manifestSource.schemaVersion,
        meta = manifestSource.meta,
        chunks = initialChunks,
    }

    local stats = ImportService.ImportManifest(initialManifest, {
        clearFirst = true,
        worldRootName = "GeneratedWorld_Austin",
        printReport = true,
        config = runtimeWorldConfig,
        loadRadius = RunAustin.LOAD_RADIUS, -- studs around the manifest focus point
        loadCenter = loadCenter,
        nonBlocking = true,
        frameBudgetSeconds = RunAustin.FRAME_BUDGET_SECONDS,
        startupChunkCount = RunAustin.STARTUP_CHUNK_COUNT,
        registrationChunksById = startupChunkRefsById,
    })

    -- Background prefetch hint: as soon as the synchronous spawn ring is in
    -- the world, fire-and-forget a fetch of the next ring (2× spawn radius).
    -- This warms the cache so when StreamingService.Update reaches a chunk
    -- the player is moving toward, it's already decoded and ready to
    -- materialize without an HTTP round trip. The chunk source dedupes
    -- already-cached chunks, so this is safe to call repeatedly.
    --
    -- The cancellation token is a Workspace attribute that the bootstrap
    -- stamps before each run. If a new bootstrap attempt supersedes this
    -- one (teardown + restart), the attempt id advances and the background
    -- prefetch loop exits before firing against a stale manifest handle.
    -- This closes the reference-leak window flagged by the reviewer.
    if type(manifestSource.PrefetchChunks) == "function"
        and type(manifestSource.GetChunkIdsWithinRadius) == "function"
    then
        local prefetchRadius = RunAustin.LOAD_RADIUS * 2
        local outerIds = manifestSource:GetChunkIdsWithinRadius(loadCenter, prefetchRadius)
        local alreadyHave = {}
        for _, chunk in ipairs(initialChunks) do
            if chunk and chunk.id then
                alreadyHave[chunk.id] = true
            end
        end
        local toPrefetch = {}
        for _, id in ipairs(outerIds or {}) do
            if not alreadyHave[id] then
                table.insert(toPrefetch, id)
            end
        end
        local chunkFetchFailuresAtStartup = tonumber(Workspace:GetAttribute("ArnisChunkFetchFailures")) or 0
        if #toPrefetch > 0 and stats.chunksImported > 0 and chunkFetchFailuresAtStartup == 0 then
            local attemptId = Workspace:GetAttribute("ArnisAustinBootstrapAttemptId")
            print(
                ("[RunAustin] Background prefetch hint: %d outer-ring chunks queued (attempt=%s)"):format(
                    #toPrefetch,
                    tostring(attemptId)
                )
            )
            task.spawn(function()
                -- Re-check the attempt id right before firing. If the
                -- bootstrap was torn down and restarted between scheduling
                -- and this coroutine waking up, abort silently. The
                -- attempt-id guard is sufficient on its own — we do NOT
                -- additionally gate on manifestSourceKind because that
                -- would silently skip prefetch for roblox_asset-sourced
                -- manifests which also have a meaningful PrefetchChunks
                -- implementation.
                if Workspace:GetAttribute("ArnisAustinBootstrapAttemptId") ~= attemptId then
                    return
                end
                local ok, err = pcall(function()
                    manifestSource:PrefetchChunks(toPrefetch)
                end)
                if not ok then
                    warn(("[RunAustin] Background prefetch failed: %s"):format(tostring(err)))
                end
            end)
        elseif #toPrefetch > 0 then
            warn(
                ("[RunAustin] Skipping background prefetch hint because startup imported %d chunks with %d fetch failures"):format(
                    stats.chunksImported or 0,
                    chunkFetchFailuresAtStartup
                )
            )
        end
    end
    local worldRoot = Workspace:FindFirstChild("GeneratedWorld_Austin")
    setPerfAttribute("WorldRootName", "GeneratedWorld_Austin")
    if worldRoot then
        setPerfAttribute("WorldRootExists", 1)
        setPerfAttribute("WorldRootChildCount", #worldRoot:GetChildren())
        setPerfAttribute("WorldRootDescendantCount", #worldRoot:GetDescendants())
    else
        setPerfAttribute("WorldRootExists", 0)
        setPerfAttribute("WorldRootChildCount", 0)
        setPerfAttribute("WorldRootDescendantCount", 0)
    end
    local phaseSummary = Profiler.generateSummary()
    emitRunProfile(stats, phaseSummary, manifestSource, loadCenter)
    setPerfAttribute("Status", "ready")

    print(
        ("[RunAustin] Imported Austin manifest: chunks=%d roads=%d buildings=%d props=%d"):format(
            stats.chunksImported,
            stats.roadsImported,
            stats.buildingsImported,
            stats.propsImported
        )
    )

    -- Read manifestSourceKind directly from the resolved manifest handle
    -- (annotated by CanonicalWorldContract.loadCanonicalManifestSource)
    -- rather than from the Workspace attribute that setPerfAttribute stamps
    -- at RunAustin.loadManifestSource entry. The attribute is derived purely
    -- from whether a route catalog name was provided and can only ever be
    -- "route_catalog" or "canonical_manifest" — it never reflects
    -- "external_url" or "roblox_asset" even when those are the real source
    -- kind. The downstream SceneMarkerEmitter + audit pipeline keys off this
    -- field, so the attribute-based read was shipping wrong telemetry.
    local resolvedSourceKind = (type(manifestSource) == "table" and manifestSource.manifestSourceKind)
        or Workspace:GetAttribute("VertigoAustinManifestSourceKind")

    return {
        manifest = initialManifest,
        manifestSource = manifestSource,
        resolvedManifestName = resolvedManifestName,
        manifestSourceKind = resolvedSourceKind,
        stats = stats,
        phaseSummary = phaseSummary,
        focusPoint = loadCenter,
        spawnPoint = spawnPoint,
        lookTarget = boundedEnvelope.lookTarget,
    }
end

return RunAustin
