-- MovementSafetyGuard.client.lua
-- VIEWERS VS ME - MOVEMENT SAFETY GUARD V1
-- Prevents AutoCombat from backing/running into boxes, buildings and other hard blockers.

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

local function clearDirection(root,dir)
	if dir.Magnitude<.05 then return false end
	dir=Vector3.new(dir.X,0,dir.Z).Unit
	rayParams.FilterDescendantsInstances={player.Character,workspace:FindFirstChild("TikTokEnemies")}
	local origin=root.Position+Vector3.new(0,1.7,0)
	local right=Vector3.new(-dir.Z,0,dir.X)
	for _,off in ipairs({0,-1.4,1.4}) do
		local hit=workspace:Raycast(origin+right*off,dir*6,rayParams)
		if hit and hit.Instance and hit.Instance.CanCollide and hit.Normal.Y<.6 then return false end
	end
	local ground=workspace:Raycast(root.Position+dir*5+Vector3.new(0,5,0),Vector3.new(0,-10,0),rayParams)
	return ground and ground.Instance and ground.Instance.CanCollide and ground.Normal.Y>.72
end

local stuckSince=nil
local lastPos=nil
local escapeUntil=0
local escapeDir=nil

RunService:BindToRenderStep("ViewersVsMeMovementSafety",Enum.RenderPriority.Camera.Value+20,function()
	local char=player.Character
	local hum=char and char:FindFirstChildOfClass("Humanoid")
	local root=char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health<=0 or player:GetAttribute("AutoMovePaused")==true then
		stuckSince=nil;lastPos=root and root.Position or nil;escapeDir=nil;return
	end

	local move=hum.MoveDirection
	local flat=Vector3.new(move.X,0,move.Z)
	if flat.Magnitude<.08 then
		stuckSince=nil;lastPos=root.Position;return
	end
	flat=flat.Unit

	-- Detect a hard blocker directly in the movement corridor.
	rayParams.FilterDescendantsInstances={char,workspace:FindFirstChild("TikTokEnemies")}
	local origin=root.Position+Vector3.new(0,1.6,0)
	local blocker=workspace:Raycast(origin,flat*5.5,rayParams)
	local blocked=blocker and blocker.Instance and blocker.Instance.CanCollide and blocker.Normal.Y<.6

	-- Detect being physically stuck even if the blocker has a generic name.
	if lastPos then
		local moved=(Vector3.new(root.Position.X,0,root.Position.Z)-Vector3.new(lastPos.X,0,lastPos.Z)).Magnitude
		if moved<.025 then stuckSince=stuckSince or os.clock() else stuckSince=nil end
	end
	lastPos=root.Position
	local stuck=stuckSince and (os.clock()-stuckSince>.45)

	if blocked or stuck or os.clock()<escapeUntil then
		if os.clock()>=escapeUntil or not escapeDir then
			local right=Vector3.new(-flat.Z,0,flat.X)
			local options={right,-right,(right+flat*.35).Unit,(-right+flat*.35).Unit,-flat}
			if rng:NextNumber()<.5 then options[1],options[2]=options[2],options[1] end
			escapeDir=nil
			for _,dir in ipairs(options) do
				if clearDirection(root,dir) then escapeDir=dir break end
			end
			escapeUntil=os.clock()+.65
		end
		if escapeDir then hum:Move(escapeDir,false) else hum:Move(Vector3.zero,false) end
		if stuck then hum.Jump=true end
		stuckSince=nil
	end
end)

print("MOVEMENT SAFETY GUARD V1 READY - box/building escape enabled")
