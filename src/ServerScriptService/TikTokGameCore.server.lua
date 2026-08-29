-- TikTokGameCore.server.lua
-- VIEWERS VS ME - ZOMBIE CORE V3.1
-- Smooth whole-rig ground emergence, outdoor-only spawning, and reliable gift boss/horde requests.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local ServerStorage=game:GetService("ServerStorage")
local PathfindingService=game:GetService("PathfindingService")
local TweenService=game:GetService("TweenService")
local Debris=game:GetService("Debris")

local rng=Random.new()

local function remote(name)
	local r=ReplicatedStorage:FindFirstChild(name)
	if r and not r:IsA("RemoteEvent") then r:Destroy();r=nil end
	if not r then r=Instance.new("RemoteEvent");r.Name=name;r.Parent=ReplicatedStorage end
	return r
end

local function bindable(name)
	local b=ServerStorage:FindFirstChild(name)
	if b and not b:IsA("BindableEvent") then b:Destroy();b=nil end
	if not b then b=Instance.new("BindableEvent");b.Name=name;b.Parent=ServerStorage end
	return b
end

local testRemote=remote("TikTokTestSpawn")
local streamRemote=remote("TikTokStreamEvent")
local attackRemote=remote("AutoCombatAttack")
local giftSpawn=bindable("GiftSpawnRequest")

local enemies=workspace:FindFirstChild("TikTokEnemies") or Instance.new("Folder")
enemies.Name="TikTokEnemies";enemies.Parent=workspace

local active=0
local kills=0

local function hostPlayer() return Players:GetPlayers()[1] end
local function hostCharacter() local p=hostPlayer();return p and p.Character end
local function stats() streamRemote:FireAllClients({kind="stats",kills=kills,active=active,wave=math.floor(kills/20)+1}) end

local rayParams=RaycastParams.new()
rayParams.FilterType=Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater=true

local overlapParams=OverlapParams.new()
overlapParams.FilterType=Enum.RaycastFilterType.Exclude
overlapParams.MaxParts=40

local function groundAt(raw)
	rayParams.FilterDescendantsInstances={enemies,hostCharacter()}
	local hit=workspace:Raycast(raw+Vector3.new(0,45,0),Vector3.new(0,-100,0),rayParams)
	if not hit then return nil end
	if hit.Normal.Y<.75 then return nil end
	return hit.Position,hit.Instance
end

local function openOutdoorSpot(pos,groundPart)
	overlapParams.FilterDescendantsInstances={enemies,hostCharacter(),groundPart}
	-- Reject anything occupying body space: walls, cars, props, interiors, etc.
	local bodyParts=workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.new(0,3.2,0)),Vector3.new(5.4,6.4,5.4),overlapParams)
	for _,p in ipairs(bodyParts) do
		if p:IsA("BasePart") and p.CanCollide and p.Transparency<.95 then
			return false
		end
	end
	-- Need sky/open vertical room above the emergence point.
	rayParams.FilterDescendantsInstances={enemies,hostCharacter(),groundPart}
	local roof=workspace:Raycast(pos+Vector3.new(0,1.5,0),Vector3.new(0,18,0),rayParams)
	if roof and roof.Instance and roof.Instance.CanCollide then return false end
	return true
end

local ROAD_LINES={-200,-100,0,100,200}
local function roadCandidatesAround(rootPos)
	local choices={}
	-- The V6/V7 city has broad roads centered on these grid lines. Spawn on those lanes first.
	for _,x in ipairs(ROAD_LINES) do
		for _,z in ipairs(ROAD_LINES) do
			-- intersections
			table.insert(choices,Vector3.new(x,rootPos.Y,z))
			-- road stretches between intersections
			for _,off in ipairs({-38,38}) do
				table.insert(choices,Vector3.new(x,rootPos.Y,z+off))
				table.insert(choices,Vector3.new(x+off,rootPos.Y,z))
			end
		end
	end
	for i=#choices,2,-1 do
		local j=rng:NextInteger(1,i);choices[i],choices[j]=choices[j],choices[i]
	end
	return choices
