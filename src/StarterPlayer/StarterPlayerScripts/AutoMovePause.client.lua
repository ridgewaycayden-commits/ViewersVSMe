-- AutoMovePause.client.lua
-- VIEWERS VS ME - clean manual-control toggle.
-- P toggles autonomous movement. AutoCombat owns the AI and natively respects AutoMovePaused.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local paused = player:GetAttribute("AutoMovePaused") == true

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
button.Size = UDim2.fromOffset(215,46)
button.BackgroundColor3 = Color3.fromRGB(20,22,28)
button.BackgroundTransparency = .08
button.BorderSizePixel = 0
button.Font = Enum.Font.GothamBold
button.TextSize = 16
button.TextColor3 = Color3.fromRGB(235,240,245)
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

local function refresh()
	button.Text = paused and "MANUAL CONTROL [P]" or "PAUSE AUTO MOVE [P]"
	button.BackgroundColor3 = paused and Color3.fromRGB(115,38,42) or Color3.fromRGB(20,22,28)
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

button.Activated:Connect(toggle)
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
print("AUTO MOVE PAUSE V8 READY - clean toggle, no physics fighting")
