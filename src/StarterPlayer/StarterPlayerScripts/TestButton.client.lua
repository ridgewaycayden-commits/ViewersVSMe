-- TestButton.client.lua
-- Put in StarterPlayer > StarterPlayerScripts
-- Works with self-contained TestSpawner V4.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
button.Size = UDim2.fromOffset(165,38)
button.Position = UDim2.new(0,18,1,-56)
button.BackgroundColor3 = Color3.fromRGB(18,22,30)
button.BackgroundTransparency = .08
button.BorderSizePixel = 0
button.Text = "TEST • 10 ZOMBIES"
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

button.Text = "TEST • 10 ZOMBIES"

button.MouseButton1Click:Connect(function()
	button.Text = "SPAWNING..."
	remote:FireServer(10)
	task.wait(.8)
	button.Text = "TEST • 10 ZOMBIES"
end)

print("TestButton V4 connected.")