end

local function chooseSpawnPoint()
	local char=hostCharacter();local root=char and char:FindFirstChild("HumanoidRootPart")
	local origin=root and root.Position or Vector3.zero
	-- Prefer known road/plaza positions that are 24-95 studs away.
	for _,raw in ipairs(roadCandidatesAround(origin)) do
		local flat=Vector3.new(raw.X-origin.X,0,raw.Z-origin.Z).Magnitude
		if flat>=24 and flat<=95 then
			local ground,part=groundAt(raw)
			if ground and openOutdoorSpot(ground,part) then return ground end
		end
	end
	-- Fallback: ring sampling, but still require clearance + no roof.
	for _=1,50 do
		local a=rng:NextNumber(0,math.pi*2);local radius=rng:NextNumber(28,58)
		local raw=origin+Vector3.new(math.cos(a)*radius,0,math.sin(a)*radius)
		local ground,part=groundAt(raw)
		if ground and openOutdoorSpot(ground,part) then return ground end
	end
	-- Central plaza fallback is intentionally open in the city overhaul.
	local ground=select(1,groundAt(Vector3.new(0,origin.Y,0)))
	return ground or origin+Vector3.new(0,0,-32)
end

local palettes={
	{skin=Color3.fromRGB(105,125,91),torso=Color3.fromRGB(48,57,46),pants=Color3.fromRGB(31,34,34)},
	{skin=Color3.fromRGB(126,108,88),torso=Color3.fromRGB(60,48,43),pants=Color3.fromRGB(30,31,34)},
	{skin=Color3.fromRGB(92,112,104),torso=Color3.fromRGB(43,52,56),pants=Color3.fromRGB(27,29,33)},
	{skin=Color3.fromRGB(130,96,82),torso=Color3.fromRGB(62,42,39),pants=Color3.fromRGB(34,31,30)},
}

local function weldedDetail(model,part,name,size,offset,color,material)
	if not part then return end
	local d=Instance.new("Part");d.Name=name;d.Size=size;d.Color=color;d.Material=material or Enum.Material.SmoothPlastic
	d.CanCollide=false;d.CanTouch=false;d.CanQuery=false;d.Massless=true;d.CFrame=part.CFrame*offset;d.Parent=model
	local w=Instance.new("WeldConstraint");w.Part0=part;w.Part1=d;w.Parent=d
	return d
end

