-- AutoCombat.client.lua
-- VIEWERS VS ME - PLAYER AI V2.3
-- Autonomous FPS combat + obstacle avoidance + timed TikTok gift weapons.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Debris=game:GetService("Debris")
local PathfindingService=game:GetService("PathfindingService")

local player=Players.LocalPlayer
local camera=workspace.CurrentCamera
local enemies=workspace:WaitForChild("TikTokEnemies")
local attackRemote=ReplicatedStorage:WaitForChild("AutoCombatAttack")
local rng=Random.new()

local Weapons={
	Pistol={range=100,cooldown=.32,color=Color3.fromRGB(255,200,80),pellets=1,spread=.45,kick=.065},
	SMG={range=95,cooldown=.10,color=Color3.fromRGB(70,205,255),pellets=1,spread=1.1,kick=.035},
	Shotgun={range=65,cooldown=.72,color=Color3.fromRGB(255,135,65),pellets=7,spread=4.5,kick=.14},
	Rifle={range=145,cooldown=.22,color=Color3.fromRGB(105,255,150),pellets=1,spread=.30,kick=.06},
	Minigun={range=120,cooldown=.055,color=Color3.fromRGB(255,75,75),pellets=1,spread=1.8,kick=.025},
	Sword={range=10,cooldown=.48,color=Color3.fromRGB(90,220,255),kick=.10},
}

local currentWeapon="Rifle"
local shownWeapon=nil
local currentTarget=nil
local lastShot,lastSword=0,0
local strafeSign=1
local nextStrafeFlip=0
local roamGoal=nil
local roamExpire=0
local pathWaypoints=nil
local pathIndex=1
local nextPathRefresh=0
local lastMovePos=nil
local lastMoveSample=0
local stuckFor=0
local recoil=0
local bobTime=0
local aimPoint=nil
local viewModel=nil
local weaponRoot=nil
local muzzlePart=nil

local rayParams=RaycastParams.new();rayParams.FilterType=Enum.RaycastFilterType.Exclude;rayParams.IgnoreWater=true

local function getCharacter()
	local char=player.Character;if not char then return end
	local hum=char:FindFirstChildOfClass("Humanoid");local root=char:FindFirstChild("HumanoidRootPart");local head=char:FindFirstChild("Head")
	if not hum or not root or not head or hum.Health<=0 then return end
	return char,hum,root,head
end

local function aliveEnemy(m)
	if not m or not m.Parent or m:GetAttribute("Dead")==true then return false end
	local h=m:FindFirstChildOfClass("Humanoid");local r=m:FindFirstChild("HumanoidRootPart")
	return h and r and h.Health>0
end

local function nearestEnemy(root)
	local best,bestD
	for _,m in ipairs(enemies:GetChildren()) do
		if aliveEnemy(m) then local er=m:FindFirstChild("HumanoidRootPart");local d=(er.Position-root.Position).Magnitude;if not bestD or d<bestD then best,bestD=m,d end end
	end
	return best,bestD
end

local function hideLocalCharacter(char)
	for _,obj in ipairs(char:GetDescendants()) do if obj:IsA("BasePart") and (obj.Name=="Head" or obj.Parent:IsA("Accessory")) then obj.LocalTransparencyModifier=1 end end
end

local function giftGun()
	local name=player:GetAttribute("GiftWeapon")
	local untilTime=player:GetAttribute("GiftWeaponUntil") or 0
	if type(name)=="string" and Weapons[name] and name~="Sword" and untilTime>workspace:GetServerTimeNow() then return name end
	return "Rifle"
end

local function newPart(model,name,size,color,material,relative)
	local p=Instance.new("Part");p.Name=name;p.Size=size;p.Color=color;p.Material=material or Enum.Material.Metal;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.CFrame=relative or CFrame.new();p.Parent=model;return p
end

local function clearViewModel()
	if viewModel then viewModel:Destroy() end
	viewModel=nil;weaponRoot=nil;muzzlePart=nil;shownWeapon=nil
end

local function addArms(model)
	local sleeve=Color3.fromRGB(33,38,48);local glove=Color3.fromRGB(16,18,23)
	newPart(model,"RightArm",Vector3.new(.44,.44,1.18),sleeve,Enum.Material.Fabric,CFrame.new(.72,-.63,.45)*CFrame.Angles(math.rad(-16),0,math.rad(-10)))
	newPart(model,"RightGlove",Vector3.new(.36,.34,.62),glove,Enum.Material.SmoothPlastic,CFrame.new(.52,-.40,-.10)*CFrame.Angles(math.rad(-9),0,math.rad(-8)))
	newPart(model,"LeftArm",Vector3.new(.44,.44,1.16),sleeve,Enum.Material.Fabric,CFrame.new(-.62,-.67,.20)*CFrame.Angles(math.rad(-18),0,math.rad(12)))
	newPart(model,"LeftGlove",Vector3.new(.36,.34,.60),glove,Enum.Material.SmoothPlastic,CFrame.new(-.43,-.39,-.38)*CFrame.Angles(math.rad(-11),0,math.rad(9)))
