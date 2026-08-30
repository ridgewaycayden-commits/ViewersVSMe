-- MovementSafetyGuard.client.lua
-- VIEWERS VS ME - MOVEMENT SAFETY GUARD V2
-- Keeps autonomous movement inside the center grass play area and avoids hard blockers.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")

local player=Players.LocalPlayer
local rng=Random.new()
local rayParams=RaycastParams.new()
rayParams.FilterType=Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater=true

local BLOCK_WORDS={
	"box","crate","container","building","wall","dumpster","bench","table","car","truck","bus","fence","barrier","railing","prop"
}

local center=nil
local centerRadius=32
local grassPart=nil

local function isBadBlocker(part)
	if not part or not part:IsA("BasePart") or not part.CanCollide then return false end
	local cur=part
	for _=1,6 do
		if not cur then break end
		local n=string.lower(cur.Name or "")
		for _,word in ipairs(BLOCK_WORDS) do
			if n:find(word,1,true) then return true end
		end
		cur=cur.Parent
	end
	return false
end

local function groundBelow(pos,char)
	rayParams.FilterDescendantsInstances={char,workspace:FindFirstChild("TikTokEnemies")}
	return workspace:Raycast(pos+Vector3.new(0,6,0),Vector3.new(0,-14,0),rayParams)
end

local function setCenterZone(char,root)
	center=Vector3.new(root.Position.X,root.Position.Y,root.Position.Z)
	grassPart=nil

	local hit=groundBelow(root.Position,char)
	if hit and hit.Instance and hit.Instance:IsA("BasePart") then
		local p=hit.Instance
		local n=string.lower(p.Name or "")
		if p.Material==Enum.Material.Grass or n:find("grass",1,true) then
			grassPart=p
			-- Stay a few studs inside the actual grass part edges.
			centerRadius=math.max(12,math.min(p.Size.X,p.Size.Z)*.5-4)
			center=Vector3.new(p.Position.X,root.Position.Y,p.Position.Z)
		else
			centerRadius=32
		end
	else
		centerRadius=32
	end

	print("CENTER GRASS ZONE SET - radius",math.floor(centerRadius),grassPart and grassPart:GetFullName() or "spawn-centered fallback")
end

local function insideCenterZone(pos,char)
	if not center then return true end
	local flat=Vector3.new(pos.X-center.X,0,pos.Z-center.Z)
	if flat.Magnitude>centerRadius then return false end

	local hit=groundBelow(pos,char)
	if not hit then return false end
	if grassPart then
		return hit.Instance==grassPart or hit.Instance:IsDescendantOf(grassPart.Parent) and hit.Instance.Material==Enum.Material.Grass
	end
	return hit.Material==Enum.Material.Grass or string.lower(hit.Instance.Name or ""):find("grass",1,true)~=nil
end

local function clearDirection(root,dir,char)
	if dir.Magnitude<.05 then return false end
	dir=Vector3.new(dir.X,0,dir.Z).Unit
	local probe=root.Position+dir*5
	if not insideCenterZone(probe,char) then return false end

	rayParams.FilterDescendantsInstances={char,workspace:FindFirstChild("TikTokEnemies")}
	local origin=root.Position+Vector3.new(0,1.7,0)
	local right=Vector3.new(-dir.Z,0,dir.X)
	for _,off in ipairs({0,-1.4,1.4}) do
		local hit=workspace:Raycast(origin+right*off,dir*6,rayParams)
		if hit and hit.Instance and hit.Instance.CanCollide and hit.Normal.Y<.6 then return false end
	end
	local ground=workspace:Raycast(probe+Vector3.new(0,5,0),Vector3.new(0,-10,0),rayParams)
	return ground and ground.Instance and ground.Instance.CanCollide and ground.Normal.Y>.72
end

local stuckSince=nil
local lastPos=nil
local escapeUntil=0
local escapeDir=nil

