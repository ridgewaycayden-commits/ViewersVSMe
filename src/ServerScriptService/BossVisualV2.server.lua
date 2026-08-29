-- BossVisualV2.server.lua
-- VIEWERS VS ME - TITAN BOSS VISUAL V2
-- Extra visual layer inspired by the hulking red/black armored reference.

local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local Debris=game:GetService("Debris")

local enemies=workspace:WaitForChild("TikTokEnemies")
local RED=Color3.fromRGB(255,28,38)
local HOT=Color3.fromRGB(255,75,55)
local BLACK=Color3.fromRGB(8,10,14)
local ARMOR=Color3.fromRGB(24,27,33)
local STEEL=Color3.fromRGB(58,64,74)

local animated={}

local function weld(model,target,name,size,offset,color,material)
	if not target then return end
	local p=Instance.new("Part")
	p.Name=name;p.Size=size;p.Color=color;p.Material=material or Enum.Material.Metal
	p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Massless=true
	p.CFrame=target.CFrame*offset;p.Parent=model
	local w=Instance.new("WeldConstraint");w.Part0=target;w.Part1=p;w.Parent=p
	return p
end

local function wedge(model,target,name,size,offset,color)
	local p=Instance.new("WedgePart")
	p.Name=name;p.Size=size;p.Color=color;p.Material=Enum.Material.Metal
	p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Massless=true
	p.CFrame=target.CFrame*offset;p.Parent=model
	local w=Instance.new("WeldConstraint");w.Part0=target;w.Part1=p;w.Parent=p
	return p
end

