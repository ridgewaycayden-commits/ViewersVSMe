-- LocalTikTokBridge.server.lua
-- VIEWERS VS ME - LOCAL STUDIO TIKTOK BRIDGE V1.1
-- Polls the PC bridge at 127.0.0.1:8765 while testing in Studio.
-- Requires Studio Settings > Security > Allow HTTP Requests.

local HttpService=game:GetService("HttpService")
local RunService=game:GetService("RunService")
local ServerStorage=game:GetService("ServerStorage")
local ReplicatedStorage=game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then return end

local URL="http://127.0.0.1:8765/events"

-- Do not WaitForChild here. Script startup order is not guaranteed in Studio,
-- so create/reuse the same BindableEvent that GiftEvents uses.
local dispatch=ServerStorage:FindFirstChild("ViewersVsMeGiftDispatch")
if dispatch and not dispatch:IsA("BindableEvent") then
	dispatch:Destroy()
	dispatch=nil
end
if not dispatch then
	dispatch=Instance.new("BindableEvent")
	dispatch.Name="ViewersVsMeGiftDispatch"
	dispatch.Parent=ServerStorage
end

local streamRemote=ReplicatedStorage:FindFirstChild("TikTokStreamEvent")
local warned=false

print("LOCAL TIKTOK BRIDGE V1.1 READY - polling PC bridge")

task.spawn(function()
	while script.Parent do
		local ok,body=pcall(function()
			return HttpService:GetAsync(URL,false)
		end)

		if ok then
			warned=false
			local decodedOk,events=pcall(function()
				return HttpService:JSONDecode(body)
			end)

			if decodedOk and type(events)=="table" then
				for _,e in ipairs(events) do
					if type(e)=="table" and tostring(e.type or ""):lower()=="gift" then
						local gift=tostring(e.gift or "")
						local sender=tostring(e.sender or "VIEWER")
						local count=math.clamp(math.floor(tonumber(e.count) or 1),1,50)

						if gift~="" then
							dispatch:Fire(gift,sender,count)
							if streamRemote then
								streamRemote:FireAllClients({type="gift",giftName=gift,sender=sender,count=count})
							end
							print("LOCAL TIKTOK GIFT:",gift,"from",sender,"x"..count)
						end
					end
			end
		elseif not warned then
			warned=true
			warn("LOCAL TIKTOK BRIDGE cannot reach PC bridge. Keep bridge open and enable HTTP Requests. Error:",body)
		end

		task.wait(.35)
	end
end)
