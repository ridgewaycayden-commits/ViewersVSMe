-- TikTokGameCore.server.lua
-- VIEWERS VS ME - ZOMBIE CORE V4.0
-- Five fixed, validated zombie spawn points. No per-zombie random building/roof spawns.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local ServerStorage=game:GetService("ServerStorage")
local PathfindingService=game:GetService("PathfindingService")
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
enemies.Name="TikTokEnemies"
enemies.Parent=workspace

local spawnFolder=workspace:FindFirstChild("ZombieSpawns") or Instance.new("Folder")
spawnFolder.Name="ZombieSpawns"
spawnFolder.Parent=workspace
for _,v in ipairs(spawnFolder:GetChildren()) do v:Destroy() end

local active,kills=0,0
local spawnPoints={}
local spawnOrigin=nil
local buildingSpawns=false

local function hostPlayer() return Players:GetPlayers()[1] end
local function hostCharacter() local p=hostPlayer();return p and p.Character end
local function stats() streamRemote:FireAllClients({kind="stats",kills=kills,active=active,wave=math.floor(kills/20)+1}) end

local rayParams=RaycastParams.new()
rayParams.FilterType=Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater=true

local overlapParams=OverlapParams.new()
overlapParams.FilterType=Enum.RaycastFilterType.Exclude
overlapParams.MaxParts=100

local bannedWords={
	"roof","car","truck","vehicle","bus","police","crate","box","container","awning","table","bench","chair",
	"dumpster","trash","prop","sign","fence","wall","window","door","tree","lamp","light","hydrant","barrier",
	"railing","stairs","stair","balcony","porch","deck","scaffold","statue","planter","building"
}

local function badSurface(part)
	if not part or not part:IsA("BasePart") or not part.CanCollide or part.Transparency>=.98 then return true end
	local cur=part
	for _=1,7 do
		if not cur then break end
		local name=string.lower(cur.Name or "")
		for _,word in ipairs(bannedWords) do
			if name:find(word,1,true) then return true end
		end
		cur=cur.Parent
	end
	return false
end

local function groundAt(raw)
	rayParams.FilterDescendantsInstances={enemies,spawnFolder,hostCharacter()}
	local hit=workspace:Raycast(raw+Vector3.new(0,55,0),Vector3.new(0,-120,0),rayParams)
	if not hit or hit.Normal.Y<.9 or badSurface(hit.Instance) then return nil end
	return hit.Position,hit.Instance
end

local function openSpot(pos,groundPart)
	overlapParams.FilterDescendantsInstances={enemies,spawnFolder,hostCharacter(),groundPart}
	local blockers=workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.new(0,3.2,0)),Vector3.new(8,6.4,8),overlapParams)
	for _,p in ipairs(blockers) do
		if p:IsA("BasePart") and p.CanCollide and p.Transparency<.95 then return false end
	end

	-- If there is a ceiling/roof above the point, reject it. This prevents indoor spawns.
	rayParams.FilterDescendantsInstances={enemies,spawnFolder,hostCharacter(),groundPart}
	local above=workspace:Raycast(pos+Vector3.new(0,1,0),Vector3.new(0,40,0),rayParams)
	if above and above.Instance and above.Instance.CanCollide then return false end

	-- Require flat/open ground around the whole marker, not a tiny ledge or prop top.
	for _,off in ipairs({
		Vector3.new(4,0,0),Vector3.new(-4,0,0),Vector3.new(0,0,4),Vector3.new(0,0,-4),
		Vector3.new(3,0,3),Vector3.new(-3,0,3),Vector3.new(3,0,-3),Vector3.new(-3,0,-3)
	}) do
		local near,part=groundAt(pos+off)
		if not near or badSurface(part) or math.abs(near.Y-pos.Y)>0.8 then return false end
	end
	return true
end

local function pathExists(fromPos,toPos)
	local path=PathfindingService:CreatePath({AgentRadius=2.4,AgentHeight=5.5,AgentCanJump=true,AgentCanClimb=false,WaypointSpacing=5})
	local ok=pcall(function() path:ComputeAsync(fromPos+Vector3.new(0,2.8,0),toPos) end)
	return ok and path.Status==Enum.PathStatus.Success and #path:GetWaypoints()>=2
