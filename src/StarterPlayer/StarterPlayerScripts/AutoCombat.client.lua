-- AutoCombat.client.lua
-- VIEWERS VS ME - PLAYER AI V3.7
-- Imported FPS weapons + melee + gift guns + manual pause + reliable human-like navigation.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Debris=game:GetService("Debris")
local TweenService=game:GetService("TweenService")
local PathfindingService=game:GetService("PathfindingService")

local player=Players.LocalPlayer
local camera=workspace.CurrentCamera
local enemies=workspace:WaitForChild("TikTokEnemies")
local attackRemote=ReplicatedStorage:WaitForChild("AutoCombatAttack")
local weaponAssets=ReplicatedStorage:WaitForChild("WeaponAssets",10)
local rng=Random.new()

local Weapons={
 Pistol={range=100,cooldown=.30,kick=.075,asset="Handgun",size=2.65,offset=CFrame.new(.76,-.82,-2.05)*CFrame.Angles(math.rad(-5),math.rad(169),math.rad(2)),tracer=Color3.fromRGB(255,214,105),clip=12,reserve=72,reload=1.05},
 SMG={range=95,cooldown=.09,kick=.04,asset="HyperlaserGun",size=3.35,offset=CFrame.new(.77,-.80,-2.12)*CFrame.Angles(math.rad(-4),math.rad(170),math.rad(2)),tracer=Color3.fromRGB(90,220,255),clip=36,reserve=180,reload=1.25},
 Shotgun={range=65,cooldown=.70,kick=.16,asset="Handgun",size=2.65,offset=CFrame.new(.76,-.82,-2.05)*CFrame.Angles(math.rad(-5),math.rad(169),math.rad(2)),tracer=Color3.fromRGB(255,150,75),clip=6,reserve=36,reload=1.65},
 Rifle={range=145,cooldown=.16,kick=.075,asset="AK47",size=3.75,offset=CFrame.new(1.18,-1.08,-2.35)*CFrame.Angles(math.rad(-7),math.rad(166),math.rad(3)),tracer=Color3.fromRGB(255,214,90),clip=30,reserve=150,reload=1.35},
 Minigun={range=120,cooldown=.055,kick=.028,asset="Minigun",size=4.05,offset=CFrame.new(.90,-.98,-2.55)*CFrame.Angles(math.rad(-6),math.rad(169),math.rad(2)),tracer=Color3.fromRGB(255,105,75),clip=120,reserve=480,reload=2.0},
 Sword={range=10,cooldown=.45,kick=0,asset="Knife",size=2.35,offset=CFrame.new(.78,-.86,-1.65)*CFrame.Angles(math.rad(-15),math.rad(174),math.rad(11)),tracer=Color3.fromRGB(160,235,255),clip=1,reserve=0,reload=0},
}

local currentWeapon="Sword"
local shownWeapon,lastShot,recoil=nil,0,0
local viewModel,weaponRoot,muzzlePart
local roamGoal,roamExpire=nil,0
local bobClock,reloading=0,false
local ammo,reserve={},{}
local navWaypoints,navIndex,navGoal={},1,nil
local nextPathCompute,forceRepath=0,false
local nextHumanPause,humanPauseUntil=0,0
local lastRootPos,stuckSince=nil,nil
local idleHeading=nil

for name,cfg in pairs(Weapons) do ammo[name]=cfg.clip;reserve[name]=cfg.reserve end
local losParams=RaycastParams.new();losParams.FilterType=Enum.RaycastFilterType.Exclude;losParams.IgnoreWater=true
local moveRayParams=RaycastParams.new();moveRayParams.FilterType=Enum.RaycastFilterType.Exclude;moveRayParams.IgnoreWater=true

