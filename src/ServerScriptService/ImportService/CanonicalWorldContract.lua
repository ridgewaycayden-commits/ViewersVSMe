local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local AustinSpawn = require(script.Parent.AustinSpawn)
local ManifestLoader = require(script.Parent.ManifestLoader)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local CanonicalWorldContract = {}

CanonicalWorldContract.CANONICAL_MANIFEST_INDEX_NAME = "AustinManifestIndex"
CanonicalWorldContract.LOCAL_DEV_FULL_BAKE_MATERIALIZATION_INDEX_NAMES = {
    "AustinCanonicalManifestIndex",
}
CanonicalWorldContract.LOCAL_DEV_PLAY_MATERIALIZATION_INDEX_NAMES = {
    "AustinCanonicalManifestIndex",
}

-- Planetary streaming: multi-city manifest registry.
-- Each entry maps a world-space region (origin + radius in studs) to a manifest.
-- When the player crosses a region boundary, the streaming system loads the
-- corresponding manifest. Regions can overlap; the nearest center wins.
--
-- Coordinates use true-scale Mercator projection from (0°N, 0°E) at 0.3 m/stud.
-- Distance Austin→Tokyo ≈ 295 million studs (~35,000 km real-world).
-- A jetpack at 120 studs/s would take ~28 days continuous — realistic for true scale.
-- Between cities: procedural ocean/terrain from satellite tiles + DEM elevation.
CanonicalWorldContract.METERS_PER_STUD = 0.3
CanonicalWorldContract.PlanetaryManifestRegistry = {
    {
        worldName = "Austin",
        manifestIndexName = "AustinManifestIndex",
        -- 30.27°N, -97.74°W → Mercator planetary coords at 0.3 m/stud
        originStuds = Vector3.new(-36234000, 0, -11183000),
        radiusStuds = 50000,
    },
    {
        worldName = "Amsterdam",
        manifestIndexName = "AmsterdamManifestIndex",
        -- 52.37°N, 4.90°E
        originStuds = Vector3.new(1816000, 0, -22760000),
        radiusStuds = 50000,
    },
    {
        worldName = "Tokyo",
        manifestIndexName = "TokyoManifestIndex",
        -- 35.68°N, 139.69°E
        originStuds = Vector3.new(51830000, 0, -14020000),
        radiusStuds = 50000,
    },
    {
        worldName = "SanFrancisco",
        manifestIndexName = "SanFranciscoManifestIndex",
        -- 37.79°N, -122.41°W
        originStuds = Vector3.new(-45412000, 0, -14935000),
        radiusStuds = 50000,
    },
}

-- Resolve which manifest to use based on world-space position.
-- Returns the manifest index name and the region entry.
function CanonicalWorldContract.resolveManifestForPosition(worldPosition)
    local bestEntry = nil
    local bestDistSq = math.huge
    for _, entry in ipairs(CanonicalWorldContract.PlanetaryManifestRegistry) do
        local delta = worldPosition - entry.originStuds
        local distSq = delta.X * delta.X + delta.Z * delta.Z
        if distSq < entry.radiusStuds * entry.radiusStuds and distSq < bestDistSq then
            bestEntry = entry
            bestDistSq = distSq
        end
    end
    if bestEntry then
        return bestEntry.manifestIndexName, bestEntry
    end
    -- Fallback to canonical
    return CanonicalWorldContract.CANONICAL_MANIFEST_INDEX_NAME, nil
end

function CanonicalWorldContract.resolveCanonicalManifestFamily(_policyMode)
    return CanonicalWorldContract.CANONICAL_MANIFEST_INDEX_NAME
end

local function getSampleDataFolder()
    return ServerStorage:FindFirstChild("SampleData")
end