end

local function candidate(raw,origin)
	local pos,part=groundAt(raw)
	if not pos then return nil end
	if math.abs(pos.Y-(origin.Y-3))>5 then return nil end
	if not openSpot(pos,part) then return nil end
	if not pathExists(pos,origin) then return nil end
	return pos
end

local function makeMarker(index,pos)
	local p=Instance.new("Part")
	p.Name="SafeSpawn"..index
	p.Size=Vector3.new(5,.3,5)
	p.Anchored=true
	p.CanCollide=false
	p.CanTouch=false
	p.CanQuery=false
	p.Transparency=1
	p.CFrame=CFrame.new(pos+Vector3.new(0,.15,0))
	p:SetAttribute("SafeZombieSpawn",true)
	p.Parent=spawnFolder
	table.insert(spawnPoints,p)
end

local function buildSafeSpawns()
	if #spawnPoints>=5 then return true end
	local char=hostCharacter()
	local root=char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	spawnOrigin=root.Position

	-- Five separate sectors around the play area. Once chosen, these stay fixed for the session.
	for sector=1,5 do
		local base=((sector-1)/5)*math.pi*2
		local found=nil
		for attempt=1,80 do
			local angle=base+rng:NextNumber(-0.45,0.45)
			local radius=rng:NextNumber(34,72)
			local raw=spawnOrigin+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
			local pos=candidate(raw,spawnOrigin)
			if pos then
				local separated=true
				for _,marker in ipairs(spawnPoints) do
					if (marker.Position-pos).Magnitude<18 then separated=false break end
				end
				if separated then found=pos break end
			end
		end
		if found then makeMarker(sector,found) end
	end

	-- Fill any missing sectors, still using only fully validated outdoor ground.
	local guard=0
	while #spawnPoints<5 and guard<350 do
		guard+=1
		local angle=rng:NextNumber(0,math.pi*2)
		local radius=rng:NextNumber(30,78)
		local pos=candidate(spawnOrigin+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),spawnOrigin)
		if pos then
			local separated=true
			for _,marker in ipairs(spawnPoints) do if (marker.Position-pos).Magnitude<16 then separated=false break end end
			if separated then makeMarker(#spawnPoints+1,pos) end
		end
	end

	print("SAFE ZOMBIE SPAWNS BUILT:",#spawnPoints,"/ 5")
	if #spawnPoints<5 then warn("Only",#spawnPoints,"safe zombie spawn markers could be verified; unsafe locations will NOT be used.") end
	return #spawnPoints>0
end

local function chooseSpawnPoint()
	if #spawnPoints==0 and not buildSafeSpawns() then return nil end
	local char=hostCharacter();local root=char and char:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	-- Prefer a fixed marker that is not right beside the player and still has a route to them.
	local choices={}
	for _,marker in ipairs(spawnPoints) do
		local dist=(marker.Position-root.Position).Magnitude
		if dist>=20 and pathExists(marker.Position,root.Position) then table.insert(choices,marker) end
	end
	if #choices==0 then
		for _,marker in ipairs(spawnPoints) do
			if pathExists(marker.Position,root.Position) then table.insert(choices,marker) end
		end
	end
	if #choices==0 then
		warn("ZOMBIE SPAWN SKIPPED - player is not reachable from any fixed safe spawn")
		return nil
	end
	return choices[rng:NextInteger(1,#choices)].Position
end

local palettes={
	{skin=Color3.fromRGB(105,125,91),torso=Color3.fromRGB(48,57,46),pants=Color3.fromRGB(31,34,34)},
	{skin=Color3.fromRGB(126,108,88),torso=Color3.fromRGB(60,48,43),pants=Color3.fromRGB(30,31,34)},
	{skin=Color3.fromRGB(92,112,104),torso=Color3.fromRGB(43,52,56),pants=Color3.fromRGB(27,29,33)},
	{skin=Color3.fromRGB(130,96,82),torso=Color3.fromRGB(62,42,39),pants=Color3.fromRGB(34,31,30)},
}

local function styleZombie(model,boss)
	local pal=palettes[rng:NextInteger(1,#palettes)]
	for _,o in ipairs(model:GetDescendants()) do
		if o:IsA("Accessory") or o:IsA("Shirt") or o:IsA("Pants") or o:IsA("ShirtGraphic") then
			o:Destroy()
		elseif o:IsA("BasePart") then
			o.Anchored=false
			o.Material=Enum.Material.SmoothPlastic
			if o.Name=="Head" then o.Color=boss and Color3.fromRGB(120,66,58) or pal.skin
			elseif o.Name:find("Torso") then o.Color=boss and Color3.fromRGB(72,25,25) or pal.torso
			elseif o.Name:find("Arm") or o.Name:find("Hand") then o.Color=boss and Color3.fromRGB(110,57,52) or pal.skin
			elseif o.Name:find("Leg") or o.Name:find("Foot") then o.Color=pal.pants end
		end
	end
end

local function addName(model,name,boss)
	local head=model:FindFirstChild("Head");if not head then return end
	local gui=Instance.new("BillboardGui")
	gui.Name="ViewerTag";gui.Size=UDim2.fromOffset(boss and 220 or 170,32);gui.StudsOffset=Vector3.new(0,3.1,0)
	gui.AlwaysOnTop=false;gui.MaxDistance=boss and 140 or 95;gui.LightInfluence=0;gui.Parent=head
	local lbl=Instance.new("TextLabel")
	lbl.Size=UDim2.fromScale(1,1);lbl.BackgroundTransparency=1;lbl.Font=Enum.Font.GothamBlack;lbl.TextScaled=true
	lbl.TextStrokeTransparency=.2;lbl.TextColor3=boss and Color3.fromRGB(255,75,60) or Color3.new(1,1,1)
	lbl.Text=boss and ("BOSS • @"..name) or ("@"..name);lbl.Parent=gui
end

local function startChase(model)
	local hum=model:FindFirstChildOfClass("Humanoid");local root=model:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return end
	task.spawn(function()
		local waypoints=nil;local idx=2;local repathAt=0;local lastHit=0;local lastPos=root.Position;local stuck=0
		while model.Parent and hum.Health>0 and not model:GetAttribute("Dead") do
			local char=hostCharacter();local th=char and char:FindFirstChildOfClass("Humanoid");local tr=char and char:FindFirstChild("HumanoidRootPart")
			if th and tr and th.Health>0 then
				local dist=(tr.Position-root.Position).Magnitude
				if os.clock()>=repathAt or not waypoints or not waypoints[idx] then
					repathAt=os.clock()+.55
					local path=PathfindingService:CreatePath({AgentRadius=2.1,AgentHeight=5.2,AgentCanJump=true,AgentCanClimb=false,WaypointSpacing=4})
					local ok=pcall(function() path:ComputeAsync(root.Position,tr.Position) end)
					if ok and path.Status==Enum.PathStatus.Success then waypoints=path:GetWaypoints();idx=2 else waypoints=nil end
				end
				local goal=nil
				if waypoints and waypoints[idx] then
					local wp=waypoints[idx]
					if (root.Position-wp.Position).Magnitude<3 then idx+=1;wp=waypoints[idx] end
					if wp then goal=wp.Position;if wp.Action==Enum.PathWaypointAction.Jump then hum.Jump=true end end
				end
				-- Do NOT directly MoveTo the player through a building when no path exists.
				if goal then hum:MoveTo(goal) else hum:Move(Vector3.zero,false) end
				local moved=(root.Position-lastPos).Magnitude
				if moved<.15 and dist>6 then stuck+=.12 else stuck=0 end
				lastPos=root.Position
				if stuck>1 then hum.Jump=true;waypoints=nil;stuck=0;repathAt=0 end
				if dist<=4.8 and os.clock()-lastHit>1.35 then lastHit=os.clock();th:TakeDamage(model:GetAttribute("Boss") and 5 or 1.5) end
			end
			task.wait(.12)
		end
	end)
end

local function spawnZombie(sender,boss,forcedPos)
	local pos=forcedPos or chooseSpawnPoint()
	if not pos then return end

	local desc=Instance.new("HumanoidDescription")
	desc.BodyTypeScale=0;desc.ProportionScale=0;desc.HeightScale=boss and 1.23 or rng:NextNumber(.94,1.08)
	desc.WidthScale=boss and 1.16 or rng:NextNumber(.92,1.08);desc.DepthScale=boss and 1.1 or 1;desc.HeadScale=boss and 1.08 or 1
	local ok,model=pcall(function() return Players:CreateHumanoidModelFromDescriptionAsync(desc,Enum.HumanoidRigType.R15) end)
	if not ok or not model then warn("ZOMBIE CREATE FAILED",model);return end
	model.Name=(boss and "Boss_" or "Zombie_")..tostring(sender)
	model:SetAttribute("Boss",boss==true);model:SetAttribute("Dead",false);model.Parent=enemies
	local hum=model:FindFirstChildOfClass("Humanoid");local root=model:FindFirstChild("HumanoidRootPart")
	if not hum or not root then model:Destroy();return end
	styleZombie(model,boss);addName(model,tostring(sender),boss)
	hum.MaxHealth=boss and 850 or 100;hum.Health=hum.MaxHealth;hum.WalkSpeed=boss and 8 or 9;hum.JumpPower=36
	for _,bp in ipairs(model:GetDescendants()) do if bp:IsA("BasePart") then bp.Anchored=false;pcall(function() bp:SetNetworkOwner(nil) end) end end
	model:PivotTo(CFrame.new(pos+Vector3.new(0,3.1,0)))
	active+=1;stats()
	hum.Died:Connect(function()
		if model:GetAttribute("Dead") then return end
		model:SetAttribute("Dead",true);active=math.max(0,active-1);kills+=1;stats()
		for _,bp in ipairs(model:GetDescendants()) do if bp:IsA("BasePart") then bp.CanCollide=false;bp.CanTouch=false end end
		task.delay(1.2,function() if model.Parent then model:Destroy() end end)
	end)
	startChase(model)
	return model
end

local function spawnGroup(sender,count,boss)
	count=math.clamp(tonumber(count) or 1,1,30)
	if boss then spawnZombie(sender,true,nil) end
	for i=1,count do task.delay((i-1)*.09,function() spawnZombie(sender..(count>1 and ("_"..i) or ""),false,nil) end) end
end

task.spawn(function()
	for _=1,80 do
		if buildSafeSpawns() then break end
		task.wait(.25)
	end
end)

testRemote.OnServerEvent:Connect(function(player,amount)
	if player~=hostPlayer() then return end
	amount=math.clamp(tonumber(amount) or 10,1,20)
	spawnGroup("TEST_VIEWER",amount,false)
	print("ZOMBIE TEST SPAWN:",player.Name,amount)
end)

giftSpawn.Event:Connect(function(sender,count,boss)
	spawnGroup(tostring(sender or "VIEWER"),tonumber(count) or 1,boss==true)
end)

local weaponData={Pistol={damage=20,range=100},SMG={damage=11,range=95},Shotgun={damage=30,range=65},Rifle={damage=31,range=145},Minigun={damage=8,range=120},Sword={damage=40,range=10}}
attackRemote.OnServerEvent:Connect(function(player,target,weapon)
	if player~=hostPlayer() or typeof(target)~="Instance" or not target:IsDescendantOf(enemies) then return end
	local model=target:IsA("Model") and target or target:FindFirstAncestorOfClass("Model")
	if not model or not model:IsDescendantOf(enemies) then return end
	local h=model:FindFirstChildOfClass("Humanoid");local r=model:FindFirstChild("HumanoidRootPart")
	local char=player.Character;local pr=char and char:FindFirstChild("HumanoidRootPart")
	local cfg=weaponData[tostring(weapon)] or weaponData.Rifle
	if not h or not r or not pr or h.Health<=0 or model:GetAttribute("Dead") then return end
	if (pr.Position-r.Position).Magnitude>cfg.range+8 then return end
	h:TakeDamage(cfg.damage)
end)

print("ZOMBIE CORE V4.0 READY - 5 fixed verified safe spawns only")