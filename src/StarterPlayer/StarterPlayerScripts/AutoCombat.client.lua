-- AutoCombat.client.lua
-- VIEWERS VS ME - PLAYER AI V3.2
-- Imported FPS weapons + visible gunfire + ammo/reload + manual pause + road-focused movement.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Debris=game:GetService("Debris")
local TweenService=game:GetService("TweenService")

local player=Players.LocalPlayer
local camera=workspace.CurrentCamera
local enemies=workspace:WaitForChild("TikTokEnemies")
local attackRemote=ReplicatedStorage:WaitForChild("AutoCombatAttack")
local weaponAssets=ReplicatedStorage:WaitForChild("WeaponAssets",10)
local rng=Random.new()

local Weapons={
 Pistol={range=100,cooldown=.30,kick=.075,asset="Handgun",size=2.65,offset=CFrame.new(.76,-.82,-2.05)*CFrame.Angles(math.rad(-5),math.rad(169),math.rad(2)),tracer=Color3.fromRGB(255,214,105),clip=12,reserve=72,reload=1.05},
 SMG={range=95,cooldown=.09,kick=.04,asset="HyperlaserGun",size=3.35,offset=CFrame.new(.77,-.80,-2.12)*CFrame.Angles(math.rad(-4),math.rad(170),math.rad(2)),tracer=Color3.fromRGB(90,220,255),clip=36,reserve=180,reload=1.25},
 Shotgun={range=65,cooldown=.70,kick=.16,asset="RocketLauncher",size=3.8,offset=CFrame.new(.84,-.89,-2.35)*CFrame.Angles(math.rad(-6),math.rad(169),math.rad(2)),tracer=Color3.fromRGB(255,150,75),clip=6,reserve=36,reload=1.65},
 Rifle={range=145,cooldown=.16,kick=.075,asset="AK47",size=3.75,offset=CFrame.new(1.18,-1.08,-2.35)*CFrame.Angles(math.rad(-7),math.rad(166),math.rad(3)),tracer=Color3.fromRGB(255,214,90),clip=30,reserve=150,reload=1.35},
 Minigun={range=120,cooldown=.055,kick=.028,asset="Minigun",size=4.05,offset=CFrame.new(.90,-.98,-2.55)*CFrame.Angles(math.rad(-6),math.rad(169),math.rad(2)),tracer=Color3.fromRGB(255,105,75),clip=120,reserve=480,reload=2.0},
 Sword={range=10,cooldown=.45,kick=.11,asset="Knife",size=2.35,offset=CFrame.new(.78,-.86,-1.65)*CFrame.Angles(math.rad(-15),math.rad(174),math.rad(11)),tracer=Color3.fromRGB(160,235,255),clip=1,reserve=0,reload=0},
}

local currentWeapon="Rifle"
local shownWeapon
local lastShot=0
local recoil=0
local viewModel
local weaponRoot
local muzzlePart
local roamGoal
local roamExpire=0
local strafeSign=1
local nextStrafeFlip=0
local nextRoadCheck=0
local cachedRoadDir=Vector3.zero
local bobClock=0
local reloading=false
local ammo={}
local reserve={}

for name,cfg in pairs(Weapons) do ammo[name]=cfg.clip;reserve[name]=cfg.reserve end

local losParams=RaycastParams.new();losParams.FilterType=Enum.RaycastFilterType.Exclude;losParams.IgnoreWater=true
local moveRayParams=RaycastParams.new();moveRayParams.FilterType=Enum.RaycastFilterType.Exclude;moveRayParams.IgnoreWater=true

local function publishWeaponState()
 local cfg=Weapons[currentWeapon] or Weapons.Rifle
 player:SetAttribute("CurrentWeapon",currentWeapon)
 player:SetAttribute("CurrentWeaponAsset",cfg.asset)
 player:SetAttribute("CurrentAmmo",ammo[currentWeapon] or cfg.clip)
 player:SetAttribute("ReserveAmmo",reserve[currentWeapon] or 0)
 player:SetAttribute("Reloading",reloading)
end

local function getCharacter()
 local c=player.Character;if not c then return end
 local h=c:FindFirstChildOfClass("Humanoid");local r=c:FindFirstChild("HumanoidRootPart");local hd=c:FindFirstChild("Head")
 if h and r and hd and h.Health>0 then return c,h,r,hd end
end

