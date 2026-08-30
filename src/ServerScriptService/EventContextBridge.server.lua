-- EventContextBridge.server.lua
-- Sends a single exact description of what each gift/event is actually doing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local remote = ReplicatedStorage:FindFirstChild("EventContextFX")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "EventContextFX"
	remote.Parent = ReplicatedStorage
end

local dispatch = ServerStorage:WaitForChild("ViewersVsMeGiftDispatch")
local debug = ReplicatedStorage:WaitForChild("GiftDebug")

local MAP = {
	["Rose"]={side="HELP",title="ROSE • HEAL",subtitle="+8 HP restored",color=Color3.fromRGB(90,255,150)},
	["Heart Me"]={side="HELP",title="HEART ME • HYPERLASER",subtitle="Temporary Hyperlaser weapon activated",color=Color3.fromRGB(80,220,255)},
	["Hand Hearts"]={side="HELP",title="HAND HEARTS • SHOTGUN",subtitle="+30 HP and temporary shotgun activated",color=Color3.fromRGB(255,155,90)},
	["Galaxy"]={side="HELP",title="GALAXY • MINIGUN",subtitle="Minigun activated + 6 second shield",color=Color3.fromRGB(120,180,255)},
	["Interstellar"]={side="HELP",title="INTERSTELLAR • FREEZE",subtitle="Horde frozen + AK47 boost activated",color=Color3.fromRGB(120,230,255)},
	["Phoenix"]={side="HELP",title="PHOENIX • AIRSTRIKE",subtitle="Normal infected wiped + 60 HP restored",color=Color3.fromRGB(255,205,80)},
	["Perfume"]={side="AGAINST",title="PERFUME • POISON",subtitle="You took 8 damage",color=Color3.fromRGB(190,100,255)},
	["Sports Car"]={side="AGAINST",title="SPORTS CAR • HORDE",subtitle="8 infected dropped into the city",color=Color3.fromRGB(255,95,65)},
	["Lion"]={side="AGAINST",title="LION • TITAN DEPLOYED",subtitle="Boss + 6 escorts spawned",color=Color3.fromRGB(255,70,55)},
	["TikTok Universe"]={side="AGAINST",title="UNIVERSE • BLACKOUT",subtitle="12 second blackout + 16 infected spawned",color=Color3.fromRGB(190,80,255)},
	["Universe"]={side="AGAINST",title="UNIVERSE • BLACKOUT",subtitle="12 second blackout + 16 infected spawned",color=Color3.fromRGB(190,80,255)},
	["Meteor Shower"]={side="AGAINST",title="METEOR SHOWER • INBOUND",subtitle="Impact targeted near your position",color=Color3.fromRGB(255,110,45)},
	["Private Jet"]={side="HELP",title="PRIVATE JET • ORBITAL STRIKE",subtitle="Orbital support targeting infected",color=Color3.fromRGB(80,220,255)},
	["Castle Fantasy"]={side="HELP",title="CASTLE FANTASY • OVERDRIVE",subtitle="Minigun + full heal + temporary shield",color=Color3.fromRGB(255,90,90)},
	["Dragon Flame"]={side="AGAINST",title="DRAGON FLAME • HELLSTORM",subtitle="Meteor barrage attacking your area",color=Color3.fromRGB(255,75,30)},
	["Leon and Lion"]={side="AGAINST",title="LEON & LION • TITAN RAGE",subtitle="Titans enraged or a Titan is spawned",color=Color3.fromRGB(255,35,40)},
	["Thunder Falcon"]={side="AGAINST",title="THUNDER FALCON • EMP",subtitle="Support weapon disabled + city darkened",color=Color3.fromRGB(155,85,255)},
}

local function host()
	return Players:GetPlayers()[1]
end

local function send(name,sender,count)
	local cfg = MAP[tostring(name or "")]
	if not cfg then return end
	remote:FireAllClients({
		side=cfg.side,
		title=cfg.title,
		subtitle=(count and count > 1) and (cfg.subtitle.."  x"..count) or cfg.subtitle,
		sender=tostring(sender or "VIEWER"),
		color=cfg.color,
	})
end

dispatch.Event:Connect(function(name,sender,count)
	send(name,sender,tonumber(count) or 1)
end)

debug.OnServerEvent:Connect(function(p,giftName)
	if p == host() then send(giftName,"TEST_VIEWER",1) end
end)

print("EVENT CONTEXT BRIDGE READY - exact gift/action popups")
