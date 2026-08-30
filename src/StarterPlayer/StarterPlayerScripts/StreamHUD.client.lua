-- StreamHUD.client.lua
-- VIEWERS VS ME - CINEMATIC FPS HUD V2.1
-- Clean gameplay HUD. Gift mechanics still run in the background; no TikTok gift legend is shown.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local UserInputService=game:GetService("UserInputService")
local TweenService=game:GetService("TweenService")

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")

local old=playerGui:FindFirstChild("ViewersVsMeHUD")
if old then old:Destroy() end

local gui=Instance.new("ScreenGui")
gui.Name="ViewersVsMeHUD"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=false
gui.DisplayOrder=999
gui.Parent=playerGui

local function round(o,r)local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,r or 10);c.Parent=o end
local function stroke(o,t,col)local s=Instance.new("UIStroke");s.Thickness=1.2;s.Transparency=t or .75;s.Color=col or Color3.new(1,1,1);s.Parent=o end
local function text(parent,txt,pos,size,font,ts,color,align)
 local l=Instance.new("TextLabel");l.BackgroundTransparency=1;l.Position=pos;l.Size=size;l.Font=font or Enum.Font.GothamBold;l.TextSize=ts or 14;l.TextColor3=color or Color3.new(1,1,1);l.Text=txt;l.TextXAlignment=align or Enum.TextXAlignment.Left;l.Parent=parent;return l
end
local function panel(name,pos,size,trans)
 local f=Instance.new("Frame");f.Name=name;f.Position=pos;f.Size=size;f.BackgroundColor3=Color3.fromRGB(8,10,15);f.BackgroundTransparency=trans or .16;f.BorderSizePixel=0;f.Parent=gui;round(f,14);stroke(f,.82);return f
end

local top=panel("LivePanel",UDim2.fromOffset(18,18),UDim2.fromOffset(305,116),.14)
local dot=Instance.new("Frame");dot.Size=UDim2.fromOffset(10,10);dot.Position=UDim2.fromOffset(14,15);dot.BackgroundColor3=Color3.fromRGB(255,54,66);dot.BorderSizePixel=0;dot.Parent=top;round(dot,99)
text(top,"LIVE",UDim2.fromOffset(31,4),UDim2.fromOffset(70,28),Enum.Font.GothamBlack,19)
text(top,"VIEWERS VS ME",UDim2.fromOffset(14,34),UDim2.new(1,-28,0,28),Enum.Font.GothamBlack,22)
local stats=text(top,"KILLS 0  •  ENEMIES 0  •  WAVE 1",UDim2.fromOffset(14,67),UDim2.new(1,-28,0,20),Enum.Font.GothamBold,13,Color3.fromRGB(225,230,240))
text(top,"SURVIVE THE HORDE",UDim2.fromOffset(14,90),UDim2.new(1,-28,0,18),Enum.Font.GothamMedium,11,Color3.fromRGB(155,165,185))

local weapon=panel("WeaponPanel",UDim2.new(0,20,1,-190),UDim2.fromOffset(180,112),.12)
text(weapon,"CURRENT WEAPON",UDim2.fromOffset(14,10),UDim2.new(1,-28,0,18),Enum.Font.GothamBold,11,Color3.fromRGB(180,188,205))
local weaponName=text(weapon,"AK47",UDim2.fromOffset(14,28),UDim2.new(1,-28,0,34),Enum.Font.GothamBlack,26)
local ammoLabel=text(weapon,"30 / 150",UDim2.fromOffset(14,60),UDim2.new(1,-28,0,34),Enum.Font.GothamBlack,29)
local fireMode=text(weapon,"AR  •  AUTO",UDim2.fromOffset(14,91),UDim2.new(1,-28,0,16),Enum.Font.GothamBold,10,Color3.fromRGB(150,160,180))

