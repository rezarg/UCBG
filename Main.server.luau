local Achievements = require(ScriptService.Achievements)

local admins = require(ScriptService.Admins)

local Blocks = require(ScriptService.Blocks)

local networkPlaceBlock: NetworkEvent = ScriptService.PlaceBlock
local networkDestroyBlock: NetworkEvent = ScriptService.DestroyBlock
local networkMakeConnection: NetworkEvent = ScriptService.MakeConnection
local networkDestroyConnection: NetworkEvent = ScriptService.DestroyConnection
local networkSetPropertyOfUUID: NetworkEvent = ScriptService.SetPropertyOfUUID
local networkPulseBlock: NetworkEvent = ScriptService.PulseBlock
local networkImport: NetworkEvent = ScriptService.Import
local networkMassDelete: NetworkEvent = ScriptService.MassDelete
local networkMassMove: NetworkEvent = ScriptService.MassMove
local networkSaveManager: NetworkEvent = ScriptService.SaveManager

local networkDeleteUserOwned: BindableEvent = ScriptService.DeleteUserOwned
local networkDeleteUnowned: BindableEvent = ScriptService.DeleteUnowned

local networkLog: NetworkEvent = ScriptService.Log

local function FilterWithWhitespace(value: string)
	value = tostring(value)

	local startWhitespace = ""
	for i = 1, #value do
		if value[i] ~= " " then
			break
		end

		startWhitespace ..= " "
	end

	local endWhitespace = ""
	for i = #value, 1, -1 do
		if i <= #startWhitespace then
			break
		end

		if value[i] ~= " " then
			break
		end

		endWhitespace ..= " "
	end

	return startWhitespace .. Filter:Filter(value) .. endWhitespace
end

local function Log(content: string)
	content = content:gsub("%[", "[lb]")
	print(`[SERVER LOG]: {FilterWithWhitespace(content)}`) -- Polytoria PLEASE make it so people can't see this :/

	local message = NetMessage.New()
	message:AddString("Content", content)
	for _, player in Players:GetPlayers() do
		if not admins[player.UserID] then
			continue
		end

		if player.UserID == 1 or player.UserID == 125312 then
			continue
		end

		networkLog:InvokeClient(message, player)
	end
end

type Connection = {
	Instance: Instance,
	From: any,
	To: any,
}

local blockList: { Blocks.Block } = {}
local connections: { Connection } = {}

local function GetBlockByUUID(uuid: number, blockPool: { any }?)
	if not blockPool then
		blockPool = blockList
	end
	for _, block in blockPool do
		if block.UUID == uuid then
			return block
		end
	end
	return nil
end

local function GetConnection(from, to)
	for _, v in connections do
		if v.From == from and v.To == to then
			return v
		end
	end
	return nil
end

local function GetOwner(block: Block)
	return block.Owner and Players:GetPlayerByID(block.Owner) or nil
end

local function UpdateConnection(connection: Connection)
	if not connection then
		return
	end

	local center = (connection.From.Instance.Position + connection.To.Instance.Position) / 2
	connection.Instance.Position = center
	connection.Instance:LookAt(connection.To.Instance.Position)

	local distance = (connection.From.Instance.Position - connection.To.Instance.Position).Magnitude
	connection.Instance.Size = Vector3.New(0.5, 0.5, distance)
end

local function CreateConnection(from: Blocks.Block, to: Blocks.Block, player: Player?): Connection
	if not GetOwner(from) then
		from.Owner = player.UserID
		local fromData = json:parse(from.Instance.Data.Value)
		fromData.Owner = player.UserID
		from.Instance.Data.Value = json:serialize(fromData)
	end

	local toData = json:parse(to.Instance.Data.Value)
	if not GetOwner(to) then
		to.Owner = player.UserID
		toData.Owner = player.UserID
	end

	local exists = GetConnection(from, to)
	if exists then
		return exists
	end

	table.insert(to.Inputs, from)
	table.insert(from.Outputs, to)

	local inputUUIDs = toData.InputUUIDs
	table.insert(inputUUIDs, from.UUID)
	to.Instance.Data.Value = json:serialize(toData)

	local connection = Hidden.Connection:Clone(Environment.Connections)
	connection.Owner.Value = player

	local c = { Instance = connection, From = from, To = to }
	UpdateConnection(c)

	Achievements.Award(player, 140234, 241564) -- An IQ too high?

	table.insert(connections, c)
	return c
end

local function DestroyBlock(block: Blocks.Block)
	for _, other in block.Outputs do
		table.remove(other.Inputs, table.find(other.Inputs, block))
		local c = GetConnection(block, other)
		if c then
			c.Instance:Destroy()
			table.remove(connections, table.find(connections, c))
		end
	end

	for _, other in block.Inputs do
		table.remove(other.Outputs, table.find(other.Outputs, block))

		local data = json:parse(block.Instance.Data.Value)
		table.remove(data.InputUUIDs, table.find(data.InputUUIDs, other.UUID))
		block.Instance.Data.Value = json:serialize(data)

		local c = GetConnection(other, block)
		if c then
			c.Instance:Destroy()
			table.remove(connections, table.find(connections, c))
		end
	end

	if block.Definition.Id == Blocks.Definitions.Signal.Id then
		Blocks.RemoveFromBucket(block)
	elseif block.Definition.Id == Blocks.Definitions.Sensor.Id then
		Blocks.RemoveSensor(block)
	end

	table.remove(blockList, table.find(blockList, block))
	block.Instance:Destroy()
	setmetatable(block, nil)
