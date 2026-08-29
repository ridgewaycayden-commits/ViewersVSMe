-- GiftFX.client.lua
-- VIEWERS VS ME - cinematic gift announcements + first-person friendly test keys.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local TweenService=game:GetService("TweenService")
local UserInputService=game:GetService("UserInputService")

local player=Players.LocalPlayer
local guiParent=player:WaitForChild("PlayerGui")
local fxRemote=ReplicatedStorage:WaitForChild("GiftFX")
local debugRemote=ReplicatedStorage:WaitForChild("GiftDebug")

local old=guiParent:FindFirstChild("GiftFXGui")
if old then old:Destroy() end

local gui=Instance.new("ScreenGui")
gui.Name="GiftFXGui";gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=2500;gui.Parent=guiParent

local flash=Instance.new("Frame")
flash.Size=UDim2.fromScale(1,1);flash.BackgroundColor3=Color3.new(1,1,1);flash.BackgroundTransparency=1;flash.BorderSizePixel=0;flash.Parent=gui

local banner=Instance.new("Frame")
banner.AnchorPoint=Vector2.new(.5,0);banner.Position=UDim2.new(.5,0,0,-120);banner.Size=UDim2.fromOffset(560,86);banner.BackgroundColor3=Color3.fromRGB(12,14,20);banner.BackgroundTransparency=.08;banner.BorderSizePixel=0;banner.Parent=gui
local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,14);corner.Parent=banner
local stroke=Instance.new("UIStroke");stroke.Thickness=2;stroke.Color=Color3.fromRGB(80,220,255);stroke.Transparency=.1;stroke.Parent=banner

local side=Instance.new("TextLabel")
side.Size=UDim2.new(0,105,1,0);side.BackgroundTransparency=1;side.Font=Enum.Font.GothamBlack;side.TextScaled=true;side.Text="HELP";side.TextColor3=Color3.fromRGB(80,255,150);side.Parent=banner

local title=Instance.new("TextLabel")
title.Position=UDim2.fromOffset(110,8);title.Size=UDim2.new(1,-120,0,36);title.BackgroundTransparency=1;title.Font=Enum.Font.GothamBlack;title.TextXAlignment=Enum.TextXAlignment.Left;title.TextScaled=true;title.Text="GIFT EVENT";title.TextColor3=Color3.new(1,1,1);title.Parent=banner

local sub=Instance.new("TextLabel")
sub.Position=UDim2.fromOffset(112,45);sub.Size=UDim2.new(1,-120,0,26);sub.BackgroundTransparency=1;sub.Font=Enum.Font.GothamMedium;sub.TextXAlignment=Enum.TextXAlignment.Left;sub.TextScaled=true;sub.Text="";sub.TextColor3=Color3.fromRGB(210,218,232);sub.Parent=banner

local help=Instance.new("TextLabel")
help.AnchorPoint=Vector2.new(1,1);help.Position=UDim2.new(1,-16,1,-16);help.Size=UDim2.fromOffset(370,54);help.BackgroundColor3=Color3.fromRGB(10,12,18);help.BackgroundTransparency=.18;help.BorderSizePixel=0;help.TextColor3=Color3.fromRGB(225,232,245);help.Font=Enum.Font.GothamBold;help.TextSize=12;help.TextWrapped=true;help.Text="GIFT TESTS  Z Galaxy | X Shotgun | C Phoenix | V Horde | B Boss | N Universe | M Meteor";help.Parent=gui
local hc=Instance.new("UICorner");hc.CornerRadius=UDim.new(0,10);hc.Parent=help

task.delay(12,function() if help and help.Parent then TweenService:Create(help,TweenInfo.new(.5),{TextTransparency=.55,BackgroundTransparency=.65}):Play() end end)

local token=0
local function announce(data)
	token+=1;local my=token
	local c=typeof(data.color)=="Color3" and data.color or Color3.fromRGB(80,220,255)
	stroke.Color=c;side.Text=data.side or "GIFT";side.TextColor3=(data.side=="AGAINST") and Color3.fromRGB(255,75,75) or Color3.fromRGB(80,255,150);title.Text=data.title or "GIFT EVENT";sub.Text=data.subtitle or ""
	banner.Position=UDim2.new(.5,0,0,-120)
	TweenService:Create(banner,TweenInfo.new(.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(.5,0,0,28)}):Play()
	task.delay(2.8,function()
		if my~=token then return end
		TweenService:Create(banner,TweenInfo.new(.28,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Position=UDim2.new(.5,0,0,-120)}):Play()
	end)
end

local function screenFlash(color,alpha,duration)
	flash.BackgroundColor3=color;flash.BackgroundTransparency=alpha
	TweenService:Create(flash,TweenInfo.new(duration or .4),{BackgroundTransparency=1}):Play()
end

fxRemote.OnClientEvent:Connect(function(data)
	if type(data)~="table" then return end
	if data.kind=="announce" then announce(data)
	elseif data.kind=="heal" then screenFlash(Color3.fromRGB(65,255,135),.80,.55)
	elseif data.kind=="shield" then screenFlash(Color3.fromRGB(80,190,255),.82,.65)
	elseif data.kind=="damage" then screenFlash(Color3.fromRGB(255,40,45),.72,.38)
	elseif data.kind=="freeze" then screenFlash(Color3.fromRGB(100,220,255),.84,.7)
	elseif data.kind=="airstrike" then screenFlash(Color3.fromRGB(255,220,95),.70,.5)
	elseif data.kind=="meteor" then screenFlash(Color3.fromRGB(255,105,35),.82,.5)
	elseif data.kind=="blackout" then screenFlash(Color3.fromRGB(90,40,130),.86,.7) end
end)

-- Normal letter keys work even when first-person owns the mouse.
local tests={
	[Enum.KeyCode.Z]="Galaxy",
	[Enum.KeyCode.X]="Hand Hearts",
	[Enum.KeyCode.C]="Phoenix",
	[Enum.KeyCode.V]="Sports Car",
	[Enum.KeyCode.B]="Lion",
	[Enum.KeyCode.N]="TikTok Universe",
	[Enum.KeyCode.M]="Meteor Shower",
}
UserInputService.InputBegan:Connect(function(input,processed)
	if processed then return end
	local gift=tests[input.KeyCode]
	if gift then debugRemote:FireServer(gift) end
end)

print("GIFT FX READY - Z/X/C help, V/B/N/M attack tests.")