local function alive(m)
 local h=m and m:FindFirstChildOfClass("Humanoid");local r=m and m:FindFirstChild("HumanoidRootPart")
 return m and m.Parent and m:GetAttribute("Dead")~=true and h and r and h.Health>0
end

local function point(m)
 local h=m:FindFirstChild("Head") or m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart")
 return h and h.Position
end

local function los(m)
 if not alive(m) then return false end
 local p=point(m);if not p then return false end
 local d=p-camera.CFrame.Position
 losParams.FilterDescendantsInstances={player.Character,camera,viewModel}
 local hit=workspace:Raycast(camera.CFrame.Position,d,losParams)
 return hit and hit.Instance:IsDescendantOf(m)
end

local function nearest(root)
 local best,bd,vis
 for _,m in ipairs(enemies:GetChildren()) do
  if alive(m) then
   local r=m:FindFirstChild("HumanoidRootPart");local d=(r.Position-root.Position).Magnitude;local v=los(m)
   if not bd or (v and not vis) or (v==vis and d<bd) then best,bd,vis=m,d,v end
  end
 end
 return best,bd,vis
end

local function giftGun()
 local n=player:GetAttribute("GiftWeapon");local u=player:GetAttribute("GiftWeaponUntil") or 0
 if type(n)=="string" and Weapons[n] and n~="Sword" and u>workspace:GetServerTimeNow() then return n end
 return "Rifle"
end

local function clearVM()
 if viewModel then viewModel:Destroy() end
 viewModel=nil;weaponRoot=nil;muzzlePart=nil;shownWeapon=nil
end

local function fallbackWeapon(n)
 local m=Instance.new("Model");m.Name="FPSViewModel_"..n;m.Parent=camera
 local p=Instance.new("Part");p.Name="Handle";p.Size=Vector3.new(.6,.6,3.2);p.Material=Enum.Material.Metal;p.Color=Color3.fromRGB(35,42,52);p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.Parent=m;m.PrimaryPart=p
 return m,p
end

local function makeWeapon(n)
 clearVM();shownWeapon=n
 local cfg=Weapons[n] or Weapons.Rifle
 local source=weaponAssets and weaponAssets:FindFirstChild(cfg.asset)
 if not source then warn("VIEWERS VS ME: missing weapon asset",cfg.asset,"- using fallback");viewModel,weaponRoot=fallbackWeapon(n);publishWeaponState();return end
 local holder=Instance.new("Model");holder.Name="FPSViewModel_"..cfg.asset;holder.Parent=camera
 local clone=source:Clone()
 for _,obj in ipairs(clone:GetDescendants()) do
  if obj:IsA("Script") or obj:IsA("LocalScript") or obj:IsA("ModuleScript") or obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then obj:Destroy() end
 end
 for _,child in ipairs(clone:GetChildren()) do child.Parent=holder end
 clone:Destroy()
 weaponRoot=holder:FindFirstChild("Handle",true) or holder:FindFirstChild("Main",true) or holder:FindFirstChild("AimPart",true) or holder:FindFirstChildWhichIsA("BasePart",true)
 if not weaponRoot then holder:Destroy();viewModel,weaponRoot=fallbackWeapon(n);publishWeaponState();return end
 for _,obj in ipairs(holder:GetDescendants()) do
  if obj:IsA("BasePart") then obj.Anchored=true;obj.CanCollide=false;obj.CanTouch=false;obj.CanQuery=false;obj.CastShadow=false end
 end
 holder.PrimaryPart=weaponRoot
 local ok,_,size=pcall(function() local cf,s=holder:GetBoundingBox();return cf,s end)
 if ok and size then local longest=math.max(size.X,size.Y,size.Z);if longest>.05 then pcall(function() holder:ScaleTo(math.clamp(cfg.size/longest,.06,10)) end) end end
 muzzlePart=holder:FindFirstChild("Muzzle",true) or holder:FindFirstChild("MuzzleLoc",true) or holder:FindFirstChild("MouseLoc",true) or holder:FindFirstChild("Chamber",true) or holder:FindFirstChild("A1",true)
 viewModel=holder
 publishWeaponState()
 print("EQUIPPED IMPORTED WEAPON:",n,"->",cfg.asset)
end

local function muzzlePosition()
 if muzzlePart then
  if muzzlePart:IsA("Attachment") then return muzzlePart.WorldPosition end
  if muzzlePart:IsA("BasePart") then return muzzlePart.Position end
 end
 return (camera.CFrame*CFrame.new(.78,-.45,-3.2)).Position
