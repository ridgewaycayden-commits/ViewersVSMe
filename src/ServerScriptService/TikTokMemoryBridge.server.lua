-- TikTokMemoryBridge.server.lua
-- VIEWERS VS ME - LIVE TIKTOK MEMORYSTORE BRIDGE V1.1
-- Studio-safe bridge: published servers poll TikTokLiveEventsV1 automatically.
-- Studio stays quiet unless this script's EnableInStudio attribute is set true.

local MemoryStoreService=game:GetService("MemoryStoreService")
local ServerStorage=game:GetService("ServerStorage")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")
local RunService=game:GetService("RunService")

local QUEUE_NAME="TikTokLiveEventsV1"
local ENABLE_IN_STUDIO=script:GetAttribute("EnableInStudio")==true

local dispatch=ServerStorage:WaitForChild("ViewersVsMeGiftDispatch")
local streamRemote=ReplicatedStorage:FindFirstChild("TikTokStreamEvent")

local function pick(t,...)
	for _,k in ipairs({...}) do
		local v=t[k]
		if v~=nil then return v end
	end
end

local function normalized(raw)
	if type(raw)=="string" then
		local ok,data=pcall(function() return HttpService:JSONDecode(raw) end)
		if ok and type(data)=="table" then raw=data else return nil,"string event was not JSON" end
	end
	if type(raw)~="table" then return nil,"event was not a table" end

	local eventType=tostring(pick(raw,"type","event","eventType","kind") or "gift"):lower()
	local sender=tostring(pick(raw,"sender","username","user","uniqueId","nickname") or "VIEWER")
	local gift=pick(raw,"giftName","gift_name","gift","name")
	local count=tonumber(pick(raw,"count","repeatCount","repeat_count","quantity","amount")) or 1
	count=math.clamp(math.floor(count),1,50)

	if type(raw.data)=="table" then
		local d=raw.data
		eventType=tostring(pick(d,"type","event","eventType","kind") or eventType):lower()
		sender=tostring(pick(d,"sender","username","user","uniqueId","nickname") or sender)
		gift=pick(d,"giftName","gift_name","gift","name") or gift
		count=tonumber(pick(d,"count","repeatCount","repeat_count","quantity","amount")) or count
		count=math.clamp(math.floor(count),1,50)
	end

	return {eventType=eventType,sender=sender,gift=gift and tostring(gift) or nil,count=count,raw=raw}
end

local function process(raw)
	local e,err=normalized(raw)
	if not e then warn("TIKTOK BRIDGE: ignored malformed event:",err);return false end

	if e.eventType=="gift" or e.gift then
		if not e.gift or e.gift=="" then warn("TIKTOK BRIDGE: gift event missing gift name");return false end
		dispatch:Fire(e.gift,e.sender,e.count)
		if streamRemote then streamRemote:FireAllClients({type="gift",giftName=e.gift,sender=e.sender,count=e.count}) end
		print("TIKTOK LIVE GIFT:",e.gift,"from",e.sender,"x"..e.count)
		return true
	end

	if streamRemote then streamRemote:FireAllClients(e.raw) end
	print("TIKTOK LIVE EVENT:",e.eventType,"from",e.sender)
	return true
end

if RunService:IsStudio() and not ENABLE_IN_STUDIO then
	print("TIKTOK MEMORY BRIDGE V1.1 STANDBY - Studio polling disabled. Published servers will connect automatically.")
	return
end

local queue=MemoryStoreService:GetQueue(QUEUE_NAME,20)
print("TIKTOK MEMORY BRIDGE V1.1 READY - queue:",QUEUE_NAME)

local missingQueueNotice=false

task.spawn(function()
	local consecutiveErrors=0
	while script.Parent do
		local ok,items,id=pcall(function()
			return queue:ReadAsync(10,false,5)
		end)

		if not ok then
			local err=tostring(items)
			if string.find(err,"UnknownMemoryStoreQueue",1,true) then
				if not missingQueueNotice then
					missingQueueNotice=true
					print("TIKTOK BRIDGE WAITING - queue has not been created by the external TikTok bridge yet.")
				end
				consecutiveErrors=0
				task.wait(3)
			else
				consecutiveErrors+=1
				warn("TIKTOK BRIDGE queue read failed:",err)
				task.wait(math.min(8,1+consecutiveErrors))
			end
		elseif items and #items>0 then
			missingQueueNotice=false
			consecutiveErrors=0
			local processedAll=true
			for _,item in ipairs(items) do
				local worked=false
				local success,processErr=pcall(function() worked=process(item) end)
				if not success then
					warn("TIKTOK BRIDGE event processing error:",processErr)
					processedAll=false
				elseif not worked then
					warn("TIKTOK BRIDGE event skipped")
				end
			end
			if processedAll and id then
				local removed,removeErr=pcall(function() queue:RemoveAsync(id) end)
				if not removed then warn("TIKTOK BRIDGE queue remove failed:",removeErr) end
			end
		else
			missingQueueNotice=false
			consecutiveErrors=0
			task.wait(.2)
		end
	end
end)
