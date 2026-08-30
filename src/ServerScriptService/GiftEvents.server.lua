-- GiftEvents.server.lua
-- VIEWERS VS ME - BIG GIFT EVENT SYSTEM V1.3
-- Paired TikTok gifts: each price tier has one HELP gift and one AGAINST gift.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local ServerStorage=game:GetService("ServerStorage")
local Lighting=game:GetService("Lighting")
local TweenService=game:GetService("TweenService")
local Debris=game:GetService("Debris")

local function remote(name)
 local r=ReplicatedStorage:FindFirstChild(name);if r and not r:IsA("RemoteEvent") then r:Destroy();r=nil end
 if not r then r=Instance.new("RemoteEvent");r.Name=name;r.Parent=ReplicatedStorage end;return r
end
local function bindable(name)
 local b=ServerStorage:FindFirstChild(name);if b and not b:IsA("BindableEvent") then b:Destroy();b=nil end
 if not b then b=Instance.new("BindableEvent");b.Name=name;b.Parent=ServerStorage end;return b
end
local fxRemote=remote("GiftFX")
local debugRemote=remote("GiftDebug")
local dispatch=bindable("ViewersVsMeGiftDispatch")
local spawnRequest=bindable("GiftSpawnRequest")
local enemies=workspace:WaitForChild("TikTokEnemies")
local function host() return Players:GetPlayers()[1] end
local function character() local p=host();return p and p.Character end
local function humanoid() local c=character();return c and c:FindFirstChildOfClass("Humanoid") end
local function root() local c=character();return c and c:FindFirstChild("HumanoidRootPart") end
local function announce(side,title,subtitle,color) fxRemote:FireAllClients({kind="announce",side=side,title=title,subtitle=subtitle,color=color}) end
local function setGiftWeapon(weapon,duration,sender,label)
 local p=host();if not p then return end;duration=duration or 90
 local expires=workspace:GetServerTimeNow()+duration;p:SetAttribute("GiftWeapon",weapon);p:SetAttribute("GiftWeaponUntil",expires)
 announce("HELP",label or (weapon:upper().." DROP!"),"@"..sender.." armed you for "..duration.."s",Color3.fromRGB(80,225,255))
 task.delay(duration+.2,function()if p.Parent and p:GetAttribute("GiftWeapon")==weapon and(p:GetAttribute("GiftWeaponUntil")or 0)<=workspace:GetServerTimeNow()+.25 then p:SetAttribute("GiftWeapon",nil);p:SetAttribute("GiftWeaponUntil",nil)end end)
end
local function heal(amount,sender,label)
 local h=humanoid();if not h then return end;h.Health=math.min(h.MaxHealth,h.Health+amount)
 announce("HELP",label or "MEDICAL DROP","@"..sender.." restored +"..amount.." HP",Color3.fromRGB(80,255,150));fxRemote:FireAllClients({kind="heal",amount=amount})
end
local function shield(duration,sender,label)
 local c=character();if not c then return end;local ff=c:FindFirstChild("GiftShield")or Instance.new("ForceField");ff.Name="GiftShield";ff.Visible=true;ff.Parent=c
 announce("HELP",label or "INVINCIBILITY","@"..sender.." protected you for "..duration.."s",Color3.fromRGB(110,210,255));fxRemote:FireAllClients({kind="shield",duration=duration});task.delay(duration,function()if ff and ff.Parent then ff:Destroy()end end)
end
local function freezeZombies(duration,sender)
 local saved={};for _,m in ipairs(enemies:GetChildren())do local h=m:FindFirstChildOfClass("Humanoid");if h and h.Health>0 then saved[h]=h.WalkSpeed;h.WalkSpeed=0 end end
 announce("HELP","TIME FREEZE","@"..sender.." froze the horde",Color3.fromRGB(120,230,255));fxRemote:FireAllClients({kind="freeze",duration=duration});task.delay(duration,function()for h,s in pairs(saved)do if h.Parent and h.Health>0 then h.WalkSpeed=s end end end)