end

local function tracerFX(fromPos,toPos,color,width,lifetime)
 local delta=toPos-fromPos;local dist=delta.Magnitude;if dist<.1 then return end
 local p=Instance.new("Part");p.Name="LocalBulletTracer";p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.Material=Enum.Material.Neon;p.Color=color;p.Transparency=.02;p.Size=Vector3.new(width,width,dist);p.CFrame=CFrame.lookAt((fromPos+toPos)*.5,toPos);p.Parent=workspace
 local light=Instance.new("PointLight");light.Color=color;light.Brightness=.7;light.Range=5;light.Shadows=false;light.Parent=p
 Debris:AddItem(p,lifetime or .10)
end

local function muzzleFlash(pos,cfg)
 local flash=Instance.new("Part");flash.Name="LocalMuzzleFlash";flash.Anchored=true;flash.CanCollide=false;flash.CanTouch=false;flash.CanQuery=false;flash.CastShadow=false;flash.Material=Enum.Material.Neon;flash.Color=cfg.tracer;flash.Shape=Enum.PartType.Ball;flash.Size=Vector3.new(.52,.52,.52);flash.CFrame=CFrame.new(pos);flash.Parent=workspace
 local light=Instance.new("PointLight");light.Color=cfg.tracer;light.Brightness=4.5;light.Range=12;light.Shadows=false;light.Parent=flash
 TweenService:Create(flash,TweenInfo.new(.055),{Size=Vector3.new(.12,.12,.12),Transparency=1}):Play();Debris:AddItem(flash,.07)
end

local function casingFX()
 if currentWeapon=="Sword" or currentWeapon=="Minigun" or currentWeapon=="Shotgun" then return end
 local shell=Instance.new("Part");shell.Name="LocalShell";shell.Size=Vector3.new(.10,.10,.28);shell.Material=Enum.Material.Metal;shell.Color=Color3.fromRGB(195,145,60);shell.CanCollide=false;shell.CanTouch=false;shell.CanQuery=false;shell.CastShadow=false
 shell.CFrame=camera.CFrame*CFrame.new(.55,-.34,-1.15)*CFrame.Angles(0,0,math.rad(90));shell.Parent=workspace
 shell.AssemblyLinearVelocity=camera.CFrame.RightVector*rng:NextNumber(8,13)+Vector3.new(0,rng:NextNumber(4,8),0)+camera.CFrame.LookVector*rng:NextNumber(-1,2)
 shell.AssemblyAngularVelocity=Vector3.new(rng:NextNumber(-22,22),rng:NextNumber(-22,22),rng:NextNumber(-22,22));Debris:AddItem(shell,1)
end

local function impactFX(pos,color)
 local hit=Instance.new("Part");hit.Name="LocalImpact";hit.Anchored=true;hit.CanCollide=false;hit.CanTouch=false;hit.CanQuery=false;hit.CastShadow=false;hit.Material=Enum.Material.Neon;hit.Color=color;hit.Shape=Enum.PartType.Ball;hit.Size=Vector3.new(.22,.22,.22);hit.CFrame=CFrame.new(pos);hit.Parent=workspace;Debris:AddItem(hit,.11)
end

local function startReload()
 if reloading or currentWeapon=="Sword" then return end
 local cfg=Weapons[currentWeapon] or Weapons.Rifle
 if (ammo[currentWeapon] or 0)>=cfg.clip or (reserve[currentWeapon] or 0)<=0 then return end
 reloading=true;publishWeaponState()
 local thisWeapon=currentWeapon
 task.delay(cfg.reload,function()
  if currentWeapon~=thisWeapon then reloading=false;publishWeaponState();return end
  local need=cfg.clip-(ammo[thisWeapon] or 0)
  local take=math.min(need,reserve[thisWeapon] or 0)
  ammo[thisWeapon]=(ammo[thisWeapon] or 0)+take
  reserve[thisWeapon]=(reserve[thisWeapon] or 0)-take
  reloading=false;publishWeaponState()
 end)
end

