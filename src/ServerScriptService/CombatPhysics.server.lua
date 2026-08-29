-- CombatPhysics.server.lua
-- VIEWERS VS ME - COMBAT PHYSICS V1
-- Add-on: zombie hit reactions/ragdolls + Titan boss slam/charge physics.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local enemies = workspace:WaitForChild("TikTokEnemies")
local rng = Random.new()

local function hostCharacter()
	local p = Players:GetPlayers()[1]
	return p and p.Character
end

local function hostRootHum()
	local c = hostCharacter()
	return c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
end

local function flashHit(model, boss)
	local h = Instance.new("Highlight")
	h.Name = "DamageFlash"
	h.FillColor = boss and Color3.fromRGB(255,55,45) or Color3.fromRGB(255,105,75)
	h.OutlineColor = Color3.new(1,1,1)
	h.FillTransparency = .45
	h.OutlineTransparency = .35
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = model
	TweenService:Create(h,TweenInfo.new(.12),{FillTransparency=1,OutlineTransparency=1}):Play()
	Debris:AddItem(h,.16)
end

local function bloodBurst(model)
	local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("UpperTorso")
	if not root then return end
	local a = Instance.new("Attachment")
	a.Parent = root
	local p = Instance.new("ParticleEmitter")
	p.Rate = 0
	p.Lifetime = NumberRange.new(.18,.38)
	p.Speed = NumberRange.new(5,11)
	p.SpreadAngle = Vector2.new(120,120)
	p.Drag = 5
	p.Color = ColorSequence.new(Color3.fromRGB(105,8,10),Color3.fromRGB(45,2,4))
	p.Size = NumberSequence.new({NumberSequenceKeypoint.new(0,.16),NumberSequenceKeypoint.new(1,0)})
	p.Parent = a
	p:Emit(rng:NextInteger(6,11))
	Debris:AddItem(a,.7)
end

local function pushFromPlayer(model, strength)
	local er = model:FindFirstChild("HumanoidRootPart")
	local pr = select(1,hostRootHum())
	if not er or not pr then return end
	local delta = Vector3.new(er.Position.X-pr.Position.X,0,er.Position.Z-pr.Position.Z)
	if delta.Magnitude < .1 then delta = Vector3.new(1,0,0) end
	er:ApplyImpulse((delta.Unit*strength + Vector3.new(0,strength*.18,0))*er.AssemblyMass)
end

local function ragdoll(model)
	if model:GetAttribute("PhysicsRagdolled") then return end
	model:SetAttribute("PhysicsRagdolled",true)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.AutoRotate = false
		hum.PlatformStand = true
	end
	for _,motor in ipairs(model:GetDescendants()) do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagdollA0"
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RagdollA1"
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 48
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -28
			socket.TwistUpperAngle = 28
			socket.Parent = motor.Parent
			motor.Enabled = false
		end
	end
	for _,p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = p.Name ~= "HumanoidRootPart"
			p.Massless = false
		end
	end
	pushFromPlayer(model, model:GetAttribute("Boss") and 18 or 32)
end

local function shockwave(pos, radius, color)
	local ring = Instance.new("Part")
	ring.Name = "Shockwave"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = .18
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(.18,2,2)
	ring.CFrame = CFrame.new(pos + Vector3.new(0,.18,0))*CFrame.Angles(0,0,math.rad(90))
	ring.Parent = workspace
	TweenService:Create(ring,TweenInfo.new(.42,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=Vector3.new(.18,radius*2,radius*2),Transparency=1}):Play()
	Debris:AddItem(ring,.48)
end

