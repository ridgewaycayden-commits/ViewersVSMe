-- Nuketown2025.server.lua
-- VIEWERS VS ME - compact retro-futuristic Nuketown 2025 recreation.
-- Rebuilt from public visual/layout references; no ripped Call of Duty assets.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local ROOT_NAME = "Nuketown2025"

local function part(parent,name,size,cf,color,material,collide)
    local p=Instance.new("Part")
    p.Name=name
    p.Size=size
    p.CFrame=cf
    p.Color=color
    p.Material=material or Enum.Material.SmoothPlastic
    p.Anchored=true
    p.CanCollide=collide~=false
    p.CanTouch=false
    p.CanQuery=collide~=false
    p.CastShadow=true
    p.Parent=parent
    return p
end

local function textFace(p,text,color,face)
    local gui=Instance.new("SurfaceGui")
    gui.Face=face or Enum.NormalId.Front
    gui.LightInfluence=0
    gui.PixelsPerStud=45
    gui.Parent=p
    local t=Instance.new("TextLabel")
    t.Size=UDim2.fromScale(1,1)
    t.BackgroundTransparency=1
    t.Text=text
    t.TextColor3=color
    t.TextStrokeTransparency=.35
    t.Font=Enum.Font.GothamBlack
    t.TextScaled=true
    t.Parent=gui
end

local function model(parent,name)
    local m=Instance.new("Model")
    m.Name=name
    m.Parent=parent
    return m
end

local function hideLegacy()
    for _,name in ipairs({"RealMidtown","ManhattanMidtownV10","NeonQuarantineV6","CityCinematicV7","CityProductionV8"}) do
        local o=workspace:FindFirstChild(name)
        if o then o:Destroy() end
    end
    local oldCity=workspace:FindFirstChild("TikTokAFKCity") or workspace:FindFirstChild("TikTokCity")
    if oldCity then
        for _,o in ipairs(oldCity:GetDescendants()) do
            if o:IsA("BasePart") then
                o.Transparency=1
                o.CanCollide=false
                o.CanTouch=false
                o.CanQuery=false
            elseif o:IsA("Decal") or o:IsA("Texture") then
                o.Transparency=1
            elseif o:IsA("PointLight") or o:IsA("SpotLight") or o:IsA("SurfaceLight") then
                o.Enabled=false
            end
        end
    end
end

hideLegacy()
local prior=workspace:FindFirstChild(ROOT_NAME)
if prior then prior:Destroy() end

local root=Instance.new("Folder")
root.Name=ROOT_NAME
root.Parent=workspace

-- Bright retro-future daylight like BO2 Nuketown 2025.
Lighting.ClockTime=14.1
Lighting.Brightness=3
Lighting.ExposureCompensation=.15
Lighting.Ambient=Color3.fromRGB(135,140,150)
Lighting.OutdoorAmbient=Color3.fromRGB(170,175,185)
Lighting.GlobalShadows=true
Lighting.ShadowSoftness=.28
local atm=Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere",Lighting)
atm.Density=.12
atm.Haze=.45
atm.Glare=.08
atm.Color=Color3.fromRGB(215,225,240)
atm.Decay=Color3.fromRGB(160,175,195)
local bloom=Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect",Lighting)
bloom.Intensity=.35
bloom.Size=24
bloom.Threshold=1.4
local cc=Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect",Lighting)
cc.Brightness=.03
cc.Contrast=.08
cc.Saturation=.15
cc.TintColor=Color3.fromRGB(255,248,236)

-- Play space / perimeter.
part(root,"Ground",Vector3.new(360,1,300),CFrame.new(0,-.5,0),Color3.fromRGB(100,155,78),Enum.Material.Grass,true)
part(root,"Street",Vector3.new(92,.35,260),CFrame.new(0,.18,0),Color3.fromRGB(48,49,52),Enum.Material.Asphalt,true)
part(root,"CenterCircle",Vector3.new(118,.4,118),CFrame.new(0,.22,0),Color3.fromRGB(50,51,54),Enum.Material.Asphalt,true).Shape=Enum.PartType.Cylinder
root.CenterCircle.Orientation=Vector3.new(0,0,90)

-- sidewalks
for _,x in ipairs({-54,54}) do
    part(root,"Sidewalk",Vector3.new(14,.55,260),CFrame.new(x,.28,0),Color3.fromRGB(198,196,184),Enum.Material.Concrete,true)
end
for _,z in ipairs({-118,118}) do
    part(root,"BackWalk",Vector3.new(118,.5,12),CFrame.new(0,.25,z),Color3.fromRGB(198,196,184),Enum.Material.Concrete,true)
end

-- perimeter fencing.
local function fenceSegment(pos,size)
    local f=part(root,"Fence",size,CFrame.new(pos),Color3.fromRGB(105,112,112),Enum.Material.Metal,true)
    f.Transparency=.15
end
for x=-170,170,20 do
    fenceSegment(Vector3.new(x,4,-145),Vector3.new(18,8,.4))
    fenceSegment(Vector3.new(x,4,145),Vector3.new(18,8,.4))
