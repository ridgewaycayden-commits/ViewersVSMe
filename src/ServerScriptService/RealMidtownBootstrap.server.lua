-- RealMidtownBootstrap.server.lua
-- Loads the generated Arnis sharded Midtown manifest directly.
-- This intentionally bypasses ManifestLoader.LoadNamedSample, which treats the
-- generated index like a normal manifest and returns zero materialized chunks.

local ServerStorage = game:GetService("ServerStorage")
local ImportService = require(script.Parent.ImportService)
local ManifestLoader = require(script.Parent.ImportService.ManifestLoader)

local RUN_ON_BOOT = true
if not RUN_ON_BOOT then return end

local function loadMidtown()
    task.wait(2)
    local sampleData = ServerStorage:WaitForChild("SampleData", 15)
    local indexModule = sampleData:WaitForChild("MidtownManifestIndex", 15)
    local shardFolder = sampleData:WaitForChild("MidtownManifestChunks", 15)

    print("[REAL MIDTOWN] Preparing sharded Manhattan data...")
    local handle = ManifestLoader.LoadShardedModuleHandle(indexModule, shardFolder, 15)
    print(("[REAL MIDTOWN] %d chunk refs found"):format(#(handle.chunkRefs or {})))

    local manifest = handle:MaterializeManifest()
    print(("[REAL MIDTOWN] %d chunks materialized; importing world..."):format(#(manifest.chunks or {})))

    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = "GeneratedWorld",
    })

    print("[REAL MIDTOWN] IMPORT COMPLETE")
end

task.spawn(function()
    local ok, err = pcall(loadMidtown)
    if not ok then
        warn("[REAL MIDTOWN] IMPORT FAILED: " .. tostring(err))
    end
end)