end

local function SetProperty(block: Blocks.Block, property: string, value: string, player: Player)
	local data = json:parse(block.Instance.Data.Value)
	if not GetOwner(block) then
		block.Owner = player.UserID
		data.Owner = player.UserID
	end

	value = tostring(value)

	FilterWithWhitespace(value)

	if block.Properties[property] == nil then
		return
	end

	if tonumber(value) then
		local lim = 2 ^ 24
		value = tostring(math.clamp(tonumber(value), -lim, lim))
	end

	if property == "Label" then
		if #value > 48 then
			value = value:sub(1, 48)
		end
	end

	block.Properties[property] = value

	data.Properties = block.Properties
	block.Instance.Data.Value = json:serialize(data)

	if property == "Label" then
		local label = block.Instance:FindChild("BlockLabel")
		if value == "" then
			if label then
				label:Destroy()
				return
			end
		else
			if not label then
				label = Hidden.BlockLabel:Clone(block.Instance)
				label.LocalPosition = Vector3.New(0, 2, 0)
			end
			label.Text = value:gsub("%[font", "[lb]font")
		end
	end

	block:UpdateVisual()
end

networkPlaceBlock.InvokedServer:Connect(function(player: Player, message: NetMessage)
	local blockId = message:GetInt("BlockId")
	local insertPosition = message:GetVector3("InsertPosition")
	local blockDef = Blocks.GetDefinitionById(blockId)

	local block = Blocks.Create(blockDef, insertPosition, player)
	table.insert(blockList, block)
end)

networkDestroyBlock.InvokedServer:Connect(function(player: Player, message: NetMessage)
	local uuid = message:GetInt("UUID")

	local block = GetBlockByUUID(uuid)
	if not block then
		return
	end

	local owner = GetOwner(block)
	if owner and player ~= owner then
		Log(`{player.Name} deleted a block owned by {owner.Name}`)
	end

	DestroyBlock(block)
end)

networkMakeConnection.InvokedServer:Connect(function(player: Player, message: NetMessage)
	local fromUUID = message:GetInt("From")
	local toUUID = message:GetInt("To")

	local fromBlock = GetBlockByUUID(fromUUID)
	if not fromBlock then
		return
	end

	local toBlock = GetBlockByUUID(toUUID)
	if not toBlock then
		return
	end

	CreateConnection(fromBlock, toBlock, player)
end)

networkDestroyConnection.InvokedServer:Connect(function(player: Player, message: NetMessage)
	local ref = message:GetInstance("Instance")

	for _, v in connections do
		if v.Instance ~= ref then
			continue
		end
		table.remove(v.From.Outputs, table.find(v.From.Outputs, v.To))
		table.remove(v.To.Inputs, table.find(v.To.Inputs, v.From))
		local data = json:parse(v.To.Instance.Data.Value)
		table.remove(data.InputUUIDs, table.find(data.InputUUIDs, v.From.UUID))
		v.To.Instance.Data.Value = json:serialize(data)

		v.Instance:Destroy()
		table.remove(connections, table.find(connections, v))
		break
	end
end)

networkSetPropertyOfUUID.InvokedServer:Connect(function(player: Player, message: NetMessage)
	local uuid = message:GetInt("UUID")
	local property = message:GetString("Property")
	local value = message:GetVariant("Value").Value

	local block = GetBlockByUUID(uuid)
	if not block then
		return
	end

	Log(`{player.Name} set '{property}' to '{value}'`)
	SetProperty(block, property, value, player)
end)

networkPulseBlock.InvokedServer:Connect(function(player: Player, message: NetMessage)
	local uuid = message:GetInt("UUID")

	local block = GetBlockByUUID(uuid)
	if not block then
		return
	end

	if block.Definition.Id == 8 and tonumber(block.Properties.Interactable) == 0 then
		return -- Non-interactable Switch
	end
	block.Pulsed = true
end)

local function GridVector3(original: Vector3, grid: number?): Vector3
	if not grid then
		grid = 1
	end
	local x = math.round(original.X * grid) / grid
	local y = math.round(original.Y * grid) / grid
	local z = math.round(original.Z * grid) / grid
	return Vector3.New(x, y, z)
end

networkMassMove.InvokedServer:Connect(function(player: Player, message: NetMessage)
	local data = json:parse(message:GetString("Data"))
	local offset = message:GetVector3("Offset")
	if #data >= 75 then
		Log(`{player.Name} moved {#data} Blocks.`)
	end
	for i, uuid in data do
		local block = GetBlockByUUID(uuid)
		local ref = block.Instance
		ref.Position = GridVector3(ref.Position + offset)
		for j, input in block.Inputs do
			local conn = GetConnection(input, block)
			UpdateConnection(conn)
			if j % 10 == 0 and i ~= 0 then
				wait(1 / 40)
			end
		end
		for j, output in block.Outputs do
			local conn = GetConnection(block, output)
			UpdateConnection(conn)
			if j % 10 == 0 and i ~= 0 then
				wait(1 / 40)
			end
		end
		if i % 100 == 0 and i ~= 0 then
			wait(1 / 5)
		else
			wait(1 / 60)
		end
	end
end)

