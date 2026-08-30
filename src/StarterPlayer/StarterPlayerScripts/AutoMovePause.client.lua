-- AutoMovePause.client.lua
-- Reliable pause: temporarily disables AutoCombat so it cannot issue movement commands.
-- Manual WASD/Space remains normal while paused. P resumes AutoCombat.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerScripts = player:WaitForChild("PlayerScripts")
local paused = false

local function findAutoCombat()
	return playerScripts:FindFirstChild("AutoCombat")
		or playerScripts:FindFirstChild("AutoCombat.client")
		or playerScripts:FindFirstChild("AutoCombat.client.lua")
end

local gui = Instance.new("ScreenGui")
gui.Name = "AutoMoveControls"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 500
gui.Parent = player:WaitForChild("PlayerGui")

local button = Instance.new("TextButton")
button.Name = "PauseAutoMove"
button.AnchorPoint = Vector2.new(1,1)
button.Position = UDim2.new(1,-22,1,-22)
button.Size = UDim2.fromOffset(210,46)
button.BackgroundColor3 = Color3.fromRGB(20,22,28)
button.BackgroundTransparency = .08
button.BorderSizePixel = 0
button.Font = Enum.Font.GothamBold
button.TextSize = 16
button.TextColor3 = Color3.fromRGB(235,240,245)
button.Text = "PAUSE AUTO MOVE [P]"
button.AutoButtonColor = true
button.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,8)
corner.Parent = button

local stroke = Instance.new("UIStroke")
stroke.Thickness = 1.5
stroke.Transparency = .25
stroke.Color = Color3.fromRGB(120,135,155)
stroke.Parent = button

local function setHumanoidManualReady()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = 16
		hum.AutoRotate = true
		hum:Move(Vector3.zero,false)
	end
end

local function refresh()
	button.Text = paused and "MANUAL CONTROL [P]" or "PAUSE AUTO MOVE [P]"
	button.BackgroundColor3 = paused and Color3.fromRGB(115,38,42) or Color3.fromRGB(20,22,28)
	player:SetAttribute("AutoMovePaused", paused)
end

local function applyState()
	local autoCombat = findAutoCombat()
	if autoCombat and autoCombat:IsA("LocalScript") then
		autoCombat.Disabled = paused
	end
	if paused then
		setHumanoidManualReady()
	end
	refresh()
end

local function toggle()
	paused = not paused
	applyState()
end

button.Activated:Connect(toggle)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.P then
		toggle()
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(.3)
	if paused then setHumanoidManualReady() end
	applyState()
end)

-- AutoCombat can arrive a moment after this script depending on Rojo/start order.
task.spawn(function()
	for _=1,30 do
		if findAutoCombat() then
			applyState()
			return
		end
		task.wait(.2)
	end
	warn("AUTO MOVE PAUSE: AutoCombat LocalScript not found")
end)

refresh()
print("AUTO MOVE PAUSE V5 READY - P disables/enables AutoCombat for true manual control")
