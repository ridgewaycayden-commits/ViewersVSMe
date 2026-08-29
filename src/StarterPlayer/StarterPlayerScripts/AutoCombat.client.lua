-- AutoCombat.client.lua
-- VIEWERS VS ME - PLAYER AI V2
-- First-person autonomous combat, smoother armed movement, obstacle steering,
-- and high-detail stylized FPS weapon viewmodels.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local enemies = workspace:WaitForChild("TikTokEnemies")
local attackRemote = ReplicatedStorage:WaitForChild("AutoCombatAttack")

local Weapons = {
	Pistol = {range=100,cooldown=.32,color=Color3.fromRGB(255,205,90),pellets=1,spread=.45,kick=.055},
	SMG = {range=95,cooldown=.10,color=Color3.fromRGB(95,215,255),pellets=1,spread=1.15,kick=.035},
	Shotgun = {range=65,cooldown=.72,color=Color3.fromRGB(255,145,75),pellets=7,spread=4.5,kick=.12},
	Rifle = {range=145,cooldown=.22,color=Color3.fromRGB(110,255,155),pellets=1,spread=.28,kick=.055},
	Minigun = {range=120,cooldown=.055,color=Color3.fromRGB(255,80,80),pellets=1,spread=1.8,kick=.022},
	Sword = {range=10,cooldown=.48,color=Color3.fromRGB(115,220,255)},
}

local currentWeapon = "Rifle"
local shownWeapon = nil
local currentTarget = nil
local lastShot = 0
local lastSword = 0
local roamGoal = nil
local roamAt = 0
local nextJump = 0
local strafeSign = 1
local lastStrafeFlip = 0
local lastPos = nil
local stuckSince = nil
local cameraRecoil = 0
local bobClock = 0
local viewModel = nil
local weaponRoot = nil
local muzzlePart = nil

local rng = Random.new()
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

local function aliveEnemy(m)
	if not m or not m.Parent or m:GetAttribute("Dead") == true then return false end
	local hum = m:FindFirstChildOfClass("Humanoid")
	local root = m:FindFirstChild("HumanoidRootPart")
	return hum ~= nil and root ~= nil and hum.Health > 0
end

local function nearestEnemy(root)
	local best,bestD
	for _,m in ipairs(enemies:GetChildren()) do
		if aliveEnemy(m) then
			local eroot = m:FindFirstChild("HumanoidRootPart")
			local d = (eroot.Position-root.Position).Magnitude
			if not bestD or d < bestD then best,bestD = m,d end
		end
	end
	return best,bestD
end

local function hideLocalHead(char)
	for _,obj in ipairs(char:GetDescendants()) do
		if obj:IsA("BasePart") and (obj.Name == "Head" or obj.Parent:IsA("Accessory")) then
			obj.LocalTransparencyModifier = 1
		end
	end
end

local function makePart(parent,name,size,color,material,cf)
	local p = Instance.new("Part")
	p.Name=name
	p.Size=size
	p.Color=color
	p.Material=material or Enum.Material.Metal
	p.Anchored=true
	p.CanCollide=false
	p.CanTouch=false
	p.CanQuery=false
	p.CastShadow=false
	p.CFrame=cf or CFrame.new()
	p.Parent=parent
	return p
end

local function clearViewModel()
	if viewModel then viewModel:Destroy() end
	viewModel=nil; weaponRoot=nil; muzzlePart=nil; shownWeapon=nil
end

local function addArms(model)
	local sleeve=Color3.fromRGB(35,40,48)
	local glove=Color3.fromRGB(22,24,29)
	makePart(model,"RightSleeve",Vector3.new(.40,.42,1.3),sleeve,Enum.Material.Fabric,CFrame.new(.60,-.74,-1.15)*CFrame.Angles(math.rad(-13),0,math.rad(-7)))
	makePart(model,"RightGlove",Vector3.new(.34,.32,.62),glove,Enum.Material.SmoothPlastic,CFrame.new(.48,-.48,-1.78)*CFrame.Angles(math.rad(-8),0,math.rad(-7)))
	makePart(model,"LeftSleeve",Vector3.new(.40,.42,1.18),sleeve,Enum.Material.Fabric,CFrame.new(-.56,-.78,-1.30)*CFrame.Angles(math.rad(-18),0,math.rad(10)))
	makePart(model,"LeftGlove",Vector3.new(.34,.32,.60),glove,Enum.Material.SmoothPlastic,CFrame.new(-.42,-.51,-1.93)*CFrame.Angles(math.rad(-10),0,math.rad(8)))
end

