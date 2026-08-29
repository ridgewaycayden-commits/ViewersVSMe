-- PremiumGiftEvents.server.lua
-- VIEWERS VS ME - PREMIUM GIFT EVENTS V1.2
-- High-tier HELP/AGAINST events + reliable Studio debug + REAL orbital standby.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local ServerStorage=game:GetService("ServerStorage")
local Lighting=game:GetService("Lighting")
local TweenService=game:GetService("TweenService")
local Debris=game:GetService("Debris")

local enemies=workspace:WaitForChild("TikTokEnemies")
local spawnRequest=ServerStorage:WaitForChild("GiftSpawnRequest")
local dispatch=ServerStorage:WaitForChild("ViewersVsMeGiftDispatch")

local function remote(name)
 local r=ReplicatedStorage:FindFirstChild(name)
 if r and not r:IsA("RemoteEvent") then r:Destroy();r=nil end
 if not r then r=Instance.new("RemoteEvent");r.Name=name;r.Parent=ReplicatedStorage end
 return r
end
local premiumFX=remote("PremiumGiftFX")
local debug=remote("GiftDebug")

local function host() return Players:GetPlayers()[1] end
local function char() local p=host();return p and p.Character end
local function root() local c=char();return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c=char();return c and c:FindFirstChildOfClass("Humanoid") end
local function announce(side,title,sub,color) premiumFX:FireAllClients({kind="announce",side=side,title=title,subtitle=sub,color=color}) end

local function neonBall(pos,size,color,lifetime)
 local p=Instance.new("Part");p.Shape=Enum.PartType.Ball;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Material=Enum.Material.Neon;p.Color=color;p.Transparency=.18;p.Size=Vector3.new(size,size,size);p.CFrame=CFrame.new(pos);p.Parent=workspace
 local light=Instance.new("PointLight");light.Color=color;light.Brightness=5;light.Range=size*3;light.Parent=p
 TweenService:Create(p,TweenInfo.new(lifetime,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=Vector3.new(size*2.5,size*2.5,size*2.5),Transparency=1}):Play();Debris:AddItem(p,lifetime+.1)
end

local function validNormalTarget(m)
 if not m or not m.Parent or m:GetAttribute("Boss") or m:GetAttribute("Dead") then return false end
 local h=m:FindFirstChildOfClass("Humanoid")
 local r=m:FindFirstChild("HumanoidRootPart")
 return h and r and h.Health>0
end

local function fireOrbitalTarget(m,delayTime)
 task.delay(delayTime or 0,function()
  if not validNormalTarget(m) then return end
  local er=m:FindFirstChild("HumanoidRootPart");local eh=m:FindFirstChildOfClass("Humanoid")
  if not er or not eh then return end
  local beam=Instance.new("Part");beam.Name="OrbitalBeam";beam.Anchored=true;beam.CanCollide=false;beam.CanTouch=false;beam.CanQuery=false;beam.Material=Enum.Material.Neon;beam.Color=Color3.fromRGB(100,235,255);beam.Size=Vector3.new(.55,95,.55);beam.CFrame=CFrame.new(er.Position+Vector3.new(0,47.5,0));beam.Parent=workspace
  local light=Instance.new("PointLight");light.Color=beam.Color;light.Brightness=7;light.Range=24;light.Parent=beam
  Debris:AddItem(beam,.24)
  neonBall(er.Position,3.1,beam.Color,.35)
  premiumFX:FireAllClients({kind="orbitalHit",position=er.Position})
  eh:TakeDamage(500)
 end)
end

