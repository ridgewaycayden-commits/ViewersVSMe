-- MovementSafetyGuard.client.lua
-- VIEWERS VS ME - MOVEMENT SAFETY GUARD V4
-- Roams around the center grass while absolutely preventing autonomous movement from leaving it.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")

local player=Players.LocalPlayer
local rng=Random.new()
local rayParams=RaycastParams.new()
rayParams.FilterType=Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater=true

local center=nil
local grassPart=nil
local halfX,halfZ=24,24
local MARGIN=4
local lastSafe=nil
local roamTarget=nil
local nextRoamAt=0
local idleSince=nil

local function groundBelow(pos,char)
	rayParams.FilterDescendantsInstances={char,workspace:FindFirstChild("TikTokEnemies")}
	return workspace:Raycast(pos+Vector3.new(0,8,0),Vector3.new(0,-20,0),rayParams)
end

local function setZone(char,root)
	local hit=groundBelow(root.Position,char)
	center=Vector3.new(root.Position.X,root.Position.Y,root.Position.Z)
	grassPart=nil
	halfX,halfZ=24,24
	if hit and hit.Instance and hit.Instance:IsA("BasePart") then
		local p=hit.Instance
		local n=string.lower(p.Name or "")
		if p.Material==Enum.Material.Grass or n:find("grass",1,true) then
			grassPart=p
			center=Vector3.new(p.Position.X,root.Position.Y,p.Position.Z)
			halfX=math.max(10,p.Size.X*.5-MARGIN)
			halfZ=math.max(10,p.Size.Z*.5-MARGIN)
		end
	end
	lastSafe=root.Position
	roamTarget=nil
	nextRoamAt=0
	print("CENTER GRASS ROAM ZONE SET",grassPart and grassPart:GetFullName() or "fallback","half",math.floor(halfX),math.floor(halfZ))
end

local function insideBounds(pos)
	if not center then return true end
	return math.abs(pos.X-center.X)<=halfX and math.abs(pos.Z-center.Z)<=halfZ
end

local function onGrass(pos,char)
	local hit=groundBelow(pos,char)
	if not hit or not hit.Instance then return false end
	if grassPart then return hit.Instance==grassPart end
	local p=hit.Instance
	return p.Material==Enum.Material.Grass or string.lower(p.Name or ""):find("grass",1,true)~=nil
end

local function safePosition(pos,char)
	return insideBounds(pos) and onGrass(pos,char)
end

local function chooseRoamTarget(char,root)
	for _=1,30 do
		local x=center.X+rng:NextNumber(-halfX*.78,halfX*.78)
		local z=center.Z+rng:NextNumber(-halfZ*.78,halfZ*.78)
		local p=Vector3.new(x,root.Position.Y,z)
		if safePosition(p,char) and (Vector3.new(x-root.Position.X,0,z-root.Position.Z)).Magnitude>7 then
			roamTarget=p
			nextRoamAt=os.clock()+rng:NextNumber(4,8)
			return
		end
	end
	roamTarget=Vector3.new(center.X,root.Position.Y,center.Z)
	nextRoamAt=os.clock()+3
end

local function directionTo(root,target)
	if not target then return Vector3.zero end
	local d=Vector3.new(target.X-root.Position.X,0,target.Z-root.Position.Z)
	return d.Magnitude>.15 and d.Unit or Vector3.zero
end

RunService:BindToRenderStep("ViewersVsMeMovementSafety",Enum.RenderPriority.Last.Value,function()
	local char=player.Character
	local hum=char and char:FindFirstChildOfClass("Humanoid")
	local root=char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health<=0 then return end
	if not center then setZone(char,root) end
	if player:GetAttribute("AutoMovePaused")==true then idleSince=nil return end

	if safePosition(root.Position,char) then lastSafe=root.Position end
	if not roamTarget or os.clock()>=nextRoamAt or (Vector3.new(roamTarget.X-root.Position.X,0,roamTarget.Z-root.Position.Z)).Magnitude<4 then
		chooseRoamTarget(char,root)
	end

	local move=hum.MoveDirection
	local flat=Vector3.new(move.X,0,move.Z)
	local override=false

	-- If AutoCombat wants to leave the grass, redirect it across the grass instead of pinning it in place.
	if flat.Magnitude>.05 then
		local dir=flat.Unit
		for _,dist in ipairs({3,6,9}) do
			if not safePosition(root.Position+dir*dist,char) then
				override=true
				break
			end
		end
		idleSince=nil
	else
		idleSince=idleSince or os.clock()
		if os.clock()-idleSince>.35 then override=true end
	end

	if override then
		local dir=directionTo(root,roamTarget)
		if dir.Magnitude<.05 or not safePosition(root.Position+dir*4,char) then
			chooseRoamTarget(char,root)
			dir=directionTo(root,roamTarget)
		end
		if dir.Magnitude>.05 then hum:Move(dir,false) else hum:Move(Vector3.zero,false) end
	end

	-- Absolute failsafe: never let the root cross off the grass.
	if not safePosition(root.Position,char) then
		local safe=lastSafe or Vector3.new(center.X,root.Position.Y,center.Z)
		root.AssemblyLinearVelocity=Vector3.new(0,root.AssemblyLinearVelocity.Y,0)
		root.CFrame=CFrame.new(safe.X,root.Position.Y,safe.Z)*root.CFrame.Rotation
		chooseRoamTarget(char,root)
		local dir=directionTo(root,roamTarget)
		if dir.Magnitude>.05 then hum:Move(dir,false) end
	end
end)

player.CharacterAdded:Connect(function(char)
	center=nil;grassPart=nil;lastSafe=nil;roamTarget=nil;idleSince=nil
	local root=char:WaitForChild("HumanoidRootPart",5)
	if root then task.wait(.25);setZone(char,root) end
end)

print("MOVEMENT SAFETY GUARD V4 READY - free grass roaming + hard boundary")