local function bossSlam(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	local pr,ph = hostRootHum()
	if not root or not hum or not pr or not ph or ph.Health<=0 then return end
	model:SetAttribute("BossAttacking",true)
	local oldSpeed = hum.WalkSpeed
	hum.WalkSpeed = 0
	local warn = Instance.new("PointLight")
	warn.Color = Color3.fromRGB(255,25,35)
	warn.Brightness = 8
	warn.Range = 28
	warn.Parent = root
	TweenService:Create(root,TweenInfo.new(.26,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{CFrame=root.CFrame*CFrame.new(0,1.15,0)}):Play()
	task.wait(.34)
	root:ApplyImpulse(Vector3.new(0,-95,0)*root.AssemblyMass)
	task.wait(.16)
	shockwave(root.Position,16,Color3.fromRGB(255,35,45))
	local d = (Vector3.new(pr.Position.X,root.Position.Y,pr.Position.Z)-root.Position).Magnitude
	if d <= 16 then
		ph:TakeDamage(18)
		local away = Vector3.new(pr.Position.X-root.Position.X,0,pr.Position.Z-root.Position.Z)
		if away.Magnitude < .1 then away=Vector3.new(1,0,0) end
		pr:ApplyImpulse((away.Unit*55 + Vector3.new(0,28,0))*pr.AssemblyMass)
	end
	warn:Destroy()
	hum.WalkSpeed = oldSpeed
	model:SetAttribute("BossAttacking",false)
end

local function bossCharge(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	local pr,ph = hostRootHum()
	if not root or not hum or not pr or not ph or ph.Health<=0 then return end
	model:SetAttribute("BossAttacking",true)
	local old = hum.WalkSpeed
	hum.WalkSpeed = 0
	local dir = Vector3.new(pr.Position.X-root.Position.X,0,pr.Position.Z-root.Position.Z)
	if dir.Magnitude < 1 then model:SetAttribute("BossAttacking",false);hum.WalkSpeed=old;return end
	local glow = Instance.new("Highlight")
	glow.FillColor=Color3.fromRGB(255,20,30);glow.OutlineColor=Color3.fromRGB(255,110,90);glow.FillTransparency=.58;glow.Parent=model
	task.wait(.42)
	root:ApplyImpulse((dir.Unit*105 + Vector3.new(0,7,0))*root.AssemblyMass)
	local start=os.clock()
	while model.Parent and os.clock()-start<.65 do
		local dist=(pr.Position-root.Position).Magnitude
		if dist<6 then
			ph:TakeDamage(14)
			pr:ApplyImpulse((dir.Unit*50+Vector3.new(0,18,0))*pr.AssemblyMass)
			break
		end
		RunService.Heartbeat:Wait()
	end
	glow:Destroy()
	hum.WalkSpeed=old
	model:SetAttribute("BossAttacking",false)
end

local function attach(model)
	if model:GetAttribute("CombatPhysicsAttached") then return end
	model:SetAttribute("CombatPhysicsAttached",true)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local boss = model:GetAttribute("Boss") == true
	local last = hum.Health
	local staggerCooldown = 0

	hum.HealthChanged:Connect(function(newHealth)
		if newHealth < last and newHealth > 0 then
			flashHit(model,boss)
			bloodBurst(model)
			if os.clock()>staggerCooldown then
				staggerCooldown=os.clock()+(boss and .7 or .28)
				pushFromPlayer(model,boss and 5 or 12)
				if not boss then
					local old=hum.WalkSpeed
					hum.WalkSpeed=math.max(0,old*.25)
					task.delay(.12,function() if hum.Parent and hum.Health>0 then hum.WalkSpeed=old end end)
				end
			end
		end
		last=newHealth
	end)

	hum.Died:Connect(function()
		bloodBurst(model)
		ragdoll(model)
	end)

	if boss then
		task.spawn(function()
			task.wait(2.5)
			while model.Parent and hum.Health>0 do
				local pr,ph=hostRootHum()
				if pr and ph and ph.Health>0 and not model:GetAttribute("BossAttacking") then
					local d=(pr.Position-(model:FindFirstChild("HumanoidRootPart") and model.HumanoidRootPart.Position or pr.Position)).Magnitude
					if d<17 and rng:NextNumber()<.62 then bossSlam(model) elseif d<42 then bossCharge(model) end
				end
				task.wait(rng:NextNumber(4.3,6.8))
			end
		end)
	end
end

for _,m in ipairs(enemies:GetChildren()) do task.defer(attach,m) end
enemies.ChildAdded:Connect(function(m) task.wait(.15);attach(m) end)

print("COMBAT PHYSICS V1 READY - stagger, ragdoll, boss slam and charge enabled.")