-- AutoCombat.client.lua
-- SELF-CONTAINED V8
-- Put in StarterPlayer > StarterPlayerScripts as ONE LocalScript named AutoCombat.
-- Does NOT require GiftWeaponConfig.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local enemies = workspace:WaitForChild("TikTokEnemies")
local attackRemote = ReplicatedStorage:WaitForChild("AutoCombatAttack")

local Weapons = {
	Pistol = {damage=20,range=100,cooldown=.32,color=Color3.fromRGB(255,220,120),pellets=1,spread=.5},
	SMG = {damage=11,range=95,cooldown=.10,color=Color3.fromRGB(120,220,255),pellets=1,spread=1.3},
	Shotgun = {damage=30,range=65,cooldown=.72,color=Color3.fromRGB(255,170,90),pellets=7,spread=4.5},
	Rifle = {damage=31,range=145,cooldown=.22,color=Color3.fromRGB(130,255,150),pellets=1,spread=.35},
	Minigun = {damage=8,range=120,cooldown=.055,color=Color3.fromRGB(255,90,90),pellets=1,spread=2.0},
}

local currentWeapon = "Rifle"
local visualWeapon = nil
local lastShot = 0
local lastSword = 0
local roamGoal = nil
local roamStarted = 0
local combatGoal = nil
local combatMoveAt = 0
local jumpAt = 0

local function charParts()
	local char = player.Character
	if not char then return end
	return char, char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart"), char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
end

local function aliveEnemy(m)
	local hum = m and m:FindFirstChildOfClass("Humanoid")
	local root = m and m:FindFirstChild("HumanoidRootPart")
	return m and m.Parent and hum and root and hum.Health > 0 and m:GetAttribute("Dead") ~= true
end

local function nearest(root)
	local best,bestDistance
	for _,m in ipairs(enemies:GetChildren()) do
		if aliveEnemy(m) then
			local eroot = m:FindFirstChild("HumanoidRootPart")
			local d = (eroot.Position-root.Position).Magnitude
			if not bestDistance or d < bestDistance then best,bestDistance = m,d end
		end
	end
	return best,bestDistance
end

local function clearVisual(char)
	local old = char:FindFirstChild("AutoWeaponVisual")
	if old then old:Destroy() end
end

local function weldTo(hand,p,cf)
	p.CFrame = hand.CFrame * cf
	local w = Instance.new("WeldConstraint")
	w.Part0 = hand
	w.Part1 = p
	w.Parent = p
end

local function makeVisualPart(model,name,size,color,material,shape)
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
	p.Parent = model
	return p
end

local function addMuzzleLight(model,hand,cf,color)
	local muzzle = makeVisualPart(model,"Muzzle",Vector3.new(.16,.16,.22),color,Enum.Material.Neon)
	weldTo(hand,muzzle,cf)
	local light = Instance.new("PointLight")
	light.Brightness = .7
	light.Range = 6
	light.Color = color
	light.Parent = muzzle
	return muzzle
end

