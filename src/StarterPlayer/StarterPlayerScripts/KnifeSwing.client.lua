-- KnifeSwing.client.lua
-- VIEWERS VS ME - first-person knife swing animation overlay.
-- Adds a fast alternating slash/stab motion to the imported Knife viewmodel
-- without replacing AutoCombat or the TikTok gift/combat systems.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local enemies = workspace:WaitForChild("TikTokEnemies")

local swingStart = -10
local swingDuration = 0.30
local nextSwing = 0
local swingSide = 1
local lastApplied = CFrame.identity

local function aliveEnemy(model)
	if not model:IsA("Model") or model:GetAttribute("Dead") == true then return false end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	return hum and root and hum.Health > 0
end

local function knifeTargetInRange()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false end

	for _, enemy in ipairs(enemies:GetChildren()) do
		if aliveEnemy(enemy) then
			local er = enemy:FindFirstChild("HumanoidRootPart")
			if er and (er.Position - root.Position).Magnitude <= 10.5 then
				return true
			end
		end
	end
	return false
end

local function swingOffset(alpha)
	-- 0 -> 1 -> 0 arc. Fast attack, slightly slower recovery.
	local phase
	if alpha < 0.42 then
		phase = alpha / 0.42
	else
		phase = 1 - ((alpha - 0.42) / 0.58)
	end
	phase = math.clamp(phase, 0, 1)
	local eased = math.sin(phase * math.pi * 0.5)

	local yaw = math.rad(48 * swingSide) * eased
	local roll = math.rad(-62 * swingSide) * eased
	local pitch = math.rad(-24) * eased
	local x = -0.34 * swingSide * eased
	local y = 0.24 * eased
	local z = -0.55 * eased

	return CFrame.new(x, y, z) * CFrame.Angles(pitch, yaw, roll)
end

RunService.RenderStepped:Connect(function()
	-- Defer so AutoCombat gets to place the weapon first, then layer the knife swing on top.
	task.defer(function()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local vm = camera:FindFirstChild("FPSViewModel_Knife")

		if not vm or player:GetAttribute("CurrentWeapon") ~= "Sword" then
			lastApplied = CFrame.identity
			return
		end

		local now = os.clock()
		if now >= nextSwing and knifeTargetInRange() then
			swingStart = now
			nextSwing = now + 0.45
			swingSide = -swingSide
		end

		-- Remove our previous frame's overlay before applying the new one.
		if lastApplied ~= CFrame.identity then
			vm:PivotTo(vm:GetPivot() * lastApplied:Inverse())
		end

		local elapsed = now - swingStart
		if elapsed >= 0 and elapsed <= swingDuration then
			local offset = swingOffset(elapsed / swingDuration)
			vm:PivotTo(vm:GetPivot() * offset)
			lastApplied = offset
		else
			lastApplied = CFrame.identity
		end
	end)
end)

print("KNIFE SWING V1 READY - alternating slash animation")
