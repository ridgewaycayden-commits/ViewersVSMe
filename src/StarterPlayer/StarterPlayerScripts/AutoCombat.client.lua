-- AutoCombat.client.lua
-- VIEWERS VS ME - PLAYER AI V2.1
-- Autonomous first-person combat with continuous roaming, natural aim easing,
-- obstacle steering, weapon bob/recoil, and stylized Arsenal-inspired viewmodels.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local enemies = workspace:WaitForChild("TikTokEnemies")
local attackRemote = ReplicatedStorage:WaitForChild("AutoCombatAttack")

local rng = Random.new()

local Weapons = {
	Pistol = {range=100,cooldown=.32,color=Color3.fromRGB(255,200,80),pellets=1,spread=.45,kick=.065},
	SMG = {range=95,cooldown=.10,color=Color3.fromRGB(70,205,255),pellets=1,spread=1.1,kick=.035},
	Shotgun = {range=65,cooldown=.72,color=Color3.fromRGB(255,135,65),pellets=7,spread=4.5,kick=.14},
	Rifle = {range=145,cooldown=.22,color=Color3.fromRGB(105,255,150),pellets=1,spread=.30,kick=.06},
	Minigun = {range=120,cooldown=.055,color=Color3.fromRGB(255,75,75),pellets=1,spread=1.8,kick=.025},
	Sword = {range=10,cooldown=.48,color=Color3.fromRGB(90,220,255),kick=.10},
}

local currentWeapon = "Rifle"
local shownWeapon = nil
local currentTarget = nil
local lastShot = 0
local lastSword = 0
local nextStrafeFlip = 0
local strafeSign = 1
local roamGoal = nil
local roamExpires = 0
local nextPause = 0
local pauseUntil = 0
local nextJump = 0
local lastMoveSample = 0
local lastMovePos = nil
local stuckFor = 0
local recoil = 0
local bobTime = 0
local aimPoint = nil
local viewModel = nil
local weaponRoot = nil
local muzzlePart = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function getCharacter()
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	local head = char:FindFirstChild("Head")
	if not hum or not root or not head or hum.Health <= 0 then return end
	return char,hum,root,head
end

local function aliveEnemy(model)
	if not model or not model.Parent or model:GetAttribute("Dead") == true then return false end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	return hum ~= nil and root ~= nil and hum.Health > 0
end

local function nearestEnemy(root)
	local best,bestDistance
	for _,model in ipairs(enemies:GetChildren()) do
		if aliveEnemy(model) then
			local eroot = model:FindFirstChild("HumanoidRootPart")
			local d = (eroot.Position-root.Position).Magnitude
			if not bestDistance or d < bestDistance then
				best,bestDistance = model,d
			end
		end
	end
	return best,bestDistance
end

local function hideLocalCharacter(char)
	for _,obj in ipairs(char:GetDescendants()) do
		if obj:IsA("BasePart") then
			if obj.Name == "Head" or obj.Parent:IsA("Accessory") then
				obj.LocalTransparencyModifier = 1
			end
		end
	end
end

