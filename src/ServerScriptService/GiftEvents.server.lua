-- GiftEvents.server.lua
-- VIEWERS VS ME - BIG GIFT EVENT SYSTEM V1
-- Central table: HELP gifts, AGAINST gifts, and WEAPON gifts.
-- Future TikTok bridge should fire ServerStorage.ViewersVsMeGiftDispatch with (giftName, sender, count).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local function remote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if r and not r:IsA("RemoteEvent") then r:Destroy(); r=nil end
	if not r then r=Instance.new("RemoteEvent"); r.Name=name; r.Parent=ReplicatedStorage end
	return r
end

local function bindable(name)
	local b=ServerStorage:FindFirstChild(name)
	if b and not b:IsA("BindableEvent") then b:Destroy(); b=nil end
	if not b then b=Instance.new("BindableEvent"); b.Name=name; b.Parent=ServerStorage end
	return b
end

local fxRemote = remote("GiftFX")
local debugRemote = remote("GiftDebug")
local dispatch = bindable("ViewersVsMeGiftDispatch")
local spawnRequest = bindable("ViewersVsMeSpawnRequest")

local enemies = workspace:WaitForChild("TikTokEnemies")

local function host() return Players:GetPlayers()[1] end
local function character() local p=host(); return p and p.Character end
local function humanoid() local c=character(); return c and c:FindFirstChildOfClass("Humanoid") end
local function root() local c=character(); return c and c:FindFirstChild("HumanoidRootPart") end

local function announce(side,title,subtitle,color)
	fxRemote:FireAllClients({kind="announce",side=side,title=title,subtitle=subtitle,color=color})
end

local function setGiftWeapon(weapon,duration,sender)
	local p=host(); if not p then return end
	p:SetAttribute("GiftWeapon",weapon)
	p:SetAttribute("GiftWeaponUntil",workspace:GetServerTimeNow()+duration)
	announce("HELP",weapon:upper().." DROP!","@"..sender.." armed you for "..duration.."s",Color3.fromRGB(80,225,255))
	task.delay(duration,function()
		if p.Parent and p:GetAttribute("GiftWeapon")==weapon and (p:GetAttribute("GiftWeaponUntil") or 0)<=workspace:GetServerTimeNow()+.2 then
			p:SetAttribute("GiftWeapon",nil)
			p:SetAttribute("GiftWeaponUntil",nil)
		end
	end)
end

local function heal(amount,sender)
	local h=humanoid(); if not h then return end
	h.Health=math.min(h.MaxHealth,h.Health+amount)
	announce("HELP","MEDICAL DROP","@"..sender.." restored +"..amount.." HP",Color3.fromRGB(80,255,150))
	fxRemote:FireAllClients({kind="heal",amount=amount})
end

local function shield(duration,sender)
	local c=character(); if not c then return end
	local ff=c:FindFirstChild("GiftShield") or Instance.new("ForceField")
	ff.Name="GiftShield"; ff.Visible=true; ff.Parent=c
	announce("HELP","INVINCIBILITY","@"..sender.." protected you for "..duration.."s",Color3.fromRGB(110,210,255))
	fxRemote:FireAllClients({kind="shield",duration=duration})
	task.delay(duration,function() if ff and ff.Parent then ff:Destroy() end end)
end

local function freezeZombies(duration,sender)
	local saved={}
	for _,m in ipairs(enemies:GetChildren()) do
		local h=m:FindFirstChildOfClass("Humanoid")
		if h and h.Health>0 then saved[h]=h.WalkSpeed; h.WalkSpeed=0 end
	end
	announce("HELP","TIME FREEZE","@"..sender.." froze the horde",Color3.fromRGB(120,230,255))
	fxRemote:FireAllClients({kind="freeze",duration=duration})
	task.delay(duration,function()
		for h,speed in pairs(saved) do if h.Parent and h.Health>0 then h.WalkSpeed=speed end end
	end)
end

local function wipeNormal(sender)
	local removed=0
	for _,m in ipairs(enemies:GetChildren()) do
		local h=m:FindFirstChildOfClass("Humanoid")
		if h and h.Health>0 and not m:GetAttribute("Boss") then h.Health=0; removed+=1 end
	end
	announce("HELP","AIRSTRIKE","@"..sender.." wiped "..removed.." infected",Color3.fromRGB(255,210,70))
	fxRemote:FireAllClients({kind="airstrike"})
end

local function spawnPack(sender,count,boss)
	spawnRequest:Fire({sender=sender,count=count,boss=boss==true})
end

local function damagePlayer(amount,sender,label)
	local h=humanoid(); if h then h:TakeDamage(amount) end
	announce("AGAINST",label or "VIEWER ATTACK","@"..sender.." hit you for "..amount.." damage",Color3.fromRGB(255,70,70))
	fxRemote:FireAllClients({kind="damage",amount=amount})
end

