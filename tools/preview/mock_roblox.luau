-- Roblox API 최소 모킹: 서버 빌더 모듈을 luau CLI 로 돌려 파트 목록을 뽑아내기 위한 것
local __ALL = {}

---------------------------------------------------------------- Vector3
local V3 = {}
V3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = v.Magnitude
		if m < 1e-9 then
			return V3.new(0, 0, 0)
		end
		return V3.new(v.X / m, v.Y / m, v.Z / m)
	end
	return V3[k]
end
function V3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end
V3.__add = function(a, b) return V3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return V3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__unm = function(a) return V3.new(-a.X, -a.Y, -a.Z) end
V3.__mul = function(a, b)
	if type(a) == "number" then return V3.new(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return V3.new(a.X * b, a.Y * b, a.Z * b) end
	return V3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then return V3.new(a.X / b, a.Y / b, a.Z / b) end
	return V3.new(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3.__tostring = function(a) return string.format("(%.2f, %.2f, %.2f)", a.X, a.Y, a.Z) end
function V3:Dot(b) return self.X * b.X + self.Y * b.Y + self.Z * b.Z end
function V3:Cross(b) return V3.new(self.Y * b.Z - self.Z * b.Y, self.Z * b.X - self.X * b.Z, self.X * b.Y - self.Y * b.X) end
function V3:Lerp(b, t) return self + (b - self) * t end
V3.xAxis = V3.new(1, 0, 0)
V3.yAxis = V3.new(0, 1, 0)
V3.zAxis = V3.new(0, 0, 1)
V3.zero = V3.new(0, 0, 0)
V3.one = V3.new(1, 1, 1)
Vector3 = V3

local V2 = {}
V2.__index = V2
function V2.new(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V2) end
V2.__add = function(a, b) return V2.new(a.X + b.X, a.Y + b.Y) end
V2.__sub = function(a, b) return V2.new(a.X - b.X, a.Y - b.Y) end
V2.__mul = function(a, b)
	if type(a) == "number" then return V2.new(a * b.X, a * b.Y) end
	if type(b) == "number" then return V2.new(a.X * b, a.Y * b) end
	return V2.new(a.X * b.X, a.Y * b.Y)
end
Vector2 = V2

---------------------------------------------------------------- CFrame (회전 행렬 R[row][col] + 위치)
local CF = {}
local function mat3(r00, r01, r02, r10, r11, r12, r20, r21, r22)
	return { { r00, r01, r02 }, { r10, r11, r12 }, { r20, r21, r22 } }
end
local function mulM(a, b)
	local m = {}
	for i = 1, 3 do
		m[i] = {}
		for j = 1, 3 do
			m[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
		end
	end
	return m
end
local function mulMV(m, v)
	return V3.new(
		m[1][1] * v.X + m[1][2] * v.Y + m[1][3] * v.Z,
		m[2][1] * v.X + m[2][2] * v.Y + m[2][3] * v.Z,
		m[3][1] * v.X + m[3][2] * v.Y + m[3][3] * v.Z
	)
end
local function transpose(m)
	return mat3(m[1][1], m[2][1], m[3][1], m[1][2], m[2][2], m[3][2], m[1][3], m[2][3], m[3][3])
end
local function makeCF(p, R)
	return setmetatable({ p = p, R = R }, CF)
end
CF.__index = function(c, k)
	if k == "Position" then return c.p
	elseif k == "X" then return c.p.X
	elseif k == "Y" then return c.p.Y
	elseif k == "Z" then return c.p.Z
	elseif k == "RightVector" then return V3.new(c.R[1][1], c.R[2][1], c.R[3][1])
	elseif k == "UpVector" then return V3.new(c.R[1][2], c.R[2][2], c.R[3][2])
	elseif k == "LookVector" then return V3.new(-c.R[1][3], -c.R[2][3], -c.R[3][3])
	elseif k == "Rotation" then return makeCF(V3.new(0, 0, 0), c.R)
	end
	return CF[k]
end
function CF.new(x, y, z)
	if x == nil then return makeCF(V3.new(0, 0, 0), mat3(1, 0, 0, 0, 1, 0, 0, 0, 1)) end
	if type(x) == "table" then
		if y ~= nil then return CF.lookAt(x, y) end
		return makeCF(V3.new(x.X, x.Y, x.Z), mat3(1, 0, 0, 0, 1, 0, 0, 0, 1))
	end
	return makeCF(V3.new(x, y, z), mat3(1, 0, 0, 0, 1, 0, 0, 0, 1))
end
function CF.fromAxisAngle(axis, t)
	local u = axis.Unit
	local c, s = math.cos(t), math.sin(t)
	local x, y, z = u.X, u.Y, u.Z
	return makeCF(V3.new(0, 0, 0), mat3(
		c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s,
		y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s,
		z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)
	))
end
function CF.Angles(rx, ry, rz)
	return CF.fromAxisAngle(V3.xAxis, rx) * CF.fromAxisAngle(V3.yAxis, ry) * CF.fromAxisAngle(V3.zAxis, rz)
end
CF.fromEulerAnglesXYZ = CF.Angles
function CF.lookAt(from, to, up)
	up = up or V3.yAxis
	local look = (to - from).Unit
	if math.abs(look:Dot(up.Unit)) > 0.999 then
		up = V3.xAxis
	end
	local zAxis = -look
	local xAxis = up:Cross(zAxis).Unit
	local yAxis = zAxis:Cross(xAxis)
	return makeCF(from, mat3(xAxis.X, yAxis.X, zAxis.X, xAxis.Y, yAxis.Y, zAxis.Y, xAxis.Z, yAxis.Z, zAxis.Z))
end
CF.__mul = function(a, b)
	if getmetatable(b) == V3 then
		return mulMV(a.R, b) + a.p
	end
	return makeCF(mulMV(a.R, b.p) + a.p, mulM(a.R, b.R))
end
function CF:Inverse()
	local Rt = transpose(self.R)
	return makeCF(-mulMV(Rt, self.p), Rt)
end
function CF:ToObjectSpace(other) return self:Inverse() * other end
function CF:ToWorldSpace(other) return self * other end
function CF:PointToWorldSpace(v) return self * v end
function CF:PointToObjectSpace(v) return self:Inverse() * v end
function CF:VectorToWorldSpace(v) return mulMV(self.R, v) end
function CF:GetComponents()
	local R = self.R
	return self.p.X, self.p.Y, self.p.Z, R[1][1], R[1][2], R[1][3], R[2][1], R[2][2], R[2][3], R[3][1], R[3][2], R[3][3]
end
CF.identity = CF.new()
CFrame = CF

---------------------------------------------------------------- Color3 / UDim / Enum / Random
Color3 = {}
function Color3.fromRGB(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end
function Color3.new(r, g, b) return { R = r or 0, G = g or 0, B = b or 0 } end
UDim = { new = function(s, o) return { Scale = s, Offset = o } end }
UDim2 = {
	new = function(sx, ox, sy, oy) return { sx, ox, sy, oy } end,
	fromScale = function(x, y) return { x, 0, y, 0 } end,
	fromOffset = function(x, y) return { 0, x, 0, y } end,
}
NumberSequence = { new = function(...) return { ... } end }
NumberSequenceKeypoint = { new = function(...) return { ... } end }
local function enumProxy(path)
	return setmetatable({ __path = path }, {
		__index = function(t, k)
			local child = enumProxy(path .. "." .. k)
			rawset(t, k, child)
			return child
		end,
		__tostring = function() return path end,
	})
end
Enum = enumProxy("Enum")
Random = {}
Random.__index = Random
function Random.new(seed)
	-- 간단한 xorshift 대신 math.random 을 시드별로 쓰기 위해 상태를 정수로 유지 (32비트 LCG)
	return setmetatable({ s = math.floor((seed or 0) % 2147483647) }, Random)
end
local function nextUnit(self)
	self.s = (self.s * 48271) % 2147483647
	return self.s / 2147483647
end
function Random:NextNumber(a, b)
	local u = nextUnit(self)
	if a == nil then return u end
	return a + (b - a) * u
end
function Random:NextInteger(a, b)
	return a + math.floor(nextUnit(self) * (b - a + 1))
end
function Random:NextUnitVector()
	return V3.new(self:NextNumber(-1, 1), self:NextNumber(-1, 1), self:NextNumber(-1, 1)).Unit
end

---------------------------------------------------------------- Instance
local Inst = {}
Inst.__index = function(t, k)
	local raw = rawget(t, k)
	if raw ~= nil then return raw end
	local v = rawget(t, "__props")[k]
	if v ~= nil then return v end
	return Inst[k]
end
Inst.__newindex = function(t, k, v)
	if k == "Parent" then
		local old = rawget(t, "__props").Parent
		if old then
			for i, c in old.__children do
				if c == t then table.remove(old.__children, i) break end
			end
		end
		if v then table.insert(v.__children, t) end
	end
	rawget(t, "__props")[k] = v
	if k == "CFrame" then
		rawget(t, "__props").Position = v.Position
	elseif k == "Position" and rawget(t, "__props").CFrame == nil then
		rawget(t, "__props").CFrame = CF.new(v)
	elseif k == "Position" then
		local cf = rawget(t, "__props").CFrame
		rawget(t, "__props").CFrame = makeCF(v, cf.R)
	end
end
Instance = {}
local BASEPARTS = { Part = true, WedgePart = true, CornerWedgePart = true, MeshPart = true, SpawnLocation = true, TrussPart = true }
function Instance.new(class, parent)
	local t = setmetatable({ __props = { Name = class, ClassName = class, __children = {} }, __children = {} }, Inst)
	rawget(t, "__props").__children = nil
	if BASEPARTS[class] then
		rawget(t, "__props").Size = V3.new(4, 1, 2)
		rawget(t, "__props").CFrame = CF.new()
		rawget(t, "__props").Position = V3.new(0, 0, 0)
		rawget(t, "__props").Transparency = 0
		rawget(t, "__props").Color = Color3.fromRGB(163, 162, 165)
		rawget(t, "__props").Shape = Enum.PartType.Block
	end
	table.insert(__ALL, t)
	if parent then t.Parent = parent end
	return t
end
function Inst:IsA(class)
	local c = self.ClassName
	if c == class then return true end
	if class == "BasePart" and BASEPARTS[c] then return true end
	if class == "Light" and (c == "PointLight" or c == "SpotLight" or c == "SurfaceLight") then return true end
	return false
end
function Inst:GetChildren() local r = {} for _, c in self.__children do table.insert(r, c) end return r end
function Inst:GetDescendants()
	local r = {}
	local function rec(n) for _, c in n.__children do table.insert(r, c) rec(c) end end
	rec(self)
	return r
end
function Inst:FindFirstChild(name) for _, c in self.__children do if c.Name == name then return c end end return nil end
function Inst:FindFirstChildOfClass(class) for _, c in self.__children do if c.ClassName == class then return c end end return nil end
function Inst:FindFirstChildWhichIsA(class, rec)
	local list = if rec then self:GetDescendants() else self.__children
	for _, c in list do if c:IsA(class) then return c end end
	return nil
end
function Inst:Destroy() self.Parent = nil end
function Inst:Clone() return self end
function Inst:SetAttribute(k, v) rawget(self, "__props")["__attr_" .. k] = v end
function Inst:GetAttribute(k) return rawget(self, "__props")["__attr_" .. k] end
function Inst:PivotTo(cf) self.CFrame = cf end
function Inst:GetPivot() return self.CFrame or CF.new() end

local services = {}
game = {
	GetService = function(_, name)
		services[name] = services[name] or Instance.new(name)
		return services[name]
	end,
}
workspace = Instance.new("Workspace")
task = { spawn = function(f, ...) f(...) end, defer = function(f, ...) f(...) end, delay = function() end, wait = function() end }
__ALL_INSTANCES = __ALL
