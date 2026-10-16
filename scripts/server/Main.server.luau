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

local networkDeleteUserOwned: BindableEvent = ScriptService.DeleteUserOwned
local networkDeleteUnowned: BindableEvent = ScriptService.DeleteUnowned

local networkLog: NetworkEvent = ScriptService.Log

local function Log(content: string)
	content = content:gsub("%[", "[lb]")
	print(`[SERVER LOG]: {Filter:Filter(content)}`) -- Polytoria PLEASE make it so people can't see this :/

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
	end

	table.remove(blockList, table.find(blockList, block))
	block.Instance:Destroy()
	setmetatable(block, nil)
end

local function SetProperty(block: Blocks.Block, property: string, value: any, player: Player)
	local data = json:parse(block.Instance.Data.Value)
	if not GetOwner(block) then
		block.Owner = player.UserID
		data.Owner = player.UserID
	end

	value = Filter:Filter(tostring(value))

	if block.Properties[property] == nil then
		return
	end

	if tonumber(value) then
		local lim = 2 ^ 24
		value = tostring(math.clamp(tonumber(value), -lim, lim))
	end

	if property == "Label" then
		value = tostring(value)
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

networkImport.InvokedServer:Connect(function(player: Player, message: NetMessage)
	local idMap: { [any]: number } = {}

	local data = json:parse(message:GetString("Data"))
	local origin = message:GetVector3("Position")

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
	for i, v in data[5] do -- Make blocks
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
				Achievements.Award(player, 140234, 242030) -- The Stars Aligned
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
			return
		end

		wait(1 / 50)

		if i % 15 == 0 and i ~= 0 then
			wait(1 / 35)
		end

		if i % 150 == 0 and i ~= 0 then
			wait(0.1)
		end
	end

	local total_i = 0
	for i, v in data[5] do -- Make connections
		for j, c in v[7] do
			local from = GetBlockByUUID(idMap[c], TBA)
			if not from then
				continue
			end
			local to = GetBlockByUUID(idMap[v[5]], TBA)
			CreateConnection(from, to, player)

			if total_i % 300 == 0 and j ~= 0 then
				wait()
			end

			total_i += 1
		end

		if total_i % 35 == 0 and i ~= 0 then
			wait(1 / 40)
		end

		if total_i % 200 == 0 and i ~= 0 then
			wait(0.1)
		end

		wait(1 / 55)

		total_i += 1
	end

	for _, v in TBA do
		table.insert(blockList, v)
	end

	Chat:UnicastMessage("[IMPORT]: Import Finished!", player)
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
	else
		block:EvaluateNext()
		if block.Data.NextFakeState ~= nil or block.Data.FakeState ~= nil then
			return (block.NextState ~= block.State) or (block.Data.NextFakeState ~= block.Data.FakeState)
		else
			return block.NextState ~= block.State
		end
	end
end

local function UpdateBlocks(tickPeriod: number)
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

spawn(function()
	while wait(10) do
		Blocks.Players = Players:GetPlayers()
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
