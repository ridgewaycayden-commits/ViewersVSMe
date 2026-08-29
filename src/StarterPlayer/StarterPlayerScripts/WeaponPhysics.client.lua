-- WeaponPhysics.client.lua
-- VIEWERS VS ME - WEAPON PHYSICS V1
-- Physical shell/casing ejection + shot sparks + extra camera/viewmodel kick.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Debris=game:GetService("Debris")

local player=Players.LocalPlayer
local camera=workspace.CurrentCamera
local model=nil
local muzzle=nil
local lastVisible=false
local weapon="Rifle"
local lastShotAt=0

local function detect(m)
	if m:FindFirstChild("Blade") then return "Sword" end
	if m:FindFirstChild("Barrel6") then return "Minigun" end
	if m:FindFirstChild("Pump") then return "Shotgun" end
	if m:FindFirstChild("Slide") then return "Pistol" end
	if m:FindFirstChild("SideGlow") then return "SMG" end
	return "Rifle"
end

local function casingColor(w)
	if w=="Shotgun" then return Color3.fromRGB(175,25,28) end
	return Color3.fromRGB(205,155,55)
end

local function ejectCasing()
	if not model or not model.PrimaryPart or weapon=="Sword" then return end
	local root=model.PrimaryPart
	local shell=Instance.new("Part")
	shell.Name="EjectedCasing"
	shell.Size=(weapon=="Shotgun") and Vector3.new(.16,.16,.52) or Vector3.new(.10,.10,.30)
	shell.Color=casingColor(weapon)
	shell.Material=Enum.Material.Metal
	shell.CanCollide=true
	shell.CanTouch=false
	shell.CanQuery=false
	shell.Massless=false
	shell.CFrame=root.CFrame*CFrame.new(.48,.10,-.50)*CFrame.Angles(math.rad(90),0,0)
	shell.Parent=workspace
	local side=camera.CFrame.RightVector
	local up=camera.CFrame.UpVector
	local back=-camera.CFrame.LookVector
	local speed=(weapon=="Shotgun") and 11 or 8
	shell.AssemblyLinearVelocity=side*speed+up*6+back*2+Vector3.new(math.random(-2,2),0,math.random(-2,2))
	shell.AssemblyAngularVelocity=Vector3.new(math.random(-12,12),math.random(-18,18),math.random(-12,12))
	Debris:AddItem(shell,2.5)
end

local function muzzleSparks()
	if not muzzle then return end
	for i=1,3 do
		local s=Instance.new("Part")
		s.Name="MuzzleSpark"
		s.Size=Vector3.new(.025,.025,math.random(12,26)/100)
		s.Material=Enum.Material.Neon
		s.Color=muzzle.Color
		s.Anchored=false
		s.CanCollide=false
		s.CanTouch=false
		s.CanQuery=false
		s.CFrame=muzzle.CFrame*CFrame.Angles(math.rad(math.random(-10,10)),math.rad(math.random(-10,10)),0)
		s.Parent=workspace
		s.AssemblyLinearVelocity=camera.CFrame.LookVector*math.random(18,28)+Vector3.new(math.random(-5,5),math.random(-2,5),math.random(-5,5))
		Debris:AddItem(s,.12)
	end
end

local function shotFX()
	local now=os.clock()
	if now-lastShotAt<.025 then return end
	lastShotAt=now
	if weapon~="Minigun" or math.random()<.35 then ejectCasing() end
	muzzleSparks()
	local blur=Instance.new("BlurEffect")
	blur.Size=(weapon=="Shotgun") and 4 or 2
	blur.Parent=game:GetService("Lighting")
	Debris:AddItem(blur,.06)
end

local function hook(m)
	model=m
	weapon=detect(m)
	muzzle=m:FindFirstChild("Muzzle")
	lastVisible=muzzle and muzzle.Transparency<.5 or false
end

camera.ChildAdded:Connect(function(c)
	if c.Name=="FPSViewModel" then task.defer(function() task.wait();if c.Parent==camera then hook(c) end end) end
end)

for _,c in ipairs(camera:GetChildren()) do if c.Name=="FPSViewModel" then hook(c) end end

RunService.RenderStepped:Connect(function()
	if model and model.Parent~=camera then model=nil;muzzle=nil end
	if model and (not muzzle or not muzzle.Parent) then muzzle=model:FindFirstChild("Muzzle");weapon=detect(model) end
	if muzzle then
		local visible=muzzle.Transparency<.5
		if visible and not lastVisible then shotFX() end
		lastVisible=visible
	end
end)

print("WEAPON PHYSICS V1 READY - casings, shell ejection and shot sparks enabled.")