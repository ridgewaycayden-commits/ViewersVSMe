-- AutoMovePause.client.lua
-- VIEWERS VS ME - invisible manual-control toggle.
-- P still toggles autonomous movement; there is no visible pause button.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local paused = player:GetAttribute("AutoMovePaused") == true

local function refresh()
	player:SetAttribute("AutoMovePaused", paused)
end

local function stopCurrentAIMotion()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum:Move(Vector3.zero, false)
		hum.WalkSpeed = 16
	end
end

local function toggle()
	paused = not paused
	if paused then stopCurrentAIMotion() end
	refresh()
	print("AUTO MOVE:", paused and "PAUSED / MANUAL" or "RESUMED")
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.P then toggle() end
end)

player.CharacterAdded:Connect(function()
	task.wait(.25)
	if paused then stopCurrentAIMotion() end
	refresh()
end)

refresh()
print("AUTO MOVE PAUSE V9 READY - P hotkey only, no visible button")