local function shoot(t)
 if not t or not los(t) or reloading then return end
 local cfg=Weapons[currentWeapon] or Weapons.Rifle
 if currentWeapon~="Sword" and (ammo[currentWeapon] or 0)<=0 then startReload();return end
 if os.clock()-lastShot<cfg.cooldown then return end
 lastShot=os.clock();recoil=cfg.kick
 local aim=point(t);if not aim then return end
 local from=muzzlePosition()
 if currentWeapon=="Shotgun" then
  for _=1,7 do local spread=Vector3.new(rng:NextNumber(-1.8,1.8),rng:NextNumber(-1.3,1.3),rng:NextNumber(-1.8,1.8));tracerFX(from,aim+spread,cfg.tracer,.075,.11) end
 elseif currentWeapon~="Sword" then
  tracerFX(from,aim,cfg.tracer,currentWeapon=="Minigun" and .065 or .09,currentWeapon=="Minigun" and .075 or .11)
 end
 if currentWeapon~="Sword" then
  ammo[currentWeapon]=math.max(0,(ammo[currentWeapon] or cfg.clip)-1)
  publishWeaponState();muzzleFlash(from,cfg);casingFX();impactFX(aim,cfg.tracer)
  if ammo[currentWeapon]<=0 then startReload() end
 end
 attackRemote:FireServer(t,currentWeapon)
end

local function surfaceScore(hit,rootY)
 if not hit or not hit.Instance then return -100 end
 local p=hit.Instance;if not p:IsA("BasePart") or not p.CanCollide or hit.Normal.Y<.82 then return -100 end
 local name=string.lower(p.Name);local score=0;local heightDelta=math.abs(hit.Position.Y-(rootY-3))
 if heightDelta<1.5 then score+=5 elseif heightDelta<3 then score+=2 else score-=8 end
 if name:find("road") or name:find("street") or name:find("asphalt") or name:find("pavement") then score+=18 end
 if name:find("sidewalk") or name:find("walkway") or name:find("ground") or name:find("floor") then score+=7 end
 if name:find("roof") or name:find("crate") or name:find("box") or name:find("car") or name:find("truck") or name:find("bus") or name:find("bench") or name:find("table") or name:find("container") or name:find("dumpster") then score-=30 end
 if p.Material==Enum.Material.Asphalt then score+=16 end;if p.Material==Enum.Material.Concrete then score+=9 end;if p.Material==Enum.Material.Cobblestone then score+=8 end
 if p.Material==Enum.Material.Metal or p.Material==Enum.Material.Wood or p.Material==Enum.Material.WoodPlanks then score-=5 end
 return score
end

local function rotated(dir,deg)
 if dir.Magnitude<.01 then return dir end
 local a=math.rad(deg);local x=dir.X*math.cos(a)-dir.Z*math.sin(a);local z=dir.X*math.sin(a)+dir.Z*math.cos(a);return Vector3.new(x,0,z).Unit
end

local function roadAdjustedDirection(root,desired)
 if desired.Magnitude<.01 then return Vector3.zero end
 if os.clock()<nextRoadCheck and cachedRoadDir.Magnitude>.01 then return cachedRoadDir end
 nextRoadCheck=os.clock()+.12;moveRayParams.FilterDescendantsInstances={player.Character,enemies,camera}
 local bestDir=nil;local bestScore=-1e9;local angles={0,-18,18,-35,35,-55,55,-80,80,110,-110,180}
 for _,ang in ipairs(angles) do
  local dir=rotated(desired,ang);local probe=root.Position+dir*8+Vector3.new(0,6,0);local ground=workspace:Raycast(probe,Vector3.new(0,-14,0),moveRayParams);local score=surfaceScore(ground,root.Position.Y)
  score+=math.max(-5,desired:Dot(dir)*6);local wall=workspace:Raycast(root.Position+Vector3.new(0,1.5,0),dir*5,moveRayParams);if wall and wall.Instance and wall.Instance.CanCollide then score-=35 end
  if ground and math.abs(ground.Position.Y-(root.Position.Y-3))>3.2 then score-=25 end;if score>bestScore then bestScore=score;bestDir=dir end
 end
 cachedRoadDir=(bestDir or desired).Unit;return cachedRoadDir
end

local function chooseRoam(root)
 local best=nil;local bestScore=-1e9;moveRayParams.FilterDescendantsInstances={player.Character,enemies,camera}
 for _=1,20 do local a=rng:NextNumber(0,math.pi*2);local rad=rng:NextNumber(24,55);local candidate=root.Position+Vector3.new(math.cos(a)*rad,0,math.sin(a)*rad);local hit=workspace:Raycast(candidate+Vector3.new(0,10,0),Vector3.new(0,-22,0),moveRayParams);local score=surfaceScore(hit,root.Position.Y);if score>bestScore and hit then bestScore=score;best=hit.Position end end
 roamGoal=best or (root.Position+root.CFrame.LookVector*35);roamExpire=os.clock()+rng:NextNumber(4,8)
