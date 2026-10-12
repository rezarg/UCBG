local admins = require(ScriptService.Admins)

local banDS = Datastore:GetDatastore("Bans")
local serverInitTime = os.time()
Environment.Shared.InitTime = serverInitTime

local networkDeleteUserOwned: BindableEvent = ScriptService.DeleteUserOwned
local networkDeleteUnowned: BindableEvent = ScriptService.DeleteUnowned

local function GetTarget(name): Player?
	if Players:FindChild(name) then
		return Players[name]
	end

	for _, p in Players:GetPlayers() do
		if p.Name:lower() == name:lower() then
			return p
		end
	end

	for _, p in Players:GetPlayers() do
		if p.Name:sub(1, #name):lower() == name:lower() then
			return p
		end
	end

	return
end

local votes = {}
local unvotes = {}
local banList = {}
local globalBanCache = {}
local nameMap = {}
local clearVotes = {}
local hidden = {}

local function DoBubble(player: Player, message: string)
	local vb: VoiceBox? = player:FindChildByClass("VoiceBox")
	if not vb then
		vb = VoiceBox.New(player)
		vb.Color = Color.New(1, 1, 1, 0)
		wait(0.1)
	end
	vb.LocalPosition = Vector3.New(0, 4, 0)
	vb:Speak(message)
end

local function SecondsToMeasurement(seconds: number, measurement: "Hours" | "Years" | "Days")
	if measurement == "Years" then
		local years = seconds / 365 / 24 / 60 / 60
		if years < 1 then
			return SecondsToMeasurement(seconds, "Days")
		end
		return years, "Years"
	elseif measurement == "Days" then
		local days = seconds / 24 / 60 / 60
		if days < 1 then
			return SecondsToMeasurement(seconds, "Hours")
		end
		return days, "Days"
	elseif measurement == "Hours" then
		local hours = seconds / 60 / 60
		if hours < 1 then
			return seconds, "Seconds"
		end
		return hours, "Hours"
	end

	return seconds, "Seconds"
end

Chat.ChatPredicate = function(player: Player, message: string)
	local tokens = message:split(" ")
	if #tokens >= 1 then
		if tokens[1] == "!voteban" then
			local target = GetTarget(tokens[2])
			if not target then
				return false
			end

			if admins[target.UserID] then
				return false
			end

			if target == player then
				Chat:UnicastMessage("Now why would you want to do that?", player)
				return false
			end

			if not votes[target.UserID] then
				votes[target.UserID] = { player.UserID }
			else
				if table.find(votes[target.UserID], player.UserID) then
					Chat:UnicastMessage("You have already voted for this.", player)
					return false
				end
				table.insert(votes[target.UserID], player.UserID)
			end

			local requiredVoteCount = math.max(math.floor(0.8 * (#Players:GetPlayers() - 1)), 1)

			Chat:BroadcastMessage(
				`[SERVER]: {player.Name} has voted to server-ban {target.Name}. Say "!voteban {target.Name}" to add a vote. ({#votes[target]}/{requiredVoteCount})`
			)

			if #votes[target.UserID] >= requiredVoteCount then
				votes[target.UserID] = nil
				banList[target.UserID] = true
				nameMap[target.Name] = target.UserID
				networkDeleteUserOwned:Invoke(target)
				target:Kick("You have been votebanned.")
				Chat:BroadcastMessage(`[SERVER]: {target.Name} has been banned from the server.`)
			end

			return false
		elseif tokens[1] == "!voteunban" then
			local targetName = tokens[2]
			local targetId = nameMap[targetName]
			if not banList[targetId] then
				return false
			end

			if not unvotes[targetName] then
				unvotes[targetName] = { player.UserID }
			else
				if table.find(unvotes[targetName], player.UserID) then
					Chat:UnicastMessage("You have already voted for this.", player)
					return false
				end
				table.insert(unvotes[targetName], player.UserID)
			end

			local requiredVoteCount = math.max(math.floor(0.6 * (#Players:GetPlayers() - 1)), 1)

			Chat:BroadcastMessage(
				`[SERVER]: {player.Name} has voted to un-ban {targetName} from the server. Say "!voteunban {targetName}" to add a vote. ({#unvotes[targetName]}/{requiredVoteCount})`
			)

			if #unvotes[targetName] >= requiredVoteCount then
				unvotes[targetName] = nil
				banList[targetId] = nil
				Chat:BroadcastMessage(`[SERVER]: {targetName} has been unbanned from the server.`)
			end

			return false
		elseif tokens[1] == "!voteclear" then
			if not table.find(clearVotes, player.UserID) then
				table.insert(clearVotes, player.UserID)
			else
				Chat:UnicastMessage("You have already voted for this.", player)
				return false
			end

			local requiredVoteCount = #Players:GetPlayers()

			Chat:BroadcastMessage(
				`[SERVER]: {player.Name} has voted to clear unowned blocks. Say "!voteclear" to add a vote. ({#clearVotes}/{requiredVoteCount})`
			)

			if #clearVotes >= requiredVoteCount then
				clearVotes = {}
				Chat:BroadcastMessage(`[SERVER]: Unowned blocks have been cleared.`)
				networkDeleteUnowned:Invoke()
			end
		elseif tokens[1] == "!info" then
			spawn(function()
				wait(0.1)
				Chat:UnicastMessage(
					`[STATS]: Server Version: {Environment.Shared.VersionServer} (latest: {Environment.Shared.VersionLatest})`,
					player
				)
				Chat:UnicastMessage(
					`[STATS]: Average Ticks Per Second: {Environment.Shared.TicksPerSecondDone}`,
					player
				)
				Chat:UnicastMessage(`[STATS]: Target Ticks Per Second: {Environment.Shared.TicksPerSecondGoal}`, player)
				Chat:UnicastMessage(`[STATS]: Average Tick Error: {Environment.Shared.TickError}`, player)
				Chat:UnicastMessage(`[STATS]: Average Tick Error Side: {Environment.Shared.TickErrorSide}`, player)
				local lifetime = os.time() - serverInitTime
				local hours = math.floor(lifetime / 3600)
				local minutes = math.floor((lifetime % 3600) / 60)
				local seconds = lifetime % 60
				local lifetimeStr = ""
				if hours > 0 then
					lifetimeStr ..= `{hours}h `
				end
				if minutes > 0 then
					lifetimeStr ..= `{minutes}m `
				end
				lifetimeStr ..= `{seconds}s`
				Chat:UnicastMessage(`[STATS]: Server Age: {lifetimeStr}`, player)

				Achievements:AwardAsync(player.UserID, 241565) -- Quality Assurance
			end)
		elseif tokens[1] == "!goto" then
			local target = GetTarget(tokens[2])
			if not target then
				return false
			end
			player.Position = target.Position
			if hidden[player] then
				return false
			end
		elseif tokens[1] == "!help" or tokens[1] == "!cmds" then
			spawn(function()
				wait(0.1)
				Chat:UnicastMessage(`!help / !cmds | Show this.`, player)
				Chat:UnicastMessage(
					`!voteban [player] | Add a vote to remove a player from the server, including their builds. Requires a 60% majority.`,
					player
				)
				Chat:UnicastMessage(
					`!voteunban [player] | Add a vote to pardon a recently server-banned player. Requires a 40% majority.`,
					player
				)
				Chat:UnicastMessage("!voteclear | Add a vote to delete all UNOWNED blocks.", player)
				Chat:UnicastMessage(`!goto [player] | Teleport to the player.`, player)
				Chat:UnicastMessage(`!info | Show server information.`, player)
			end)
		end
	end

	if admins[player.UserID] then
		if tokens[1] == "!ban" then -- !ban [player] [length] [hours/h/days/d/years/y] [reason...] / !ban [player] forever [reason...]
			local target = GetTarget(tokens[2])
			local banName = target and target.Name or tokens[2]
			local targetID = nil

			if not target then
				local success, _ = pcall(function()
					local targetName = tokens[2]
					local info = Http:GetAsync(`https://api.polytoria.com/v1/users/find?username={targetName}`)
					if not info then
						return false, nil
					end
					info = json:parse(info)

					targetID = info.id
					return true
				end)

				if not success then
					return false
				end
			else
				targetID = target.UserID
			end

			if admins[targetID] then
				return false
			end

			local length
			if tokens[3] == "forever" then
				length = 1000
			else
				length = tonumber(tokens[3])
			end
			if not length then
				length = 24
			end

			local convert = {}
			convert.hours = "Hours"
			convert.years = "Years"
			convert.days = "Days"
			convert.h = "Hours"
			convert.y = "Years"
			convert.d = "Days"

			local measurement
			if tokens[3] == "inf" then
				measurement = "Years"
			else
				measurement = tokens[4] and convert[tokens[4]:lower()] or "Hours"
			end

			local reason
			if tokens[3] == "inf" then
				reason = table.concat(tokens, " ", 4)
			else
				reason = table.concat(tokens, " ", 5)
			end

			if reason == "" then
				reason = "Unspecified"
			end

			local timeout = os.time()
			if measurement == "Hours" then
				timeout += length * 60 * 60
			elseif measurement == "Days" then
				timeout += length * 60 * 60 * 24
			elseif measurement == "Years" then
				timeout += length * 60 * 60 * 24 * 365
			end

			local entry = {
				Reason = reason,
				Timeout = timeout,
				Measurement = measurement,
			}

			local success, e = pcall(function()
				banDS:SetAsync(targetID, json:serialize(entry))
			end)

			if not success then
				Chat:UnicastMessage("Failed to ban player.", player)
				warn(e)
				return false
			end

			networkDeleteUserOwned:Invoke(target)
			if tokens[3] == "inf" then
				target:Kick(`You have been permanently banned by an administrator: {reason}`)
			else
				target:Kick(`You have been banned by an administrator for {length} {measurement}: {reason}`)
			end
			networkDeleteUserOwned:Invoke(target)

			spawn(function()
				wait(0.1)
				if tokens[3] == "inf" then
					Chat:BroadcastMessage(
						`[SERVER]: {banName} has been permanently banned by an administrator: {reason}`
					)
				else
					Chat:BroadcastMessage(
						`[SERVER]: {banName} has been banned from by an administrator for {length} {measurement}: {reason}`
					)
				end
			end)

			return false
		elseif tokens[1] == "!banid" then
			local targetUserId = tonumber(tokens[2])
			if not targetUserId then
				return false
			end

			if admins[targetUserId] then
				return false
			end

			local length
			if tokens[3] == "inf" then
				length = 1000
			else
				length = tonumber(tokens[3])
			end
			if not length then
				length = 24
			end

			local convert = {}
			convert.hours = "Hours"
			convert.years = "Years"
			convert.days = "Days"
			convert.h = "Hours"
			convert.y = "Years"
			convert.d = "Days"

			local measurement
			if tokens[3] == "inf" then
				measurement = "Years"
			else
				measurement = tokens[4] and convert[tokens[4]:lower()] or "Hours"
			end

			local reason
			if tokens[3] == "inf" then
				reason = table.concat(tokens, " ", 4)
			else
				reason = table.concat(tokens, " ", 5)
			end

			if reason == "" then
				reason = "Unspecified"
			end

			local timeout = os.time()
			if measurement == "Hours" then
				timeout += length * 60 * 60
			elseif measurement == "Days" then
				timeout += length * 60 * 60 * 24
			elseif measurement == "Years" then
				timeout += length * 60 * 60 * 24 * 365
			end

			local entry = {
				Reason = reason,
				Timeout = timeout,
				Measurement = measurement,
			}

			local success, e = pcall(function()
				banDS:SetAsync(targetUserId, json:serialize(entry))
			end)

			if not success then
				Chat:UnicastMessage("Failed to ban player.", player)
				warn(e)
				return false
			end

			spawn(function()
				wait(0.1)
				if tokens[3] == "inf" then
					Chat:BroadcastMessage(
						`[SERVER]: User ID {targetUserId} has been permanently banned by an administrator: {reason}`
					)
				else
					Chat:BroadcastMessage(
						`[SERVER]: User ID {targetUserId} has been banned from by an administrator for {length} {measurement}: {reason}`
					)
				end
			end)
		elseif tokens[1] == "!unban" then
			local target = GetTarget(tokens[2])
			local banName = target and target.Name or tokens[2]
			local targetID = nil

			if not target then
				local success, _ = pcall(function()
					local targetName = tokens[2]
					local info = Http:GetAsync(`https://api.polytoria.com/v1/users/find?username={targetName}`)
					if not info then
						return false, nil
					end
					info = json:parse(info)

					targetID = info.id
					return true
				end)

				if not success then
					return false
				end
			else
				targetID = target.UserID
			end

			local success, _ = pcall(function()
				banDS:SetAsync(targetID, nil)
				globalBanCache[targetID] = nil
			end)

			if success then
				Chat:UnicastMessage(`{banName} has been unbanned.`, player)
			else
				Chat:UnicastMessage(`Failed to unban {banName}.`, player)
			end

			return false
		elseif tokens[1] == "!checkban" then
			local target = GetTarget(tokens[2])
			local banName = target and target.Name or tokens[2]
			local targetID = nil

			if not target then
				local success, _ = pcall(function()
					local targetName = tokens[2]
					local info = Http:GetAsync(`https://api.polytoria.com/v1/users/find?username={targetName}`)
					if not info then
						return false, nil
					end
					info = json:parse(info)

					targetID = info.id
					return true
				end)

				if not success then
					return false
				end
			else
				targetID = target.UserID
			end

			local success, result = pcall(function()
				return banDS:GetAsync(targetID)
			end)

			if not success then
				Chat:UnicastMessage("Failed to fetch ban info.", player)
				return false
			elseif not result then
				Chat:UnicastMessage(`No ban info for {banName}.`, player)
				return false
			end

			local entry = json:parse(result)
			local remaining, measurement = SecondsToMeasurement(entry.Timeout - os.time(), entry.Measurement)

			if measurement == "Years" and remaining > 500 then
				Chat:UnicastMessage(`[Ban Info] Time Remaining: (permanent) - Reason: {entry.Reason}`, player)
			else
				Chat:UnicastMessage(
					`[Ban Info] Time Remaining: {remaining} {measurement} - Reason: {entry.Reason}`,
					player
				)
			end

			return false
		elseif tokens[1] == "!fakeban" then
			local target = GetTarget(tokens[2])
			if not target then
				return false
			end

			target:Kick("You have been SUPER BANNED by an ADMIN!!!\n\n(just kidding, you can come back)")

			spawn(function()
				wait(0.1)
				Chat:BroadcastMessage(`[SERVER]: {target.Name} has been SUPER BANNED from the server by an ADMIN!!!`)
			end)
		elseif tokens[1] == "!tickrate" then
			local tps = tonumber(tokens[2])
			if not tps then
				return false
			end

			Environment.Shared.TickPeriod = 1 / tps

			spawn(function()
				wait(0.1)
				Chat:BroadcastMessage(`[SERVER]: The Tick Rate has been set to {tps} TPS.`)
			end)
		elseif tokens[1] == "!hidetag" then
			hidden[player] = not hidden[player] or nil
			if hidden[player] then
				Chat:UnicastMessage("Your admin status is now hidden.", player)
			else
				Chat:UnicastMessage("Your admin status is no longer hidden.", player)
			end
			return false
		elseif tokens[1] == "!hideself" then
			local hidden = Vector3.New(0, 1000, 0)
			local nothidden = Vector3.Zero
			local curr = player.Character.LocalPosition
			player.Character.LocalPosition = curr == hidden and nothidden or hidden
			return false
		elseif tokens[1] == "!setver" and player.UserID == 125312 then
			local version = tonumber(tokens[2])
			if not version then
				return false
			end

			local ds = Datastore:GetDatastore("Version")
			ds:SetAsync("Latest", version)
			ds:Disconnect()
			Environment.Shared.VersionLatest = version

			return false
		end
	end

	if player.UserID == 125312 then
		local prefix = `[color=#9731EB][Owner][/color]`
		local username = `[color={player.ChatColor:ToHex()}]{player.Name}[/color]`
		Chat:BroadcastMessage(`{prefix} {username}: {message}`)
		DoBubble(player, message)
		return false
	elseif admins[player.UserID] and player.UserID ~= 839194 and not hidden[player] then
		local prefix = `[color=#FF8230][Admin][/color]`
		local username = `[color={player.ChatColor:ToHex()}]{player.Name}[/color]`
		Chat:BroadcastMessage(`{prefix} {username}: {message}`)
		DoBubble(player, message)
		return false
	end

	return true
end

Players.PlayerAdded:Connect(function(player: Player)
	if banList[player.UserID] and not admins[player.UserID] then
		player:Kick("You are banned from this server.")
		return
	end

	local success, entry = pcall(function()
		if globalBanCache[player.UserID] then
			return globalBanCache[player.UserId]
		end
		local v = banDS:GetAsync(player.UserID)
		globalBanCache[player.UserID] = v
		return v
	end)

	if not success then
		warn(entry)
		player:Kick("Sorry, something went wrong in the join handler, please try rejoining!")
		return
	end

	if entry and not admins[player.UserID] then
		entry = json:parse(entry)
		if os.time() < entry.Timeout then
			local remaining, measurement = SecondsToMeasurement(entry.Timeout - os.time(), entry.Measurement)
			while player and player.Parent == Players do
				if measurement == "Years" and remaining > 500 then
					player:Kick(`You are permanently banned for:\n{entry.Reason}\n`)
				else
					player:Kick(`You are banned for {math.round(remaining)} more {measurement} for:\n{entry.Reason}\n`)
				end
				wait(0.5)
			end
			return
		end
	end

	wait(1)

	Chat:UnicastMessage(
		`[SYSTEM]: Welcome! Keep in mind that this game has user-generated content. If you see someone breaking Polytoria ToS, causing lag, or otherwise blatantly ruining the experience, say "!voteban PLAYER_NAME" to remove them.`,
		player
	)

	wait(1)

	if admins[player.UserID] then
		Chat:UnicastMessage(`Hello, {player.Name}! You are an admin. Below is a list of commands:`, player)
		Chat:UnicastMessage(
			`!ban [player] [number] (h/hours/d/days) [reason] -- e.g. !ban {player.Name} 24 hours Griefing`,
			player
		)
		Chat:UnicastMessage(`!ban [player] inf [reason] -- e.g. !ban {player.Name} inf Griefing`, player)
		Chat:UnicastMessage(
			`!banid [userid] [number] (h/hours) [reason] -- e.g. !banid {player.UserID} 24 hours Griefing`,
			player
		)
		Chat:UnicastMessage(`!banid [userid] inf [reason] -- e.g. !banid {player.UserID} inf Griefing`, player)
		Chat:UnicastMessage(`!checkban [player] -- e.g. !checkban {player.Name}`, player)
		Chat:UnicastMessage(`!fakeban [player]`, player)
		Chat:UnicastMessage(`!tickrate [tps] -- e.g. !tickrate 20`, player)
		Chat:UnicastMessage(`!hidetag -- toggles [ADMIN] tag visibility`, player)
		Chat:UnicastMessage(`!hideself -- toggles character visibility`, player)
	end
end)

while wait(60 * 15) do
	Chat:BroadcastMessage(`[REMINDER]: Say "!cmds" or "!help" to view a list of commands.`)
end