local blackoutSerial=0
local function blackout(duration,sender)
	blackoutSerial+=1; local serial=blackoutSerial
	local oldBrightness=Lighting.Brightness; local oldExposure=Lighting.ExposureCompensation; local oldAmbient=Lighting.Ambient; local oldOutdoor=Lighting.OutdoorAmbient
	announce("AGAINST","CITY BLACKOUT","@"..sender.." killed the power",Color3.fromRGB(190,80,255))
	fxRemote:FireAllClients({kind="blackout",duration=duration})
	TweenService:Create(Lighting,TweenInfo.new(.55),{Brightness=.45,ExposureCompensation=-.9,Ambient=Color3.fromRGB(18,18,28),OutdoorAmbient=Color3.fromRGB(22,22,35)}):Play()
	task.delay(duration,function()
		if serial~=blackoutSerial then return end
		TweenService:Create(Lighting,TweenInfo.new(1),{Brightness=oldBrightness,ExposureCompensation=oldExposure,Ambient=oldAmbient,OutdoorAmbient=oldOutdoor}):Play()
	end)
end

local function meteor(sender)
	local r=root(); if not r then return end
	announce("AGAINST","METEOR INBOUND","@"..sender.." called it on your position",Color3.fromRGB(255,110,45))
	fxRemote:FireAllClients({kind="meteor",delay=2.1})
	local target=r.Position
	local marker=Instance.new("Part"); marker.Name="MeteorMarker"; marker.Anchored=true; marker.CanCollide=false; marker.CanTouch=false; marker.CanQuery=false; marker.Material=Enum.Material.Neon; marker.Color=Color3.fromRGB(255,55,25); marker.Transparency=.35; marker.Size=Vector3.new(14,.15,14); marker.CFrame=CFrame.new(target+Vector3.new(0,.1,0)); marker.Parent=workspace
	Debris:AddItem(marker,2.4)
	task.delay(2.1,function()
		local h=humanoid(); local rr=root(); if h and rr and (rr.Position-target).Magnitude<10 then h:TakeDamage(35) end
		local blast=Instance.new("Explosion"); blast.Position=target; blast.BlastRadius=13; blast.BlastPressure=0; blast.DestroyJointRadiusPercent=0; blast.Parent=workspace
		for _,m in ipairs(enemies:GetChildren()) do
			local eh=m:FindFirstChildOfClass("Humanoid"); local er=m:FindFirstChild("HumanoidRootPart")
			if eh and er and (er.Position-target).Magnitude<13 then eh:TakeDamage(80) end
		end
	end)
end

-- HELP SIDE: keeps you alive, buffs you, or upgrades the gun.
-- AGAINST SIDE: viewers make the run harder.
local Gifts = {
	["Rose"]={side="HELP",action=function(sender) heal(8,sender) end},
	["Heart Me"]={side="HELP",action=function(sender) setGiftWeapon("SMG",14,sender) end},
	["Hand Hearts"]={side="HELP",action=function(sender) heal(30,sender); setGiftWeapon("Shotgun",20,sender) end},
	["Galaxy"]={side="HELP",action=function(sender) setGiftWeapon("Minigun",28,sender); shield(6,sender) end},
	["Interstellar"]={side="HELP",action=function(sender) freezeZombies(7,sender); setGiftWeapon("Rifle",30,sender) end},
	["Phoenix"]={side="HELP",action=function(sender) wipeNormal(sender); heal(60,sender) end},

	["Perfume"]={side="AGAINST",action=function(sender) damagePlayer(8,sender,"POISON CLOUD") end},
	["Sports Car"]={side="AGAINST",action=function(sender) spawnPack(sender,8,false); announce("AGAINST","HORDE DROP","@"..sender.." released 8 infected",Color3.fromRGB(255,90,65)) end},
	["Lion"]={side="AGAINST",action=function(sender) spawnPack(sender,1,true); spawnPack(sender,6,false); announce("AGAINST","THE LION BOSS","@"..sender.." spawned a boss + escort",Color3.fromRGB(255,75,55)) end},
	["TikTok Universe"]={side="AGAINST",action=function(sender) blackout(12,sender); spawnPack(sender,16,false) end},
	["Universe"]={side="AGAINST",action=function(sender) blackout(12,sender); spawnPack(sender,16,false) end},
	["Meteor Shower"]={side="AGAINST",action=function(sender) meteor(sender) end},
}

local function processGift(giftName,sender,count)
	giftName=tostring(giftName or ""); sender=tostring(sender or "VIEWER"); count=math.clamp(tonumber(count) or 1,1,20)
	local cfg=Gifts[giftName]
	if not cfg then warn("GIFT EVENT: unmapped gift",giftName); return end
	for _=1,count do cfg.action(sender) end
	print("GIFT EVENT:",cfg.side,giftName,"from",sender,"x"..count)
end

dispatch.Event:Connect(processGift)
debugRemote.OnServerEvent:Connect(function(player,giftName)
	if player~=host() then return end
	processGift(giftName,"TEST_VIEWER",1)
end)

print("BIG GIFT EVENTS V1 READY - HELP / AGAINST / WEAPON gifts enabled.")