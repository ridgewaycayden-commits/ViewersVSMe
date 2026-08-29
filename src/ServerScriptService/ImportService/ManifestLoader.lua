local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ChunkSchema = require(ReplicatedStorage.Shared.ChunkSchema)
local Logger = require(ReplicatedStorage.Shared.Logger)

local ManifestLoader = {}
local SAMPLE_DATA_TIMEOUT_SECONDS = 5
local normalizeChunkRefs
local buildChunkRefsFromShards

local function cloneArray(values)
    if type(values) ~= "table" then
        return values
    end

    local copy = {}
    for index, value in ipairs(values) do
        if type(value) == "table" then
            copy[index] = table.clone(value)
        else
            copy[index] = value
        end
    end
    return copy
end

local function cloneChunkRef(chunkRef)
    local cloned = {
        id = chunkRef.id,
        originStuds = chunkRef.originStuds and table.clone(chunkRef.originStuds) or nil,
    }

    if type(chunkRef.shards) == "table" then
        cloned.shards = cloneArray(chunkRef.shards)
    end

    if chunkRef.featureCount ~= nil then
        cloned.featureCount = chunkRef.featureCount
    end

    if chunkRef.streamingCost ~= nil then
        cloned.streamingCost = chunkRef.streamingCost
    end
    if chunkRef.estimatedMemoryCost ~= nil then
        cloned.estimatedMemoryCost = chunkRef.estimatedMemoryCost
    end

    if chunkRef.partitionVersion ~= nil then
        cloned.partitionVersion = chunkRef.partitionVersion
    end

    if type(chunkRef.subplans) == "table" then
        cloned.subplans = cloneArray(chunkRef.subplans)
    end

    return cloned
end

