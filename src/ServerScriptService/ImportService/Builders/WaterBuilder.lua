local AssetService = game:GetService("AssetService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local GroundSampler = require(script.Parent.Parent.GroundSampler)
local PolygonBatcher = require(script.Parent.Parent.PolygonBatcher)
local _Logger = require(ReplicatedStorage.Shared.Logger)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local WaterBuilder = {}

-- Water fills 2 studs deep from the surface so it looks like a body of water.
local WATER_DEPTH = 2
-- How many studs below the water surface to carve terrain.
local CARVE_DEPTH = WorldConfig.WaterCarveDepth or 4

local function getWaterDetailParent(parent)
    local detailFolder = parent:FindFirstChild("Detail")
    if detailFolder then
        return detailFolder
    end

    detailFolder = Instance.new("Folder")
    detailFolder.Name = "Detail"
    detailFolder:SetAttribute("ArnisLodGroupKind", "detail")
    CollectionService:AddTag(detailFolder, "LOD_DetailGroup")
    detailFolder.Parent = parent
    return detailFolder
end

local DEFAULT_WATER_COLOR = Color3.fromRGB(40, 80, 120)

-- Per-kind visual defaults.  Manifest `color` field always takes priority.
local WATER_KIND_PROPERTIES = {
    -- Rivers/streams/canals: shallower, more reflective, slightly lighter blue
    river = { color = Color3.fromRGB(55, 100, 140), transparency = 0.45, reflectance = 0.35 },
    stream = { color = Color3.fromRGB(55, 100, 140), transparency = 0.45, reflectance = 0.35 },
    canal = { color = Color3.fromRGB(55, 100, 140), transparency = 0.45, reflectance = 0.35 },
    -- Lakes/reservoirs/basins: deeper, darker blue, higher reflectance
    lake = { color = Color3.fromRGB(30, 60, 105), transparency = 0.35, reflectance = 0.40 },
    reservoir = { color = Color3.fromRGB(30, 60, 105), transparency = 0.35, reflectance = 0.40 },
    basin = { color = Color3.fromRGB(30, 60, 105), transparency = 0.35, reflectance = 0.40 },
    -- Ponds: greener tint, default transparency
    pond = { color = Color3.fromRGB(45, 85, 100), transparency = 0.40, reflectance = 0.35 },
    -- Wetlands/marsh/swamp: dark green-brown, murky
    wetland = { color = Color3.fromRGB(55, 70, 55), transparency = 0.25, reflectance = 0.15 },
    marsh = { color = Color3.fromRGB(55, 70, 55), transparency = 0.25, reflectance = 0.15 },
    swamp = { color = Color3.fromRGB(55, 70, 55), transparency = 0.25, reflectance = 0.15 },
}
WaterBuilder.WATER_KIND_PROPERTIES = WATER_KIND_PROPERTIES

local function resolveKindProperties(water)
    -- Prefer the more specific waterType (from OSM `water` tag) over the
    -- generic kind field.  Both map into the same WATER_KIND_PROPERTIES table.
    local waterType = water and water.waterType
    if type(waterType) == "string" and waterType ~= "" then
        local props = WATER_KIND_PROPERTIES[waterType]
        if props then
            return props
        end
    end
    local kind = water and water.kind
    if type(kind) == "string" and kind ~= "" then
        return WATER_KIND_PROPERTIES[kind]
    end
    return nil
end

local function resolveWaterColor(colorField, kindProps)
    if type(colorField) == "table" and type(colorField.r) == "number" then
        return Color3.fromRGB(
            math.clamp(tonumber(colorField.r) or 0, 0, 255),
            math.clamp(tonumber(colorField.g) or 0, 0, 255),
            math.clamp(tonumber(colorField.b) or 0, 0, 255)
        )
    end
    if kindProps and kindProps.color then
        return kindProps.color
    end
    return DEFAULT_WATER_COLOR
end

local function createWaterSurface(parent, cframe, size, name, surfaceType, waterKind, waterId, waterColor, kindProps)
    local surface = Instance.new("Part")
    surface.Name = name or "WaterSurface"
    surface.Size = size
    surface.CFrame = cframe
    surface.Material = Enum.Material.Glass
    -- Per-body color from manifest (lake/river/pond differentiation), falling
    -- back to a cool dark hue that gives the Cesium 3D / Google Earth sky-mirror
    -- sheen on still bodies. Per-kind transparency overrides wetlands/rivers.
    surface.Color = waterColor or Color3.fromRGB(34, 70, 110)
    surface.Transparency = (kindProps and kindProps.transparency) or 0.34
    surface:SetAttribute("BaseTransparency", surface.Transparency)
    surface:SetAttribute("ArnisBaseTransparency", surface.Transparency)
    if type(surfaceType) == "string" and surfaceType ~= "" then
        surface:SetAttribute("ArnisWaterSurfaceType", surfaceType)
    end
    if type(waterKind) == "string" and waterKind ~= "" then
        surface:SetAttribute("ArnisWaterKind", waterKind)
    end
    if type(waterId) == "string" and waterId ~= "" then
        surface:SetAttribute("ArnisWaterSourceId", waterId)
    end
    surface.Reflectance = (kindProps and kindProps.reflectance) or 0.5
    surface.Anchored = true
    surface.CanCollide = false
    surface.CastShadow = false
    surface.Parent = parent
    CollectionService:AddTag(surface, "LOD_Detail")
    return surface
end

local function offsetPoint(point, origin)
    return Vector3.new(point.x + origin.x, point.y + origin.y, point.z + origin.z)
end

local function resolveWaterSurfaceY(water, fallbackY, _chunk, _worldX, _worldZ)
    if water.surfaceY then
        return water.surfaceY
    end
    return fallbackY
end

local function estimatePolygonSurfaceY(chunk, worldPts, sampleGroundY)
    if not worldPts or #worldPts == 0 then
        return (chunk and chunk.originStuds and chunk.originStuds.y) or 0
    end

    local minGroundY = math.huge
    local sumX = 0
    local sumZ = 0
    for _, point in ipairs(worldPts) do
        local groundY = sampleGroundY(point.X, point.Z)
        if groundY < minGroundY then
            minGroundY = groundY
        end
        sumX += point.X
        sumZ += point.Z
    end

    local centroidGroundY = sampleGroundY(sumX / #worldPts, sumZ / #worldPts)
    return math.min(minGroundY, centroidGroundY)
end

-- Paint a ribbon water feature (river/stream) into terrain.
local function paintRibbonSegment(terrain, p1, p2, width, waterMaterial)
    local delta = p2 - p1
    local length = delta.Magnitude
    if length < 0.01 then
        return
    end

    -- Use per-vertex Y so FillBlock tilts to follow the river's slope.
    local startPos = Vector3.new(p1.X, p1.Y - WATER_DEPTH * 0.5, p1.Z)
    local endPos = Vector3.new(p2.X, p2.Y - WATER_DEPTH * 0.5, p2.Z)
    local midPos = (startPos + endPos) * 0.5
    local cf = CFrame.lookAt(midPos, endPos)
    terrain:FillBlock(cf, Vector3.new(width, WATER_DEPTH, length), waterMaterial or Enum.Material.Water)
end

-- Carve a channel of Air below a ribbon water segment.
local function carveRibbonChannel(terrain, p1, p2, width)
    local delta = p2 - p1
    local length = delta.Magnitude
    if length < 0.01 then
        return
    end

    -- Use per-vertex Y so the carved channel follows terrain slope.
    local startPos = Vector3.new(p1.X, p1.Y - WATER_DEPTH - CARVE_DEPTH * 0.5, p1.Z)
    local endPos = Vector3.new(p2.X, p2.Y - WATER_DEPTH - CARVE_DEPTH * 0.5, p2.Z)
    local midPos = (startPos + endPos) * 0.5
    local cf = CFrame.lookAt(midPos, endPos)
    terrain:FillBlock(cf, Vector3.new(width, CARVE_DEPTH, length), Enum.Material.Air)
end

local function mergeRibbonSegments(points, width, material)
    local merged = {}
    local active = nil

    local function canMerge(current, nextSegment)
        local currentDir = (current.p2 - current.p1).Unit
        local nextDir = (nextSegment.p2 - nextSegment.p1).Unit
        if currentDir:Dot(nextDir) < 0.999 then
            return false
        end
        if math.abs(current.width - nextSegment.width) > 1e-6 or current.material ~= nextSegment.material then
            return false
        end
        return (current.p2 - nextSegment.p1).Magnitude <= 1e-6
    end

    for i = 1, #points - 1 do
        local nextSegment = {
            p1 = points[i],
            p2 = points[i + 1],
            width = width,
            material = material,
        }
        if (nextSegment.p2 - nextSegment.p1).Magnitude < 0.01 then
            continue
        end
        if active and canMerge(active, nextSegment) then
            active.p2 = nextSegment.p2
        else
            if active then
                merged[#merged + 1] = active
            end
            active = nextSegment
        end
    end

    if active then
        merged[#merged + 1] = active
    end

    return merged
end

-- Scanline polygon rasterisation: fills the actual polygon shape row by row.
-- material defaults to Water; pass Enum.Material.LeafyGrass etc. to cut islands.
local SCAN_STEP = 4 -- studs resolution per scanline row

local function getPointXZ(point)
    if point == nil then
        return nil, nil
    end

    local x = point.X
    if x == nil then
        x = point.x
    end

    local z = point.Z
    if z == nil then
        z = point.z
    end

    return x, z
end

local function buildPolygonSegmentsForRow(worldPts, z)
    local xs = table.create(#worldPts)
    for i = 1, #worldPts do
        local p1 = worldPts[i]
        local p2 = worldPts[(i % #worldPts) + 1]
        local x1, z1 = getPointXZ(p1)
        local x2, z2 = getPointXZ(p2)
        if x1 == nil or z1 == nil or x2 == nil or z2 == nil then
            continue
        end
        if (z1 <= z and z < z2) or (z2 <= z and z < z1) then
            local t = (z - z1) / (z2 - z1)
            table.insert(xs, x1 + t * (x2 - x1))
        end
    end
    table.sort(xs)

    local segments = {}
    local i = 1
    while i + 1 <= #xs do
        local x0, x1 = xs[i], xs[i + 1]
        if x1 - x0 > 0.1 then
            segments[#segments + 1] = { x0 = x0, x1 = x1 }
        end
        i += 2
    end
    return segments
end

local function subtractCutSegments(outerSegments, cutSegments)
    if #cutSegments == 0 then
        return outerSegments
    end

    table.sort(cutSegments, function(a, b)
        if a.x0 == b.x0 then
            return a.x1 < b.x1
        end
        return a.x0 < b.x0
    end)

    local result = {}
    for _, outer in ipairs(outerSegments) do
        local fragments = { {
            x0 = outer.x0,
            x1 = outer.x1,
        } }

        for _, cut in ipairs(cutSegments) do
            local nextFragments = {}
            for _, fragment in ipairs(fragments) do
                if cut.x1 <= fragment.x0 or cut.x0 >= fragment.x1 then
                    nextFragments[#nextFragments + 1] = fragment
                else
                    if cut.x0 > fragment.x0 then
                        nextFragments[#nextFragments + 1] = {
                            x0 = fragment.x0,
                            x1 = math.min(cut.x0, fragment.x1),
                        }
                    end
                    if cut.x1 < fragment.x1 then
                        nextFragments[#nextFragments + 1] = {
                            x0 = math.max(cut.x1, fragment.x0),
                            x1 = fragment.x1,
                        }
                    end
                end
            end
            fragments = nextFragments
            if #fragments == 0 then
                break
            end
        end

        for _, fragment in ipairs(fragments) do
            if fragment.x1 - fragment.x0 > 0.1 then
                result[#result + 1] = fragment
            end
        end
    end

    return result
end

local function buildPolygonRows(worldPts, stripDepth, holePtsList)
    if #worldPts < 3 then
        return {}
    end

    local minZ, maxZ = math.huge, -math.huge
    for _, p in ipairs(worldPts) do
        local _x, pointZ = getPointXZ(p)
        if pointZ ~= nil then
            minZ = math.min(minZ, pointZ)
            maxZ = math.max(maxZ, pointZ)
        end
    end

    if minZ == math.huge or maxZ == -math.huge then
        return {}
    end

    local rows = {}
    local z = minZ + stripDepth * 0.5
    while z <= maxZ do
        local segments = buildPolygonSegmentsForRow(worldPts, z)
        if holePtsList and #holePtsList > 0 and #segments > 0 then
            local holeSegments = {}
            for _, holePts in ipairs(holePtsList) do
                for _, holeSegment in ipairs(buildPolygonSegmentsForRow(holePts, z)) do
                    holeSegments[#holeSegments + 1] = holeSegment
                end
            end
            segments = subtractCutSegments(segments, holeSegments)
        end

        if #segments > 0 then
            rows[#rows + 1] = {
                z = z,
                segments = segments,
            }
        end
        z += stripDepth
    end

    return rows
end

local function emitPolygonWaterSurfaces(
    detailParent,
    worldPts,
    surfaceY,
    holePtsList,
    waterKind,
    waterId,
    waterColor,
    kindProps
)
    local rows = buildPolygonRows(worldPts, SCAN_STEP, holePtsList)
    for index, rect in ipairs(PolygonBatcher.BuildRectsFromRows(rows, SCAN_STEP)) do
        createWaterSurface(
            detailParent,
            CFrame.new(rect.centerX, surfaceY + 0.05, rect.centerZ),
            Vector3.new(rect.width, 0.1, rect.depth),
            string.format("PolygonWaterSurface_%d", index),
            "polygon",
            waterKind,
            waterId,
            waterColor,
            kindProps
        )
    end
end

local function paintPolygonScanline(terrain, worldPts, cy, material)
    material = material or Enum.Material.Water
    for _, rect in ipairs(PolygonBatcher.BuildRects(worldPts, SCAN_STEP)) do
        terrain:FillBlock(
            CFrame.new(rect.centerX, cy, rect.centerZ),
            Vector3.new(rect.width, WATER_DEPTH, rect.depth),
            material
        )
    end
end

-- Carve Air below a polygon water footprint using the same scanline approach.
-- Skips cells that fall inside any of the island hole polygons so that
-- islands remain solid terrain.
local function carvePolygonBelow(terrain, worldPts, surfaceY, holePtsList)
    if #worldPts < 3 then
        return
    end

    -- Carve block starts just below the water surface.
    local carveSurfaceY = surfaceY - WATER_DEPTH
    local carveHeight = CARVE_DEPTH
    local carveCenterY = carveSurfaceY - carveHeight * 0.5

    local rows = buildPolygonRows(worldPts, SCAN_STEP, holePtsList)
    for _, rect in ipairs(PolygonBatcher.BuildRectsFromRows(rows, SCAN_STEP)) do
        terrain:FillBlock(
            CFrame.new(rect.centerX, carveCenterY, rect.centerZ),
            Vector3.new(rect.width, carveHeight, rect.depth),
            Enum.Material.Air
        )
    end
end

-- Telemetry counters for precomputed vs runtime water mesh generation.
local waterMeshTelemetry = {
    precomputedMeshCount = 0,
    runtimeMeshCount = 0,
}

function WaterBuilder.GetMeshTelemetry()
    return {
        precomputedMeshCount = waterMeshTelemetry.precomputedMeshCount,
        runtimeMeshCount = waterMeshTelemetry.runtimeMeshCount,
    }
end

function WaterBuilder.ResetMeshTelemetry()
    waterMeshTelemetry.precomputedMeshCount = 0
    waterMeshTelemetry.runtimeMeshCount = 0
end

--- Load a Rust pre-computed water mesh (flat arrays) into a single MeshPart.
--- waterMesh = { vertices = {x,y,z,...}, triangles = {v0,v1,v2,...}, normals = {nx,ny,nz,...} }
--- originStuds = Vector3 chunk origin to convert from chunk-local to world space.
--- Rust triangle indices are 0-based; Roblox EditableMesh vertex refs are 1-based.
function WaterBuilder.BuildPrecomputedMesh(parent, water, originStuds)
    local waterMesh = water.waterMesh
    if not waterMesh then
        return false
    end

    local verts = waterMesh.vertices
    local tris = waterMesh.triangles
    local norms = waterMesh.normals
    if not verts or not tris or #verts < 9 or #tris < 3 then
        return false
    end

    local meshOk, mesh = pcall(function()
        return AssetService:CreateEditableMesh()
    end)
    if not meshOk or not mesh then
        warn("[WaterBuilder] CreateEditableMesh failed: " .. tostring(mesh))
        return false
    end

    -- Accept both JSON-decoded manifest origins (lowercase {x,y,z}) and
    -- Roblox Vector3 origins (uppercase {X,Y,Z}). Under the lazy external
    -- fetcher chunks are passed through directly from the manifest JSON.
    local ox = originStuds.X or originStuds.x or 0
    local oy = originStuds.Y or originStuds.y or 0
    local oz = originStuds.Z or originStuds.z or 0
    -- Truncate to whole triples so malformed meshes can't crash with
    -- "attempt to perform arithmetic on number and nil".
    local vertsLen = math.floor(#verts / 3) * 3
    local trisLen = math.floor(#tris / 3) * 3
    local vertexCountOut = vertsLen / 3
    local vertexIds = table.create(vertexCountOut)
    -- Load vertices (every 3 floats = one Vector3) with origin offset
    for i = 1, vertsLen, 3 do
        local vi = (i - 1) / 3 + 1
        local pos = Vector3.new(
            (verts[i] or 0) + ox,
            (verts[i + 1] or 0) + oy,
            (verts[i + 2] or 0) + oz
        )
        vertexIds[vi] = mesh:AddVertex(pos)
        -- Set normals if available
        if norms and #norms >= i + 2 and norms[i] and norms[i + 1] and norms[i + 2] then
            pcall(function()
                mesh:SetVertexNormal(vertexIds[vi], Vector3.new(norms[i], norms[i + 1], norms[i + 2]))
            end)
        end
    end

    -- Load triangles (convert 0-based Rust indices to 1-based). Skip any
    -- triangle whose indices are nil or out of range of the vertices we
    -- actually materialized.
    for i = 1, trisLen, 3 do
        local a = tris[i]
        local b = tris[i + 1]
        local c = tris[i + 2]
        if a ~= nil and b ~= nil and c ~= nil
            and a >= 0 and a < vertexCountOut
            and b >= 0 and b < vertexCountOut
            and c >= 0 and c < vertexCountOut
        then
            local v1 = vertexIds[a + 1]
            local v2 = vertexIds[b + 1]
            local v3 = vertexIds[c + 1]
            if v1 and v2 and v3 then
                mesh:AddTriangle(v1, v2, v3)
            end
        end
    end

    local partOk, part = pcall(function()
        return AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
    end)
    if not partOk or not part then
        warn("[WaterBuilder] CreateMeshPartAsync failed: " .. tostring(part))
        return false
    end

    -- Resolve kind-specific visual defaults
    local kindProps = resolveKindProperties(water)
    local waterColor = resolveWaterColor(water.color, kindProps)

    part.Name = "WaterMesh_precomputed"
    part.Material = Enum.Material.Glass
    part.Color = waterColor
    part.Transparency = (kindProps and kindProps.transparency) or 0.4
    part.Reflectance = (kindProps and kindProps.reflectance) or 0.35
    part.Anchored = true
    part.CanCollide = false
    part.CastShadow = false
    if type(water.kind) == "string" and water.kind ~= "" then
        part:SetAttribute("ArnisWaterKind", water.kind)
    end
    if type(water.id) == "string" and water.id ~= "" then
        part:SetAttribute("ArnisWaterSourceId", water.id)
    end
    part:SetAttribute("ArnisPrecomputedMesh", true)
    CollectionService:AddTag(part, "LOD_Detail")
    part.Parent = parent

    return true
end

function WaterBuilder.BuildAll(parent, waters, originStuds, chunk)
    if not waters or #waters == 0 then
        return
    end
    local sampleGroundY = if chunk and chunk.terrain then GroundSampler.createRenderedSurfaceSampler(chunk) else nil
    for _, water in ipairs(waters) do
        WaterBuilder.Build(parent, water, originStuds, chunk, sampleGroundY)
    end
end

function WaterBuilder.Build(parent, water, originStuds, chunk, sampleGroundY)
    -- Fast path: use pre-computed mesh from Rust pipeline if available
    if water.waterMesh then
        local ok = WaterBuilder.BuildPrecomputedMesh(parent, water, originStuds)
        if ok then
            waterMeshTelemetry.precomputedMeshCount += 1
            return
        end
    end
    waterMeshTelemetry.runtimeMeshCount += 1
    WaterBuilder.FallbackBuild(parent, water, originStuds, chunk, sampleGroundY)
end

function WaterBuilder.FallbackBuild(parent, water, originStuds, chunk, sampleGroundY)
    local terrain = Workspace.Terrain
    sampleGroundY = sampleGroundY or GroundSampler.createRenderedSurfaceSampler(chunk)
    -- Resolve kind-specific visual defaults (color/transparency/reflectance).
    -- Per-body `color` from the manifest always takes priority over kind defaults.
    local kindProps = resolveKindProperties(water)
    -- Intermittent water bodies (seasonal streambeds) render as dry sand
    local waterMaterial = Enum.Material.Water
    if water.intermittent then
        waterMaterial = Enum.Material.Sand
    end
    if water.points then
        local width = water.widthStuds or 8
        local resolvedPoints = table.create(#water.points)
        for i = 1, #water.points do
            local point = offsetPoint(water.points[i], originStuds)
            local surfaceY = resolveWaterSurfaceY(water, point.Y, chunk, point.X, point.Z)
            resolvedPoints[i] = Vector3.new(point.X, surfaceY, point.Z)
        end

        local detailParent = nil
        if not water.intermittent then
            detailParent = getWaterDetailParent(parent)
        end

        for _, segment in ipairs(mergeRibbonSegments(resolvedPoints, width, waterMaterial)) do
            local p1 = segment.p1
            local p2 = segment.p2
            local surfaceY1 = resolveWaterSurfaceY(water, p1.Y, chunk, p1.X, p1.Z)
            local surfaceY2 = resolveWaterSurfaceY(water, p2.Y, chunk, p2.X, p2.Z)
            local resolvedP1 = Vector3.new(p1.X, surfaceY1, p1.Z)
            local resolvedP2 = Vector3.new(p2.X, surfaceY2, p2.Z)
            paintRibbonSegment(terrain, resolvedP1, resolvedP2, segment.width, segment.material)
            -- Carve terrain below the ribbon channel after placing water material.
            carveRibbonChannel(terrain, resolvedP1, resolvedP2, segment.width)
            if detailParent then
                local delta = resolvedP2 - resolvedP1
                local segmentLength = delta.Magnitude
                if segmentLength >= 0.01 then
                    -- Use per-vertex Y so the surface Part tilts to follow river slope.
                    local startSurf = Vector3.new(resolvedP1.X, surfaceY1 + 0.05, resolvedP1.Z)
                    local endSurf = Vector3.new(resolvedP2.X, surfaceY2 + 0.05, resolvedP2.Z)
                    local midSurf = (startSurf + endSurf) * 0.5
                    createWaterSurface(
                        detailParent,
                        CFrame.lookAt(midSurf, endSurf),
                        Vector3.new(segment.width, 0.1, segmentLength),
                        "RibbonWaterSurface",
                        "ribbon",
                        water.kind,
                        water.id,
                        resolveWaterColor(water.color, kindProps),
                        kindProps
                    )
                end
            end
        end
    elseif water.footprint and #water.footprint >= 3 then
        -- Build world-space point array
        local worldPts = table.create(#water.footprint)
        for _, p in ipairs(water.footprint) do
            table.insert(worldPts, Vector3.new(p.x + originStuds.x, 0, p.z + originStuds.z))
        end
        local surfaceY = water.surfaceY or estimatePolygonSurfaceY(chunk, worldPts, sampleGroundY)
        local cy = surfaceY - WATER_DEPTH * 0.5
        -- Scanline fill for accurate polygon shape
        paintPolygonScanline(terrain, worldPts, cy, waterMaterial)
        -- Restore islands: fill inner rings (holes) with terrain
        local holePtsList = nil
        if water.holes then
            holePtsList = table.create(#water.holes)
            for _, hole in ipairs(water.holes) do
                if #hole >= 3 then
                    local holePtsV3 = table.create(#hole)
                    for _, p in ipairs(hole) do
                        local wx = p.x + originStuds.x
                        local wz = p.z + originStuds.z
                        table.insert(holePtsV3, Vector3.new(wx, cy, wz))
                    end
                    paintPolygonScanline(terrain, holePtsV3, cy, Enum.Material.LeafyGrass)
                    table.insert(holePtsList, holePtsV3)
                end
            end
        end
        -- Carve terrain below water surface after placing water material.
        -- Island polygons (holes) are excluded so they stay solid.
        carvePolygonBelow(terrain, worldPts, surfaceY, holePtsList)
        if not water.intermittent then
            emitPolygonWaterSurfaces(
                getWaterDetailParent(parent),
                worldPts,
                surfaceY,
                holePtsList,
                water.kind,
                water.id,
                resolveWaterColor(water.color, kindProps),
                kindProps
            )
        end
    end
end

return WaterBuilder