end

local function makeWeaponModel(name)
	clearViewModel();shownWeapon=name
	local model=Instance.new("Model");model.Name="FPSViewModel";model.Parent=camera;viewModel=model
	weaponRoot=newPart(model,"Root",Vector3.new(.05,.05,.05),Color3.new(),Enum.Material.SmoothPlastic,CFrame.new());weaponRoot.Transparency=1;model.PrimaryPart=weaponRoot;addArms(model)
	local black=Color3.fromRGB(10,12,16);local dark=Color3.fromRGB(25,29,36);local steel=Color3.fromRGB(78,88,102);local light=Color3.fromRGB(132,142,158);local red=Color3.fromRGB(235,48,60);local cyan=Color3.fromRGB(65,210,255);local gold=Color3.fromRGB(230,175,55)

	if name=="Sword" then
		newPart(model,"Grip",Vector3.new(.25,.25,1.05),black,Enum.Material.SmoothPlastic,CFrame.new(.38,-.22,-.08)*CFrame.Angles(math.rad(90),0,0));newPart(model,"Guard",Vector3.new(1.15,.14,.24),steel,Enum.Material.Metal,CFrame.new(.38,.02,-.42));newPart(model,"Blade",Vector3.new(.10,.12,3.75),Color3.fromRGB(205,214,228),Enum.Material.Metal,CFrame.new(.38,.04,-2.35));newPart(model,"Edge",Vector3.new(.026,.135,3.55),cyan,Enum.Material.Neon,CFrame.new(.445,.04,-2.35));newPart(model,"Accent",Vector3.new(.026,.13,1.45),red,Enum.Material.Neon,CFrame.new(.315,.04,-1.85));return
	elseif name=="Pistol" then
		newPart(model,"Slide",Vector3.new(.44,.34,1.55),steel,Enum.Material.Metal,CFrame.new(.28,.03,-.65));newPart(model,"Frame",Vector3.new(.39,.31,1.02),dark,Enum.Material.Metal,CFrame.new(.28,-.22,-.48));newPart(model,"Grip",Vector3.new(.35,.78,.40),black,Enum.Material.SmoothPlastic,CFrame.new(.28,-.68,-.02)*CFrame.Angles(math.rad(-13),0,0));newPart(model,"Barrel",Vector3.new(.12,.12,.62),light,Enum.Material.Metal,CFrame.new(.28,.03,-1.72));newPart(model,"Sight",Vector3.new(.09,.11,.09),gold,Enum.Material.Neon,CFrame.new(.28,.25,-1.18));muzzlePart=newPart(model,"Muzzle",Vector3.new(.09,.09,.09),Weapons.Pistol.color,Enum.Material.Neon,CFrame.new(.28,.03,-2.07))
	elseif name=="SMG" then
		newPart(model,"Receiver",Vector3.new(.50,.52,1.48),dark,Enum.Material.Metal,CFrame.new(.12,-.03,-.65));newPart(model,"Upper",Vector3.new(.46,.20,1.36),steel,Enum.Material.Metal,CFrame.new(.12,.30,-.72));newPart(model,"Mag",Vector3.new(.31,.82,.39),black,Enum.Material.Metal,CFrame.new(.12,-.64,-.55)*CFrame.Angles(math.rad(-8),0,0));newPart(model,"Foregrip",Vector3.new(.25,.58,.27),black,Enum.Material.SmoothPlastic,CFrame.new(.12,-.43,-1.46));newPart(model,"Stock",Vector3.new(.38,.40,1.0),black,Enum.Material.SmoothPlastic,CFrame.new(.12,-.04,.50));newPart(model,"Barrel",Vector3.new(.13,.13,1.10),light,Enum.Material.Metal,CFrame.new(.12,.02,-2.35));newPart(model,"SideGlow",Vector3.new(.025,.16,1.0),cyan,Enum.Material.Neon,CFrame.new(.385,.07,-.68));muzzlePart=newPart(model,"Muzzle",Vector3.new(.10,.10,.10),Weapons.SMG.color,Enum.Material.Neon,CFrame.new(.12,.02,-2.95))
	elseif name=="Shotgun" then
		newPart(model,"Receiver",Vector3.new(.54,.56,1.38),dark,Enum.Material.Metal,CFrame.new(.08,-.02,-.55));newPart(model,"Stock",Vector3.new(.50,.58,1.45),Color3.fromRGB(72,46,31),Enum.Material.Wood,CFrame.new(.08,-.07,.92));newPart(model,"Barrel",Vector3.new(.17,.17,2.75),light,Enum.Material.Metal,CFrame.new(.08,.07,-2.45));newPart(model,"Tube",Vector3.new(.15,.15,2.35),dark,Enum.Material.Metal,CFrame.new(.08,-.19,-2.30));newPart(model,"Pump",Vector3.new(.49,.43,.92),Color3.fromRGB(94,60,38),Enum.Material.Wood,CFrame.new(.08,-.15,-1.62));newPart(model,"ShellAccent",Vector3.new(.025,.08,.85),Color3.fromRGB(255,90,45),Enum.Material.Neon,CFrame.new(.365,.18,-.48));muzzlePart=newPart(model,"Muzzle",Vector3.new(.11,.11,.11),Weapons.Shotgun.color,Enum.Material.Neon,CFrame.new(.08,.07,-3.87))
	elseif name=="Minigun" then
		newPart(model,"Housing",Vector3.new(.82,.78,1.55),dark,Enum.Material.Metal,CFrame.new(.05,-.04,-.65));newPart(model,"Rear",Vector3.new(.88,.84,.76),black,Enum.Material.Metal,CFrame.new(.05,-.04,.48));newPart(model,"Grip",Vector3.new(.31,.72,.29),black,Enum.Material.SmoothPlastic,CFrame.new(.05,-.68,-.25));local offs={{.20,.20},{-.20,.20},{.20,-.20},{-.20,-.20},{0,.28},{0,-.28}};for i,o in ipairs(offs) do newPart(model,"Barrel"..i,Vector3.new(.105,.105,2.55),light,Enum.Material.Metal,CFrame.new(.05+o[1],o[2]-0.02,-2.75)) end;newPart(model,"PowerGlow",Vector3.new(.03,.28,1.08),red,Enum.Material.Neon,CFrame.new(.48,-.02,-.62));muzzlePart=newPart(model,"Muzzle",Vector3.new(.12,.12,.12),Weapons.Minigun.color,Enum.Material.Neon,CFrame.new(.05,-.02,-4.06))
	else -- Rifle
		newPart(model,"Receiver",Vector3.new(.56,.58,1.58),dark,Enum.Material.Metal,CFrame.new(.05,-.02,-.15));newPart(model,"Upper",Vector3.new(.52,.28,1.95),steel,Enum.Material.Metal,CFrame.new(.05,.31,-.33));newPart(model,"Handguard",Vector3.new(.50,.48,1.95),Color3.fromRGB(38,43,52),Enum.Material.Metal,CFrame.new(.05,.02,-1.92));newPart(model,"Stock",Vector3.new(.52,.58,1.25),black,Enum.Material.SmoothPlastic,CFrame.new(.05,-.02,1.25));newPart(model,"Grip",Vector3.new(.32,.78,.36),black,Enum.Material.SmoothPlastic,CFrame.new(.05,-.62,.22)*CFrame.Angles(math.rad(-13),0,0));newPart(model,"Mag",Vector3.new(.38,.98,.48),black,Enum.Material.Metal,CFrame.new(.05,-.72,-.42)*CFrame.Angles(math.rad(-9),0,0));newPart(model,"Barrel",Vector3.new(.14,.14,1.72),light,Enum.Material.Metal,CFrame.new(.05,.01,-3.72));newPart(model,"MuzzleBrake",Vector3.new(.25,.25,.44),black,Enum.Material.Metal,CFrame.new(.05,.01,-4.77));newPart(model,"OpticMount",Vector3.new(.42,.11,.72),black,Enum.Material.Metal,CFrame.new(.05,.54,-.58));newPart(model,"OpticBody",Vector3.new(.50,.42,.66),black,Enum.Material.Metal,CFrame.new(.05,.73,-.58));newPart(model,"OpticLens",Vector3.new(.27,.25,.04),cyan,Enum.Material.Neon,CFrame.new(.05,.73,-.93));newPart(model,"SideAccent",Vector3.new(.025,.22,1.34),red,Enum.Material.Neon,CFrame.new(.342,.10,-.24));for i=0,6 do newPart(model,"Rail"..i,Vector3.new(.42,.055,.12),black,Enum.Material.Metal,CFrame.new(.05,.43,-.84-i*.27)) end;muzzlePart=newPart(model,"Muzzle",Vector3.new(.10,.10,.10),Weapons.Rifle.color,Enum.Material.Neon,CFrame.new(.05,.01,-5.02))
	end
	if muzzlePart then muzzlePart.Transparency=1 end