local function publishWeaponState()
 local cfg=Weapons[currentWeapon] or Weapons.Sword
 player:SetAttribute("CurrentWeapon",currentWeapon);player:SetAttribute("CurrentWeaponAsset",cfg.asset)
 player:SetAttribute("CurrentAmmo",ammo[currentWeapon] or cfg.clip);player:SetAttribute("ReserveAmmo",reserve[currentWeapon] or 0);player:SetAttribute("Reloading",reloading)
end
local function getCharacter()
 local c=player.Character;if not c then return end
 local h=c:FindFirstChildOfClass("Humanoid");local r=c:FindFirstChild("HumanoidRootPart");local hd=c:FindFirstChild("Head")
 if h and r and hd and h.Health>0 then return c,h,r,hd end
end
local function alive(m)local h=m and m:FindFirstChildOfClass("Humanoid");local r=m and m:FindFirstChild("HumanoidRootPart");return m and m.Parent and m:GetAttribute("Dead")~=true and h and r and h.Health>0 end
local function point(m)local h=m:FindFirstChild("Head") or m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart");return h and h.Position end
local function los(m)
 if not alive(m) then return false end;local p=point(m);if not p then return false end
 losParams.FilterDescendantsInstances={player.Character,camera,viewModel};local hit=workspace:Raycast(camera.CFrame.Position,p-camera.CFrame.Position,losParams);return hit and hit.Instance:IsDescendantOf(m)
end
local function nearest(root)
 local best,bd,vis
 for _,m in ipairs(enemies:GetChildren()) do if alive(m) then local r=m:FindFirstChild("HumanoidRootPart");local d=(r.Position-root.Position).Magnitude;local v=los(m);if not bd or (v and not vis) or (v==vis and d<bd) then best,bd,vis=m,d,v end end end
 return best,bd,vis
end
local function giftGun()local n=player:GetAttribute("GiftWeapon");local u=player:GetAttribute("GiftWeaponUntil") or 0;if type(n)=="string" and Weapons[n] and n~="Sword" and u>workspace:GetServerTimeNow() then return n end;return "Sword" end
local function clearVM()if viewModel then viewModel:Destroy() end;viewModel=nil;weaponRoot=nil;muzzlePart=nil;shownWeapon=nil end
local function fallbackWeapon(n)local m=Instance.new("Model");m.Name="FPSViewModel_"..n;m.Parent=camera;local p=Instance.new("Part");p.Name="Handle";p.Size=Vector3.new(.6,.6,3.2);p.Material=Enum.Material.Metal;p.Color=Color3.fromRGB(35,42,52);p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.Parent=m;m.PrimaryPart=p;return m,p end
local function makeWeapon(n)
 clearVM();shownWeapon=n;local cfg=Weapons[n] or Weapons.Sword;local source=weaponAssets and weaponAssets:FindFirstChild(cfg.asset)
 if not source then warn("VIEWERS VS ME: missing weapon asset",cfg.asset,"- using fallback");viewModel,weaponRoot=fallbackWeapon(n);publishWeaponState();return end
 local holder=Instance.new("Model");holder.Name="FPSViewModel_"..cfg.asset;holder.Parent=camera;local clone=source:Clone()
 for _,obj in ipairs(clone:GetDescendants()) do if obj:IsA("Script") or obj:IsA("LocalScript") or obj:IsA("ModuleScript") or obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then obj:Destroy() end end
 for _,child in ipairs(clone:GetChildren()) do child.Parent=holder end;clone:Destroy()
 weaponRoot=holder:FindFirstChild("Handle",true) or holder:FindFirstChild("Main",true) or holder:FindFirstChild("AimPart",true) or holder:FindFirstChildWhichIsA("BasePart",true)
 if not weaponRoot then holder:Destroy();viewModel,weaponRoot=fallbackWeapon(n);publishWeaponState();return end
 for _,obj in ipairs(holder:GetDescendants()) do if obj:IsA("BasePart") then obj.Anchored=true;obj.CanCollide=false;obj.CanTouch=false;obj.CanQuery=false;obj.CastShadow=false end end
 holder.PrimaryPart=weaponRoot;local ok,_,size=pcall(function()local cf,s=holder:GetBoundingBox();return cf,s end);if ok and size then local longest=math.max(size.X,size.Y,size.Z);if longest>.05 then pcall(function()holder:ScaleTo(math.clamp(cfg.size/longest,.06,10))end)end end
 muzzlePart=holder:FindFirstChild("Muzzle",true) or holder:FindFirstChild("MuzzleLoc",true) or holder:FindFirstChild("MouseLoc",true) or holder:FindFirstChild("Chamber",true) or holder:FindFirstChild("A1",true);viewModel=holder;publishWeaponState()