end
for z=-135,135,20 do
    fenceSegment(Vector3.new(-176,4,z),Vector3.new(.4,8,18))
    fenceSegment(Vector3.new(176,4,z),Vector3.new(.4,8,18))
end

local function house(name,side,color,accent)
    local m=model(root,name)
    local x=side*104
    local cf=CFrame.new(x,0,0)

    -- Main two-story mid-century house and garage.
    part(m,"Main",Vector3.new(58,22,54),cf*CFrame.new(0,11,4),color,Enum.Material.SmoothPlastic,true)
    part(m,"Upper",Vector3.new(50,18,42),cf*CFrame.new(0,31,1),color:Lerp(Color3.new(1,1,1),.09),Enum.Material.SmoothPlastic,true)
    part(m,"Garage",Vector3.new(34,16,34),cf*CFrame.new(-side*39,8,13),Color3.fromRGB(214,213,200),Enum.Material.SmoothPlastic,true)
    local door=part(m,"GarageDoor",Vector3.new(.5,11,24),cf*CFrame.new(-side*56,7,13),Color3.fromRGB(188,195,194),Enum.Material.Metal,false)
    if side==-1 then door.Size=Vector3.new(.5,11,24) end

    -- large front glass / retro accent panels.
    local glassX=-side*29.1
    local glass=part(m,"FrontGlass",Vector3.new(.35,12,27),cf*CFrame.new(glassX,29,-7),Color3.fromRGB(88,158,175),Enum.Material.Glass,false)
    glass.Transparency=.23
    local stripe=part(m,"Accent",Vector3.new(.5,17,12),cf*CFrame.new(glassX-(side*.05),28,12),accent,Enum.Material.SmoothPlastic,false)
    stripe.CastShadow=false

    -- roof slabs + solar panels.
    part(m,"Roof",Vector3.new(64,1.8,60),cf*CFrame.new(0,43,3),Color3.fromRGB(61,64,66),Enum.Material.Slate,true)
    for zz=-12,18,15 do
        local panel=part(m,"SolarPanel",Vector3.new(22,.35,10),cf*CFrame.new(-8,44,zz),Color3.fromRGB(45,67,76),Enum.Material.Glass,false)
        panel.Transparency=.08
    end

    -- backyard and patio.
    local yardZ=88
    part(m,"BackPatio",Vector3.new(76,.35,34),cf*CFrame.new(0,.2,yardZ),Color3.fromRGB(195,184,165),Enum.Material.Concrete,true)
    part(m,"Hedge",Vector3.new(68,5,4),cf*CFrame.new(0,2.5,127),Color3.fromRGB(57,112,57),Enum.Material.Grass,true)

    -- side routes around house.
    part(m,"SidePath",Vector3.new(15,.35,96),cf*CFrame.new(-side*39,.2,62),Color3.fromRGB(194,190,177),Enum.Material.Concrete,true)

    -- balcony / upper sightline.
    part(m,"Balcony",Vector3.new(18,1,22),cf*CFrame.new(-side*30,21,44),Color3.fromRGB(190,190,180),Enum.Material.Metal,true)
    part(m,"Rail",Vector3.new(.5,5,22),cf*CFrame.new(-side*39,23.5,44),Color3.fromRGB(128,137,139),Enum.Material.Metal,true)

    -- house number plates inspired by the playable houses.
    local plate=part(m,"HouseNumber",Vector3.new(.4,5,8),cf*CFrame.new(-side*29.3,13,-17),Color3.fromRGB(240,240,230),Enum.Material.SmoothPlastic,false)
    textFace(plate,side<0 and "11" or "13",Color3.fromRGB(45,45,45),side<0 and Enum.NormalId.Right or Enum.NormalId.Left)
end

house("BlueHouse",-1,Color3.fromRGB(94,181,205),Color3.fromRGB(242,146,69))
house("OrangeHouse",1,Color3.fromRGB(234,164,78),Color3.fromRGB(96,193,204))

-- Central bus / truck cover.
local function vehicle(parent,name,pos,size,color,rot)
    local m=model(parent,name)
    local cf=CFrame.new(pos)*CFrame.Angles(0,math.rad(rot or 0),0)
    part(m,"Body",size,cf*CFrame.new(0,size.Y/2,0),color,Enum.Material.Metal,true)
    part(m,"Windows",Vector3.new(size.X*.92,size.Y*.32,size.Z*.72),cf*CFrame.new(0,size.Y*.68,0),Color3.fromRGB(37,48,56),Enum.Material.Glass,false).Transparency=.18
    for sx=-1,1,2 do
        for sz=-1,1,2 do
            local w=part(m,"Wheel",Vector3.new(2.8,2.8,1.2),cf*CFrame.new(sx*(size.X/2-.4),1.4,sz*(size.Z*.31))*CFrame.Angles(0,0,math.rad(90)),Color3.fromRGB(24,24,25),Enum.Material.SmoothPlastic,true)
            w.Shape=Enum.PartType.Cylinder
        end
    end
    return m
