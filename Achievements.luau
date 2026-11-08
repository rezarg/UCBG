local PTAchievements = Achievements

local Achievements = {}

local cache: { [number]: { number } } = {}

function Achievements.Award(player: Player, worldId: number, achId: number)
	if not player then
		print(debug.traceback("Failed to award achievement: Player is nil."))
		return
	end

	if worldId ~= world.WorldID and world.WorldID ~= 0 then
		print(debug.traceback("Failed to award achievement: World ID is invalid."))
		return
	end

	if not cache[player.UserID] then
		cache[player.UserID] = {}
	end

	if table.find(cache[player.UserID], achId) then
		return
	end

	table.insert(cache[player.UserID], achId)
	local success, exception = pcall(function()
		PTAchievements:AwardAsync(player.UserID, 247356)
	end)

	if not success then
		print(debug.traceback(exception))
		table.remove(cache[player.UserId], table.find(cache[player.UserId], achId))
	end
end

return Achievements
