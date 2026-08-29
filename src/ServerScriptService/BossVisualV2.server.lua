-- BossVisualV2.server.lua
-- VIEWERS VS ME - TITAN BOSS VISUAL V3
-- Grounded heavy armor pass. No permanent glow/orbiting shards.

local TweenService=game:GetService("TweenService")
local Debris=game:GetService("Debris")

local enemies=workspace:WaitForChild("TikTokEnemies")
local BLACK=Color3.fromRGB(9,10,12)
local CHARCOAL=Color3.fromRGB(23,25,29)
local GUNMETAL=Color3.fromRGB(48,52,58)
local STEEL=Color3.fromRGB(78,82,88)
local BLOOD=Color3.fromRGB(112,8,12)
local BONE=Color3.fromRGB(187,170,145)

local function weld(model,target,name,size,offset,color,material,shape)
	if not target then return end
	local p=Instance.new("Part")
	p.Name=name
	p.Size=size
	p.Color=color
	p.Material=material or Enum.Material.Metal
	p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Massless=true;p.CastShadow=true
	if shape then p.Shape=shape end
	p.CFrame=target.CFrame*offset
	p.Parent=model
	local w=Instance.new("WeldConstraint");w.Part0=target;w.Part1=p;w.Parent=p
	return p
end

local function wedge(model,target,name,size,offset,color,material)
	if not target then return end
	local p=Instance.new("WedgePart")
	p.Name=name;p.Size=size;p.Color=color;p.Material=material or Enum.Material.Metal
	p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Massless=true;p.CastShadow=true
	p.CFrame=target.CFrame*offset;p.Parent=model
	local w=Instance.new("WeldConstraint");w.Part0=target;w.Part1=p;w.Parent=p
	return p
end