local vitals=Instance.new("Frame");vitals.Position=UDim2.new(0,20,1,-66);vitals.Size=UDim2.fromOffset(325,52);vitals.BackgroundTransparency=1;vitals.Parent=gui
local hpBack=Instance.new("Frame");hpBack.Size=UDim2.fromOffset(300,19);hpBack.Position=UDim2.fromOffset(0,0);hpBack.BackgroundColor3=Color3.fromRGB(70,20,24);hpBack.BorderSizePixel=0;hpBack.Parent=vitals;round(hpBack,6)
local hpFill=Instance.new("Frame");hpFill.Size=UDim2.fromScale(1,1);hpFill.BackgroundColor3=Color3.fromRGB(215,65,72);hpFill.BorderSizePixel=0;hpFill.Parent=hpBack;round(hpFill,6)
local hpText=text(hpBack,"100 / 100",UDim2.fromOffset(0,0),UDim2.fromScale(1,1),Enum.Font.GothamBlack,12,Color3.new(1,1,1),Enum.TextXAlignment.Center)
local shBack=Instance.new("Frame");shBack.Size=UDim2.fromOffset(300,19);shBack.Position=UDim2.fromOffset(0,27);shBack.BackgroundColor3=Color3.fromRGB(24,49,72);shBack.BorderSizePixel=0;shBack.Parent=vitals;round(shBack,6)
local shFill=Instance.new("Frame");shFill.Size=UDim2.fromScale(0,1);shFill.BackgroundColor3=Color3.fromRGB(78,155,220);shFill.BorderSizePixel=0;shFill.Parent=shBack;round(shFill,6)
local shText=text(shBack,"0 / 100",UDim2.fromOffset(0,0),UDim2.fromScale(1,1),Enum.Font.GothamBlack,12,Color3.new(1,1,1),Enum.TextXAlignment.Center)

local slots=Instance.new("Frame");slots.AnchorPoint=Vector2.new(.5,1);slots.Position=UDim2.new(.5,0,1,-18);slots.Size=UDim2.fromOffset(560,58);slots.BackgroundTransparency=1;slots.Parent=gui
local slotNames={"AK47","HANDGUN","KNIFE","MINIGUN","ROCKET","LASER"}
for i,n in ipairs(slotNames) do
 local b=Instance.new("Frame");b.Size=UDim2.fromOffset(84,54);b.Position=UDim2.fromOffset((i-1)*94,0);b.BackgroundColor3=Color3.fromRGB(8,10,15);b.BackgroundTransparency=.20;b.BorderSizePixel=0;b.Parent=slots;round(b,9);stroke(b,i==1 and .25 or .82,i==1 and Color3.fromRGB(75,145,255) or Color3.new(1,1,1))
 text(b,tostring(i),UDim2.fromOffset(5,3),UDim2.fromOffset(16,14),Enum.Font.GothamBlack,10,Color3.fromRGB(220,225,235))
 text(b,n,UDim2.fromOffset(6,22),UDim2.new(1,-12,0,20),Enum.Font.GothamBold,9,Color3.fromRGB(235,238,245),Enum.TextXAlignment.Center)
end

local status=panel("StatusPanel",UDim2.new(1,-350,1,-82),UDim2.fromOffset(330,62),.18)
text(status,"HUD READY • WAITING FOR EVENTS",UDim2.fromOffset(14,10),UDim2.new(1,-28,0,18),Enum.Font.GothamBlack,12)
local status2=text(status,"LIVE EVENT LINK READY",UDim2.fromOffset(14,34),UDim2.new(1,-28,0,18),Enum.Font.GothamBold,11,Color3.fromRGB(190,205,220))

local clean=text(gui,"F10 • CLEAN STREAM",UDim2.new(.5,-90,1,-88),UDim2.fromOffset(180,26),Enum.Font.GothamBold,10,Color3.fromRGB(180,188,202),Enum.TextXAlignment.Center)
clean.BackgroundTransparency=.28;clean.BackgroundColor3=Color3.fromRGB(8,10,15);round(clean,9)

