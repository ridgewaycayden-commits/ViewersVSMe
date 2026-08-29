-- NYCReworkV9.server.lua
-- VIEWERS VS ME - NYC / MANHATTAN ARCHITECTURE REWORK V9
-- Replaces the generic building look with a dense NYC-inspired quarantine district.
-- Keeps roads/gameplay systems, hides old tall block buildings, then builds optimized
-- brick walkups, glass towers, art-deco setbacks, storefronts, fire escapes, water tanks,
-- rooftop HVAC, subway entrances, scaffolding, alleys and skyline landmarks.

local Lighting=game:GetService("Lighting")

local prior=workspace:FindFirstChild("NYCReworkV9")
if prior then prior:Destroy() end
local world=Instance.new("Folder");world.Name="NYCReworkV9";world.Parent=workspace
local rng=Random.new(29082026)

local function part(name,size,cf,color,material,collide,parent)
 local p=Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material or Enum.Material.Concrete;p.Anchored=true;p.CanCollide=collide==true;p.CanTouch=false;p.CanQuery=collide==true;p.Parent=parent or world;return p
end
local function nocollide(p) p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;return p end
local function model(name) local m=Instance.new("Model");m.Name=name;m.Parent=world;return m end
local function neon(name,size,cf,color,parent)
 local p=part(name,size,cf,color,Enum.Material.Neon,false,parent);local l=Instance.new("PointLight");l.Color=color;l.Brightness=.55;l.Range=11;l.Shadows=false;l.Parent=p;return p
end
local function faceText(parent,text,color)
 local sg=Instance.new("SurfaceGui");sg.Face=Enum.NormalId.Front;sg.LightInfluence=0;sg.PixelsPerStud=50;sg.Parent=parent
 local t=Instance.new("TextLabel");t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1;t.Font=Enum.Font.GothamBlack;t.TextScaled=true;t.TextStrokeTransparency=.45;t.TextColor3=color;t.Text=text;t.Parent=sg
end

-- Hide old generic high-rise blocks only. Roads/plaza/props stay intact.
local oldCity=workspace:FindFirstChild("TikTokAFKCity") or workspace:FindFirstChild("TikTokCity")
if oldCity then
 for _,obj in ipairs(oldCity:GetDescendants()) do
  if obj:IsA("BasePart") and obj.Size.Y>=18 and obj.Size.X>=8 and obj.Size.Z>=8 then
   obj:SetAttribute("NYC_V9_HIDDEN",true);obj.Transparency=1;obj.CanCollide=false;obj.CanTouch=false;obj.CanQuery=false
  end
 end
end

-- Also suppress previous purely decorative roof/building overlay strips that make the new skyline noisy.
local oldV6=workspace:FindFirstChild("NeonQuarantineV6")
if oldV6 then
 for _,p in ipairs(oldV6:GetDescendants()) do
  if p:IsA("BasePart") and (p.Name=="NeonStrip" or p.Name=="Billboard") and p.Position.Y>14 then p.Transparency=1 end
 end
end

local brickColors={Color3.fromRGB(104,58,47),Color3.fromRGB(91,52,43),Color3.fromRGB(118,70,54),Color3.fromRGB(82,61,55),Color3.fromRGB(108,83,66)}
local stoneColors={Color3.fromRGB(115,112,105),Color3.fromRGB(135,128,114),Color3.fromRGB(92,96,101),Color3.fromRGB(151,143,129)}
local glassColors={Color3.fromRGB(28,43,55),Color3.fromRGB(25,37,48),Color3.fromRGB(36,50,62),Color3.fromRGB(20,31,42)}

local function windowGrid(m,baseCF,w,d,h,style)
 local rows=math.max(2,math.floor((h-8)/7))
 local colsX=math.max(2,math.floor(w/7))
 local colsZ=math.max(2,math.floor(d/7))
 local lit=Color3.fromRGB(235,210,145);local dark=Color3.fromRGB(24,30,38)
 for r=1,rows do
  local y=-h/2+5+r*7
  for c=1,colsX do
   local x=-w/2+(c-.5)*(w/colsX)
   local on=rng:NextNumber()<.22
   local mat=on and Enum.Material.Neon or Enum.Material.Glass
   local col=on and lit or dark
   local f=part("Window",Vector3.new(math.max(2.2,w/colsX-2),3.3,.12),baseCF*CFrame.new(x,y,-d/2-.07),col,mat,false,m);f.Transparency=on and .05 or .18
   local b=f:Clone();b.CFrame=baseCF*CFrame.new(-x,y,d/2+.07);b.Parent=m
  end
  for c=1,colsZ do
   local z=-d/2+(c-.5)*(d/colsZ)
   local on=rng:NextNumber()<.18
   local mat=on and Enum.Material.Neon or Enum.Material.Glass
   local col=on and lit or dark
   local l=part("Window",Vector3.new(.12,3.3,math.max(2.2,d/colsZ-2)),baseCF*CFrame.new(-w/2-.07,y,z),col,mat,false,m);l.Transparency=on and .05 or .18
   local rr=l:Clone();rr.CFrame=baseCF*CFrame.new(w/2+.07,y,-z);rr.Parent=m
  end
 end
