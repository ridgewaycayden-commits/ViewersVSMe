-- EnemyMovementFix.server.lua
-- VIEWERS VS ME - ENEMY MOVEMENT FIX V1.1
-- Restores visible walking + robust path chase for normal infected and Titans.
-- Titans are intentionally slower than regular infected.
-- Works alongside TikTokGameCore V4 fixed safe spawns.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")

local enemies = workspace:WaitForChild("TikTokEnemies")
local WALK_ANIM = "rbxassetid://507777826"
local NORMAL_SPEED = 9
local TITAN_SPEED = 6

local states = setmetatable({}, {__mode = "k"})

local function hostCharacter()
	local p = Players:GetPlayers()[1]
	return p and p.Character
end

local function attachWalkAnimation(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if hum:GetAttribute("VVSWalkAnimationAttached") then return end
	hum:SetAttribute("VVSWalkAnimationAttached", true)

	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	local anim = Instance.new("Animation")
	anim.AnimationId = WALK_ANIM
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok or not track then return end
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Movement

	hum.Running:Connect(function(speed)
		if hum.Health <= 0 then
			if track.IsPlaying then track:Stop(0.08) end
		elseif speed > 0.45 then
			if not track.IsPlaying then track:Play(0.12) end
			track:AdjustSpeed(math.clamp(speed / 8.5, 0.7, 1.45))
		elseif track.IsPlaying then
			track:Stop(0.15)
		end
	end)
end

local function clearLine(fromPos, toPos, model, char)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = {model, char, enemies}
	local hit = workspace:Raycast(fromPos, toPos - fromPos, params)
	return hit == nil
end

local function newPath(fromPos, toPos)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2.1,
		AgentHeight = 5.2,
		AgentCanJump = true,
		AgentCanClimb = false,
		WaypointSpacing = 4,
	})
	local ok = pcall(function()
		path:ComputeAsync(fromPos, toPos)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then return nil end
	local waypoints = path:GetWaypoints()
	if #waypoints < 2 then return nil end
	return waypoints
end

local function stepEnemy(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 or model:GetAttribute("Dead") then return end
	attachWalkAnimation(model)

	local char = hostCharacter()
	local targetHum = char and char:FindFirstChildOfClass("Humanoid")
	local targetRoot = char and char:FindFirstChild("HumanoidRootPart")
	if not targetHum or not targetRoot or targetHum.Health <= 0 then return end

	-- Keep Titans noticeably slower without interfering with a temporary freeze at WalkSpeed 0.
	if hum.WalkSpeed > 0 then
		local desiredSpeed = model:GetAttribute("Boss") and TITAN_SPEED or NORMAL_SPEED
		if hum.WalkSpeed ~= desiredSpeed then hum.WalkSpeed = desiredSpeed end
	end

	-- Never let a stale zero speed leave enemies permanently frozen.
	if hum.WalkSpeed <= 0 and not hum:GetAttribute("GiftFrozen") then
		hum.WalkSpeed = model:GetAttribute("Boss") and TITAN_SPEED or NORMAL_SPEED
	end

	local state = states[model]
	if not state then
		state = {waypoints=nil, index=2, repathAt=0, lastPos=root.Position, stuckFor=0}
		states[model] = state
	end

	local now = os.clock()
	local distance = (targetRoot.Position - root.Position).Magnitude
	local hasLOS = clearLine(root.Position + Vector3.new(0,2,0), targetRoot.Position + Vector3.new(0,2,0), model, char)

	if now >= state.repathAt or not state.waypoints or not state.waypoints[state.index] then
		state.repathAt = now + 0.65
		state.waypoints = newPath(root.Position, targetRoot.Position)
		state.index = 2
	end

	local goal
	local wp = state.waypoints and state.waypoints[state.index]
	if wp then
		if (root.Position - wp.Position).Magnitude < 3 then
			state.index += 1
			wp = state.waypoints[state.index]
		end
		if wp then
			goal = wp.Position
			if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
		end
	end

	-- If pathfinding briefly fails but the player is directly visible, keep chasing.
	-- If a building blocks line of sight, do NOT run into the wall.
	if not goal and hasLOS then goal = targetRoot.Position end
	if goal then
		hum:MoveTo(goal)
	else
		hum:Move(Vector3.zero, false)
	end

	local moved = (root.Position - state.lastPos).Magnitude
	if moved < 0.12 and distance > 6 then
		state.stuckFor += 0.2
	else
		state.stuckFor = 0
	end
	state.lastPos = root.Position
	if state.stuckFor > 1.0 then
		hum.Jump = true
		state.waypoints = nil
		state.index = 2
		state.repathAt = 0
		state.stuckFor = 0
	end
end

for _, model in ipairs(enemies:GetChildren()) do attachWalkAnimation(model) end
enemies.ChildAdded:Connect(function(model)
	task.defer(function()
		if model.Parent then attachWalkAnimation(model) end
	end)
end)

task.spawn(function()
	while script.Parent do
		for _, model in ipairs(enemies:GetChildren()) do
			stepEnemy(model)
		end
		task.wait(0.2)
	end
end)

print("ENEMY MOVEMENT FIX V1.1 READY - zombies 9 speed, Titans 6 speed")