end

local function tracer(a,b,color)
	local d=b-a;local dist=d.Magnitude;if dist<.05 then return end
	local p=Instance.new("Part");p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Material=Enum.Material.Neon;p.Color=color;p.Size=Vector3.new(.045,.045,dist);p.CFrame=CFrame.lookAt((a+b)/2,b);p.Parent=workspace;Debris:AddItem(p,.045)
end
local function muzzleFlash() if muzzlePart then muzzlePart.Transparency=0;task.delay(.035,function() if muzzlePart then muzzlePart.Transparency=1 end end) end end

local function obstacleAhead(root,dir,dist)
	if dir.Magnitude<.05 then return nil end
	rayParams.FilterDescendantsInstances={player.Character,enemies}
	for _,o in ipairs({root.Position+Vector3.new(0,.35,0),root.Position+Vector3.new(0,1.3,0),root.Position+Vector3.new(0,2.7,0)}) do local hit=workspace:Raycast(o,dir.Unit*dist,rayParams);if hit and hit.Instance and hit.Instance.CanCollide then return hit end end
end
local function floorExists(pos) rayParams.FilterDescendantsInstances={player.Character,enemies};return workspace:Raycast(pos+Vector3.new(0,3,0),Vector3.new(0,-9,0),rayParams)~=nil end
local function steerAround(root,desired)
	if desired.Magnitude<.05 then return Vector3.zero end
	local flat=Vector3.new(desired.X,0,desired.Z);if flat.Magnitude<.05 then return Vector3.zero end;flat=flat.Unit
	if not obstacleAhead(root,flat,9) then return flat end
	local right=Vector3.new(-flat.Z,0,flat.X)
	for _,c in ipairs({(flat+right*.9).Unit,(flat-right*.9).Unit,right,-right,-flat}) do if not obstacleAhead(root,c,7.5) and floorExists(root.Position+c*5.5) then return c end end
	return -flat