end

vehicle(root,"RetroBus",Vector3.new(-13,0,-3),Vector3.new(15,12,54),Color3.fromRGB(226,207,142),8)
vehicle(root,"MovingTruck",Vector3.new(18,0,7),Vector3.new(16,13,46),Color3.fromRGB(79,105,118),-10)

-- classic cars near houses.
vehicle(root,"TealCar",Vector3.new(3,0,71),Vector3.new(8,4,18),Color3.fromRGB(76,194,190),0)
vehicle(root,"RedCar",Vector3.new(-86,0,-37),Vector3.new(8,4,17),Color3.fromRGB(190,58,50),90)
vehicle(root,"WhiteCar",Vector3.new(88,0,45),Vector3.new(8,4,17),Color3.fromRGB(222,218,196),90)

-- Entrance / Nuketown-style retro-future sign.
local signPost=part(root,"SignPost",Vector3.new(4,28,4),CFrame.new(0,14,-132)*CFrame.Angles(0,0,math.rad(-12)),Color3.fromRGB(85,82,76),Enum.Material.Metal,true)
local sign=part(root,"NuketownSign",Vector3.new(34,12,1.2),CFrame.new(0,25,-132)*CFrame.Angles(0,0,math.rad(-8)),Color3.fromRGB(206,67,75),Enum.Material.Metal,false)
textFace(sign,"NUKETOWN\n2025",Color3.fromRGB(255,244,215),Enum.NormalId.Front)
local atom=part(root,"AtomTop",Vector3.new(7,7,1),CFrame.new(0,35,-132),Color3.fromRGB(79,181,197),Enum.Material.Neon,false)
atom.Shape=Enum.PartType.Ball

-- Mannequins / suburban display props.
local function mannequin(pos,rot,shirt)
    local m=model(root,"Mannequin")
    local cf=CFrame.new(pos)*CFrame.Angles(0,math.rad(rot or 0),0)
    part(m,"Torso",Vector3.new(2.3,3,1.2),cf*CFrame.new(0,4.5,0),shirt,Enum.Material.SmoothPlastic,false)
    local head=part(m,"Head",Vector3.new(1.8,1.8,1.8),cf*CFrame.new(0,7,0),Color3.fromRGB(230,203,176),Enum.Material.SmoothPlastic,false);head.Shape=Enum.PartType.Ball
    part(m,"LegL",Vector3.new(.8,3,.8),cf*CFrame.new(-.6,1.5,0),Color3.fromRGB(75,80,88),Enum.Material.SmoothPlastic,false)
    part(m,"LegR",Vector3.new(.8,3,.8),cf*CFrame.new(.6,1.5,0),Color3.fromRGB(75,80,88),Enum.Material.SmoothPlastic,false)
end
for _,d in ipairs({
    {Vector3.new(-68,0,74),25,Color3.fromRGB(155,88,169)},
    {Vector3.new(72,0,-63),-35,Color3.fromRGB(86,142,184)},
    {Vector3.new(-18,0,94),180,Color3.fromRGB(223,150,81)},
    {Vector3.new(91,0,91),-90,Color3.fromRGB(137,179,91)}
}) do mannequin(d[1],d[2],d[3]) end

-- Retro streetlights.
for _,z in ipairs({-102,-60,60,102}) do
    for _,x in ipairs({-61,61}) do
        local pole=part(root,"LampPole",Vector3.new(.7,15,.7),CFrame.new(x,7.5,z),Color3.fromRGB(99,106,107),Enum.Material.Metal,true)
        local lamp=part(root,"Lamp",Vector3.new(3,.6,2),CFrame.new(x,15,z),Color3.fromRGB(255,239,193),Enum.Material.Neon,false)
        local l=Instance.new("PointLight");l.Brightness=.7;l.Range=18;l.Color=lamp.Color;l.Parent=lamp
    end
end

-- open spawn in the backyard, matching the classic Nuketown flow.
local spawn=Instance.new("SpawnLocation")
spawn.Name="NuketownSpawn"
spawn.Size=Vector3.new(16,1,16)
spawn.CFrame=CFrame.new(0,1,112)
spawn.Transparency=1
spawn.CanCollide=false
spawn.Anchored=true
spawn.Neutral=true
spawn.Duration=0
spawn.Parent=root

local function movePlayer(plr)
    local char=plr.Character
    local hrp=char and char:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.CFrame=CFrame.new(0,4,108)*CFrame.Angles(0,math.rad(180),0) end
end
Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function() task.wait(.4);movePlayer(plr) end)
end)
for _,plr in ipairs(Players:GetPlayers()) do
    if plr.Character then task.defer(movePlayer,plr) end
    plr.CharacterAdded:Connect(function() task.wait(.4);movePlayer(plr) end)
end

print("[NUKETOWN 2025] READY - retro-future two-house / cul-de-sac combat map loaded")