end

local function rooftopHVAC(m,cf,w,d,h)
 for i=1,rng:NextInteger(2,4) do
  local sx=rng:NextNumber(3.5,7);local sz=rng:NextNumber(3.5,7)
  part("HVAC",Vector3.new(sx,2.2,sz),cf*CFrame.new(rng:NextNumber(-w*.28,w*.28),h/2+1.1,rng:NextNumber(-d*.28,d*.28)),Color3.fromRGB(70,73,76),Enum.Material.Metal,false,m)
 end
end

local function waterTower(m,cf,w,d,h)
 local x=rng:NextNumber(-w*.2,w*.2);local z=rng:NextNumber(-d*.2,d*.2);local y=h/2+4
 for dx=-1,1,2 do for dz=-1,1,2 do part("TankLeg",Vector3.new(.25,5,.25),cf*CFrame.new(x+dx*1.6,y-1.5,z+dz*1.6),Color3.fromRGB(61,52,44),Enum.Material.Wood,false,m) end end
 local tank=part("WaterTower",Vector3.new(5.4,5.2,5.4),cf*CFrame.new(x,y+2,z),Color3.fromRGB(94,77,60),Enum.Material.Wood,false,m);tank.Shape=Enum.PartType.Cylinder;tank.CFrame=tank.CFrame*CFrame.Angles(0,0,math.rad(90))
end

local function fireEscape(m,cf,w,d,h)
 local side=(rng:NextNumber()<.5) and -1 or 1
 for y=-h/2+10,h/2-7,9 do
  local plat=part("FireEscape",Vector3.new(5,.18,3.2),cf*CFrame.new(side*(w/2+.45),y,0),Color3.fromRGB(35,37,39),Enum.Material.Metal,false,m)
  for z=-1.2,1.2,2.4 do part("Rail",Vector3.new(.12,2.2,.12),plat.CFrame*CFrame.new(0,1,z),Color3.fromRGB(35,37,39),Enum.Material.Metal,false,m) end
  part("RailTop",Vector3.new(.12,.12,3),plat.CFrame*CFrame.new(0,2,0),Color3.fromRGB(35,37,39),Enum.Material.Metal,false,m)
 end
end

