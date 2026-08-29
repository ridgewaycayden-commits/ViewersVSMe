-- AutoMovePause.client.lua
-- Hard pause/resume for autonomous movement while leaving combat/camera active.
-- P key or on-screen button toggles the movement lock.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local paused = false
local lockedPosition = nil

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
button.Size = UDim2.fromOffset(190,46)
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
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return hum, root
end

local function applyHardPause()
	local hum, root = characterParts()
	if not hum or not root then return end
	if not lockedPosition then lockedPosition = root.Position end
	hum:Move(Vector3.zero, false)
	hum.WalkSpeed = 0
	hum.Jump = false
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	-- Preserve whatever facing AutoCombat/camera wants, but force XYZ back to the pause point.
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X,0,look.Z)
	if flat.Magnitude < .01 then flat = Vector3.new(0,0,-1) else flat = flat.Unit end
	root.CFrame = CFrame.lookAt(lockedPosition, lockedPosition + flat)
end

local function refresh()
	button.Text = paused and "RESUME AUTO MOVE [P]" or "PAUSE AUTO MOVE [P]"
	button.BackgroundColor3 = paused and Color3.fromRGB(115,38,42) or Color3.fromRGB(20,22,28)
	player:SetAttribute("AutoMovePaused", paused)
end

local function toggle()
	paused = not paused
	local hum, root = characterParts()
	if paused then
		lockedPosition = root and root.Position or nil
		applyHardPause()
	else
		lockedPosition = nil
		if hum then hum.WalkSpeed = 16 end
	end
	refresh()
end

button.Activated:Connect(toggle)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.P then toggle() end
end)

-- AutoCombat issues Humanoid:Move every frame. Run after it and hard-lock the
-- root position so no pathing/strafe/roam command can physically move the player.
RunService:BindToRenderStep("AutoMovePauseOverride", Enum.RenderPriority.Last.Value + 10, function()
	if paused then applyHardPause() end
end)

player.CharacterAdded:Connect(function()
	lockedPosition = nil
	task.wait(.25)
	if paused then
		local _, root = characterParts()
		lockedPosition = root and root.Position or nil
		applyHardPause()
	end
	refresh()
end)

refresh()
print("AUTO MOVE PAUSE V2 READY - hard position lock")