local function makeWeaponModel(name)
	clearViewModel()
	shownWeapon=name
	local model=Instance.new("Model")
	model.Name="FPSViewModel"
	model.Parent=camera
	viewModel=model
	addArms(model)

	local black=Color3.fromRGB(13,15,19)
	local dark=Color3.fromRGB(27,30,37)
	local steel=Color3.fromRGB(78,86,98)
	local steel2=Color3.fromRGB(122,130,142)
	local red=Color3.fromRGB(220,45,55)
	local cyan=Color3.fromRGB(70,210,255)
	local gold=Color3.fromRGB(225,175,55)
	local base=CFrame.new(.18,-.52,-2.25)
	weaponRoot=makePart(model,"WeaponRoot",Vector3.new(.1,.1,.1),black,Enum.Material.SmoothPlastic,base)
	weaponRoot.Transparency=1

	if name=="Sword" then
		makePart(model,"Grip",Vector3.new(.22,.22,.95),black,Enum.Material.SmoothPlastic,base*CFrame.new(.32,-.18,.25)*CFrame.Angles(math.rad(90),0,0))
		makePart(model,"Guard",Vector3.new(1.05,.12,.22),steel,Enum.Material.Metal,base*CFrame.new(.32,.06,-.13))
		makePart(model,"Blade",Vector3.new(.10,.10,3.55),Color3.fromRGB(205,215,228),Enum.Material.Metal,base*CFrame.new(.32,.08,-1.95))
		makePart(model,"BladeEdge",Vector3.new(.025,.115,3.38),cyan,Enum.Material.Neon,base*CFrame.new(.378,.08,-1.95))
		makePart(model,"BladeSpine",Vector3.new(.035,.12,3.3),dark,Enum.Material.Metal,base*CFrame.new(.265,.08,-1.95))
		return
	end

	if name=="Rifle" then
		makePart(model,"Receiver",Vector3.new(.54,.54,1.62),dark,Enum.Material.Metal,base)
		makePart(model,"Upper",Vector3.new(.50,.24,2.00),steel,Enum.Material.Metal,base*CFrame.new(0,.32,-.26))
		makePart(model,"Handguard",Vector3.new(.48,.46,1.88),Color3.fromRGB(38,42,49),Enum.Material.Metal,base*CFrame.new(0,.02,-1.75))
		makePart(model,"Stock",Vector3.new(.48,.54,1.40),black,Enum.Material.SmoothPlastic,base*CFrame.new(0,-.03,1.37))
		makePart(model,"Grip",Vector3.new(.31,.77,.34),black,Enum.Material.SmoothPlastic,base*CFrame.new(0,-.61,.30)*CFrame.Angles(math.rad(-12),0,0))
		makePart(model,"Magazine",Vector3.new(.36,.94,.45),black,Enum.Material.Metal,base*CFrame.new(0,-.70,-.25)*CFrame.Angles(math.rad(-10),0,0))
		makePart(model,"Barrel",Vector3.new(.13,.13,1.75),steel2,Enum.Material.Metal,base*CFrame.new(0,.03,-3.50))
		makePart(model,"MuzzleBrake",Vector3.new(.25,.25,.42),black,Enum.Material.Metal,base*CFrame.new(0,.03,-4.58))
		makePart(model,"OpticBase",Vector3.new(.42,.11,.72),black,Enum.Material.Metal,base*CFrame.new(0,.53,-.42))
		makePart(model,"Optic",Vector3.new(.46,.38,.62),black,Enum.Material.Metal,base*CFrame.new(0,.71,-.42))
		makePart(model,"Lens",Vector3.new(.27,.24,.035),cyan,Enum.Material.Neon,base*CFrame.new(0,.71,-.75))
		for i=-2,2 do makePart(model,"Accent"..i,Vector3.new(.025,.045,.25),red,Enum.Material.Neon,base*CFrame.new(.245,.18,-1.76+i*.31)) end
		muzzlePart=makePart(model,"Muzzle",Vector3.new(.12,.12,.12),Weapons.Rifle.color,Enum.Material.Neon,base*CFrame.new(0,.03,-4.84))
	elseif name=="Pistol" then
		makePart(model,"Slide",Vector3.new(.43,.34,1.55),steel,Enum.Material.Metal,base*CFrame.new(.15,.05,-.05))
		makePart(model,"Frame",Vector3.new(.40,.34,1.04),dark,Enum.Material.Metal,base*CFrame.new(.15,-.23,.10))
		makePart(model,"Grip",Vector3.new(.36,.82,.42),black,Enum.Material.SmoothPlastic,base*CFrame.new(.15,-.69,.45)*CFrame.Angles(math.rad(-12),0,0))
		makePart(model,"Barrel",Vector3.new(.13,.13,.62),steel2,Enum.Material.Metal,base*CFrame.new(.15,.05,-1.13))
		makePart(model,"Accent",Vector3.new(.025,.06,1.10),gold,Enum.Material.Neon,base*CFrame.new(.37,.10,-.05))
		muzzlePart=makePart(model,"Muzzle",Vector3.new(.10,.10,.10),Weapons.Pistol.color,Enum.Material.Neon,base*CFrame.new(.15,.05,-1.50))
	elseif name=="SMG" then
		makePart(model,"Receiver",Vector3.new(.53,.55,1.75),dark,Enum.Material.Metal,base)
		makePart(model,"Upper",Vector3.new(.48,.22,1.52),steel,Enum.Material.Metal,base*CFrame.new(0,.32,-.18))
		makePart(model,"Stock",Vector3.new(.42,.48,1.15),black,Enum.Material.SmoothPlastic,base*CFrame.new(0,-.02,1.28))
		makePart(model,"Magazine",Vector3.new(.34,.86,.42),black,Enum.Material.Metal,base*CFrame.new(0,-.67,-.22)*CFrame.Angles(math.rad(-8),0,0))
		makePart(model,"Foregrip",Vector3.new(.26,.66,.28),black,Enum.Material.SmoothPlastic,base*CFrame.new(0,-.50,-1.40))
		makePart(model,"Barrel",Vector3.new(.14,.14,1.25),steel2,Enum.Material.Metal,base*CFrame.new(0,.02,-2.34))
		makePart(model,"Accent",Vector3.new(.025,.18,1.30),cyan,Enum.Material.Neon,base*CFrame.new(.275,.08,-.22))
		muzzlePart=makePart(model,"Muzzle",Vector3.new(.11,.11,.11),Weapons.SMG.color,Enum.Material.Neon,base*CFrame.new(0,.02,-3.00))
	elseif name=="Shotgun" then
		makePart(model,"Receiver",Vector3.new(.55,.58,1.45),dark,Enum.Material.Metal,base)
		makePart(model,"Stock",Vector3.new(.52,.62,1.52),Color3.fromRGB(72,47,32),Enum.Material.Wood,base*CFrame.new(0,-.06,1.36))
		makePart(model,"Barrel",Vector3.new(.18,.18,2.75),steel2,Enum.Material.Metal,base*CFrame.new(0,.07,-2.20))
		makePart(model,"Tube",Vector3.new(.16,.16,2.40),dark,Enum.Material.Metal,base*CFrame.new(0,-.20,-2.10))
		makePart(model,"Pump",Vector3.new(.50,.44,.92),Color3.fromRGB(92,59,38),Enum.Material.Wood,base*CFrame.new(0,-.17,-1.57))
		makePart(model,"Accent",Vector3.new(.025,.06,1.05),red,Enum.Material.Neon,base*CFrame.new(.285,.22,.03))
		muzzlePart=makePart(model,"Muzzle",Vector3.new(.12,.12,.12),Weapons.Shotgun.color,Enum.Material.Neon,base*CFrame.new(0,.07,-3.63))
	elseif name=="Minigun" then
		makePart(model,"Housing",Vector3.new(.85,.82,1.72),dark,Enum.Material.Metal,base)
		makePart(model,"Rear",Vector3.new(.92,.88,.80),black,Enum.Material.Metal,base*CFrame.new(0,0,.98))
		makePart(model,"Grip",Vector3.new(.32,.76,.30),black,Enum.Material.SmoothPlastic,base*CFrame.new(0,-.68,.22))
		local offsets={{.20,.20},{-.20,.20},{.20,-.20},{-.20,-.20},{0,.28},{0,-.28}}
		for i,o in ipairs(offsets) do makePart(model,"Barrel"..i,Vector3.new(.105,.105,2.65),steel2,Enum.Material.Metal,base*CFrame.new(o[1],o[2],-2.20)) end
		makePart(model,"Accent",Vector3.new(.03,.30,1.25),red,Enum.Material.Neon,base*CFrame.new(.44,0,-.15))
		muzzlePart=makePart(model,"Muzzle",Vector3.new(.13,.13,.13),Weapons.Minigun.color,Enum.Material.Neon,base*CFrame.new(0,0,-3.58))
	end
	if muzzlePart then muzzlePart.Transparency=1 end
