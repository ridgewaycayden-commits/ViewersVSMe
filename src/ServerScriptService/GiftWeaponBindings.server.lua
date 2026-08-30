-- GiftWeaponBindings.server.lua
-- VIEWERS VS ME - maps TikTok gifts to imported weapon models and owns the shared gift-gun timer.
-- Any new gift refreshes an active gift gun to 90 seconds. If gifts stop, the gun expires and AutoCombat falls back to Knife.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local ServerStorage=game:GetService("ServerStorage")

local function host()
	return Players:GetPlayers()[1]
end

local dispatch=ServerStorage:WaitForChild("ViewersVsMeGiftDispatch")
local debugRemote=ReplicatedStorage:WaitForChild("GiftDebug")

local GUN_LIFETIME=90

-- Logical weapon names used by AutoCombat.
local GiftWeapons={
	["Rose"]="Pistol",
	["Heart Me"]="Rifle",
	["Hand Hearts"]="Shotgun", -- visually uses the Handgun model
	["Galaxy"]="Minigun",
	["Interstellar"]="SMG",
	["Phoenix"]="Shotgun", -- visually uses the Handgun model
	["Castle Fantasy"]="Minigun",
}

local serial=0

local function processGift(giftName,sender,count)
	local p=host();if not p then return end
	giftName=tostring(giftName or "")
	local mapped=GiftWeapons[giftName]

	-- Run after the other gift scripts so this becomes the final weapon/timer state.
	task.delay(.06,function()
		if not p.Parent then return end
		serial+=1
		local mySerial=serial
		local now=workspace:GetServerTimeNow()

		if mapped then
			p:SetAttribute("GiftWeapon",mapped)
			p:SetAttribute("GiftWeaponUntil",now+GUN_LIFETIME)
			print("TIKTOK GIFT WEAPON:",giftName,"from",sender,"->",mapped,"for",GUN_LIFETIME,"seconds")
		else
			-- Even a non-weapon gift counts as continued interaction and refreshes the current gift gun.
			local current=p:GetAttribute("GiftWeapon")
			local untilTime=tonumber(p:GetAttribute("GiftWeaponUntil")) or 0
			if type(current)=="string" and current~="" and untilTime>now then
				p:SetAttribute("GiftWeaponUntil",now+GUN_LIFETIME)
			end
		end

		task.delay(GUN_LIFETIME+.3,function()
			if mySerial~=serial or not p.Parent then return end
			if (tonumber(p:GetAttribute("GiftWeaponUntil")) or 0)<=workspace:GetServerTimeNow()+.35 then
				p:SetAttribute("GiftWeapon",nil)
				p:SetAttribute("GiftWeaponUntil",nil)
				print("GIFT GUN EXPIRED - reverting to Knife")
			end
		end)
	end)
end

dispatch.Event:Connect(processGift)
debugRemote.OnServerEvent:Connect(function(player,giftName)
	if player==host() then processGift(giftName,"TEST_VIEWER",1) end
end)

print("GIFT WEAPON BINDINGS V2 READY - 90s shared inactivity timer, Knife fallback")