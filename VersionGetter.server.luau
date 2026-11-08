local version = require(ScriptService.Server.Version)

local ds = Datastore:GetDatastore("Version")

Environment.Shared.VersionServer = version

while wait(1) do
	local latest = ds:GetAsync("Latest")
	if latest == nil or version > latest then
		ds:SetAsync("Latest", version)
		latest = version
	end
	Environment.Shared.VersionLatest = latest
	wait(59)
end