end
local function muzzlePosition()if muzzlePart then if muzzlePart:IsA("Attachment") then return muzzlePart.WorldPosition elseif muzzlePart:IsA("BasePart") then return muzzlePart.Position end end;return(camera.CFrame*CFrame.new(.78,-.45,-3.2)).Position end
local function tracerFX(a,b,c,w,l)local d=b-a;local dist=d.Magnitude;if dist<.1 then return end;local p=Instance.new("Part");p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.Material=Enum.Material.Neon;p.Color=c;p.Transparency=.02;p.Size=Vector3.new(w,w,dist);p.CFrame=CFrame.lookAt((a+b)*.5,b);p.Parent=workspace;Debris:AddItem(p,l or .1) end
local function muzzleFlash(pos,cfg)local p=Instance.new("Part");p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.Material=Enum.Material.Neon;p.Color=cfg.tracer;p.Shape=Enum.PartType.Ball;p.Size=Vector3.new(.52,.52,.52);p.CFrame=CFrame.new(pos);p.Parent=workspace;TweenService:Create(p,TweenInfo.new(.055),{Size=Vector3.new(.12,.12,.12),Transparency=1}):Play();Debris:AddItem(p,.07) end
local function casingFX()if currentWeapon=="Sword" or currentWeapon=="Minigun" or currentWeapon=="Shotgun" then return end;local s=Instance.new("Part");s.Size=Vector3.new(.1,.1,.28);s.Material=Enum.Material.Metal;s.Color=Color3.fromRGB(195,145,60);s.CanCollide=false;s.CanTouch=false;s.CanQuery=false;s.CFrame=camera.CFrame*CFrame.new(.55,-.34,-1.15);s.Parent=workspace;s.AssemblyLinearVelocity=camera.CFrame.RightVector*10+Vector3.new(0,6,0);Debris:AddItem(s,1) end
local function impactFX(pos,color)local p=Instance.new("Part");p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Material=Enum.Material.Neon;p.Color=color;p.Shape=Enum.PartType.Ball;p.Size=Vector3.new(.22,.22,.22);p.CFrame=CFrame.new(pos);p.Parent=workspace;Debris:AddItem(p,.11) end
local function startReload()
 if reloading or currentWeapon=="Sword" then return end;local cfg=Weapons[currentWeapon] or Weapons.Sword;if(ammo[currentWeapon]or 0)>=cfg.clip or(reserve[currentWeapon]or 0)<=0 then return end;reloading=true;publishWeaponState();local w=currentWeapon
 task.delay(cfg.reload,function()if currentWeapon~=w then reloading=false;publishWeaponState();return end;local need=cfg.clip-(ammo[w]or 0);local take=math.min(need,reserve[w]or 0);ammo[w]=(ammo[w]or 0)+take;reserve[w]=(reserve[w]or 0)-take;reloading=false;publishWeaponState()end)