end
local function wipeNormal(sender,label)
 local removed=0;for _,m in ipairs(enemies:GetChildren())do local h=m:FindFirstChildOfClass("Humanoid");if h and h.Health>0 and not m:GetAttribute("Boss")then h.Health=0;removed+=1 end end
 announce("HELP",label or "AIRSTRIKE","@"..sender.." wiped "..removed.." infected",Color3.fromRGB(255,210,70));fxRemote:FireAllClients({kind="airstrike"})
end
local function damagePlayer(amount,sender,label)
 local h=humanoid();if h then h:TakeDamage(amount)end;announce("AGAINST",label or "VIEWER ATTACK","@"..sender.." hit you for "..amount.." damage",Color3.fromRGB(255,70,70));fxRemote:FireAllClients({kind="damage",amount=amount})
end
local function horde(sender,count,title)
 spawnRequest:Fire(sender,count,false);announce("AGAINST",title or "HORDE DROP","@"..sender.." released "..count.." infected",Color3.fromRGB(255,90,65))
end
local function bossHorde(sender,count,title)
 spawnRequest:Fire(sender,count,true);announce("AGAINST",title or "TITAN DEPLOYED","@"..sender.." spawned a Titan + "..count.." infected",Color3.fromRGB(255,65,45))
end
local blackoutSerial=0
local function blackout(duration,sender,label)
 blackoutSerial+=1;local serial=blackoutSerial;local oldB=Lighting.Brightness;local oldE=Lighting.ExposureCompensation;local oldA=Lighting.Ambient;local oldO=Lighting.OutdoorAmbient
 announce("AGAINST",label or "CITY BLACKOUT","@"..sender.." killed the power",Color3.fromRGB(190,80,255));fxRemote:FireAllClients({kind="blackout",duration=duration})
 TweenService:Create(Lighting,TweenInfo.new(.5),{Brightness=.35,ExposureCompensation=-1,Ambient=Color3.fromRGB(12,12,20),OutdoorAmbient=Color3.fromRGB(16,16,28)}):Play()
 task.delay(duration,function()if serial~=blackoutSerial then return end;TweenService:Create(Lighting,TweenInfo.new(1),{Brightness=oldB,ExposureCompensation=oldE,Ambient=oldA,OutdoorAmbient=oldO}):Play()end)
