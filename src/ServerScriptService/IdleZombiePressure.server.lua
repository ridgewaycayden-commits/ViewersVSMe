-- IdleZombiePressure.server.lua
-- Keeps the stream moving when chat/viewers stop interacting.
-- After a quiet period, occasionally adds a small number of normal zombies.

local ServerStorage=game:GetService("ServerStorage")
local ReplicatedStorage=game:GetService("ReplicatedStorage")

local dispatch=ServerStorage:WaitForChild("ViewersVsMeGiftDispatch")
local spawnRequest=ServerStorage:WaitForChild("GiftSpawnRequest")
local enemies=workspace:WaitForChild("TikTokEnemies")
local debugRemote=ReplicatedStorage:FindFirstChild("GiftDebug")
local rng=Random.new()

local QUIET_BEFORE_PRESSURE=28
local MIN_INTERVAL=22
local MAX_INTERVAL=38
local MAX_ACTIVE=11

local lastInteraction=os.clock()
local nextIdleSpawn=os.clock()+QUIET_BEFORE_PRESSURE+rng:NextNumber(4,12)

local function markInteraction()
	lastInteraction=os.clock()
	nextIdleSpawn=lastInteraction+QUIET_BEFORE_PRESSURE+rng:NextNumber(4,12)
end

dispatch.Event:Connect(function()
	markInteraction()
end)

-- Studio gift tests should count as interaction too.
if debugRemote then
	debugRemote.OnServerEvent:Connect(function()
		markInteraction()
	end)
end

local function aliveCount()
	local n=0
	for _,m in ipairs(enemies:GetChildren()) do
		local h=m:FindFirstChildOfClass("Humanoid")
		if h and h.Health>0 and m:GetAttribute("Dead")~=true then n+=1 end
	end
	return n
end

task.spawn(function()
	while true do
		task.wait(2)
		local now=os.clock()
		if now-lastInteraction>=QUIET_BEFORE_PRESSURE and now>=nextIdleSpawn then
			local active=aliveCount()
			if active<MAX_ACTIVE then
				local room=MAX_ACTIVE-active
				local amount=math.min(room,rng:NextInteger(1,3))
				if amount>0 then
					spawnRequest:Fire("IDLE_PRESSURE",amount,false)
					print("IDLE PRESSURE: spawned",amount,"zombie(s) after viewer inactivity")
				end
			end
			nextIdleSpawn=now+rng:NextNumber(MIN_INTERVAL,MAX_INTERVAL)
		end
	end
end)

print("IDLE ZOMBIE PRESSURE READY - occasional fallback spawns during quiet chat")