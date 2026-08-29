-- CityCinematicV7.server.lua
-- Add-on layer for the existing Neon Quarantine city.

local Lighting=game:GetService("Lighting")
local RunService=game:GetService("RunService")
local Debris=game:GetService("Debris")

local old=workspace:FindFirstChild("CityCinematicV7")
if old then old:Destroy() end
local world=Instance.new("Folder");world.Name="CityCinematicV7";world.Parent=workspace

local function part(name,size,cf,color,material,collide)
	local p=Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material or Enum.Material.Metal;p.Anchored=true;p.CanCollide=collide==true;p.CanTouch=false;p.CanQuery=collide==true;p.Parent=world;return p
end

local function lightPart(pos,color,range,brightness)
	local p=part("LightAnchor",Vector3.new(.2,.2,.2),CFrame.new(pos),color,Enum.Material.Neon,false);p.Transparency=1
	local l=Instance.new("PointLight");l.Color=color;l.Range=range;l.Brightness=brightness;l.Shadows=false;l.Parent=p
	return p,l
end

-- Rooftop emergency beacons
for _,pos in ipairs({Vector3.new(-120,38,-120),Vector3.new(120,42,-120),Vector3.new(-120,40,120),Vector3.new(120,44,120),Vector3.new(0,48,-170),Vector3.new(0,46,170)}) do
	local mast=part("EmergencyMast",Vector3.new(.45,7,.45),CFrame.new(pos),Color3.fromRGB(38,42,48),Enum.Material.Metal,false)
	local beacon=part("EmergencyBeacon",Vector3.new(1.1,.7,1.1),CFrame.new(pos+Vector3.new(0,3.8,0)),Color3.fromRGB(255,45,60),Enum.Material.Neon,false)
	local l=Instance.new("PointLight");l.Color=beacon.Color;l.Range=32;l.Brightness=2.5;l.Parent=beacon
	task.spawn(function()
		while beacon.Parent do
			beacon.Transparency=.05;l.Enabled=true;task.wait(.28);beacon.Transparency=.72;l.Enabled=false;task.wait(.52)
		end
	end)
end

-- Police / quarantine flash clusters
for _,pos in ipairs({Vector3.new(42,3,-11),Vector3.new(-52,3,13),Vector3.new(96,3,27),Vector3.new(-104,3,-34)}) do
	local blue,bl=lightPart(pos+Vector3.new(-1.2,0,0),Color3.fromRGB(45,120,255),24,2.3)
	local red,rl=lightPart(pos+Vector3.new(1.2,0,0),Color3.fromRGB(255,45,65),24,2.3)
	blue.Transparency=.15;red.Transparency=.15
	task.spawn(function()
		while blue.Parent and red.Parent do
			bl.Enabled=true;rl.Enabled=false;task.wait(.11);bl.Enabled=false;rl.Enabled=true;task.wait(.11)
		end
	end)
end

-- Steam vents and sewer atmosphere
for _,pos in ipairs({Vector3.new(18,.3,24),Vector3.new(-26,.3,36),Vector3.new(78,.3,-40),Vector3.new(-76,.3,-66),Vector3.new(12,.3,108),Vector3.new(118,.3,86)}) do
	local vent=part("SteamVent",Vector3.new(2.2,.15,2.2),CFrame.new(pos),Color3.fromRGB(36,38,42),Enum.Material.Metal,false)
	local smoke=Instance.new("ParticleEmitter");smoke.Texture="rbxasset://textures/particles/smoke_main.dds";smoke.Rate=5;smoke.Lifetime=NumberRange.new(1.5,3);smoke.Speed=NumberRange.new(1.8,4.5);smoke.Acceleration=Vector3.new(0,1.4,0);smoke.SpreadAngle=Vector2.new(14,14);smoke.Color=ColorSequence.new(Color3.fromRGB(120,130,145),Color3.fromRGB(65,70,82));smoke.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.45),NumberSequenceKeypoint.new(1,1)});smoke.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,1.2),NumberSequenceKeypoint.new(1,4.5)});smoke.Parent=vent
end