end
local function meteor(sender)
 local r=root();if not r then return end;local target=r.Position;announce("AGAINST","METEOR INBOUND","@"..sender.." targeted your position",Color3.fromRGB(255,105,40));fxRemote:FireAllClients({kind="meteor",delay=2.25})
 local ring=Instance.new("Part");ring.Name="MeteorWarning";ring.Anchored=true;ring.CanCollide=false;ring.CanTouch=false;ring.CanQuery=false;ring.Material=Enum.Material.Neon;ring.Color=Color3.fromRGB(255,55,20);ring.Transparency=.22;ring.Shape=Enum.PartType.Cylinder;ring.Size=Vector3.new(.18,16,16);ring.CFrame=CFrame.new(target+Vector3.new(0,.15,0))*CFrame.Angles(0,0,math.rad(90));ring.Parent=workspace;Debris:AddItem(ring,2.6)
 local rock=Instance.new("Part");rock.Name="GiftMeteor";rock.Anchored=true;rock.CanCollide=false;rock.CanTouch=false;rock.CanQuery=false;rock.Material=Enum.Material.Slate;rock.Color=Color3.fromRGB(55,40,35);rock.Size=Vector3.new(5,5,5);rock.Shape=Enum.PartType.Ball;rock.CFrame=CFrame.new(target+Vector3.new(0,85,0));rock.Parent=workspace;local fire=Instance.new("Fire");fire.Size=10;fire.Heat=8;fire.Parent=rock;TweenService:Create(rock,TweenInfo.new(2.2,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{CFrame=CFrame.new(target+Vector3.new(0,2,0))}):Play();Debris:AddItem(rock,2.5)
 task.delay(2.2,function()local h=humanoid();local rr=root();if h and rr and(rr.Position-target).Magnitude<11 then h:TakeDamage(35)end;local blast=Instance.new("Explosion");blast.Position=target;blast.BlastRadius=14;blast.BlastPressure=0;blast.DestroyJointRadiusPercent=0;blast.Parent=workspace end)
end

local Gifts={
 -- Existing tiers
 ["Rose"]={side="HELP",action=function(s)heal(10,s,"ROSE HEAL")end},
 ["Chilli"]={side="AGAINST",action=function(s)horde(s,3,"CHILLI HORDE")end},
 ["Love You"]={side="HELP",action=function(s)heal(25,s,"LOVE YOU BOOST");setGiftWeapon("Pistol",90,s,"HANDGUN DROP")end},
 ["Night Star"]={side="AGAINST",action=function(s)blackout(8,s,"NIGHT STAR BLACKOUT");horde(s,6,"NIGHT STAR HORDE")end},
 ["Galaxy"]={side="HELP",action=function(s)setGiftWeapon("Minigun",90,s,"GALAXY MINIGUN");shield(8,s,"GALAXY SHIELD")end},
 ["Giraffe"]={side="AGAINST",action=function(s)bossHorde(s,8,"GIRAFFE TITAN")end},

 -- 20 coins: small but noticeable
 ["Perfume"]={side="HELP",action=function(s)heal(20,s,"PERFUME MEDKIT")end},
 ["G.O.A.T Busker"]={side="AGAINST",action=function(s)damagePlayer(12,s,"BUSKER HIT");horde(s,2,"BUSKER BACKUP")end},

 -- 500 coins: major swing
 ["Manifesting"]={side="HELP",action=function(s)heal(45,s,"MANIFESTING BOOST");freezeZombies(8,s);setGiftWeapon("Rifle",90,s,"AK47 DROP")end},
 ["Star Map Polaris"]={side="AGAINST",action=function(s)blackout(10,s,"POLARIS BLACKOUT");horde(s,10,"POLARIS HORDE")end},

 -- 1,200 coins: high-impact pair
 ["Travel The US"]={side="HELP",action=function(s)wipeNormal(s,"TRAVEL THE US AIRSTRIKE");heal(75,s,"TRAVEL THE US HEAL");shield(12,s,"TRAVEL THE US SHIELD")end},
 ["Bunny DJ"]={side="AGAINST",action=function(s)bossHorde(s,12,"BUNNY DJ TITAN");meteor(s)end},

 -- Legacy compatibility while the remaining gifts are reorganized into pairs.
 ["Heart Me"]={side="HELP",action=function(s)setGiftWeapon("SMG",90,s)end},
 ["Hand Hearts"]={side="HELP",action=function(s)heal(30,s);setGiftWeapon("Shotgun",90,s,"HANDGUN DROP")end},
 ["Interstellar"]={side="HELP",action=function(s)freezeZombies(7,s);setGiftWeapon("Rifle",90,s)end},
 ["Phoenix"]={side="HELP",action=function(s)wipeNormal(s);heal(60,s)end},
 ["Sports Car"]={side="AGAINST",action=function(s)horde(s,8,"HORDE DROP")end},
 ["Lion"]={side="AGAINST",action=function(s)bossHorde(s,6,"THE LION BOSS")end},
 ["TikTok Universe"]={side="AGAINST",action=function(s)blackout(12,s);horde(s,16,"UNIVERSE HORDE")end},
 ["Universe"]={side="AGAINST",action=function(s)blackout(12,s);horde(s,16,"UNIVERSE HORDE")end},
 ["Meteor Shower"]={side="AGAINST",action=function(s)meteor(s)end},
}
local function processGift(name,sender,count)
 name=tostring(name or "");sender=tostring(sender or "VIEWER");count=math.clamp(tonumber(count)or 1,1,10);local cfg=Gifts[name];if not cfg then warn("GIFT EVENT: unmapped gift",name);return end
 for _=1,count do cfg.action(sender)end;print("GIFT EVENT:",cfg.side,name,"from",sender,"x"..count)
end
dispatch.Event:Connect(processGift)
debugRemote.OnServerEvent:Connect(function(player,giftName)if player==host()then processGift(giftName,"TEST_VIEWER",1)end end)
print("BIG GIFT EVENTS V1.3 READY - paired tiers through 1200 coins")