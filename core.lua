local highest = {}

local addonPrefix = "DRBv1"

local senders = {
	["Delpump-DefiasPillager"] = true,
	["Delf-DefiasPillager"] = true,
	["Deletery-DefiasPillager"] = true,
}

local targetTable

local function checksumReceive(tbl)
	local countPost = 0
	local sumPost = 0
	for _, v in pairs(tbl) do
		countPost = countPost + 1
		sumPost = sumPost + v
	end
	print("after sending:\n" .. countPost .. "\n" .. sumPost)
end

local function areWeMasterLooter()
	local masterLooter = select(2, GetLootMethod())
	return 0 == masterLooter
end

local f = CreateFrame("frame")
f:RegisterEvent("CHAT_MSG_RAID")
f:RegisterEvent("CHAT_MSG_RAID_LEADER")
f:RegisterEvent("CHAT_MSG_SYSTEM")
f:RegisterEvent("CHAT_MSG_RAID_WARNING")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("ADDON_LOADED")

C_ChatInfo.RegisterAddonMessagePrefix("DRBv1")

f:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		DRB_MC1 = DRB_MC1 or {}
		DRB_MC3 = DRB_MC3 or {}
		DRB_Raid = DRB_Raid or {}

		if DRB_Raid[UnitName("player")] == 1 then
			targetTable = DRB_MC1
		elseif DRB_Raid[UnitName("player")] == 3 then
			targetTable = DRB_MC3
		end
		-- PRINT LENGTH AND SUM OF BONUSES IN DRB_MC1 BEFORE SENDING DATA. PLACEHOLDER FOR CHECKSUM FUNCTION

		local function checksumSend(tbl)
			local countPre = 0
			local sumPre = 0
			for _, v in pairs(tbl) do
				countPre = countPre + 1
				sumPre = sumPre + v
			end
			print("before sending:\n" .. countPre .. "\n" .. sumPre)
		end

		-- DELAY FUNCTION USED TO SPACE OUT ADDON MESSAGES (LIMIT ONE/SEC)

		local function delay(tick)
			local th = coroutine.running()
			C_Timer.After(tick, function()
				coroutine.resume(th)
			end)
			coroutine.yield()
		end

		-- CHUNKING FUNCTION TO SPLIT UP TABLE INTO MULTIPLE MESSAGE CHUNKS

		local function chunkTable(tbl, num)
			local chunks = {}
			local chunk = tostring(num)
			for k, v in pairs(tbl) do
				if #(chunk .. k .. v .. ";") <= 254 then
					chunk = chunk .. k .. v .. ";"
				else
					table.insert(chunks, chunk)
					chunk = tostring(num) .. k .. v .. ";"
				end
			end
			table.insert(chunks, chunk)
			return chunks
		end

		-- THE ACTUAL SEND MESSAGE FUNCTION WHICH GETS CALLED WITH A COROUTINE DELAY

		local function sendMessage(tbl, num)
			local prefix = "DRBv1"
			local channel = "GUILD"
			local message = ""

			local chunks = chunkTable(tbl, num)

			for i, _ in pairs(chunks) do
				message = chunks[i]
				C_ChatInfo.SendAddonMessage(prefix, message, channel)
				--SendChatMessage(message, "WHISPER", "Common", "Delpump")
				delay(1.5)
			end
		end

		-- MANUAL CALL OF THE SYNC FUNCTION
		function DRBSync(num)
			local tbl
			if num == 1 then
				tbl = DRB_MC1
			elseif num == 3 then
				tbl = DRB_MC3
			else
				return
			end
			checksumSend(tbl)

			coroutine.wrap(sendMessage)(tbl, num)
		end

		function DRBRaid(num)
			if num == 1 or num == 3 then
				local player = UnitName("player")
				DRB_Raid[player] = num
				if DRB_Raid[player] == 1 then
					targetTable = DRB_MC1
				elseif DRB_Raid[player] == 3 then
					targetTable = DRB_MC3
				end
			else
				return
			end
		end
	end

	SLASH_SYNC1 = "/drbsync"
	SlashCmdList["SYNC"] = function(msg)
		msg = tonumber(msg)
		if msg == 1 or msg == 3 then
			DRBSync(msg)
		else
			return
		end
	end

	SLASH_MC1 = "/drbmc"
	SlashCmdList["MC"] = function(msg)
		msg = tonumber(msg)
		if msg == 1 or msg == 3 then
			DRBRaid(msg)
			ReloadUI()
		else
			return
		end
	end

	if event == "CHAT_MSG_ADDON" then
		local prefix, text, _, sender = ...
		local isAuthenticated = (prefix == addonPrefix) and senders[sender]
		if isAuthenticated and not (UnitName("player") == string.gsub(sender, "-%w+", "")) then
			local raidPrefix = string.match(text, "^[0-9]")
			text = string.gsub(text, "^[0-9]", "")
			local syncTable = {}
			if raidPrefix == "1" then
				syncTable = DRB_MC1
			elseif raidPrefix == "3" then
				syncTable = DRB_MC3
			end

			for k, v in string.gmatch(text, "([^0-9;]+)([0-9]+)") do
				syncTable[k] = tonumber(v)
			end
			checksumReceive(syncTable)
		end
	end

	if event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_RAID_WARNING" then
		local text, playerName = ...

		if
			UnitName("player") == string.gsub(playerName, "-%w+", "")
			and areWeMasterLooter()
			and (text == "start" or string.find(text, "Gargul : You have"))
		then
			highest = {}
		end

		if
			UnitName("player") == string.gsub(playerName, "-%w+", "")
			and areWeMasterLooter()
			and (text == "stop" or string.find(text, "Stop your rolls!"))
		then
			local function getKeysSortedByValue(tbl, sortFunction)
				local keys = {}
				for key in pairs(tbl) do
					table.insert(keys, key)
				end

				table.sort(keys, function(a, b)
					return sortFunction(tbl[a], tbl[b])
				end)

				return keys
			end

			local sortedKeys = getKeysSortedByValue(highest, function(a, b)
				return a > b
			end)

			for i = 1, #sortedKeys, 1 do
				SendChatMessage(format("%s %d", sortedKeys[i], highest[sortedKeys[i]]), "RAID")
			end
		end
	end

	if event == "CHAT_MSG_SYSTEM" then
		local text = ...
		local author, rollResult, rollMin, rollMax = string.match(text, "(.+) rolls (%d+) %((%d+)-(%d+)%)")

		if not (rollResult == nil) and (rollMin == "1") and (rollMax == "100") and areWeMasterLooter() then
			local function populateBonusTable()
				local playerBonus = targetTable[author]
				local playerTotal = rollResult + (playerBonus or 0)

				if not highest[author] then
					highest[author] = playerTotal
				end
			end
			a, b = pcall(populateBonusTable)
			if a == false then
				print(
					b,
					"Error, try running '/run DRBRaid(1)' or '/run DRBRaid(3)' to set the raid your are looting for to either MC1 or MC3. Then /reload"
				)
			end
		end
	end
end)