local function newPart(model,name,size,color,material,relative,shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	if shape then p.Shape = shape end
	p.CFrame = relative or CFrame.new()
	p.Parent = model
	return p
end

local function clearViewModel()
	if viewModel then viewModel:Destroy() end
	viewModel=nil
	weaponRoot=nil
	muzzlePart=nil
	shownWeapon=nil
end

local function addArms(model)
	local sleeve = Color3.fromRGB(33,38,48)
	local glove = Color3.fromRGB(16,18,23)
	newPart(model,"RightUpper",Vector3.new(.44,.44,1.10),sleeve,Enum.Material.Fabric,CFrame.new(.63,-.62,.58)*CFrame.Angles(math.rad(-14),0,math.rad(-8)))
	newPart(model,"RightGlove",Vector3.new(.36,.34,.62),glove,Enum.Material.SmoothPlastic,CFrame.new(.48,-.43,.02)*CFrame.Angles(math.rad(-10),0,math.rad(-8)))
	newPart(model,"LeftUpper",Vector3.new(.44,.44,1.12),sleeve,Enum.Material.Fabric,CFrame.new(-.58,-.65,.35)*CFrame.Angles(math.rad(-18),0,math.rad(11)))
	newPart(model,"LeftGlove",Vector3.new(.36,.34,.60),glove,Enum.Material.SmoothPlastic,CFrame.new(-.40,-.39,-.23)*CFrame.Angles(math.rad(-10),0,math.rad(8)))
end

local function addRail(model,zStart,count,spacing)
	for i=0,count-1 do
		newPart(model,"Rail"..i,Vector3.new(.42,.055,.12),Color3.fromRGB(12,14,18),Enum.Material.Metal,CFrame.new(0,.42,zStart-i*spacing))
	end
end

local function makeWeaponModel(name)
	clearViewModel()
	shownWeapon = name
	local model = Instance.new("Model")
	model.Name = "FPSViewModel"
	model.Parent = camera
	viewModel = model
	weaponRoot = newPart(model,"Root",Vector3.new(.05,.05,.05),Color3.new(),Enum.Material.SmoothPlastic,CFrame.new())
	weaponRoot.Transparency = 1
	model.PrimaryPart = weaponRoot
	addArms(model)

	local black = Color3.fromRGB(10,12,16)
	local dark = Color3.fromRGB(25,29,36)
	local steel = Color3.fromRGB(79,88,102)
	local lightSteel = Color3.fromRGB(132,142,158)
	local red = Color3.fromRGB(235,48,60)
	local cyan = Color3.fromRGB(65,210,255)
	local gold = Color3.fromRGB(230,175,55)

	if name == "Sword" then
		newPart(model,"Grip",Vector3.new(.24,.24,1.00),black,Enum.Material.SmoothPlastic,CFrame.new(.32,-.18,-.10)*CFrame.Angles(math.rad(90),0,0))
		newPart(model,"Pommel",Vector3.new(.34,.24,.34),steel,Enum.Material.Metal,CFrame.new(.32,-.72,-.10))
		newPart(model,"Guard",Vector3.new(1.18,.14,.24),steel,Enum.Material.Metal,CFrame.new(.32,.03,-.42))
		newPart(model,"BladeCore",Vector3.new(.11,.12,3.72),Color3.fromRGB(205,214,228),Enum.Material.Metal,CFrame.new(.32,.04,-2.35))
		newPart(model,"BladeEdge",Vector3.new(.026,.135,3.55),cyan,Enum.Material.Neon,CFrame.new(.39,.04,-2.35))
		newPart(model,"BladeSpine",Vector3.new(.03,.13,3.35),dark,Enum.Material.Metal,CFrame.new(.255,.04,-2.22))
		newPart(model,"BladeAccent",Vector3.new(.028,.14,1.30),red,Enum.Material.Neon,CFrame.new(.255,.04,-1.75))
		return
	end

	if name == "Rifle" then
		newPart(model,"LowerReceiver",Vector3.new(.56,.58,1.55),dark,Enum.Material.Metal,CFrame.new(0,0,0))
		newPart(model,"UpperReceiver",Vector3.new(.52,.28,1.98),steel,Enum.Material.Metal,CFrame.new(0,.31,-.18))
		newPart(model,"Handguard",Vector3.new(.50,.48,1.95),Color3.fromRGB(38,43,52),Enum.Material.Metal,CFrame.new(0,.02,-1.78))
		newPart(model,"StockBody",Vector3.new(.52,.58,1.32),black,Enum.Material.SmoothPlastic,CFrame.new(0,-.02,1.37))
		newPart(model,"StockPad",Vector3.new(.58,.68,.20),Color3.fromRGB(35,39,45),Enum.Material.SmoothPlastic,CFrame.new(0,-.02,2.13))
		newPart(model,"PistolGrip",Vector3.new(.32,.78,.36),black,Enum.Material.SmoothPlastic,CFrame.new(0,-.62,.34)*CFrame.Angles(math.rad(-13),0,0))
		newPart(model,"Magazine",Vector3.new(.38,.98,.48),black,Enum.Material.Metal,CFrame.new(0,-.72,-.28)*CFrame.Angles(math.rad(-9),0,0))
		newPart(model,"Barrel",Vector3.new(.14,.14,1.72),lightSteel,Enum.Material.Metal,CFrame.new(0,.01,-3.58))
		newPart(model,"MuzzleBrake",Vector3.new(.25,.25,.44),black,Enum.Material.Metal,CFrame.new(0,.01,-4.66))
		newPart(model,"OpticMount",Vector3.new(.42,.11,.72),black,Enum.Material.Metal,CFrame.new(0,.54,-.45))
		newPart(model,"OpticBody",Vector3.new(.50,.42,.66),black,Enum.Material.Metal,CFrame.new(0,.73,-.45))
		newPart(model,"OpticLens",Vector3.new(.27,.25,.04),cyan,Enum.Material.Neon,CFrame.new(0,.73,-.80))
		newPart(model,"ChargingHandle",Vector3.new(.18,.13,.34),lightSteel,Enum.Material.Metal,CFrame.new(.34,.20,.13))
		newPart(model,"SideAccent",Vector3.new(.025,.22,1.34),red,Enum.Material.Neon,CFrame.new(.292,.10,-.10))
		newPart(model,"HandAccent",Vector3.new(.025,.08,1.34),red,Enum.Material.Neon,CFrame.new(.262,.10,-1.76))
		addRail(model,-.70,7,.27)
		muzzlePart = newPart(model,"Muzzle",Vector3.new(.10,.10,.10),Weapons.Rifle.color,Enum.Material.Neon,CFrame.new(0,.01,-4.92))
	elseif name == "Pistol" then
		newPart(model,"Slide",Vector3.new(.44,.35,1.58),steel,Enum.Material.Metal,CFrame.new(.16,.04,-.12))
		newPart(model,"Frame",Vector3.new(.40,.34,1.04),dark,Enum.Material.Metal,CFrame.new(.16,-.23,.04))
		newPart(model,"Grip",Vector3.new(.37,.84,.43),black,Enum.Material.SmoothPlastic,CFrame.new(.16,-.70,.40)*CFrame.Angles(math.rad(-13),0,0))
		newPart(model,"Barrel",Vector3.new(.13,.13,.63),lightSteel,Enum.Material.Metal,CFrame.new(.16,.04,-1.18))
		newPart(model,"RearSight",Vector3.new(.20,.12,.12),black,Enum.Material.Metal,CFrame.new(.16,.27,.42))
		newPart(model,"FrontSight",Vector3.new(.10,.12,.10),gold,Enum.Material.Neon,CFrame.new(.16,.27,-.72))
		newPart(model,"SlideAccent",Vector3.new(.025,.07,1.18),gold,Enum.Material.Neon,CFrame.new(.39,.10,-.12))
		muzzlePart = newPart(model,"Muzzle",Vector3.new(.09,.09,.09),Weapons.Pistol.color,Enum.Material.Neon,CFrame.new(.16,.04,-1.53))
	elseif name == "SMG" then
		newPart(model,"Receiver",Vector3.new(.54,.57,1.72),dark,Enum.Material.Metal,CFrame.new(0,0,-.08))
		newPart(model,"Upper",Vector3.new(.49,.24,1.58),steel,Enum.Material.Metal,CFrame.new(0,.32,-.18))
		newPart(model,"Stock",Vector3.new(.43,.49,1.14),black,Enum.Material.SmoothPlastic,CFrame.new(0,-.02,1.26))
		newPart(model,"Mag",Vector3.new(.34,.88,.42),black,Enum.Material.Metal,CFrame.new(0,-.68,-.28)*CFrame.Angles(math.rad(-8),0,0))
		newPart(model,"Foregrip",Vector3.new(.27,.67,.29),black,Enum.Material.SmoothPlastic,CFrame.new(0,-.49,-1.42))
		newPart(model,"Barrel",Vector3.new(.14,.14,1.24),lightSteel,Enum.Material.Metal,CFrame.new(0,.01,-2.39))
		newPart(model,"TopRail",Vector3.new(.40,.07,1.32),black,Enum.Material.Metal,CFrame.new(0,.46,-.18))
		newPart(model,"Accent",Vector3.new(.025,.20,1.32),cyan,Enum.Material.Neon,CFrame.new(.285,.08,-.18))
		muzzlePart = newPart(model,"Muzzle",Vector3.new(.10,.10,.10),Weapons.SMG.color,Enum.Material.Neon,CFrame.new(0,.01,-3.05))
	elseif name == "Shotgun" then
		newPart(model,"Receiver",Vector3.new(.56,.59,1.48),dark,Enum.Material.Metal,CFrame.new(0,0,0))
		newPart(model,"Stock",Vector3.new(.53,.64,1.54),Color3.fromRGB(72,46,31),Enum.Material.Wood,CFrame.new(0,-.05,1.40))
		newPart(model,"StockPad",Vector3.new(.58,.70,.18),black,Enum.Material.SmoothPlastic,CFrame.new(0,-.05,2.26))
		newPart(model,"Barrel",Vector3.new(.18,.18,2.78),lightSteel,Enum.Material.Metal,CFrame.new(0,.08,-2.24))
		newPart(model,"Tube",Vector3.new(.16,.16,2.42),dark,Enum.Material.Metal,CFrame.new(0,-.20,-2.14))
		newPart(model,"Pump",Vector3.new(.51,.45,.96),Color3.fromRGB(94,60,38),Enum.Material.Wood,CFrame.new(0,-.16,-1.60))
		newPart(model,"ReceiverAccent",Vector3.new(.025,.07,1.06),red,Enum.Material.Neon,CFrame.new(.295,.22,.02))
		muzzlePart = newPart(model,"Muzzle",Vector3.new(.11,.11,.11),Weapons.Shotgun.color,Enum.Material.Neon,CFrame.new(0,.08,-3.68))
	elseif name == "Minigun" then
		newPart(model,"Housing",Vector3.new(.86,.84,1.72),dark,Enum.Material.Metal,CFrame.new(0,0,-.05))
		newPart(model,"Rear",Vector3.new(.94,.90,.82),black,Enum.Material.Metal,CFrame.new(0,0,.99))
		newPart(model,"Grip",Vector3.new(.33,.78,.31),black,Enum.Material.SmoothPlastic,CFrame.new(0,-.69,.20))
		local offs={{.20,.20},{-.20,.20},{.20,-.20},{-.20,-.20},{0,.29},{0,-.29}}
		for i,o in ipairs(offs) do
			newPart(model,"Barrel"..i,Vector3.new(.105,.105,2.72),lightSteel,Enum.Material.Metal,CFrame.new(o[1],o[2],-2.25))
		end
		newPart(model,"FrontRing",Vector3.new(.74,.74,.16),steel,Enum.Material.Metal,CFrame.new(0,0,-3.63),Enum.PartType.Cylinder)
		newPart(model,"Accent",Vector3.new(.03,.31,1.27),red,Enum.Material.Neon,CFrame.new(.445,0,-.16))
		muzzlePart = newPart(model,"Muzzle",Vector3.new(.12,.12,.12),Weapons.Minigun.color,Enum.Material.Neon,CFrame.new(0,0,-3.73))
	end

	if muzzlePart then muzzlePart.Transparency = 1 end
end

local function tracer(a,b,color)
	local delta = b-a
	local dist = delta.Magnitude
	if dist < .05 then return end
	local p = Instance.new("Part")
	p.Anchored=true
	p.CanCollide=false
	p.CanTouch=false
	p.CanQuery=false
	p.Material=Enum.Material.Neon
	p.Color=color
	p.Size=Vector3.new(.04,.04,dist)
	p.CFrame=CFrame.lookAt((a+b)/2,b)
	p.Parent=workspace
	Debris:AddItem(p,.05)
end

local function flashMuzzle()
	if not muzzlePart then return end
	muzzlePart.Transparency = 0
	local light = Instance.new("PointLight")
	light.Brightness = 2.5
	light.Range = 8
	light.Color = muzzlePart.Color
	light.Parent = muzzlePart
	Debris:AddItem(light,.04)
	task.delay(.035,function()
		if muzzlePart then muzzlePart.Transparency = 1 end
	end)
end

local function clearPath(char,origin,dir,distance)
	if dir.Magnitude < .01 then return true end
	rayParams.FilterDescendantsInstances = {char,enemies,camera}
	return workspace:Raycast(origin,dir.Unit*distance,rayParams) == nil
end

local function steerDirection(char,root,desired)
	if desired.Magnitude < .01 then return Vector3.zero end
	local flat = Vector3.new(desired.X,0,desired.Z)
	if flat.Magnitude < .01 then return Vector3.zero end
	local forward = flat.Unit
	if clearPath(char,root.Position+Vector3.new(0,1.8,0),forward,7) then return forward end

	local left = Vector3.new(-forward.Z,0,forward.X)
	local right = -left
	local leftFree = clearPath(char,root.Position+Vector3.new(0,1.8,0),left,8)
	local rightFree = clearPath(char,root.Position+Vector3.new(0,1.8,0),right,8)
	if leftFree and not rightFree then return (forward*.25+left).Unit end
	if rightFree and not leftFree then return (forward*.25+right).Unit end
	if leftFree and rightFree then return (forward*.20+(rng:NextNumber()<.5 and left or right)).Unit end
	return (-forward + left*.35).Unit
end

local function chooseRoam(root)
	local angle = rng:NextNumber(0,math.pi*2)
	local distance = rng:NextNumber(18,44)
	roamGoal = root.Position + Vector3.new(math.cos(angle)*distance,0,math.sin(angle)*distance)
	roamExpires = os.clock()+rng:NextNumber(2.6,5.0)
end

local function targetAimPosition(target)
	local eroot = target and target:FindFirstChild("HumanoidRootPart")
	if not eroot then return nil end
	local head = target:FindFirstChild("Head")
	local base = head and head.Position or (eroot.Position+Vector3.new(0,1.8,0))
	local velocity = eroot.AssemblyLinearVelocity
	local lead = Vector3.new(velocity.X,0,velocity.Z)*.10
	return base + lead
end

local function fireGun(target)
	local cfg = Weapons[currentWeapon]
	if not cfg or os.clock()-lastShot < cfg.cooldown then return end
	local targetPos = targetAimPosition(target)
	if not targetPos then return end
	lastShot = os.clock()
	recoil = math.min(recoil+cfg.kick,.22)
	flashMuzzle()
	local origin = muzzlePart and muzzlePart.Position or camera.CFrame.Position
	for _=1,cfg.pellets do
		local spread = cfg.spread
		local aim = targetPos + Vector3.new(rng:NextNumber(-spread,spread),rng:NextNumber(-spread*.25,spread*.25),rng:NextNumber(-spread,spread))
		tracer(origin,aim,cfg.color)
	end
	attackRemote:FireServer(target,currentWeapon)
end

local function swingSword(target)
	if os.clock()-lastSword < Weapons.Sword.cooldown then return end
	lastSword = os.clock()
	recoil = math.min(recoil+.12,.24)
	attackRemote:FireServer(target,"Sword")
end

local function updateMovement(dt,char,hum,root,target,distance)
	hum.AutoRotate = false
	hum.WalkSpeed = target and 19 or 17

	if os.clock() > nextPause then
		nextPause = os.clock()+rng:NextNumber(2.8,5.2)
		pauseUntil = os.clock()+rng:NextNumber(.08,.24)
	end

	local move = Vector3.zero
	local facePos = nil

	if target and aliveEnemy(target) then
		local eroot = target:FindFirstChild("HumanoidRootPart")
		local toEnemy = eroot.Position-root.Position
		local flat = Vector3.new(toEnemy.X,0,toEnemy.Z)
		local forward = flat.Magnitude > .01 and flat.Unit or root.CFrame.LookVector
		local right = Vector3.new(-forward.Z,0,forward.X)

		if os.clock() > nextStrafeFlip then
			nextStrafeFlip = os.clock()+rng:NextNumber(.65,1.45)
			strafeSign = rng:NextNumber()<.5 and -1 or 1
		end

		if distance > 43 then
			move = forward + right*strafeSign*.20
		elseif distance < 12 then
			move = -forward + right*strafeSign*.45
		else
			local pressure = rng:NextNumber(-.12,.16)
			move = right*strafeSign + forward*pressure
		end
		facePos = eroot.Position
	else
		if not roamGoal or os.clock()>roamExpires or (Vector3.new(roamGoal.X-root.Position.X,0,roamGoal.Z-root.Position.Z)).Magnitude < 4 then
			chooseRoam(root)
		end
		move = roamGoal-root.Position
		facePos = root.Position+move
	end

	move = steerDirection(char,root,move)
	if os.clock() < pauseUntil then move = Vector3.zero end
	hum:Move(move,false)

	if facePos then
		local flatLook = Vector3.new(facePos.X,root.Position.Y,facePos.Z)
		if (flatLook-root.Position).Magnitude > .1 then
			local desired = CFrame.lookAt(root.Position,flatLook)
			root.CFrame = root.CFrame:Lerp(desired,1-math.exp(-dt*7.0))
		end
	end

	if os.clock()-lastMoveSample > .18 then
		if lastMovePos then
			local moved = (root.Position-lastMovePos).Magnitude
			if move.Magnitude > .2 and moved < .18 then stuckFor += .18 else stuckFor = 0 end
		end
		lastMovePos = root.Position
		lastMoveSample = os.clock()
	end

	if stuckFor > .72 and os.clock()>nextJump then
		nextJump = os.clock()+1.2
		hum.Jump = true
		chooseRoam(root)
		stuckFor = 0
	elseif target and distance < 18 and rng:NextNumber() < dt*.17 and os.clock()>nextJump then
		nextJump = os.clock()+rng:NextNumber(1.3,2.5)
		hum.Jump = true
	end
end

local function updateCamera(dt,char,hum,root,head,target)
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	camera.CameraType = Enum.CameraType.Scriptable
	hideLocalCharacter(char)

	local desiredPoint
	if target and aliveEnemy(target) then
		desiredPoint = targetAimPosition(target)
	else
		desiredPoint = head.Position + root.CFrame.LookVector*70 + Vector3.new(0,.15,0)
	end
	if not desiredPoint then desiredPoint = head.Position+root.CFrame.LookVector*70 end

	if not aimPoint then aimPoint = desiredPoint end
	local aimAlpha = 1-math.exp(-dt*(target and 5.0 or 3.0))
	aimPoint = aimPoint:Lerp(desiredPoint,aimAlpha)

	bobTime += dt*(hum.MoveDirection.Magnitude>.05 and 9.5 or 3.2)
	local speedBob = hum.MoveDirection.Magnitude
	local bobX = math.sin(bobTime)*.035*speedBob
	local bobY = math.abs(math.cos(bobTime))*-.028*speedBob
	local sway = math.sin(os.clock()*1.7)*.012
	recoil = recoil*math.exp(-dt*12)

	local camPos = head.Position + Vector3.new(0,.12,0)
	local look = CFrame.lookAt(camPos,aimPoint)
	camera.CFrame = look * CFrame.Angles(-recoil*.42,sway,0) * CFrame.new(bobX,bobY,0)
	camera.FieldOfView = 76

	local desiredWeapon = (target and select(2,nearestEnemy(root)) and select(2,nearestEnemy(root)) <= 8.5) and "Sword" or currentWeapon
	if shownWeapon ~= desiredWeapon then makeWeaponModel(desiredWeapon) end
	if viewModel then
		local vmBobX = math.sin(bobTime)*.028*speedBob
		local vmBobY = math.abs(math.cos(bobTime))*-.020*speedBob
		local baseOffset
		if shownWeapon == "Sword" then
			baseOffset = CFrame.new(.68,-.88,-1.15)*CFrame.Angles(math.rad(-7),math.rad(-7),math.rad(7))
		else
			baseOffset = CFrame.new(.62,-.82,-1.25)*CFrame.Angles(math.rad(-4),math.rad(-2),math.rad(1.5))
		end
		local kick = CFrame.new(0,0,recoil*1.1)*CFrame.Angles(-recoil*.75,0,recoil*.12)
		viewModel:PivotTo(camera.CFrame*baseOffset*CFrame.new(vmBobX,vmBobY,0)*kick)
	end
end

player.CharacterAdded:Connect(function()
	clearViewModel()
	aimPoint=nil
	roamGoal=nil
	lastMovePos=nil
	stuckFor=0
	task.wait(.35)
	local char=player.Character
	if char then hideLocalCharacter(char) end
end)

RunService.RenderStepped:Connect(function(dt)
	local char,hum,root,head = getCharacter()
	if not char then return end

	if not currentTarget or not aliveEnemy(currentTarget) then
		currentTarget = nearestEnemy(root)
	end
	local distance
	if currentTarget and aliveEnemy(currentTarget) then
		local eroot=currentTarget:FindFirstChild("HumanoidRootPart")
		distance=(eroot.Position-root.Position).Magnitude
	else
		currentTarget,distance = nearestEnemy(root)
	end

	updateMovement(dt,char,hum,root,currentTarget,distance)
	updateCamera(dt,char,hum,root,head,currentTarget)

	if currentTarget and distance then
		if distance <= 8.5 then
			if shownWeapon ~= "Sword" then makeWeaponModel("Sword") end
			swingSword(currentTarget)
		elseif distance <= Weapons[currentWeapon].range then
			if shownWeapon ~= currentWeapon then makeWeaponModel(currentWeapon) end
			fireGun(currentTarget)
		end
	end
end)

print("PLAYER AI V2.1 READY - roaming restored, natural aim enabled, FPS viewmodels upgraded.")
