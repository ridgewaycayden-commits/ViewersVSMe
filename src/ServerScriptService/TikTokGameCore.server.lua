-- TikTokGameCore.server.lua
-- VIEWERS VS ME - ZOMBIE CORE V3.5
-- City Fight safe street spawns, smooth emergence, path chase, gift/test hordes, occluded viewer tags.

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

local active,kills=0,0
local function hostPlayer() return Players:GetPlayers()[1] end
local function hostCharacter() local p=hostPlayer();return p and p.Character end
local function stats() streamRemote:FireAllClients({kind="stats",kills=kills,active=active,wave=math.floor(kills/20)+1}) end

local rayParams=RaycastParams.new();rayParams.FilterType=Enum.RaycastFilterType.Exclude;rayParams.IgnoreWater=true
local overlapParams=OverlapParams.new();overlapParams.FilterType=Enum.RaycastFilterType.Exclude;overlapParams.MaxParts=75

local function groundAt(raw)
	rayParams.FilterDescendantsInstances={enemies,hostCharacter()}
	local hit=workspace:Raycast(raw+Vector3.new(0,70,0),Vector3.new(0,-160,0),rayParams)
	if not hit or hit.Normal.Y<.82 then return nil end
	return hit.Position,hit.Instance
end

local bannedWords={
	"roof","car","truck","vehicle","bus","police","crate","box","container","awning","table","bench","chair","dumpster","trash","prop","sign","fence","wall","window","door","tree","lamp","light","hydrant","barrier","railing","stairs","stair","balcony","porch","deck","scaffold","statue","planter"
}

local function badSurface(part)
	if not part or not part:IsA("BasePart") then return true end
	if not part.CanCollide or part.Transparency>=.98 then return true end
	local cur=part
	for _=1,6 do
		if not cur then break end
		local n=string.lower(cur.Name or "")
		for _,word in ipairs(bannedWords) do if n:find(word,1,true) then return true end end
		cur=cur.Parent
	end
	return false
end

local function openOutdoorSpot(pos,groundPart)
	if badSurface(groundPart) then return false end
	overlapParams.FilterDescendantsInstances={enemies,hostCharacter(),groundPart}
	for _,p in ipairs(workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.new(0,3.4,0)),Vector3.new(6.5,6.8,6.5),overlapParams)) do
		if p:IsA("BasePart") and p.CanCollide and p.Transparency<.95 then return false end
	end
	rayParams.FilterDescendantsInstances={enemies,hostCharacter(),groundPart}
	local roof=workspace:Raycast(pos+Vector3.new(0,1.5,0),Vector3.new(0,28,0),rayParams)
	return not (roof and roof.Instance and roof.Instance.CanCollide)
end

local function isStreetLevelSpot(pos,groundPart,origin)
	-- HRP is normally ~3 studs above the street, so this keeps spawns on the same city level.
	if math.abs(pos.Y-origin.Y)>5.5 then return false end
	if badSurface(groundPart) then return false end

	-- Require a broad flat patch so tiny props, car roofs, curbs and ledges fail.
	local offsets={
		Vector3.new(3.5,0,0),Vector3.new(-3.5,0,0),Vector3.new(0,0,3.5),Vector3.new(0,0,-3.5),
		Vector3.new(2.5,0,2.5),Vector3.new(-2.5,0,2.5),Vector3.new(2.5,0,-2.5),Vector3.new(-2.5,0,-2.5)
	}
	for _,off in ipairs(offsets) do
		local near,part=groundAt(pos+off)
		if not near or badSurface(part) or math.abs(near.Y-pos.Y)>1.0 then return false end
	end
	return true
end

local function reachableFromPlayer(pos,origin)
	local path=PathfindingService:CreatePath({AgentRadius=2.3,AgentHeight=5.4,AgentCanJump=true,AgentCanClimb=false,WaypointSpacing=5})
	local ok=pcall(function() path:ComputeAsync(pos+Vector3.new(0,2.5,0),origin) end)
	return ok and path.Status==Enum.PathStatus.Success and #path:GetWaypoints()>=2
end