local function cloneChunkRefs(chunkRefs)
    local sourceChunkRefs = chunkRefs or {}
    local clonedChunkRefs = table.create(#sourceChunkRefs)
    for index, chunkRef in ipairs(sourceChunkRefs) do
        clonedChunkRefs[index] = cloneChunkRef(chunkRef)
    end
    return clonedChunkRefs
end

local function buildChunkRefSeedMap(chunkRefs)
    local chunkRefsById = {}
    for _, chunkRef in ipairs(chunkRefs or {}) do
        chunkRefsById[chunkRef.id] = chunkRef
    end
    return chunkRefsById
end

local function hasChunkRefs(chunkRefs)
    return type(chunkRefs) == "table" and #chunkRefs > 0
end

local function requireModule(module, freshRequire)
    if not freshRequire then
        return require(module)
    end

    if not module:IsA("ModuleScript") then
        return require(module)
    end

    local clone = module:Clone()
    clone.Name = module.Name .. "_Fresh"
    clone.Parent = module.Parent

    local ok, result = pcall(require, clone)
    clone:Destroy()
    if not ok then
        error(result)
    end
    return result
end

local function requireTableModule(module, freshRequire, label)
    local value = requireModule(module, freshRequire)
    if type(value) ~= "table" then
        error(("%s must return a table"):format(label))
    end
    return value
end

local function resolveRelativeInstance(root, relativePath, timeoutSeconds)
    if typeof(root) ~= "Instance" then
        error("Relative module resolution root must be an Instance")
    end
    if type(relativePath) ~= "string" or relativePath == "" then
        error("Relative module path is required")
    end

    local current = root
    for segment in string.gmatch(relativePath, "[^/]+") do
        local child = current:FindFirstChild(segment)
            or current:WaitForChild(segment, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
        if child == nil then
            error(("%s.%s was not provisioned into the live DataModel"):format(current:GetFullName(), segment))
        end
        current = child
    end
    return current
end

local function resolveRelativeModule(root, relativePath, timeoutSeconds)
    local module = resolveRelativeInstance(root, relativePath, timeoutSeconds)
    if not module:IsA("ModuleScript") then
        error(("%s must resolve to a ModuleScript"):format(relativePath))
    end
    return module
end

local function loadShardedHandleFromIndexModule(indexModule, timeoutSeconds, options)
    local freshRequire = type(options) == "table" and options.freshRequire == true
    local index = requireTableModule(indexModule, freshRequire, "Sharded manifest index")
    local shardFolderName = index.shardFolder or (indexModule.Name .. "Chunks")
    local parent = indexModule.Parent
    local shardFolder = parent and parent:FindFirstChild(shardFolderName)
        or (parent and parent:WaitForChild(shardFolderName, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS))
    if shardFolder == nil then
        error(("%s.%s was not provisioned into the live DataModel"):format(parent:GetFullName(), shardFolderName))
    end
    return ManifestLoader.LoadShardedModuleHandle(indexModule, shardFolder, timeoutSeconds, options)
end

local function buildLanePayloadKey(stepIndex, laneName)
    return ("%s:%s"):format(tostring(stepIndex), tostring(laneName))
end

local function newManifest(index, chunkRefs)
    local manifest = {
        schemaVersion = index.schemaVersion,
        meta = index.meta,
        chunks = {},
    }

    if type(chunkRefs) == "table" and #chunkRefs > 0 then
        manifest.chunkRefs = cloneChunkRefs(chunkRefs)
    end

    return manifest
end

local function mergeTableValue(target, value)
    local isArray = #value > 0
    if isArray then
        for _, item in ipairs(value) do
            table.insert(target, item)
        end
        return
    end

    for nestedKey, nestedValue in pairs(value) do
        if type(nestedValue) == "table" then
            local nestedTarget = target[nestedKey]
            if type(nestedTarget) ~= "table" then
                nestedTarget = {}
                target[nestedKey] = nestedTarget
            end
            mergeTableValue(nestedTarget, nestedValue)
        elseif target[nestedKey] == nil then
            target[nestedKey] = nestedValue
        end
    end
end

local function mergeChunkFragment(chunksById, chunkOrder, chunk)
    local existing = chunksById[chunk.id]
    if not existing then
        existing = {}
        chunksById[chunk.id] = existing
        table.insert(chunkOrder, chunk.id)
    end

    for key, value in pairs(chunk) do
        if type(value) == "table" then
            local target = existing[key]
            if target == nil then
                target = {}
                existing[key] = target
            end

            mergeTableValue(target, value)
        elseif existing[key] == nil then
            existing[key] = value
        end
    end
end

local function finalizeManifest(index, chunksById, chunkOrder, chunkRefs)
    local manifest = newManifest(index, chunkRefs)
    for _, chunkId in ipairs(chunkOrder) do
        table.insert(manifest.chunks, chunksById[chunkId])
    end

    return ChunkSchema.validateManifest(manifest)
end

local function resolveSampleDataFolder(timeoutSeconds)
    print("[ManifestLoader] Resolving ServerStorage.SampleData")
    local sampleData = ServerStorage:FindFirstChild("SampleData")
    if sampleData then
        print("[ManifestLoader] Resolved ServerStorage.SampleData via FindFirstChild")
        return sampleData
    end

    sampleData = ServerStorage:WaitForChild("SampleData", timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
    if sampleData then
        print("[ManifestLoader] Resolved ServerStorage.SampleData via WaitForChild")
        return sampleData
    end

    error("ServerStorage.SampleData was not provisioned into the live DataModel")
end

local function resolveSampleModule(name, timeoutSeconds)
    local sampleData = resolveSampleDataFolder(timeoutSeconds)
    print(("[ManifestLoader] Resolving sample module %s"):format(name))
    local module = sampleData:FindFirstChild(name)
    if module then
        print(("[ManifestLoader] Resolved sample module %s via FindFirstChild"):format(name))
        return module
    end

    module = sampleData:WaitForChild(name, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
    if module then
        print(("[ManifestLoader] Resolved sample module %s via WaitForChild"):format(name))
        return module
    end

    error(("ServerStorage.SampleData.%s was not provisioned into the live DataModel"):format(name))
end

local function resolveSampleModulePath(path, timeoutSeconds)
    local sampleData = resolveSampleDataFolder(timeoutSeconds)
    if type(path) ~= "string" or path == "" then
        error("Sample module path is required")
    end

    local current = sampleData
    for segment in string.gmatch(path, "[^./]+") do
        current = current:FindFirstChild(segment)
            or current:WaitForChild(segment, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
        if current == nil then
            error(("ServerStorage.SampleData.%s was not provisioned into the live DataModel"):format(path))
        end
    end

    if not current:IsA("ModuleScript") then
        error(("ServerStorage.SampleData.%s must resolve to a ModuleScript"):format(path))
    end

    return current
end

local function loadShardedManifest(indexModule, timeoutSeconds)
    local index = require(indexModule)
    if type(index) ~= "table" then
        error("Sharded manifest index must return a table")
    end

    local sampleData = resolveSampleDataFolder(timeoutSeconds)
    local shardFolderName = index.shardFolder or (indexModule.Name .. "Chunks")
    local shardFolder = sampleData:FindFirstChild(shardFolderName)
        or sampleData:WaitForChild(shardFolderName, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
    if not shardFolder then
        error(("ServerStorage.SampleData.%s was not provisioned into the live DataModel"):format(shardFolderName))
    end

    local chunkRefs =
        buildChunkRefsFromShards(index, shardFolder, timeoutSeconds, buildChunkRefSeedMap(index.chunkRefs))
    local chunksById = {}
    local chunkOrder = {}

    for _, shardName in ipairs(index.shards or {}) do
        local shardModule = shardFolder:FindFirstChild(shardName)
            or shardFolder:WaitForChild(shardName, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
        if not shardModule then
            error(
                ("ServerStorage.SampleData.%s.%s was not provisioned into the live DataModel"):format(
                    shardFolderName,
                    shardName
                )
            )
        end

        local shardData = require(shardModule)
        for _, chunk in ipairs(shardData.chunks or {}) do
            mergeChunkFragment(chunksById, chunkOrder, chunk)
        end
    end

    return finalizeManifest(index, chunksById, chunkOrder, chunkRefs)
end

function buildChunkRefsFromShards(index, shardFolder, timeoutSeconds, seedChunkRefsById, shardDataLoader)
    local chunkRefsById = {}
    local chunkOrder = {}

    for _, shardName in ipairs(index.shards or {}) do
        local shardData
        if type(shardDataLoader) == "function" then
            shardData = shardDataLoader(shardName)
        else
            local shardModule = shardFolder:FindFirstChild(shardName)
                or shardFolder:WaitForChild(shardName, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
            if not shardModule then
                error(
                    ("%s.%s was not provisioned into the live DataModel"):format(shardFolder:GetFullName(), shardName)
                )
            end

            shardData = require(shardModule)
        end
        for _, chunk in ipairs(shardData.chunks or {}) do
            local chunkRef = chunkRefsById[chunk.id]
            if not chunkRef then
                local seedChunkRef = seedChunkRefsById and seedChunkRefsById[chunk.id]
                chunkRef = {
                    id = chunk.id,
                    originStuds = chunk.originStuds or (seedChunkRef and seedChunkRef.originStuds and table.clone(
                        seedChunkRef.originStuds
                    )) or { x = 0, y = 0, z = 0 },
                    shards = {},
                }
                if seedChunkRef then
                    if seedChunkRef.featureCount ~= nil then
                        chunkRef.featureCount = seedChunkRef.featureCount
                    end
                    if seedChunkRef.streamingCost ~= nil then
                        chunkRef.streamingCost = seedChunkRef.streamingCost
                    end
                    if seedChunkRef.estimatedMemoryCost ~= nil then
                        chunkRef.estimatedMemoryCost = seedChunkRef.estimatedMemoryCost
                    end
                    if seedChunkRef.partitionVersion ~= nil then
                        chunkRef.partitionVersion = seedChunkRef.partitionVersion
                    end
                    if type(seedChunkRef.subplans) == "table" then
                        chunkRef.subplans = cloneArray(seedChunkRef.subplans)
                    end
                end
                chunkRefsById[chunk.id] = chunkRef
                table.insert(chunkOrder, chunk.id)
            end
            table.insert(chunkRef.shards, shardName)
        end
    end

    local chunkRefs = table.create(#chunkOrder)
    for arrayIndex, chunkId in ipairs(chunkOrder) do
        chunkRefs[arrayIndex] = chunkRefsById[chunkId]
    end
    return chunkRefs
end

function normalizeChunkRefs(index, shardFolder, timeoutSeconds)
    if hasChunkRefs(index.chunkRefs) then
        return cloneChunkRefs(index.chunkRefs)
    end

    return buildChunkRefsFromShards(index, shardFolder, timeoutSeconds, buildChunkRefSeedMap(index.chunkRefs))
end

function ManifestLoader.LoadShardedModuleHandle(indexModule, shardFolder, timeoutSeconds, options)
    local freshRequire = type(options) == "table" and options.freshRequire == true
    print(("[ManifestLoader] Requiring sharded index %s"):format(indexModule:GetFullName()))
    local index = requireModule(indexModule, freshRequire)
    print(("[ManifestLoader] Required sharded index %s"):format(indexModule.Name))
    if type(index) ~= "table" then
        error("Sharded manifest index must return a table")
    end
    if not shardFolder then
        error("Sharded manifest folder is required")
    end

    local shardCache = {}
    local chunkCache = {}
    local chunkFingerprintCache = {}
    local chunkRefs = normalizeChunkRefs(index, shardFolder, timeoutSeconds)
    ChunkSchema.validateChunkRefs(chunkRefs)
    print(("[ManifestLoader] Prepared handle for %s with %d chunkRefs"):format(indexModule.Name, #chunkRefs))
    local canonicalShardCacheByChunkId = {}
    local chunkIdsByShardName = {}

    local chunkRefById = {}
    for _, chunkRef in ipairs(chunkRefs) do
        chunkRefById[chunkRef.id] = chunkRef
    end
    local canonicalChunkRefs = nil
    local handle

    local function resolveShardModule(shardName, required)
        local shardModule = shardFolder:FindFirstChild(shardName)
        if shardModule == nil and required ~= false then
            shardModule = shardFolder:WaitForChild(shardName, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
        end
        if shardModule == nil and required ~= false then
            error(("%s.%s was not provisioned into the live DataModel"):format(shardFolder:GetFullName(), shardName))
        end
        return shardModule
    end

    local function loadShardData(shardName, required)
        local cached = shardCache[shardName]
        if cached ~= nil then
            return cached
        end

        local shardModule = resolveShardModule(shardName, required)
        if shardModule == nil then
            return nil
        end

        cached = requireModule(shardModule, freshRequire)
        shardCache[shardName] = cached
        return cached
    end

    local function shardContainsChunk(shardName, chunkId, required)
        local chunkIds = chunkIdsByShardName[shardName]
        if chunkIds == nil then
            chunkIds = {}
            local shardData = loadShardData(shardName, required)
            if shardData ~= nil then
                for _, chunk in ipairs(shardData.chunks or {}) do
                    chunkIds[chunk.id] = true
                end
            end
            chunkIdsByShardName[shardName] = chunkIds
        end

        return chunkIds[chunkId] == true
    end

    local function resolveCanonicalShardsForChunk(chunkId)
        local cached = canonicalShardCacheByChunkId[chunkId]
        if cached ~= nil then
            return cached
        end

        local chunkRef = chunkRefById[chunkId]
        if not chunkRef then
            error(("Unknown chunk id: %s"):format(tostring(chunkId)))
        end

        local declaredChunkShards = chunkRef.shards or {}
        local declaredIndexShards = index.shards or {}
        local canonicalShards = table.create(#declaredChunkShards + #declaredIndexShards)
        local seenShardNames = {}

        for _, shardName in ipairs(declaredChunkShards) do
            if not seenShardNames[shardName] and shardContainsChunk(shardName, chunkId, false) then
                seenShardNames[shardName] = true
                table.insert(canonicalShards, shardName)
            end
        end

        for _, shardName in ipairs(declaredIndexShards) do
            if not seenShardNames[shardName] and shardContainsChunk(shardName, chunkId, true) then
                seenShardNames[shardName] = true
                table.insert(canonicalShards, shardName)
            end
        end

        if #canonicalShards == 0 then
            error(("Failed to resolve canonical shards for chunk id: %s"):format(tostring(chunkId)))
        end

        chunkRef.shards = cloneArray(canonicalShards)
        canonicalShardCacheByChunkId[chunkId] = chunkRef.shards
        return chunkRef.shards
    end

    local function materializeChunkFromShardNames(chunkId, chunkRef, shardNames, required)
        if type(shardNames) ~= "table" or #shardNames == 0 then
            return nil, nil
        end

        local chunksById = {}
        local chunkOrder = {}
        local resolvedShardNames = {}

        for _, shardName in ipairs(shardNames) do
            local shardData = loadShardData(shardName, required)
            if shardData ~= nil then
                local foundChunk = false
                for _, chunk in ipairs(shardData.chunks or {}) do
                    if chunk.id == chunkId then
                        mergeChunkFragment(chunksById, chunkOrder, chunk)
                        foundChunk = true
                    end
                end
                if foundChunk then
                    table.insert(resolvedShardNames, shardName)
                end
            end
        end

        if #chunkOrder == 0 then
            return nil, nil
        end

        local validated = finalizeManifest(index, chunksById, chunkOrder, { chunkRef })
        return validated.chunks[1], resolvedShardNames
    end

    local function resolveCanonicalChunkRefs()
        if canonicalChunkRefs ~= nil then
            return canonicalChunkRefs
        end

        canonicalChunkRefs =
            buildChunkRefsFromShards(index, shardFolder, timeoutSeconds, buildChunkRefSeedMap(chunkRefs), loadShardData)
        chunkRefs = canonicalChunkRefs
        chunkRefById = {}
        for _, chunkRef in ipairs(canonicalChunkRefs) do
            chunkRefById[chunkRef.id] = chunkRef
        end
        handle.chunkRefs = canonicalChunkRefs
        return canonicalChunkRefs
    end

    handle = {
        schemaVersion = index.schemaVersion,
        meta = index.meta,
        shardFolder = index.shardFolder,
        chunkRefs = chunkRefs,
    }

    function handle:ResolveChunkRef(chunkId)
        if chunkRefById[chunkId] == nil then
            resolveCanonicalChunkRefs()
        end
        return chunkRefById[chunkId]
    end

    function handle:GetChunk(chunkId)
        local cached = chunkCache[chunkId]
        if cached ~= nil then
            return cached
        end

        local chunkRef = chunkRefById[chunkId]
        if not chunkRef then
            chunkRef = self:ResolveChunkRef(chunkId)
        end
        if not chunkRef then
            error(("Unknown chunk id: %s"):format(tostring(chunkId)))
        end

        local chunk = nil
        local resolvedShardNames = nil

        if type(chunkRef.shards) == "table" and #chunkRef.shards > 0 then
            chunk, resolvedShardNames = materializeChunkFromShardNames(chunkId, chunkRef, chunkRef.shards, false)
        end

        if chunk == nil then
            local canonicalShards = resolveCanonicalShardsForChunk(chunkId)
            chunk, resolvedShardNames = materializeChunkFromShardNames(chunkId, chunkRef, canonicalShards, true)
        end

        if not chunk then
            error(("Failed to materialize chunk id: %s"):format(tostring(chunkId)))
        end

        if resolvedShardNames and #resolvedShardNames > 0 then
            chunkRef.shards = cloneArray(resolvedShardNames)
            canonicalShardCacheByChunkId[chunkId] = chunkRef.shards
        end

        chunkCache[chunkId] = chunk
        return chunk
    end

    function handle:GetChunkFingerprint(chunkId)
        local cached = chunkFingerprintCache[chunkId]
        if cached ~= nil then
            return cached
        end

        local chunkRef = chunkRefById[chunkId]
        if not chunkRef then
            chunkRef = self:ResolveChunkRef(chunkId)
        end
        if not chunkRef then
            error(("Unknown chunk id: %s"):format(tostring(chunkId)))
        end

        local shardNames = canonicalShardCacheByChunkId[chunkId]
        if shardNames == nil then
            shardNames = chunkRef.shards
        end
        if type(shardNames) ~= "table" or #shardNames == 0 then
            shardNames = resolveCanonicalShardsForChunk(chunkId)
        end
        local shardFingerprints = table.create(#shardNames)

        for _, shardName in ipairs(shardNames) do
            local shardModule = resolveShardModule(shardName)
            local shardFingerprint = shardModule:GetAttribute("VertigoSyncSha256")
            if type(shardFingerprint) ~= "string" or shardFingerprint == "" then
                local sourceOk, sourceOrErr = pcall(function()
                    return shardModule.Source
                end)
                if sourceOk and type(sourceOrErr) == "string" then
                    shardFingerprint = ("len:%d"):format(#sourceOrErr)
                else
                    shardFingerprint = "module:" .. shardModule.Name
                end
            end
            table.insert(shardFingerprints, ("%s:%s"):format(shardName, shardFingerprint))
        end

        cached = table.concat(shardFingerprints, "|")
        chunkFingerprintCache[chunkId] = cached
        return cached
    end

    function handle:LoadChunks(chunkIds)
        local loadChunkIds = chunkIds or {}
        local chunks = table.create(#loadChunkIds)
        for arrayIndex, chunkId in ipairs(loadChunkIds) do
            chunks[arrayIndex] = self:GetChunk(chunkId)
        end
        return chunks
    end

    function handle:GetChunkIdsWithinRadius(loadCenter, loadRadius)
        if not loadRadius then
            local resolvedChunkRefs = resolveCanonicalChunkRefs()
            local chunkIds = table.create(#resolvedChunkRefs)
            for arrayIndex, chunkRef in ipairs(resolvedChunkRefs) do
                chunkIds[arrayIndex] = chunkRef.id
            end
            return chunkIds
        end

        local centerX = loadCenter and loadCenter.X or 0
        local centerZ = loadCenter and loadCenter.Z or 0
        local chunkSize = self.meta and self.meta.chunkSizeStuds or 256
        local loadRadiusSq = loadRadius * loadRadius
        local chunkIds = table.create(#self.chunkRefs)
        for _, chunkRef in ipairs(self.chunkRefs) do
            local origin = chunkRef.originStuds or { x = 0, z = 0 }
            local chunkCenterX = origin.x + chunkSize * 0.5
            local chunkCenterZ = origin.z + chunkSize * 0.5
            local dx = chunkCenterX - centerX
            local dz = chunkCenterZ - centerZ
            if dx * dx + dz * dz <= loadRadiusSq then
                table.insert(chunkIds, chunkRef.id)
            end
        end
        return chunkIds
    end

    function handle:LoadChunksWithinRadius(loadCenter, loadRadius)
        local chunkIds = self:GetChunkIdsWithinRadius(loadCenter, loadRadius)
        return self:LoadChunks(chunkIds)
    end

    function handle:MaterializeManifest()
        local resolvedChunkRefs = resolveCanonicalChunkRefs()
        local chunkIds = table.create(#resolvedChunkRefs)
        for arrayIndex, chunkRef in ipairs(resolvedChunkRefs) do
            chunkIds[arrayIndex] = chunkRef.id
        end

        local chunks = self:LoadChunks(chunkIds)
        local manifest = newManifest(index, resolvedChunkRefs)
        manifest.chunks = chunks
        return ChunkSchema.validateManifest(manifest)
    end

    return handle
end

function ManifestLoader.LoadFromShardedModuleIndex(indexModule, shardFolder, timeoutSeconds)
    local handle = ManifestLoader.LoadShardedModuleHandle(indexModule, shardFolder, timeoutSeconds)
    return handle:MaterializeManifest()
end

function ManifestLoader.LoadFromModule(module)
    if not module:IsA("ModuleScript") then
        error("Manifest must be a ModuleScript")
    end

    local manifest = require(module)
    return ChunkSchema.validateManifest(manifest)
end

function ManifestLoader.LoadSample()
    return ManifestLoader.LoadNamedSample("SampleManifest")
end

function ManifestLoader.LoadNamedSample(name, timeoutSeconds)
    local module = resolveSampleModule(name, timeoutSeconds)
    local manifest = require(module)
    return ChunkSchema.validateManifest(manifest)
end

function ManifestLoader.LoadNamedShardedSample(indexName, timeoutSeconds)
    local indexModule = resolveSampleModule(indexName, timeoutSeconds)
    return loadShardedManifest(indexModule, timeoutSeconds)
end

function ManifestLoader.LoadNamedShardedSampleHandle(indexName, timeoutSeconds, options)
    print(("[ManifestLoader] Loading named sharded sample handle %s"):format(indexName))
    local indexModule = resolveSampleModule(indexName, timeoutSeconds)
    local sampleData = resolveSampleDataFolder(timeoutSeconds)
    print(("[ManifestLoader] Requiring named sharded sample index %s"):format(indexName))
    local index = require(indexModule)
    print(("[ManifestLoader] Required named sharded sample index %s"):format(indexName))
    local shardFolderName = index.shardFolder or (indexModule.Name .. "Chunks")
    local shardFolder = sampleData:FindFirstChild(shardFolderName)
        or sampleData:WaitForChild(shardFolderName, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
    if not shardFolder then
        error(("ServerStorage.SampleData.%s was not provisioned into the live DataModel"):format(shardFolderName))
    end
    print(("[ManifestLoader] Resolved shard folder %s for %s"):format(shardFolderName, indexName))

    return ManifestLoader.LoadShardedModuleHandle(indexModule, shardFolder, timeoutSeconds, options)
end

function ManifestLoader.LoadRouteCatalogHandle(catalogModule, timeoutSeconds, options)
    if not catalogModule:IsA("ModuleScript") then
        error("Route catalog must be a ModuleScript")
    end

    local freshRequire = type(options) == "table" and options.freshRequire == true
    local rootFolder = catalogModule.Parent
    local catalog = requireTableModule(catalogModule, freshRequire, "Route catalog")
    local payloads = catalog.payloads or {}
    local payloadsByKey = {}
    local tableModuleCache = {}
    local moduleScriptCache = {}

    for _, payload in ipairs(payloads) do
        payloadsByKey[buildLanePayloadKey(payload.step_index, payload.lane)] = payload
    end

    local function resolveTableModule(modulePath, label)
        if type(modulePath) ~= "string" or modulePath == "" then
            return nil
        end

        local cached = tableModuleCache[modulePath]
        if cached ~= nil then
            return cached
        end

        local module = resolveRelativeModule(rootFolder, modulePath, timeoutSeconds)
        cached = requireTableModule(module, freshRequire, label)
        tableModuleCache[modulePath] = cached
        moduleScriptCache[modulePath] = module
        return cached
    end

    local function resolveModuleScript(modulePath)
        if type(modulePath) ~= "string" or modulePath == "" then
            return nil
        end

        local cached = moduleScriptCache[modulePath]
        if cached ~= nil then
            return cached
        end

        cached = resolveRelativeModule(rootFolder, modulePath, timeoutSeconds)
        moduleScriptCache[modulePath] = cached
        return cached
    end

    local handle = {
        catalog = catalog,
        routeCatalog = catalog,
        rootFolder = rootFolder,
        bundleRoot = rootFolder,
        payloads = payloads,
        routeSession = nil,
        hydratedRoute = nil,
        schedule = nil,
    }

    function handle:GetRouteSession()
        if self.routeSession == nil then
            self.routeSession = resolveTableModule(catalog.route_session_module_path, "Route session")
        end
        return self.routeSession
    end

    function handle:GetHydratedRoute()
        if self.hydratedRoute == nil then
            self.hydratedRoute = resolveTableModule(catalog.hydrated_route_module_path, "Hydrated route")
        end
        return self.hydratedRoute
    end

    function handle:GetSchedule()
        if self.schedule == nil then
            self.schedule = resolveTableModule(catalog.schedule_module_path, "Route schedule")
        end
        return self.schedule
    end

    function handle:GetLanePayload(stepIndex, laneName)
        local payload = payloadsByKey[buildLanePayloadKey(stepIndex, laneName)]
        if payload == nil then
            error(
                ("Route catalog does not declare a payload for step %s lane %s"):format(
                    tostring(stepIndex),
                    tostring(laneName)
                )
            )
        end
        return payload
    end

    function handle:ResolveLanePayload(stepIndex, laneName)
        return self:GetLanePayload(stepIndex, laneName)
    end

    function handle:LoadLaneSummary(stepIndex, laneName)
        local payload = self:GetLanePayload(stepIndex, laneName)
        return resolveTableModule(payload.lane_module_path, "Route lane")
    end

    function handle:LoadLane(stepIndex, laneName)
        return self:LoadLaneSummary(stepIndex, laneName)
    end

    function handle:LoadLaneManifest(stepIndex, laneName)
        local payload = self:GetLanePayload(stepIndex, laneName)
        if type(payload.manifest_module_path) ~= "string" then
            error(
                ("Route catalog payload for step %s lane %s is missing manifest_module_path"):format(
                    tostring(stepIndex),
                    tostring(laneName)
                )
            )
        end
        local module = resolveModuleScript(payload.manifest_module_path)
        return ManifestLoader.LoadFromModule(module)
    end

    function handle:LoadLaneRuntimeHandle(stepIndex, laneName, laneTimeoutSeconds, laneOptions)
        if type(laneTimeoutSeconds) == "table" and laneOptions == nil then
            laneOptions = laneTimeoutSeconds
            laneTimeoutSeconds = nil
        end
        local payload = self:GetLanePayload(stepIndex, laneName)
        if type(payload.runtime_index_module_path) ~= "string" then
            error(
                ("Route catalog payload for step %s lane %s is missing runtime_index_module_path"):format(
                    tostring(stepIndex),
                    tostring(laneName)
                )
            )
        end

        local resolvedOptions = {}
        if type(options) == "table" then
            for key, value in pairs(options) do
                resolvedOptions[key] = value
            end
        end
        if type(laneOptions) == "table" then
            for key, value in pairs(laneOptions) do
                resolvedOptions[key] = value
            end
        end

        local indexModule = resolveModuleScript(payload.runtime_index_module_path)
        return loadShardedHandleFromIndexModule(indexModule, laneTimeoutSeconds or timeoutSeconds, resolvedOptions)
    end

    function handle:LoadLaneManifestSource(stepIndex, laneName, laneTimeoutSeconds, laneOptions)
        if type(laneTimeoutSeconds) == "table" and laneOptions == nil then
            laneOptions = laneTimeoutSeconds
            laneTimeoutSeconds = nil
        end
        local payload = self:GetLanePayload(stepIndex, laneName)
        if type(payload.manifest_module_path) == "string" then
            return self:LoadLaneManifest(stepIndex, laneName)
        end
        if type(payload.runtime_index_module_path) == "string" then
            return self:LoadLaneRuntimeHandle(stepIndex, laneName, laneTimeoutSeconds, laneOptions)
        end
        error(
            ("Route catalog payload for step %s lane %s has no manifest or runtime source"):format(
                tostring(stepIndex),
                tostring(laneName)
            )
        )
    end

    handle.routeSession = handle:GetRouteSession()
    handle.hydratedRoute = handle:GetHydratedRoute()
    handle.schedule = handle:GetSchedule()

    return handle
end

function ManifestLoader.LoadNamedRouteCatalogHandle(name, timeoutSeconds, options)
    local catalogModule = resolveSampleModulePath(name, timeoutSeconds)
    return ManifestLoader.LoadRouteCatalogHandle(catalogModule, timeoutSeconds, options)
end

function ManifestLoader.LoadRouteBundleHandle(bundleFolder, timeoutSeconds, options)
    if not bundleFolder:IsA("Folder") then
        error("Route bundle must be a Folder")
    end
    local catalogModule = resolveRelativeModule(bundleFolder, "route-catalog", timeoutSeconds)
    return ManifestLoader.LoadRouteCatalogHandle(catalogModule, timeoutSeconds, options)
end

function ManifestLoader.LoadNamedRouteBundleHandle(name, timeoutSeconds, options)
    local sampleData = resolveSampleDataFolder(timeoutSeconds)
    local bundleFolder = resolveRelativeInstance(sampleData, name, timeoutSeconds)
    if not bundleFolder:IsA("Folder") then
        error(("ServerStorage.SampleData.%s must resolve to a Folder route bundle"):format(name))
    end
    return ManifestLoader.LoadRouteBundleHandle(bundleFolder, timeoutSeconds, options)
end

function ManifestLoader.ResolveModuleByPath(root, modulePath, timeoutSeconds)
    return resolveRelativeModule(root, modulePath, timeoutSeconds)
end

function ManifestLoader.LoadRouteCatalogFromModule(catalogModule, timeoutSeconds, options)
    return ManifestLoader.LoadRouteCatalogHandle(catalogModule, timeoutSeconds, options).catalog
end

function ManifestLoader.LoadNamedRouteCatalog(name, timeoutSeconds, options)
    return ManifestLoader.LoadNamedRouteCatalogHandle(name, timeoutSeconds, options).catalog
end

function ManifestLoader.LoadRouteSessionFromCatalogModule(catalogModule, timeoutSeconds, options)
    return ManifestLoader.LoadRouteCatalogHandle(catalogModule, timeoutSeconds, options):GetRouteSession()
end

function ManifestLoader.LoadHydratedRouteFromCatalogModule(catalogModule, timeoutSeconds, options)
    return ManifestLoader.LoadRouteCatalogHandle(catalogModule, timeoutSeconds, options):GetHydratedRoute()
end

function ManifestLoader.LoadRouteScheduleFromCatalogModule(catalogModule, timeoutSeconds, options)
    return ManifestLoader.LoadRouteCatalogHandle(catalogModule, timeoutSeconds, options):GetSchedule()
end

function ManifestLoader.LoadRouteLaneManifestFromCatalogModule(
    catalogModule,
    stepIndex,
    laneName,
    timeoutSeconds,
    options
)
    local manifest = ManifestLoader.LoadRouteCatalogHandle(catalogModule, timeoutSeconds, options)
        :LoadLaneManifest(stepIndex, laneName)
    if manifest == nil then
        error(
            ("Route catalog does not expose a materialized manifest for step %s lane %s"):format(
                tostring(stepIndex),
                tostring(laneName)
            )
        )
    end
    return manifest
end

function ManifestLoader.LoadRouteLaneRuntimeHandleFromCatalogModule(
    catalogModule,
    stepIndex,
    laneName,
    timeoutSeconds,
    options
)
    local handle = ManifestLoader.LoadRouteCatalogHandle(catalogModule, timeoutSeconds, options)
        :LoadLaneRuntimeHandle(stepIndex, laneName, options)
    if handle == nil then
        error(
            ("Route catalog does not expose a runtime handle for step %s lane %s"):format(
                tostring(stepIndex),
                tostring(laneName)
            )
        )
    end
    return handle
end

function ManifestLoader.FreezeHandleForChunkIds(handle, chunkIds)
    local sourceChunkIds = chunkIds or {}
    local frozenChunkIds = table.create(#sourceChunkIds)
    local frozenChunkIdSet = {}
    for _, chunkId in ipairs(sourceChunkIds) do
        if not frozenChunkIdSet[chunkId] then
            frozenChunkIdSet[chunkId] = true
            table.insert(frozenChunkIds, chunkId)
        end
    end

    local frozenChunkRefs = table.create(#frozenChunkIds)
    local frozenChunkRefById = {}
    for _, chunkId in ipairs(frozenChunkIds) do
        local resolvedChunkRef = nil
        if type(handle.ResolveChunkRef) == "function" then
            resolvedChunkRef = handle:ResolveChunkRef(chunkId)
        else
            for _, chunkRef in ipairs(handle.chunkRefs or {}) do
                if chunkRef.id == chunkId then
                    resolvedChunkRef = chunkRef
                    break
                end
            end
        end
        if resolvedChunkRef ~= nil then
            local frozenRef = cloneChunkRef(resolvedChunkRef)
            frozenChunkRefById[chunkId] = frozenRef
            table.insert(frozenChunkRefs, frozenRef)
        end
    end

    local frozenChunks = {}
    local frozenFingerprints = {}
    for _, chunkId in ipairs(frozenChunkIds) do
        frozenChunks[chunkId] = handle:GetChunk(chunkId)
        frozenFingerprints[chunkId] = handle:GetChunkFingerprint(chunkId)
    end

    local frozenHandle = {
        schemaVersion = handle.schemaVersion,
        meta = handle.meta,
        chunkRefs = frozenChunkRefs,
    }

    function frozenHandle:GetChunk(chunkId)
        local chunk = frozenChunks[chunkId]
        if chunk == nil then
            error(("Unknown frozen chunk id: %s"):format(tostring(chunkId)))
        end
        return chunk
    end

    function frozenHandle:GetChunkFingerprint(chunkId)
        local fingerprint = frozenFingerprints[chunkId]
        if fingerprint == nil then
            error(("Unknown frozen chunk id: %s"):format(tostring(chunkId)))
        end
        return fingerprint
    end

    function frozenHandle:LoadChunks(loadChunkIds)
        local requestedChunkIds = loadChunkIds or {}
        local chunks = table.create(#requestedChunkIds)
        for index, chunkId in ipairs(requestedChunkIds) do
            chunks[index] = self:GetChunk(chunkId)
        end
        return chunks
    end

    function frozenHandle:GetChunkIdsWithinRadius(loadCenter, loadRadius)
        if not loadRadius then
            local ids = table.create(#self.chunkRefs)
            for index, chunkRef in ipairs(self.chunkRefs) do
                ids[index] = chunkRef.id
            end
            return ids
        end

        local centerX = loadCenter and loadCenter.X or 0
        local centerZ = loadCenter and loadCenter.Z or 0
        local chunkSize = self.meta and self.meta.chunkSizeStuds or 256
        local loadRadiusSq = loadRadius * loadRadius
        local ids = table.create(#self.chunkRefs)
        for _, chunkRef in ipairs(self.chunkRefs) do
            local origin = chunkRef.originStuds or { x = 0, z = 0 }
            local chunkCenterX = origin.x + chunkSize * 0.5
            local chunkCenterZ = origin.z + chunkSize * 0.5
            local dx = chunkCenterX - centerX
            local dz = chunkCenterZ - centerZ
            if dx * dx + dz * dz <= loadRadiusSq then
                table.insert(ids, chunkRef.id)
            end
        end
        return ids
    end

    function frozenHandle:LoadChunksWithinRadius(loadCenter, loadRadius)
        return self:LoadChunks(self:GetChunkIdsWithinRadius(loadCenter, loadRadius))
    end

    function frozenHandle:MaterializeManifest()
        local manifest = newManifest({
            schemaVersion = self.schemaVersion,
            meta = self.meta,
        }, self.chunkRefs)
        manifest.chunks = self:LoadChunks(frozenChunkIds)
        return ChunkSchema.validateManifest(manifest)
    end

    return frozenHandle
end

function ManifestLoader.RequireNamedSample(name, timeoutSeconds)
    local module = resolveSampleModule(name, timeoutSeconds)
    return require(module)
end

function ManifestLoader.LoadFromFile(_path)
    -- In Studio, we might use a plugin to read files,
    -- but for runtime scripts we rely on pre-loaded ModuleScripts.
    Logger.warn("LoadFromFile not implemented for runtime - use LoadFromModule")
    return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- External manifest loading (HttpService / AssetService).
--
-- These resolvers exist so that release builds can keep `roblox/src/ServerStorage/SampleData/`
-- excluded from the .rbxlx and instead pull manifest JSON from external storage at
-- runtime. The current `require()` Lua-shard path is preserved as the default and as
-- the fallback when external sources fail.
--
-- The returned object exposes the same surface used by ChunkLoader / StreamingService
-- (chunkRefs, GetChunk, GetChunkFingerprint, LoadChunks, GetChunkIdsWithinRadius,
-- LoadChunksWithinRadius, MaterializeManifest) so callers do not need to special-case it.
-- ─────────────────────────────────────────────────────────────────────────────

local externalManifestCache = {}

local function djb2Fingerprint(str)
    local hash = 5381
    for i = 1, #str do
        hash = ((hash * 33) + string.byte(str, i)) % 4294967296
    end
    return string.format("djb2:%08x", hash)
end

local function buildInMemoryHandle(manifest, sourceTag, chunkFetcher)
    if type(manifest) ~= "table" then
        error("In-memory manifest must be a table")
    end
    manifest = ChunkSchema.validateManifest(manifest)

    local chunks = manifest.chunks or {}
    local chunkRefs = manifest.chunkRefs
    if not hasChunkRefs(chunkRefs) then
        chunkRefs = table.create(#chunks)
        for index, chunk in ipairs(chunks) do
            chunkRefs[index] = {
                id = chunk.id,
                originStuds = chunk.originStuds and table.clone(chunk.originStuds) or { x = 0, y = 0, z = 0 },
                shards = {},
            }
        end
    else
        chunkRefs = cloneChunkRefs(chunkRefs)
    end
    ChunkSchema.validateChunkRefs(chunkRefs)

    -- chunksById is the in-memory chunk cache. For embedded/sample manifests
    -- it is fully populated upfront. For lazy sources (external_url) it starts
    -- empty and gets filled on demand by the chunkFetcher when GetChunk /
    -- LoadChunks is called. The downstream consumers (AustinSpawn,
    -- StreamingService, ChunkPriority) already use the spatial query path,
    -- so once a chunk is fetched it stays in cache for the rest of the
    -- session and the scheduler decides when to materialize it.
    local chunksById = {}
    local chunkOrder = table.create(#chunks)
    for _, chunk in ipairs(chunks) do
        chunksById[chunk.id] = chunk
        table.insert(chunkOrder, chunk.id)
    end

    local fingerprintBase = sourceTag or "in_memory"
    local fingerprintsByChunkId = {}

    -- chunkRefMap is used by LoadChunks/PrefetchChunks for O(1) lookup of a
    -- ref by id. We rebuild it on every chunkRefs mutation; the planetary
    -- streaming roadmap will mutate chunkRefs as new shards come online.
    local chunkRefMap = {}
    for _, ref in ipairs(chunkRefs) do
        chunkRefMap[ref.id] = ref
    end

    local handle = {
        schemaVersion = manifest.schemaVersion,
        meta = manifest.meta,
        chunkRefs = chunkRefs,
        manifestSourceKind = "external",
    }

    function handle:ResolveChunkRef(chunkId)
        return chunkRefMap[chunkId]
    end

    -- Internal helper that performs a parallel fan-out fetch over the given
    -- list of ids using the chunkFetcher. Results are written into chunksById
    -- so subsequent GetChunk calls return from cache. Returns the count of
    -- successfully fetched chunks. This is the streaming hot path: bootstrap
    -- only fetches the chunks within the spawn radius (typically 5-9), and
    -- StreamingService later calls GetChunk one-by-one as the player moves.
    local function fetchChunkBatch(idsToFetch, progressCallback)
        if not chunkFetcher or type(chunkFetcher.fetchParallel) ~= "function" then
            local fetched = 0
            for _, id in ipairs(idsToFetch) do
                if chunksById[id] == nil and chunkFetcher and type(chunkFetcher.fetchSingle) == "function" then
                    local chunk = chunkFetcher.fetchSingle(id)
                    if chunk ~= nil then
                        chunksById[id] = chunk
                        fetched += 1
                        if progressCallback then
                            progressCallback(fetched, #idsToFetch)
                        end
                    end
                end
            end
            return fetched
        end
        return chunkFetcher.fetchParallel(idsToFetch, function(id, chunk)
            if chunk ~= nil and chunksById[id] == nil then
                chunksById[id] = chunk
            end
        end, progressCallback)
    end

    function handle:GetChunk(chunkId)
        local chunk = chunksById[chunkId]
        if chunk ~= nil then
            return chunk
        end
        if chunkFetcher and type(chunkFetcher.fetchSingle) == "function" then
            chunk = chunkFetcher.fetchSingle(chunkId)
            if chunk ~= nil then
                chunksById[chunkId] = chunk
                return chunk
            end
        end
        error(("Unknown external chunk id: %s"):format(tostring(chunkId)))
    end

    function handle:HasChunkInCache(chunkId)
        return chunksById[chunkId] ~= nil
    end

    function handle:GetCachedChunkCount()
        local count = 0
        for _ in pairs(chunksById) do
            count += 1
        end
        return count
    end

    function handle:PrefetchChunks(chunkIds, progressCallback)
        if type(chunkIds) ~= "table" or #chunkIds == 0 then
            return 0
        end
        local toFetch = {}
        for _, id in ipairs(chunkIds) do
            if chunksById[id] == nil then
                table.insert(toFetch, id)
            end
        end
        if #toFetch == 0 then
            return 0
        end
        return fetchChunkBatch(toFetch, progressCallback)
    end

    function handle:GetChunkFingerprint(chunkId)
        local cached = fingerprintsByChunkId[chunkId]
        if cached ~= nil then
            return cached
        end
        cached = ("%s:%s"):format(fingerprintBase, tostring(chunkId))
        fingerprintsByChunkId[chunkId] = cached
        return cached
    end

    function handle:LoadChunks(chunkIds)
        local requestedChunkIds = chunkIds or {}
        -- Fast path: gather any uncached ids and fan them out in parallel
        -- before the per-chunk return loop. This collapses the spawn-radius
        -- fetch from N sequential round trips to one parallel batch.
        local missing = nil
        for _, chunkId in ipairs(requestedChunkIds) do
            if chunksById[chunkId] == nil then
                if missing == nil then
                    missing = {}
                end
                table.insert(missing, chunkId)
            end
        end
        if missing and #missing > 0 then
            fetchChunkBatch(missing, nil)
        end
        -- Collect results, skipping any chunks that failed to fetch during
        -- the batch. We deliberately do NOT fall through to `self:GetChunk`
        -- here because that would (1) trigger a second serial HTTP request
        -- per missing chunk that was already attempted in the batch, and
        -- (2) cascade into a hard error that aborts the whole bootstrap for
        -- a single failed chunk. Returning a partial result lets the
        -- ImportService progress on the chunks that succeeded while the
        -- chunkFetcher stats record the failures for the audit pipeline.
        local out = table.create(#requestedChunkIds)
        local skipped = 0
        for _, chunkId in ipairs(requestedChunkIds) do
            local chunk = chunksById[chunkId]
            if chunk ~= nil then
                out[#out + 1] = chunk
            else
                skipped += 1
            end
        end
        if skipped > 0 then
            warn(
                ("[ManifestLoader] LoadChunks returned %d/%d chunks; %d failed during batch fetch and were skipped"):format(
                    #out,
                    #requestedChunkIds,
                    skipped
                )
            )
        end
        return out
    end

    function handle:GetChunkIdsWithinRadius(loadCenter, loadRadius)
        if not loadRadius then
            local ids = table.create(#self.chunkRefs)
            for index, chunkRef in ipairs(self.chunkRefs) do
                ids[index] = chunkRef.id
            end
            return ids
        end

        local centerX = loadCenter and loadCenter.X or 0
        local centerZ = loadCenter and loadCenter.Z or 0
        local chunkSize = self.meta and self.meta.chunkSizeStuds or 256
        local loadRadiusSq = loadRadius * loadRadius
        local ids = table.create(#self.chunkRefs)
        for _, chunkRef in ipairs(self.chunkRefs) do
            local origin = chunkRef.originStuds or { x = 0, z = 0 }
            local chunkCenterX = origin.x + chunkSize * 0.5
            local chunkCenterZ = origin.z + chunkSize * 0.5
            local dx = chunkCenterX - centerX
            local dz = chunkCenterZ - centerZ
            if dx * dx + dz * dz <= loadRadiusSq then
                table.insert(ids, chunkRef.id)
            end
        end
        return ids
    end

    function handle:LoadChunksWithinRadius(loadCenter, loadRadius)
        return self:LoadChunks(self:GetChunkIdsWithinRadius(loadCenter, loadRadius))
    end

    function handle:MaterializeManifest()
        local materialized = newManifest({
            schemaVersion = self.schemaVersion,
            meta = self.meta,
        }, self.chunkRefs)
        materialized.chunks = table.create(#chunkOrder)
        for _, chunkId in ipairs(chunkOrder) do
            table.insert(materialized.chunks, chunksById[chunkId])
        end
        return ChunkSchema.validateManifest(materialized)
    end

    return handle
end

function ManifestLoader.LoadFromInMemoryManifest(manifest, sourceTag)
    return buildInMemoryHandle(manifest, sourceTag)
end

local function decodeManifestJson(rawJson, sourceTag)
    if type(rawJson) ~= "string" or rawJson == "" then
        error(("External manifest payload from %s was empty"):format(tostring(sourceTag)))
    end
    local HttpService = game:GetService("HttpService")
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(rawJson)
    end)
    if not ok then
        error(("Failed to JSONDecode manifest from %s: %s"):format(tostring(sourceTag), tostring(decoded)))
    end
    if type(decoded) ~= "table" then
        error(("External manifest from %s did not decode to a table"):format(tostring(sourceTag)))
    end
    return decoded
end

function ManifestLoader.loadFromExternalSource(sourceUrl, options)
    if type(sourceUrl) ~= "string" or sourceUrl == "" then
        error("loadFromExternalSource requires a non-empty source URL")
    end

    local cacheKey = "url::" .. sourceUrl
    local bypassCache = type(options) == "table" and options.bypassCache == true
    if not bypassCache then
        local cached = externalManifestCache[cacheKey]
        if cached ~= nil then
            return cached
        end
    end

    print(("[ManifestLoader] Fetching external manifest from %s"):format(sourceUrl))
    local HttpService = game:GetService("HttpService")
    -- RequestAsync (not GetAsync) so we can send Accept-Encoding: gzip and let
    -- Cloudflare's edge auto-compress the response. Index alone is small, but
    -- this also normalizes error reporting (StatusCode + StatusMessage in the
    -- error overlay) for the very first network call the bootstrap makes.
    -- Falls back to GetAsync if RequestAsync misbehaves (some platform builds
    -- pass gzip through undecoded).
    local body
    do
        local okReq, reqResponse = pcall(function()
            return HttpService:RequestAsync({
                Url = sourceUrl,
                Method = "GET",
                -- Restricted headers (Accept-Encoding, User-Agent) are
                -- not allowed by HttpService:RequestAsync and throw
                -- "Header X is not allowed!". Engine auto-negotiates gzip.
                Headers = {
                    ["Accept"] = "application/json",
                },
            })
        end)
        if okReq and type(reqResponse) == "table" and reqResponse.Success == true
            and type(reqResponse.Body) == "string" and reqResponse.Body ~= ""
        then
            body = reqResponse.Body
        else
            local okGet, getResponse = pcall(function()
                return HttpService:GetAsync(sourceUrl, true)
            end)
            if not okGet or type(getResponse) ~= "string" or getResponse == "" then
                local reqDescription = if okReq then tostring(reqResponse and reqResponse.StatusCode) else tostring(reqResponse)
                error(
                    ("HttpService manifest fetch %s failed. RequestAsync: %s | GetAsync: %s"):format(
                        sourceUrl,
                        reqDescription,
                        tostring(getResponse)
                    )
                )
            end
            body = getResponse
        end
    end

    local manifest = decodeManifestJson(body, sourceUrl)

    -- Split manifest support: when the index advertises a chunkBaseUrl we
    -- treat the per-chunk JSON files as a *lazy* chunk source. We do NOT
    -- pre-fetch all 93 chunks here — instead we hand the manifest handle a
    -- chunkFetcher closure (single + parallel) that fetches on demand. The
    -- bootstrap calls LoadChunksWithinRadius(spawn, radius) which only pulls
    -- the ~5-9 near-ring chunks; StreamingService later calls GetChunk for
    -- additional chunks as the player moves. This is the same architecture
    -- as Cesium 3D Tiles / Google Earth: the spatial scheduler drives demand
    -- and the network fetches just enough to render what the player sees.
    local chunkFetcher = nil
    if manifest.chunkBaseUrl and (not manifest.chunks or #manifest.chunks == 0) then
        local chunkBaseUrl = manifest.chunkBaseUrl
        local total = manifest.chunkRefs and #manifest.chunkRefs or 0
        print(
            ("[ManifestLoader] Lazy split-manifest source bound: %d chunkRefs available from %s"):format(
                total,
                chunkBaseUrl
            )
        )

        -- Soft-link to LoadingScreen so the live player sees streaming
        -- progress without us having to thread a callback through four
        -- layers of API surface.
        local LoadingScreen
        do
            local ok, mod = pcall(function()
                return require(script.Parent.LoadingScreen)
            end)
            if ok then
                LoadingScreen = mod
            end
        end
        local function reportLoadingScreen(text)
            if LoadingScreen and type(LoadingScreen.SetStatus) == "function" then
                pcall(LoadingScreen.SetStatus, text)
            end
        end

        local function buildChunkFetchUrl(chunkBaseUrl, chunkId)
            local queryStart = string.find(chunkBaseUrl, "?", 1, true)
            if queryStart then
                local basePath = string.sub(chunkBaseUrl, 1, queryStart - 1)
                local querySuffix = string.sub(chunkBaseUrl, queryStart)
                return basePath .. chunkId .. ".json" .. querySuffix
            end
            return chunkBaseUrl .. chunkId .. ".json"
        end

        -- Use RequestAsync with explicit Accept-Encoding so Cloudflare's edge
        -- auto-gzip kicks in. Each chunk drops from 1146 KB → 235 KB on the
        -- wire (4.87× reduction). HttpService:GetAsync does not send
        -- Accept-Encoding by default, so the previous code was paying full
        -- uncompressed bandwidth for no reason.
        --
        -- Fallback: if RequestAsync returns a body that doesn't decode as
        -- JSON (which would happen if Roblox passed through gzipped binary
        -- without inflating), we retry with GetAsync once. This guards
        -- against the platform not auto-decompressing on the response side.
        local function fetchChunkViaRequest(chunkId)
            local chunkUrl = buildChunkFetchUrl(chunkBaseUrl, chunkId)
            local ok, response = pcall(function()
                return HttpService:RequestAsync({
                    Url = chunkUrl,
                    Method = "GET",
                    -- Roblox HttpService restricts several common headers
                    -- (Accept-Encoding, User-Agent, Host, etc.) — setting any
                    -- of them causes RequestAsync to throw "Header X is not
                    -- allowed!". The engine adds its own User-Agent and
                    -- handles gzip auto-negotiation internally when the
                    -- server responds with Content-Encoding: gzip, so
                    -- dropping our custom headers is safe and lets the
                    -- request succeed. Only whitelisted headers (Accept,
                    -- Content-Type, custom X-* prefixes) are allowed.
                    Headers = {
                        ["Accept"] = "application/json",
                    },
                })
            end)
            if not ok or type(response) ~= "table" then
                return nil, ("RequestAsync error: %s"):format(tostring(response))
            end
            if response.Success ~= true then
                return nil, ("HTTP %s: %s"):format(
                    tostring(response.StatusCode),
                    tostring(response.StatusMessage)
                )
            end
            local body = response.Body
            if type(body) ~= "string" or body == "" then
                return nil, "empty body"
            end
            local okDecode, chunkData = pcall(function()
                return HttpService:JSONDecode(body)
            end)
            if not okDecode or type(chunkData) ~= "table" then
                return nil, ("JSON decode failed: %s"):format(tostring(chunkData))
            end
            return chunkData, nil
        end

        local function fetchChunkViaGet(chunkId)
            local chunkUrl = buildChunkFetchUrl(chunkBaseUrl, chunkId)
            local ok, response = pcall(function()
                return HttpService:GetAsync(chunkUrl, true)
            end)
            if not ok or type(response) ~= "string" then
                return nil, ("GetAsync error: %s"):format(tostring(response))
            end
            local okDecode, chunkData = pcall(function()
                return HttpService:JSONDecode(response)
            end)
            if not okDecode or type(chunkData) ~= "table" then
                return nil, ("JSON decode failed: %s"):format(tostring(chunkData))
            end
            return chunkData, nil
        end

        local function isChunkFetchRateLimited(errText)
            if type(errText) ~= "string" or errText == "" then
                return false
            end
            return string.find(errText, "Number of requests exceeded limit", 1, true) ~= nil
                or string.find(errText, "HTTP 429", 1, true) ~= nil
        end

        local function fetchChunkOverHttp(chunkId)
            local REQUEST_RETRY_DELAYS_SECONDS = { 0.5, 1, 2 }
            local chunkData = nil
            local err = nil
            for attempt = 1, #REQUEST_RETRY_DELAYS_SECONDS + 1 do
                chunkData, err = fetchChunkViaRequest(chunkId)
                if chunkData ~= nil then
                    return chunkData
                end
                if not isChunkFetchRateLimited(err) then
                    break
                end
                if attempt <= #REQUEST_RETRY_DELAYS_SECONDS then
                    task.wait(REQUEST_RETRY_DELAYS_SECONDS[attempt])
                end
            end
            if isChunkFetchRateLimited(err) then
                warn(("[ManifestLoader] RequestAsync rate limited for chunk %s; skipping immediate GetAsync fallback"):format(
                    tostring(chunkId)
                ))
                return nil
            end
            -- Fall back to GetAsync if RequestAsync failed for any reason —
            -- including "decoded body wasn't JSON" which would be the symptom
            -- of platform-side gzip pass-through.
            local fallbackData, fallbackErr = fetchChunkViaGet(chunkId)
            if fallbackData ~= nil then
                return fallbackData
            end
            warn(
                ("[ManifestLoader] Both RequestAsync and GetAsync failed for chunk %s. RequestAsync: %s | GetAsync: %s"):format(
                    tostring(chunkId),
                    tostring(err),
                    tostring(fallbackErr)
                )
            )
            return nil
        end

        -- Per-fetch telemetry: every successful fetch contributes a sample,
        -- every failure increments the error counter. We mirror running
        -- aggregates onto Workspace attributes so the Studio Explorer, the
        -- harness audit scripts (scene_parity_audit.py et al), and any future
        -- live-stream telemetry tooling can consume them without parsing logs.
        local Workspace = game:GetService("Workspace")
        local stats = {
            fetchCount = 0,
            failureCount = 0,
            totalBytes = 0,
            totalLatencySeconds = 0,
            slowestLatencySeconds = 0,
            slowestChunkId = "",
        }
        local function publishStats()
            local avgLatencyMs = if stats.fetchCount > 0
                then (stats.totalLatencySeconds / stats.fetchCount) * 1000
                else 0
            Workspace:SetAttribute("ArnisChunkFetchCount", stats.fetchCount)
            Workspace:SetAttribute("ArnisChunkFetchFailures", stats.failureCount)
            Workspace:SetAttribute("ArnisChunkFetchBytes", stats.totalBytes)
            Workspace:SetAttribute("ArnisChunkFetchAvgLatencyMs", avgLatencyMs)
            Workspace:SetAttribute("ArnisChunkFetchSlowestLatencyMs", stats.slowestLatencySeconds * 1000)
            Workspace:SetAttribute("ArnisChunkFetchSlowestChunkId", stats.slowestChunkId)
            Workspace:SetAttribute("ArnisChunkFetchSourceUrl", chunkBaseUrl)
        end

        local rawFetchChunk = fetchChunkOverHttp
        fetchChunkOverHttp = function(chunkId)
            local startClock = os.clock()
            local result = rawFetchChunk(chunkId)
            local elapsed = os.clock() - startClock
            stats.fetchCount += 1
            stats.totalLatencySeconds += elapsed
            if elapsed > stats.slowestLatencySeconds then
                stats.slowestLatencySeconds = elapsed
                stats.slowestChunkId = tostring(chunkId)
            end
            if result == nil then
                stats.failureCount += 1
            else
                -- Approximate bytes by re-encoding the decoded table. This
                -- intentionally undercounts compared to the wire bytes (which
                -- include gzip overhead and JSON whitespace) but it gives the
                -- audit pipeline a stable byte budget figure that doesn't
                -- depend on transport details.
                local okEnc, encoded = pcall(function()
                    return HttpService:JSONEncode(result)
                end)
                if okEnc and type(encoded) == "string" then
                    stats.totalBytes += #encoded
                end
            end
            if stats.fetchCount % 3 == 0 or result == nil then
                publishStats()
            end
            return result
        end

        chunkFetcher = {
            sourceUrl = chunkBaseUrl,
            chunkCount = total,
            stats = stats,
            publishStats = publishStats,
            fetchSingle = fetchChunkOverHttp,
            fetchParallel = function(idsToFetch, onChunkLoaded, progressCallback)
                local count = #idsToFetch
                if count == 0 then
                    return 0
                end
                local MAX_PARALLEL_CHUNK_REQUESTS = 4
                local startClock = os.clock()
                reportLoadingScreen(
                    ("Streaming %d chunks from Cloudflare worker..."):format(count)
                )
                local completed = 0
                local fetched = 0
                local nextIndex = 1
                local workerCount = math.min(count, MAX_PARALLEL_CHUNK_REQUESTS)
                for _ = 1, workerCount do
                    task.spawn(function()
                        while true do
                            local currentIndex = nextIndex
                            nextIndex += 1
                            if currentIndex > count then
                                break
                            end

                            local capturedId = idsToFetch[currentIndex]
                            local chunkData = fetchChunkOverHttp(capturedId)
                            if chunkData ~= nil then
                                onChunkLoaded(capturedId, chunkData)
                                fetched += 1
                            end
                            completed += 1
                            if progressCallback then
                                progressCallback(completed, count)
                            end
                            if LoadingScreen and (completed % 3 == 0 or completed == count) then
                                reportLoadingScreen(
                                    ("Streaming chunks from Cloudflare (%d/%d)..."):format(completed, count)
                                )
                            end
                        end
                    end)
                end
                local FETCH_TIMEOUT_SECONDS = 60
                local pollDeadline = os.clock() + FETCH_TIMEOUT_SECONDS
                while completed < count and os.clock() < pollDeadline do
                    task.wait(0.05)
                end
                local elapsed = os.clock() - startClock
                if completed < count then
                    warn(
                        ("[ManifestLoader] Parallel fetch timed out after %ds: %d/%d completed"):format(
                            FETCH_TIMEOUT_SECONDS,
                            completed,
                            count
                        )
                    )
                else
                    print(
                        ("[ManifestLoader] Lazy fetch completed: %d/%d chunks in %.2fs (parallel, %d req in flight)"):format(
                            fetched,
                            count,
                            elapsed,
                            workerCount
                        )
                    )
                end
                publishStats()
                return fetched
            end,
        }
    end

    local handle = buildInMemoryHandle(manifest, djb2Fingerprint(body), chunkFetcher)
    handle.manifestSourceKind = "external_url"
    handle.manifestSourceName = sourceUrl
    externalManifestCache[cacheKey] = handle
    return handle
end

function ManifestLoader.loadFromRobloxAsset(assetId, options)
    local numericAssetId = tonumber(assetId)
    if not numericAssetId or numericAssetId <= 0 then
        error("loadFromRobloxAsset requires a positive asset id")
    end

    local cacheKey = "asset::" .. tostring(numericAssetId)
    local bypassCache = type(options) == "table" and options.bypassCache == true
    if not bypassCache then
        local cached = externalManifestCache[cacheKey]
        if cached ~= nil then
            return cached
        end
    end

    print(("[ManifestLoader] Fetching external manifest from rbxassetid://%d"):format(numericAssetId))
    -- AssetService:GetAssetFetchStatusAsync / InsertService can return ModuleScripts,
    -- but for free-form JSON payloads the supported runtime path is to host the JSON
    -- behind a Roblox URL alias and read it via HttpService. This wrapper exists so
    -- callers can express intent ("roblox_asset") without leaking the underlying
    -- transport into config; on platforms where AssetService:CreatePlaceAsync or
    -- MarketplaceService:GetProductInfo is the right path, swap implementations here.
    local HttpService = game:GetService("HttpService")
    local assetUrl = ("https://assetdelivery.roblox.com/v1/asset?id=%d"):format(numericAssetId)
    local ok, response = pcall(function()
        return HttpService:GetAsync(assetUrl, true)
    end)
    if not ok then
        error(("AssetService fetch for asset %d failed: %s"):format(numericAssetId, tostring(response)))
    end

    local manifest = decodeManifestJson(response, assetUrl)
    local handle = buildInMemoryHandle(manifest, djb2Fingerprint(response))
    handle.manifestSourceKind = "roblox_asset"
    handle.manifestSourceName = ("rbxassetid://%d"):format(numericAssetId)
    externalManifestCache[cacheKey] = handle
    return handle
end

function ManifestLoader.clearExternalManifestCache()
    externalManifestCache = {}
end

-- Resolve a manifest source from a config table:
--   { mode = "embedded" | "external_url" | "roblox_asset",
--     externalUrl = "...", robloxAssetId = N }
-- with a fallback to the embedded SampleData path on any failure.
function ManifestLoader.LoadFromManifestSourceConfig(config, embeddedFallback, options)
    config = config or {}
    local mode = config.mode or "embedded"
    local function tryEmbedded()
        if type(embeddedFallback) ~= "function" then
            error("ManifestSource fallback was not provided for mode " .. tostring(mode))
        end
        return embeddedFallback()
    end

    if mode == "embedded" then
        return tryEmbedded()
    end

    local ok, handleOrErr
    if mode == "external_url" then
        ok, handleOrErr = pcall(ManifestLoader.loadFromExternalSource, config.externalUrl, options)
    elseif mode == "roblox_asset" then
        ok, handleOrErr = pcall(ManifestLoader.loadFromRobloxAsset, config.robloxAssetId, options)
    else
        Logger.warn(("Unknown ManifestSource.mode %q; falling back to embedded"):format(tostring(mode)))
        return tryEmbedded()
    end

    if ok then
        return handleOrErr
    end

    Logger.warn(
        ("ManifestSource mode=%s failed (%s); falling back to embedded SampleData"):format(
            tostring(mode),
            tostring(handleOrErr)
        )
    )
    return tryEmbedded()
end

return ManifestLoader