function CanonicalWorldContract.resolveCanonicalMaterializationCandidates(policyMode)
    local candidates = {}
    local sampleData = getSampleDataFolder()
    if sampleData then
        local preferredIndexNames = CanonicalWorldContract.LOCAL_DEV_FULL_BAKE_MATERIALIZATION_INDEX_NAMES
        if policyMode == "play" then
            preferredIndexNames = CanonicalWorldContract.LOCAL_DEV_PLAY_MATERIALIZATION_INDEX_NAMES
        end
        for _, manifestIndexName in ipairs(preferredIndexNames) do
            if sampleData:FindFirstChild(manifestIndexName) ~= nil then
                candidates[#candidates + 1] = manifestIndexName
            end
        end
    end

    local canonicalFamily = CanonicalWorldContract.resolveCanonicalManifestFamily(policyMode)
    candidates[#candidates + 1] = canonicalFamily
    return candidates
end

function CanonicalWorldContract.resolveCanonicalMaterializationFamily(policyMode)
    return CanonicalWorldContract.resolveCanonicalMaterializationCandidates(policyMode)[1]
end

local function annotateManifestSource(manifestSource, metadata)
    if type(manifestSource) ~= "table" or type(metadata) ~= "table" then
        return manifestSource
    end
    for key, value in pairs(metadata) do
        manifestSource[key] = value
    end
    return manifestSource
end

function CanonicalWorldContract.loadCanonicalManifestSource(policyMode, timeoutSeconds, options)
    local canonicalFamily = CanonicalWorldContract.resolveCanonicalManifestFamily(policyMode)
    if type(options) == "table" and type(options.routeCatalogName) == "string" then
        local routeLane = options.routeLane or "active"
        local routeStepIndex = options.routeStepIndex or 0
        local routeCatalogHandle =
            ManifestLoader.LoadNamedRouteCatalogHandle(options.routeCatalogName, timeoutSeconds, options)
        local manifestSource =
            routeCatalogHandle:LoadLaneRuntimeHandle(routeStepIndex, routeLane, timeoutSeconds, options)
        if type(manifestSource) == "table" and type(routeCatalogHandle.LoadLaneSummary) == "function" then
            function manifestSource:LoadLaneSummary(stepIndex, laneName)
                return routeCatalogHandle:LoadLaneSummary(stepIndex, laneName)
            end
        end
        annotateManifestSource(manifestSource, {
            manifestSourceKind = "route_catalog",
            manifestSourceName = options.routeCatalogName,
            manifestFamily = canonicalFamily,
            routeCatalogName = options.routeCatalogName,
            routeLane = routeLane,
            routeStepIndex = routeStepIndex,
        })
        return manifestSource, options.routeCatalogName, canonicalFamily
    end

    -- ManifestSource config: when not in "embedded" mode, attempt the external
    -- transport first and fall back to the embedded SampleData candidates below.
    local manifestSourceConfig = WorldConfig.ManifestSource
    if type(manifestSourceConfig) == "table" and manifestSourceConfig.mode and manifestSourceConfig.mode ~= "embedded" then
        local externalOk, externalHandle = pcall(function()
            if manifestSourceConfig.mode == "external_url" then
                return ManifestLoader.loadFromExternalSource(manifestSourceConfig.externalUrl, options)
            elseif manifestSourceConfig.mode == "roblox_asset" then
                return ManifestLoader.loadFromRobloxAsset(manifestSourceConfig.robloxAssetId, options)
            end
            return nil
        end)
        if externalOk and externalHandle ~= nil then
            annotateManifestSource(externalHandle, {
                manifestSourceKind = externalHandle.manifestSourceKind or manifestSourceConfig.mode,
                manifestSourceName = externalHandle.manifestSourceName
                    or (manifestSourceConfig.mode == "external_url" and manifestSourceConfig.externalUrl)
                    or (manifestSourceConfig.mode == "roblox_asset" and tostring(manifestSourceConfig.robloxAssetId))
                    or manifestSourceConfig.mode,
                manifestFamily = canonicalFamily,
            })
            return externalHandle, externalHandle.manifestSourceName or manifestSourceConfig.mode, canonicalFamily
        end
        -- When the operator explicitly chose a non-embedded source we MUST
        -- surface the real failure in live (production) Roblox so the user
        -- can see what actually broke. In Studio/harness/test we keep the
        -- silent fallback so dev workflows can run against embedded
        -- SampleData even when no HTTP egress is available. The opt-in
        -- `fallbackToEmbedded` flag forces fallback in all environments.
        local externalErr = tostring(externalHandle)
        local RunService = game:GetService("RunService")
        local isStudio = false
        do
            local ok, value = pcall(function()
                return RunService:IsStudio()
            end)
            if ok then
                isStudio = value == true
            end
        end
        local allowFallback = manifestSourceConfig.fallbackToEmbedded == true or isStudio
        if not allowFallback then
            error(
                ("[CanonicalWorldContract] ManifestSource mode=%s failed: %s"):format(
                    tostring(manifestSourceConfig.mode),
                    externalErr
                )
            )
        end
        warn(
            ("[CanonicalWorldContract] ManifestSource mode=%s failed (%s); falling back to embedded SampleData"):format(
                tostring(manifestSourceConfig.mode),
                externalErr
            )
        )
    end

    local candidates = CanonicalWorldContract.resolveCanonicalMaterializationCandidates(policyMode)
    local lastError = nil
    for _, manifestIndexName in ipairs(candidates) do
        local ok, handle =
            pcall(ManifestLoader.LoadNamedShardedSampleHandle, manifestIndexName, timeoutSeconds, options)
        if ok then
            annotateManifestSource(handle, {
                manifestSourceKind = "canonical_manifest",
                manifestSourceName = manifestIndexName,
                manifestFamily = canonicalFamily,
            })
            return handle, manifestIndexName, canonicalFamily
        end
        lastError = handle
    end

    if lastError ~= nil then
        error(lastError)
    end

    error("Canonical world contract did not resolve any manifest materialization candidates")
end

function CanonicalWorldContract.resolveCanonicalAnchor(manifestSource, loadRadius, loadCenter)
    return AustinSpawn.resolveCanonicalAnchorValues(manifestSource, loadRadius, loadCenter)
end

function CanonicalWorldContract.resolveBoundedEnvelope(manifestSource, loadRadius, loadCenter)
    local anchor = CanonicalWorldContract.resolveCanonicalAnchor(manifestSource, loadRadius, loadCenter)
    local selectedChunks = anchor.selectedChunks or {}
    local chunkIds = table.create(#selectedChunks)
    for index, chunk in ipairs(selectedChunks) do
        chunkIds[index] = chunk.id
    end

    return {
        manifestFamily = CanonicalWorldContract.resolveCanonicalManifestFamily(),
        manifestSourceKind = manifestSource.manifestSourceKind or "canonical_manifest",
        manifestSourceName = manifestSource.manifestSourceName,
        routeCatalogName = manifestSource.routeCatalogName,
        routeLane = manifestSource.routeLane,
        routeStepIndex = manifestSource.routeStepIndex,
        anchor = anchor,
        focusPoint = anchor.focusPoint,
        spawnPoint = anchor.spawnPoint,
        lookTarget = anchor.lookTarget,
        selectedChunks = selectedChunks,
        chunkIds = chunkIds,
    }
end

return CanonicalWorldContract
