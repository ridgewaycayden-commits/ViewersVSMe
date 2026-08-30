-- EventContextPopup.client.lua
-- VIEWERS VS ME - contextual event popup V2
-- Accurate event messages, positioned away from the boss HUD.

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
gui.DisplayOrder = 9000
gui.Parent = playerGui

local banner = Instance.new("Frame")
banner.AnchorPoint = Vector2.new(1,0)
banner.Position = UDim2.new(1,560,0,165)
banner.Size = UDim2.fromOffset(520,104)
banner.BackgroundColor3 = Color3.fromRGB(7,9,13)
banner.BackgroundTransparency = .04
banner.BorderSizePixel = 0
banner.ZIndex = 50
banner.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,14)
corner.Parent = banner

local stroke = Instance.new("UIStroke")
stroke.Thickness = 3
stroke.Transparency = .02
stroke.Parent = banner

local side = Instance.new("TextLabel")
side.Position = UDim2.fromOffset(16,11)
side.Size = UDim2.fromOffset(110,24)
side.BackgroundTransparency = 1
side.Font = Enum.Font.GothamBlack
side.TextSize = 18
side.TextXAlignment = Enum.TextXAlignment.Left
side.Text = "EVENT"
side.ZIndex = 51
side.Parent = banner

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(16,36)
title.Size = UDim2.new(1,-32,0,30)
title.BackgroundTransparency = 1
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBlack
title.TextSize = 21
title.TextColor3 = Color3.new(1,1,1)
title.Text = "VIEWER EVENT"
title.ZIndex = 51
title.Parent = banner

local sub = Instance.new("TextLabel")
sub.Position = UDim2.fromOffset(16,68)
sub.Size = UDim2.new(1,-32,0,25)
sub.BackgroundTransparency = 1
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.Font = Enum.Font.GothamMedium
sub.TextSize = 13
sub.TextColor3 = Color3.fromRGB(210,218,232)
sub.TextWrapped = true
sub.Text = ""
sub.ZIndex = 51
sub.Parent = banner

local serial = 0
local function show(data)
	serial += 1
	local mine = serial
	local c = typeof(data.color)=="Color3" and data.color or Color3.fromRGB(90,220,255)
	stroke.Color = c
	local sideText = tostring(data.side or "EVENT")
	side.Text = sideText
	side.TextColor3 = (sideText=="AGAINST") and Color3.fromRGB(255,80,80) or Color3.fromRGB(90,255,155)
	title.Text = tostring(data.title or "VIEWER EVENT")
	local sender = tostring(data.sender or "VIEWER")
	local subtitle = tostring(data.subtitle or "")
	sub.Text = subtitle ~= "" and ("@"..sender.."  •  "..subtitle) or ("@"..sender)
	banner.Position = UDim2.new(1,560,0,165)
	TweenService:Create(banner,TweenInfo.new(.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(1,-20,0,165)}):Play()
	task.delay(3.2,function()
		if serial ~= mine then return end
		TweenService:Create(banner,TweenInfo.new(.24,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Position=UDim2.new(1,560,0,165)}):Play()
	end)
end

local function suppressGenericBanners()
	local normal = playerGui:FindFirstChild("GiftFXGui")
	if normal then
		for _,v in ipairs(normal:GetChildren()) do
			if v:IsA("Frame") and v.Name ~= "" then
				local sx,sy=v.Size.X.Offset,v.Size.Y.Offset
				if (sx==560 and sy==86) then v.Visible=false end
			end
		end
	end
	local premium = playerGui:FindFirstChild("PremiumGiftHUD")
	if premium then
		for _,v in ipairs(premium:GetChildren()) do
			if v:IsA("Frame") then
				local sx,sy=v.Size.X.Offset,v.Size.Y.Offset
				if (sx==620 and sy==86) then v.Visible=false end
			end
		end
	end
end

playerGui.ChildAdded:Connect(function()
	task.defer(suppressGenericBanners)
end)
task.spawn(function()
	while gui.Parent do
		suppressGenericBanners()
		task.wait(.5)
	end
end)

remote.OnClientEvent:Connect(show)
print("EVENT CONTEXT POPUP V2 READY - readable alerts, boss HUD safe")