end
local function shoot(t)
 if not t or not los(t) or reloading then return end;local cfg=Weapons[currentWeapon]or Weapons.Sword
 if currentWeapon=="Sword" then local pr=player.Character and player.Character:FindFirstChild("HumanoidRootPart");local er=t:FindFirstChild("HumanoidRootPart");if not pr or not er or(er.Position-pr.Position).Magnitude>cfg.range or os.clock()-lastShot<cfg.cooldown then return end;lastShot=os.clock();attackRemote:FireServer(t,"Sword");return end
 if(ammo[currentWeapon]or 0)<=0 then startReload();return end;if os.clock()-lastShot<cfg.cooldown then return end;lastShot=os.clock();recoil=cfg.kick;local aim=point(t);if not aim then return end;local from=muzzlePosition()
 if currentWeapon=="Shotgun" then for _=1,7 do tracerFX(from,aim+Vector3.new(rng:NextNumber(-1.8,1.8),rng:NextNumber(-1.3,1.3),rng:NextNumber(-1.8,1.8)),cfg.tracer,.075,.11)end else tracerFX(from,aim,cfg.tracer,currentWeapon=="Minigun"and .065 or .09,.1)end
 ammo[currentWeapon]=math.max(0,(ammo[currentWeapon]or cfg.clip)-1);publishWeaponState();muzzleFlash(from,cfg);casingFX();impactFX(aim,cfg.tracer);if ammo[currentWeapon]<=0 then startReload()end;attackRemote:FireServer(t,currentWeapon)
end

-- Returns only ground that looks like a sensible place for a person to stand/walk.
local function walkableGround(pos,rootY)
 moveRayParams.FilterDescendantsInstances={player.Character,enemies,camera}
 local hit=workspace:Raycast(pos+Vector3.new(0,18,0),Vector3.new(0,-38,0),moveRayParams);if not hit or not hit.Instance or not hit.Instance:IsA("BasePart") or not hit.Instance.CanCollide or hit.Normal.Y<.78 then return nil,-100 end
 local p=hit.Instance;local n=string.lower(p.Name);local dy=math.abs(hit.Position.Y-(rootY-3));if dy>4 then return nil,-100 end
 local score=2
 if n:find("road")or n:find("street")or n:find("asphalt")or n:find("pavement")then score+=35 end
 if n:find("sidewalk")or n:find("walkway")then score+=24 end
 if n:find("ground")or n:find("floor")then score+=6 end
 if p.Material==Enum.Material.Asphalt then score+=32 elseif p.Material==Enum.Material.Concrete then score+=14 elseif p.Material==Enum.Material.Cobblestone then score+=12 end
 if n:find("roof")or n:find("crate")or n:find("box")or n:find("car")or n:find("truck")or n:find("bus")or n:find("bench")or n:find("table")or n:find("container")or n:find("dumpster")then return nil,-100 end
 return hit.Position,score
end

local function pathPossible(root,goal)
 local path=PathfindingService:CreatePath({AgentRadius=3,AgentHeight=5.5,AgentCanJump=true,AgentCanClimb=false,WaypointSpacing=5})
 local ok=pcall(function()path:ComputeAsync(root.Position,goal)end);if not ok or path.Status~=Enum.PathStatus.Success then return nil end;local w=path:GetWaypoints();if#w<2 then return nil end;return w
end

