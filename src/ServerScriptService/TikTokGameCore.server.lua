-- TikTokGameCore.server.lua
-- VIEWERS VS ME - ZOMBIE OVERHAUL

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local function getRemote(name)
	local r=ReplicatedStorage:FindFirstChild(name)
	if r and not r:IsA("RemoteEvent") then r:Destroy();r=nil end
	if not r then r=Instance.new("RemoteEvent");r.Name=name;r.Parent=ReplicatedStorage end
	return r
end

local testRemote=getRemote("TikTokTestSpawn")
local streamRemote=getRemote("TikTokStreamEvent")
local attackRemote=getRemote("AutoCombatAttack")

local enemies=workspace:FindFirstChild("TikTokEnemies") or Instance.new("Folder")
enemies.Name="TikTokEnemies";enemies.Parent=workspace

local active=0
local kills=0
local rng=Random.new()

local function hostPlayer() return Players:GetPlayers()[1] end
local function hostCharacter() local p=hostPlayer();return p and p.Character end
local function stats()
	streamRemote:FireAllClients({kind="stats",kills=kills,active=active,wave=math.floor(kills/20)+1})
end

local function groundAt(pos)
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={enemies}
	local hit=workspace:Raycast(pos+Vector3.new(0,30,0),Vector3.new(0,-80,0),params)
	return hit and hit.Position or pos
end

local function randomSpawn()
	local char=hostCharacter();local root=char and char:FindFirstChild("HumanoidRootPart")
	if root then
		for _=1,12 do
			local a=rng:NextNumber(0,math.pi*2);local radius=rng:NextNumber(30,46)
			local raw=root.Position+Vector3.new(math.cos(a)*radius,0,math.sin(a)*radius)
			local ground=groundAt(raw)
			if (ground-root.Position).Magnitude>22 then return ground end
		end
	end
	return groundAt(Vector3.new(rng:NextNumber(-35,35),3,rng:NextNumber(-35,35)))
end

local palettes={
	{skin=Color3.fromRGB(105,125,91),torso=Color3.fromRGB(48,57,46),pants=Color3.fromRGB(31,34,34)},
	{skin=Color3.fromRGB(126,108,88),torso=Color3.fromRGB(60,48,43),pants=Color3.fromRGB(30,31,34)},
	{skin=Color3.fromRGB(92,112,104),torso=Color3.fromRGB(43,52,56),pants=Color3.fromRGB(27,29,33)},
	{skin=Color3.fromRGB(130,96,82),torso=Color3.fromRGB(62,42,39),pants=Color3.fromRGB(34,31,30)},
}

local function addScar(part,size,offset,color)
	local scar=Instance.new("Part")
	scar.Name="DecayDetail";scar.Size=size;scar.Color=color or Color3.fromRGB(76,35,32);scar.Material=Enum.Material.SmoothPlastic
	scar.CanCollide=false;scar.CanTouch=false;scar.CanQuery=false;scar.Massless=true
	scar.CFrame=part.CFrame*offset;scar.Parent=part.Parent
	local weld=Instance.new("WeldConstraint");weld.Part0=part;weld.Part1=scar;weld.Parent=scar
end

