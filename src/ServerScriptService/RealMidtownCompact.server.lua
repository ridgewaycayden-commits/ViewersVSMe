-- RealMidtownCompact.server.lua
-- Lightweight real-Midtown renderer built from the user's Arnis/OSM export.
-- The giant emitted shard set stays on disk and is never materialized.

local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local DATA_TIMEOUT = 20
local ROOT_NAME = "RealMidtown"
local SPAWN_CLEAR_RADIUS = 48

local function part(parent, name, size, cf, color, material, collide)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size
    p.CFrame = cf
    p.Color = color
    p.Material = material
    p.Anchored = true
    p.CanCollide = collide ~= false
    p.CanTouch = false
    p.CanQuery = collide ~= false
    p.CastShadow = true
    p.Parent = parent
    return p
end

local function chooseOpenSpawn(roads)
    local best, bestScore
    for _, r in ipairs(roads or {}) do
        local x1,z1,x2,z2,y,width = r[1],r[2],r[3],r[4],r[5],r[6]
        local dx, dz = x2-x1, z2-z1
        local len = math.sqrt(dx*dx + dz*dz)
        if len >= 30 then
            local mx, mz = (x1+x2)*0.5, (z1+z2)*0.5
            local centerPenalty = math.sqrt(mx*mx + mz*mz) * 0.06
            local score = (width or 8) * 4 + math.min(len, 180) - centerPenalty
            if not bestScore or score > bestScore then
                bestScore = score
                best = {
                    x = mx,
                    z = mz,
                    y = (y or 0) + 1,
                    yaw = math.atan2(-dx, -dz),
                    width = width or 10,
                    length = len,
                }
            end
        end
    end
    return best or {x=0,z=0,y=1,yaw=0,width=12,length=80}
end

local function teleportCharacter(character, spawnCF)
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        rootPart = character and character:WaitForChild("HumanoidRootPart", 8)
    end
    if rootPart then
        character:PivotTo(spawnCF * CFrame.new(0, 4, 0))
    end
end