local banner=text(gui,"",UDim2.new(.5,-300,0,24),UDim2.fromOffset(600,54),Enum.Font.GothamBlack,25,Color3.new(1,1,1),Enum.TextXAlignment.Center)
banner.BackgroundColor3=Color3.fromRGB(8,10,15);banner.BackgroundTransparency=1;banner.TextTransparency=1;round(banner,12)

local kills,active,wave=0,0,1
local cleanMode=false
local bannerToken=0

local function refreshStats()stats.Text=("KILLS %d  •  ENEMIES %d  •  WAVE %d"):format(kills,active,wave) end
local function showBanner(t)
 bannerToken+=1;local token=bannerToken;banner.Text=t
 TweenService:Create(banner,TweenInfo.new(.12),{TextTransparency=0,BackgroundTransparency=.18}):Play()
 task.delay(1.8,function()if token~=bannerToken then return end;TweenService:Create(banner,TweenInfo.new(.24),{TextTransparency=1,BackgroundTransparency=1}):Play()end)
end

local function setClean(on)
 cleanMode=on
 weapon.Visible=not on;vitals.Visible=not on;slots.Visible=not on;status.Visible=not on;clean.Visible=not on
end
UserInputService.InputBegan:Connect(function(i,p)if not p and i.KeyCode==Enum.KeyCode.F10 then setClean(not cleanMode)end end)

local function bindHumanoid(char)
 local hum=char:WaitForChild("Humanoid",5);if not hum then return end
 local function update()
  local max=math.max(1,hum.MaxHealth);local hp=math.clamp(hum.Health,0,max);hpFill.Size=UDim2.fromScale(hp/max,1);hpText.Text=("%d / %d"):format(math.floor(hp+.5),math.floor(max+.5))
  local shield=char:FindFirstChildOfClass("ForceField") and 100 or 0;shFill.Size=UDim2.fromScale(shield/100,1);shText.Text=("%d / 100"):format(shield)
 end
 hum.HealthChanged:Connect(update);hum:GetPropertyChangedSignal("MaxHealth"):Connect(update);char.ChildAdded:Connect(update);char.ChildRemoved:Connect(update);update()
end
if player.Character then task.spawn(bindHumanoid,player.Character) end
player.CharacterAdded:Connect(bindHumanoid)

local function updateWeapon()
 local logical=tostring(player:GetAttribute("CurrentWeapon") or "Rifle")
 local asset=tostring(player:GetAttribute("CurrentWeaponAsset") or logical)
 local a=tonumber(player:GetAttribute("CurrentAmmo")) or 0
 local r=tonumber(player:GetAttribute("ReserveAmmo")) or 0
 local reload=player:GetAttribute("Reloading")==true
 weaponName.Text=asset:upper()
 ammoLabel.Text=reload and "RELOADING" or (("%d / %d"):format(a,r))
 ammoLabel.TextSize=reload and 18 or 29
 fireMode.Text=(logical=="Sword") and "MELEE" or ((logical=="Shotgun") and "HEAVY" or "AUTO")
end
for _,a in ipairs({"CurrentWeapon","CurrentWeaponAsset","CurrentAmmo","ReserveAmmo","Reloading"}) do player:GetAttributeChangedSignal(a):Connect(updateWeapon) end
updateWeapon()

local remote=ReplicatedStorage:WaitForChild("TikTokStreamEvent",15)
if remote then
 status2.Text="LIVE EVENT LINK READY"
 remote.OnClientEvent:Connect(function(e)
  if type(e)~="table" then return end
  if e.kind=="stats" then kills=e.kills or kills;active=e.active or active;wave=e.wave or wave;refreshStats() end
  if e.kind=="gift" then
   kills=e.kills or kills;active=e.active or active;wave=e.wave or wave;refreshStats()
   showBanner(("@%s • %s"):format(tostring(e.sender or "VIEWER"),tostring(e.gift or "GIFT")))
  elseif e.kind=="banner" then showBanner(tostring(e.title or "VIEWER EVENT")) end
 end)
else status2.Text="EVENT LINK NOT READY" end

refreshStats()
print("STREAM HUD V2.1 READY - clean FPS layout, gift legend removed")