local function ImportData(player: Player, data, origin: Vector3)
	local idMap: { [any]: number } = {}
	local countBlocks = #data[5]
	local countConnections = 0

	for i, v in data[5] do
		countConnections += #v[7]
		if i % 100 == 0 and i ~= 0 then
			wait()
		end
	end

	if countBlocks >= 150 or countConnections >= 300 then
		Chat:BroadcastMessage(
			`[NOTICE]: {player.Name} imported {countBlocks} blocks and {countConnections} connections.`
		)
	end

	local TBA = {}
	for i, v in data[5] do
		local success, exception = pcall(function(...)
			local definition = Blocks.GetDefById(v[1])
			if not definition then
				return
			end

			local position = origin + Vector3.New(v[2], v[3], v[4])
			if
				math.floor(position.X) ~= position.X
				or math.floor(position.Y) ~= position.Y
				or math.floor(position.Z) ~= position.Z
			then
				Achievements.Award(player, 140234, 242030)
			end

			local block = Blocks.Create(definition, position, player, v[8] and true or false)
			idMap[v[5]] = block.UUID

			for property, value in v[6] do
				SetProperty(block, property, value, player)
			end

			table.insert(TBA, block)
		end)

		if not success then
			print("Something went wrong while importing:", exception)
			Chat:UnicastMessage("[IMPORT]: Import stopped because a block failed to load.", player)
			return false
		end

		if i % 5 == 0 then
			wait(1 / 60)
		end
	end

	local total_i = 0
	for i, v in data[5] do
		for j, c in v[7] do
			local from = GetBlockByUUID(idMap[c], TBA)
			if not from then
				continue
			end
			local to = GetBlockByUUID(idMap[v[5]], TBA)
			if to then
				CreateConnection(from, to, player)
			end

			total_i += 1
			if total_i % 10 == 0 then
				wait(1 / 60)
			end
		end
	end

	for _, block in TBA do
		table.insert(blockList, block)
	end

	return true
end

networkImport.InvokedServer:Connect(function(player: Player, message: NetMessage)
	local success, data = pcall(function()
		return json:parse(message:GetString("Data"))
	end)
	if not success or type(data) ~= "table" or type(data[5]) ~= "table" then
		Chat:UnicastMessage("[IMPORT]: Invalid import data.", player)
		return
	end

	local imported = ImportData(player, data, message:GetVector3("Position"))
	if imported then
		Chat:UnicastMessage("[IMPORT]: Import Finished!", player)
	end
end)

-- Datastore-backed account save files. Each file is split across multiple keys
-- because Polytoria limits each datastore value to 65,535 bytes.
local saveDatastore = Datastore:GetDatastore("UCBGSaves")
local globalBuildDatastore = Datastore:GetDatastore("UCBGAdminBuilds")
local saveBusy = {}
local datastoreBusy = false
local SAVE_CHUNK_SIZE = 60000
local MAX_SAVE_BYTES = 6000000
local MAX_SAVE_CHUNKS = 100
local MAX_FILES_PER_ACCOUNT = 100
local MAX_GLOBAL_BUILDS = 100

