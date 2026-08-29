-- TikTokMemoryBridge.server.lua
-- VIEWERS VS ME - LIVE TIKTOK MEMORYSTORE BRIDGE V1
-- Reads Open Cloud/TikTok bridge events from TikTokLiveEventsV1 and forwards gifts
-- into the existing ServerStorage.ViewersVsMeGiftDispatch BindableEvent.

local MemoryStoreService=game:GetService("MemoryStoreService")
local ServerStorage=game:GetService("ServerStorage")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")

local QUEUE_NAME="TikTokLiveEventsV1"
local queue=MemoryStoreService:GetQueue(QUEUE_NAME,20)
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

	-- Some bridge payloads wrap the event data one level deeper.
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

	-- Non-gift TikTok events can still reach the HUD/other systems without being
	-- incorrectly treated as gifts. This leaves room for likes/follows later.
	if streamRemote then streamRemote:FireAllClients(e.raw) end
	print("TIKTOK LIVE EVENT:",e.eventType,"from",e.sender)
	return true
end

print("TIKTOK MEMORY BRIDGE V1 READY - queue:",QUEUE_NAME)

task.spawn(function()
	local consecutiveErrors=0
	while script.Parent do
		local ok,items,id=pcall(function()
			return queue:ReadAsync(10,false,5)
		end)

		if not ok then
			consecutiveErrors+=1
			warn("TIKTOK BRIDGE queue read failed:",items)
			task.wait(math.min(8,1+consecutiveErrors))
		elseif items and #items>0 then
			consecutiveErrors=0
			local processedAll=true
			for _,item in ipairs(items) do
				local worked=false
				local success,processErr=pcall(function() worked=process(item) end)
				if not success then warn("TIKTOK BRIDGE event processing error:",processErr);processedAll=false
				elseif not worked then warn("TIKTOK BRIDGE event skipped") end
			end
			-- Remove the batch only after processing attempts. If processing actually throws,
			-- leave it invisible until timeout so it can retry instead of silently disappearing.
			if processedAll and id then
				local removed,removeErr=pcall(function() queue:RemoveAsync(id) end)
				if not removed then warn("TIKTOK BRIDGE queue remove failed:",removeErr) end
			end
		else
			consecutiveErrors=0
			task.wait(.15)
		end
	end
end)
