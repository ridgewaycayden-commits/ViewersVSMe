-- GiftFX.client.lua
-- VIEWERS VS ME - cinematic gift announcements + test hotkeys.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local TweenService=game:GetService("TweenService")
local UserInputService=game:GetService("UserInputService")
local Lighting=game:GetService("Lighting")

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

-- Debug only. Lets us test the live gift behavior while first-person is mouse locked.
local tests={
	[Enum.KeyCode.F1]="Galaxy",
	[Enum.KeyCode.F2]="Hand Hearts",
	[Enum.KeyCode.F3]="Phoenix",
	[Enum.KeyCode.F4]="Sports Car",
	[Enum.KeyCode.F5]="Lion",
	[Enum.KeyCode.F6]="TikTok Universe",
	[Enum.KeyCode.F7]="Meteor Shower",
}
UserInputService.InputBegan:Connect(function(input,processed)
	if processed then return end
	local gift=tests[input.KeyCode]
	if gift then debugRemote:FireServer(gift) end
end)

print("GIFT FX READY - F1/F2/F3 help, F4/F5/F6/F7 attack tests.")