local function upgrade(model)
	if not model:GetAttribute("Boss") or model:GetAttribute("BossVisualV2") then return end
	model:SetAttribute("BossVisualV2",true)
	local head=model:FindFirstChild("Head")
	local chest=model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	local root=model:FindFirstChild("HumanoidRootPart")
	local lua=model:FindFirstChild("LeftUpperArm") or model:FindFirstChild("Left Arm")
	local rua=model:FindFirstChild("RightUpperArm") or model:FindFirstChild("Right Arm")
	local lla=model:FindFirstChild("LeftLowerArm") or lua
	local rla=model:FindFirstChild("RightLowerArm") or rua
	if not head or not chest or not root then return end

	-- Layered chest fortress + reactor.
	weld(model,chest,"TitanChestPlate",Vector3.new(3.7,2.5,1.05),CFrame.new(0,.12,-.55),ARMOR)
	weld(model,chest,"TitanChestInner",Vector3.new(2.55,1.55,.18),CFrame.new(0,.08,-1.10),BLACK)
	local core=weld(model,chest,"TitanReactor",Vector3.new(1.05,1.05,.24),CFrame.new(0,.05,-1.27),RED,Enum.Material.Neon)
	weld(model,chest,"TitanCoreFrame",Vector3.new(1.42,1.42,.12),CFrame.new(0,.05,-1.18),STEEL)
	for _,x in ipairs({-1.34,1.34}) do
		weld(model,chest,"ChestVent",Vector3.new(.36,1.25,.20),CFrame.new(x,.04,-1.14)*CFrame.Angles(0,0,math.rad(x>0 and -18 or 18)),RED,Enum.Material.Neon)
	end

	-- Huge layered shoulders similar to the reference silhouette.
	for _,pack in ipairs({{lua,-1},{rua,1}}) do
		local arm,side=pack[1],pack[2]
		if arm then
			weld(model,arm,"TitanShoulderBase",Vector3.new(2.4,1.7,2.0),CFrame.new(side*.45,.45,0),ARMOR)
			weld(model,arm,"TitanShoulderTop",Vector3.new(2.0,.65,2.35),CFrame.new(side*.50,1.15,-.08)*CFrame.Angles(0,0,math.rad(side*-12)),BLACK)
			wedge(model,arm,"TitanShoulderBlade",Vector3.new(1.25,1.25,1.65),CFrame.new(side*1.25,.95,.10)*CFrame.Angles(0,math.rad(side*90),math.rad(side*-15)),RED)
			weld(model,arm,"TitanShoulderGlow",Vector3.new(1.55,.12,.18),CFrame.new(side*.58,.70,-1.08),RED,Enum.Material.Neon)
		end
	end

	-- Oversized forearm armor/gauntlets.
	for _,pack in ipairs({{lla,-1},{rla,1}}) do
		local arm,side=pack[1],pack[2]
		if arm then
			weld(model,arm,"TitanGauntlet",Vector3.new(1.55,1.8,1.65),CFrame.new(0,-.20,0),ARMOR)
			for i=-1,1 do weld(model,arm,"GauntletClaw",Vector3.new(.20,.36,.90),CFrame.new(i*.42,-1.00,-.48),RED,Enum.Material.Neon) end
		end
	end

	-- Mask, jaw and crown spikes.
	weld(model,head,"TitanMask",Vector3.new(1.55,1.45,.42),CFrame.new(0,.02,-.67),Color3.fromRGB(125,10,15),Enum.Material.Metal)
	weld(model,head,"MaskCenter",Vector3.new(.62,.78,.12),CFrame.new(0,.08,-.92),RED,Enum.Material.Neon)
	for _,x in ipairs({-.30,.30}) do weld(model,head,"MaskEye",Vector3.new(.22,.18,.08),CFrame.new(x,.25,-.94),Color3.fromRGB(255,145,130),Enum.Material.Neon) end
	weld(model,head,"Jaw",Vector3.new(1.10,.42,.24),CFrame.new(0,-.55,-.82),BLACK)
	for i=-2,2 do
		wedge(model,head,"Tooth",Vector3.new(.14,.26,.16),CFrame.new(i*.18,-.55,-.98)*CFrame.Angles(math.rad(180),0,0),Color3.fromRGB(255,210,190))
	end
	for _,x in ipairs({-0.52,0.52}) do wedge(model,head,"Horn",Vector3.new(.46,1.25,.55),CFrame.new(x,.88,.02)*CFrame.Angles(0,0,math.rad(x>0 and -18 or 18)),BLACK) end

	-- Back reactor towers / spikes.
	for i=-2,2 do
		local h=1.7+math.abs(i)*.35
		wedge(model,chest,"BackSpike",Vector3.new(.52,h,.70),CFrame.new(i*.58,.75,.82)*CFrame.Angles(math.rad(-15),0,0),i%2==0 and RED or BLACK)
	end

	-- Dynamic red energy shards orbiting the upper body.
	local shards={}
	for i=1,6 do
		local s=Instance.new("Part")
		s.Name="TitanEnergyShard";s.Size=Vector3.new(.22,.65,.22);s.Color=RED;s.Material=Enum.Material.Neon
		s.Anchored=true;s.CanCollide=false;s.CanTouch=false;s.CanQuery=false;s.Parent=model
		table.insert(shards,s)
	end
	animated[model]={root=root,core=core,shards=shards,phase=math.random()*10}

	local light=Instance.new("PointLight")
	light.Name="TitanCoreLight";light.Color=RED;light.Brightness=5;light.Range=22;light.Shadows=true;light.Parent=core or chest

	-- Spawn pulse.
	local h=Instance.new("Highlight")
	h.FillColor=RED;h.OutlineColor=Color3.new(1,1,1);h.FillTransparency=.35;h.OutlineTransparency=.25;h.Parent=model
	TweenService:Create(h,TweenInfo.new(.8),{FillTransparency=1,OutlineTransparency=1}):Play();Debris:AddItem(h,.9)
end

for _,m in ipairs(enemies:GetChildren()) do task.defer(upgrade,m) end
enemies.ChildAdded:Connect(function(m) task.wait(.2);upgrade(m) end)

RunService.Heartbeat:Connect(function()
	local t=os.clock()
	for model,data in pairs(animated) do
		if not model.Parent or not data.root.Parent then animated[model]=nil
		else
			if data.core and data.core.Parent then
				local pulse=.92+math.sin(t*4+data.phase)*.10
				data.core.Size=Vector3.new(1.05,1.05,.24)*pulse
			end
			for i,s in ipairs(data.shards) do
				if s.Parent then
					local a=t*1.5+(i/#data.shards)*math.pi*2+data.phase
					local radius=3.1+math.sin(t*2+i)*.25
					local y=2.2+math.sin(a*1.7)*.55
					s.CFrame=data.root.CFrame*CFrame.new(math.cos(a)*radius,y,math.sin(a)*radius)*CFrame.Angles(a*1.7,a*.7,a*1.3)
				end
			end
		end
	end
end)

print("TITAN BOSS VISUAL V2 READY - layered armor, reactor, mask, gauntlets and orbiting energy shards.")