local function steerBack(root,hum,char)
	if not center then return false end
	local toCenter=Vector3.new(center.X-root.Position.X,0,center.Z-root.Position.Z)
	if toCenter.Magnitude<.1 then hum:Move(Vector3.zero,false);return true end
	local base=toCenter.Unit
	for _,ang in ipairs({0,20,-20,40,-40,65,-65,90,-90}) do
		local dir=(CFrame.Angles(0,math.rad(ang),0):VectorToWorldSpace(base)).Unit
		if clearDirection(root,dir,char) then hum:Move(dir,false);return true end
	end
	hum:Move(Vector3.zero,false)
	return true
end

RunService:BindToRenderStep("ViewersVsMeMovementSafety",Enum.RenderPriority.Camera.Value+20,function()
	local char=player.Character
	local hum=char and char:FindFirstChildOfClass("Humanoid")
	local root=char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health<=0 then
		stuckSince=nil;lastPos=root and root.Position or nil;escapeDir=nil;return
	end
	if not center then setCenterZone(char,root) end
	if player:GetAttribute("AutoMovePaused")==true then
		stuckSince=nil;lastPos=root.Position;escapeDir=nil;return
	end

	-- Hard leash: if AutoCombat ever gets us to the grass edge/outside, immediately steer inward.
	if not insideCenterZone(root.Position,char) then
		steerBack(root,hum,char)
		stuckSince=nil;lastPos=root.Position;escapeDir=nil;return
	end

	local move=hum.MoveDirection
	local flat=Vector3.new(move.X,0,move.Z)
	if flat.Magnitude<.08 then
		stuckSince=nil;lastPos=root.Position;return
	end
	flat=flat.Unit

	-- Never allow the next few studs of autonomous movement to leave the center grass.
	if not insideCenterZone(root.Position+flat*5,char) then
		steerBack(root,hum,char)
		stuckSince=nil;lastPos=root.Position;escapeDir=nil;return
	end

	rayParams.FilterDescendantsInstances={char,workspace:FindFirstChild("TikTokEnemies")}
	local origin=root.Position+Vector3.new(0,1.6,0)
	local blocker=workspace:Raycast(origin,flat*5.5,rayParams)
	local blocked=blocker and blocker.Instance and blocker.Instance.CanCollide and blocker.Normal.Y<.6

	if lastPos then
		local moved=(Vector3.new(root.Position.X,0,root.Position.Z)-Vector3.new(lastPos.X,0,lastPos.Z)).Magnitude
		if moved<.025 then stuckSince=stuckSince or os.clock() else stuckSince=nil end
	end
	lastPos=root.Position
	local stuck=stuckSince and (os.clock()-stuckSince>.45)

	if blocked or stuck or os.clock()<escapeUntil then
		if os.clock()>=escapeUntil or not escapeDir then
			local right=Vector3.new(-flat.Z,0,flat.X)
			local options={right,-right,(right+flat*.35).Unit,(-right+flat*.35).Unit}
			if rng:NextNumber()<.5 then options[1],options[2]=options[2],options[1] end
			escapeDir=nil
			for _,dir in ipairs(options) do
				if clearDirection(root,dir,char) then escapeDir=dir break end
			end
			if not escapeDir then
				local inward=Vector3.new(center.X-root.Position.X,0,center.Z-root.Position.Z)
				if inward.Magnitude>.1 and clearDirection(root,inward.Unit,char) then escapeDir=inward.Unit end
			end
			escapeUntil=os.clock()+.65
		end
		if escapeDir then hum:Move(escapeDir,false) else hum:Move(Vector3.zero,false) end
		if stuck then hum.Jump=true end
		stuckSince=nil
	end
end)

player.CharacterAdded:Connect(function(char)
	center=nil;grassPart=nil;stuckSince=nil;lastPos=nil;escapeDir=nil
	local root=char:WaitForChild("HumanoidRootPart",5)
	if root then task.wait(.3);setCenterZone(char,root) end
end)

print("MOVEMENT SAFETY GUARD V2 READY - center grass only")
