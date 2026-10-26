export type Block = {
	Owner: Player?,
	Definition: BlockDef,
	UUID: number,
	Inputs: { Block },
	Outputs: { Block },
	State: boolean,
	NextState: boolean,
	Pulsed: boolean,
	Instance: Part,
	Properties: { [string]: any },
	Data: { [string]: any },
	EvaluateNext: (self: Block) -> (),
	UpdateVisual: (self: Block) -> (),
}

export type BlockDef = {
	Id: number,
	Name: string,
	Bind: KeyCode,
	BindShifted: boolean,
	Color: Color,
	Properties: { [string]: any }?,
	Evaluator: (self: Block) -> (),
	UpdateVisual: ((self: Block) -> ())?,
}

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

local Blocks = {}
Blocks.Players = {}

local CURRENT_BLOCK_ID = 0
function Blocks.GenerateUUID()
	local id = CURRENT_BLOCK_ID
	CURRENT_BLOCK_ID += 1
	return id
end

function Blocks.GetDefNameById(id: number)
	for _, v in Blocks.Definitions do
		if v.Id == id then
			return v.Name
		end
	end
	return
end

function Blocks.GetDefById(id: number)
	for _, v in Blocks.Definitions do
		if v.Id == id then
			return v
		end
	end
	return
end

Blocks.DefaultUpdateVisual = function(self: Block)
	if self.State then
		self.Instance.Material = Enums.PartMaterial.Neon
	else
		self.Instance.Material = Enums.PartMaterial.SmoothPlastic
	end
end

local function DeepCopy(original)
	local clone = table.clone(original)
	for key, value in original do
		if type(value) == "table" then
			clone[key] = DeepCopy(value)
		end
	end

	return clone
end

Blocks.SignalChannels = {}