local function styleZombie(model,boss)
	local p=palettes[rng:NextInteger(1,#palettes)]
	for _,obj in ipairs(model:GetDescendants()) do
		if obj:IsA("Accessory") or obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic") then obj:Destroy()
		elseif obj:IsA("BasePart") then
			obj.Anchored=false;obj.Material=Enum.Material.SmoothPlastic
			if obj.Name=="Head" then obj.Color=boss and Color3.fromRGB(120,66,58) or p.skin
			elseif obj.Name:find("Torso") then obj.Color=boss and Color3.fromRGB(72,25,25) or p.torso
			elseif obj.Name:find("Arm") or obj.Name:find("Hand") then obj.Color=boss and Color3.fromRGB(110,57,52) or p.skin
			elseif obj.Name:find("Leg") or obj.Name:find("Foot") then obj.Color=p.pants end
		end
	end
	local head=model:FindFirstChild("Head")
	if head then
		local face=head:FindFirstChildOfClass("Decal");if face then face:Destroy() end
		weldedDetail(model,head,"EyeL",Vector3.new(.13,.13,.05),CFrame.new(-.18,.10,-.49),boss and Color3.fromRGB(255,65,45) or Color3.fromRGB(235,225,170),Enum.Material.Neon)
		weldedDetail(model,head,"EyeR",Vector3.new(.13,.13,.05),CFrame.new(.18,.10,-.49),boss and Color3.fromRGB(255,65,45) or Color3.fromRGB(235,225,170),Enum.Material.Neon)
		weldedDetail(model,head,"FaceDecay",Vector3.new(.25,.08,.04),CFrame.new(.10,-.16,-.50)*CFrame.Angles(0,0,math.rad(-18)),Color3.fromRGB(72,27,25))
	end
	local torso=model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if torso then
		weldedDetail(model,torso,"ChestDecay",Vector3.new(.60,.11,.05),CFrame.new(.18,.04,-.52)*CFrame.Angles(0,0,math.rad(22)),Color3.fromRGB(67,27,25))
	end
end

local function addName(model,name,boss)
	local head=model:FindFirstChild("Head");if not head then return end
	local gui=Instance.new("BillboardGui");gui.Name="ViewerTag";gui.Size=UDim2.fromOffset(boss and 220 or 170,32);gui.StudsOffset=Vector3.new(0,3.1,0);gui.AlwaysOnTop=true;gui.Parent=head
	local lbl=Instance.new("TextLabel");lbl.Size=UDim2.fromScale(1,1);lbl.BackgroundTransparency=1;lbl.Font=Enum.Font.GothamBlack;lbl.TextScaled=true;lbl.TextStrokeTransparency=.2;lbl.TextColor3=boss and Color3.fromRGB(255,75,60) or Color3.new(1,1,1);lbl.Text=boss and ("BOSS • @"..name) or ("@"..name);lbl.Parent=gui
end

local function addWalk(hum)
	local animator=hum:FindFirstChildOfClass("Animator") or Instance.new("Animator");animator.Parent=hum
	local anim=Instance.new("Animation");anim.AnimationId="rbxassetid://507777826"
	local ok,track=pcall(function() return animator:LoadAnimation(anim) end)
	if ok and track then
		track.Looped=true;track.Priority=Enum.AnimationPriority.Movement
		hum.Running:Connect(function(speed)
			if hum.Health<=0 then if track.IsPlaying then track:Stop(.05) end
			elseif speed>.5 then if not track.IsPlaying then track:Play(.12) end;track:AdjustSpeed(math.clamp(speed/8.5,.65,1.35))
			elseif track.IsPlaying then track:Stop(.15) end
		end)
	end
end

local function emergeFromGround(model,groundPos)
	local hum=model:FindFirstChildOfClass("Humanoid");local root=model:FindFirstChild("HumanoidRootPart");if not hum or not root then return end
	local target=CFrame.new(groundPos+Vector3.new(0,3.05,0))*CFrame.Angles(0,rng:NextNumber(-math.pi,math.pi),0)
	local start=target*CFrame.new(0,-5.4,0)*CFrame.Angles(math.rad(13),0,math.rad(rng:NextNumber(-5,5)))
	model:PivotTo(start)
	hum.WalkSpeed=0;hum.AutoRotate=false
	local saved={}
	for _,bp in ipairs(model:GetDescendants()) do
		if bp:IsA("BasePart") then saved[bp]=bp.CanCollide;bp.CanCollide=false end
	end
	local dirt=Instance.new("Part");dirt.Name="SpawnDirt";dirt.Anchored=true;dirt.CanCollide=false;dirt.CanTouch=false;dirt.CanQuery=false;dirt.Material=Enum.Material.Ground;dirt.Color=Color3.fromRGB(67,53,40);dirt.Size=Vector3.new(5.5,.16,5.5);dirt.CFrame=CFrame.new(groundPos+Vector3.new(0,.06,0));dirt.Parent=workspace
	local smoke=Instance.new("ParticleEmitter");smoke.Texture="rbxasset://textures/particles/smoke_main.dds";smoke.Rate=0;smoke.Lifetime=NumberRange.new(.45,.85);smoke.Speed=NumberRange.new(2.5,6);smoke.SpreadAngle=Vector2.new(180,180);smoke.Color=ColorSequence.new(Color3.fromRGB(95,77,57));smoke.Parent=dirt;smoke:Emit(28)
	-- Tween a CFrameValue and PivotTo the WHOLE model every update, so limbs never stretch away from the root.
	local driver=Instance.new("CFrameValue");driver.Value=start
	local conn=driver:GetPropertyChangedSignal("Value"):Connect(function() if model.Parent then model:PivotTo(driver.Value) end end)
	local tw=TweenService:Create(driver,TweenInfo.new(1.15,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Value=target})
	tw:Play();tw.Completed:Wait();conn:Disconnect();driver:Destroy()
	if not model.Parent then return end
	model:PivotTo(target);hum.AutoRotate=true
	for bp,was in pairs(saved) do if bp.Parent then bp.CanCollide=was end end
	Debris:AddItem(dirt,.55)
end

local function startChase(model)
	local hum=model:FindFirstChildOfClass("Humanoid");local root=model:FindFirstChild("HumanoidRootPart");if not hum or not root then return end
	task.spawn(function()
		local lastHit=0;local lastPath=0;local waypoints=nil;local idx=2;local lastPos=root.Position;local stuck=0
		while model.Parent and hum.Health>0 and not model:GetAttribute("Dead") do
			local char=hostCharacter();local th=char and char:FindFirstChildOfClass("Humanoid");local tr=char and char:FindFirstChild("HumanoidRootPart")
			if th and tr and th.Health>0 then
				local dist=(tr.Position-root.Position).Magnitude
				if os.clock()-lastPath>.65 or not waypoints or not waypoints[idx] then
					lastPath=os.clock();local path=PathfindingService:CreatePath({AgentRadius=2.2,AgentHeight=5.2,AgentCanJump=true,WaypointSpacing=5})
					local ok=pcall(function() path:ComputeAsync(root.Position,tr.Position) end)
					if ok and path.Status==Enum.PathStatus.Success then waypoints=path:GetWaypoints();idx=2 else waypoints=nil end
				end
				local goal=tr.Position
				if waypoints and waypoints[idx] then
					local wp=waypoints[idx];if (root.Position-wp.Position).Magnitude<3 then idx+=1;wp=waypoints[idx] end
					if wp then goal=wp.Position;if wp.Action==Enum.PathWaypointAction.Jump then hum.Jump=true end end
				end
				hum:MoveTo(goal)
				local moved=(root.Position-lastPos).Magnitude;if moved<.2 and dist>6 then stuck+=.12 else stuck=0 end;lastPos=root.Position
				if stuck>1.0 then hum.Jump=true;waypoints=nil;idx=2;hum:MoveTo(root.Position+Vector3.new(rng:NextNumber(-7,7),0,rng:NextNumber(-7,7)));stuck=0 end
				if dist<=4.8 and os.clock()-lastHit>1.35 then lastHit=os.clock();th:TakeDamage(model:GetAttribute("Boss") and 5 or 1.5) end
			end
			task.wait(.12)
		end
	end)
end

local function spawnZombie(sender,boss,forcedPos)
	local desc=Instance.new("HumanoidDescription")
	desc.BodyTypeScale=0;desc.ProportionScale=0;desc.HeightScale=boss and 1.23 or rng:NextNumber(.94,1.08);desc.WidthScale=boss and 1.16 or rng:NextNumber(.92,1.08);desc.DepthScale=boss and 1.10 or 1;desc.HeadScale=boss and 1.08 or rng:NextNumber(.95,1.05)
	local ok,model=pcall(function() return Players:CreateHumanoidModelFromDescriptionAsync(desc,Enum.HumanoidRigType.R15) end)
	if not ok or not model then warn("Zombie rig failed",model);return end
	model.Name=boss and ("Boss_"..sender) or ("Zombie_"..sender);model:SetAttribute("TikTokEnemy",true);model:SetAttribute("Boss",boss==true);model:SetAttribute("Dead",false);model.Parent=enemies
	local hum=model:FindFirstChildOfClass("Humanoid");local root=model:FindFirstChild("HumanoidRootPart");if not hum or not root then model:Destroy();return end
	styleZombie(model,boss);addName(model,sender,boss);addWalk(hum)
	hum.MaxHealth=boss and 850 or rng:NextInteger(110,145);hum.Health=hum.MaxHealth;hum.JumpPower=34;hum.AutoRotate=true;hum.PlatformStand=false;hum.Sit=false;hum.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
	local spawnPos=forcedPos or chooseSpawnPoint();model:PivotTo(CFrame.new(spawnPos+Vector3.new(0,3,0)))
	pcall(function() root:SetNetworkOwner(nil) end)
	active+=1;stats()
	task.spawn(function()
		emergeFromGround(model,spawnPos)
		if model.Parent and hum.Health>0 then hum.WalkSpeed=boss and 8.2 or rng:NextNumber(7.4,9.4);startChase(model) end
	end)
	hum.Died:Connect(function()
		if model:GetAttribute("Dead") then return end
		model:SetAttribute("Dead",true);hum.WalkSpeed=0;active=math.max(0,active-1);kills+=1;stats()
		for _,obj in ipairs(model:GetDescendants()) do if obj:IsA("BasePart") then obj.CanTouch=false;obj.CanCollide=false end end
		Debris:AddItem(model,1.5)
	end)
	return model
end

local function spawnGroup(sender,count,boss)
	count=math.clamp(tonumber(count) or 1,1,24)
	if boss then
		-- Boss gets one guaranteed outdoor location; escorts use separate clear points so they don't stack inside him.
		spawnZombie(sender,true,chooseSpawnPoint())
		for i=1,count do
			task.delay(.18*i,function() spawnZombie(sender.."_ESCORT_"..i,false,chooseSpawnPoint()) end)
		end
	else
		for i=1,count do task.delay(.10*(i-1),function() spawnZombie(sender.."_"..i,false,chooseSpawnPoint()) end) end
	end
end

testRemote.OnServerEvent:Connect(function(player,amount)
	amount=math.clamp(tonumber(amount) or 10,1,20);print("ZOMBIE TEST SPAWN:",player.Name,amount);spawnGroup("TEST_VIEWER",amount,false)
end)

giftSpawn.Event:Connect(function(sender,count,boss)
	sender=tostring(sender or "VIEWER")
	if boss then
		print("GIFT SPAWN: BOSS +",count,"escort from",sender)
		spawnGroup(sender,math.clamp(tonumber(count) or 6,1,12),true)
	else
		print("GIFT SPAWN:",count,"zombies from",sender)
		spawnGroup(sender,math.clamp(tonumber(count) or 1,1,24),false)
	end
end)

local weapons={Pistol={damage=20,range=100},SMG={damage=11,range=95},Shotgun={damage=30,range=65},Rifle={damage=31,range=145},Minigun={damage=8,range=120}}
attackRemote.OnServerEvent:Connect(function(player,target,weapon)
	if typeof(target)~="Instance" or not target:IsDescendantOf(enemies) then return end
	local char=player.Character;local pr=char and char:FindFirstChild("HumanoidRootPart");local eh=target:FindFirstChildOfClass("Humanoid");local er=target:FindFirstChild("HumanoidRootPart")
	if not pr or not eh or not er or eh.Health<=0 or target:GetAttribute("Dead") then return end
	local d=(pr.Position-er.Position).Magnitude
	if weapon=="Sword" then if d<=10 then eh:TakeDamage(40) end;return end
	local cfg=weapons[weapon];if cfg and d<=cfg.range+10 then eh:TakeDamage(cfg.damage) end
end)

print("ZOMBIE CORE V3.1 READY - outdoor spawn clearance + reliable boss escorts.")