end

local function moveViewModel(cf)
	if not viewModel or not weaponRoot then return end
	local old=weaponRoot.CFrame
	for _,p in ipairs(viewModel:GetChildren()) do
		if p:IsA("BasePart") and p~=weaponRoot then
			local rel=old:ToObjectSpace(p.CFrame)
			p.CFrame=cf*rel
		end
	end
	weaponRoot.CFrame=cf
end

local function tracer(a,b,color)
	local d=b-a
	local dist=d.Magnitude
	if dist<.05 then return end
	local p=Instance.new("Part")
	p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false
	p.Material=Enum.Material.Neon; p.Color=color; p.Size=Vector3.new(.045,.045,dist)
	p.CFrame=CFrame.lookAt((a+b)/2,b)
	p.Parent=workspace
	Debris:AddItem(p,.045)
end

local function muzzleFlash()
	if not muzzlePart then return end
	muzzlePart.Transparency=0
	local light=Instance.new("PointLight")
	light.Brightness=2.6; light.Range=9; light.Color=muzzlePart.Color; light.Parent=muzzlePart
	Debris:AddItem(light,.045)
	task.delay(.045,function() if muzzlePart and muzzlePart.Parent then muzzlePart.Transparency=1 end end)
end

local function forwardClear(root,dir,dist,char)
	if dir.Magnitude<.1 then return true end
	rayParams.FilterDescendantsInstances={char,enemies}
	local origin=root.Position+Vector3.new(0,1.6,0)
	return workspace:Raycast(origin,dir.Unit*dist,rayParams)==nil