end

local function computePath(root,goal)
	local path=PathfindingService:CreatePath({AgentRadius=2.2,AgentHeight=5.2,AgentCanJump=true,AgentCanClimb=false,WaypointSpacing=4.5});local ok=pcall(function() path:ComputeAsync(root.Position,goal) end)
	if ok and path.Status==Enum.PathStatus.Success then pathWaypoints=path:GetWaypoints();pathIndex=2 else pathWaypoints=nil;pathIndex=1 end
end
local function pathDirection(root,goal)
	if os.clock()>nextPathRefresh then nextPathRefresh=os.clock()+.62;computePath(root,goal) end
	if pathWaypoints and pathWaypoints[pathIndex] then local wp=pathWaypoints[pathIndex];if (root.Position-wp.Position).Magnitude<3 then pathIndex+=1;wp=pathWaypoints[pathIndex] end;if wp then local _,hum=getCharacter();if hum and wp.Action==Enum.PathWaypointAction.Jump then hum.Jump=true end;return wp.Position-root.Position end end
	return goal-root.Position
end
local function chooseRoamGoal(root)
	for _=1,12 do local a=rng:NextNumber(0,math.pi*2);local d=rng:NextNumber(18,42);local p=root.Position+Vector3.new(math.cos(a)*d,0,math.sin(a)*d);if floorExists(p) and not obstacleAhead(root,p-root.Position,6) then roamGoal=p;roamExpire=os.clock()+rng:NextNumber(3.5,6.5);nextPathRefresh=0;return end end
	roamGoal=root.Position+Vector3.new(rng:NextNumber(-12,12),0,rng:NextNumber(-12,12));roamExpire=os.clock()+3
end

local function shoot(target)
	local cfg=Weapons[currentWeapon];if not cfg or os.clock()-lastShot<cfg.cooldown then return end
	local er=target and target:FindFirstChild("HumanoidRootPart");if not er then return end
	lastShot=os.clock();recoil=math.min(.18,recoil+cfg.kick);muzzleFlash();local origin=camera.CFrame.Position+camera.CFrame.LookVector*1.2
	for _=1,cfg.pellets do local aim=er.Position+Vector3.new((rng:NextNumber()-.5)*cfg.spread,1+(rng:NextNumber()-.5)*cfg.spread*.25,(rng:NextNumber()-.5)*cfg.spread);tracer(origin,aim,cfg.color) end
	attackRemote:FireServer(target,currentWeapon)
