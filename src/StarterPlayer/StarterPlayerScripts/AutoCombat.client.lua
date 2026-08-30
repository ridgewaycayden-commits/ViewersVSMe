-- AutoCombat.client.lua
-- VIEWERS VS ME - PLAYER AI V2.7
-- Autonomous FPS combat with manual pause + road-focused movement for City Map.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Debris=game:GetService("Debris")

local player=Players.LocalPlayer
local camera=workspace.CurrentCamera
local enemies=workspace:WaitForChild("TikTokEnemies")
local attackRemote=ReplicatedStorage:WaitForChild("AutoCombatAttack")
local rng=Random.new()

local Weapons={
 Pistol={range=100,cooldown=.32,color=Color3.fromRGB(255,200,80),kick=.065},SMG={range=95,cooldown=.10,color=Color3.fromRGB(70,205,255),kick=.035},Shotgun={range=65,cooldown=.72,color=Color3.fromRGB(255,135,65),kick=.14},Rifle={range=145,cooldown=.22,color=Color3.fromRGB(105,255,150),kick=.06},Minigun={range=120,cooldown=.055,color=Color3.fromRGB(255,75,75),kick=.025},Sword={range=10,cooldown=.48,color=Color3.fromRGB(90,220,255),kick=.10},
}

local currentWeapon="Rifle"
local shownWeapon
local lastShot=0
local recoil=0
local viewModel
local weaponRoot
local muzzlePart
local bobTime=0
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
 losParams.FilterDescendantsInstances={player.Character,camera}
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

local function part(m,n,s,c,mat,cf)
 local p=Instance.new("Part")
 p.Name=n;p.Size=s;p.Color=c;p.Material=mat or Enum.Material.Metal;p.Anchored=true
 p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.CFrame=cf;p.Parent=m
 return p
end

local function clearVM()
 if viewModel then viewModel:Destroy() end
 viewModel=nil;weaponRoot=nil;muzzlePart=nil;shownWeapon=nil
end

local function makeWeapon(n)
 clearVM();shownWeapon=n
 local m=Instance.new("Model");m.Name="FPSViewModel";m.Parent=camera;viewModel=m
 weaponRoot=part(m,"Root",Vector3.new(.05,.05,.05),Color3.new(),Enum.Material.SmoothPlastic,CFrame.new())
 weaponRoot.Transparency=1;m.PrimaryPart=weaponRoot
 part(m,"Gun",Vector3.new(.58,.62,3.4),Color3.fromRGB(35,42,52),Enum.Material.Metal,CFrame.new(.15,-.1,-1.5))
 part(m,"Barrel",Vector3.new(.15,.15,2),Color3.fromRGB(100,110,120),Enum.Material.Metal,CFrame.new(.15,.05,-4))
 part(m,"Grip",Vector3.new(.35,.85,.4),Color3.fromRGB(15,17,20),Enum.Material.SmoothPlastic,CFrame.new(.15,-.65,-.25))
 muzzlePart=part(m,"Muzzle",Vector3.new(.1,.1,.1),Weapons[n].color,Enum.Material.Neon,CFrame.new(.15,.05,-5));muzzlePart.Transparency=1
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
 if not p:IsA("BasePart") then return -100 end
 if not p.CanCollide then return -100 end
 if hit.Normal.Y < .82 then return -100 end

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

  -- Prefer staying generally pointed where the AI wanted to go.
  score += math.max(-5,desired:Dot(dir)*6)

  -- Reject directions with a solid waist/chest-height obstacle immediately ahead.
  local wall=workspace:Raycast(root.Position+Vector3.new(0,1.5,0),dir*5,moveRayParams)
  if wall and wall.Instance and wall.Instance.CanCollide then score-=35 end

  -- Big vertical change means stairs/props/roofs; roads should remain nearly flat.
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
  -- Absolutely no AI movement/camera steering while paused.
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
 bobTime+=dt*(hum.MoveDirection.Magnitude>.1 and 8 or 2)
 recoil*=math.max(0,1-dt*10)
 if viewModel and weaponRoot then
  viewModel:PivotTo(camera.CFrame*CFrame.new(.46,-.62,-1.25+recoil)*CFrame.Angles(math.rad(-4-recoil*50),math.rad(-2),math.rad(-1)))
 end
end)

player.CharacterAdded:Connect(function()
 task.wait(.4);clearVM();roamGoal=nil;cachedRoadDir=Vector3.zero
end)

print("PLAYER AI V2.7 READY - clean pause + road-focused movement")