local function equip(char,hand,name)
	if not hand then return end
	if visualWeapon == name and char:FindFirstChild("AutoWeaponVisual") then return end
	visualWeapon = name
	clearVisual(char)
	local model = Instance.new("Model")
	model.Name = "AutoWeaponVisual"
	model.Parent = char
	local dark = Color3.fromRGB(25,28,34)
	local black = Color3.fromRGB(14,16,20)
	local metal = Color3.fromRGB(72,78,88)
	local accent = Color3.fromRGB(115,125,140)
	local wood = Color3.fromRGB(74,52,38)
	if name == "Sword" then
		local grip = makeVisualPart(model,"Grip",Vector3.new(.28,.95,.28),black,Enum.Material.SmoothPlastic); weldTo(hand,grip,CFrame.new(0,-.45,-.05))
		local pommel = makeVisualPart(model,"Pommel",Vector3.new(.38,.24,.38),metal,Enum.Material.Metal); weldTo(hand,pommel,CFrame.new(0,-.92,-.05))
		local guard = makeVisualPart(model,"Guard",Vector3.new(1.3,.16,.28),metal,Enum.Material.Metal); weldTo(hand,guard,CFrame.new(0,-.18,-.42))
		local blade = makeVisualPart(model,"Blade",Vector3.new(.12,.22,3.9),Color3.fromRGB(215,225,235),Enum.Material.Metal); weldTo(hand,blade,CFrame.new(0,-.18,-2.45))
		local edge = makeVisualPart(model,"Edge",Vector3.new(.035,.24,3.75),Color3.fromRGB(115,220,255),Enum.Material.Neon); weldTo(hand,edge,CFrame.new(.075,-.18,-2.45))
		return
	end
	if name == "Pistol" then
		local slide = makeVisualPart(model,"Slide",Vector3.new(.46,.36,1.55),dark,Enum.Material.Metal); weldTo(hand,slide,CFrame.new(0,-.12,-.82))
		local frame = makeVisualPart(model,"Frame",Vector3.new(.42,.34,1.10),black,Enum.Material.Metal); weldTo(hand,frame,CFrame.new(0,-.36,-.55))
		local grip = makeVisualPart(model,"Grip",Vector3.new(.38,.85,.42),Color3.fromRGB(32,32,36),Enum.Material.SmoothPlastic); weldTo(hand,grip,CFrame.new(0,-.78,-.10)*CFrame.Angles(math.rad(-12),0,0))
		local barrel = makeVisualPart(model,"Barrel",Vector3.new(.15,.15,.70),metal,Enum.Material.Metal); weldTo(hand,barrel,CFrame.new(0,-.10,-1.92))
		local sightF = makeVisualPart(model,"FrontSight",Vector3.new(.08,.14,.09),accent,Enum.Material.Metal); weldTo(hand,sightF,CFrame.new(0,.13,-1.25))
		addMuzzleLight(model,hand,CFrame.new(0,-.10,-2.28),Weapons.Pistol.color)
		return
	end
	if name == "SMG" then
		local receiver = makeVisualPart(model,"Receiver",Vector3.new(.58,.62,2.25),dark,Enum.Material.Metal); weldTo(hand,receiver,CFrame.new(0,-.15,-1.10))
		local upper = makeVisualPart(model,"Upper",Vector3.new(.48,.25,1.65),metal,Enum.Material.Metal); weldTo(hand,upper,CFrame.new(0,.25,-1.10))
		local mag = makeVisualPart(model,"Magazine",Vector3.new(.34,1.15,.48),black,Enum.Material.Metal); weldTo(hand,mag,CFrame.new(0,-.86,-.68)*CFrame.Angles(math.rad(-8),0,0))
		local grip = makeVisualPart(model,"ForeGrip",Vector3.new(.30,.82,.32),black,Enum.Material.SmoothPlastic); weldTo(hand,grip,CFrame.new(0,-.62,-1.65)*CFrame.Angles(math.rad(-8),0,0))
		local barrel = makeVisualPart(model,"Barrel",Vector3.new(.16,.16,1.30),metal,Enum.Material.Metal); weldTo(hand,barrel,CFrame.new(0,-.08,-2.85))
		local stock = makeVisualPart(model,"Stock",Vector3.new(.46,.52,1.20),black,Enum.Material.Metal); weldTo(hand,stock,CFrame.new(0,-.12,.55))
		addMuzzleLight(model,hand,CFrame.new(0,-.08,-3.52),Weapons.SMG.color)
		return
	end
	if name == "Shotgun" then
		local receiver = makeVisualPart(model,"Receiver",Vector3.new(.58,.62,1.65),dark,Enum.Material.Metal); weldTo(hand,receiver,CFrame.new(0,-.12,-.78))
		local barrel = makeVisualPart(model,"Barrel",Vector3.new(.20,.20,3.0),metal,Enum.Material.Metal); weldTo(hand,barrel,CFrame.new(0,-.04,-3.10))
		local tube = makeVisualPart(model,"Tube",Vector3.new(.18,.18,2.45),Color3.fromRGB(48,52,60),Enum.Material.Metal); weldTo(hand,tube,CFrame.new(0,-.30,-2.92))
		local pump = makeVisualPart(model,"Pump",Vector3.new(.54,.50,.95),Color3.fromRGB(88,61,42),Enum.Material.Wood); weldTo(hand,pump,CFrame.new(0,-.25,-2.15))
		local stock = makeVisualPart(model,"Stock",Vector3.new(.58,.72,1.80),wood,Enum.Material.Wood); weldTo(hand,stock,CFrame.new(0,-.18,.92))
		addMuzzleLight(model,hand,CFrame.new(0,-.04,-4.63),Weapons.Shotgun.color)
		return
	end
	if name == "Rifle" then
		local lower = makeVisualPart(model,"Lower",Vector3.new(.58,.62,1.75),dark,Enum.Material.Metal); weldTo(hand,lower,CFrame.new(0,-.12,-.72))
		local upper = makeVisualPart(model,"Upper",Vector3.new(.54,.34,2.2),metal,Enum.Material.Metal); weldTo(hand,upper,CFrame.new(0,.18,-1.08))
		local handguard = makeVisualPart(model,"Handguard",Vector3.new(.52,.50,1.75),Color3.fromRGB(40,44,52),Enum.Material.Metal); weldTo(hand,handguard,CFrame.new(0,-.02,-2.55))
		for i=-1,1 do local slot = makeVisualPart(model,"RailSlot"..i,Vector3.new(.08,.07,.32),black,Enum.Material.Metal); weldTo(hand,slot,CFrame.new(0,.30,-2.45 + i*.45)) end
		local mag = makeVisualPart(model,"Magazine",Vector3.new(.40,1.15,.52),black,Enum.Material.Metal); weldTo(hand,mag,CFrame.new(0,-.88,-.63)*CFrame.Angles(math.rad(-10),0,0))
		local grip = makeVisualPart(model,"PistolGrip",Vector3.new(.34,.86,.36),Color3.fromRGB(30,32,36),Enum.Material.SmoothPlastic); weldTo(hand,grip,CFrame.new(0,-.80,.08)*CFrame.Angles(math.rad(-12),0,0))
		local stock = makeVisualPart(model,"Stock",Vector3.new(.55,.62,1.65),black,Enum.Material.SmoothPlastic); weldTo(hand,stock,CFrame.new(0,-.10,1.28))
		local barrel = makeVisualPart(model,"Barrel",Vector3.new(.14,.14,1.75),Color3.fromRGB(82,88,98),Enum.Material.Metal); weldTo(hand,barrel,CFrame.new(0,-.02,-4.24))
		local opticBase = makeVisualPart(model,"OpticBase",Vector3.new(.42,.12,.62),black,Enum.Material.Metal); weldTo(hand,opticBase,CFrame.new(0,.43,-1.10))
		local optic = makeVisualPart(model,"Optic",Vector3.new(.44,.40,.55),Color3.fromRGB(22,25,30),Enum.Material.Metal); weldTo(hand,optic,CFrame.new(0,.63,-1.10))
		local lens = makeVisualPart(model,"Lens",Vector3.new(.25,.25,.05),Color3.fromRGB(80,210,255),Enum.Material.Neon); weldTo(hand,lens,CFrame.new(0,.63,-1.39))
		addMuzzleLight(model,hand,CFrame.new(0,-.02,-5.13),Weapons.Rifle.color)
		return
	end
	if name == "Minigun" then
		local housing = makeVisualPart(model,"Housing",Vector3.new(.92,.95,2.15),dark,Enum.Material.Metal); weldTo(hand,housing,CFrame.new(0,-.16,-1.05))
		local rear = makeVisualPart(model,"RearHousing",Vector3.new(1.05,1.05,1.05),black,Enum.Material.Metal); weldTo(hand,rear,CFrame.new(0,-.16,.40))
		local grip = makeVisualPart(model,"Grip",Vector3.new(.34,.90,.34),black,Enum.Material.SmoothPlastic); weldTo(hand,grip,CFrame.new(0,-.88,-.25))
		local offsets = {Vector3.new(.22,.22,0),Vector3.new(-.22,.22,0),Vector3.new(.22,-.22,0),Vector3.new(-.22,-.22,0),Vector3.new(0,.31,0),Vector3.new(0,-.31,0)}
		for i,o in ipairs(offsets) do local barrel = makeVisualPart(model,"Barrel"..i,Vector3.new(.12,.12,3.0),metal,Enum.Material.Metal); weldTo(hand,barrel,CFrame.new(o.X,o.Y,-3.35)) end
		local ring = makeVisualPart(model,"BarrelRing",Vector3.new(.78,.78,.20),Color3.fromRGB(55,60,68),Enum.Material.Metal,Enum.PartType.Cylinder); weldTo(hand,ring,CFrame.new(0,-.16,-4.80)*CFrame.Angles(0,0,math.rad(90)))
		addMuzzleLight(model,hand,CFrame.new(0,-.16,-5.05),Weapons.Minigun.color)
	end
