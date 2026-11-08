local function RFC3339(s: string)
	local year, month, day, hour, min, sec, _, tzSign, tzH, tzM =
		s:match("(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d).(%d%d%d)([Z%+%-])(%d*):?(%d*)")

	local t = os.time({
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day),
		hour = tonumber(hour),
		min = tonumber(min),
		sec = tonumber(sec),
	})

	if tzSign == "+" then
		t -= (tonumber(tzH) * 3600 + tonumber(tzM or 0) * 60)
	elseif tzSign == "-" then
		t += (tonumber(tzH) * 3600 + tonumber(tzM or 0) * 60)
	end

	return t
end

Players.PlayerAdded:Connect(function(player: Player)
	local info = Http:GetAsync(`https://api.polytoria.com/v1/users/{player.UserID}`)
	info = json:parse(info)

	local age = os.time() - RFC3339(info.registeredAt)

	if age < 172800 then -- 2 days
		player:Kick("Sorry, your account is untrusted.")
	elseif age < 604800 then -- 1 week
		if info.forumPosts == 0 and info.netWorth == 0 then
			player:Kick("Sorry, your account is untrusted.")
		end
	end
end)
