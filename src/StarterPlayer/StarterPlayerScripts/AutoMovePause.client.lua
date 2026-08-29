-- AutoMovePause.client.lua
-- Pauses autonomous movement while keeping MANUAL WASD + combat/camera available.
-- P key or on-screen button toggles manual-control mode.

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

local function characterParts()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum
end

local function refresh()
	button.Text = paused and "MANUAL CONTROL [P]" or "PAUSE AUTO MOVE [P]"
	button.BackgroundColor3 = paused and Color3.fromRGB(115,38,42) or Color3.fromRGB(20,22,28)
	player:SetAttribute("AutoMovePaused", paused)
end

local function toggle()
	paused = not paused
	local hum = characterParts()
	if hum then
		hum.WalkSpeed = 16
		hum:Move(Vector3.zero, false)
	end
	refresh()
end

button.Activated:Connect(toggle)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.P then toggle() end
end)

-- AutoCombat calls Humanoid:Move every frame. While paused, run AFTER it and
-- replace that command with the player's keyboard input. No key = zero movement;
-- WASD = normal manual movement. Jump remains manual too.
RunService:BindToRenderStep("ManualMoveWhileAutoPaused", Enum.RenderPriority.Last.Value + 20, function()
	if not paused then return end
	local hum = characterParts()
	if not hum or hum.Health <= 0 then return end

	local x = 0
	local z = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then z -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then z += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end

	local move = Vector3.new(x,0,z)
	if move.Magnitude > 1 then move = move.Unit end
	hum.WalkSpeed = 16
	hum:Move(move, true)
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then hum.Jump = true end
end)

player.CharacterAdded:Connect(function()
	task.wait(.2)
	local hum = characterParts()
	if hum and paused then hum.WalkSpeed = 16 end
	refresh()
end)

refresh()
print("AUTO MOVE PAUSE V4 READY - P toggles manual WASD control")