local orbitalSerial=0
local function orbital(sender)
 local r=root();if not r then return end
 orbitalSerial+=1
 local serial=orbitalSerial
 announce("HELP","ORBITAL SUPPORT","@"..sender.." called in a cleansing strike",Color3.fromRGB(80,220,255))

 local targets={}
 for _,m in ipairs(enemies:GetChildren()) do if validNormalTarget(m) then table.insert(targets,m) end end
 table.sort(targets,function(a,b) return (a.HumanoidRootPart.Position-r.Position).Magnitude<(b.HumanoidRootPart.Position-r.Position).Magnitude end)

 if #targets>0 then
  for i=1,math.min(10,#targets) do fireOrbitalTarget(targets[i],(i-1)*.11) end
  return
 end

 -- REAL standby: stays armed and automatically strikes the next infected that emerge.
 local standbySeconds=15
 local maxShots=10
 local fired=0
 announce("HELP","ORBITAL ARMED","No infected detected — strike armed for "..standbySeconds.."s",Color3.fromRGB(80,220,255))
 premiumFX:FireAllClients({kind="orbitalStandby",duration=standbySeconds})
 neonBall(r.Position+Vector3.new(0,4,0),3,Color3.fromRGB(80,220,255),.5)

 local conn
 conn=enemies.ChildAdded:Connect(function(m)
  if serial~=orbitalSerial or os.clock()==math.huge then return end
  task.delay(.25,function()
   if serial~=orbitalSerial or not validNormalTarget(m) then return end
   fired+=1
   fireOrbitalTarget(m,.08)
   if fired==1 then announce("HELP","ORBITAL LOCK","Target acquired — firing",Color3.fromRGB(100,235,255)) end
   if fired>=maxShots and conn then conn:Disconnect();conn=nil end
  end)
 end)

 task.delay(standbySeconds,function()
  if serial~=orbitalSerial then return end
  if conn then conn:Disconnect();conn=nil end
  if fired==0 then announce("HELP","ORBITAL EXPIRED","No targets entered the strike zone",Color3.fromRGB(130,190,210))
  else announce("HELP","ORBITAL COMPLETE",fired.." infected eliminated",Color3.fromRGB(100,235,255)) end
 end)
end

local function overdrive(sender)
 local p=host();local h=hum();if not p or not h then return end
 announce("HELP","OVERDRIVE","@"..sender.." activated the prototype weapon",Color3.fromRGB(255,80,80));p:SetAttribute("GiftWeapon","Minigun");p:SetAttribute("GiftWeaponUntil",workspace:GetServerTimeNow()+45);h.Health=h.MaxHealth
 local c=char();if not c then return end
 local old=c:FindFirstChild("PremiumOverdriveShield");if old then old:Destroy() end
 local ff=Instance.new("ForceField");ff.Name="PremiumOverdriveShield";ff.Visible=true;ff.Parent=c;premiumFX:FireAllClients({kind="overdrive",duration=10})
 task.delay(10,function() if ff and ff.Parent then ff:Destroy() end end)
end

local function titanRage(sender)
 announce("AGAINST","TITAN RAGE","@"..sender.." enraged every Titan",Color3.fromRGB(255,25,35));local found=false
 for _,m in ipairs(enemies:GetChildren()) do
  if m:GetAttribute("Boss") and not m:GetAttribute("Dead") then
   local h=m:FindFirstChildOfClass("Humanoid");local r=m:FindFirstChild("HumanoidRootPart")
   if h and h.Health>0 then
    found=true;h.WalkSpeed=math.max(h.WalkSpeed,13);h.MaxHealth=math.max(h.MaxHealth,1800);h.Health=math.min(h.MaxHealth,h.Health+450);m:SetAttribute("Enraged",true)
    if r then neonBall(r.Position,5,Color3.fromRGB(255,25,35),.7) end
   end
  end
 end
 if not found then spawnRequest:Fire(sender,8,true) end
 premiumFX:FireAllClients({kind="rage",duration=12})
end

local function hellstorm(sender)
 local r=root();if not r then return end
 announce("AGAINST","HELLSTORM","@"..sender.." opened the sky",Color3.fromRGB(255,70,25));premiumFX:FireAllClients({kind="hellstorm",duration=8})
 for i=1,8 do
  task.delay((i-1)*.7,function()
   local rr=root();if not rr then return end
   local target=rr.Position+Vector3.new(math.random(-18,18),0,math.random(-18,18))
   local warning=Instance.new("Part");warning.Shape=Enum.PartType.Cylinder;warning.Anchored=true;warning.CanCollide=false;warning.CanTouch=false;warning.CanQuery=false;warning.Material=Enum.Material.Neon;warning.Color=Color3.fromRGB(255,55,20);warning.Transparency=.25;warning.Size=Vector3.new(.12,8,8);warning.CFrame=CFrame.new(target+Vector3.new(0,.15,0))*CFrame.Angles(0,0,math.rad(90));warning.Parent=workspace;Debris:AddItem(warning,.8)
   task.delay(.72,function()
    local rock=Instance.new("Part");rock.Shape=Enum.PartType.Ball;rock.Anchored=true;rock.CanCollide=false;rock.CanTouch=false;rock.CanQuery=false;rock.Material=Enum.Material.Slate;rock.Color=Color3.fromRGB(48,32,28);rock.Size=Vector3.new(3.5,3.5,3.5);rock.CFrame=CFrame.new(target+Vector3.new(math.random(-10,10),60,math.random(-10,10)));rock.Parent=workspace
    local fire=Instance.new("Fire");fire.Size=8;fire.Heat=8;fire.Parent=rock
    TweenService:Create(rock,TweenInfo.new(.55,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{CFrame=CFrame.new(target+Vector3.new(0,1.5,0))}):Play();Debris:AddItem(rock,.7)
    task.delay(.55,function()
     local hh=hum();local pr=root();if hh and pr and (pr.Position-target).Magnitude<7 then hh:TakeDamage(18) end
     local ex=Instance.new("Explosion");ex.Position=target;ex.BlastRadius=7;ex.BlastPressure=0;ex.DestroyJointRadiusPercent=0;ex.Parent=workspace
    end)
   end)
  end)
 end
end

local empSerial=0
local function emp(sender)
 empSerial+=1;local serial=empSerial
 announce("AGAINST","EMP LOCKDOWN","@"..sender.." disabled your support systems",Color3.fromRGB(155,80,255));local p=host();if p then p:SetAttribute("GiftWeapon",nil);p:SetAttribute("GiftWeaponUntil",nil) end
 local oldB=Lighting.Brightness;local oldE=Lighting.ExposureCompensation
 TweenService:Create(Lighting,TweenInfo.new(.25),{Brightness=.15,ExposureCompensation=-1.4}):Play();premiumFX:FireAllClients({kind="emp",duration=7})
 task.delay(7,function() if serial==empSerial then TweenService:Create(Lighting,TweenInfo.new(.8),{Brightness=oldB,ExposureCompensation=oldE}):Play() end end)
end

local premium={
 ["Private Jet"]={side="HELP",fn=orbital},
 ["Castle Fantasy"]={side="HELP",fn=overdrive},
 ["Dragon Flame"]={side="AGAINST",fn=hellstorm},
 ["Leon and Lion"]={side="AGAINST",fn=titanRage},
 ["Thunder Falcon"]={side="AGAINST",fn=emp},
}

local function processPremium(name,sender,count)
 local cfg=premium[tostring(name or "")];if not cfg then return false end
 count=math.clamp(tonumber(count) or 1,1,3);sender=tostring(sender or "VIEWER")
 for _=1,count do cfg.fn(sender) end
 print("PREMIUM GIFT:",cfg.side,name,"from",sender,"x"..count)
 return true
end

dispatch.Event:Connect(function(name,sender,count) processPremium(name,sender,count) end)
debug.OnServerEvent:Connect(function(player,giftName) if player==host() then processPremium(giftName,"TEST_VIEWER",1) end end)

print("PREMIUM GIFT EVENTS V1.2 READY - real orbital standby + reliability patches.")