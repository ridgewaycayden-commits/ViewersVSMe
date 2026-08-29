local Workspace = game:GetService("Workspace")

local RailBuilder = {}

local RAIL_THICKNESS = 1

-- Kind-specific visual properties for rail types.
-- Each entry: material, thickness (studs), color (BrickColor name).
local RAIL_KIND_PROPERTIES = {
    rail = { material = Enum.Material.Metal, thickness = 1.5, color = BrickColor.new("Dark grey").Color },
    heavy_rail = { material = Enum.Material.Metal, thickness = 1.5, color = BrickColor.new("Dark grey").Color },
    light_rail = { material = Enum.Material.Metal, thickness = 1.0, color = BrickColor.new("Medium grey").Color },
    tram = { material = Enum.Material.Metal, thickness = 1.0, color = BrickColor.new("Medium grey").Color },
    subway = { material = Enum.Material.Concrete, thickness = 2.0, color = BrickColor.new("Light grey").Color },
    metro = { material = Enum.Material.Concrete, thickness = 2.0, color = BrickColor.new("Light grey").Color },
    narrow_gauge = { material = Enum.Material.Metal, thickness = 0.8, color = BrickColor.new("Dark grey").Color },
}

local DEFAULT_RAIL_PROPERTIES = { material = Enum.Material.Cobblestone, thickness = RAIL_THICKNESS, color = nil }

local function resolveRailKindProperties(kind)
    if kind and RAIL_KIND_PROPERTIES[kind] then
        return RAIL_KIND_PROPERTIES[kind]
    end
    return DEFAULT_RAIL_PROPERTIES
end

local function offsetPoint(point, origin)
    return Vector3.new(point.x + origin.x, point.y + origin.y, point.z + origin.z)
end

local function paintSegment(terrain, p1, p2, width, kindProps)
    local delta = p2 - p1
    local length = delta.Magnitude
    if length < 0.01 then
        return
    end

    local thickness = kindProps.thickness
    local material = kindProps.material

    -- Use per-vertex Y so FillBlock tilts to follow terrain slope.
    local startPos = Vector3.new(p1.X, p1.Y - thickness * 0.5, p1.Z)
    local endPos = Vector3.new(p2.X, p2.Y - thickness * 0.5, p2.Z)
    local midPos = (startPos + endPos) * 0.5
    local cf = CFrame.lookAt(midPos, endPos)
    terrain:FillBlock(cf, Vector3.new(width, thickness, length), material)
end

local function emitAuditRecord(parent, rail, builtSegmentCount)
    if parent == nil or builtSegmentCount <= 0 then
        return
    end
    local record = Instance.new("Configuration")
    local railId = tostring(rail.id or "rail")
    record.Name = "RailAudit_" .. railId
    record:SetAttribute("ArnisRailAuditRecord", true)
    record:SetAttribute("ArnisRailKind", tostring(rail.kind or "unknown"))
    record:SetAttribute("ArnisRailSourceId", railId)
    record:SetAttribute("ArnisRailSegmentCount", builtSegmentCount)
    record:SetAttribute("ArnisRailWidthStuds", tonumber(rail.widthStuds) or 4)
    record.Parent = parent
end

function RailBuilder.BuildAll(parent, rails, originStuds)
    if not rails or #rails == 0 then
        return
    end
    for _, rail in ipairs(rails) do
        RailBuilder.FallbackBuild(parent, rail, originStuds)
    end
end

function RailBuilder.Build(parent, rail, originStuds)
    RailBuilder.FallbackBuild(parent, rail, originStuds)
end

function RailBuilder.FallbackBuild(parent, rail, originStuds)
    local terrain = Workspace.Terrain
    local width = rail.widthStuds or 4
    local kindProps = resolveRailKindProperties(rail.kind)
    local builtSegmentCount = 0
    for i = 1, #rail.points - 1 do
        local p1 = offsetPoint(rail.points[i], originStuds)
        local p2 = offsetPoint(rail.points[i + 1], originStuds)
        paintSegment(terrain, p1, p2, width, kindProps)
        builtSegmentCount += 1
    end
    emitAuditRecord(parent, rail, builtSegmentCount)
end

return RailBuilder
