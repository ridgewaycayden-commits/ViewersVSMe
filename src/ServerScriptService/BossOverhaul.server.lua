-- BossOverhaul.server.lua
-- VIEWERS VS ME - TITAN BOSS VISUAL OVERHAUL
-- Add-on only: watches TikTokEnemies and upgrades boss models without replacing the working zombie core.

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local enemies = workspace:WaitForChild("TikTokEnemies")
local RED = Color3.fromRGB(255,35,45)
local DARK_RED = Color3.fromRGB(105,8,14)
local BLACK = Color3.fromRGB(12,14,18)
local ARMOR = Color3.fromRGB(28,31,38)
local STEEL = Color3.fromRGB(67,72,82)

local function weldPart(model, target, name, size, offset, color, material, shape)
	if not target or not target.Parent then return nil end
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = true
	if shape then p.Shape = shape end
	p.CFrame = target.CFrame * offset
	p.Parent = model
	local w = Instance.new("WeldConstraint")
	w.Part0 = target
	w.Part1 = p
	w.Parent = p
	return p
end

local function addLight(part, brightness, range, color)
	if not part then return end
	local l = Instance.new("PointLight")
	l.Brightness = brightness
	l.Range = range
	l.Color = color
	l.Shadows = true
	l.Parent = part
	return l
end