local function styleZombie(model,boss)
	local p=palettes[rng:NextInteger(1,#palettes)]
	for _,obj in ipairs(model:GetDescendants()) do
		if obj:IsA("Accessory") or obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic") then
			obj:Destroy()
		elseif obj:IsA("BasePart") then
			obj.Anchored=false;obj.Material=Enum.Material.SmoothPlastic
			if obj.Name=="Head" then obj.Color=boss and Color3.fromRGB(122,72,65) or p.skin
			elseif obj.Name:find("Torso") then obj.Color=boss and Color3.fromRGB(72,29,28) or p.torso
			elseif obj.Name:find("Arm") or obj.Name:find("Hand") then obj.Color=boss and Color3.fromRGB(112,66,58) or p.skin
			elseif obj.Name:find("Leg") or obj.Name:find("Foot") then obj.Color=p.pants end
		end
	end

	local head=model:FindFirstChild("Head")
	if head then
		local face=head:FindFirstChildOfClass("Decal");if face then face:Destroy() end
		local eye1=Instance.new("Part");eye1.Size=Vector3.new(.12,.12,.05);eye1.Color=Color3.fromRGB(235,225,170);eye1.Material=Enum.Material.Neon;eye1.CanCollide=false;eye1.CanTouch=false;eye1.CanQuery=false;eye1.Massless=true;eye1.CFrame=head.CFrame*CFrame.new(-.18,.10,-.48);eye1.Parent=model
		local eye2=eye1:Clone();eye2.CFrame=head.CFrame*CFrame.new(.18,.10,-.48);eye2.Parent=model
		for _,eye in ipairs({eye1,eye2}) do local w=Instance.new("WeldConstraint");w.Part0=head;w.Part1=eye;w.Parent=eye end
		addScar(head,Vector3.new(.24,.08,.04),CFrame.new(.10,-.16,-.49)*CFrame.Angles(0,0,math.rad(-18)),Color3.fromRGB(76,32,28))
	end
	local torso=model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if torso then
		addScar(torso,Vector3.new(.55,.10,.05),CFrame.new(.18,.05,-.51)*CFrame.Angles(0,0,math.rad(22)),Color3.fromRGB(70,30,28))
	end
end

local function addName(model,name,boss)
	local head=model:FindFirstChild("Head");if not head then return end
	local gui=Instance.new("BillboardGui");gui.Name="ViewerTag";gui.Size=UDim2.fromOffset(boss and 210 or 170,32);gui.StudsOffset=Vector3.new(0,3.1,0);gui.AlwaysOnTop=true;gui.Parent=head
	local lbl=Instance.new("TextLabel");lbl.Size=UDim2.fromScale(1,1);lbl.BackgroundTransparency=1;lbl.Font=Enum.Font.GothamBlack;lbl.TextScaled=true;lbl.TextStrokeTransparency=.2;lbl.TextColor3=boss and Color3.fromRGB(255,85,70) or Color3.new(1,1,1);lbl.Text=boss and ("BOSS • @"..name) or ("@"..name);lbl.Parent=gui
end

local function addWalk(hum)
	local animator=hum:FindFirstChildOfClass("Animator") or Instance.new("Animator");animator.Parent=hum
	local anim=Instance.new("Animation");anim.AnimationId="rbxassetid://507777826"
	local ok,track=pcall(function() return animator:LoadAnimation(anim) end)
	if ok and track then
		track.Looped=true;track.Priority=Enum.AnimationPriority.Movement
		hum.Running:Connect(function(speed)
			if hum.Health<=0 then if track.IsPlaying then track:Stop(.05) end
			elseif speed>.5 then if not track.IsPlaying then track:Play(.12) end;track:AdjustSpeed(math.clamp(speed/8.5,.65,1.25))
			elseif track.IsPlaying then track:Stop(.15) end
		end)
	end
end

local function emergeFromGround(model,groundPos)
	local hum=model:FindFirstChildOfClass("Humanoid");local root=model:FindFirstChild("HumanoidRootPart");if not hum or not root then return end
	local finalCF=CFrame.new(groundPos+Vector3.new(0,3,0))
	local startCF=CFrame.new(groundPos-Vector3.new(0,2.7,0))
	model:PivotTo(startCF)
	hum.WalkSpeed=0;hum.AutoRotate=false
	for _,bp in ipairs(model:GetDescendants()) do if bp:IsA("BasePart") then bp.CanCollide=false end end
	local dirt=Instance.new("Part");dirt.Name="SpawnDirt";dirt.Anchored=true;dirt.CanCollide=false;dirt.CanTouch=false;dirt.Material=Enum.Material.Ground;dirt.Color=Color3.fromRGB(68,55,42);dirt.Size=Vector3.new(4.5,.18,4.5);dirt.CFrame=CFrame.new(groundPos+Vector3.new(0,.07,0));dirt.Parent=workspace
	local mesh=Instance.new("SpecialMesh");mesh.MeshType=Enum.MeshType.Cylinder;mesh.Scale=Vector3.new(1,.15,1);mesh.Parent=dirt
	local tween=TweenService:Create(root,TweenInfo.new(1.45,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{CFrame=finalCF})
	for _,bp in ipairs(model:GetDescendants()) do if bp:IsA("BasePart") and bp~=root then bp.Anchored=false end end
	root.Anchored=true;tween:Play()
	local smoke=Instance.new("ParticleEmitter");smoke.Texture="rbxasset://textures/particles/smoke_main.dds";smoke.Rate=0;smoke.Lifetime=NumberRange.new(.35,.75);smoke.Speed=NumberRange.new(3,7);smoke.SpreadAngle=Vector2.new(180,180);smoke.Color=ColorSequence.new(Color3.fromRGB(90,75,58));smoke.Parent=dirt;smoke:Emit(22)
	tween.Completed:Wait();root.Anchored=false;hum.AutoRotate=true
	for _,bp in ipairs(model:GetDescendants()) do if bp:IsA("BasePart") then bp.CanCollide=(bp.Name=="HumanoidRootPart" or bp.Name:find("Torso")~=nil) end end
	Debris:AddItem(dirt,.65)
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
				if waypoints and waypoints[idx] then local wp=waypoints[idx];if (root.Position-wp.Position).Magnitude<3 then idx+=1;wp=waypoints[idx] end;if wp then goal=wp.Position;if wp.Action==Enum.PathWaypointAction.Jump then hum.Jump=true end end end
				hum:MoveTo(goal)
				local moved=(root.Position-lastPos).Magnitude;if moved<.2 and dist>6 then stuck+=.12 else stuck=0 end;lastPos=root.Position
				if stuck>1.0 then hum.Jump=true;waypoints=nil;idx=2;hum:MoveTo(root.Position+Vector3.new(rng:NextNumber(-7,7),0,rng:NextNumber(-7,7)));stuck=0 end
				if dist<=4.8 and os.clock()-lastHit>1.35 then lastHit=os.clock();th:TakeDamage(model:GetAttribute("Boss") and 5 or 1.5) end
			end
			task.wait(.12)
		end
	end)
end

local function spawnZombie(sender,boss)
	local desc=Instance.new("HumanoidDescription")
	desc.BodyTypeScale=0;desc.ProportionScale=0;desc.HeightScale=boss and 1.18 or rng:NextNumber(.94,1.08);desc.WidthScale=boss and 1.12 or rng:NextNumber(.92,1.08);desc.DepthScale=boss and 1.08 or 1;desc.HeadScale=rng:NextNumber(.95,1.05)
	local ok,model=pcall(function() return Players:CreateHumanoidModelFromDescriptionAsync(desc,Enum.HumanoidRigType.R15) end)
	if not ok or not model then warn("Zombie rig failed",model);return end
	model.Name=boss and ("Boss_"..sender) or ("Zombie_"..sender);model:SetAttribute("TikTokEnemy",true);model:SetAttribute("Boss",boss==true);model:SetAttribute("Dead",false);model.Parent=enemies
	local hum=model:FindFirstChildOfClass("Humanoid");local root=model:FindFirstChild("HumanoidRootPart");if not hum or not root then model:Destroy();return end
	styleZombie(model,boss);addName(model,sender,boss);addWalk(hum)
	hum.MaxHealth=boss and 700 or rng:NextInteger(110,145);hum.Health=hum.MaxHealth;hum.JumpPower=34;hum.AutoRotate=true;hum.PlatformStand=false;hum.Sit=false;hum.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
	local spawnPos=randomSpawn();model:PivotTo(CFrame.new(spawnPos+Vector3.new(0,3,0)))
	pcall(function() root:SetNetworkOwner(nil) end)
	active+=1;stats()
	task.spawn(function()
		emergeFromGround(model,spawnPos)
		if model.Parent and hum.Health>0 then hum.WalkSpeed=boss and 7.5 or rng:NextNumber(7.4,9.2);startChase(model) end
	end)
	hum.Died:Connect(function()
		if model:GetAttribute("Dead") then return end
		model:SetAttribute("Dead",true);hum.WalkSpeed=0;active=math.max(0,active-1);kills+=1;stats()
		for _,obj in ipairs(model:GetDescendants()) do if obj:IsA("BasePart") then obj.CanTouch=false;obj.CanCollide=false end end
		Debris:AddItem(model,1.5)
	end)
end

testRemote.OnServerEvent:Connect(function(player,amount)
	amount=math.clamp(tonumber(amount) or 10,1,20);print("ZOMBIE OVERHAUL TEST SPAWN:",player.Name,amount)
	for i=1,amount do spawnZombie("TEST_VIEWER_"..i,false);task.wait(.12) end
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

print("ZOMBIE OVERHAUL READY - ground emergence + detailed variants enabled.")