-- RealMidtownBootstrap.server.lua
-- Legacy full Arnis importer kept only as a fallback/reference.
-- IMPORTANT: the emitted Midtown shards are ~2.1 GB, so materializing all of
-- them in Studio is intentionally disabled. RealMidtownCompact.server.lua is
-- the production path used by ViewersVSMe.

local RUN_ON_BOOT = false
if not RUN_ON_BOOT then
    return
end

local ServerStorage = game:GetService("ServerStorage")
local ImportService = require(script.Parent.ImportService)
local ManifestLoader = require(script.Parent.ImportService.ManifestLoader)

local function loadMidtown()
    task.wait(2)
    local sampleData = ServerStorage:WaitForChild("SampleData", 15)
    local indexModule = sampleData:WaitForChild("MidtownManifestIndex", 15)
    local shardFolder = sampleData:WaitForChild("MidtownManifestChunks", 15)

    local handle = ManifestLoader.LoadShardedModuleHandle(indexModule, shardFolder, 15)
    local manifest = handle:MaterializeManifest()
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = "GeneratedWorld",
    })
end

task.spawn(function()
    local ok, err = pcall(loadMidtown)
    if not ok then
        warn("[REAL MIDTOWN LEGACY] IMPORT FAILED: " .. tostring(err))
    end
end)