local function upgrade(model)
	if not model:GetAttribute("Boss") or model:GetAttribute("BossVisualV3") then return end
	model:SetAttribute("BossVisualV3",true)

	local head=model:FindFirstChild("Head")
	local chest=model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	local lower=model:FindFirstChild("LowerTorso") or chest
	local root=model:FindFirstChild("HumanoidRootPart")
	local lua=model:FindFirstChild("LeftUpperArm") or model:FindFirstChild("Left Arm")
	local rua=model:FindFirstChild("RightUpperArm") or model:FindFirstChild("Right Arm")
	local lla=model:FindFirstChild("LeftLowerArm") or lua
	local rla=model:FindFirstChild("RightLowerArm") or rua
	local lul=model:FindFirstChild("LeftUpperLeg") or model:FindFirstChild("Left Leg")
	local rul=model:FindFirstChild("RightUpperLeg") or model:FindFirstChild("Right Leg")
	local lll=model:FindFirstChild("LeftLowerLeg") or lul
	local rll=model:FindFirstChild("RightLowerLeg") or rul
	if not head or not chest or not root then return end

	-- Broad armored torso with layered ribs instead of a flat glowing box.
	weld(model,chest,"V3ChestShell",Vector3.new(3.9,2.65,1.15),CFrame.new(0,.08,-.48),CHARCOAL,Enum.Material.DiamondPlate)
	weld(model,chest,"V3Sternum",Vector3.new(.58,2.08,.26),CFrame.new(0,.10,-1.12),GUNMETAL,Enum.Material.Metal)
	for _,pack in ipairs({{-1.22,-18},{-.62,-10},{.62,10},{1.22,18}}) do
		weld(model,chest,"V3RibPlate",Vector3.new(.72,1.62,.22),CFrame.new(pack[1],.04,-1.10)*CFrame.Angles(0,0,math.rad(pack[2])),GUNMETAL,Enum.Material.Metal)
	end
	weld(model,lower,"V3AbPlate",Vector3.new(2.65,1.05,.72),CFrame.new(0,-.25,-.35),BLACK,Enum.Material.DiamondPlate)

	-- Raised collar/neck protection gives the boss a tank-like silhouette.
	weld(model,chest,"V3Collar",Vector3.new(3.20,.58,1.18),CFrame.new(0,1.38,-.20),BLACK,Enum.Material.Metal)
	weld(model,chest,"V3NeckGuardL",Vector3.new(.58,1.05,.85),CFrame.new(-1.28,1.25,-.33)*CFrame.Angles(0,0,math.rad(-18)),GUNMETAL)
	weld(model,chest,"V3NeckGuardR",Vector3.new(.58,1.05,.85),CFrame.new(1.28,1.25,-.33)*CFrame.Angles(0,0,math.rad(18)),GUNMETAL)

	-- Huge sloped shoulders, but matte and believable.
	for _,pack in ipairs({{lua,-1},{rua,1}}) do
		local arm,side=pack[1],pack[2]
		if arm then
			weld(model,arm,"V3ShoulderMain",Vector3.new(2.65,1.45,2.10),CFrame.new(side*.52,.48,-.02)*CFrame.Angles(0,0,math.rad(side*11)),CHARCOAL,Enum.Material.DiamondPlate)
			weld(model,arm,"V3ShoulderCap",Vector3.new(2.20,.38,2.28),CFrame.new(side*.58,1.18,-.05)*CFrame.Angles(0,0,math.rad(side*14)),GUNMETAL)
			wedge(model,arm,"V3ShoulderSpike",Vector3.new(.72,.90,1.18),CFrame.new(side*1.38,.84,.08)*CFrame.Angles(0,math.rad(side*90),math.rad(side*-16)),STEEL)
		end
	end

	-- Oversized gauntlets with knuckle blocks / claws.
	for _,pack in ipairs({{lla,-1},{rla,1}}) do
		local arm,side=pack[1],pack[2]
		if arm then
			weld(model,arm,"V3Gauntlet",Vector3.new(1.72,1.95,1.74),CFrame.new(0,-.18,0),GUNMETAL,Enum.Material.DiamondPlate)
			weld(model,arm,"V3ForearmPlate",Vector3.new(1.28,.42,1.98),CFrame.new(0,.55,-.18),BLACK)
			for i=-1,1 do
				wedge(model,arm,"V3KnuckleClaw",Vector3.new(.20,.32,.72),CFrame.new(i*.40,-1.08,-.52)*CFrame.Angles(math.rad(180),0,0),STEEL)
			end
		end
	end

	-- Full brutal helmet: brow, cheek plates, jaw cage, horns.
	weld(model,head,"V3Helmet",Vector3.new(1.72,1.62,1.28),CFrame.new(0,.16,-.10),BLACK,Enum.Material.Metal)
	weld(model,head,"V3FacePlate",Vector3.new(1.48,1.08,.30),CFrame.new(0,.03,-.78),BLOOD,Enum.Material.DiamondPlate)
	weld(model,head,"V3Brow",Vector3.new(1.58,.28,.30),CFrame.new(0,.48,-.91)*CFrame.Angles(math.rad(-7),0,0),GUNMETAL)
	for _,x in ipairs({-.43,.43}) do
		weld(model,head,"V3Cheek",Vector3.new(.46,.78,.28),CFrame.new(x,-.10,-.91)*CFrame.Angles(0,0,math.rad(x>0 and -10 or 10)),GUNMETAL)
	end
	weld(model,head,"V3JawCage",Vector3.new(1.22,.36,.36),CFrame.new(0,-.58,-.80),BLACK)
	for i=-2,2 do
		wedge(model,head,"V3Tooth",Vector3.new(.13,.30,.16),CFrame.new(i*.19,-.62,-1.00)*CFrame.Angles(math.rad(180),0,0),BONE,Enum.Material.Slate)
	end
	for _,x in ipairs({-.56,.56}) do
		wedge(model,head,"V3Horn",Vector3.new(.48,1.32,.58),CFrame.new(x,.98,.05)*CFrame.Angles(0,0,math.rad(x>0 and -20 or 20)),BLACK)
	end

	-- Back silhouette: mechanical spine and exhaust housings, no glow.
	weld(model,chest,"V3BackPack",Vector3.new(2.35,2.05,.78),CFrame.new(0,.10,.86),BLACK,Enum.Material.DiamondPlate)
	for i=-2,2 do
		local h=1.15+math.abs(i)*.18
		wedge(model,chest,"V3BackSpike",Vector3.new(.34,h,.55),CFrame.new(i*.48,.92,.95)*CFrame.Angles(math.rad(-18),0,0),i==0 and STEEL or GUNMETAL)
	end

	-- Leg armor so the upper body doesn't look glued to skinny Roblox legs.
	for _,pack in ipairs({{lul,-1},{rul,1}}) do
		local leg,side=pack[1],pack[2]
		if leg then
			weld(model,leg,"V3Thigh",Vector3.new(1.48,2.05,1.42),CFrame.new(0,0,0),CHARCOAL,Enum.Material.DiamondPlate)
			weld(model,leg,"V3HipGuard",Vector3.new(.82,.72,1.62),CFrame.new(side*.34,.78,-.03)*CFrame.Angles(0,0,math.rad(side*10)),GUNMETAL)
		end
	end
	for _,leg in ipairs({lll,rll}) do
		if leg then
			weld(model,leg,"V3Shin",Vector3.new(1.30,1.75,1.32),CFrame.new(0,-.05,-.10),GUNMETAL,Enum.Material.DiamondPlate)
			weld(model,leg,"V3Knee",Vector3.new(1.02,.62,1.52),CFrame.new(0,.80,-.15),BLACK)
		end
	end

	-- Small permanent scars/paint instead of emissive strips.
	for _,x in ipairs({-.90,0,.90}) do
		weld(model,chest,"V3WarPaint",Vector3.new(.12,1.18,.08),CFrame.new(x,-.18,-1.28)*CFrame.Angles(0,0,math.rad(22+x*8)),BLOOD,Enum.Material.SmoothPlastic)
	end

	-- Short spawn flash only; CharacterNoGlow will remove it immediately after if needed.
	local h=Instance.new("Highlight")
	h.Name="TitanSpawnFlash";h.FillColor=Color3.fromRGB(150,12,16);h.OutlineColor=Color3.fromRGB(235,220,205)
	h.FillTransparency=.55;h.OutlineTransparency=.35;h.Parent=model
	TweenService:Create(h,TweenInfo.new(.45),{FillTransparency=1,OutlineTransparency=1}):Play()
	Debris:AddItem(h,.5)
end

for _,m in ipairs(enemies:GetChildren()) do task.defer(upgrade,m) end
enemies.ChildAdded:Connect(function(m) task.wait(.2);upgrade(m) end)

print("TITAN BOSS VISUAL V3 READY - heavier matte armor, helmet, claws, spine and leg plating.")