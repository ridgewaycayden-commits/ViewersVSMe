-- MovementSafetyGuard.client.lua
-- VIEWERS VS ME - MOVEMENT SAFETY GUARD V3
-- Hard movement controller: autonomous movement cannot leave the starting grass island.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")

local player=Players.LocalPlayer
local rayParams=RaycastParams.new()
rayParams.FilterType=Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater=true

local center=nil
local grassPart=nil
local halfX,halfZ=24,24
local MARGIN=3.5
local lastSafe=nil

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
			halfX=math.max(8,p.Size.X*.5-MARGIN)
			halfZ=math.max(8,p.Size.Z*.5-MARGIN)
		end
	end
	lastSafe=root.Position
	print("CENTER GRASS HARD ZONE SET",grassPart and grassPart:GetFullName() or "fallback","half",math.floor(halfX),math.floor(halfZ))
end

local function isGrassHit(hit)
	if not hit or not hit.Instance then return false end
	if grassPart and hit.Instance==grassPart then return true end
	local p=hit.Instance
	return p.Material==Enum.Material.Grass or string.lower(p.Name or ""):find("grass",1,true)~=nil
end

local function inside(pos,char)
	if not center then return true end
	local dx=math.abs(pos.X-center.X)
	local dz=math.abs(pos.Z-center.Z)
	if dx>halfX or dz>halfZ then return false end
	return isGrassHit(groundBelow(pos,char))
end

local function clampToZone(pos)
	return Vector3.new(
		math.clamp(pos.X,center.X-halfX,center.X+halfX),
		pos.Y,
		math.clamp(pos.Z,center.Z-halfZ,center.Z+halfZ)
	)
end

RunService:BindToRenderStep("ViewersVsMeMovementSafety",Enum.RenderPriority.Last.Value,function()
	local char=player.Character
	local hum=char and char:FindFirstChildOfClass("Humanoid")
	local root=char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health<=0 then return end
	if not center then setZone(char,root) end
	if player:GetAttribute("AutoMovePaused")==true then return end

	if inside(root.Position,char) then lastSafe=root.Position end

	local move=hum.MoveDirection
	local flat=Vector3.new(move.X,0,move.Z)
	if flat.Magnitude>.05 then
		local probes={3,6,9}
		for _,dist in ipairs(probes) do
			if not inside(root.Position+flat.Unit*dist,char) then
				local inward=Vector3.new(center.X-root.Position.X,0,center.Z-root.Position.Z)
				if inward.Magnitude>.2 then hum:Move(inward.Unit,false) else hum:Move(Vector3.zero,false) end
				break
			end
		end
	end

	-- Absolute failsafe. AutoCombat runs earlier in RenderStep; this runs last and physically
	-- prevents a bad path/Move command from carrying the character off the grass island.
	if not inside(root.Position,char) then
		local safe=lastSafe or clampToZone(root.Position)
		local y=root.Position.Y
		root.AssemblyLinearVelocity=Vector3.new(0,root.AssemblyLinearVelocity.Y,0)
		root.CFrame=CFrame.new(safe.X,y,safe.Z)*root.CFrame.Rotation
		local inward=Vector3.new(center.X-safe.X,0,center.Z-safe.Z)
		if inward.Magnitude>.1 then hum:Move(inward.Unit,false) else hum:Move(Vector3.zero,false) end
	end
end)

player.CharacterAdded:Connect(function(char)
	center=nil;grassPart=nil;lastSafe=nil
	local root=char:WaitForChild("HumanoidRootPart",5)
	if root then task.wait(.25);setZone(char,root) end
end)

print("MOVEMENT SAFETY GUARD V3 READY - HARD grass boundary runs after AutoCombat")
