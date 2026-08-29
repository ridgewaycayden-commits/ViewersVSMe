-- TestButton.client.lua
-- First-person friendly test spawner for VIEWERS VS ME.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local old = playerGui:FindFirstChild("TikTokTestGui")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "TikTokTestGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 1200
gui.Parent = playerGui

local button = Instance.new("TextButton")
button.Size = UDim2.fromOffset(205,38)
button.Position = UDim2.new(0,18,1,-56)
button.BackgroundColor3 = Color3.fromRGB(18,22,30)
button.BackgroundTransparency = .08
button.BorderSizePixel = 0
button.Text = "TEST • 10 ZOMBIES  [T]"
button.TextColor3 = Color3.new(1,1,1)
button.Font = Enum.Font.GothamBlack
button.TextSize = 13
button.Parent = gui

local c = Instance.new("UICorner")
c.CornerRadius = UDim.new(0,11)
c.Parent = button

local remote = ReplicatedStorage:WaitForChild("TikTokTestSpawn",20)

if not remote then
	button.Text = "SPAWNER NOT READY"
	warn("TestButton: TikTokTestSpawn missing after 20 seconds.")
	return
end

local busy = false
local function spawnTen()
	if busy then return end
	busy = true
	button.Text = "SPAWNING..."
	remote:FireServer(10)
	task.delay(.8,function()
		if button and button.Parent then
			button.Text = "TEST • 10 ZOMBIES  [T]"
		end
		busy = false
	end)
end

button.MouseButton1Click:Connect(spawnTen)

UserInputService.InputBegan:Connect(function(input,gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.T then
		spawnTen()
	end
end)

print("TestButton V5 connected - press T to spawn 10 zombies in first person.")
