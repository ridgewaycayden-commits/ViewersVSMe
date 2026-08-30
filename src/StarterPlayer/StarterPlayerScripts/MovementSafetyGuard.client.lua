-- MovementSafetyGuard.client.lua
-- VIEWERS VS ME - MOVEMENT SAFETY GUARD V6
-- Smooth center-grass roaming: no-enemy movement commits to one roam target instead of fighting AutoCombat.

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
local roamTarget=nil
local nextRoamAt=0
local lastSafe=nil
local lastPos=nil
local stuckSince=nil

local function enemiesFolder()
	return workspace:FindFirstChild("TikTokEnemies")
end

local function hasLiveEnemies()
	local folder=enemiesFolder()
	if not folder then return false end
	for _,m in ipairs(folder:GetChildren()) do
		local h=m:FindFirstChildOfClass("Humanoid")
		if h and h.Health>0 then return true end
	end
	return false
end

local function groundBelow(pos,char)
	rayParams.FilterDescendantsInstances={char,enemiesFolder()}
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
	lastPos=root.Position
	stuckSince=nil
	print("CENTER GRASS ACTIVE ZONE",grassPart and grassPart:GetFullName() or "spawn fallback","half",math.floor(halfX),math.floor(halfZ))
end

local function insideBounds(pos,padding)
	if not center then return true end
	padding=padding or 0
	return math.abs(pos.X-center.X)<=math.max(2,halfX-padding) and math.abs(pos.Z-center.Z)<=math.max(2,halfZ-padding)
end

local function chooseRoamTarget(root)
	for _=1,40 do
		local x=center.X+rng:NextNumber(-halfX*.68,halfX*.68)
		local z=center.Z+rng:NextNumber(-halfZ*.68,halfZ*.68)
		local p=Vector3.new(x,root.Position.Y,z)
		if insideBounds(p,3) and (Vector3.new(x-root.Position.X,0,z-root.Position.Z)).Magnitude>10 then
			roamTarget=p
			-- Commit to the destination. Only change early if reached or genuinely stuck.
			nextRoamAt=os.clock()+rng:NextNumber(7,11)
			return
		end
	end
	roamTarget=Vector3.new(center.X,root.Position.Y,center.Z)
	nextRoamAt=os.clock()+5
end

local function dirTo(root,target)
	if not target then return Vector3.zero end
	local d=Vector3.new(target.X-root.Position.X,0,target.Z-root.Position.Z)
	return d.Magnitude>.35 and d.Unit or Vector3.zero
end

local function blocked(root,dir,char)
	if dir.Magnitude<.05 then return true end
	rayParams.FilterDescendantsInstances={char,enemiesFolder()}
	local origin=root.Position+Vector3.new(0,1.7,0)
	local right=Vector3.new(-dir.Z,0,dir.X)
	for _,off in ipairs({0,-1.25,1.25}) do
		local hit=workspace:Raycast(origin+right*off,dir.Unit*4.5,rayParams)
		if hit and hit.Instance and hit.Instance.CanCollide and hit.Normal.Y<.55 then return true end
	end
	return false
end

local function pickSafeDirection(root,preferred,char)
	local base=preferred
	if base.Magnitude<.05 then base=dirTo(root,roamTarget) end
	if base.Magnitude<.05 then base=Vector3.new(1,0,0) end
	base=base.Unit
	for _,ang in ipairs({0,18,-18,38,-38,65,-65,95,-95,135,-135,180}) do
		local dir=(CFrame.Angles(0,math.rad(ang),0):VectorToWorldSpace(base)).Unit
		if insideBounds(root.Position+dir*5,3) and not blocked(root,dir,char) then return dir end
	end
	local inward=Vector3.new(center.X-root.Position.X,0,center.Z-root.Position.Z)
	return inward.Magnitude>.1 and inward.Unit or Vector3.zero
end

RunService:BindToRenderStep("ViewersVsMeMovementSafety",Enum.RenderPriority.Last.Value,function()
	local char=player.Character
	local hum=char and char:FindFirstChildOfClass("Humanoid")
	local root=char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health<=0 then return end
	if not center then setZone(char,root) end
	if player:GetAttribute("AutoMovePaused")==true then
		hum:Move(Vector3.zero,false)
		lastPos=root.Position
		stuckSince=nil
		return
	end

	if insideBounds(root.Position,0) then lastSafe=root.Position end

	local noEnemies=not hasLiveEnemies()
	local distanceToRoam=roamTarget and Vector3.new(roamTarget.X-root.Position.X,0,roamTarget.Z-root.Position.Z).Magnitude or 0
	if not roamTarget or distanceToRoam<3.5 or os.clock()>=nextRoamAt then
		chooseRoamTarget(root)
	end

	local desired
	if noEnemies then
		-- Critical jitter fix: ignore AutoCombat's idle left/right commands and commit to one grass target.
		desired=dirTo(root,roamTarget)
	else
		local requested=Vector3.new(hum.MoveDirection.X,0,hum.MoveDirection.Z)
		if requested.Magnitude>.08 and insideBounds(root.Position+requested.Unit*6,3) then
			desired=requested.Unit
		else
			desired=dirTo(root,roamTarget)
		end
	end

	if desired.Magnitude>.05 and not insideBounds(root.Position+desired*5,3) then
		desired=Vector3.new(center.X-root.Position.X,0,center.Z-root.Position.Z)
		if desired.Magnitude>.05 then desired=desired.Unit end
	end

	desired=pickSafeDirection(root,desired,char)

	if lastPos then
		local moved=(Vector3.new(root.Position.X,0,root.Position.Z)-Vector3.new(lastPos.X,0,lastPos.Z)).Magnitude
		if moved<.015 then stuckSince=stuckSince or os.clock() else stuckSince=nil end
		if stuckSince and os.clock()-stuckSince>.75 then
			chooseRoamTarget(root)
			desired=pickSafeDirection(root,dirTo(root,roamTarget),char)
			hum.Jump=true
			stuckSince=nil
		end
	end
	lastPos=root.Position

	hum:Move(desired,false)

	if not insideBounds(root.Position,0) then
		local safe=lastSafe or Vector3.new(center.X,root.Position.Y,center.Z)
		root.AssemblyLinearVelocity=Vector3.new(0,root.AssemblyLinearVelocity.Y,0)
		root.CFrame=CFrame.new(safe.X,root.Position.Y,safe.Z)*root.CFrame.Rotation
		chooseRoamTarget(root)
	end
end)

player.CharacterAdded:Connect(function(char)
	center=nil;grassPart=nil;roamTarget=nil;lastSafe=nil;lastPos=nil;stuckSince=nil
	local root=char:WaitForChild("HumanoidRootPart",5)
	if root then task.wait(.25);setZone(char,root) end
end)

print("MOVEMENT SAFETY GUARD V6 READY - smooth idle grass roaming, no-enemy jitter fixed")
