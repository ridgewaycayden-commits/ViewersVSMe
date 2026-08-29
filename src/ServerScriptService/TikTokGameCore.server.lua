-- TikTokGameCore.server.lua
-- VIEWERS VS ME - ZOMBIE CORE V3
-- Smooth whole-rig ground emergence + gift horde/boss spawn support.

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
local spawnRequest=bindable("ViewersVsMeSpawnRequest")

local enemies=workspace:FindFirstChild("TikTokEnemies") or Instance.new("Folder")
enemies.Name="TikTokEnemies";enemies.Parent=workspace

local active,kills=0,0
local function hostPlayer() return Players:GetPlayers()[1] end
local function hostCharacter() local p=hostPlayer();return p and p.Character end
local function stats() streamRemote:FireAllClients({kind="stats",kills=kills,active=active,wave=math.floor(kills/20)+1}) end

local function groundAt(pos)
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={enemies};params.IgnoreWater=true
	local hit=workspace:Raycast(pos+Vector3.new(0,35,0),Vector3.new(0,-100,0),params)
	return hit and hit.Position or pos
end

local function randomSpawn(minR,maxR)
	local char=hostCharacter();local root=char and char:FindFirstChild("HumanoidRootPart")
	if root then
		for _=1,16 do
			local a=rng:NextNumber(0,math.pi*2);local radius=rng:NextNumber(minR or 30,maxR or 46)
			local g=groundAt(root.Position+Vector3.new(math.cos(a)*radius,0,math.sin(a)*radius))
			if (g-root.Position).Magnitude>22 then return g end
		end
	end
	return groundAt(Vector3.new(rng:NextNumber(-35,35),3,rng:NextNumber(-35,35)))
end

local palettes={
	{Color3.fromRGB(105,125,91),Color3.fromRGB(48,57,46),Color3.fromRGB(31,34,34)},
	{Color3.fromRGB(126,108,88),Color3.fromRGB(60,48,43),Color3.fromRGB(30,31,34)},
	{Color3.fromRGB(92,112,104),Color3.fromRGB(43,52,56),Color3.fromRGB(27,29,33)},
	{Color3.fromRGB(130,96,82),Color3.fromRGB(62,42,39),Color3.fromRGB(34,31,30)},
	{Color3.fromRGB(91,102,79),Color3.fromRGB(52,45,39),Color3.fromRGB(26,28,29)},
}

local function detail(part,name,size,offset,color,material)
	local d=Instance.new("Part");d.Name=name;d.Size=size;d.Color=color;d.Material=material or Enum.Material.SmoothPlastic;d.CanCollide=false;d.CanTouch=false;d.CanQuery=false;d.Massless=true;d.CFrame=part.CFrame*offset;d.Parent=part.Parent
	local w=Instance.new("WeldConstraint");w.Part0=part;w.Part1=d;w.Parent=d
	return d
end