Blocks.RemoveFromBucket = function(block: Block)
	local channel = block.Data.Bucket
	if not channel then
		return
	end
	local bucket = Blocks.SignalChannels[channel]
	if bucket then
		local i = table.find(bucket, block)
		if i then
			bucket[i] = bucket[#bucket]
			bucket[#bucket] = nil
		end
		if #bucket == 0 then
			Blocks.SignalChannels[channel] = nil
		end
	end
	block.Data.Bucket = nil
end

local function AddToBucket(block: Block)
	local channel = block.Properties.Channel
	if block.Data.Bucket == channel then
		return
	end
	Blocks.RemoveFromBucket(block)
	local bucket = Blocks.SignalChannels[channel]
	if not bucket then
		bucket = {}
		Blocks.SignalChannels[channel] = bucket
	end
	table.insert(bucket, block)
	block.Data.Bucket = channel
end

function Blocks.Create(definition: BlockDef, position: Vector3, owner: Player?, initialState: boolean?): Block
	if initialState == nil then
		initialState = false
	end

	local block: Block = {}
	block.Owner = owner and owner.UserID or nil
	block.Definition = definition
	block.UUID = Blocks.GenerateUUID()
	block.Inputs = {}
	block.Outputs = {}
	block.State = initialState
	block.NextState = false
	block.Pulsed = false
	block.Properties = definition.Properties and DeepCopy(definition.Properties) or {}
	block.Properties.Label = ""
	block.Data = {}
	block.EvaluateNext = definition.Evaluator
	block.UpdateVisual = definition.UpdateVisual or Blocks.DefaultUpdateVisual

	local ref = Part.New(Environment.Blocks)
	block.Instance = ref
	ref.Color = block.Definition.Color
	ref.Position = position
	ref.Name = `{block.Definition.Id}_{block.UUID}`

	local dataRef = StringValue.New(ref)
	dataRef.Name = "Data"
	dataRef.Value = json:serialize({
		UUID = block.UUID,
		Properties = block.Properties,
		Owner = owner and owner.UserID or nil,
		InputUUIDs = {},
		State = initialState,
	})

	if definition.Id == Blocks.Definitions.Signal.Id then
		AddToBucket(block)
	end

	block:UpdateVisual()

	return block
end

local Definitions: { [string]: BlockDef } = {}

function Blocks.GetDefinitionById(id: number): BlockDef?
	for _, blockDef in Blocks.Definitions do
		if blockDef.Id == id then
			return blockDef
		end
	end
	return
end

function Blocks.GetDefinitionsSorted(): { BlockDef }
	local result = {}
	for _, blockDef in Blocks.Definitions do
		result[blockDef.Id + 1] = blockDef
	end
	return result
end

Definitions.And = {
	Id = 0,
	Name = "And",
	Bind = Enums.KeyCode.Key1,
	BindShifted = false,
	Color = Color.New(0.26, 0.58, 1),
	Evaluator = function(self: Block)
		if #self.Inputs == 0 then
			self.NextState = false
			return
		end
		for _, v in self.Inputs do
			if not v.State then
				self.NextState = false
				return
			end
		end
		self.NextState = true
	end,
}

Definitions.Or = {
	Id = 1,
	Name = "Or",
	Bind = Enums.KeyCode.Key2,
	BindShifted = false,
	Color = Color.New(0.26, 1, 0.58),
	Evaluator = function(self: Block)
		for _, v in self.Inputs do
			if v.State then
				self.NextState = true
				return
			end
		end
		self.NextState = false
	end,
}

Definitions.Nand = {
	Id = 2,
	Name = "Nand",
	Bind = Enums.KeyCode.Key3,
	BindShifted = false,
	Color = Color.New(0, 0.1, 0.36),
	Evaluator = function(self: Block)
		if #self.Inputs == 0 then
			self.NextState = true
			return
		end
		for _, v in self.Inputs do
			if not v.State then
				self.NextState = true
				return
			end
		end
		self.NextState = false
	end,
}

Definitions.Nor = {
	Id = 3,
	Name = "Nor",
	Bind = Enums.KeyCode.Key4,
	BindShifted = false,
	Color = Color.New(0, 0.36, 0.1),
	Evaluator = function(self: Block)
		for _, v in self.Inputs do
			if v.State then
				self.NextState = false
				return
			end
		end
		self.NextState = true
	end,
}

Definitions.Xor = {
	Id = 4,
	Name = "Xor",
	Bind = Enums.KeyCode.Key5,
	BindShifted = false,
	Color = Color.New(1, 0.36, 0.1),
	Evaluator = function(self: Block)
		local activeCount = 0
		for _, v in self.Inputs do
			if v.State then
				activeCount += 1
			end
		end
		self.NextState = activeCount % 2 == 1
	end,
}

Definitions.Xnor = {
	Id = 5,
	Name = "Xnor",
	Bind = Enums.KeyCode.Key6,
	BindShifted = false,
	Color = Color.New(0.58, 0.1, 0),
	Evaluator = function(self: Block)
		local activeCount = 0
		for _, v in self.Inputs do
			if v.State then
				activeCount += 1
			end
		end
		self.NextState = activeCount % 2 == 0
	end,
}

Definitions.Led = {
	Id = 6,
	Name = "LED",
	Bind = Enums.KeyCode.Key7,
	BindShifted = false,
	Color = Color.New(0, 0, 0),
	Properties = { On_R = 255, On_G = 255, On_B = 255, Off_R = 0, Off_G = 0, Off_B = 0 },
	Evaluator = Definitions.Or.Evaluator,
	UpdateVisual = function(self: Block)
		self.Properties.On_R = tonumber(self.Properties.On_R) or 255
		self.Properties.On_R = math.clamp(self.Properties.On_R, 0, 255)
		self.Properties.On_G = tonumber(self.Properties.On_G) or 255
		self.Properties.On_G = math.clamp(self.Properties.On_G, 0, 255)
		self.Properties.On_B = tonumber(self.Properties.On_B) or 255
		self.Properties.On_B = math.clamp(self.Properties.On_B, 0, 255)
		self.Properties.Off_R = tonumber(self.Properties.Off_R) or 0
		self.Properties.Off_R = math.clamp(self.Properties.Off_R, 0, 255)
		self.Properties.Off_G = tonumber(self.Properties.Off_G) or 0
		self.Properties.Off_G = math.clamp(self.Properties.Off_G, 0, 255)
		self.Properties.Off_B = tonumber(self.Properties.Off_B) or 0
		self.Properties.Off_B = math.clamp(self.Properties.Off_B, 0, 255)
		if self.State then
			self.Instance.Color = Color.FromRGB(self.Properties.On_R, self.Properties.On_G, self.Properties.On_B)
		else
			self.Instance.Color = Color.FromRGB(self.Properties.Off_R, self.Properties.Off_G, self.Properties.Off_B)
		end
		if self.Instance.Material ~= Enums.PartMaterial.Neon then
			self.Instance.Material = Enums.PartMaterial.Neon
		end
	end,
}

Definitions.Delay = {
	Id = 7,
	Name = "Delay",
	Bind = Enums.KeyCode.Key8,
	BindShifted = false,
	Color = Color.New(0.58, 0.36, 0.80),
	Properties = { Tick_Delay = 15, Pulse_Length = 1 },
	Evaluator = function(self: Block)
		self.Properties.Tick_Delay = tonumber(self.Properties.Tick_Delay) or 15
		self.Properties.Pulse_Length = tonumber(self.Properties.Pulse_Length) or 1

		local active = false
		if not active then
			for _, v in self.Inputs do
				if v.State then
					active = true
					break
				end
			end
		end

		if self.State and not active then
			if not self.Data.TicksLeft then
				self.Data.TicksLeft = self.Properties.Pulse_Length
			end
			self.Data.TicksLeft -= 1
			if self.Data.TicksLeft <= 0 then
				self.Data.TickCounter = nil
				self.Data.TicksLeft = nil
				self.NextState = false
				return
			end
			self.NextState = true
			return
		end

		if active and self.Data.TickCounter == nil then
			self.Data.TickCounter = 0
		end
		if self.Data.TickCounter and self.Data.TickCounter < self.Properties.Tick_Delay then
			self.Data.TickCounter += 1
		end
		if self.Data.TickCounter and self.Data.TickCounter >= self.Properties.Tick_Delay then
			self.NextState = true
			return
		end
		self.NextState = false
	end,
}

Definitions.Switch = {
	Id = 8,
	Name = "Switch",
	Bind = Enums.KeyCode.Key9,
	BindShifted = false,
	Color = Color.New(0.3, 0.3, 0.3),
	Properties = { Interactable = 1 },
	Evaluator = function(self: Block)
		self.Properties.Interactable = tonumber(self.Properties.Interactable)
		if self.Properties.Interactable ~= 0 then
			self.Properties.Interactable = 1
		end

		local active = false
		for _, v in self.Inputs do
			if v.State then
				active = true
				break
			end
		end

		if active and not self.Data.WasActive then
			self.NextState = not self.State
		else
			self.NextState = self.State
		end

		self.Data.WasActive = active
	end,
}

Definitions.Block = {
	Id = 9,
	Name = "Block",
	Bind = Enums.KeyCode.Key0,
	BindShifted = false,
	Color = Color.FromRGB(128, 128, 128),
	Properties = { R = 128, G = 128, B = 128, Alpha = 255, Solid = 1 },
	Evaluator = function(self: Block)
		self.NextState = false
	end,
	UpdateVisual = function(self: Block)
		self.Properties.R = tonumber(self.Properties.R) or 128
		self.Properties.R = math.clamp(self.Properties.R, 0, 255)
		self.Properties.G = tonumber(self.Properties.G) or 128
		self.Properties.G = math.clamp(self.Properties.G, 0, 255)
		self.Properties.B = tonumber(self.Properties.B) or 128
		self.Properties.B = math.clamp(self.Properties.B, 0, 255)
		self.Properties.Alpha = tonumber(self.Properties.Alpha) or 255
		self.Properties.Alpha = math.clamp(self.Properties.Alpha, 64, 255)
		self.Properties.Solid = tonumber(self.Properties.Solid) or 1
		if self.Properties.Solid ~= 0 then
			self.Properties.Solid = 1
		end
		self.Instance.Color =
			Color.FromRGB(self.Properties.R, self.Properties.G, self.Properties.B, self.Properties.Alpha / 255)
		self.Instance.CanCollide = self.Properties.Solid ~= 0 and true or false
		Blocks.DefaultUpdateVisual(self)
	end,
}

Definitions.Random = {
	Id = 10,
	Name = "Random",
	Bind = Enums.KeyCode.Key1,
	BindShifted = true,
	Color = Color.New(0.37, 0.22, 0.15),
	Properties = { Chance = 50 },
	Evaluator = function(self: Block)
		self.Properties.Chance = tonumber(self.Properties.Chance) or 50
		self.NextState = math.random(1, 100) <= tonumber(self.Properties.Chance)
	end,
}

local speakerWaveforms = {}
speakerWaveforms.Sine = 237740
speakerWaveforms.Sawtooth = 237741
speakerWaveforms.Square = 237742
speakerWaveforms.Triangle = 237743
speakerWaveforms.Pulse = 237744

Definitions.Speaker = {
	Id = 11,
	Name = "Speaker",
	Bind = Enums.KeyCode.Key2,
	BindShifted = true,
	Color = Color.New(0.87, 0.47, 0.1),
	Properties = { Frequency = 440, Volume = 100, Waveform = "Sine" },
	Evaluator = Definitions.Or.Evaluator,
	UpdateVisual = function(self: Block)
		self.Properties.Frequency = tonumber(self.Properties.Frequency) or 440
		self.Properties.Frequency = math.clamp(self.Properties.Frequency, 1, 9680) -- Previously 27.5-4186.01
		self.Properties.Volume = tonumber(self.Properties.Volume) or 100
		self.Properties.Volume = math.clamp(self.Properties.Volume, 0, 100)
		self.Properties.Waveform = speakerWaveforms[self.Properties.Waveform] and self.Properties.Waveform or "Sine"
		local sound: Sound? = self.Data.Sound
		local volume = 0.9 * (self.Properties.Volume / 100)
		local audio = speakerWaveforms[self.Properties.Waveform]
		local pitch = self.Properties.Frequency / 1760 -- Asset is 1760Hz
		if not sound then
			sound = Sound.New(self.Instance)
			sound.Audio = PTAudioAsset.New()
			sound.Audio.AudioID = audio
			sound.Volume = volume
			sound.Pitch = pitch
			sound.Loop = true
			sound.PlayInWorld = true
			self.Data.Sound = sound
		end
		if sound.Audio.AudioID ~= audio then
			sound:Stop()
			sound.Audio.AudioID = audio
		end
		sound.Pitch = pitch
		sound.Volume = volume
		if self.State and not sound.Playing then
			sound:Play()
		elseif not self.State and sound.Playing then
			sound:Stop()
		end
		Blocks.DefaultUpdateVisual(self)
	end,
}

local setterOpMap = {}
setterOpMap["+="] = "+"
setterOpMap["-="] = "-"
setterOpMap["*="] = "*"
setterOpMap["/="] = "/"
setterOpMap["%="] = "%"
setterOpMap["^="] = "^"
setterOpMap["//="] = "//"
setterOpMap["..="] = ".."

local function GetSetterValue(value: string): {
	Value: number | string,
	Raw: string,
	Numeric: boolean,
	Operator: string?,
	Literal: boolean,
}
	local result = {}
	result.Literal = false
	if value:sub(1, 1) == '"' and value:sub(-1) == '"' then
		value = value:sub(2, -2)
		result.Operator = nil
		result.Literal = true
	else
		local smallOp = setterOpMap[value:sub(1, 2)]
		local largeOp = setterOpMap[value:sub(1, 3)]
		result.Operator = smallOp ~= nil and smallOp or largeOp
		if result.Operator then
			value = value:sub(#result.Operator + 2)
		end
	end
	local numericValue = tonumber(value)
	result.Numeric = numericValue ~= nil
	result.Value = numericValue ~= nil and numericValue or value
	result.Raw = value
	return result
end

Definitions.Setter = {
	Id = 12,
	Name = "Setter",
	Bind = Enums.KeyCode.Key3,
	BindShifted = true,
	Color = Color.New(1, 0.83, 0.69),
	Properties = {
		Property = "", -- Legacy
		Value = "", -- Legacy
		Property_1 = "",
		Value_1 = "",
		Property_2 = "",
		Value_2 = "",
		Property_3 = "",
		Value_3 = "",
		Power_Source = 1,
	},
	Evaluator = function(self: Block)
		if self.Properties.Property ~= nil or self.Properties.Value ~= nil then
			if self.Properties.Property and self.Properties.Property ~= "" then
				self.Properties.Property_1 = self.Properties.Property
			end
			self.Properties.Property = nil

			if self.Properties.Value and self.Properties.Value ~= "" then
				self.Properties.Value_1 = self.Properties.Value
			end
			self.Properties.Value = nil

			local data = json:parse(self.Instance.Data.Value)
			data.Properties = self.Properties
			self.Instance.Data.Value = json:serialize(data)
		end

		self.Properties.Power_Source = tonumber(self.Properties.Power_Source) ~= 0 and 1 or 0

		local active = false
		for _, v in self.Inputs do
			if v.State then
				active = true
				break
			end
		end

		if not (self.State or self.Data.FakeState) and self.Data.DidSet then
			self.Data.DidSet = false
		end

		if (self.State or self.Data.FakeState) and not self.Data.DidSet then
			self.Data.DidSet = true
			for _, other in self.Outputs do
				local properties: { string } = {
					tostring(self.Properties.Property_1),
					tostring(self.Properties.Property_2),
					tostring(self.Properties.Property_3),
				}
				local values: { string } = {
					tostring(self.Properties.Value_1),
					tostring(self.Properties.Value_2),
					tostring(self.Properties.Value_3),
				}

				local changed = false
				for i, property in properties do
					if not property or #property == 0 or not other.Properties[property] then
						continue
					end

					local thisValue = GetSetterValue(values[i])
					local otherValue = GetSetterValue(tostring(other.Properties[property]))

					local newValue = other.Properties[property]
					if not thisValue.Operator and not thisValue.Literal then
						newValue = thisValue.Value
					elseif thisValue.Operator and otherValue.Numeric and not thisValue.Literal then
						if thisValue.Operator == "+" then
							otherValue.Value += thisValue.Value
						elseif thisValue.Operator == "-" then
							otherValue.Value -= thisValue.Value
						elseif thisValue.Operator == "*" then
							otherValue.Value *= thisValue.Value
						elseif thisValue.Operator == "/" then
							otherValue.Value /= thisValue.Value
						elseif thisValue.Operator == "%" then
							otherValue.Value %= thisValue.Value
						elseif thisValue.Operator == "^" then
							otherValue.Value ^= thisValue.Value
						elseif thisValue.Operator == "//" then
							otherValue.Value //= thisValue.Value
						elseif thisValue.Operator == ".." then
							otherValue.Value = otherValue.Raw .. thisValue.Raw
						end

						newValue = otherValue.Operator and `{otherValue.Operator}={otherValue.Value}`
							or otherValue.Value
						newValue = otherValue.Literal and `"{newValue}"` or newValue
					elseif thisValue.Literal then
						newValue = thisValue.Operator and `{thisValue.Operator}={thisValue.Value}` or thisValue.Value
					elseif thisValue.Operator and not otherValue.Numeric then
						local otherValueSecond = GetSetterValue(otherValue.Value)
						if otherValueSecond.Operator and otherValueSecond.Numeric then
							if thisValue.Operator == "+" then
								otherValueSecond.Value += thisValue.Value
							elseif thisValue.Operator == "-" then
								otherValueSecond.Value -= thisValue.Value
							elseif thisValue.Operator == "*" then
								otherValueSecond.Value *= thisValue.Value
							elseif thisValue.Operator == "/" then
								otherValueSecond.Value /= thisValue.Value
							elseif thisValue.Operator == "%" then
								otherValueSecond.Value %= thisValue.Value
							elseif thisValue.Operator == "^" then
								otherValueSecond.Value ^= thisValue.Value
							elseif thisValue.Operator == "//" then
								otherValueSecond.Value //= thisValue.Value
							elseif thisValue.Operator == ".." then
								otherValueSecond.Value = otherValueSecond.Raw .. thisValue.Raw
							end

							newValue = `"{otherValueSecond.Operator}={otherValueSecond.Value}"`
						else
							if thisValue.Operator == ".." then
								otherValue.Value = otherValueSecond.Raw .. thisValue.Raw

								newValue = otherValue.Operator and `{otherValue.Operator}={otherValue.Value}`
									or otherValue.Value
							end
						end
					end

					newValue = tostring(newValue)

					if property == "Label" then
						local label = other.Instance:FindChild("BlockLabel")
						if newValue == "" then
							if label then
								label:Destroy()
							end
						else
							if not label then
								label = Hidden.BlockLabel:Clone(other.Instance)
								label.LocalPosition = Vector3.New(0, 2, 0)
							end
							newValue = newValue:sub(1, 48):gsub("%[font", "[lb]font")
							if label.Text ~= newValue then
								newValue = FilterWithWhitespace(newValue)
								label.Text = newValue
							end
						end
					elseif newValue ~= other.Properties[property] then
						newValue = FilterWithWhitespace(newValue)
					end

					changed = changed or other.Properties[property] ~= newValue
					other.Properties[property] = newValue
				end

				if changed then
					other:UpdateVisual()
					local data = json:parse(other.Instance.Data.Value)
					data.Properties = other.Properties
					other.Instance.Data.Value = json:serialize(data)
				end
			end
		end

		self.Data.NextFakeState = active
		if self.Properties.Power_Source ~= 0 then
			self.NextState = active
		else
			self.NextState = false
		end
	end,
	UpdateVisual = function(self: Block)
		if self.State or self.Data.FakeState then
			self.Instance.Material = Enums.PartMaterial.Neon
		else
			self.Instance.Material = Enums.PartMaterial.SmoothPlastic
		end
	end,
}

Definitions.Range = {
	Id = 13,
	Name = "Range",
	Bind = Enums.KeyCode.Key4,
	BindShifted = true,
	Color = Color.New(0.98, 0.46, 1),
	Properties = { Min = 2, Max = 4 },
	Evaluator = function(self: Block)
		local count = 0
		for _, v in self.Inputs do
			if v.State then
				count += 1
			end
		end

		self.Properties.Min = tonumber(math.floor(self.Properties.Min)) or 2
		self.Properties.Max = tonumber(math.floor(self.Properties.Max)) or 4

		if self.Properties.Min <= self.Properties.Max then
			self.NextState = count >= self.Properties.Min and count <= self.Properties.Max
		elseif self.Properties.Min > self.Properties.Max then
			self.NextState = not (count >= self.Properties.Max and count <= self.Properties.Min)
		else
			self.NextState = count == self.Properties.Max
		end
	end,
}

Definitions.Signal = {
	Id = 14,
	Name = "Signal",
	Bind = Enums.KeyCode.Key5,
	BindShifted = true,
	Color = Color.New(0.85, 0.93, 0.73),
	Properties = { Channel = "default" },
	Evaluator = function(self: Block)
		local channel = self.Properties.Channel
		if #channel > 24 then
			channel = string.sub(channel, 1, 24)
			self.Properties.Channel = channel
		end

		AddToBucket(self)

		for _, v in self.Inputs do
			if v.State then
				self.NextState = true
				self.Data.NextOrganicPower = true
				return
			end
		end

		self.Data.NextOrganicPower = false
		for _, v in Blocks.SignalChannels[channel] do
			if v ~= self and v.Data.OrganicPower and v.State then
				self.NextState = true
				return
			end
		end

		self.NextState = false
	end,
}

Definitions.Sensor = {
	Id = 15,
	Name = "Sensor",
	Bind = Enums.KeyCode.Key6,
	BindShifted = true,
	Color = Color.New(0.61, 0.44, 0.61),
	Properties = { Distance = 12 },
	Evaluator = function(self: Block)
		self.Properties.Distance = tonumber(self.Properties.Distance) or 12
		self.Properties.Distance = math.clamp(self.Properties.Distance, 0, 128)
		local at = self.Instance.Position
		local sqrDist = self.Properties.Distance ^ 2
		for _, v in Blocks.Players do
			local pos = v.Position
			local dx, dy, dz = pos.X - at.X, pos.Y - at.Y, pos.Z - at.Z
			if dx * dx + dy * dy + dz * dz <= sqrDist then
				self.NextState = true
				return
			end
		end

		self.NextState = false
	end,
}

Definitions.GetterR = {
	Id = 16,
	Name = "Getter (R)",
	Bind = Enums.KeyCode.Key7,
	BindShifted = true,
	Color = Color.New(0.78, 0.65, 0.54),
	Properties = { Property = "", Min = 0, Max = 0 },
	Evaluator = function(self: Block)
		self.Properties.Min = tonumber(self.Properties.Min) or 0
		self.Properties.Max = tonumber(self.Properties.Max) or 0
		local prop = self.Properties.Property
		local min = self.Properties.Min
		local max = self.Properties.Max

		for _, other in self.Inputs do
			local value
			if
				other.Definition.Id ~= Definitions.Block.Id
				and (prop == "R" or prop == "G" or prop == "B" or prop == "A")
			then
				value = other.Instance.Color[prop] * 255
			else
				value = other.Properties[prop]
			end
			if not value then
				continue
			end
			if not value then
				continue
			end
			value = tonumber(value)
			if not value then
				continue
			end
			if min < max then
				self.NextState = value >= min and value <= max
			elseif min > max then
				self.NextState = not (value >= max and value <= min)
			else
				self.NextState = value == min
			end
			if self.NextState then
				return
			end
		end

		self.NextState = false
	end,
}

Definitions.GetterE = {
	Id = 17,
	Name = "Getter",
	Bind = Enums.KeyCode.Key8,
	BindShifted = true,
	Color = Color.New(0.78, 0.65, 0.54),
	Properties = { Property = "", Value = 0 },
	Evaluator = function(self: Block)
		local prop = self.Properties.Property
		local val = tostring(self.Properties.Value)
		for _, other in self.Inputs do
			local value
			if
				other.Definition.Id ~= Definitions.Block.Id
				and (prop == "R" or prop == "G" or prop == "B" or prop == "A")
			then
				value = other.Instance.Color[prop] * 255
			else
				value = other.Properties[prop]
			end
			if not value then
				continue
			end
			self.NextState = tostring(value) == val
			if self.NextState then
				return
			end
		end

		self.NextState = false
	end,
}

Definitions.Contains = {
	Id = 18,
	Name = "Contains",
	Bind = Enums.KeyCode.Key9,
	BindShifted = true,
	Color = Color.New(0.64, 0.77, 0.85),
	Properties = { Property = "", Contains = "" },
	Evaluator = function(self: Block)
		local prop = self.Properties.Property
		local contains = tostring(self.Properties.Contains)
		for _, other in self.Inputs do
			local value
			if
				other.Definition.Id ~= Definitions.Block.Id
				and (prop == "R" or prop == "G" or prop == "B" or prop == "A")
			then
				value = tostring(other.Instance.Color[prop] * 255)
			else
				value = tostring(other.Properties[prop])
			end
			if not value then
				continue
			end
			if string.find(value, contains, 1, true) then
				self.NextState = true
				return
			end
		end

		self.NextState = false
	end,
}

Blocks.Definitions = Definitions

return Blocks
