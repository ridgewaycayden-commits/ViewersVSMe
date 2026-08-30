-- TestButton.client.lua
-- VIEWERS VS ME - invisible first-person test spawner.
-- T still spawns 10 zombies; there is no visible test button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("TikTokTestSpawn",20)

if not remote then
	warn("TestButton: TikTokTestSpawn missing after 20 seconds.")
	return
end

local busy = false
local function spawnTen()
	if busy then return end
	busy = true
	remote:FireServer(10)
	task.delay(.8,function()
		busy = false
	end)
end

UserInputService.InputBegan:Connect(function(input,gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.T then
		spawnTen()
	end
end)

print("TEST HOTKEY READY - press T to spawn 10 zombies; no visible test button")