end

local function tracer(a,b,color)
	local delta = b-a
	local dist = delta.Magnitude
	if dist < .05 then return end
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.Material = Enum.Material.Neon; p.Color = color; p.Size = Vector3.new(.055,.055,dist); p.CFrame = CFrame.lookAt((a+b)/2,b); p.Parent = workspace
	Debris:AddItem(p,.045)
end

local function shoot(char,root,hand,target)
	local cfg = Weapons[currentWeapon]
	if not cfg or os.clock()-lastShot < cfg.cooldown then return end
	local eroot = target:FindFirstChild("HumanoidRootPart")
	if not eroot then return end
	lastShot = os.clock(); equip(char,hand,currentWeapon)
	root.CFrame = CFrame.lookAt(root.Position,Vector3.new(eroot.Position.X,root.Position.Y,eroot.Position.Z))
	local origin = hand and hand.Position or root.Position+Vector3.new(0,1.5,0)
	for _=1,cfg.pellets do
		local aim = eroot.Position + Vector3.new((math.random()-.5)*cfg.spread,1+(math.random()-.5)*cfg.spread*.3,(math.random()-.5)*cfg.spread)
		tracer(origin,aim,cfg.color)
	end
	attackRemote:FireServer(target,currentWeapon)
end

local function sword(char,root,hand,target)
	if os.clock()-lastSword < .55 then return end
	local eroot = target:FindFirstChild("HumanoidRootPart")
	if not eroot then return end
	lastSword = os.clock(); equip(char,hand,"Sword")
	root.CFrame = CFrame.lookAt(root.Position,Vector3.new(eroot.Position.X,root.Position.Y,eroot.Position.Z))
	attackRemote:FireServer(target,"Sword")