local function render()
    local dataModule = ServerStorage:WaitForChild("RealMidtownCompact", DATA_TIMEOUT)
    if not dataModule then
        warn("[REAL MIDTOWN COMPACT] Waiting for generated RealMidtownCompact.lua. Run BUILD_REAL_MIDTOWN_COMPACT.bat first.")
        return
    end

    local ok, data = pcall(require, dataModule)
    if not ok or type(data) ~= "table" then
        warn("[REAL MIDTOWN COMPACT] Could not require data module: " .. tostring(data))
        return
    end

    local old = workspace:FindFirstChild(ROOT_NAME)
    if old then old:Destroy() end
    local fake = workspace:FindFirstChild("ManhattanMidtownV10")
    if fake then fake:Destroy() end

    local root = Instance.new("Folder")
    root.Name = ROOT_NAME
    root.Parent = workspace

    local roadsFolder = Instance.new("Folder")
    roadsFolder.Name = "Roads"
    roadsFolder.Parent = root

    local buildingsFolder = Instance.new("Folder")
    buildingsFolder.Name = "Buildings"
    buildingsFolder.Parent = root

    local spawn = chooseOpenSpawn(data.roads)
    local spawnCF = CFrame.new(spawn.x, spawn.y + 0.35, spawn.z) * CFrame.Angles(0, spawn.yaw, 0)

    Lighting.ClockTime = 21.25
    Lighting.Brightness = 3.2
    Lighting.ExposureCompensation = 0.55
    Lighting.Ambient = Color3.fromRGB(70, 75, 88)
    Lighting.OutdoorAmbient = Color3.fromRGB(88, 94, 110)

    for i, r in ipairs(data.roads or {}) do
        local x1,z1,x2,z2,y,width = r[1],r[2],r[3],r[4],r[5],r[6]
        local a = Vector3.new(x1, y + 0.15, z1)
        local b = Vector3.new(x2, y + 0.15, z2)
        local delta = b-a
        local len = delta.Magnitude
        if len > 0.5 then
            local mid = (a+b)*0.5
            local cf = CFrame.lookAt(mid, b)
            part(roadsFolder, "Road_"..i, Vector3.new(width, 0.3, len), cf, Color3.fromRGB(28,29,32), Enum.Material.Asphalt, true)
            if width >= 12 then
                local stripe = part(roadsFolder, "Lane_"..i, Vector3.new(0.22, 0.04, len*0.92), cf * CFrame.new(0,0.18,0), Color3.fromRGB(220,196,82), Enum.Material.SmoothPlastic, false)
                stripe.CastShadow = false
            end
        end
        if i % 200 == 0 then task.wait() end
    end

    -- Keep a generous open square around spawn so the player never starts boxed in.
    local plaza = part(root, "SpawnPlaza", Vector3.new(SPAWN_CLEAR_RADIUS*2, 0.4, SPAWN_CLEAR_RADIUS*2), CFrame.new(spawn.x, spawn.y, spawn.z), Color3.fromRGB(42,43,47), Enum.Material.Asphalt, true)
    plaza.CastShadow = false

    for i, b in ipairs(data.buildings or {}) do
        local x,z,w,d,h,baseY,angle = b[1],b[2],b[3],b[4],b[5],b[6],b[7]
        local dx, dz = x-spawn.x, z-spawn.z
        local clearX = SPAWN_CLEAR_RADIUS + w*0.5
        local clearZ = SPAWN_CLEAR_RADIUS + d*0.5
        if math.abs(dx) > clearX or math.abs(dz) > clearZ then
            local c = Color3.fromRGB(b[8] or 115, b[9] or 118, b[10] or 124)
            local cf = CFrame.new(x, baseY + h/2, z) * CFrame.Angles(0, math.rad(-angle), 0)
            part(buildingsFolder, "Building_"..i, Vector3.new(math.max(2,w), h, math.max(2,d)), cf, c, Enum.Material.Concrete, true)

            if h >= 28 and w >= 8 and d >= 8 then
                local bands = math.min(8, math.floor(h/18))
                for band = 1, bands do
                    local yy = -h/2 + (band/(bands+1))*h
                    local front = part(buildingsFolder, "WindowBand", Vector3.new(w*0.84, 1.5, 0.12), cf * CFrame.new(0,yy,-d/2-0.07), Color3.fromRGB(30,39,47), Enum.Material.Glass, false)
                    front.Transparency = 0.18
                    front.CastShadow = false
                end
                local cap = part(buildingsFolder, "RoofCap", Vector3.new(w*0.9, 1.2, d*0.9), cf * CFrame.new(0,h/2+0.6,0), c:Lerp(Color3.new(0,0,0),0.18), Enum.Material.Concrete, true)
                cap.CastShadow = true
            end
        end
        if i % 100 == 0 then task.wait() end
    end

    local oldSpawn = workspace:FindFirstChild("RealMidtownSpawn")
    if oldSpawn then oldSpawn:Destroy() end
    local spawnLocation = Instance.new("SpawnLocation")
    spawnLocation.Name = "RealMidtownSpawn"
    spawnLocation.Size = Vector3.new(12, 0.5, 12)
    spawnLocation.CFrame = spawnCF
    spawnLocation.Anchored = true
    spawnLocation.CanCollide = true
    spawnLocation.Transparency = 1
    spawnLocation.Neutral = true
    spawnLocation.Parent = workspace

    local function hookPlayer(player)
        player.CharacterAdded:Connect(function(character)
            task.wait(0.25)
            teleportCharacter(character, spawnCF)
        end)
        if player.Character then
            teleportCharacter(player.Character, spawnCF)
        end
    end

    for _, player in ipairs(Players:GetPlayers()) do
        hookPlayer(player)
    end
    Players.PlayerAdded:Connect(hookPlayer)

    print(("[REAL MIDTOWN COMPACT] READY - %d real buildings, %d road segments | open spawn at %.0f, %.0f"):format(#(data.buildings or {}), #(data.roads or {}), spawn.x, spawn.z))
end

task.spawn(render)