end

local function steerAround(root,desired,char)
	local delta=desired-root.Position
	local flat=Vector3.new(delta.X,0,delta.Z)
	if flat.Magnitude<1 then return desired end
	local dir=flat.Unit
	if forwardClear(root,dir,9,char) then return desired end
	local right=Vector3.new(-dir.Z,0,dir.X)
	for _,sign in ipairs({strafeSign,-strafeSign}) do
		local candidate=(dir*.45+right*sign*.90).Unit
		if forwardClear(root,candidate,8,char) then return root.Position+candidate*11 end
	end
	return root.Position-dir*5+right*strafeSign*6
end

local function chooseRoam(root)
	local angle=rng:NextNumber(0,math.pi*2)
	local dist=rng:NextNumber(18,42)
	roamGoal=root.Position+Vector3.new(math.cos(angle)*dist,0,math.sin(angle)*dist)
	roamAt=os.clock()
end

local function faceTarget(root,targetPos,alpha)
	local flat=Vector3.new(targetPos.X,root.Position.Y,targetPos.Z)
	if (flat-root.Position).Magnitude<.1 then return end
	root.CFrame=root.CFrame:Lerp(CFrame.lookAt(root.Position,flat),alpha)
end

local function fireGun(target)
	local cfg=Weapons[currentWeapon]
	if not cfg or os.clock()-lastShot<cfg.cooldown then return end
	local eroot=target and target:FindFirstChild("HumanoidRootPart")
	if not eroot then return end
	lastShot=os.clock()
	if shownWeapon~=currentWeapon then makeWeaponModel(currentWeapon) end
	cameraRecoil=math.min(cameraRecoil+cfg.kick,.18)
	muzzleFlash()
	local origin=camera.CFrame.Position+camera.CFrame.LookVector*1.4
	for _=1,cfg.pellets do
		local aim=eroot.Position+Vector3.new(rng:NextNumber(-.5,.5)*cfg.spread,1+rng:NextNumber(-.5,.5)*cfg.spread*.25,rng:NextNumber(-.5,.5)*cfg.spread)
		tracer(origin,aim,cfg.color)
	end
	attackRemote:FireServer(target,currentWeapon)
end

local function swingSword(target)
	if os.clock()-lastSword<Weapons.Sword.cooldown then return end
	if not target or not target:FindFirstChild("HumanoidRootPart") then return end
	lastSword=os.clock()
	if shownWeapon~="Sword" then makeWeaponModel("Sword") end
	cameraRecoil=math.min(cameraRecoil+.08,.20)
	attackRemote:FireServer(target,"Sword")
end