-- Idle roaming now chooses destinations that are BOTH good surfaces and actually reachable.
local function chooseRoam(root)
 local candidates={};local forward=idleHeading or Vector3.new(root.CFrame.LookVector.X,0,root.CFrame.LookVector.Z)
 if forward.Magnitude<.1 then forward=Vector3.new(0,0,-1)else forward=forward.Unit end
 for _=1,46 do
  local angle=rng:NextNumber(-math.pi*.72,math.pi*.72);local dir=(CFrame.Angles(0,angle,0):VectorToWorldSpace(forward)).Unit;local rad=rng:NextNumber(20,58)
  local ground,score=walkableGround(root.Position+dir*rad,root.Position.Y)
  if ground then score+=math.max(0,forward:Dot(dir))*8;table.insert(candidates,{p=ground,s=score})end
 end
 table.sort(candidates,function(a,b)return a.s>b.s end)
 for i=1,math.min(12,#candidates)do local w=pathPossible(root,candidates[i].p);if w then roamGoal=candidates[i].p;navWaypoints=w;navIndex=2;navGoal=roamGoal;forceRepath=false;nextPathCompute=os.clock()+1.2;roamExpire=os.clock()+rng:NextNumber(7,13);idleHeading=(roamGoal-root.Position).Unit;return true end end
 -- If no distant candidate works, use a short reachable escape goal instead of freezing.
 for _,dist in ipairs({12,8,5})do for _,ang in ipairs({0,45,-45,90,-90,135,-135,180})do local dir=(CFrame.Angles(0,math.rad(ang),0):VectorToWorldSpace(forward)).Unit;local g=walkableGround(root.Position+dir*dist,root.Position.Y);if g then local w=pathPossible(root,g);if w then roamGoal=g;navWaypoints=w;navIndex=2;navGoal=g;roamExpire=os.clock()+4;idleHeading=dir;return true end end end end
 roamGoal=nil;navWaypoints={};navGoal=nil;return false
end

local function computePath(root,goal)
 if not goal then return false end;local w=pathPossible(root,goal);if not w then navWaypoints={};navIndex=1;navGoal=goal;nextPathCompute=os.clock()+.35;return false end
 navWaypoints=w;navIndex=2;navGoal=goal;nextPathCompute=os.clock()+1;forceRepath=false;return true
end
local function wallAhead(root,dir)
 if dir.Magnitude<.05 then return false end;moveRayParams.FilterDescendantsInstances={player.Character,enemies,camera};local origin=root.Position+Vector3.new(0,1.6,0);local right=Vector3.new(-dir.Z,0,dir.X)
 for _,off in ipairs({0,-1.45,1.45})do local hit=workspace:Raycast(origin+right*off,dir.Unit*5.5,moveRayParams);if hit and hit.Instance and hit.Instance.CanCollide and hit.Normal.Y<.55 then return true end end;return false
end
local function navigationDirection(root,goal)
 if not goal then return Vector3.zero end;if not navGoal or(navGoal-goal).Magnitude>7 or forceRepath or os.clock()>=nextPathCompute then computePath(root,goal)end;if#navWaypoints==0 then return Vector3.zero end
 while navIndex<=#navWaypoints do local wp=navWaypoints[navIndex];local flat=Vector3.new(wp.Position.X-root.Position.X,0,wp.Position.Z-root.Position.Z);if flat.Magnitude<3 then navIndex+=1 else if wp.Action==Enum.PathWaypointAction.Jump then local h=root.Parent and root.Parent:FindFirstChildOfClass("Humanoid");if h then h.Jump=true end end;local dir=flat.Unit;if wallAhead(root,dir)then forceRepath=true;return Vector3.zero end;return dir end end;forceRepath=true;return Vector3.zero
end
local function combatGoal(root,target)
 local er=target and target:FindFirstChild("HumanoidRootPart");if not er then return nil end;local away=Vector3.new(root.Position.X-er.Position.X,0,root.Position.Z-er.Position.Z);if away.Magnitude<.1 then away=Vector3.new(1,0,0)end;local gap=(giftGun()=="Sword")and 6.5 or 24;local desired=er.Position+away.Unit*gap;local g=walkableGround(desired,root.Position.Y);return g or desired
end

player.CameraMode=Enum.CameraMode.LockFirstPerson;publishWeaponState()
RunService.RenderStepped:Connect(function(dt)
 local char,hum,root,head=getCharacter();if not char then return end;local paused=player:GetAttribute("AutoMovePaused")==true;local target,dist,visible=nearest(root);local desired=Vector3.zero;local wanted=giftGun()
 if paused then hum:Move(Vector3.zero,false) else
  if os.clock()>nextHumanPause then nextHumanPause=os.clock()+rng:NextNumber(8,15);if rng:NextNumber()<.18 then humanPauseUntil=os.clock()+rng:NextNumber(.15,.35)end end
  local goal
  if target and alive(target)then goal=combatGoal(root,target);hum.WalkSpeed=(giftGun()=="Sword")and 18 or 17
  else
   -- No enemies: always keep exploring. If a path fails or finishes, immediately find another reachable road/sidewalk goal.
   if not roamGoal or os.clock()>roamExpire or(root.Position-roamGoal).Magnitude<4 or#navWaypoints==0 then chooseRoam(root)end
   goal=roamGoal;hum.WalkSpeed=14.5
  end
  if os.clock()>=humanPauseUntil then desired=navigationDirection(root,goal)end
  -- Idle fallback: if pathfinding has no direction for a moment, probe nearby open directions instead of standing still.
  if not target and desired.Magnitude<.05 then
   moveRayParams.FilterDescendantsInstances={player.Character,enemies,camera};local base=idleHeading or Vector3.new(root.CFrame.LookVector.X,0,root.CFrame.LookVector.Z);if base.Magnitude<.1 then base=Vector3.new(0,0,-1)else base=base.Unit end
   for _,ang in ipairs({0,25,-25,50,-50,80,-80,120,-120,180})do local dir=(CFrame.Angles(0,math.rad(ang),0):VectorToWorldSpace(base)).Unit;if not wallAhead(root,dir)then local g=walkableGround(root.Position+dir*7,root.Position.Y);if g then desired=dir;idleHeading=dir;break end end end
  end
  hum:Move(desired,false)
  if desired.Magnitude>.1 then if lastRootPos then local moved=(Vector3.new(root.Position.X,0,root.Position.Z)-Vector3.new(lastRootPos.X,0,lastRootPos.Z)).Magnitude;if moved<.03 then stuckSince=stuckSince or os.clock()else stuckSince=nil end;if stuckSince and os.clock()-stuckSince>.5 then forceRepath=true;roamGoal=nil;stuckSince=nil;hum:Move(Vector3.zero,false)end end;lastRootPos=root.Position else stuckSince=nil;lastRootPos=root.Position end
 end
 if wanted~=currentWeapon then currentWeapon=wanted;reloading=false;publishWeaponState()end;if target and visible then shoot(target)end
 if not paused then local look=target and visible and point(target)or(root.Position+(desired.Magnitude>.1 and desired or root.CFrame.LookVector)*30+Vector3.new(0,1.4,0));if look then local cp=head.Position+Vector3.new(0,.15,0);camera.CFrame=camera.CFrame:Lerp(CFrame.lookAt(cp,look),math.clamp(dt*3.1,0,1));if desired.Magnitude>.08 then root.CFrame=root.CFrame:Lerp(CFrame.lookAt(root.Position,root.Position+desired),math.clamp(dt*4.5,0,1))end end end
 if shownWeapon~=currentWeapon then makeWeapon(currentWeapon)end;recoil*=math.max(0,1-dt*11);bobClock+=dt*(hum.MoveDirection.Magnitude>.1 and 7 or 2)
 if viewModel and weaponRoot then local cfg=Weapons[currentWeapon]or Weapons.Sword;local ma=hum.MoveDirection.Magnitude>.1 and 1 or .18;local bob=CFrame.new(math.sin(bobClock)*.010*ma,math.abs(math.cos(bobClock*2))*.007*ma,0)*CFrame.Angles(math.rad(math.cos(bobClock)*.12*ma),0,math.rad(math.sin(bobClock)*.30*ma));local rc=CFrame.new(0,0,recoil*1.9)*CFrame.Angles(math.rad(-recoil*58),math.rad(recoil*8),0);viewModel:PivotTo(camera.CFrame*cfg.offset*bob*rc)end
end)
player.CharacterAdded:Connect(function()task.wait(.4);clearVM();roamGoal=nil;navWaypoints={};navGoal=nil;forceRepath=true;lastRootPos=nil;stuckSince=nil;idleHeading=nil;reloading=false;currentWeapon="Sword";publishWeaponState()end)
print("PLAYER AI V3.7 READY - reliable idle roaming + reachable road goals + building avoidance")