end

local function randomRoam(root)
	local angle = math.rad(math.random(0,359)); local radius = math.random(16,38)
	return root.Position + Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
end

local function combatMove(root,target,d)
	local eroot = target:FindFirstChild("HumanoidRootPart")
	if not eroot then return root.Position end
	local flat = Vector3.new(eroot.Position.X-root.Position.X,0,eroot.Position.Z-root.Position.Z)
	if flat.Magnitude < .1 then return root.Position end
	local dir = flat.Unit; local side = Vector3.new(-dir.Z,0,dir.X)
	if d > 38 then return root.Position + dir*10 + side*math.random(-3,3)
	elseif d < 8 then return root.Position - dir*7 + side*math.random(-6,6)
	elseif math.random() < .55 then return root.Position + side*math.random(-10,10)
	else return root.Position - dir*math.random(2,5) + side*math.random(-6,6) end
end

local rayParams = RaycastParams.new(); rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function obstacleFree(root, goal, char)
	local delta = goal - root.Position; local flat = Vector3.new(delta.X,0,delta.Z)
	if flat.Magnitude < 1 then return true end
	rayParams.FilterDescendantsInstances = {char,enemies}
	local hit = workspace:Raycast(root.Position+Vector3.new(0,2,0),flat.Unit*math.min(flat.Magnitude,10),rayParams)
	return hit == nil, hit
end

local function steerAroundObstacle(root, goal, char)
	local clear = obstacleFree(root,goal,char)
	if clear then return goal end
	local delta = goal-root.Position; local flat = Vector3.new(delta.X,0,delta.Z)
	if flat.Magnitude < .1 then return goal end
	local forward = flat.Unit; local left = Vector3.new(-forward.Z,0,forward.X); local right = -left
	local candidates = {root.Position+left*10+forward*6,root.Position+right*10+forward*6,root.Position+left*14,root.Position+right*14,root.Position-forward*5+left*9,root.Position-forward*5+right*9}
	for _,candidate in ipairs(candidates) do if obstacleFree(root,candidate,char) then return candidate end end
	local angle = math.rad(math.random(0,359)); return root.Position+Vector3.new(math.cos(angle)*12,0,math.sin(angle)*12)
end

local lastPos=nil; local stuckTimer=0; local stuckCheckAt=0
local function handleStuck(hum,root)
	if os.clock() < stuckCheckAt then return end
	stuckCheckAt = os.clock()+.15
	if not lastPos then lastPos=root.Position return end
	local moved=(root.Position-lastPos).Magnitude; lastPos=root.Position
	if moved < .12 then stuckTimer += .15 else stuckTimer=0 end
	if stuckTimer > .9 then
		stuckTimer=0
		if hum.FloorMaterial ~= Enum.Material.Air then hum.Jump=true end
		roamGoal=randomRoam(root); roamStarted=os.clock(); combatGoal=nil
	end
end

RunService.Heartbeat:Connect(function()
	local char,hum,root,hand = charParts()
	if not char or not hum or not root or hum.Health <= 0 then return end
	hum.AutoRotate = true
	local target,distance = nearest(root)
	if target then
		roamGoal=nil
		if not combatGoal or os.clock() >= combatMoveAt then combatMoveAt=os.clock()+.35+math.random()*.35; combatGoal=combatMove(root,target,distance) end
		combatGoal=steerAroundObstacle(root,combatGoal,char); hum:MoveTo(combatGoal)
		if distance <= 8 then sword(char,root,hand,target) else local cfg=Weapons[currentWeapon]; if cfg and distance <= cfg.range then shoot(char,root,hand,target) end end
	else
		combatGoal=nil
		if not roamGoal or (root.Position-roamGoal).Magnitude < 4 or os.clock()-roamStarted > 4 then roamGoal=randomRoam(root); roamStarted=os.clock() end
		roamGoal=steerAroundObstacle(root,roamGoal,char); hum:MoveTo(roamGoal); equip(char,hand,currentWeapon)
	end
	handleStuck(hum,root)
	if os.clock() >= jumpAt then jumpAt=os.clock()+math.random(3,6); if hum.FloorMaterial ~= Enum.Material.Air and math.random() < .2 then hum.Jump=true end end
end)

print("V8 AUTO COMBAT READY - continuous roaming enabled.")
