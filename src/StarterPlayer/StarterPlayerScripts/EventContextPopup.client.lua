-- EventContextPopup.client.lua
-- Clean contextual event popup. Keeps flashes/shakes from the original FX scripts,
-- but hides their generic top banners so the player sees one accurate message.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("EventContextFX")

local old = playerGui:FindFirstChild("EventContextPopup")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "EventContextPopup"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5000
gui.Parent = playerGui

local banner = Instance.new("Frame")
banner.AnchorPoint = Vector2.new(.5,0)
banner.Position = UDim2.new(.5,0,0,-110)
banner.Size = UDim2.fromOffset(650,88)
banner.BackgroundColor3 = Color3.fromRGB(8,10,15)
banner.BackgroundTransparency = .08
banner.BorderSizePixel = 0
banner.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,14)
corner.Parent = banner

local stroke = Instance.new("UIStroke")
stroke.Thickness = 2.5
stroke.Transparency = .06
stroke.Parent = banner

local side = Instance.new("TextLabel")
side.Size = UDim2.fromOffset(118,88)
side.BackgroundTransparency = 1
side.Font = Enum.Font.GothamBlack
side.TextSize = 18
side.Text = "EVENT"
side.Parent = banner

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(124,10)
title.Size = UDim2.new(1,-136,0,31)
title.BackgroundTransparency = 1
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBlack
title.TextSize = 21
title.TextColor3 = Color3.new(1,1,1)
title.Parent = banner

local sub = Instance.new("TextLabel")
sub.Position = UDim2.fromOffset(124,42)
sub.Size = UDim2.new(1,-136,0,34)
sub.BackgroundTransparency = 1
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.Font = Enum.Font.GothamMedium
sub.TextSize = 14
sub.TextColor3 = Color3.fromRGB(210,218,232)
sub.TextWrapped = true
sub.Parent = banner

local serial = 0
local function show(data)
	serial += 1
	local mine = serial
	local c = typeof(data.color)=="Color3" and data.color or Color3.fromRGB(90,220,255)
	stroke.Color = c
	side.Text = tostring(data.side or "EVENT")
	side.TextColor3 = (data.side=="AGAINST") and Color3.fromRGB(255,80,80) or Color3.fromRGB(90,255,155)
	title.Text = tostring(data.title or "VIEWER EVENT")
	sub.Text = "@"..tostring(data.sender or "VIEWER").." • "..tostring(data.subtitle or "")
	banner.Position = UDim2.new(.5,0,0,-110)
	TweenService:Create(banner,TweenInfo.new(.24,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(.5,0,0,26)}):Play()
	task.delay(2.9,function()
		if serial ~= mine then return end
		TweenService:Create(banner,TweenInfo.new(.25,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Position=UDim2.new(.5,0,0,-110)}):Play()
	end)
end

local function suppressGenericBanners()
	local normal = playerGui:FindFirstChild("GiftFXGui")
	if normal then
		for _,v in ipairs(normal:GetChildren()) do
			if v:IsA("Frame") and v.Size.X.Offset == 560 and v.Size.Y.Offset == 86 then
				v.Visible = false
			end
		end
	end
	local premium = playerGui:FindFirstChild("PremiumGiftHUD")
	if premium then
		for _,v in ipairs(premium:GetChildren()) do
			if v:IsA("Frame") and v.Size.X.Offset == 620 and v.Size.Y.Offset == 86 then
				v.Visible = false
			end
		end
	end
end

playerGui.ChildAdded:Connect(function()
	task.defer(suppressGenericBanners)
end)
task.spawn(function()
	for _=1,20 do suppressGenericBanners();task.wait(.5) end
end)

remote.OnClientEvent:Connect(show)
print("EVENT CONTEXT POPUP READY - accurate action banners")
