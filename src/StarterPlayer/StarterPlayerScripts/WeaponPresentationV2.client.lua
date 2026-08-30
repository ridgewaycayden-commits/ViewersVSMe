-- WeaponPresentationV2.client.lua
-- VIEWERS VS ME - imported weapon presentation pass V2.1.
-- Runs after AutoCombat's render update so every Toolbox model gets a sane FPS scale/pose.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Config = {
	Rifle = {
		asset = "AK47",
		display = "AK47",
		targetLongest = 3.75,
		offset = CFrame.new(1.05,-1.02,-2.42) * CFrame.Angles(math.rad(-7),math.rad(166),math.rad(3)),
	},
	Pistol = {
		asset = "Handgun",
		display = "HANDGUN",
		targetLongest = 1.75,
		offset = CFrame.new(.82,-.82,-1.72) * CFrame.Angles(math.rad(-5),math.rad(170),math.rad(2)),
	},
	Sword = {
		asset = "Knife",
		display = "KNIFE",
		targetLongest = 1.95,
		offset = CFrame.new(.92,-.90,-1.58) * CFrame.Angles(math.rad(-17),math.rad(170),math.rad(13)),
	},
	Minigun = {
		asset = "Minigun",
		display = "MINIGUN",
		-- This Toolbox minigun has a much larger/stranger source bounding box than the AK.
		-- Keep it lower-right, closer, and rotate it independently so the barrels point forward.
		targetLongest = 3.65,
		offset = CFrame.new(1.38,-1.22,-2.18) * CFrame.Angles(math.rad(-4),math.rad(82),math.rad(-2)),
	},
	Shotgun = {
		asset = "RocketLauncher",
		-- Logical combat name stays Shotgun for server compatibility, but visually this asset is an RPG.
		display = "ROCKET LAUNCHER",
		-- The imported RPG's long axis is 90 degrees off the AK-style assets, so correct it here.
		targetLongest = 3.20,
		offset = CFrame.new(1.30,-1.10,-2.28) * CFrame.Angles(math.rad(-7),math.rad(78),math.rad(-3)),
	},
	SMG = {
		asset = "HyperlaserGun",
		display = "HYPERLASER",
		targetLongest = 2.65,
		offset = CFrame.new(.96,-.92,-2.22) * CFrame.Angles(math.rad(-5),math.rad(169),math.rad(2)),
	},
}

local activeModel
local normalizedModel
local bobClock = 0
local kick = 0
local lastAmmo = tonumber(player:GetAttribute("CurrentAmmo")) or 0

local function currentConfig()
	return Config[tostring(player:GetAttribute("CurrentWeapon") or "Rifle")] or Config.Rifle
end

local correctingLabel = false
local function syncDisplayLabel()
	if correctingLabel then return end
	local cfg = currentConfig()
	if player:GetAttribute("CurrentWeaponAsset") ~= cfg.display then
		correctingLabel = true
		player:SetAttribute("CurrentWeaponAsset",cfg.display)
		correctingLabel = false
	end
end

player:GetAttributeChangedSignal("CurrentWeapon"):Connect(function()
	normalizedModel = nil
	syncDisplayLabel()
end)
player:GetAttributeChangedSignal("CurrentWeaponAsset"):Connect(syncDisplayLabel)
player:GetAttributeChangedSignal("CurrentAmmo"):Connect(function()
	local now = tonumber(player:GetAttribute("CurrentAmmo")) or 0
	if now < lastAmmo then kick = math.min(.11,kick + .045) end
	lastAmmo = now
end)

local function findViewModel()
	local wanted = "FPSViewModel_" .. currentConfig().asset
	local m = camera:FindFirstChild(wanted)
	if m and m:IsA("Model") then return m end
	for _,v in ipairs(camera:GetChildren()) do
		if v:IsA("Model") and string.sub(v.Name,1,13) == "FPSViewModel_" then return v end
	end
end

local function normalize(m,cfg)
	local ok,_,size = pcall(function() return m:GetBoundingBox() end)
	if not ok or not size then return end
	local longest = math.max(size.X,size.Y,size.Z)
	if longest <= .01 then return end
	local currentScale = 1
	pcall(function() currentScale = m:GetScale() end)
	local desiredScale = math.clamp(currentScale * (cfg.targetLongest / longest),.03,8)
	pcall(function() m:ScaleTo(desiredScale) end)
	normalizedModel = m
end

RunService:BindToRenderStep("ViewersVsMeWeaponPresentation",Enum.RenderPriority.Camera.Value + 80,function(dt)
	camera = workspace.CurrentCamera or camera
	if not camera then return end
	local cfg = currentConfig()
	syncDisplayLabel()

	local m = findViewModel()
	if not m then activeModel=nil;normalizedModel=nil;return end
	if m ~= activeModel then
		activeModel=m
		normalizedModel=nil
	end
	if normalizedModel ~= m then normalize(m,cfg) end

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local moving = hum and hum.MoveDirection.Magnitude > .1
	bobClock += dt * (moving and 7 or 2)
	kick *= math.max(0,1-dt*12)

	local moveAmt = moving and 1 or .15
	local bob = CFrame.new(
		math.sin(bobClock)*.012*moveAmt,
		math.abs(math.cos(bobClock*2))*.008*moveAmt,
		0
	) * CFrame.Angles(0,0,math.rad(math.sin(bobClock)*.35*moveAmt))
	local recoil = CFrame.new(0,0,kick*1.4) * CFrame.Angles(math.rad(-kick*45),math.rad(kick*5),0)
	m:PivotTo(camera.CFrame * cfg.offset * bob * recoil)
end)

syncDisplayLabel()
print("WEAPON PRESENTATION V2.1 READY - RPG axis fixed + minigun FPS pose corrected")
