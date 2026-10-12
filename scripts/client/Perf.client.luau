local connections = Environment.Connections
local culledConnections = Hidden.CulledConnections

local camera = Environment.CurrentCamera

local cullDistance = 144 ^ 2
local uncullDistance = (144 - 12) ^ 2

local function sqrMag(vector: Vector3)
	return vector:Dot(vector)
end

local lastPos = Vector3.Zero
while wait(1 / 3) do
	local pos = camera.Position
	if sqrMag(lastPos - pos) > 9 then
		lastPos = pos

		for i, conn in connections:GetChildren() do
			local d = pos - conn.Position
			if sqrMag(d) > cullDistance then
				conn.Parent = culledConnections
			end
			if i % 50 == 0 then
				wait()
			end
		end

		local camPos = camera.Position
		for i, conn in culledConnections:GetChildren() do
			local d = camPos - conn.Position
			if sqrMag(d) < uncullDistance then
				conn.Parent = connections
			end
			if i % 50 == 0 then
				wait()
			end
		end
	end
end