local function storefront(m,cf,w,d)
 local front=cf*CFrame.new(0,-.5,-d/2-.25)
 part("StoreGlass",Vector3.new(math.max(8,w-4),5,.3),front*CFrame.new(0,2.8,0),Color3.fromRGB(21,32,40),Enum.Material.Glass,false,m).Transparency=.18
 local awning=part("Awning",Vector3.new(math.max(8,w-3),.4,2.4),front*CFrame.new(0,5.6,-.8)*CFrame.Angles(math.rad(12),0,0),Color3.fromRGB(38,58,71),Enum.Material.Metal,false,m)
 local sign=part("StoreSign",Vector3.new(math.min(15,w-4),2,.35),front*CFrame.new(0,7.4,-.05),Color3.fromRGB(18,20,24),Enum.Material.Metal,false,m)
 local names={"DELI","BODEGA","PIZZA","PHARMACY","MARKET","24 HRS","DINER"};faceText(sign,names[rng:NextInteger(1,#names)],rng:NextNumber()<.5 and Color3.fromRGB(255,205,80) or Color3.fromRGB(90,220,255))
end

local function brickBuilding(pos,w,d,h)
 local m=model("NYC_BrickWalkup");local cf=CFrame.new(pos+Vector3.new(0,h/2,0));local col=brickColors[rng:NextInteger(1,#brickColors)]
 part("Shell",Vector3.new(w,h,d),cf,col,Enum.Material.Brick,true,m);windowGrid(m,cf,w,d,h,"brick");storefront(m,cf,w,d);fireEscape(m,cf,w,d,h);rooftopHVAC(m,cf,w,d,h)
 if h>38 and rng:NextNumber()<.7 then waterTower(m,cf,w,d,h) end
 return m
end

local function glassTower(pos,w,d,h)
 local m=model("NYC_GlassTower");local cf=CFrame.new(pos+Vector3.new(0,h/2,0));local col=glassColors[rng:NextInteger(1,#glassColors)]
 part("Core",Vector3.new(w,h,d),cf,col,Enum.Material.Glass,true,m).Transparency=.12
 for x=-w/2+3,w/2-2,5 do part("Mullion",Vector3.new(.18,h+.2,.22),cf*CFrame.new(x,0,-d/2-.12),Color3.fromRGB(53,59,65),Enum.Material.Metal,false,m) end
 for y=-h/2+5,h/2-4,6 do part("FloorBand",Vector3.new(w+.3,.18,.25),cf*CFrame.new(0,y,-d/2-.13),Color3.fromRGB(48,54,60),Enum.Material.Metal,false,m) end
 local crown=part("Crown",Vector3.new(w*.72,6,d*.72),cf*CFrame.new(0,h/2+3,0),Color3.fromRGB(45,50,58),Enum.Material.Metal,false,m)
 if rng:NextNumber()<.55 then neon("CrownLight",Vector3.new(w*.58,.25,.25),crown.CFrame*CFrame.new(0,1,-d*.37),Color3.fromRGB(160,210,255),m) end
 rooftopHVAC(m,cf,w,d,h)
 return m
end

local function artDeco(pos,w,d,h)
 local m=model("NYC_ArtDecoTower");local base=CFrame.new(pos)
 local levels={{1,w,d,h*.58},{2,w*.78,d*.78,h*.22},{3,w*.56,d*.56,h*.13},{4,w*.34,d*.34,h*.07}}
 local y=0
 for _,v in ipairs(levels) do local lh=v[4];local cf=base*CFrame.new(0,y+lh/2,0);part("Setback",Vector3.new(v[2],lh,v[3]),cf,stoneColors[rng:NextInteger(1,#stoneColors)],Enum.Material.Concrete,true,m);windowGrid(m,cf,v[2],v[3],lh,"deco");y+=lh end
 local spire=part("Spire",Vector3.new(1.2,15,1.2),base*CFrame.new(0,h+7.5,0),Color3.fromRGB(160,155,142),Enum.Material.Metal,false,m)
 neon("SpireLight",Vector3.new(.35,8,.35),spire.CFrame*CFrame.new(0,3,0),Color3.fromRGB(210,225,255),m)
 return m
end

local function scaffolding(pos,rot)
 local m=model("SidewalkScaffolding");local cf=CFrame.new(pos)*CFrame.Angles(0,math.rad(rot),0)
 for x=-10,10,5 do part("Post",Vector3.new(.25,8,.25),cf*CFrame.new(x,4,0),Color3.fromRGB(68,70,72),Enum.Material.Metal,false,m) end
 part("Roof",Vector3.new(22,.35,4),cf*CFrame.new(0,8,0),Color3.fromRGB(58,60,62),Enum.Material.Metal,false,m)
 for x=-9,9,3 do part("Brace",Vector3.new(.12,7,.12),cf*CFrame.new(x,4,0)*CFrame.Angles(0,0,math.rad(18)),Color3.fromRGB(78,80,82),Enum.Material.Metal,false,m) end
end

local function subwayEntrance(pos,rot)
 local m=model("SubwayEntrance");local cf=CFrame.new(pos)*CFrame.Angles(0,math.rad(rot),0)
 part("StairHole",Vector3.new(8,.2,13),cf*CFrame.new(0,.12,0),Color3.fromRGB(20,22,25),Enum.Material.Asphalt,false,m)
 for x=-4,4,8 do part("Rail",Vector3.new(.22,3,13),cf*CFrame.new(x,1.5,0),Color3.fromRGB(50,54,58),Enum.Material.Metal,false,m) end
 local sign=part("SubwaySign",Vector3.new(7,2,.25),cf*CFrame.new(0,3,-5.8),Color3.fromRGB(22,25,30),Enum.Material.Metal,false,m);faceText(sign,"SUBWAY  ● A C E",Color3.fromRGB(235,235,240))
end

-- Build dense Manhattan blocks between the existing 30-stud road grid.
local roads={-200,-100,0,100,200}
local blocks={-150,-50,50,150}
for _,bx in ipairs(blocks) do
 for _,bz in ipairs(blocks) do
  -- keep the central gameplay area more open
  if not (math.abs(bx)<80 and math.abs(bz)<80) then
   local landmark=(math.abs(bx)==150 and math.abs(bz)==150 and rng:NextNumber()<.45)
   if landmark then
    artDeco(Vector3.new(bx,0,bz),50,50,rng:NextInteger(95,135))
   else
    local slots={{-20,-20},{20,-20},{-20,20},{20,20}}
    for _,s in ipairs(slots) do
     local pos=Vector3.new(bx+s[1],0,bz+s[2]);local roll=rng:NextNumber()
     if roll<.55 then brickBuilding(pos,rng:NextInteger(25,32),rng:NextInteger(25,32),rng:NextInteger(32,64))
     elseif roll<.87 then glassTower(pos,rng:NextInteger(25,34),rng:NextInteger(25,34),rng:NextInteger(62,105))
     else artDeco(pos,rng:NextInteger(26,34),rng:NextInteger(26,34),rng:NextInteger(70,115)) end
    end
   end
  end
 end
end

-- Midtown skyline anchors, inspired by NYC silhouettes without copying one exact building.
artDeco(Vector3.new(155,0,-155),54,54,145)
artDeco(Vector3.new(-155,0,155),48,48,125)
glassTower(Vector3.new(-155,0,-155),55,55,132)
glassTower(Vector3.new(155,0,155),58,58,118)

-- Street-level NYC dressing.
for _,d in ipairs({{Vector3.new(-25,0,-96),0},{Vector3.new(102,0,25),90},{Vector3.new(-102,0,-25),90},{Vector3.new(25,0,103),180}}) do subwayEntrance(d[1],d[2]) end
for _,d in ipairs({{Vector3.new(48,0,-82),0},{Vector3.new(-52,0,82),180},{Vector3.new(82,0,48),90},{Vector3.new(-82,0,-48),-90}}) do scaffolding(d[1],d[2]) end

-- Yellow cabs and delivery vans as dead/stalled street props.
local function vehicle(pos,rot,yellow)
 local m=model(yellow and "NYC_YellowCab" or "NYC_DeliveryVan");local cf=CFrame.new(pos)*CFrame.Angles(0,math.rad(rot),0);local col=yellow and Color3.fromRGB(224,174,34) or Color3.fromRGB(218,218,211)
 part("Body",Vector3.new(yellow and 6 or 6.5,1.6,yellow and 10 or 11.5),cf*CFrame.new(0,1.4,0),col,Enum.Material.Metal,true,m)
 part("Cabin",Vector3.new(5.2,2.2,5),cf*CFrame.new(0,3,.3),Color3.fromRGB(26,34,40),Enum.Material.Glass,false,m).Transparency=.1
 for x=-1,1,2 do for z=-1,1,2 do local w=part("Wheel",Vector3.new(1.5,1.5,.8),cf*CFrame.new(x*3,.7,z*3.6)*CFrame.Angles(0,0,math.rad(90)),Color3.fromRGB(18,18,20),Enum.Material.SmoothPlastic,true,m);w.Shape=Enum.PartType.Cylinder end end
 if yellow then local roof=part("TaxiTop",Vector3.new(2.6,.55,1.2),cf*CFrame.new(0,4.4,0),Color3.fromRGB(235,225,180),Enum.Material.Neon,false,m);faceText(roof,"TAXI",Color3.fromRGB(20,20,20)) end
end
vehicle(Vector3.new(8,0,-150),16,true);vehicle(Vector3.new(-14,0,150),-11,true);vehicle(Vector3.new(150,0,14),84,true);vehicle(Vector3.new(-150,0,-12),102,false)

-- NYC-style street-name signs around the central district.
local function streetSign(pos,a,b)
 local pole=part("StreetSignPole",Vector3.new(.3,9,.3),CFrame.new(pos+Vector3.new(0,4.5,0)),Color3.fromRGB(55,58,62),Enum.Material.Metal,false)
 local s1=part("StreetSign",Vector3.new(8,1.4,.25),pole.CFrame*CFrame.new(0,3.7,0),Color3.fromRGB(25,92,67),Enum.Material.Metal,false);faceText(s1,a,Color3.new(1,1,1))
 local s2=part("StreetSign",Vector3.new(8,1.4,.25),pole.CFrame*CFrame.new(0,2.2,0)*CFrame.Angles(0,math.rad(90),0),Color3.fromRGB(25,92,67),Enum.Material.Metal,false);faceText(s2,b,Color3.new(1,1,1))
end
streetSign(Vector3.new(17,0,17),"5 AV","W 42 ST");streetSign(Vector3.new(-17,0,-17),"BROADWAY","W 34 ST");streetSign(Vector3.new(102,0,102),"LEXINGTON","E 47 ST")

-- Lighting tuned away from cyberpunk overload and toward wet NYC night.
Lighting.ClockTime=21.35
Lighting.Brightness=2.9
Lighting.ExposureCompensation=.55
Lighting.Ambient=Color3.fromRGB(62,68,82)
Lighting.OutdoorAmbient=Color3.fromRGB(78,84,98)
local cc=Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
if cc then cc.Saturation=-.04;cc.Contrast=.14;cc.Brightness=.03;cc.TintColor=Color3.fromRGB(225,230,240) end
local bloom=Lighting:FindFirstChildOfClass("BloomEffect")
if bloom then bloom.Intensity=.55;bloom.Size=28;bloom.Threshold=1.2 end

print("NYC REWORK V9 READY - Manhattan street canyons, brick walkups, towers, fire escapes, water tanks, subway entrances and NYC street detail loaded.")