local function validSpawn(raw,origin,requirePath)
	local ground,groundPart=groundAt(raw)
	if not ground then return nil end
	if not openOutdoorSpot(ground,groundPart) then return nil end
	if not isStreetLevelSpot(ground,groundPart,origin) then return nil end
	if requirePath and not reachableFromPlayer(ground,origin) then return nil end
	return ground
end

local function chooseSpawnPoint()
	local char=hostCharacter();local root=char and char:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local origin=root.Position

	-- Main ring: far enough to feel natural, but only on verified open street/sidewalk ground.
	for _=1,180 do
		local angle=rng:NextNumber(0,math.pi*2)
		local radius=rng:NextNumber(34,78)
		local raw=origin+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
		local ground=validSpawn(raw,origin,true)
		if ground then return ground end
	end

	-- Crowded-map fallback remains strict and still requires a valid path.
	for _=1,140 do
		local angle=rng:NextNumber(0,math.pi*2)
		local radius=rng:NextNumber(20,44)
		local raw=origin+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
		local ground=validSpawn(raw,origin,true)
		if ground then return ground end
	end

	-- Never force a zombie onto a roof/prop just because no good location was found.
	warn("ZOMBIE SPAWN SKIPPED - no verified street-level spot found")
	return nil
end

local palettes={
	{skin=Color3.fromRGB(105,125,91),torso=Color3.fromRGB(48,57,46),pants=Color3.fromRGB(31,34,34)},
	{skin=Color3.fromRGB(126,108,88),torso=Color3.fromRGB(60,48,43),pants=Color3.fromRGB(30,31,34)},
	{skin=Color3.fromRGB(92,112,104),torso=Color3.fromRGB(43,52,56),pants=Color3.fromRGB(27,29,33)},
	{skin=Color3.fromRGB(130,96,82),torso=Color3.fromRGB(62,42,39),pants=Color3.fromRGB(34,31,30)},
}

local function weldedDetail(model,base,name,size,offset,color,material)
	if not base then return end
	local p=Instance.new("Part");p.Name=name;p.Size=size;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Massless=true;p.CFrame=base.CFrame*offset;p.Parent=model
	local w=Instance.new("WeldConstraint");w.Part0=base;w.Part1=p;w.Parent=p;return p
end

