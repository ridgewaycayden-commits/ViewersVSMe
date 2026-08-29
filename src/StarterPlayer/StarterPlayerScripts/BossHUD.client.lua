-- BossHUD.client.lua
-- VIEWERS VS ME - cinematic boss health bar.

local Players=game:GetService("Players")
local TweenService=game:GetService("TweenService")
local RunService=game:GetService("RunService")

local player=Players.LocalPlayer
local enemies=workspace:WaitForChild("TikTokEnemies")
local guiParent=player:WaitForChild("PlayerGui")

local old=guiParent:FindFirstChild("BossHUD")
if old then old:Destroy() end

local gui=Instance.new("ScreenGui")
gui.Name="BossHUD"
gui.IgnoreGuiInset=true
gui.ResetOnSpawn=false
gui.DisplayOrder=2300
gui.Parent=guiParent

local frame=Instance.new("Frame")
frame.AnchorPoint=Vector2.new(.5,0)
frame.Position=UDim2.new(.5,0,0,-120)
frame.Size=UDim2.fromOffset(650,78)
frame.BackgroundColor3=Color3.fromRGB(10,11,14)
frame.BackgroundTransparency=.08
frame.BorderSizePixel=0
frame.Parent=gui

local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,12);corner.Parent=frame
local stroke=Instance.new("UIStroke");stroke.Color=Color3.fromRGB(255,45,55);stroke.Thickness=2;stroke.Transparency=.05;stroke.Parent=frame

local title=Instance.new("TextLabel")
title.Position=UDim2.fromOffset(14,7)
title.Size=UDim2.new(1,-28,0,27)
title.BackgroundTransparency=1
title.Font=Enum.Font.GothamBlack
title.TextXAlignment=Enum.TextXAlignment.Left
title.TextSize=22
title.TextColor3=Color3.fromRGB(255,70,70)
title.Text="⚠ TITAN INFECTED"
title.Parent=frame

local hpText=Instance.new("TextLabel")
hpText.AnchorPoint=Vector2.new(1,0)
hpText.Position=UDim2.new(1,-14,0,8)
hpText.Size=UDim2.fromOffset(180,24)
hpText.BackgroundTransparency=1
hpText.Font=Enum.Font.GothamBold
hpText.TextXAlignment=Enum.TextXAlignment.Right
hpText.TextSize=16
hpText.TextColor3=Color3.fromRGB(225,225,235)
hpText.Text="1400 / 1400"
hpText.Parent=frame

local back=Instance.new("Frame")
back.Position=UDim2.fromOffset(14,43)
back.Size=UDim2.new(1,-28,0,21)
back.BackgroundColor3=Color3.fromRGB(33,12,15)
back.BorderSizePixel=0
back.Parent=frame
local backCorner=Instance.new("UICorner");backCorner.CornerRadius=UDim.new(0,6);backCorner.Parent=back

local fill=Instance.new("Frame")
fill.Size=UDim2.fromScale(1,1)
fill.BackgroundColor3=Color3.fromRGB(245,42,52)
fill.BorderSizePixel=0
fill.Parent=back
local fillCorner=Instance.new("UICorner");fillCorner.CornerRadius=UDim.new(0,6);fillCorner.Parent=fill

local gloss=Instance.new("Frame")
gloss.Size=UDim2.new(1,0,.36,0)
gloss.BackgroundColor3=Color3.fromRGB(255,120,110)
gloss.BackgroundTransparency=.55
gloss.BorderSizePixel=0
gloss.Parent=fill
local glossCorner=Instance.new("UICorner");glossCorner.CornerRadius=UDim.new(0,6);glossCorner.Parent=gloss

local activeBoss=nil
local activeHum=nil
local shown=false

local function bossName(model)
	local name=model.Name:gsub("^Boss_","")
	name=name:gsub("_ESCORT_%d+$","")
	return name
end

local function findBoss()
	for _,m in ipairs(enemies:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("Boss") and not m:GetAttribute("Dead") then
			local h=m:FindFirstChildOfClass("Humanoid")
			if h and h.Health>0 then return m,h end
		end
	end
end

local function show()
	if shown then return end
	shown=true
	frame.Position=UDim2.new(.5,0,0,-120)
	TweenService:Create(frame,TweenInfo.new(.32,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(.5,0,0,24)}):Play()
end

local function hide()
	if not shown then return end
	shown=false
	TweenService:Create(frame,TweenInfo.new(.25,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Position=UDim2.new(.5,0,0,-120)}):Play()
end

RunService.RenderStepped:Connect(function()
	if not activeBoss or not activeBoss.Parent or not activeHum or activeHum.Health<=0 or activeBoss:GetAttribute("Dead") then
		activeBoss,activeHum=findBoss()
	end

	if activeBoss and activeHum and activeHum.Health>0 then
		show()
		title.Text="⚠ TITAN INFECTED • @"..bossName(activeBoss)
		local max=math.max(1,activeHum.MaxHealth)
		local ratio=math.clamp(activeHum.Health/max,0,1)
		hpText.Text=string.format("%d / %d",math.ceil(activeHum.Health),math.ceil(max))
		fill.Size=UDim2.fromScale(ratio,1)
		if ratio<.25 then
			stroke.Transparency=.02
			fill.BackgroundColor3=Color3.fromRGB(255,25,35)
		else
			stroke.Transparency=.05
			fill.BackgroundColor3=Color3.fromRGB(245,42,52)
		end
	else
		hide()
		activeBoss=nil;activeHum=nil
	end
end)

print("BOSS HUD READY - live titan health bar enabled.")