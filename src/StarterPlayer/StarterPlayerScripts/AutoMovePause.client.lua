-- AutoMovePause.client.lua
-- Reliable manual-control toggle for ViewersVSMe.
-- P pauses ONLY autonomous movement; WASD + Space still work.
-- Uses PreSimulation so our manual input overrides AutoCombat's RenderStepped Move() before physics.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local paused = false

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

local function getHumanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function refresh()
	button.Text = paused and "MANUAL CONTROL [P]" or "PAUSE AUTO MOVE [P]"
	button.BackgroundColor3 = paused and Color3.fromRGB(115,38,42) or Color3.fromRGB(20,22,28)
	player:SetAttribute("AutoMovePaused", paused)
end

local function toggle()
	paused = not paused
	local hum = getHumanoid()
	if hum then
		hum.WalkSpeed = paused and 16 or 15.5
		hum:Move(Vector3.zero, false)
	end
	refresh()
	print("AUTO MOVE:", paused and "PAUSED / MANUAL" or "RESUMED")
end

button.Activated:Connect(toggle)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.P then toggle() end
end)

local function manualMoveVector()
	local x,z = 0,0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then z -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then z += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end
	local v = Vector3.new(x,0,z)
	if v.Magnitude > 1 then v = v.Unit end
	return v
end

-- IMPORTANT: AutoCombat issues Humanoid:Move() in RenderStepped.
-- PreSimulation runs after rendering input logic but before physics, so this is the
-- final movement command physics receives whenever manual control is enabled.
RunService.PreSimulation:Connect(function()
	if not paused then return end
	local hum = getHumanoid()
	if not hum or hum.Health <= 0 then return end

	hum.WalkSpeed = 16
	hum:Move(manualMoveVector(), true)
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		hum.Jump = true
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(.25)
	local hum = getHumanoid()
	if hum and paused then hum.WalkSpeed = 16 end
	refresh()
end)

refresh()
print("AUTO MOVE PAUSE V6 READY - PreSimulation manual override")