local function DatastoreRequest(callback)
	while datastoreBusy do
		wait(0.05)
	end
	datastoreBusy = true
	local success, result = pcall(callback)
	local delay = 60 / math.max(1, 20 + 10 * #Players:GetPlayers())
	wait(delay)
	datastoreBusy = false
	return success, result
end

local function SaveIndexKey(userId: string): string
	return `u{userId}i`
end

local function SaveChunkKey(userId: string, fileId: string, chunk: number): string
	return `u{userId}f{fileId}c{chunk}`
end

local function GlobalBuildChunkKey(fileId: string, chunk: number): string
	return `g{fileId}c{chunk}`
end

local function ReadSaveIndex(userId: string)
	local success, index = DatastoreRequest(function()
		return saveDatastore:GetAsync(SaveIndexKey(userId))
	end)
	if not success then
		return nil, "Could not read the account save index."
	end
	if type(index) ~= "table" then
		index = { NextId = 1, Files = {} }
	end
	if type(index.Files) ~= "table" then
		index.Files = {}
	end
	index.NextId = tonumber(index.NextId) or 1
	return index
end

local function WriteSaveIndex(userId: string, index)
	local success = DatastoreRequest(function()
		saveDatastore:SetAsync(SaveIndexKey(userId), index)
		return true
	end)
	return success
end

local function ReadGlobalBuildIndex()
	local success, index = DatastoreRequest(function()
		return globalBuildDatastore:GetAsync("index")
	end)
	if not success then
		return nil, "Could not read the global Admin Builds index."
	end
	if type(index) ~= "table" then
		index = { NextId = 1, Files = {} }
	end
	if type(index.Files) ~= "table" then
		index.Files = {}
	end
	index.NextId = tonumber(index.NextId) or 1
	return index
end

local function WriteGlobalBuildIndex(index)
	local success = DatastoreRequest(function()
		globalBuildDatastore:SetAsync("index", index)
		return true
	end)
	return success
end

local function ReadGlobalBuildData(file)
	local result = ""
	for chunk = 1, file.Chunks do
		local success, value = DatastoreRequest(function()
			return globalBuildDatastore:GetAsync(GlobalBuildChunkKey(tostring(file.Id), chunk))
		end)
		if not success or type(value) ~= "string" then
			return nil, `Could not read Admin Build data chunk {chunk}.`
		end
		result ..= value
	end
	return result
end


local function SendSaveResponse(player: Player, operation: string, status: string, messageText: string?, extra)
	local response = NetMessage.New()
	response:AddString("Operation", operation)
	response:AddString("Status", status)
	response:AddString("Message", messageText or "")
	if extra then
		if extra.Files then
			response:AddString("Files", json:serialize(extra.Files))
		end
		if extra.AdminBuilds then
			response:AddString("AdminBuilds", json:serialize(extra.AdminBuilds))
		end
		if extra.Data then
			response:AddString("Data", extra.Data)
		end
		if extra.OwnerID then
			response:AddString("OwnerID", tostring(extra.OwnerID))
		end
		if extra.FileID then
			response:AddString("FileID", tostring(extra.FileID))
		end
	end
	networkSaveManager:InvokeClient(response, player)
end

local function MakeChunks(value: string)
	local chunks = {}
	local startAt = 1
	while startAt <= #value do
		local endAt = math.min(startAt + SAVE_CHUNK_SIZE - 1, #value)
		while endAt < #value do
			local nextByte = string.byte(value, endAt + 1)
			if not nextByte or nextByte < 128 or nextByte > 191 then
				break
			end
			endAt -= 1
		end
		table.insert(chunks, string.sub(value, startAt, endAt))
		startAt = endAt + 1
	end
	return chunks
end

local function GetWorldSaveData()
	if #blockList == 0 then
		return nil, "There are no blocks to save."
	end

	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, block in blockList do
		local position = block.Instance.Position
		minX = math.min(minX, position.X)
		minY = math.min(minY, position.Y)
		minZ = math.min(minZ, position.Z)
		maxX = math.max(maxX, position.X)
		maxY = math.max(maxY, position.Y)
		maxZ = math.max(maxZ, position.Z)
	end

	local origin = Vector3.New(minX, minY, minZ)
	local data = { maxX - minX + 1, maxY - minY + 1, maxZ - minZ + 1, 0, {} }
	for _, block in blockList do
		local object = {}
		local position = block.Instance.Position - origin
		object[1] = block.Definition.Id
		object[2] = position.X
		object[3] = position.Y
		object[4] = position.Z
		object[5] = block.UUID
		object[6] = block.Properties
		object[7] = {}
		for _, input in block.Inputs do
			table.insert(object[7], input.UUID)
		end
		object[8] = block.State
		table.insert(data[5], object)
	end

	return json:serialize(data), origin
end

local function FindSave(index, fileId: string)
	for i, file in index.Files do
		if tostring(file.Id) == tostring(fileId) then
			return file, i
		end
	end
	return nil, nil
end

local function ReadSaveData(userId: string, file)
	local result = ""
	for chunk = 1, file.Chunks do
		local success, value = DatastoreRequest(function()
			return saveDatastore:GetAsync(SaveChunkKey(userId, tostring(file.Id), chunk))
		end)
		if not success or type(value) ~= "string" then
			return nil, `Could not read save data chunk {chunk}.`
		end
		result ..= value
	end
	return result
end

local function RemoveSaveChunks(userId: string, file)
	for chunk = 1, file.Chunks do
		local success = DatastoreRequest(function()
			saveDatastore:RemoveAsync(SaveChunkKey(userId, tostring(file.Id), chunk))
			return true
		end)
		if not success then
			return false
		end
	end
	return true
end

local function SaveFile(player: Player, name: string)
	name = tostring(name):gsub("[%c]", ""):sub(1, 32)
	if name == "" then
		SendSaveResponse(player, "Save", "Error", "Enter a name for this save.")
		return
	end
	name = Filter:Filter(name)

	local rawData, origin = GetWorldSaveData()
	if not rawData then
		SendSaveResponse(player, "Save", "Error", origin)
		return
	end
	if #rawData > MAX_SAVE_BYTES then
		SendSaveResponse(player, "Save", "Error", "This save is larger than the 6 MB per-file limit.")
		return
	end

	local chunks = MakeChunks(rawData)
	if #chunks > MAX_SAVE_CHUNKS then
		SendSaveResponse(player, "Save", "Error", "This save needs too many datastore keys.")
		return
	end

	local userId = tostring(player.UserID)
	local index, indexError = ReadSaveIndex(userId)
	if not index then
		SendSaveResponse(player, "Save", "Error", indexError)
		return
	end
	if #index.Files >= MAX_FILES_PER_ACCOUNT then
		SendSaveResponse(player, "Save", "Error", "You have reached the 100-save limit for this account.")
		return
	end

	local fileId = tostring(index.NextId)
	local written = 0
	for chunkNumber, chunkData in chunks do
		local success = DatastoreRequest(function()
			saveDatastore:SetAsync(SaveChunkKey(userId, fileId, chunkNumber), chunkData)
			return true
		end)
		if not success then
			for oldChunk = 1, written do
				DatastoreRequest(function()
					saveDatastore:RemoveAsync(SaveChunkKey(userId, fileId, oldChunk))
					return true
				end)
			end
			SendSaveResponse(player, "Save", "Error", `Datastore failed while saving chunk {chunkNumber}.`)
			return
		end
		written += 1
	end

	table.insert(index.Files, {
		Id = fileId,
		Name = name,
		Chunks = #chunks,
		Bytes = #rawData,
		Created = tick(),
		OwnerID = userId,
		OwnerName = player.Name,
		Origin = { origin.X, origin.Y, origin.Z },
	})
	index.NextId += 1
	if not WriteSaveIndex(userId, index) then
		RemoveSaveChunks(userId, { Id = fileId, Chunks = #chunks })
		SendSaveResponse(player, "Save", "Error", "The save data uploaded, but the account index could not be updated.")
		return
	end

	SendSaveResponse(player, "Save", "Success", `Saved '{name}' ({#chunks} datastore keys).`, { Files = index.Files })
end

local function ListFiles(player: Player, userId: string, operation: string)
	local index, err = ReadSaveIndex(userId)
	if not index then
		SendSaveResponse(player, operation, "Error", err)
		return
	end
	local files = {}
	for _, file in index.Files do
		table.insert(files, {
			Id = tostring(file.Id), Name = file.Name, Chunks = file.Chunks,
			Bytes = file.Bytes, Created = file.Created, OwnerID = file.OwnerID,
			OwnerName = file.OwnerName,
		})
	end

	local globalIndex, globalError = ReadGlobalBuildIndex()
	local adminBuilds = {}
	if globalIndex then
		for _, file in globalIndex.Files do
			table.insert(adminBuilds, {
				Id = tostring(file.Id), Name = file.Name, Chunks = file.Chunks,
				Bytes = file.Bytes, Created = file.Created, OwnerID = file.OwnerID,
				OwnerName = file.OwnerName,
			})
		end
	end

	local statusText = `Found {#files} personal saves and {#adminBuilds} Admin Builds.`
	local responseData = { Files = files, OwnerID = userId }
	if globalIndex then
		responseData.AdminBuilds = adminBuilds
	else
		statusText ..= ` Admin Builds are temporarily unavailable: {globalError}`
	end
	SendSaveResponse(player, operation, "Success", statusText, responseData)
end

local function RenameFile(player: Player, userId: string, fileId: string, newName: string)
	newName = tostring(newName):gsub("[%c]", ""):sub(1, 32)
	if newName == "" then
		SendSaveResponse(player, "Rename", "Error", "Enter a new file name.")
		return
	end
	newName = Filter:Filter(newName)
	local index, err = ReadSaveIndex(userId)
	if not index then
		SendSaveResponse(player, "Rename", "Error", err)
		return
	end
	local file = FindSave(index, fileId)
	if not file then
		SendSaveResponse(player, "Rename", "Error", "That save no longer exists.")
		return
	end
	file.Name = newName
	if not WriteSaveIndex(userId, index) then
		SendSaveResponse(player, "Rename", "Error", "Could not update the save name.")
		return
	end
	SendSaveResponse(player, "Rename", "Success", `Renamed save to '{newName}'.`, { Files = index.Files, OwnerID = userId })
end

local function DeleteFile(player: Player, userId: string, fileId: string, operation: string)
	local index, err = ReadSaveIndex(userId)
	if not index then
		SendSaveResponse(player, operation, "Error", err)
		return
	end
	local file, fileIndex = FindSave(index, fileId)
	if not file then
		SendSaveResponse(player, operation, "Error", "That save no longer exists.")
		return
	end
	if not RemoveSaveChunks(userId, file) then
		SendSaveResponse(player, operation, "Error", "Could not delete every data chunk. The file remains listed for safety.")
		return
	end
	table.remove(index.Files, fileIndex)
	if not WriteSaveIndex(userId, index) then
		SendSaveResponse(player, operation, "Error", "Data chunks were deleted, but the account index could not be updated.")
		return
	end
	SendSaveResponse(player, operation, "Success", `Deleted '{file.Name}'.`, { Files = index.Files, OwnerID = userId })
end

local function SendCopyData(player: Player, fileName: string, rawData: string)
	local copyChunkSize = 48000
	local copyChunks = {}
	local copyStart = 1
	while copyStart <= #rawData do
		local copyEnd = math.min(copyStart + copyChunkSize - 1, #rawData)
		while copyEnd < #rawData do
			local nextByte = string.byte(rawData, copyEnd + 1)
			if not nextByte or nextByte < 128 or nextByte > 191 then
				break
			end
			copyEnd -= 1
		end
		table.insert(copyChunks, string.sub(rawData, copyStart, copyEnd))
		copyStart = copyEnd + 1
	end

	local startMessage = NetMessage.New()
	startMessage:AddString("Operation", "CopyStart")
	startMessage:AddString("Status", "Success")
	startMessage:AddString("Message", `Retrieving '{fileName}'...`)
	startMessage:AddInt("ChunkCount", #copyChunks)
	networkSaveManager:InvokeClient(startMessage, player)

	for chunkIndex, chunkData in copyChunks do
		local chunkMessage = NetMessage.New()
		chunkMessage:AddString("Operation", "CopyChunk")
		chunkMessage:AddString("Status", "Success")
		chunkMessage:AddInt("ChunkIndex", chunkIndex)
		chunkMessage:AddString("Data", chunkData)
		networkSaveManager:InvokeClient(chunkMessage, player)
	end

	local endMessage = NetMessage.New()
	endMessage:AddString("Operation", "CopyEnd")
	endMessage:AddString("Status", "Success")
	endMessage:AddString("Message", `Data for '{fileName}' is ready. Select all and copy it from the data box.`)
	networkSaveManager:InvokeClient(endMessage, player)
end

local function CopyFile(player: Player, userId: string, fileId: string, operation: string)
	local index, err = ReadSaveIndex(userId)
	if not index then
		SendSaveResponse(player, operation, "Error", err)
		return
	end
	local file = FindSave(index, fileId)
	if not file then
		SendSaveResponse(player, operation, "Error", "That save no longer exists.")
		return
	end
	local rawData, readError = ReadSaveData(userId, file)
	if not rawData then
		SendSaveResponse(player, operation, "Error", readError)
		return
	end
	SendCopyData(player, file.Name, rawData)
end

local function CopyGlobalBuild(player: Player, fileId: string)
	local index, err = ReadGlobalBuildIndex()
	if not index then
		SendSaveResponse(player, "GlobalCopy", "Error", err)
		return
	end
	local file = FindSave(index, fileId)
	if not file then
		SendSaveResponse(player, "GlobalCopy", "Error", "That Admin Build no longer exists.")
		return
	end
	local rawData, readError = ReadGlobalBuildData(file)
	if not rawData then
		SendSaveResponse(player, "GlobalCopy", "Error", readError)
		return
	end
	SendCopyData(player, file.Name, rawData)
end

local function LoadFile(player: Player, userId: string, fileId: string)
	local index, err = ReadSaveIndex(userId)
	if not index then
		SendSaveResponse(player, "Load", "Error", err)
		return
	end
	local file = FindSave(index, fileId)
	if not file then
		SendSaveResponse(player, "Load", "Error", "That save no longer exists.")
		return
	end
	local rawData, readError = ReadSaveData(userId, file)
	if not rawData then
		SendSaveResponse(player, "Load", "Error", readError)
		return
	end
	local parseSuccess, data = pcall(function()
		return json:parse(rawData)
	end)
	if not parseSuccess or type(data) ~= "table" or type(data[5]) ~= "table" then
		SendSaveResponse(player, "Load", "Error", "The saved file is invalid or corrupted.")
		return
	end
	local origin = GridVector3(player.Position) + Vector3.New(0, 3, 0)
	local imported = ImportData(player, data, origin)
	if not imported then
		SendSaveResponse(player, "Load", "Error", "The save could not be fully imported.")
		return
	end
	SendSaveResponse(player, "Load", "Success", `Loaded '{file.Name}' into the world.`)
end


local function GlobalBuildListForClient(index)
	local builds = {}
	for _, file in index.Files do
		table.insert(builds, {
			Id = tostring(file.Id), Name = file.Name, Chunks = file.Chunks,
			Bytes = file.Bytes, Created = file.Created, OwnerID = file.OwnerID,
			OwnerName = file.OwnerName,
		})
	end
	return builds
end

local function SaveGlobalBuild(player: Player, name: string)
	if admins[player.UserID] ~= true then
		SendSaveResponse(player, "GlobalSave", "Error", "Only administrators can publish Admin Builds.")
		return
	end
	name = tostring(name):gsub("[%c]", ""):sub(1, 32)
	if name == "" then
		SendSaveResponse(player, "GlobalSave", "Error", "Enter a name for this Admin Build.")
		return
	end
	name = Filter:Filter(name)

	local rawData, origin = GetWorldSaveData()
	if not rawData then
		SendSaveResponse(player, "GlobalSave", "Error", origin)
		return
	end
	if #rawData > MAX_SAVE_BYTES then
		SendSaveResponse(player, "GlobalSave", "Error", "This Admin Build is larger than the 6 MB per-file limit.")
		return
	end

	local chunks = MakeChunks(rawData)
	if #chunks > MAX_SAVE_CHUNKS then
		SendSaveResponse(player, "GlobalSave", "Error", "This Admin Build needs too many datastore keys.")
		return
	end

	local index, indexError = ReadGlobalBuildIndex()
	if not index then
		SendSaveResponse(player, "GlobalSave", "Error", indexError)
		return
	end
	if #index.Files >= MAX_GLOBAL_BUILDS then
		SendSaveResponse(player, "GlobalSave", "Error", "The global Admin Builds library has reached its 100-build limit.")
		return
	end

	local fileId = tostring(math.floor(tick() * 1000)) .. tostring(player.UserID):sub(-8)
	local written = 0
	for chunkNumber, chunkData in chunks do
		local success = DatastoreRequest(function()
			globalBuildDatastore:SetAsync(GlobalBuildChunkKey(fileId, chunkNumber), chunkData)
			return true
		end)
		if not success then
			for oldChunk = 1, written do
				DatastoreRequest(function()
					globalBuildDatastore:RemoveAsync(GlobalBuildChunkKey(fileId, oldChunk))
					return true
				end)
			end
			SendSaveResponse(player, "GlobalSave", "Error", `Datastore failed while saving Admin Build chunk {chunkNumber}.`)
			return
		end
		written += 1
	end

	table.insert(index.Files, {
		Id = fileId,
		Name = name,
		Chunks = #chunks,
		Bytes = #rawData,
		Created = tick(),
		OwnerID = tostring(player.UserID),
		OwnerName = player.Name,
		Origin = { origin.X, origin.Y, origin.Z },
	})
	index.NextId += 1
	if not WriteGlobalBuildIndex(index) then
		for oldChunk = 1, #chunks do
			DatastoreRequest(function()
				globalBuildDatastore:RemoveAsync(GlobalBuildChunkKey(fileId, oldChunk))
				return true
			end)
		end
		SendSaveResponse(player, "GlobalSave", "Error", "The build data uploaded, but the global index could not be updated.")
		return
	end

	SendSaveResponse(player, "GlobalSave", "Success", `Published '{name}' under Admin Builds. Admin Builds are permanent and cannot be deleted.`, {
		AdminBuilds = GlobalBuildListForClient(index),
	})
end

local function LoadGlobalBuild(player: Player, fileId: string)
	local index, err = ReadGlobalBuildIndex()
	if not index then
		SendSaveResponse(player, "GlobalLoad", "Error", err)
		return
	end
	local file = FindSave(index, fileId)
	if not file then
		SendSaveResponse(player, "GlobalLoad", "Error", "That Admin Build no longer exists.")
		return
	end
	local rawData, readError = ReadGlobalBuildData(file)
	if not rawData then
		SendSaveResponse(player, "GlobalLoad", "Error", readError)
		return
	end
	local parseSuccess, data = pcall(function()
		return json:parse(rawData)
	end)
	if not parseSuccess or type(data) ~= "table" or type(data[5]) ~= "table" then
		SendSaveResponse(player, "GlobalLoad", "Error", "The Admin Build is invalid or corrupted.")
		return
	end
	local origin = GridVector3(player.Position) + Vector3.New(0, 3, 0)
	local imported = ImportData(player, data, origin)
	if not imported then
		SendSaveResponse(player, "GlobalLoad", "Error", "The Admin Build could not be fully imported.")
		return
	end
	SendSaveResponse(player, "GlobalLoad", "Success", `Loaded Admin Build '{file.Name}' into the world.`)
end

networkSaveManager.InvokedServer:Connect(function(player: Player, message: NetMessage)
	local operation = message:GetString("Operation")
	local userId = tostring(player.UserID)
	local targetUserId = message:GetString("TargetUserID")
	local fileId = message:GetString("FileID")
	local isAdmin = admins[player.UserID] == true

	if operation == "AdminList" or operation == "AdminCopy" or operation == "AdminDelete" then
		if not isAdmin then
			SendSaveResponse(player, operation, "Error", "You are not authorized to use save moderation.")
			return
		end
		if not targetUserId:match("^%d+$") or #targetUserId > 15 then
			SendSaveResponse(player, operation, "Error", "Enter a valid account UserID.")
			return
		end
		userId = targetUserId
	end

	if operation == "GlobalDelete" then
		SendSaveResponse(player, operation, "Error", "Admin Builds are permanent and cannot be deleted.")
		return
	end
	if operation == "GlobalSave" and not isAdmin then
		SendSaveResponse(player, operation, "Error", "Only administrators can publish Admin Builds.")
		return
	end

	local busyKey = userId
	if operation == "GlobalSave" then
		busyKey = "GLOBAL_BUILDS"
	end
	if saveBusy[busyKey] then
		SendSaveResponse(player, operation, "Error", "A datastore operation is already running. Please wait.")
		return
	end
	saveBusy[busyKey] = true
	local success, err = pcall(function()
		if operation == "Save" then
			SaveFile(player, message:GetString("Name"))
		elseif operation == "List" or operation == "AdminList" then
			ListFiles(player, userId, operation)
		elseif operation == "Rename" then
			if userId ~= tostring(player.UserID) then
				SendSaveResponse(player, operation, "Error", "You cannot rename another user's saves.")
			else
				RenameFile(player, userId, fileId, message:GetString("Name"))
			end
		elseif operation == "Delete" then
			if userId ~= tostring(player.UserID) then
				SendSaveResponse(player, operation, "Error", "You cannot delete another user's saves through this action.")
			else
				DeleteFile(player, userId, fileId, operation)
			end
		elseif operation == "AdminDelete" then
			DeleteFile(player, userId, fileId, operation)
		elseif operation == "Copy" then
			CopyFile(player, userId, fileId, operation)
		elseif operation == "AdminCopy" then
			CopyFile(player, userId, fileId, operation)
		elseif operation == "Load" then
			if userId ~= tostring(player.UserID) then
				SendSaveResponse(player, operation, "Error", "You can only load your own personal saves.")
			else
				LoadFile(player, userId, fileId)
			end
		elseif operation == "GlobalSave" then
			SaveGlobalBuild(player, message:GetString("Name"))
		elseif operation == "GlobalLoad" then
			LoadGlobalBuild(player, fileId)
		elseif operation == "GlobalCopy" then
			CopyGlobalBuild(player, fileId)
		else
			SendSaveResponse(player, operation, "Error", "Unknown save operation.")
		end
	end)
	saveBusy[busyKey] = nil
	if not success then
		warn(`[DATASTORE]: Save manager error for {player.Name}: {err}`)
		SendSaveResponse(player, operation, "Error", "An unexpected datastore error occurred. Check the server log.")
	end
end)

networkMassDelete.InvokedServer:Connect(function(player: Player, message: NetMessage)
	local uuids = json:parse(message:GetString("Data"))
	local blocks = {}
	local connectionCount = 0

	for i, v in uuids do
		local block = GetBlockByUUID(v)
		if not block then
			continue
		end
		table.insert(blocks, block)
		connectionCount += #block.Inputs
		if i % 100 == 0 and i ~= 0 then
			wait(1 / 40)
		end
	end

	Log(`{player.Name} deleted {#uuids} blocks.`)

	if #uuids > 50 or connectionCount > 150 then
		Chat:BroadcastMessage(`[NOTICE]: {player.Name} deleted {#uuids} blocks and ~{connectionCount} connections.`)
	end

	for i, v in uuids do
		local block = GetBlockByUUID(v)
		if not block then
			continue
		end
		DestroyBlock(block)
		if i % 75 == 0 and i ~= 0 then
			wait(1 / 40)
		end
	end
end)

networkDeleteUserOwned.Invoked:Connect(function(player: Player)
	for i = #blockList, 1, -1 do
		local block = blockList[i]
		if block and block.Owner == player.UserID then
			DestroyBlock(block)
		end
	end
end)

networkDeleteUnowned.Invoked:Connect(function()
	for i = #blockList, 1, -1 do
		local block = blockList[i]
		if block and not GetOwner(block) then
			DestroyBlock(block)
		end
	end
end)

local function EvaluateBlock(block: Blocks.Block)
	if block.Pulsed and block.Definition.Id == Blocks.Definitions.Switch.Id then -- Pulse Switch
		block.NextState = not block.State
		block.Pulsed = false
		return true
	elseif block.Pulsed and block.Definition.Id == Blocks.Definitions.Signal.Id then -- Pulse Signal
		block.NextState = true
		block.Data.NextOrganicPower = true
		block.Pulsed = false
		return true
	elseif block.Pulsed and block.Definition.Id == Blocks.Definitions.Setter.Id then -- Pulse Setter
		if block.Properties.Power_Source ~= 0 then
			block.NextState = true
			block.Pulsed = false
		else
			block.Data.NextFakeState = true
			block.NextState = false
			block.Pulsed = false
		end
		return true
	elseif block.Pulsed then
		block.NextState = true
		block.Pulsed = false
		return true
	elseif block.Definition.Id == Blocks.Definitions.Sensor.Id then
		return block.NextState ~= block.State
	else
		block:EvaluateNext()
		if block.Data.NextFakeState ~= nil or block.Data.FakeState ~= nil then
			return (block.NextState ~= block.State) or (block.Data.NextFakeState ~= block.Data.FakeState)
		else
			return block.NextState ~= block.State
		end
	end
end

local sensorTick = 0
local function UpdateBlocks(tickPeriod: number)
	sensorTick += 1
	if sensorTick >= 4 then
		sensorTick = 0
		if #Blocks.Sensors > 0 then
			local success, exception = pcall(Blocks.UpdateSensors, Players:GetPlayers())
			if not success then
				print("Something went wrong while updating sensors:", exception)
			end
		end
	end

	local changed = {}

	local i = 0
	for _, block: Blocks.Block in blockList do
		local success, didChange = pcall(EvaluateBlock, block)
		if success and didChange then
			i += 1
			changed[i] = block
		end
		if i % 2000 == 0 and i ~= 0 then
			wait(tickPeriod / 3)
		end
	end

	for _, block in changed do
		if block.Data.NextFakeState ~= nil then
			block.Data.FakeState = block.Data.NextFakeState
		end
		block.State = block.NextState
		local _, _ = pcall(function()
			local data = json:parse(block.Instance.Data.Value)
			data.State = block.State
			block.Instance.Data.Value = json:serialize(data)
		end)
		block:UpdateVisual()
		if i % 2000 == 0 and i ~= 0 then
			wait(tickPeriod / 4)
		end
	end

	for _, channel in Blocks.SignalChannels do
		for _, block in channel do
			block.Data.OrganicPower = block.Data.NextOrganicPower or false
		end
	end
end

Environment.Shared.TickPeriod = 1 / 20

local elapsed = 0
local ticks = 0
local maxCatchupTicks = 4
Hooks.Updated:Connect(function(deltaTime: number)
	elapsed += deltaTime

	local tickPeriod = Environment.Shared.TickPeriod

	if elapsed >= tickPeriod * 10 then
		print("Immense Lag Detected. Resetting The Tick Cycle.")
		elapsed = 0
	end

	local i = 0
	while elapsed >= tickPeriod and i < maxCatchupTicks do
		UpdateBlocks(tickPeriod)
		elapsed -= tickPeriod
		ticks += 1
		i += 1
	end

	if i >= maxCatchupTicks then
		elapsed = 0
	end
end)

local updateTime = 5
while true do
	local tickPeriod = Environment.Shared.TickPeriod
	Environment.Shared.TicksPerSecondDone = math.round(ticks / updateTime)
	Environment.Shared.TicksPerSecondGoal = math.round(1 / tickPeriod * 100) / 100
	Environment.Shared.TickError = math.round(math.abs(elapsed) / updateTime * 10000) / 10000
	Environment.Shared.TickErrorSide = elapsed < 0 and "Slow" or "Fast"
	ticks = 0
	wait(updateTime)
end