local function styleZombie(model,boss)
	local pal=palettes[rng:NextInteger(1,#palettes)]
	for _,o in ipairs(model:GetDescendants()) do
		if o:IsA("Accessory") or o:IsA("Shirt") or o:IsA("Pants") or o:IsA("ShirtGraphic") then o:Destroy()
		elseif o:IsA("BasePart") then
			o.Anchored=false;o.Material=Enum.Material.SmoothPlastic
			if o.Name=="Head" then o.Color=boss and Color3.fromRGB(120,66,58) or pal.skin
			elseif o.Name:find("Torso") then o.Color=boss and Color3.fromRGB(72,25,25) or pal.torso
			elseif o.Name:find("Arm") or o.Name:find("Hand") then o.Color=boss and Color3.fromRGB(110,57,52) or pal.skin
			elseif o.Name:find("Leg") or o.Name:find("Foot") then o.Color=pal.pants end
		end
	end
	local head=model:FindFirstChild("Head")
	if head then
		local face=head:FindFirstChildOfClass("Decal");if face then face:Destroy() end
		weldedDetail(model,head,"EyeL",Vector3.new(.13,.13,.05),CFrame.new(-.18,.1,-.49),boss and Color3.fromRGB(255,65,45) or Color3.fromRGB(235,225,170),Enum.Material.Neon)
		weldedDetail(model,head,"EyeR",Vector3.new(.13,.13,.05),CFrame.new(.18,.1,-.49),boss and Color3.fromRGB(255,65,45) or Color3.fromRGB(235,225,170),Enum.Material.Neon)
		weldedDetail(model,head,"FaceDecay",Vector3.new(.25,.08,.04),CFrame.new(.1,-.16,-.5)*CFrame.Angles(0,0,math.rad(-18)),Color3.fromRGB(72,27,25))
	end
	local torso=model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if torso then weldedDetail(model,torso,"ChestDecay",Vector3.new(.6,.11,.05),CFrame.new(.18,.04,-.52)*CFrame.Angles(0,0,math.rad(22)),Color3.fromRGB(67,27,25)) end
end

local function addName(model,name,boss)
	local head=model:FindFirstChild("Head");if not head then return end
	local gui=Instance.new("BillboardGui");gui.Name="ViewerTag";gui.Size=UDim2.fromOffset(boss and 220 or 170,32);gui.StudsOffset=Vector3.new(0,3.1,0);gui.AlwaysOnTop=false;gui.MaxDistance=boss and 140 or 95;gui.LightInfluence=0;gui.Parent=head
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
	model:PivotTo(start);hum.WalkSpeed=0;hum.AutoRotate=false
	local saved={};for _,bp in ipairs(model:GetDescendants()) do if bp:IsA("BasePart") then saved[bp]=bp.CanCollide;bp.CanCollide=false end end
	local dirt=Instance.new("Part");dirt.Name="SpawnDirt";dirt.Anchored=true;dirt.CanCollide=false;dirt.CanTouch=false;dirt.CanQuery=false;dirt.Material=Enum.Material.Ground;dirt.Color=Color3.fromRGB(67,53,40);dirt.Size=Vector3.new(5.5,.16,5.5);dirt.CFrame=CFrame.new(groundPos+Vector3.new(0,.06,0));dirt.Parent=workspace
	local smoke=Instance.new("ParticleEmitter");smoke.Texture="rbxasset://textures/particles/smoke_main.dds";smoke.Rate=0;smoke.Lifetime=NumberRange.new(.45,.85);smoke.Speed=NumberRange.new(2.5,6);smoke.SpreadAngle=Vector2.new(180,180);smoke.Color=ColorSequence.new(Color3.fromRGB(95,77,57));smoke.Parent=dirt;smoke:Emit(28)
	local driver=Instance.new("CFrameValue");driver.Value=start
	local conn=driver:GetPropertyChangedSignal("Value"):Connect(function() if model.Parent then model:PivotTo(driver.Value) end end)
	local tw=TweenService:Create(driver,TweenInfo.new(1.15,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Value=target});tw:Play();tw.Completed:Wait();conn:Disconnect();driver:Destroy()
	if not model.Parent then return end
	model:PivotTo(target);hum.AutoRotate=true;for bp,was in pairs(saved) do if bp.Parent then bp.CanCollide=was end end;Debris:AddItem(dirt,.55)
end

local function startChase(model)
	local hum=model:FindFirstChildOfClass("Humanoid");local root=model:FindFirstChild("HumanoidRootPart");if not hum or not root then return end
	task.spawn(function()
		local lastHit,lastPath=0,0;local waypoints=nil;local idx=2;local lastPos=root.Position;local stuck=0
		while model.Parent and hum.Health>0 and not model:GetAttribute("Dead") do
			local char=hostCharacter();local th=char and char:FindFirstChildOfClass("Humanoid");local tr=char and char:FindFirstChild("HumanoidRootPart")
			if th and tr and th.Health>0 then
				local dist=(tr.Position-root.Position).Magnitude
				if os.clock()-lastPath>.55 or not waypoints or not waypoints[idx] then
					lastPath=os.clock();local path=PathfindingService:CreatePath({AgentRadius=2.1,AgentHeight=5.2,AgentCanJump=true,WaypointSpacing=4})
					local ok=pcall(function() path:ComputeAsync(root.Position,tr.Position) end);if ok and path.Status==Enum.PathStatus.Success then waypoints=path:GetWaypoints();idx=2 else waypoints=nil end
				end
				local goal=tr.Position
				if waypoints and waypoints[idx] then local wp=waypoints[idx];if (root.Position-wp.Position).Magnitude<3 then idx+=1;wp=waypoints[idx] end;if wp then goal=wp.Position;if wp.Action==Enum.PathWaypointAction.Jump then hum.Jump=true end end end
				hum:MoveTo(goal)
				local moved=(root.Position-lastPos).Magnitude;if moved<.18 and dist>6 then stuck+=.12 else stuck=0 end;lastPos=root.Position
				if stuck>1 then hum.Jump=true;waypoints=nil;idx=2;stuck=0 end
				if dist<=4.8 and os.clock()-lastHit>1.35 then lastHit=os.clock();th:TakeDamage(model:GetAttribute("Boss") and 5 or 1.5) end
			end
			task.wait(.12)
		end
	end)
end

local function spawnZombie(sender,boss,forcedPos)
	local desc=Instance.new("HumanoidDescription");desc.BodyTypeScale=0;desc.ProportionScale=0;desc.HeightScale=boss and 1.23 or rng:NextNumber(.94,1.08);desc.WidthScale=boss and 1.16 or rng:NextNumber(.92,1.08);desc.DepthScale=boss and 1.1 or 1;desc.HeadScale=boss and 1.08 or 1
	local ok,model=pcall(function() return Players:CreateHumanoidModelFromDescriptionAsync(desc,Enum.HumanoidRigType.R15) end)
	if not ok or not model then warn("ZOMBIE CREATE FAILED",model);return end
	model.Name=(boss and "Boss_" or "Zombie_")..tostring(sender);model:SetAttribute("Boss",boss==true);model:SetAttribute("Dead",false);model.Parent=enemies
	local hum=model:FindFirstChildOfClass("Humanoid");local root=model:FindFirstChild("HumanoidRootPart");if not hum or not root then model:Destroy();return end
	styleZombie(model,boss);addName(model,tostring(sender),boss);addWalk(hum);hum.MaxHealth=boss and 850 or 100;hum.Health=hum.MaxHealth;hum.WalkSpeed=boss and 8 or 9;hum.JumpPower=36
	for _,bp in ipairs(model:GetDescendants()) do if bp:IsA("BasePart") then bp.Anchored=false;pcall(function() bp:SetNetworkOwner(nil) end) end end
	local pos=forcedPos or chooseSpawnPoint()
	if not pos then model:Destroy();return end
	active+=1;stats()
	hum.Died:Connect(function()
		if model:GetAttribute("Dead") then return end
		model:SetAttribute("Dead",true);active=math.max(0,active-1);kills+=1;stats();for _,bp in ipairs(model:GetDescendants()) do if bp:IsA("BasePart") then bp.CanCollide=false;bp.CanTouch=false end end;task.delay(1.2,function() if model.Parent then model:Destroy() end end)
	end)
	emergeFromGround(model,pos);if model.Parent and hum.Health>0 then hum.WalkSpeed=boss and 8 or 9;startChase(model) end;return model
end

local function spawnGroup(sender,count,boss)
	count=math.clamp(tonumber(count) or 1,1,30)
	if boss then spawnZombie(sender,true,nil) end
	for i=1,count do task.delay((i-1)*.09,function() spawnZombie(sender..(count>1 and ("_"..i) or ""),false,nil) end) end
end

testRemote.OnServerEvent:Connect(function(player,amount)
	if player~=hostPlayer() then return end;amount=math.clamp(tonumber(amount) or 10,1,20);spawnGroup("TEST_VIEWER",amount,false);print("ZOMBIE TEST SPAWN:",player.Name,amount)
end)
giftSpawn.Event:Connect(function(sender,count,boss) spawnGroup(tostring(sender or "VIEWER"),tonumber(count) or 1,boss==true) end)

local weaponData={Pistol={damage=20,range=100},SMG={damage=11,range=95},Shotgun={damage=30,range=65},Rifle={damage=31,range=145},Minigun={damage=8,range=120},Sword={damage=40,range=10}}
attackRemote.OnServerEvent:Connect(function(player,target,weapon)
	if player~=hostPlayer() or typeof(target)~="Instance" or not target:IsDescendantOf(enemies) then return end
	local model=target:IsA("Model") and target or target:FindFirstAncestorOfClass("Model");if not model or not model:IsDescendantOf(enemies) then return end
	local h=model:FindFirstChildOfClass("Humanoid");local r=model:FindFirstChild("HumanoidRootPart");local char=player.Character;local pr=char and char:FindFirstChild("HumanoidRootPart");local cfg=weaponData[tostring(weapon)] or weaponData.Rifle
	if not h or not r or not pr or h.Health<=0 or model:GetAttribute("Dead") then return end;if (pr.Position-r.Position).Magnitude>cfg.range+8 then return end;h:TakeDamage(cfg.damage)
end)

print("ZOMBIE CORE V3.5 READY - strict City Fight street-only spawning")