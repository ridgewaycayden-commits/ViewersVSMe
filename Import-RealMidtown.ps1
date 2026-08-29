$ErrorActionPreference = 'Stop'

$game = 'C:\Users\mika9\ViewersVSMe'
$arnis = 'C:\Users\mika9\arnis-roblox\roblox\src'

$index = Join-Path $arnis 'ServerStorage\SampleData\MidtownManifestIndex.lua'
$chunks = Join-Path $arnis 'ServerStorage\SampleData\MidtownManifestChunks'
$importService = Join-Path $arnis 'ServerScriptService\ImportService'
$shared = Join-Path $arnis 'ReplicatedStorage\Shared'

Write-Host '[1/5] Checking the real Midtown files...'
foreach ($p in @($index, $chunks, $importService, $shared)) {
    if (-not (Test-Path $p)) {
        Write-Host "MISSING: $p" -ForegroundColor Red
        Write-Host 'Nothing was changed.'
        exit 1
    }
}

Write-Host '[2/5] Copying Arnis runtime + real Midtown data into ViewersVSMe...'
New-Item -ItemType Directory -Force -Path (Join-Path $game 'src\ServerStorage\SampleData') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $game 'src\ReplicatedStorage') | Out-Null

Copy-Item $index (Join-Path $game 'src\ServerStorage\SampleData\MidtownManifestIndex.lua') -Force
Copy-Item $chunks (Join-Path $game 'src\ServerStorage\SampleData\MidtownManifestChunks') -Recurse -Force
Copy-Item $importService (Join-Path $game 'src\ServerScriptService\ImportService') -Recurse -Force
Copy-Item $shared (Join-Path $game 'src\ReplicatedStorage\Shared') -Recurse -Force

Write-Host '[3/5] Wiring Rojo to ReplicatedStorage + ServerStorage...'
$project = @'
{
  "name": "ViewersVSMe",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "$className": "ReplicatedStorage",
      "$ignoreUnknownInstances": true,
      "$path": "src/ReplicatedStorage"
    },
    "ServerStorage": {
      "$className": "ServerStorage",
      "$ignoreUnknownInstances": true,
      "$path": "src/ServerStorage"
    },
    "ServerScriptService": {
      "$className": "ServerScriptService",
      "$ignoreUnknownInstances": true,
      "$path": "src/ServerScriptService"
    },
    "StarterPlayer": {
      "$className": "StarterPlayer",
      "$ignoreUnknownInstances": true,
      "StarterPlayerScripts": {
        "$className": "StarterPlayerScripts",
        "$ignoreUnknownInstances": true,
        "$path": "src/StarterPlayer/StarterPlayerScripts"
      }
    }
  }
}
'@
Set-Content -Path (Join-Path $game 'default.project.json') -Value $project -Encoding UTF8

Write-Host '[4/5] Installing a sharded Midtown loader that bypasses the broken LoadNamedSample path...'
$bootstrap = @'
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
'@
Set-Content -Path (Join-Path $game 'src\ServerScriptService\RealMidtownBootstrap.server.lua') -Value $bootstrap -Encoding UTF8

Write-Host '[5/5] Saving the imported map files to GitHub...'
Set-Location $game
git add default.project.json src/ReplicatedStorage src/ServerStorage src/ServerScriptService/ImportService src/ServerScriptService/RealMidtownBootstrap.server.lua

$pending = git diff --cached --name-only
if ($pending) {
    git commit -m "Import real Midtown Manhattan Arnis data"
    git push origin main
    if ($LASTEXITCODE -ne 0) { throw 'git push failed' }
    Write-Host ''
    Write-Host 'DONE - real Midtown data is now in ViewersVSMe and pushed to GitHub.' -ForegroundColor Green
    Write-Host 'Rojo should resync automatically. Stop Play mode before testing the new map.'
} else {
    Write-Host 'Everything is already imported. No new Git changes were needed.' -ForegroundColor Green
}
