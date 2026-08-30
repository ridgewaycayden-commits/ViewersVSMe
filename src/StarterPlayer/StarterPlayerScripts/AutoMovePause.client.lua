-- AutoMovePause.client.lua
-- HARD manual-control toggle for ViewersVSMe.
-- P pauses autonomous movement. While paused, AI Humanoid movement is physically blocked,
-- but WASD + Space still move the player manually.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local paused = false
local MANUAL_SPEED = 16

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

local function getParts()
	local char = player.Character
	if not char then return nil,nil end
	return char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

local function refresh()
	button.Text = paused and "MANUAL CONTROL [P]" or "PAUSE AUTO MOVE [P]"
	button.BackgroundColor3 = paused and Color3.fromRGB(115,38,42) or Color3.fromRGB(20,22,28)
	player:SetAttribute("AutoMovePaused", paused)
end

local function toggle()
	paused = not paused
	local hum,root = getParts()
	if hum then
		hum:Move(Vector3.zero,false)
		hum.WalkSpeed = paused and 0 or 15.5
	end
	if paused and root then
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(0,v.Y,0)
	end
	refresh()
	print("AUTO MOVE:", paused and "PAUSED / MANUAL" or "RESUMED")
end

button.Activated:Connect(toggle)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.P then toggle() end
end)

local function inputVectorWorld()
	local x,z = 0,0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then z += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then z -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end

	local localMove = Vector2.new(x,z)
	if localMove.Magnitude > 1 then localMove = localMove.Unit end
	if localMove.Magnitude < .01 then return Vector3.zero end

	local camera = workspace.CurrentCamera
	local look = camera and camera.CFrame.LookVector or Vector3.new(0,0,-1)
	local right = camera and camera.CFrame.RightVector or Vector3.new(1,0,0)
	look = Vector3.new(look.X,0,look.Z)
	right = Vector3.new(right.X,0,right.Z)
	if look.Magnitude > .01 then look = look.Unit end
	if right.Magnitude > .01 then right = right.Unit end
	return (right * localMove.X + look * localMove.Y).Unit
end

local function enforceManual()
	if not paused then return end
	local hum,root = getParts()
	if not hum or not root or hum.Health <= 0 then return end

	-- AutoCombat sets WalkSpeed and calls Humanoid:Move every RenderStepped.
	-- Force WalkSpeed to zero before physics so those AI Move() calls cannot move us.
	hum.WalkSpeed = 0
	hum:Move(Vector3.zero,false)

	-- Then apply our own manual horizontal velocity directly.
	local manual = inputVectorWorld()
	local vel = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(manual.X * MANUAL_SPEED, vel.Y, manual.Z * MANUAL_SPEED)

	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		hum.Jump = true
	end
end

-- Run on BOTH sides of physics so AutoCombat cannot sneak a movement command through.
RunService.PreSimulation:Connect(enforceManual)
RunService.PostSimulation:Connect(enforceManual)

player.CharacterAdded:Connect(function()
	task.wait(.25)
	local hum = getParts()
	if hum and paused then hum.WalkSpeed = 0 end
	refresh()
end)

refresh()
print("AUTO MOVE PAUSE V7 READY - hard AI stop + direct manual WASD")