local function styleZombie(model,boss)
	local p=palettes[rng:NextInteger(1,#palettes)]
	for _,obj in ipairs(model:GetDescendants()) do
		if obj:IsA("Accessory") or obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic") then obj:Destroy()
		elseif obj:IsA("BasePart") then
			obj.Anchored=false;obj.Material=Enum.Material.SmoothPlastic
			if obj.Name=="Head" then obj.Color=boss and Color3.fromRGB(122,72,65) or p[1]
			elseif obj.Name:find("Torso") then obj.Color=boss and Color3.fromRGB(72,29,28) or p[2]
			elseif obj.Name:find("Arm") or obj.Name:find("Hand") then obj.Color=boss and Color3.fromRGB(112,66,58) or p[1]
			elseif obj.Name:find("Leg") or obj.Name:find("Foot") then obj.Color=p[3] end
		end
	end
	local head=model:FindFirstChild("Head")
	if head then
		local face=head:FindFirstChildOfClass("Decal");if face then face:Destroy() end
		for _,x in ipairs({-.18,.18}) do
			local eye=detail(head,"DeadEye",Vector3.new(.12,.12,.045),CFrame.new(x,.10,-.49),boss and Color3.fromRGB(255,70,45) or Color3.fromRGB(230,220,165),Enum.Material.Neon)
			local l=Instance.new("PointLight");l.Brightness=.3;l.Range=2.4;l.Color=eye.Color;l.Parent=eye
		end
		detail(head,"FaceScar",Vector3.new(.26,.075,.04),CFrame.new(.11,-.16,-.50)*CFrame.Angles(0,0,math.rad(-18)),Color3.fromRGB(74,30,27))
		if rng:NextNumber()<.45 then detail(head,"RotPatch",Vector3.new(.32,.22,.035),CFrame.new(-.22,-.12,-.49),Color3.fromRGB(55,44,36)) end
	end
	local torso=model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if torso then
		detail(torso,"ChestTear",Vector3.new(.58,.10,.045),CFrame.new(.17,.04,-.52)*CFrame.Angles(0,0,math.rad(22)),Color3.fromRGB(67,28,27))
		if rng:NextNumber()<.55 then detail(torso,"FabricTear",Vector3.new(.34,.30,.035),CFrame.new(-.22,-.18,-.52),Color3.fromRGB(24,25,25)) end
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
			elseif speed>.5 then if not track.IsPlaying then track:Play(.12) end;track:AdjustSpeed(math.clamp(speed/8.5,.62,1.28))
			elseif track.IsPlaying then track:Stop(.15) end
		end)
	end
end

local function dirtFX(pos,boss)
	local folder=Instance.new("Folder");folder.Name="EmergenceFX";folder.Parent=workspace
	local ring=Instance.new("Part");ring.Anchored=true;ring.CanCollide=false;ring.CanTouch=false;ring.CanQuery=false;ring.Material=Enum.Material.Ground;ring.Color=Color3.fromRGB(65,52,40);ring.Size=Vector3.new(boss and 7 or 4.8,.14,boss and 7 or 4.8);ring.CFrame=CFrame.new(pos+Vector3.new(0,.05,0));ring.Parent=folder
	local smoke=Instance.new("ParticleEmitter");smoke.Texture="rbxasset://textures/particles/smoke_main.dds";smoke.Rate=0;smoke.Lifetime=NumberRange.new(.35,.85);smoke.Speed=NumberRange.new(2.5,7);smoke.RotSpeed=NumberRange.new(-120,120);smoke.SpreadAngle=Vector2.new(180,180);smoke.Color=ColorSequence.new(Color3.fromRGB(92,75,56));smoke.Parent=ring;smoke:Emit(boss and 42 or 24)
	for _=1,(boss and 12 or 8) do
		local rock=Instance.new("Part");rock.Anchored=false;rock.CanCollide=false;rock.CanTouch=false;rock.CanQuery=false;rock.Material=Enum.Material.Slate;rock.Color=Color3.fromRGB(57,50,43);rock.Size=Vector3.new(rng:NextNumber(.18,.48),rng:NextNumber(.12,.30),rng:NextNumber(.18,.48));rock.CFrame=CFrame.new(pos+Vector3.new(rng:NextNumber(-1.7,1.7),.25,rng:NextNumber(-1.7,1.7)));rock.Parent=folder;rock.AssemblyLinearVelocity=Vector3.new(rng:NextNumber(-6,6),rng:NextNumber(5,11),rng:NextNumber(-6,6))
	end
	Debris:AddItem(folder,1.7)
end

local function emerge(model,pos,boss)
	local hum=model:FindFirstChildOfClass("Humanoid");local root=model:FindFirstChild("HumanoidRootPart");if not hum or not root then return end
	local yaw=rng:NextNumber(-math.pi,math.pi)
	local final=CFrame.new(pos+Vector3.new(0,2.9,0))*CFrame.Angles(0,yaw,0)
	local start=final*CFrame.new(0,boss and -6.5 or -5.2,0)*CFrame.Angles(math.rad(7),0,math.rad(rng:NextNumber(-4,4)))
	hum.WalkSpeed=0;hum.AutoRotate=false;hum.PlatformStand=true
	for _,bp in ipairs(model:GetDescendants()) do if bp:IsA("BasePart") then bp.CanCollide=false;bp.CanTouch=false end end
	root.Anchored=true;model:PivotTo(start);dirtFX(pos,boss)
	local n=Instance.new("NumberValue");n.Value=0
	local con=n.Changed:Connect(function(v)
		if model.Parent then
			local eased=1-(1-v)^3
			model:PivotTo(start:Lerp(final,eased)*CFrame.Angles(0,0,math.sin(v*math.pi*2)*math.rad(1.3)*(1-v)))
		end
	end)
	local tw=TweenService:Create(n,TweenInfo.new(boss and 1.9 or 1.4,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Value=1});tw:Play();tw.Completed:Wait();con:Disconnect();n:Destroy()
	if not model.Parent then return end
	model:PivotTo(final);root.Anchored=false;hum.PlatformStand=false;hum.AutoRotate=true
	for _,bp in ipairs(model:GetDescendants()) do if bp:IsA("BasePart") then bp.CanTouch=true;bp.CanCollide=(bp.Name=="HumanoidRootPart") end end
end

local function startChase(model)
	local hum=model:FindFirstChildOfClass("Humanoid");local root=model:FindFirstChild("HumanoidRootPart");if not hum or not root then return end
	task.spawn(function()
		local lastHit,lastPath=0,0;local pts=nil;local idx=2;local lastPos=root.Position;local stuck=0
		while model.Parent and hum.Health>0 and not model:GetAttribute("Dead") do
			local char=hostCharacter();local th=char and char:FindFirstChildOfClass("Humanoid");local tr=char and char:FindFirstChild("HumanoidRootPart")
			if th and tr and th.Health>0 then
				local dist=(tr.Position-root.Position).Magnitude
				if os.clock()-lastPath>.65 or not pts or not pts[idx] then
					lastPath=os.clock();local path=PathfindingService:CreatePath({AgentRadius=2.1,AgentHeight=5.2,AgentCanJump=true,WaypointSpacing=4.5});local ok=pcall(function() path:ComputeAsync(root.Position,tr.Position) end);if ok and path.Status==Enum.PathStatus.Success then pts=path:GetWaypoints();idx=2 else pts=nil end
				end
				local goal=tr.Position
				if pts and pts[idx] then local wp=pts[idx];if (root.Position-wp.Position).Magnitude<3 then idx+=1;wp=pts[idx] end;if wp then goal=wp.Position;if wp.Action==Enum.PathWaypointAction.Jump then hum.Jump=true end end end
				hum:MoveTo(goal)
				local moved=(root.Position-lastPos).Magnitude;if moved<.2 and dist>6 then stuck+=.12 else stuck=0 end;lastPos=root.Position
				if stuck>1 then hum.Jump=true;pts=nil;idx=2;hum:MoveTo(root.Position+Vector3.new(rng:NextNumber(-7,7),0,rng:NextNumber(-7,7)));stuck=0 end
				if dist<=4.8 and os.clock()-lastHit>1.35 then lastHit=os.clock();th:TakeDamage(model:GetAttribute("Boss") and 5 or 1.5) end
			end
			task.wait(.12)
		end
	end)
end

local function spawnZombie(sender,boss)
	local desc=Instance.new("HumanoidDescription");desc.BodyTypeScale=0;desc.ProportionScale=0;desc.HeightScale=boss and 1.20 or rng:NextNumber(.94,1.08);desc.WidthScale=boss and 1.15 or rng:NextNumber(.92,1.08);desc.DepthScale=boss and 1.10 or 1;desc.HeadScale=rng:NextNumber(.95,1.05)
	local ok,model=pcall(function() return Players:CreateHumanoidModelFromDescriptionAsync(desc,Enum.HumanoidRigType.R15) end)
	if not ok or not model then warn("Zombie rig failed",model);return end
	model.Name=boss and ("Boss_"..sender) or ("Zombie_"..sender);model:SetAttribute("TikTokEnemy",true);model:SetAttribute("Boss",boss==true);model:SetAttribute("Dead",false);model.Parent=enemies
	local hum=model:FindFirstChildOfClass("Humanoid");local root=model:FindFirstChild("HumanoidRootPart");if not hum or not root then model:Destroy();return end
	styleZombie(model,boss);addName(model,sender,boss);addWalk(hum)
	hum.MaxHealth=boss and 700 or rng:NextInteger(110,145);hum.Health=hum.MaxHealth;hum.JumpPower=34;hum.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
	local pos=randomSpawn(boss and 34 or 30,boss and 48 or 46);model:PivotTo(CFrame.new(pos+Vector3.new(0,3,0)));pcall(function() root:SetNetworkOwner(nil) end)
	active+=1;stats()
	hum.Died:Connect(function()
		if model:GetAttribute("Dead") then return end
		model:SetAttribute("Dead",true);hum.WalkSpeed=0;active=math.max(0,active-1);kills+=1;stats();for _,o in ipairs(model:GetDescendants()) do if o:IsA("BasePart") then o.CanTouch=false;o.CanCollide=false end end;Debris:AddItem(model,1.5)
	end)
	task.spawn(function() emerge(model,pos,boss);if model.Parent and hum.Health>0 then hum.WalkSpeed=boss and 7.5 or rng:NextNumber(7.4,9.2);startChase(model) end end)
end

local function spawnMany(sender,count,boss)
	count=math.clamp(tonumber(count) or 1,1,25)
	task.spawn(function() for i=1,count do spawnZombie(sender..(count>1 and ("_"..i) or ""),boss);task.wait(boss and .2 or .11) end end)
end

testRemote.OnServerEvent:Connect(function(player,amount) print("ZOMBIE CORE V3 TEST:",player.Name,amount);spawnMany("TEST_VIEWER",math.clamp(tonumber(amount) or 10,1,20),false) end)
spawnRequest.Event:Connect(function(data) if type(data)~="table" then return end;spawnMany(tostring(data.sender or "VIEWER"),data.count,data.boss==true) end)

local weapons={Pistol={damage=20,range=100},SMG={damage=11,range=95},Shotgun={damage=30,range=65},Rifle={damage=31,range=145},Minigun={damage=8,range=120}}
attackRemote.OnServerEvent:Connect(function(player,target,weapon)
	if typeof(target)~="Instance" or not target:IsDescendantOf(enemies) then return end
	local char=player.Character;local pr=char and char:FindFirstChild("HumanoidRootPart");local eh=target:FindFirstChildOfClass("Humanoid");local er=target:FindFirstChild("HumanoidRootPart")
	if not pr or not eh or not er or eh.Health<=0 or target:GetAttribute("Dead") then return end
	local d=(pr.Position-er.Position).Magnitude;if weapon=="Sword" then if d<=10 then eh:TakeDamage(40) end;return end;local cfg=weapons[weapon];if cfg and d<=cfg.range+10 then eh:TakeDamage(cfg.damage) end
end)

print("ZOMBIE CORE V3 READY - smooth emergence + gift hordes enabled.")