-- Animated searchlights sweeping the sky/streets
local searchAnchors={Vector3.new(-175,26,-175),Vector3.new(175,28,-175),Vector3.new(-175,25,175),Vector3.new(175,30,175)}
for i,pos in ipairs(searchAnchors) do
	local base=part("SearchlightTower",Vector3.new(2,20,2),CFrame.new(pos),Color3.fromRGB(38,42,49),Enum.Material.Metal,true)
	local lamp=part("SearchlightLamp",Vector3.new(2.2,1.2,2.2),CFrame.new(pos+Vector3.new(0,10.7,0)),Color3.fromRGB(215,230,255),Enum.Material.Neon,false)
	local beam=Instance.new("SpotLight");beam.Angle=26;beam.Brightness=4;beam.Range=120;beam.Color=Color3.fromRGB(205,220,255);beam.Shadows=false;beam.Face=Enum.NormalId.Front;beam.Parent=lamp
	task.spawn(function()
		local t=i*1.7
		while lamp.Parent do
			t+=.025
			local yaw=math.sin(t*.72)*1.15 + (i-1)*1.55
			local pitch=math.rad(-18+math.sin(t*.43)*6)
			lamp.CFrame=CFrame.new(pos+Vector3.new(0,10.7,0))*CFrame.Angles(pitch,yaw,0)
			task.wait(.03)
		end
	end)
end

-- Hanging warning banners / signs
local function banner(text,pos,rot,color)
	local board=part("WarningSign",Vector3.new(14,3,.35),CFrame.new(pos)*CFrame.Angles(0,math.rad(rot),0),Color3.fromRGB(14,16,21),Enum.Material.Metal,false)
	local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Front;gui.LightInfluence=0;gui.Parent=board
	local label=Instance.new("TextLabel");label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1;label.Font=Enum.Font.GothamBlack;label.TextScaled=true;label.TextStrokeTransparency=.25;label.TextColor3=color;label.Text=text;label.Parent=gui
	local glow=Instance.new("PointLight");glow.Color=color;glow.Range=18;glow.Brightness=1.4;glow.Parent=board
end
banner("EVACUATION FAILED",Vector3.new(55,9,-52),35,Color3.fromRGB(255,70,75))
banner("INFECTED DISTRICT",Vector3.new(-58,11,54),-40,Color3.fromRGB(255,170,55))
banner("VIEWERS CONTROL THIS CITY",Vector3.new(0,24,88),180,Color3.fromRGB(75,220,255))
banner("NO WAY OUT",Vector3.new(0,18,-92),0,Color3.fromRGB(255,55,130))

-- Light rain that reads well on stream without tanking performance.
local rainAnchor=part("RainAnchor",Vector3.new(1,1,1),CFrame.new(0,65,0),Color3.new(1,1,1),Enum.Material.SmoothPlastic,false);rainAnchor.Transparency=1
local rain=Instance.new("ParticleEmitter");rain.Rate=420;rain.Lifetime=NumberRange.new(1.1,1.45);rain.Speed=NumberRange.new(62,76);rain.Acceleration=Vector3.new(0,-25,0);rain.SpreadAngle=Vector2.new(8,8);rain.Size=NumberSequence.new(.035);rain.Transparency=NumberSequence.new(.38);rain.Color=ColorSequence.new(Color3.fromRGB(175,205,235));rain.EmissionDirection=Enum.NormalId.Bottom;rain.Shape=Enum.ParticleEmitterShape.Box;rain.ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume;rain.ShapeInOut=Enum.ParticleEmitterShapeInOut.Outward;rain.ShapePartial=1;rain.Parent=rainAnchor

-- Extra cinematic post-processing, kept bright enough for TikTok.
local dof=Lighting:FindFirstChild("V7Depth") or Instance.new("DepthOfFieldEffect");dof.Name="V7Depth";dof.FarIntensity=.08;dof.FocusDistance=45;dof.InFocusRadius=28;dof.NearIntensity=.02;dof.Parent=Lighting

print("CITY CINEMATIC V7 READY - rain, searchlights, emergency beacons, steam, and warning signage enabled.")