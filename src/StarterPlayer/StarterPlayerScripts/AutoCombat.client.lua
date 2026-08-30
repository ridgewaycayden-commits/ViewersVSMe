-- AutoCombat.client.lua
-- VIEWERS VS ME - PLAYER AI V2.8
-- Autonomous FPS combat with manual pause + road-focused movement + imported Toolbox weapon models.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")

local player=Players.LocalPlayer
local camera=workspace.CurrentCamera
local enemies=workspace:WaitForChild("TikTokEnemies")
local attackRemote=ReplicatedStorage:WaitForChild("AutoCombatAttack")
local weaponAssets=ReplicatedStorage:WaitForChild("WeaponAssets",10)
local rng=Random.new()

-- Logical combat weapon -> imported Studio asset.
-- The logical names stay the same so the existing server damage + TikTok gift system keep working.
local Weapons={
 Pistol={range=100,cooldown=.32,kick=.065,asset="Handgun",size=3.0,offset=CFrame.new(.48,-.58,-1.45)*CFrame.Angles(0,math.rad(180),0)},
 SMG={range=95,cooldown=.10,kick=.035,asset="HyperlaserGun",size=3.8,offset=CFrame.new(.5,-.58,-1.65)*CFrame.Angles(0,math.rad(180),0)},
 Shotgun={range=65,cooldown=.72,kick=.14,asset="RocketLauncher",size=4.5,offset=CFrame.new(.5,-.62,-1.85)*CFrame.Angles(0,math.rad(180),0)},
 Rifle={range=145,cooldown=.22,kick=.06,asset="AK47",size=3.75,offset=CFrame.new(.78,-.82,-2.18)*CFrame.Angles(math.rad(-3),math.rad(172),math.rad(2))},
 Minigun={range=120,cooldown=.055,kick=.025,asset="Minigun",size=4.8,offset=CFrame.new(.53,-.67,-1.95)*CFrame.Angles(0,math.rad(180),0)},
 Sword={range=10,cooldown=.48,kick=.10,asset="Knife",size=2.7,offset=CFrame.new(.58,-.7,-1.25)*CFrame.Angles(math.rad(-12),math.rad(180),math.rad(8))},
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

local losParams=RaycastParams.new()
losParams.FilterType=Enum.RaycastFilterType.Exclude
losParams.IgnoreWater=true

local moveRayParams=RaycastParams.new()
moveRayParams.FilterType=Enum.RaycastFilterType.Exclude
moveRayParams.IgnoreWater=true

local function getCharacter()
 local c=player.Character
 if not c then return end
 local h=c:FindFirstChildOfClass("Humanoid")
 local r=c:FindFirstChild("HumanoidRootPart")
 local hd=c:FindFirstChild("Head")
 if h and r and hd and h.Health>0 then return c,h,r,hd end
end

local function alive(m)
 local h=m and m:FindFirstChildOfClass("Humanoid")
 local r=m and m:FindFirstChild("HumanoidRootPart")
 return m and m.Parent and m:GetAttribute("Dead")~=true and h and r and h.Health>0
end

local function point(m)
 local h=m:FindFirstChild("Head") or m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart")
 return h and h.Position
end

local function los(m)
 if not alive(m) then return false end
 local p=point(m)
 if not p then return false end
 local d=p-camera.CFrame.Position
 losParams.FilterDescendantsInstances={player.Character,camera,viewModel}
 local hit=workspace:Raycast(camera.CFrame.Position,d,losParams)
 return hit and hit.Instance:IsDescendantOf(m)
end

local function nearest(root)
 local best,bd,vis
 for _,m in ipairs(enemies:GetChildren()) do
  if alive(m) then
   local r=m:FindFirstChild("HumanoidRootPart")
   local d=(r.Position-root.Position).Magnitude
   local v=los(m)
   if not bd or (v and not vis) or (v==vis and d<bd) then best,bd,vis=m,d,v end
  end
 end
 return best,bd,vis
end

local function giftGun()
 local n=player:GetAttribute("GiftWeapon")
 local u=player:GetAttribute("GiftWeaponUntil") or 0
 if type(n)=="string" and Weapons[n] and n~="Sword" and u>workspace:GetServerTimeNow() then return n end
 return "Rifle"
end

local function clearVM()
 if viewModel then viewModel:Destroy() end
 viewModel=nil;weaponRoot=nil;muzzlePart=nil;shownWeapon=nil
end

local function fallbackWeapon(n)
 local m=Instance.new("Model")
 m.Name="FPSViewModel_"..n
 m.Parent=camera
 local p=Instance.new("Part")
 p.Name="Handle";p.Size=Vector3.new(.6,.6,3.2);p.Material=Enum.Material.Metal;p.Color=Color3.fromRGB(35,42,52)
 p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.Parent=m
 m.PrimaryPart=p
 return m,p
end

local function makeWeapon(n)
 clearVM();shownWeapon=n
 local cfg=Weapons[n] or Weapons.Rifle
 local source=weaponAssets and weaponAssets:FindFirstChild(cfg.asset)

 if not source then
  warn("VIEWERS VS ME: missing weapon asset",cfg.asset,"- using fallback")
  viewModel,weaponRoot=fallbackWeapon(n)
  return
 end

 local holder=Instance.new("Model")
 holder.Name="FPSViewModel_"..cfg.asset
 holder.Parent=camera

 local clone=source:Clone()
 for _,obj in ipairs(clone:GetDescendants()) do
  if obj:IsA("Script") or obj:IsA("LocalScript") or obj:IsA("ModuleScript") or obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
   obj:Destroy()
  end
 end
 for _,child in ipairs(clone:GetChildren()) do child.Parent=holder end
 clone:Destroy()

 weaponRoot=holder:FindFirstChild("Handle",true) or holder:FindFirstChild("Main",true) or holder:FindFirstChild("AimPart",true) or holder:FindFirstChildWhichIsA("BasePart",true)
 if not weaponRoot then
  holder:Destroy()
  viewModel,weaponRoot=fallbackWeapon(n)
  return
 end

 for _,obj in ipairs(holder:GetDescendants()) do
  if obj:IsA("BasePart") then
   obj.Anchored=true;obj.CanCollide=false;obj.CanTouch=false;obj.CanQuery=false;obj.CastShadow=false
  end
 end
 holder.PrimaryPart=weaponRoot

 local ok,_,size=pcall(function()
  local cf,s=holder:GetBoundingBox()
  return cf,s
 end)
 if ok and size then
  local longest=math.max(size.X,size.Y,size.Z)
  if longest>.05 then pcall(function() holder:ScaleTo(math.clamp(cfg.size/longest,.06,10)) end) end
 end

 muzzlePart=holder:FindFirstChild("Muzzle",true) or holder:FindFirstChild("MouseLoc",true) or holder:FindFirstChild("MuzzleLoc",true) or holder:FindFirstChild("Chamber",true) or holder:FindFirstChild("A1",true)
 viewModel=holder
 print("EQUIPPED IMPORTED WEAPON:",n,"->",cfg.asset)
end

local function shoot(t)
 if not t or not los(t) then return end
 local cfg=Weapons[currentWeapon] or Weapons.Rifle
 if os.clock()-lastShot<cfg.cooldown then return end
 lastShot=os.clock();recoil=cfg.kick;attackRemote:FireServer(t,currentWeapon)
end

local function surfaceScore(hit,rootY)
 if not hit or not hit.Instance then return -100 end
 local p=hit.Instance
 if not p:IsA("BasePart") or not p.CanCollide or hit.Normal.Y<.82 then return -100 end
 local name=string.lower(p.Name)
 local score=0
 local heightDelta=math.abs(hit.Position.Y-(rootY-3))
 if heightDelta<1.5 then score+=5 elseif heightDelta<3 then score+=2 else score-=8 end
 if name:find("road") or name:find("street") or name:find("asphalt") or name:find("pavement") then score+=18 end
 if name:find("sidewalk") or name:find("walkway") or name:find("ground") or name:find("floor") then score+=7 end
 if name:find("roof") or name:find("crate") or name:find("box") or name:find("car") or name:find("truck") or name:find("bus") or name:find("bench") or name:find("table") or name:find("container") or name:find("dumpster") then score-=30 end
 if p.Material==Enum.Material.Asphalt then score+=16 end
 if p.Material==Enum.Material.Concrete then score+=9 end
 if p.Material==Enum.Material.Cobblestone then score+=8 end
 if p.Material==Enum.Material.Metal or p.Material==Enum.Material.Wood or p.Material==Enum.Material.WoodPlanks then score-=5 end
 return score
end

local function rotated(dir,deg)
 if dir.Magnitude<.01 then return dir end
 local a=math.rad(deg)
 local x=dir.X*math.cos(a)-dir.Z*math.sin(a)
 local z=dir.X*math.sin(a)+dir.Z*math.cos(a)
 return Vector3.new(x,0,z).Unit
end

local function roadAdjustedDirection(root,desired)
 if desired.Magnitude<.01 then return Vector3.zero end
 if os.clock()<nextRoadCheck and cachedRoadDir.Magnitude>.01 then return cachedRoadDir end
 nextRoadCheck=os.clock()+.12
 moveRayParams.FilterDescendantsInstances={player.Character,enemies,camera}
 local bestDir=nil
 local bestScore=-1e9
 local angles={0,-18,18,-35,35,-55,55,-80,80,110,-110,180}
 for _,ang in ipairs(angles) do
  local dir=rotated(desired,ang)
  local probe=root.Position+dir*8+Vector3.new(0,6,0)
  local ground=workspace:Raycast(probe,Vector3.new(0,-14,0),moveRayParams)
  local score=surfaceScore(ground,root.Position.Y)
  score+=math.max(-5,desired:Dot(dir)*6)
  local wall=workspace:Raycast(root.Position+Vector3.new(0,1.5,0),dir*5,moveRayParams)
  if wall and wall.Instance and wall.Instance.CanCollide then score-=35 end
  if ground and math.abs(ground.Position.Y-(root.Position.Y-3))>3.2 then score-=25 end
  if score>bestScore then bestScore=score;bestDir=dir end
 end
 cachedRoadDir=(bestDir or desired).Unit
 return cachedRoadDir
end

local function chooseRoam(root)
 local best=nil
 local bestScore=-1e9
 moveRayParams.FilterDescendantsInstances={player.Character,enemies,camera}
 for _=1,20 do
  local a=rng:NextNumber(0,math.pi*2)
  local rad=rng:NextNumber(24,55)
  local candidate=root.Position+Vector3.new(math.cos(a)*rad,0,math.sin(a)*rad)
  local hit=workspace:Raycast(candidate+Vector3.new(0,10,0),Vector3.new(0,-22,0),moveRayParams)
  local score=surfaceScore(hit,root.Position.Y)
  if score>bestScore and hit then bestScore=score;best=hit.Position end
 end
 roamGoal=best or (root.Position+root.CFrame.LookVector*35)
 roamExpire=os.clock()+rng:NextNumber(4,8)
end

player.CameraMode=Enum.CameraMode.LockFirstPerson

RunService.RenderStepped:Connect(function(dt)
 local char,hum,root,head=getCharacter();if not char then return end
 local paused=player:GetAttribute("AutoMovePaused")==true
 local target,dist,visible=nearest(root)
 local desired=Vector3.zero

 if paused then
  currentWeapon=giftGun()
  if target and visible then if dist<=8.5 then currentWeapon="Sword" end;shoot(target) end
 else
  if target and alive(target) then
   local er=target:FindFirstChild("HumanoidRootPart")
   local flat=Vector3.new(er.Position.X-root.Position.X,0,er.Position.Z-root.Position.Z)
   if visible then
    if os.clock()>nextStrafeFlip then strafeSign=-strafeSign;nextStrafeFlip=os.clock()+rng:NextNumber(1,2.4) end
    local right=flat.Magnitude>0 and Vector3.new(-flat.Z,0,flat.X).Unit or Vector3.xAxis
    if dist>31 then desired=flat.Unit elseif dist<10 then desired=(-flat.Unit+right*.35*strafeSign).Unit else desired=(right*strafeSign+flat.Unit*.12).Unit end
    desired=roadAdjustedDirection(root,desired)
    hum.WalkSpeed=20;hum:Move(desired,false)
    currentWeapon=dist<=8.5 and "Sword" or giftGun();shoot(target)
   else
    currentWeapon=giftGun();hum.WalkSpeed=19
    if flat.Magnitude>0 then desired=roadAdjustedDirection(root,flat.Unit);hum:Move(desired,false) end
   end
  else
   currentWeapon=giftGun()
   if not roamGoal or os.clock()>roamExpire or (root.Position-roamGoal).Magnitude<5 then chooseRoam(root) end
   local d=Vector3.new(roamGoal.X-root.Position.X,0,roamGoal.Z-root.Position.Z)
   if d.Magnitude>0 then desired=roadAdjustedDirection(root,d.Unit);hum.WalkSpeed=15.5;hum:Move(desired,false) end
  end

  local look=target and visible and point(target) or (root.Position+(desired.Magnitude>.1 and desired or root.CFrame.LookVector)*30+Vector3.new(0,1.4,0))
  if look then
   local cp=head.Position+Vector3.new(0,.15,0)
   camera.CFrame=camera.CFrame:Lerp(CFrame.lookAt(cp,look),math.clamp(dt*3.5,0,1))
   local f=camera.CFrame.LookVector
   root.CFrame=root.CFrame:Lerp(CFrame.lookAt(root.Position,root.Position+Vector3.new(f.X,0,f.Z)),math.clamp(dt*4,0,1))
  end
 end

 if shownWeapon~=currentWeapon then makeWeapon(currentWeapon) end
 recoil*=math.max(0,1-dt*10)
 if viewModel and weaponRoot then
  local cfg=Weapons[currentWeapon] or Weapons.Rifle
  local recoilCF=CFrame.new(0,0,recoil*1.5)*CFrame.Angles(math.rad(-recoil*45),0,0)
  viewModel:PivotTo(camera.CFrame*cfg.offset*recoilCF)
 end
end)

player.CharacterAdded:Connect(function()
 task.wait(.4);clearVM();roamGoal=nil;cachedRoadDir=Vector3.zero
end)

print("PLAYER AI V2.8 READY - imported guns + TikTok gift weapons + road-focused movement")
