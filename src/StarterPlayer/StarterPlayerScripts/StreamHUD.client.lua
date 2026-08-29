-- StreamHUD.client.lua
-- COMPACT HUD VERSION
-- Put in StarterPlayer > StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local old = playerGui:FindFirstChild("ViewersVsMeHUD")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ViewersVsMeHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 999
gui.Parent = playerGui

local function round(obj, px)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = obj
end

local function stroke(obj, transparency)
	local s = Instance.new("UIStroke")
	s.Thickness = 1
	s.Transparency = transparency or .75
	s.Color = Color3.fromRGB(255,255,255)
	s.Parent = obj
end

local top = Instance.new("Frame")
top.Size = UDim2.fromOffset(320, 78)
top.Position = UDim2.fromOffset(18, 18)
top.BackgroundColor3 = Color3.fromRGB(8,10,15)
top.BackgroundTransparency = .18
top.BorderSizePixel = 0
top.Parent = gui
round(top, 14)
stroke(top, .82)

local dot = Instance.new("Frame")
dot.Size = UDim2.fromOffset(9,9)
dot.Position = UDim2.fromOffset(13,14)
dot.BackgroundColor3 = Color3.fromRGB(255,50,65)
dot.BorderSizePixel = 0
dot.Parent = top
round(dot,99)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-36,0,26)
title.Position = UDim2.fromOffset(29,5)
title.BackgroundTransparency = 1
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBlack
title.TextSize = 18
title.TextColor3 = Color3.new(1,1,1)
title.Text = "VIEWERS VS ME • LIVE"
title.Parent = top

local stats = Instance.new("TextLabel")
stats.Size = UDim2.new(1,-24,0,22)
stats.Position = UDim2.fromOffset(12,31)
stats.BackgroundTransparency = 1
stats.TextXAlignment = Enum.TextXAlignment.Left
stats.Font = Enum.Font.GothamBold
stats.TextSize = 14
stats.TextColor3 = Color3.fromRGB(228,232,240)
stats.Text = "KILLS 0   •   ENEMIES 0   •   WAVE 1"
stats.Parent = top

local sub = Instance.new("TextLabel")
sub.Size = UDim2.new(1,-24,0,18)
sub.Position = UDim2.fromOffset(12,53)
sub.BackgroundTransparency = 1
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.Font = Enum.Font.GothamMedium
sub.TextSize = 11
sub.TextColor3 = Color3.fromRGB(145,155,175)
sub.Text = "SEND GIFTS TO MAKE IT HARDER"
sub.Parent = top

local feed = Instance.new("Frame")
feed.Size = UDim2.fromOffset(330, 112)
feed.Position = UDim2.new(1,-348,1,-130)
feed.BackgroundColor3 = Color3.fromRGB(8,10,15)
feed.BackgroundTransparency = .28
feed.BorderSizePixel = 0
feed.Parent = gui
round(feed,14)
stroke(feed,.88)

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0,8)
pad.PaddingBottom = UDim.new(0,8)
pad.PaddingLeft = UDim.new(0,10)
pad.PaddingRight = UDim.new(0,10)
pad.Parent = feed

local layout = Instance.new("UIListLayout")
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Padding = UDim.new(0,3)
layout.Parent = feed

local helper = Instance.new("TextLabel")
helper.AnchorPoint = Vector2.new(.5,1)
helper.Position = UDim2.new(.5,0,1,-10)
helper.Size = UDim2.fromOffset(180,24)
helper.BackgroundColor3 = Color3.fromRGB(8,10,15)
helper.BackgroundTransparency = .38
helper.TextColor3 = Color3.fromRGB(175,185,200)
helper.Font = Enum.Font.GothamBold
helper.TextSize = 11
helper.Text = "F10 • CLEAN STREAM"
helper.Parent = gui
round(helper,9)

local banner = Instance.new("TextLabel")
banner.AnchorPoint = Vector2.new(.5,0)
banner.Position = UDim2.new(.5,0,0,24)
banner.Size = UDim2.fromOffset(560,54)
banner.BackgroundColor3 = Color3.fromRGB(8,10,15)
banner.BackgroundTransparency = 1
banner.TextTransparency = 1
banner.TextColor3 = Color3.new(1,1,1)
banner.TextStrokeTransparency = .55
banner.Font = Enum.Font.GothamBlack
banner.TextSize = 26
banner.Parent = gui
round(banner,12)

local kills, active, wave = 0,0,1
local streamClean = false

local function refresh()
	stats.Text = ("KILLS %d   •   ENEMIES %d   •   WAVE %d"):format(kills,active,wave)
end

local function addFeed(text)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1,0,0,22)
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextColor3 = Color3.new(1,1,1)
	label.Text = text
	label.Parent = feed

	local rows = {}
	for _,v in ipairs(feed:GetChildren()) do
		if v:IsA("TextLabel") then table.insert(rows,v) end
	end
	if #rows > 4 then rows[1]:Destroy() end
end

local bannerToken = 0
local function showBanner(text)
	bannerToken += 1
	local token = bannerToken
	banner.Text = text
	TweenService:Create(banner,TweenInfo.new(.12),{TextTransparency = 0,BackgroundTransparency = .2}):Play()
	task.delay(1.65,function()
		if token ~= bannerToken then return end
		TweenService:Create(banner,TweenInfo.new(.25),{TextTransparency = 1,BackgroundTransparency = 1}):Play()
	end)
end

local function setCleanMode(on)
	streamClean = on
	feed.Visible = not on
	helper.Visible = not on
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F10 then setCleanMode(not streamClean) end
end)

addFeed("HUD READY • WAITING FOR EVENTS")

task.spawn(function()
	local remote = ReplicatedStorage:WaitForChild("TikTokStreamEvent",15)
	if not remote then
		addFeed("EVENT LINK NOT READY")
		warn("StreamHUD: TikTokStreamEvent not found.")
		return
	end
	addFeed("LIVE EVENT LINK READY")
	remote.OnClientEvent:Connect(function(event)
		if type(event) ~= "table" then return end
		if event.kind == "stats" then
			kills = event.kills or kills
			active = event.active or active
			wave = event.wave or wave
			refresh()
			return
		end
		if event.kind == "gift" then
			kills = event.kills or kills
			active = event.active or active
			wave = event.wave or wave
			refresh()
			local sender = tostring(event.sender or "viewer")
			local gift = tostring(event.gift or "gift")
			local action = tostring(event.action or "enemy")
			local amount = tonumber(event.amount) or 1
			if action == "enemy" then
				local word = amount == 1 and "ENEMY" or "ENEMIES"
				addFeed(("@%s • %d %s • %s"):format(sender,amount,word,gift))
				showBanner(("@%s SENT %d %s"):format(sender,amount,word))
			elseif action == "boss" then
				addFeed(("@%s • BOSS • %s"):format(sender,gift))
				showBanner(("@%s DEPLOYED A BOSS"):format(sender))
			elseif action == "heal" then
				addFeed(("@%s • +%d HP • %s"):format(sender,amount,gift))
				showBanner(("@%s GAVE +%d HP"):format(sender,amount))
			elseif action == "shield" then
				addFeed(("@%s • SHIELD • %s"):format(sender,gift))
				showBanner(("@%s GAVE A SHIELD"):format(sender))
			elseif action == "explosion" then
				addFeed(("@%s • CHAOS • %s"):format(sender,gift))
				showBanner(("@%s DROPPED CHAOS"):format(sender))
			end
		elseif event.kind == "banner" then
			showBanner(tostring(event.title or "VIEWER EVENT"))
		end
	end)
end)

refresh()