local function updateMovement(char,hum,root,target,dist)
	-- Faster, smoother armed movement than the old build.
	hum.WalkSpeed = shownWeapon=="Sword" and 21 or (target and 19 or 18)
	hum.JumpPower=42
	hum.AutoRotate=false
	local now=os.clock()

	if now-lastStrafeFlip>1.65 then strafeSign*=-1; lastStrafeFlip=now end

	if target and aliveEnemy(target) then
		local eroot=target:FindFirstChild("HumanoidRootPart")
		local flat=Vector3.new(eroot.Position.X-root.Position.X,0,eroot.Position.Z-root.Position.Z)
		if flat.Magnitude>.1 then
			local dir=flat.Unit
			local right=Vector3.new(-dir.Z,0,dir.X)
			local desired
			if dist>35 then desired=eroot.Position-dir*24+right*strafeSign*4
			elseif dist<9 then desired=root.Position-dir*12+right*strafeSign*7
			else desired=root.Position+right*strafeSign*10+dir*(dist>22 and 5 or -2) end
			hum:MoveTo(steerAround(root,desired,char))
			faceTarget(root,eroot.Position,.20)
		end
	else
		if not roamGoal or (Vector3.new(roamGoal.X-root.Position.X,0,roamGoal.Z-root.Position.Z)).Magnitude<4 or now-roamAt>4.5 then chooseRoam(root) end
		local goal=steerAround(root,roamGoal,char)
		hum:MoveTo(goal)
		faceTarget(root,goal,.10)
	end

	if now>nextJump then
		nextJump=now+rng:NextNumber(2.6,5.0)
		if hum.FloorMaterial~=Enum.Material.Air and (target or rng:NextNumber()<.45) then hum.Jump=true end
	end

	if not lastPos then lastPos=root.Position end
	local moved=(root.Position-lastPos).Magnitude
	if moved<.10 then
		stuckSince=stuckSince or now
		if now-stuckSince>.75 then hum.Jump=true; roamGoal=nil; strafeSign*=-1; stuckSince=now end
	else
		stuckSince=nil
	end
	lastPos=root.Position
end

local function updateCamera(dt,char,root,head,target)
	camera.CameraType=Enum.CameraType.Scriptable
	player.CameraMode=Enum.CameraMode.LockFirstPerson
	hideLocalHead(char)
	local desiredLook
	if target and aliveEnemy(target) then
		local eroot=target:FindFirstChild("HumanoidRootPart")
		desiredLook=eroot and (eroot.Position+Vector3.new(0,1.05,0)) or (head.Position+root.CFrame.LookVector*20)
	else
		desiredLook=head.Position+root.CFrame.LookVector*35
	end

	bobClock+=dt*math.max(5,root.AssemblyLinearVelocity.Magnitude*.42)
	local moving=Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z).Magnitude
	local bobAmt=math.clamp(moving/18,0,1)
	local bob=Vector3.new(math.sin(bobClock)*.035*bobAmt,math.abs(math.cos(bobClock*.5))*.025*bobAmt,0)
	cameraRecoil=cameraRecoil*math.pow(.05,dt)
	local camPos=head.Position+Vector3.new(0,.05,0)+bob
	local base=CFrame.lookAt(camPos,desiredLook)
	local recoil=CFrame.Angles(-cameraRecoil,0,math.sin(bobClock*.5)*.003*bobAmt)
	camera.CFrame=camera.CFrame:Lerp(base*recoil,math.clamp(dt*12,0,1))

	if viewModel and weaponRoot then
		local swayX=math.sin(bobClock*.5)*.018*bobAmt
		local swayY=math.abs(math.cos(bobClock*.5))*.016*bobAmt
		local kick=cameraRecoil*1.7
		moveViewModel(camera.CFrame*CFrame.new(.22+swayX,-.50-swayY,-2.22+kick)*CFrame.Angles(math.rad(-1.5),math.rad(-1),math.rad(1.4)))
	end
end

local function onCharacter(char)
	clearViewModel(); roamGoal=nil; currentTarget=nil; lastPos=nil; stuckSince=nil; cameraRecoil=0
	local hum=char:WaitForChild("Humanoid",10)
	if hum then hum.AutoRotate=false end
	task.wait(.2)
	makeWeaponModel(currentWeapon)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then task.spawn(onCharacter,player.Character) end

RunService.Heartbeat:Connect(function()
	local char,hum,root=getCharacter()
	if not char then return end
	local target,dist=nearestEnemy(root)
	currentTarget=target
	if target and dist then
		if dist<=8.5 then swingSword(target) else fireGun(target) end
	elseif shownWeapon~=currentWeapon then
		makeWeaponModel(currentWeapon)
	end
	updateMovement(char,hum,root,target,dist)
end)

RunService:BindToRenderStep("ViewersVsMeFirstPerson",Enum.RenderPriority.Camera.Value+1,function(dt)
	local char,hum,root,head=getCharacter()
	if not char then return end
	updateCamera(dt,char,root,head,currentTarget)
end)

print("PLAYER AI V2 READY - first person, armed sprint movement, obstacle steering, Arsenal-style FPS weapons.")