end

player.CameraMode=Enum.CameraMode.LockFirstPerson
publishWeaponState()

RunService.RenderStepped:Connect(function(dt)
 local char,hum,root,head=getCharacter();if not char then return end
 local paused=player:GetAttribute("AutoMovePaused")==true;local target,dist,visible=nearest(root);local desired=Vector3.zero
 local wanted=currentWeapon
 if paused then
  wanted=giftGun();if target and visible and dist<=8.5 then wanted="Sword" end
 else
  if target and alive(target) then
   local er=target:FindFirstChild("HumanoidRootPart");local flat=Vector3.new(er.Position.X-root.Position.X,0,er.Position.Z-root.Position.Z)
   if visible then
    if os.clock()>nextStrafeFlip then strafeSign=-strafeSign;nextStrafeFlip=os.clock()+rng:NextNumber(1,2.4) end
    local right=flat.Magnitude>0 and Vector3.new(-flat.Z,0,flat.X).Unit or Vector3.xAxis
    if dist>31 then desired=flat.Unit elseif dist<10 then desired=(-flat.Unit+right*.35*strafeSign).Unit else desired=(right*strafeSign+flat.Unit*.12).Unit end
    desired=roadAdjustedDirection(root,desired);hum.WalkSpeed=20;hum:Move(desired,false);wanted=dist<=8.5 and "Sword" or giftGun()
   else wanted=giftGun();hum.WalkSpeed=19;if flat.Magnitude>0 then desired=roadAdjustedDirection(root,flat.Unit);hum:Move(desired,false) end end
  else
   wanted=giftGun();if not roamGoal or os.clock()>roamExpire or (root.Position-roamGoal).Magnitude<5 then chooseRoam(root) end
   local d=Vector3.new(roamGoal.X-root.Position.X,0,roamGoal.Z-root.Position.Z);if d.Magnitude>0 then desired=roadAdjustedDirection(root,d.Unit);hum.WalkSpeed=15.5;hum:Move(desired,false) end
  end
 end
 if wanted~=currentWeapon then currentWeapon=wanted;reloading=false;publishWeaponState() end
 if target and visible then shoot(target) end
 if not paused then
  local look=target and visible and point(target) or (root.Position+(desired.Magnitude>.1 and desired or root.CFrame.LookVector)*30+Vector3.new(0,1.4,0))
  if look then local cp=head.Position+Vector3.new(0,.15,0);camera.CFrame=camera.CFrame:Lerp(CFrame.lookAt(cp,look),math.clamp(dt*3.5,0,1));local f=camera.CFrame.LookVector;root.CFrame=root.CFrame:Lerp(CFrame.lookAt(root.Position,root.Position+Vector3.new(f.X,0,f.Z)),math.clamp(dt*4,0,1)) end
 end
 if shownWeapon~=currentWeapon then makeWeapon(currentWeapon) end
 recoil*=math.max(0,1-dt*11);bobClock+=dt*(hum.MoveDirection.Magnitude>.1 and 7 or 2)
 if viewModel and weaponRoot then
  local cfg=Weapons[currentWeapon] or Weapons.Rifle
  local moveAmt=hum.MoveDirection.Magnitude>.1 and 1 or .18
  local bob=CFrame.new(math.sin(bobClock)*.010*moveAmt,math.abs(math.cos(bobClock*2))*.007*moveAmt,0)*CFrame.Angles(math.rad(math.cos(bobClock)*.12*moveAmt),0,math.rad(math.sin(bobClock)*.30*moveAmt))
  local recoilCF=CFrame.new(0,0,recoil*1.9)*CFrame.Angles(math.rad(-recoil*58),math.rad(recoil*8),0)
  viewModel:PivotTo(camera.CFrame*cfg.offset*bob*recoilCF)
 end
end)

player.CharacterAdded:Connect(function() task.wait(.4);clearVM();roamGoal=nil;cachedRoadDir=Vector3.zero;reloading=false;publishWeaponState() end)
print("PLAYER AI V3.2 READY - AK proper FPS scale/placement, gift weapons preserved")