end
local function sword(target) if os.clock()-lastSword<Weapons.Sword.cooldown then return end;lastSword=os.clock();recoil=.11;attackRemote:FireServer(target,"Sword") end

player.CameraMode=Enum.CameraMode.LockFirstPerson

RunService.RenderStepped:Connect(function(dt)
	local char,hum,root,head=getCharacter();if not char then return end
	hideLocalCharacter(char)
	local target,dist=nearestEnemy(root);currentTarget=target;local desiredMove=Vector3.zero

	if target and aliveEnemy(target) then
		local er=target:FindFirstChild("HumanoidRootPart")
		if er then
			local predicted=er.Position+er.AssemblyLinearVelocity*.15+Vector3.new(0,1.25,0);aimPoint=aimPoint and aimPoint:Lerp(predicted,math.clamp(dt*5.5,0,1)) or predicted
			local flatTo=Vector3.new(er.Position.X-root.Position.X,0,er.Position.Z-root.Position.Z)
			if os.clock()>nextStrafeFlip then strafeSign*=-1;nextStrafeFlip=os.clock()+rng:NextNumber(1.0,2.4) end
			local right=flatTo.Magnitude>0 and Vector3.new(-flatTo.Z,0,flatTo.X).Unit or Vector3.xAxis
			if dist>31 then desiredMove=flatTo.Unit elseif dist<10 then desiredMove=(-flatTo.Unit+right*.35*strafeSign).Unit else desiredMove=(right*strafeSign+flatTo.Unit*.12).Unit end
			desiredMove=steerAround(root,desiredMove)
			if obstacleAhead(root,desiredMove,8) then desiredMove=steerAround(root,pathDirection(root,root.Position+desiredMove*14)) end
			hum.WalkSpeed=20;hum:Move(desiredMove,false)
			if dist<=8.5 then currentWeapon="Sword";sword(target) else currentWeapon=giftGun();shoot(target) end
		end
	else
		currentWeapon=giftGun();aimPoint=nil
		if not roamGoal or os.clock()>roamExpire or (root.Position-roamGoal).Magnitude<4 then chooseRoamGoal(root) end
		desiredMove=steerAround(root,pathDirection(root,roamGoal));hum.WalkSpeed=18;hum:Move(desiredMove,false)
	end

	if shownWeapon~=currentWeapon then makeWeaponModel(currentWeapon) end
	if os.clock()-lastMoveSample>.20 then
		lastMoveSample=os.clock();if lastMovePos then local moved=(root.Position-lastMovePos).Magnitude;if desiredMove.Magnitude>.2 and moved<.16 then stuckFor+=.20 else stuckFor=math.max(0,stuckFor-.25) end;if stuckFor>.85 then hum.Jump=true;strafeSign*=-1;roamGoal=nil;pathWaypoints=nil;nextPathRefresh=0;stuckFor=0 end end;lastMovePos=root.Position
	end

	local lookTarget=aimPoint or (root.Position+root.CFrame.LookVector*30+Vector3.new(0,1.4,0));local camPos=head.Position+Vector3.new(0,.15,0);local desiredCam=CFrame.lookAt(camPos,lookTarget);camera.CFrame=camera.CFrame:Lerp(desiredCam,math.clamp(dt*(aimPoint and 5.2 or 3.2),0,1));root.CFrame=root.CFrame:Lerp(CFrame.lookAt(root.Position,Vector3.new(camera.CFrame.LookVector.X+root.Position.X,root.Position.Y,camera.CFrame.LookVector.Z+root.Position.Z)),math.clamp(dt*5,0,1))
	bobTime+=dt*(hum.MoveDirection.Magnitude>.1 and 8.5 or 2);recoil*=math.max(0,1-dt*10)
	if viewModel and weaponRoot then local bobX=math.sin(bobTime)*.018*hum.MoveDirection.Magnitude;local bobY=math.abs(math.cos(bobTime))*-.022*hum.MoveDirection.Magnitude;viewModel:PivotTo(camera.CFrame*CFrame.new(.46+bobX,-.62+bobY,-1.25+recoil)*CFrame.Angles(math.rad(-4-recoil*50),math.rad(-2),math.rad(-1))) end
end)

player.CharacterAdded:Connect(function() task.wait(.5);clearViewModel();roamGoal=nil;pathWaypoints=nil;aimPoint=nil end)
print("PLAYER AI V2.3 READY - gift weapons + distinct viewmodels enabled.")