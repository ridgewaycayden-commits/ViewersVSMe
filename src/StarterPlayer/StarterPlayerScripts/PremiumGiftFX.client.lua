-- PremiumGiftFX.client.lua
-- VIEWERS VS ME - PREMIUM GIFT CINEMATICS V1.1
-- Reliable first-person test controls.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local UserInputService=game:GetService("UserInputService")
local TweenService=game:GetService("TweenService")
local RunService=game:GetService("RunService")

local player=Players.LocalPlayer
local fx=ReplicatedStorage:WaitForChild("PremiumGiftFX")
local debug=ReplicatedStorage:WaitForChild("GiftDebug")
local gui=Instance.new("ScreenGui");gui.Name="PremiumGiftHUD";gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=50;gui.Parent=player:WaitForChild("PlayerGui")

local banner=Instance.new("Frame");banner.AnchorPoint=Vector2.new(.5,0);banner.Position=UDim2.fromScale(.5,-.15);banner.Size=UDim2.fromOffset(620,86);banner.BackgroundColor3=Color3.fromRGB(10,12,18);banner.BackgroundTransparency=.08;banner.BorderSizePixel=0;banner.Parent=gui
local stroke=Instance.new("UIStroke");stroke.Thickness=3;stroke.Color=Color3.fromRGB(255,60,70);stroke.Parent=banner
local title=Instance.new("TextLabel");title.Size=UDim2.new(1,-20,.58,0);title.Position=UDim2.fromOffset(10,4);title.BackgroundTransparency=1;title.Font=Enum.Font.GothamBlack;title.TextScaled=true;title.TextColor3=Color3.new(1,1,1);title.Parent=banner
local sub=Instance.new("TextLabel");sub.Size=UDim2.new(1,-20,.34,0);sub.Position=UDim2.new(0,10,.61,0);sub.BackgroundTransparency=1;sub.Font=Enum.Font.GothamBold;sub.TextScaled=true;sub.TextColor3=Color3.fromRGB(215,220,230);sub.Parent=banner

local help=Instance.new("TextLabel");help.AnchorPoint=Vector2.new(1,1);help.Position=UDim2.new(1,-12,1,-12);help.Size=UDim2.fromOffset(350,88);help.BackgroundColor3=Color3.fromRGB(8,10,14);help.BackgroundTransparency=.18;help.Font=Enum.Font.Code;help.TextSize=15;help.TextColor3=Color3.fromRGB(235,240,250);help.TextXAlignment=Enum.TextXAlignment.Left;help.TextYAlignment=Enum.TextYAlignment.Top;help.Text="PREMIUM GIFT TESTS\nJ = ORBITAL     K = OVERDRIVE\nL = HELLSTORM   H = TITAN RAGE   G = EMP\n(keys work while first-person locked)";help.Parent=gui
local pad=Instance.new("UIPadding");pad.PaddingLeft=UDim.new(0,8);pad.PaddingTop=UDim.new(0,6);pad.Parent=help

local serial=0
local function announce(data)
 serial+=1;local s=serial;stroke.Color=data.color or Color3.fromRGB(255,60,70);title.Text=(data.side=="HELP" and "▲ HELP • " or "▼ AGAINST • ")..tostring(data.title or "GIFT EVENT");sub.Text=tostring(data.subtitle or "");banner.Position=UDim2.fromScale(.5,-.15)
 TweenService:Create(banner,TweenInfo.new(.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.fromScale(.5,.045)}):Play();task.delay(2.8,function() if s==serial then TweenService:Create(banner,TweenInfo.new(.32),{Position=UDim2.fromScale(.5,-.15)}):Play() end end)
end
local function flash(color,alpha,time) local f=Instance.new("Frame");f.Size=UDim2.fromScale(1,1);f.BackgroundColor3=color;f.BackgroundTransparency=1;f.BorderSizePixel=0;f.ZIndex=20;f.Parent=gui;TweenService:Create(f,TweenInfo.new(.08),{BackgroundTransparency=alpha}):Play();task.delay(.09,function() TweenService:Create(f,TweenInfo.new(time),{BackgroundTransparency=1}):Play() end);task.delay(time+.2,function() if f.Parent then f:Destroy() end end) end
local shakeUntil,shakePower=0,0
local function shake(power,duration) shakePower=math.max(shakePower,power);shakeUntil=math.max(shakeUntil,os.clock()+duration) end
RunService:BindToRenderStep("PremiumGiftShake",Enum.RenderPriority.Camera.Value+5,function() if os.clock()<shakeUntil then local cam=workspace.CurrentCamera;if cam then cam.CFrame=cam.CFrame*CFrame.new((math.random()-.5)*shakePower,(math.random()-.5)*shakePower,0)*CFrame.Angles(0,0,math.rad((math.random()-.5)*shakePower*2)) end else shakePower=0 end end)

fx.OnClientEvent:Connect(function(data) if type(data)~="table" then return end;if data.kind=="announce" then announce(data) elseif data.kind=="hellstorm" then flash(Color3.fromRGB(255,65,20),.72,.45);shake(.10,8) elseif data.kind=="rage" then flash(Color3.fromRGB(255,20,35),.70,.5);shake(.16,1.2) elseif data.kind=="emp" then flash(Color3.fromRGB(120,70,255),.58,.8);shake(.08,.8) elseif data.kind=="overdrive" then flash(Color3.fromRGB(255,70,70),.72,.5) end end)

local keys={[Enum.KeyCode.J]="Private Jet",[Enum.KeyCode.K]="Castle Fantasy",[Enum.KeyCode.L]="Dragon Flame",[Enum.KeyCode.H]="Leon and Lion",[Enum.KeyCode.G]="Thunder Falcon"}
UserInputService.InputBegan:Connect(function(input)
 if input.UserInputType~=Enum.UserInputType.Keyboard then return end
 local gift=keys[input.KeyCode]
 if gift then print("PREMIUM TEST KEY:",input.KeyCode.Name,"->",gift);debug:FireServer(gift) end
end)

print("PREMIUM GIFT FX V1.1 READY - J/K/L/H/G direct test controls active.")