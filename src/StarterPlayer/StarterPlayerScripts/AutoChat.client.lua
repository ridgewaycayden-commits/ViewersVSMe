-- AutoChat.client.lua
-- VIEWERS VS ME - reliable occasional playful trash talk in Roblox chat V2.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local rng = Random.new()

local lines = {
	"chat yall gotta do better than that",
	"who sent that weak stuff 😂",
	"im still standing chat",
	"nahhh yall thought that was enough?",
	"chat wake up im cooking",
	"keep em coming this is light work",
	"yall really trying to get me killed huh",
	"chat that horde was embarrassing",
	"somebody send something actually dangerous",
	"im farming these zombies rn",
	"chat stop selling 😭",
	"that was supposed to scare me?",
	"yall are getting cooked by the host",
	"send the boss then",
	"chat im not losing to that",
}

local function getTextChannel()
	local channels = TextChatService:FindFirstChild("TextChannels") or TextChatService:WaitForChild("TextChannels",10)
	if not channels then return nil end

	local general = channels:FindFirstChild("RBXGeneral")
	if general and general:IsA("TextChannel") then return general end

	for _,channel in ipairs(channels:GetChildren()) do
		if channel:IsA("TextChannel") then return channel end
	end
	return nil
end

local function sendLine(message)
	-- Modern TextChatService path.
	local channel = getTextChannel()
	if channel then
		local ok,err = pcall(function()
			channel:SendAsync(message)
		end)
		if ok then
			print("AUTO CHAT SENT:",message)
			return true
		else
			warn("AUTO CHAT TextChatService FAILED:",err)
		end
	end

	-- Legacy fallback.
	local events = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
	local say = events and events:FindFirstChild("SayMessageRequest")
	if say then
		local ok,err = pcall(function()
			say:FireServer(message,"All")
		end)
		if ok then
			print("AUTO CHAT SENT (legacy):",message)
			return true
		else
			warn("AUTO CHAT legacy FAILED:",err)
		end
	end

	warn("AUTO CHAT: no usable chat channel found")
	return false
end

local function alive()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0
end

-- First message comes quickly so it's obvious whether the system works.
task.spawn(function()
	task.wait(7)
	if alive() then sendLine("chat yall awake or what") end

	while true do
		task.wait(rng:NextNumber(24,42))
		if alive() then
			sendLine(lines[rng:NextInteger(1,#lines)])
		end
	end
end)

print("AUTO CHAT V2 READY - first message in ~7 seconds, then every 24-42 seconds")
