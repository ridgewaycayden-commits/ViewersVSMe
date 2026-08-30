-- CityMapSetup.server.lua
-- Adapts the imported Workspace "City Map" for ViewersVSMe.
-- Creates a safe player spawn over an open area and applies brighter daytime lighting.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local MAP_NAME = "City Map"
local SPAWN_NAME = "ViewersVSMESpawn"

local function findCityMap()
	local map = workspace:FindFirstChild(MAP_NAME)
	if map then return map end

	for _ = 1, 100 do
		map = workspace:FindFirstChild(MAP_NAME)
		if map then return map end
		task.wait(0.1)
	end

	return nil
end

local function getMapBounds(map)
	if map:IsA("Model") then
		local cf, size = map:GetBoundingBox()
		return cf, size
	elseif map:IsA("BasePart") then
		return map.CFrame, map.Size
	end

	local parts = {}
	for _, inst in ipairs(map:GetDescendants()) do
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
		end
	end

	if #parts == 0 then
		return CFrame.new(0, 0, 0), Vector3.new(200, 50, 200)
	end

	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(parts) do
		local pos = p.Position
		local half = p.Size * 0.5
		minV = Vector3.new(math.min(minV.X, pos.X - half.X), math.min(minV.Y, pos.Y - half.Y), math.min(minV.Z, pos.Z - half.Z))
		maxV = Vector3.new(math.max(maxV.X, pos.X + half.X), math.max(maxV.Y, pos.Y + half.Y), math.max(maxV.Z, pos.Z + half.Z))
	end

	local center = (minV + maxV) * 0.5
	return CFrame.new(center), maxV - minV
end

local function raycastGround(origin, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	params.IgnoreWater = false
	return workspace:Raycast(origin, Vector3.new(0, -1000, 0), params)
end

local function horizontalClearance(position, radius)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}

	local hits = workspace:GetPartBoundsInBox(CFrame.new(position + Vector3.new(0, 4, 0)), Vector3.new(radius * 2, 8, radius * 2), params)
	local blockers = 0
	for _, part in ipairs(hits) do
		if part.CanCollide and part.Transparency < 0.95 and part.Name ~= SPAWN_NAME then
			blockers += 1
		end
	end
	return blockers
end

local function chooseOpenSpawn(map)
	local boundsCF, boundsSize = getMapBounds(map)
	local center = boundsCF.Position
	local halfX = math.max(20, boundsSize.X * 0.42)
	local halfZ = math.max(20, boundsSize.Z * 0.42)
	local topY = center.Y + math.max(100, boundsSize.Y + 100)

	local bestPos = nil
	local bestScore = math.huge

	-- Search the imported map in a grid and prefer broad, low-obstruction ground.
	for ix = -5, 5 do
		for iz = -5, 5 do
			local x = center.X + (ix / 5) * halfX
			local z = center.Z + (iz / 5) * halfZ
			local hit = raycastGround(Vector3.new(x, topY, z))
			if hit and hit.Instance and hit.Instance:IsDescendantOf(map) then
				local normal = hit.Normal
				if normal.Y > 0.82 then
					local spawnPos = hit.Position + Vector3.new(0, 4, 0)
					local blockers = horizontalClearance(spawnPos, 7)
					local centerBias = (Vector2.new(x - center.X, z - center.Z).Magnitude / math.max(halfX, halfZ)) * 0.35
					local score = blockers + centerBias
					if score < bestScore then
						bestScore = score
						bestPos = spawnPos
					end
				end
			end
		end
	end

	if bestPos then
		return bestPos
	end

	-- Fallback: map center, lifted above the highest reasonable surface.
	local fallbackHit = raycastGround(Vector3.new(center.X, topY, center.Z))
	if fallbackHit then
		return fallbackHit.Position + Vector3.new(0, 4, 0)
	end

	return center + Vector3.new(0, math.max(10, boundsSize.Y * 0.5 + 8), 0)
end

local function makeSpawn(position)
	local old = workspace:FindFirstChild(SPAWN_NAME)
	if old then old:Destroy() end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = SPAWN_NAME
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = CFrame.new(position)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0
	spawn.Parent = workspace

	return spawn
end

local function teleportCharacter(character, spawn)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then return end
	task.wait(0.15)
	character:PivotTo(spawn.CFrame + Vector3.new(0, 3, 0))
end

local function setupLighting()
	Lighting.ClockTime = 13.5
	Lighting.Brightness = 3
	Lighting.ExposureCompensation = 0.25
	Lighting.Ambient = Color3.fromRGB(155, 155, 165)
	Lighting.OutdoorAmbient = Color3.fromRGB(190, 190, 200)
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35
	Lighting.EnvironmentDiffuseScale = 0.8
	Lighting.EnvironmentSpecularScale = 0.4

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = math.min(atmosphere.Density, 0.2)
		atmosphere.Haze = math.min(atmosphere.Haze, 0.75)
		atmosphere.Glare = 0
	end

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Intensity = math.min(bloom.Intensity, 0.12)
		bloom.Threshold = math.max(bloom.Threshold, 1.5)
	end

	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if cc then
		cc.Brightness = math.max(cc.Brightness, 0.03)
		cc.Contrast = math.min(cc.Contrast, 0.08)
		cc.Saturation = math.max(cc.Saturation, -0.05)
	end
end

local map = findCityMap()
if not map then
	warn("[CITY MAP SETUP] Workspace 'City Map' was not found. Insert the map, then restart Play mode.")
	return
end

setupLighting()

local spawnPos = chooseOpenSpawn(map)
local spawn = makeSpawn(spawnPos)

local function hookPlayer(player)
	player.CharacterAdded:Connect(function(character)
		teleportCharacter(character, spawn)
	end)
	if player.Character then
		task.spawn(teleportCharacter, player.Character, spawn)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	hookPlayer(player)
end
Players.PlayerAdded:Connect(hookPlayer)

print("[CITY MAP SETUP] READY - open spawn selected + brighter daytime lighting")