local function shockwave(root)
	if not root then return end
	local ring = Instance.new("Part")
	ring.Name = "BossSpawnShockwave"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = RED
	ring.Transparency = .2
	ring.Size = Vector3.new(.18,4,4)
	ring.CFrame = CFrame.new(root.Position - Vector3.new(0,2.7,0)) * CFrame.Angles(0,0,math.rad(90))
	ring.Parent = workspace
	TweenService:Create(ring,TweenInfo.new(.85,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{
		Size = Vector3.new(.12,34,34),
		Transparency = 1
	}):Play()
	Debris:AddItem(ring,1)
end

local function addBossArmor(model)
	if model:GetAttribute("TitanBossStyled") then return end
	if not model:GetAttribute("Boss") then return end
	model:SetAttribute("TitanBossStyled",true)

	local head = model:FindFirstChild("Head")
	local upper = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	local lower = model:FindFirstChild("LowerTorso") or upper
	local lUpperArm = model:FindFirstChild("LeftUpperArm") or model:FindFirstChild("Left Arm")
	local rUpperArm = model:FindFirstChild("RightUpperArm") or model:FindFirstChild("Right Arm")
	local lLowerArm = model:FindFirstChild("LeftLowerArm") or lUpperArm
	local rLowerArm = model:FindFirstChild("RightLowerArm") or rUpperArm
	local lUpperLeg = model:FindFirstChild("LeftUpperLeg") or model:FindFirstChild("Left Leg")
	local rUpperLeg = model:FindFirstChild("RightUpperLeg") or model:FindFirstChild("Right Leg")
	local root = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not head or not upper or not root or not hum then return end

	-- Heavier silhouette.
	local chest = weldPart(model,upper,"TitanChest",Vector3.new(3.25,2.75,1.25),CFrame.new(0,.05,-.18),BLACK,Enum.Material.Slate)
	weldPart(model,upper,"TitanChestPlate",Vector3.new(2.75,1.45,.30),CFrame.new(0,.18,-.83),ARMOR,Enum.Material.DiamondPlate)
	local core = weldPart(model,upper,"TitanCore",Vector3.new(.72,.72,.22),CFrame.new(0,.08,-1.02),RED,Enum.Material.Neon)
	addLight(core,4.5,18,RED)

	-- Shoulder slabs inspired by the huge armored reference silhouette.
	local ls = weldPart(model,lUpperArm,"LeftTitanShoulder",Vector3.new(2.15,1.55,1.95),CFrame.new(-.42,.28,.03)*CFrame.Angles(0,0,math.rad(-12)),ARMOR,Enum.Material.DiamondPlate)
	local rs = weldPart(model,rUpperArm,"RightTitanShoulder",Vector3.new(2.15,1.55,1.95),CFrame.new(.42,.28,.03)*CFrame.Angles(0,0,math.rad(12)),ARMOR,Enum.Material.DiamondPlate)
	for _,shoulder in ipairs({ls,rs}) do
		if shoulder then
			weldPart(model,shoulder,"ShoulderGlow",Vector3.new(1.65,.10,1.35),CFrame.new(0,.74,-.16),RED,Enum.Material.Neon)
		end
	end

	-- Giant forearm gauntlets.
	weldPart(model,lLowerArm,"LeftGauntlet",Vector3.new(1.50,2.0,1.45),CFrame.new(0,-.10,0),STEEL,Enum.Material.DiamondPlate)
	weldPart(model,rLowerArm,"RightGauntlet",Vector3.new(1.50,2.0,1.45),CFrame.new(0,-.10,0),STEEL,Enum.Material.DiamondPlate)

	-- Head becomes a glowing mask instead of a normal zombie face.
	local mask = weldPart(model,head,"TitanMask",Vector3.new(1.35,1.35,.32),CFrame.new(0,.02,-.62),DARK_RED,Enum.Material.Metal)
	local eyeL = weldPart(model,head,"TitanEyeL",Vector3.new(.28,.18,.08),CFrame.new(-.29,.18,-.82),RED,Enum.Material.Neon)
	local eyeR = weldPart(model,head,"TitanEyeR",Vector3.new(.28,.18,.08),CFrame.new(.29,.18,-.82),RED,Enum.Material.Neon)
	addLight(mask,1.4,9,RED)
	addLight(eyeL,2.4,9,RED)

	-- Jagged glowing teeth / mouth grille.
	for i=-2,2 do
		weldPart(model,head,"TitanTooth"..i,Vector3.new(.12,.30,.09),CFrame.new(i*.18,-.22,-.83)*CFrame.Angles(0,0,math.rad(i%2==0 and 12 or -12)),RED,Enum.Material.Neon)
	end

	-- Back/neck armor and spikes.
	weldPart(model,upper,"TitanBack",Vector3.new(2.7,2.2,.55),CFrame.new(0,.18,.78),ARMOR,Enum.Material.DiamondPlate)
	for _,x in ipairs({-1.0,-.5,0,.5,1.0}) do
		weldPart(model,upper,"TitanSpine",Vector3.new(.20,.65,.20),CFrame.new(x,1.42,.40)*CFrame.Angles(math.rad(18),0,math.rad(x*12)),RED,Enum.Material.Neon)
	end

	-- Leg armor to make him feel much denser.
	weldPart(model,lUpperLeg,"LeftThighArmor",Vector3.new(1.38,1.95,1.35),CFrame.new(0,0,0),ARMOR,Enum.Material.DiamondPlate)
	weldPart(model,rUpperLeg,"RightThighArmor",Vector3.new(1.38,1.95,1.35),CFrame.new(0,0,0),ARMOR,Enum.Material.DiamondPlate)

	-- Red corruption veins across the chest and limbs.
	for i=-2,2 do
		weldPart(model,upper,"ChestVein"..i,Vector3.new(.06,.11,1.05),CFrame.new(i*.43,-.38,-.88)*CFrame.Angles(0,math.rad(i*7),math.rad(38+i*6)),RED,Enum.Material.Neon)
	end
	if lUpperArm then weldPart(model,lUpperArm,"LeftArmVein",Vector3.new(.10,.10,1.20),CFrame.new(0,0,-.72)*CFrame.Angles(0,0,math.rad(22)),RED,Enum.Material.Neon) end
	if rUpperArm then weldPart(model,rUpperArm,"RightArmVein",Vector3.new(.10,.10,1.20),CFrame.new(0,0,-.72)*CFrame.Angles(0,0,math.rad(-22)),RED,Enum.Material.Neon) end

	-- Aura / smoke.
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "TitanAura"
	aura.Texture = "rbxasset://textures/particles/smoke_main.dds"
	aura.Color = ColorSequence.new(Color3.fromRGB(70,0,5),RED)
	aura.LightEmission = .65
	aura.Rate = 18
	aura.Lifetime = NumberRange.new(.45,1.0)
	aura.Speed = NumberRange.new(.4,1.6)
	aura.Rotation = NumberRange.new(0,360)
	aura.RotSpeed = NumberRange.new(-75,75)
	aura.SpreadAngle = Vector2.new(180,180)
	aura.Size = NumberSequence.new({NumberSequenceKeypoint.new(0,.35),NumberSequenceKeypoint.new(1,1.6)})
	aura.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,.25),NumberSequenceKeypoint.new(1,1)})
	aura.Parent = root

	-- Health + physical presence boost without changing core damage logic.
	hum.MaxHealth = math.max(hum.MaxHealth,1400)
	hum.Health = hum.MaxHealth

	shockwave(root)

	-- Pulse core + armor glows while alive.
	task.spawn(function()
		local pulseParts={core,eyeL,eyeR}
		while model.Parent and hum.Health>0 do
			for _,p in ipairs(pulseParts) do
				if p and p.Parent then TweenService:Create(p,TweenInfo.new(.35),{Color=Color3.fromRGB(255,110,90)}):Play() end
			end
			task.wait(.35)
			for _,p in ipairs(pulseParts) do
				if p and p.Parent then TweenService:Create(p,TweenInfo.new(.45),{Color=RED}):Play() end
			end
			task.wait(.45)
		end
	end)
end

local function consider(model)
	if not model:IsA("Model") then return end
	task.defer(function()
		for _=1,20 do
			if model:GetAttribute("Boss") and model:FindFirstChild("HumanoidRootPart") and model:FindFirstChildOfClass("Humanoid") then
				addBossArmor(model)
				return
			end
			task.wait(.1)
		end
	end)
end

for _,m in ipairs(enemies:GetChildren()) do consider(m) end
enemies.ChildAdded:Connect(consider)

print("TITAN BOSS OVERHAUL READY - armor, red core, mask, aura, and cinematic spawn FX enabled.")