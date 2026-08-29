local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local WorldConfig = require(game:GetService("ReplicatedStorage").Shared.WorldConfig)
local GeoUtils = require(script.Parent.Parent.GeoUtils)

-- Binary mesh decode: base64 → buffer → Lua table.
-- ~60% smaller than JSON float arrays over the wire. The Rust pipeline
-- emits `verticesB64`, `trianglesB64`, `normalsB64` as base64-encoded
-- little-endian binary alongside the legacy JSON arrays.
local function decodeF32Array(b64str)
    if type(b64str) ~= "string" or #b64str == 0 then
        return nil
    end
    local ok, raw = pcall(function()
        return EncodingService:Base64Decode(b64str)
    end)
    if not ok or not raw then
        return nil
    end
    local buf = buffer.fromstring(raw)
    local len = buffer.len(buf)
    local count = math.floor(len / 4)
    local result = table.create(count)
    for i = 0, count - 1 do
        result[i + 1] = buffer.readf32(buf, i * 4)
    end
    return result
end

local function decodeU32Array(b64str)
    if type(b64str) ~= "string" or #b64str == 0 then
        return nil
    end
    local ok, raw = pcall(function()
        return EncodingService:Base64Decode(b64str)
    end)
    if not ok or not raw then
        return nil
    end
    local buf = buffer.fromstring(raw)
    local len = buffer.len(buf)
    local count = math.floor(len / 4)
    local result = table.create(count)
    for i = 0, count - 1 do
        result[i + 1] = buffer.readu32(buf, i * 4)
    end
    return result
end

local BuildingBuilder = {}
local editableMeshSetVertexNormalSupported = nil
local doubleSidedCapabilityWarningIssued = false

local function markShellWallEvidence(part)
    part:SetAttribute("ArnisShellWallEvidence", true)
end

local function applyDebugRoofColor(part)
    if WorldConfig.DebugBuildingColors then
        part.Color = Color3.fromRGB(0, 0, 255)
        part.Transparency = 0
    end
end

local function trySetModelLevelOfDetail(model, levelOfDetail)
    pcall(function()
        model.LevelOfDetail = levelOfDetail
    end)
end

local function tryEnableDoubleSided(part, builderLabel)
    local ok, err = pcall(function()
        part.DoubleSided = true
    end)
    if ok or doubleSidedCapabilityWarningIssued then
        return ok
    end
    doubleSidedCapabilityWarningIssued = true
    warn(("[%s] DoubleSided unavailable in this runtime: %s"):format(builderLabel, tostring(err)))
    return false
end

BuildingBuilder._fillTerrainBlock = function(cf, size, material)
    Workspace.Terrain:FillBlock(cf, size, material)
end

local function trySetVertexNormal(mesh, vertexId, normal)
    if editableMeshSetVertexNormalSupported == false then
        return
    end

    local ok, err = pcall(function()
        mesh:SetVertexNormal(vertexId, normal)
    end)
    if ok then
        if editableMeshSetVertexNormalSupported ~= true then
            editableMeshSetVertexNormalSupported = true
            print("[MeshAccumulator] SetVertexNormal: SUPPORTED")
        end
    else
        if editableMeshSetVertexNormalSupported ~= false then
            editableMeshSetVertexNormalSupported = false
            warn("[MeshAccumulator] SetVertexNormal: NOT SUPPORTED — " .. tostring(err))
            warn("[MeshAccumulator] All mesh normals will use auto-computed defaults. This may cause invisible faces.")
        end
    end
end

-------------------------------------------------------------------------------
-- MeshAccumulator: batches quads/triangles and flushes to EditableMesh when
-- approaching the 20K triangle limit. One accumulator per (material, color).
-------------------------------------------------------------------------------
local MeshAccumulator = {}
MeshAccumulator.__index = MeshAccumulator

function MeshAccumulator.new(parent, materialName, material, color, options)
    local self = setmetatable({}, MeshAccumulator)
    options = options or {}
    self.parent = parent
    self.materialName = materialName
    self.material = material
    self.color = color
    self.canCollide = options.canCollide
    self.canQuery = options.canQuery
    self.castShadow = options.castShadow
    self.transparency = options.transparency
    self.reflectance = options.reflectance
    self.collisionFidelity = options.collisionFidelity
    self.vertices = table.create(18000 * 2) -- pre-allocate for max batch
    self.normals = table.create(18000 * 2)
    self.triangles = table.create(18000)
    self.uvs = table.create(18000 * 2) -- per-vertex [u,v] from atlas-mapped walls
    self.uvCount = 0
    -- Cached logical lengths for the buffers above. Hot addQuad/addTriangle
    -- paths previously hit `#self.triangles` / `#self.vertices` up to four
    -- times per call; caching integers in locals shaves the length-operator
    -- work. Combined with `table.clear` in :flush this also lets the
    -- pre-allocated arrays be reused across batches instead of being replaced
    -- with fresh empty tables every flush (the prior code's `self.vertices =
    -- {}` reset threw away the 36000-slot capacity on the very first flush).
    self.vertexCount = 0
    self.triangleCount = 0
    self.meshCount = 0
    self.totalVertexCount = 0
    self.totalTriangleCount = 0
    self.totalMeshCreateMs = 0
    self.MAX_TRIANGLES = 18000 -- headroom below 20K API limit
    return self
end

function MeshAccumulator:addQuad(p1, p2, p3, p4, normal)
    local triangleCount = self.triangleCount
    if triangleCount + 2 > self.MAX_TRIANGLES then
        self:flush()
        triangleCount = self.triangleCount
    end

    local vertices = self.vertices
    local normals = self.normals
    local base = self.vertexCount
    vertices[base + 1] = p1
    vertices[base + 2] = p2
    vertices[base + 3] = p3
    vertices[base + 4] = p4
    normals[base + 1] = normal
    normals[base + 2] = normal
    normals[base + 3] = normal
    normals[base + 4] = normal
    self.vertexCount = base + 4

    -- Standard winding: {1,2,3} and {1,3,4}. Auto-normals computed by Roblox
    -- from triangle winding (SetVertexNormal not available on this version).
    local triangles = self.triangles
    triangles[triangleCount + 1] = { base + 1, base + 2, base + 3 }
    triangles[triangleCount + 2] = { base + 1, base + 3, base + 4 }
    self.triangleCount = triangleCount + 2
end

function MeshAccumulator:addTriangle(p1, p2, p3, normal)
    local triangleCount = self.triangleCount
    if triangleCount + 1 > self.MAX_TRIANGLES then
        self:flush()
        triangleCount = self.triangleCount
    end

    local base = self.vertexCount
    self.vertices[base + 1] = p1
    self.vertices[base + 2] = p2
    self.vertices[base + 3] = p3
    self.normals[base + 1] = normal
    self.normals[base + 2] = normal
    self.normals[base + 3] = normal
    self.vertexCount = base + 3

    self.triangles[triangleCount + 1] = { base + 1, base + 2, base + 3 }
    self.triangleCount = triangleCount + 1
end

--- Load a Rust pre-computed mesh (flat arrays) into this accumulator.
--- meshData = { vertices = {x,y,z,...}, triangles = {v0,v1,v2,...}, normals = {nx,ny,nz,...} }
--- originStuds = Vector3 chunk origin to convert from chunk-local to world space.
--- Rust triangle indices are 0-based; accumulator vertex refs are 1-based.
function MeshAccumulator:addPrecomputedMesh(meshData, originStuds)
    -- Prefer binary base64 encoding (60% smaller over the wire).
    -- Falls back to legacy JSON arrays for old manifests.
    local verts = decodeF32Array(meshData.verticesB64) or meshData.vertices
    local tris = decodeU32Array(meshData.trianglesB64) or meshData.triangles
    local norms = decodeF32Array(meshData.normalsB64) or meshData.normals
    if not verts or not tris or #verts < 3 or #tris < 3 then
        return
    end
    -- Truncate to whole triples so a malformed mesh (e.g. a shellMesh with
    -- a stray float or a stray triangle index) can't crash the import with
    -- "attempt to perform arithmetic (add) on number and nil". The
    -- oversized-batch path below already uses `or 0` guards for vertex
    -- reads; the fast path needs matching defense.
    local vertsLen = math.floor(#verts / 3) * 3
    local trisLen = math.floor(#tris / 3) * 3
    if vertsLen == 0 or trisLen == 0 then
        return
    end
    local triCount = trisLen / 3
    local normsLen = if norms then #norms else 0
    local defaultNormal = Vector3.new(0, 1, 0)
    -- Atlas UVs: flat [u,v, u,v, ...] array from Rust wall_surface, only
    -- present when the building has an atlas_uv and multi-story windowed walls.
    local meshUvs = decodeF32Array(meshData.uvsB64) or meshData.uvs
    local meshUvsLen = if meshUvs then #meshUvs else 0
    -- Accept both JSON-decoded manifest origins (lowercase {x,y,z}) and
    -- Roblox Vector3 origins (uppercase {X,Y,Z}). Declared once before
    -- the fast/oversized branch so both paths share the same values.
    local ox = originStuds.X or originStuds.x or 0
    local oy = originStuds.Y or originStuds.y or 0
    local oz = originStuds.Z or originStuds.z or 0
    -- If the entire precomputed mesh fits alongside existing buffered data, fast path.
    if self.triangleCount + triCount <= self.MAX_TRIANGLES then
        local base = self.vertexCount
        local vertices = self.vertices
        local normalsArr = self.normals
        local triangles = self.triangles
        local uvsArr = self.uvs
        local vi = base
        local vertexCountOut = vertsLen / 3
        local uvIdx = 0
        for i = 1, vertsLen, 3 do
            vi += 1
            vertices[vi] = Vector3.new(
                (verts[i] or 0) + ox,
                (verts[i + 1] or 0) + oy,
                (verts[i + 2] or 0) + oz
            )
            normalsArr[vi] = if norms and normsLen >= i + 2 and norms[i] and norms[i + 1] and norms[i + 2]
                then Vector3.new(norms[i], norms[i + 1], norms[i + 2])
                else defaultNormal
            -- Load atlas UV for this vertex if available.
            uvIdx += 1
            if meshUvsLen >= uvIdx * 2 then
                local ui = (uvIdx - 1) * 2 + 1
                uvsArr[vi] = Vector2.new(meshUvs[ui] or 0, meshUvs[ui + 1] or 0)
            end
        end
        self.vertexCount = vi
        if meshUvsLen > 0 then
            self.uvCount = vi
        end
        local ti = self.triangleCount
        for i = 1, trisLen, 3 do
            local a = tris[i]
            local b = tris[i + 1]
            local c = tris[i + 2]
            -- Drop any triangle with nil/out-of-range indices; materializing
            -- it would produce garbage vertices and potentially propagate
            -- a nil-index crash into flush() downstream.
            if a ~= nil and b ~= nil and c ~= nil
                and a >= 0 and a < vertexCountOut
                and b >= 0 and b < vertexCountOut
                and c >= 0 and c < vertexCountOut
            then
                ti += 1
                triangles[ti] = { base + a + 1, base + b + 1, base + c + 1 }
            end
        end
        self.triangleCount = ti
        return
    end
    -- Oversized mesh: flush existing, then split into MAX_TRIANGLES batches.
    -- Each triangle references 3 vertices by 0-based index; we load a batch of
    -- triangles, gather only the vertices they reference, and flush each batch.
    self:flush()
    -- Accept both JSON-decoded manifest origins (lowercase {x,y,z}) and
-- Roblox Vector3 origins (uppercase {X,Y,Z}). The external_url lazy
    -- ox/oy/oz already declared above the branch — reuse them here.
    local maxTrisPerBatch = self.MAX_TRIANGLES
    for batchStart = 1, trisLen, maxTrisPerBatch * 3 do
        local batchEnd = math.min(batchStart + maxTrisPerBatch * 3 - 1, trisLen)
        -- Gather unique vertex indices referenced by this batch
        local vertexRemap = {} -- 0-based Rust index → 1-based accumulator index
        local vertices = self.vertices
        local normalsArr = self.normals
        for i = batchStart, batchEnd do
            local rustIdx = tris[i]
            -- rustIdx can be nil if the incoming triangle list has sparse
            -- or truncated entries. Using a nil table key throws, so skip
            -- instead. The triangle-emit loop below mirrors the same guard.
            if rustIdx ~= nil and vertexRemap[rustIdx] == nil then
                local fi = rustIdx * 3 + 1 -- flat array index (1-based)
                local pos = Vector3.new(
                    (verts[fi] or 0) + ox,
                    (verts[fi + 1] or 0) + oy,
                    (verts[fi + 2] or 0) + oz
                )
                local normal = if norms and normsLen >= fi + 2 and norms[fi] and norms[fi + 1] and norms[fi + 2]
                    then Vector3.new(norms[fi], norms[fi + 1], norms[fi + 2])
                    else defaultNormal
                local vi = self.vertexCount + 1
                vertices[vi] = pos
                normalsArr[vi] = normal
                self.vertexCount = vi
                vertexRemap[rustIdx] = vi
            end
        end
        -- Add triangles using remapped indices. Drop any triangle whose
        -- indices failed to remap (nil rustIdx or remap miss).
        local triangles = self.triangles
        local ti = self.triangleCount
        for i = batchStart, batchEnd, 3 do
            local a = tris[i] ~= nil and vertexRemap[tris[i]] or nil
            local b = tris[i + 1] ~= nil and vertexRemap[tris[i + 1]] or nil
            local c = tris[i + 2] ~= nil and vertexRemap[tris[i + 2]] or nil
            if a and b and c then
                ti += 1
                triangles[ti] = { a, b, c }
            end
        end
        self.triangleCount = ti
        -- Flush this batch if there's more data to process
        if batchEnd < trisLen then
            self:flush()
        end
    end
end

function MeshAccumulator:flush()
    if self.triangleCount == 0 then
        return
    end

    local vertexCount = self.vertexCount
    local triangleCount = self.triangleCount

    local meshOk, mesh = pcall(function()
        return AssetService:CreateEditableMesh()
    end)
    if not meshOk or not mesh then
        warn("[MeshAccumulator] CreateEditableMesh failed: " .. tostring(mesh))
        self:flushAsParts()
        return
    end

    -- Add all vertices, then (optionally) set normals via trySetVertexNormal.
    -- Splitting into two loops lets the AddVertex hot loop run tight, and —
    -- more importantly — when the runtime has already latched the support
    -- flag to false we skip the normal-apply loop entirely, saving a pcall
    -- per vertex (previously the dominant cost in flush for large shell
    -- meshes). The first flush on an unknown runtime still probes via
    -- trySetVertexNormal so the latch is established.
    local vertices = self.vertices
    local normals = self.normals
    local vertexIds = table.create(vertexCount)
    for i = 1, vertexCount do
        vertexIds[i] = mesh:AddVertex(vertices[i])
    end
    if editableMeshSetVertexNormalSupported ~= false then
        for i = 1, vertexCount do
            trySetVertexNormal(mesh, vertexIds[i], normals[i])
            -- Probe latched to false on the first call: abort the loop.
            if editableMeshSetVertexNormalSupported == false then
                break
            end
        end
    end

    -- Apply atlas UVs when available.  The uvs array is populated by
    -- addPrecomputedMesh when the Rust shell mesh carries atlas-mapped texture
    -- coordinates. Each vertex with a UV gets SetUV so the chunk atlas
    -- SurfaceAppearance maps correctly onto the wall geometry.
    local uvs = self.uvs
    if self.uvCount > 0 then
        for i = 1, vertexCount do
            if uvs[i] then
                pcall(function()
                    mesh:SetUV(vertexIds[i], uvs[i])
                end)
            end
        end
    end

    -- Add all triangles
    local triangles = self.triangles
    for i = 1, triangleCount do
        local tri = triangles[i]
        mesh:AddTriangle(vertexIds[tri[1]], vertexIds[tri[2]], vertexIds[tri[3]])
    end

    -- Create host MeshPart and apply the mesh
    self.meshCount += 1
    local meshCreateStartedAt = os.clock()
    local createOptions = nil
    if self.collisionFidelity ~= nil then
        createOptions = {
            CollisionFidelity = self.collisionFidelity,
        }
    end
    local partOk, part = pcall(function()
        return if createOptions
            then AssetService:CreateMeshPartAsync(Content.fromObject(mesh), createOptions)
            else AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
    end)
    if not partOk or not part then
        warn("[MeshAccumulator] CreateMeshPartAsync failed: " .. tostring(part))
        self:flushAsParts()
        return
    end
    self.totalMeshCreateMs += (os.clock() - meshCreateStartedAt) * 1000
    self.totalVertexCount += vertexCount
    self.totalTriangleCount += triangleCount
    part.Name = string.format("%s_mesh_%d", self.materialName, self.meshCount)
    part.Material = self.material
    part.Color = self.color
    part.Anchored = true
    part.CanCollide = if self.canCollide == nil then true else self.canCollide
    part.CanQuery = if self.canQuery == nil then true else self.canQuery
    part.CastShadow = if self.castShadow == nil then true else self.castShadow
    tryEnableDoubleSided(part, "MeshAccumulator")
    if self.transparency ~= nil then
        part.Transparency = self.transparency
    end
    if self.reflectance ~= nil then
        part.Reflectance = self.reflectance
    end
    part.Parent = self.parent

    -- Reset buffers for next batch. `table.clear` keeps the pre-allocated
    -- capacity (18000 * 2 slots) so subsequent batches don't re-grow the
    -- arrays from scratch; the cached counters drop back to zero so addQuad
    -- / addTriangle start writing at slot 1.
    table.clear(self.vertices)
    table.clear(self.normals)
    table.clear(self.triangles)
    table.clear(self.uvs)
    self.vertexCount = 0
    self.triangleCount = 0
    self.uvCount = 0
end

-- Fallback: emit simple box Parts when EditableMesh/CreateMeshPartAsync is
-- unavailable (e.g. play-mode permission restrictions).  Each buffered
-- triangle pair is approximated as a flat Part spanning its bounding box.
function MeshAccumulator:flushAsParts()
    local fallbackVertexCount = self.vertexCount
    local fallbackTriangleCount = self.triangleCount
    warn(string.format(
        "[MeshAccumulator] flushAsParts fallback for %s: %d verts, %d tris",
        self.materialName, fallbackVertexCount, fallbackTriangleCount
    ))
    if fallbackVertexCount == 0 then
        return
    end
    self.meshCount += 1
    -- Compute the AABB of the entire buffered geometry
    local minBound = self.vertices[1]
    local maxBound = self.vertices[1]
    for i = 2, fallbackVertexCount do
        local pos = self.vertices[i]
        minBound = Vector3.new(
            math.min(minBound.X, pos.X),
            math.min(minBound.Y, pos.Y),
            math.min(minBound.Z, pos.Z)
        )
        maxBound = Vector3.new(
            math.max(maxBound.X, pos.X),
            math.max(maxBound.Y, pos.Y),
            math.max(maxBound.Z, pos.Z)
        )
    end
    local center = (minBound + maxBound) * 0.5
    local size = maxBound - minBound
    -- Clamp minimum thickness so thin-wall geometry is still visible
    size = Vector3.new(
        math.max(size.X, 0.15),
        math.max(size.Y, 0.15),
        math.max(size.Z, 0.15)
    )
    local part = Instance.new("Part")
    part.Name = string.format("%s_fallback_%d", self.materialName, self.meshCount)
    part.Size = size
    part.CFrame = CFrame.new(center)
    part.Material = self.material
    part.Color = self.color
    part.Anchored = true
    part.CanCollide = if self.canCollide == nil then true else self.canCollide
    part.CanQuery = if self.canQuery == nil then true else self.canQuery
    part.CastShadow = if self.castShadow == nil then true else self.castShadow
    tryEnableDoubleSided(part, "MeshAccumulator")
    if self.transparency ~= nil then
        part.Transparency = self.transparency
    end
    if self.reflectance ~= nil then
        part.Reflectance = self.reflectance
    end
    part.Parent = self.parent

    self.totalVertexCount += fallbackVertexCount
    self.totalTriangleCount += fallbackTriangleCount

    -- Reset buffers (see :flush for rationale on table.clear over `= {}`).
    table.clear(self.vertices)
    table.clear(self.normals)
    table.clear(self.triangles)
    table.clear(self.uvs)
    self.vertexCount = 0
    self.triangleCount = 0
    self.uvCount = 0
end

local function addOrientedBox(acc, center, rightAxis, upAxis, forwardAxis, size)
    -- Pre-flush if the entire box (6 quads × 12 triangles) won't fit atomically.
    if acc.triangleCount + 12 > acc.MAX_TRIANGLES then
        acc:flush()
    end
    local hx = size.X * 0.5
    local hy = size.Y * 0.5
    local hz = size.Z * 0.5
    local right = rightAxis * hx
    local up = upAxis * hy
    local forward = forwardAxis * hz

    local leftBottomBack = center - right - up - forward
    local leftBottomFront = center - right - up + forward
    local leftTopBack = center - right + up - forward
    local leftTopFront = center - right + up + forward
    local rightBottomBack = center + right - up - forward
    local rightBottomFront = center + right - up + forward
    local rightTopBack = center + right + up - forward
    local rightTopFront = center + right + up + forward

    acc:addQuad(leftBottomFront, rightBottomFront, rightTopFront, leftTopFront, forwardAxis)
    acc:addQuad(rightBottomBack, leftBottomBack, leftTopBack, rightTopBack, -forwardAxis)
    acc:addQuad(rightBottomFront, rightBottomBack, rightTopBack, rightTopFront, rightAxis)
    acc:addQuad(leftBottomBack, leftBottomFront, leftTopFront, leftTopBack, -rightAxis)
    acc:addQuad(leftTopFront, rightTopFront, rightTopBack, leftTopBack, upAxis)
    acc:addQuad(leftBottomBack, rightBottomBack, rightBottomFront, leftBottomFront, -upAxis)
end

local WALL_THICKNESS = 0.6 -- studs
local MIN_EDGE = 0.5 -- ignore edges shorter than this
local ROOF_GRID_SIZE = 8
local ROOF_THICKNESS = 0.8

-- Material palette keyed by OSM building usage (used for wall Parts — any Enum.Material valid)
local USAGE_MATERIAL = {
    -- Residential
    residential = Enum.Material.Brick,
    apartments = Enum.Material.Brick,
    house = Enum.Material.WoodPlanks,
    detached = Enum.Material.WoodPlanks,
    terrace = Enum.Material.Brick,
    dormitory = Enum.Material.Brick,
    -- Commercial
    commercial = Enum.Material.Concrete,
    retail = Enum.Material.SmoothPlastic,
    office = Enum.Material.Concrete,
    bank = Enum.Material.Marble,
    supermarket = Enum.Material.Concrete,
    mall = Enum.Material.SmoothPlastic,
    hotel = Enum.Material.Marble,
    -- Civic
    hospital = Enum.Material.SmoothPlastic,
    school = Enum.Material.Brick,
    university = Enum.Material.Limestone,
    civic = Enum.Material.Limestone,
    government = Enum.Material.Limestone,
    courthouse = Enum.Material.Marble,
    -- Industrial
    industrial = Enum.Material.DiamondPlate,
    warehouse = Enum.Material.DiamondPlate,
    factory = Enum.Material.DiamondPlate,
    -- Religious
    religious = Enum.Material.Limestone,
    church = Enum.Material.Cobblestone,
    cathedral = Enum.Material.Cobblestone,
    mosque = Enum.Material.Marble,
    temple = Enum.Material.Sandstone,
    -- Utility
    garage = Enum.Material.DiamondPlate,
    shed = Enum.Material.WoodPlanks,
    barn = Enum.Material.WoodPlanks,
    -- Default
    yes = Enum.Material.Concrete,
    default = Enum.Material.Concrete,
}

-- OSM building:material tag → Roblox material
local MATERIAL_TAG_MAP = {
    brick = Enum.Material.Brick,
    concrete = Enum.Material.Concrete,
    glass = Enum.Material.Glass,
    metal = Enum.Material.Metal,
    steel = Enum.Material.DiamondPlate,
    wood = Enum.Material.WoodPlanks,
    stone = Enum.Material.Cobblestone,
    granite = Enum.Material.Granite,
    limestone = Enum.Material.Limestone,
    sandstone = Enum.Material.Sandstone,
    marble = Enum.Material.Marble,
    plaster = Enum.Material.SmoothPlastic,
    stucco = Enum.Material.SmoothPlastic,
    render = Enum.Material.SmoothPlastic,
    cladding = Enum.Material.DiamondPlate,
    timber_framing = Enum.Material.WoodPlanks,
    tile = Enum.Material.Cobblestone,
}

-- Floor material for Terrain:FillBlock — must be a valid terrain material (no Glass/Metal/Neon)
local USAGE_FLOOR_MATERIAL = {
    -- Residential
    residential = Enum.Material.Brick,
    apartments = Enum.Material.Brick,
    house = Enum.Material.Brick,
    detached = Enum.Material.Brick,
    terrace = Enum.Material.Brick,
    dormitory = Enum.Material.Brick,
    -- Commercial
    commercial = Enum.Material.Concrete,
    retail = Enum.Material.Concrete,
    office = Enum.Material.Concrete, -- Glass → Concrete floor
    bank = Enum.Material.Concrete,
    supermarket = Enum.Material.Concrete,
    mall = Enum.Material.Concrete,
    hotel = Enum.Material.Concrete,
    -- Civic
    hospital = Enum.Material.SmoothPlastic,
    school = Enum.Material.Concrete,
    university = Enum.Material.Concrete,
    civic = Enum.Material.Concrete,
    government = Enum.Material.Concrete,
    courthouse = Enum.Material.Concrete,
    -- Industrial
    industrial = Enum.Material.Concrete, -- DiamondPlate → Concrete floor
    warehouse = Enum.Material.Concrete, -- CorrugatedSteel → Concrete floor
    factory = Enum.Material.Concrete,
    -- Religious
    religious = Enum.Material.Concrete,
    church = Enum.Material.Cobblestone,
    cathedral = Enum.Material.Cobblestone,
    mosque = Enum.Material.Concrete,
    temple = Enum.Material.Sandstone,
    -- Utility
    garage = Enum.Material.Concrete,
    shed = Enum.Material.Concrete,
    barn = Enum.Material.Concrete,
    -- Default
    yes = Enum.Material.Concrete,
    default = Enum.Material.Concrete,
}

local function getFloorMaterial(building)
    local usage = building.usage or building.kind or "default"
    return USAGE_FLOOR_MATERIAL[usage] or USAGE_FLOOR_MATERIAL.default
end

-- Window tint variation by building usage class. Adds visual diversity to
-- glass panes so that office towers, residential buildings, and warehouses
-- each have a distinct appearance from street and aerial views.
local function getUsageClass(usage)
    if
        usage == "office"
        or usage == "commercial"
        or usage == "bank"
        or usage == "retail"
        or usage == "mall"
        or usage == "hotel"
    then
        return "office"
    elseif
        usage == "residential"
        or usage == "apartments"
        or usage == "house"
        or usage == "detached"
        or usage == "terrace"
        or usage == "dormitory"
    then
        return "residential"
    elseif usage == "warehouse" or usage == "industrial" or usage == "factory" or usage == "garage" then
        return "industrial"
    end
    return "office" -- default to office tint for civic/religious/other
end

local WINDOW_TINT_BY_USAGE_CLASS = {
    office = { color = Color3.fromRGB(100, 130, 170), transparency = 0.15 },
    residential = { color = Color3.fromRGB(150, 140, 120), transparency = 0.2 },
    industrial = { color = Color3.fromRGB(50, 50, 60), transparency = 0.05 },
}

-- Dark/empty window tint for ~20% of panes (night/vacancy effect)
local DARK_WINDOW_TINT = { color = Color3.fromRGB(30, 30, 35), transparency = 0.05 }

local function hashId(id)
    local h = 5381
    for i = 1, #id do
        h = ((h * 33) + string.byte(id, i)) % 2147483647
    end
    return h
end

local function getWindowTint(usage, buildingIdHash, paneIndex)
    -- ~20% of panes are dark/empty based on arithmetic hash of building + pane index
    local darkHash = (buildingIdHash * 31 + (paneIndex or 0)) % 2147483647
    if darkHash % 5 == 0 then
        return DARK_WINDOW_TINT
    end
    local usageClass = getUsageClass(usage or "default")
    return WINDOW_TINT_BY_USAGE_CLASS[usageClass] or WINDOW_TINT_BY_USAGE_CLASS.office
end

local function getFacadeBandSpacing(usage, facadeStyle)
    -- NOTE: facadeStyle IS now populated by the Rust pipeline from the OSM
    -- building:facade tag. The branches below consume the extracted value
    -- directly; no further enrichment step is required.
    if facadeStyle == "curtain_wall" then
        return 3
    elseif facadeStyle == "punched_window" then
        return 5
    elseif facadeStyle == "strip_window" then
        return 4
    elseif facadeStyle == "sparse" then
        return 10
    end
    if usage == "office" then
        return 4
    elseif usage == "residential" or usage == "apartments" or usage == "house" then
        return 6
    elseif usage == "warehouse" or usage == "industrial" then
        return 12
    else
        return 8
    end
end

local function getFacadeInset(usage)
    if usage == "office" then
        return 0.6
    elseif usage == "warehouse" or usage == "industrial" then
        return 0.85
    else
        return 0.7
    end
end

-- Realistic building color palette for deterministic variety when OSM lacks colour tags
local BUILDING_PALETTE = {
    Color3.fromRGB(180, 150, 120), -- sandstone/tan
    Color3.fromRGB(160, 130, 100), -- warm brick
    Color3.fromRGB(140, 155, 165), -- cool grey concrete
    Color3.fromRGB(195, 185, 170), -- light limestone
    Color3.fromRGB(120, 125, 130), -- dark concrete
    Color3.fromRGB(175, 165, 150), -- warm concrete
    Color3.fromRGB(200, 190, 175), -- cream/white plaster
    Color3.fromRGB(155, 140, 125), -- medium brick
    Color3.fromRGB(130, 140, 150), -- steel grey
    Color3.fromRGB(165, 155, 140), -- buff limestone
}

local function getMaterial(building)
    -- The Rust pipeline resolves building:cladding → building:material → material_tag
    -- into the single `material` field. No separate cladding field reaches the manifest.
    -- Priority: material tag → structureType hint → usage-based fallback
    -- Manifest material string directly via Enum lookup
    if type(building.material) == "string" and building.material ~= "" then
        local ok, mat = pcall(function()
            return Enum.Material[building.material]
        end)
        if ok and mat then
            return mat
        end
        -- Also try the OSM tag map (lowercase match)
        local tagMat = MATERIAL_TAG_MAP[building.material:lower()]
        if tagMat then
            return tagMat
        end
    end
    -- When no explicit material tag exists, use structureType (from OSM
    -- building:structure) as a material hint before falling back to usage.
    local st = building.structureType
    if type(st) == "string" and st ~= "" then
        local stLower = st:lower()
        if stLower == "timber_frame" or stLower == "wood" then
            return Enum.Material.WoodPlanks
        elseif stLower == "steel_frame" or stLower == "steel" then
            return Enum.Material.Metal
        elseif stLower == "concrete" then
            return Enum.Material.Concrete
        elseif stLower == "masonry" or stLower == "stone" then
            return Enum.Material.Cobblestone
        elseif stLower == "brick" then
            return Enum.Material.Brick
        end
    end
    -- Fall back to usage/kind lookup
    local usage = building.usage or building.kind or "default"
    return USAGE_MATERIAL[usage] or USAGE_MATERIAL.default
end

-- Per-material color palettes: each entry is {R, G, B} for Color3.fromRGB.
-- Index is chosen deterministically from the building ID hash so the same
-- building always gets the same shade, yet neighbouring buildings vary.
local MATERIAL_COLOR_RANGES = {
    [Enum.Material.Brick] = {
        { 180, 80, 60 }, -- classic red
        { 160, 90, 70 }, -- aged red
        { 200, 100, 75 }, -- bright red-orange
        { 140, 75, 55 }, -- dark weathered red
        { 175, 135, 105 }, -- tan brick
        { 155, 120, 95 }, -- warm tan
        { 110, 70, 55 }, -- dark smoked brick
        { 190, 150, 120 }, -- sandstone-tinted brick
        { 125, 85, 70 }, -- weathered terracotta
    },
    [Enum.Material.Concrete] = {
        { 180, 178, 175 }, -- smooth
        { 170, 168, 165 }, -- smooth-aged
        { 190, 188, 185 }, -- smooth-bright
        { 160, 158, 155 }, -- mid aged
        { 148, 146, 143 }, -- darker aged
        { 135, 132, 128 }, -- rough weathered
        { 200, 198, 193 }, -- bright polished
        { 172, 170, 165 }, -- warm aged
        { 158, 160, 162 }, -- cool aged
    },
    [Enum.Material.Limestone] = {
        { 230, 220, 200 },
        { 225, 215, 195 },
        { 235, 225, 205 },
        { 220, 210, 190 },
    },
    [Enum.Material.WoodPlanks] = {
        { 140, 100, 60 },
        { 130, 90, 55 },
        { 150, 110, 65 },
        { 120, 85, 50 },
    },
    [Enum.Material.Marble] = {
        { 240, 235, 230 },
        { 235, 230, 225 },
        { 245, 240, 235 },
    },
    [Enum.Material.Cobblestone] = {
        { 130, 125, 115 },
        { 120, 115, 105 },
        { 140, 135, 125 },
    },
    [Enum.Material.Sandstone] = {
        { 210, 185, 145 },
        { 200, 175, 135 },
        { 220, 195, 155 },
    },
    [Enum.Material.SmoothPlastic] = {
        { 200, 200, 198 },
        { 210, 208, 205 },
        { 190, 190, 188 },
    },
    [Enum.Material.DiamondPlate] = {
        { 165, 168, 172 },
        { 155, 158, 162 },
        { 175, 178, 182 },
    },
    [Enum.Material.Metal] = {
        { 155, 155, 150 },
        { 145, 145, 140 },
        { 165, 165, 160 },
    },
    [Enum.Material.Granite] = {
        { 130, 125, 120 },
        { 120, 115, 110 },
        { 140, 135, 130 },
    },
    [Enum.Material.Glass] = {
        { 180, 200, 215 }, -- blue-tint office glass
        { 170, 190, 210 }, -- cool blue
        { 190, 205, 220 }, -- light sky
        { 160, 180, 200 }, -- steel blue
    },
    [Enum.Material.Slate] = {
        { 100, 100, 105 },
        { 110, 108, 112 },
        { 95, 95, 100 },
    },
    [Enum.Material.Asphalt] = {
        { 80, 80, 82 },
        { 70, 70, 72 },
        { 90, 88, 85 },
    },
}

-- Return a deterministic color from MATERIAL_COLOR_RANGES for a given material,
-- or nil if that material has no defined palette (fall through to getColor).
local function getMaterialColor(material, buildingId)
    local ranges = MATERIAL_COLOR_RANGES[material]
    if not ranges then
        return nil
    end
    local idx = (hashId(buildingId) % #ranges) + 1
    local c = ranges[idx]
    return Color3.fromRGB(c[1], c[2], c[3])
end

-- Usage-driven color bias. Applied as a small deterministic tint on top of
-- the material palette so office towers feel cool grey-blue, residential
-- buildings feel warm cream, retail pops a bit warmer, and industrial
-- buildings feel darker. Per-building hash decides which tint variant is
-- used so neighbours vary instead of all looking identical.
local USAGE_COLOR_BIAS = {
    office = {
        { r = -10, g = -4, b = 12 }, -- cool grey-blue
        { r = -14, g = -6, b = 14 },
        { r = -8, g = -2, b = 10 },
    },
    commercial = {
        { r = -8, g = -3, b = 10 },
        { r = -12, g = -4, b = 12 },
    },
    bank = {
        { r = -6, g = -2, b = 10 },
    },
    hotel = {
        { r = 6, g = 2, b = -4 },
        { r = 10, g = 4, b = -2 },
    },
    retail = {
        { r = 14, g = 2, b = -6 }, -- warmer pop
        { r = 18, g = 4, b = -4 },
        { r = 10, g = 0, b = -8 },
    },
    mall = {
        { r = 8, g = 0, b = -4 },
    },
    residential = {
        { r = 12, g = 6, b = -2 }, -- warm cream
        { r = 16, g = 8, b = 0 },
        { r = 8, g = 4, b = -4 },
    },
    apartments = {
        { r = 10, g = 4, b = -2 },
        { r = 14, g = 6, b = 0 },
        { r = 6, g = 2, b = -4 },
    },
    house = {
        { r = 14, g = 6, b = 0 },
        { r = 18, g = 8, b = 2 },
    },
    detached = {
        { r = 16, g = 6, b = 0 },
    },
    terrace = {
        { r = 12, g = 4, b = -2 },
    },
    dormitory = {
        { r = 10, g = 4, b = 0 },
    },
    industrial = {
        { r = -18, g = -16, b = -12 }, -- darker
        { r = -22, g = -18, b = -14 },
        { r = -14, g = -12, b = -8 },
    },
    warehouse = {
        { r = -20, g = -16, b = -12 },
        { r = -16, g = -12, b = -8 },
    },
    factory = {
        { r = -22, g = -18, b = -14 },
    },
}

local function applyUsageColorBias(color, usage, id)
    local biases = USAGE_COLOR_BIAS[usage]
    if not biases then
        return color
    end
    local variant = biases[(hashId(id) % #biases) + 1]
    local r = math.clamp(math.floor(color.R * 255 + variant.r), 0, 255)
    local g = math.clamp(math.floor(color.G * 255 + variant.g), 0, 255)
    local b = math.clamp(math.floor(color.B * 255 + variant.b), 0, 255)
    return Color3.fromRGB(r, g, b)
end

local function getColor(building)
    if building.wallColor and building.wallColor.r then
        local r, g, b = building.wallColor.r, building.wallColor.g, building.wallColor.b
        -- OSM auto-fills building:colour with rgb(170,170,170) when no explicit
        -- colour tag exists.  We reject ONLY that exact placeholder so the palette
        -- can provide richer variety for untagged buildings.  Every other value --
        -- including near-greys like (169,170,171) -- is real upstream data and
        -- must be preserved faithfully.
        if not (r == 170 and g == 170 and b == 170) then
            return Color3.fromRGB(r, g, b)
        end
    end
    -- Prefer a material-appropriate color palette for richer visual variety
    local id = building.id or tostring(building)
    local mat = getMaterial(building)
    local usage = string.lower(tostring(building.usage or building.kind or "default"))
    local matColor = getMaterialColor(mat, id)
    if matColor then
        return applyUsageColorBias(matColor, usage, id)
    end
    -- Final fallback: generic building palette
    local paletteColor = BUILDING_PALETTE[(hashId(id) % #BUILDING_PALETTE) + 1]
    return applyUsageColorBias(paletteColor, usage, id)
end

local getRoofMaterial -- forward declaration; defined after ROOF_MATERIAL_LOOKUP tables
local ROOF_MATERIAL_PALETTE_COLORS -- forward declaration for getRoofColor closure

local function getRoofColor(building, wallColor)
    if building.roofColor and building.roofColor.r then
        return Color3.fromRGB(building.roofColor.r, building.roofColor.g, building.roofColor.b)
    end
    -- Use palette color matching the hash-diversified roof material when available
    local roofMat = getRoofMaterial(building, nil)
    local paletteColor = ROOF_MATERIAL_PALETTE_COLORS[roofMat]
    if paletteColor then
        return paletteColor
    end
    -- Fallback: darken wall color by 20%
    if wallColor then
        return Color3.new(wallColor.R * 0.8, wallColor.G * 0.8, wallColor.B * 0.8)
    end
    return Color3.fromRGB(120, 120, 120) -- grey default
end

local ROOF_MATERIAL_LOOKUP = {
    Asphalt = Enum.Material.Asphalt,
    Metal = Enum.Material.Metal,
    Brick = Enum.Material.Brick,
    WoodPlanks = Enum.Material.WoodPlanks,
    Slate = Enum.Material.Slate,
    Concrete = Enum.Material.Concrete,
    tile = Enum.Material.Brick, -- closest to clay/concrete roof tiles
    thatch = Enum.Material.Grass,
    copper = Enum.Material.Metal,
    glass = Enum.Material.Glass,
    Limestone = Enum.Material.Limestone,
    Sandstone = Enum.Material.Sandstone,
    Marble = Enum.Material.Marble,
}

local DEFAULT_ROOF_MATERIAL_BY_USAGE = {
    apartments = Enum.Material.Concrete,
    commercial = Enum.Material.Slate,
    default = Enum.Material.Concrete,
    dormitory = Enum.Material.Concrete,
    hospital = Enum.Material.Concrete,
    hotel = Enum.Material.Slate,
    house = Enum.Material.Brick,
    industrial = Enum.Material.Metal,
    office = Enum.Material.Slate,
    residential = Enum.Material.Brick,
    retail = Enum.Material.Slate,
    school = Enum.Material.Slate,
    warehouse = Enum.Material.Metal,
}

-- Hash-diversified roof material palette: prevents monochrome skylines by
-- selecting roof material from a diverse palette when no explicit roofMaterial
-- is present. Each entry has a corresponding color for visual coherence.
local ROOF_MATERIAL_PALETTE = {
    Enum.Material.Slate,
    Enum.Material.Metal,
    Enum.Material.Asphalt,
    Enum.Material.Brick,
}

ROOF_MATERIAL_PALETTE_COLORS = {
    [Enum.Material.Slate] = Color3.fromRGB(110, 120, 135), -- grey-blue slate
    [Enum.Material.Metal] = Color3.fromRGB(170, 172, 175), -- silver metal
    [Enum.Material.Asphalt] = Color3.fromRGB(80, 80, 85), -- dark grey asphalt
    [Enum.Material.Brick] = Color3.fromRGB(165, 95, 65), -- terracotta tile/brick
}

getRoofMaterial = function(building, wallMat)
    if building.roofMaterial then
        return ROOF_MATERIAL_LOOKUP[building.roofMaterial] or Enum.Material.Concrete
    end
    -- Usage-based fallback preserves semantic intent (hospitals=Concrete, warehouses=Metal)
    local usage = string.lower(tostring(building.usage or building.kind or "default"))
    local usageMat = DEFAULT_ROOF_MATERIAL_BY_USAGE[usage]
    if usageMat then
        return usageMat
    end
    -- Hash-diversified palette for unknown/default usages: prevents monochrome skylines
    local id = building.id or tostring(building)
    local paletteIndex = (hashId(id) % #ROOF_MATERIAL_PALETTE) + 1
    return ROOF_MATERIAL_PALETTE[paletteIndex]
end

local GLAZED_FACADE_USAGES = {
    bank = true,
    commercial = true,
    hospital = true,
    hotel = true,
    office = true,
    retail = true,
}

local function shouldRenderGlassFacadeBands(building, wallMaterial)
    if wallMaterial == Enum.Material.Glass then
        return false
    end

    local usage = string.lower(tostring(building.usage or building.kind or "default"))
    if not GLAZED_FACADE_USAGES[usage] then
        return false
    end

    return true
end

local function buildFootprintData(footprint, holes, originStuds)
    local worldPts = table.create(#footprint)
    local footprintXZ = table.create(#footprint)
    local holeXZ = table.create(holes and #holes or 0)
    local holeWorldLoops = table.create(holes and #holes or 0)
    local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
    local sumX = 0
    local sumZ = 0

    for index, point in ipairs(footprint) do
        local worldX = point.x + originStuds.x
        local worldZ = point.z + originStuds.z
        worldPts[index] = Vector3.new(worldX, 0, worldZ)
        footprintXZ[index] = { x = worldX, z = worldZ }
        sumX += worldX
        sumZ += worldZ

        if worldX < minX then
            minX = worldX
        end
        if worldZ < minZ then
            minZ = worldZ
        end
        if worldX > maxX then
            maxX = worldX
        end
        if worldZ > maxZ then
            maxZ = worldZ
        end
    end

    if holes then
        for holeIndex, hole in ipairs(holes) do
            local holePolyXZ = table.create(#hole)
            local holeWorldPts = table.create(#hole)
            for pointIndex, point in ipairs(hole) do
                local worldX = point.x + originStuds.x
                local worldZ = point.z + originStuds.z
                holePolyXZ[pointIndex] = { x = worldX, z = worldZ }
                holeWorldPts[pointIndex] = Vector3.new(worldX, 0, worldZ)
            end
            holeXZ[holeIndex] = holePolyXZ
            holeWorldLoops[holeIndex] = holeWorldPts
        end
    end

    return {
        worldPts = worldPts,
        footprintXZ = footprintXZ,
        holeXZ = holeXZ,
        holeWorldLoops = holeWorldLoops,
        minX = minX,
        minZ = minZ,
        maxX = maxX,
        maxZ = maxZ,
        sumX = sumX,
        sumZ = sumZ,
        count = #footprint,
    }
end

local function fillInterior(footprintXZ, holeXZ, bounds, baseY, material)
    local function distanceToSegment2D(px, pz, ax, az, bx, bz)
        local dx = bx - ax
        local dz = bz - az
        local lengthSq = dx * dx + dz * dz
        if lengthSq <= 1e-6 then
            local ox = px - ax
            local oz = pz - az
            return math.sqrt(ox * ox + oz * oz)
        end
        local t = ((px - ax) * dx + (pz - az) * dz) / lengthSq
        t = math.clamp(t, 0, 1)
        local cx = ax + dx * t
        local cz = az + dz * t
        local ox = px - cx
        local oz = pz - cz
        return math.sqrt(ox * ox + oz * oz)
    end

    local function distanceToPolygonEdges2D(px, pz, polygon)
        local bestDistance = math.huge
        local vertexCount = #polygon
        for index = 1, vertexCount do
            local a = polygon[index]
            local b = polygon[(index % vertexCount) + 1]
            local distance = distanceToSegment2D(px, pz, a.x, a.z, b.x, b.z)
            if distance < bestDistance then
                bestDistance = distance
            end
        end
        return bestDistance
    end

    local function distanceToPolygonWithHoleEdges2D(px, pz, outerPoly, holes)
        local bestDistance = distanceToPolygonEdges2D(px, pz, outerPoly)
        if holes then
            for _, hole in ipairs(holes) do
                if hole and #hole >= 2 then
                    local holeDistance = distanceToPolygonEdges2D(px, pz, hole)
                    if holeDistance < bestDistance then
                        bestDistance = holeDistance
                    end
                end
            end
        end
        return bestDistance
    end

    local minX = bounds.minX
    local minZ = bounds.minZ
    local maxX = bounds.maxX
    local maxZ = bounds.maxZ

    local GRID_SIZE = 4 -- 4-stud grid matching voxel resolution
    local WALL_THICKNESS = 0.6
    local INTERIOR_FILL_EDGE_CLEARANCE = GRID_SIZE * 0.5 + WALL_THICKNESS
    local function centerXForColumn(columnIndex)
        return minX + GRID_SIZE * 0.5 + columnIndex * GRID_SIZE
    end

    local function centerZForRow(rowIndex)
        return minZ + GRID_SIZE * 0.5 + rowIndex * GRID_SIZE
    end

    local function flushRect(rect)
        if rect == nil then
            return
        end

        local startX = centerXForColumn(rect.startColumn)
        local endX = centerXForColumn(rect.endColumn)
        local startZ = centerZForRow(rect.startRow)
        local endZ = centerZForRow(rect.endRow)
        BuildingBuilder._fillTerrainBlock(
            CFrame.new((startX + endX) * 0.5, baseY, (startZ + endZ) * 0.5),
            Vector3.new(
                (rect.endColumn - rect.startColumn + 1) * GRID_SIZE,
                GRID_SIZE,
                (rect.endRow - rect.startRow + 1) * GRID_SIZE
            ),
            material
        )
    end

    local activeRects = {}
    local rowIndex = 0
    local z = centerZForRow(rowIndex)
    while z < maxZ do
        local rowSpans = {}
        local rowSpanStartColumn = nil
        local rowSpanEndColumn = nil
        local columnIndex = 0
        local x = centerXForColumn(columnIndex)
        while x < maxX do
            local isInteriorCell = GeoUtils.pointInPolygonWithHoles(x, z, footprintXZ, holeXZ)
                and distanceToPolygonWithHoleEdges2D(x, z, footprintXZ, holeXZ) >= INTERIOR_FILL_EDGE_CLEARANCE
            if isInteriorCell then
                if rowSpanStartColumn == nil then
                    rowSpanStartColumn = columnIndex
                end
                rowSpanEndColumn = columnIndex
            elseif rowSpanStartColumn ~= nil then
                rowSpans[#rowSpans + 1] = {
                    startColumn = rowSpanStartColumn,
                    endColumn = rowSpanEndColumn,
                }
                rowSpanStartColumn = nil
                rowSpanEndColumn = nil
            end
            columnIndex += 1
            x = centerXForColumn(columnIndex)
        end
        if rowSpanStartColumn ~= nil then
            rowSpans[#rowSpans + 1] = {
                startColumn = rowSpanStartColumn,
                endColumn = rowSpanEndColumn,
            }
        end

        local nextActiveRects = {}
        for _, span in ipairs(rowSpans) do
            local spanKey = string.format("%d:%d", span.startColumn, span.endColumn)
            local activeRect = activeRects[spanKey]
            if activeRect and activeRect.endRow == rowIndex - 1 then
                activeRect.endRow = rowIndex
                nextActiveRects[spanKey] = activeRect
            else
                nextActiveRects[spanKey] = {
                    startColumn = span.startColumn,
                    endColumn = span.endColumn,
                    startRow = rowIndex,
                    endRow = rowIndex,
                }
            end
        end

        for spanKey, rect in pairs(activeRects) do
            if nextActiveRects[spanKey] == nil then
                flushRect(rect)
            end
        end

        activeRects = nextActiveRects
        rowIndex += 1
        z = centerZForRow(rowIndex)
    end

    for _, rect in pairs(activeRects) do
        flushRect(rect)
    end
end

local function shouldFillTerrainInterior(building, config)
    local rooms = if type(building) == "table" then building.rooms else nil
    if config and config.EnableRoomInteriors ~= false and type(rooms) == "table" and #rooms > 0 then
        return false
    end

    return true
end

local function buildWallLoopParts(
    shellFolder,
    bldgName,
    loopPts,
    baseY,
    height,
    mat,
    color,
    suffixPrefix,
    transparency,
    reflectance
)
    local n = #loopPts
    for i = 1, n do
        local p1 = loopPts[i]
        local p2 = loopPts[(i % n) + 1]
        local dx = p2.X - p1.X
        local dz = p2.Z - p1.Z
        local edgeLen = math.sqrt(dx * dx + dz * dz)
        if edgeLen < MIN_EDGE then
            continue
        end

        local midX = (p1.X + p2.X) * 0.5
        local midZ = (p1.Z + p2.Z) * 0.5
        local midY = baseY + height * 0.5

        local wall = Instance.new("Part")
        wall.Name = string.format("%s_%s_wall%d", bldgName, suffixPrefix, i)
        wall.Anchored = true
        wall.Size = Vector3.new(WALL_THICKNESS, height, edgeLen + WALL_THICKNESS)
        wall.CFrame = CFrame.lookAt(Vector3.new(midX, midY, midZ), Vector3.new(p2.X, midY, p2.Z))
        wall.Material = mat
        wall.Color = color
        wall.CastShadow = false
        if transparency then
            wall.Transparency = transparency
        end
        if reflectance then
            wall.Reflectance = reflectance
        end
        markShellWallEvidence(wall)
        if WorldConfig.DebugBuildingColors then
            wall.Color = Color3.fromRGB(255, 0, 0)
            wall.Transparency = 0
        end
        wall.Parent = shellFolder

        local post = Instance.new("Part")
        post.Name = string.format("%s_%s_corner%d", bldgName, suffixPrefix, i)
        post.Anchored = true
        post.Size = Vector3.new(WALL_THICKNESS, height, WALL_THICKNESS)
        post.CFrame = CFrame.new(p1.X, midY, p1.Z)
        post.Material = mat
        post.Color = color
        post.CastShadow = false
        if transparency then
            post.Transparency = transparency
        end
        if reflectance then
            post.Reflectance = reflectance
        end
        markShellWallEvidence(post)
        if WorldConfig.DebugBuildingColors then
            post.Color = Color3.fromRGB(255, 0, 0)
            post.Transparency = 0
        end
        post.Parent = shellFolder
    end
end

local function addWallLoopToAccumulator(acc, loopPts, baseY, height)
    local n = #loopPts
    for i = 1, n do
        local p1 = loopPts[i]
        local p2 = loopPts[(i % n) + 1]
        local dx = p2.X - p1.X
        local dz = p2.Z - p1.Z
        local edgeLen = math.sqrt(dx * dx + dz * dz)
        if edgeLen < MIN_EDGE then
            continue
        end

        local wallCenter = Vector3.new((p1.X + p2.X) * 0.5, baseY + height * 0.5, (p1.Z + p2.Z) * 0.5)
        local forwardAxis = Vector3.new(dx / edgeLen, 0, dz / edgeLen)
        local rightAxis = Vector3.new(-forwardAxis.Z, 0, forwardAxis.X)
        addOrientedBox(
            acc,
            wallCenter,
            rightAxis,
            Vector3.yAxis,
            forwardAxis,
            Vector3.new(WALL_THICKNESS, height, edgeLen + WALL_THICKNESS)
        )
    end
end

local function getRoofBasis(footprint)
    local centroid = Vector3.zero
    local longestEdge = Vector3.new(0, 0, 1)
    local longestEdgeLength = 0
    local count = #footprint

    for i, point in ipairs(footprint) do
        centroid += point

        local nextPoint = footprint[(i % count) + 1]
        local edge = Vector3.new(nextPoint.X - point.X, 0, nextPoint.Z - point.Z)
        local edgeLength = edge.Magnitude
        if edgeLength > longestEdgeLength then
            longestEdge = edge / edgeLength
            longestEdgeLength = edgeLength
        end
    end

    centroid /= count

    if longestEdgeLength <= 1e-3 then
        longestEdge = Vector3.new(0, 0, 1)
    end

    local rightAxis = Vector3.new(longestEdge.Z, 0, -longestEdge.X)
    if rightAxis.Magnitude <= 1e-3 then
        rightAxis = Vector3.new(1, 0, 0)
    else
        rightAxis = rightAxis.Unit
    end

    return centroid, rightAxis, longestEdge
end

local function collectUniqueRoofPoints(roofPoly)
    local uniquePoints = {}

    for _, point in ipairs(roofPoly) do
        local isDuplicate = false
        for _, existing in ipairs(uniquePoints) do
            if math.abs(existing.x - point.x) <= 0.05 and math.abs(existing.z - point.z) <= 0.05 then
                isDuplicate = true
                break
            end
        end

        if not isDuplicate then
            uniquePoints[#uniquePoints + 1] = point
        end
    end

    return uniquePoints
end

local function tryBuildSimpleFlatRoof(
    bldgName,
    partNameBase,
    roofPoly,
    centroid,
    rightAxis,
    forwardAxis,
    roofY,
    minX,
    minZ,
    maxX,
    maxZ,
    color,
    mat,
    parent,
    partOptions
)
    local uniquePoints = collectUniqueRoofPoints(roofPoly)
    if #uniquePoints ~= 4 then
        return false
    end

    local expectedCorners = {
        { x = minX, z = minZ },
        { x = minX, z = maxZ },
        { x = maxX, z = minZ },
        { x = maxX, z = maxZ },
    }
    local usedCorners = {}

    for _, point in ipairs(uniquePoints) do
        local matched = false
        for cornerIndex, corner in ipairs(expectedCorners) do
            if
                not usedCorners[cornerIndex]
                and math.abs(point.x - corner.x) <= 0.1
                and math.abs(point.z - corner.z) <= 0.1
            then
                usedCorners[cornerIndex] = true
                matched = true
                break
            end
        end

        if not matched then
            return false
        end
    end

    local width = maxX - minX
    local depth = maxZ - minZ
    if width <= 0.5 or depth <= 0.5 then
        return false
    end

    local localCenter = rightAxis * ((minX + maxX) * 0.5) + forwardAxis * ((minZ + maxZ) * 0.5)
    local worldCenter = Vector3.new(centroid.X + localCenter.X, roofY, centroid.Z + localCenter.Z)

    local roof = Instance.new("Part")
    roof.Name = partNameBase or (bldgName .. "_roof")
    roof.Anchored = true
    roof.CastShadow = false
    roof.Material = mat
    roof.Color = color
    roof.Size = Vector3.new(width, ROOF_THICKNESS, depth)
    roof.CFrame = CFrame.lookAt(worldCenter, worldCenter + forwardAxis)
    if partOptions then
        if partOptions.transparency ~= nil then
            roof.Transparency = partOptions.transparency
        end
        if partOptions.attributes then
            for attributeName, attributeValue in pairs(partOptions.attributes) do
                roof:SetAttribute(attributeName, attributeValue)
            end
        end
    end
    applyDebugRoofColor(roof)
    roof.Parent = parent

    return true
end

local function applyRoofPartOptions(part, partOptions)
    if not partOptions then
        return
    end

    if partOptions.transparency ~= nil then
        part.Transparency = partOptions.transparency
    end

    if partOptions.attributes then
        for attributeName, attributeValue in pairs(partOptions.attributes) do
            part:SetAttribute(attributeName, attributeValue)
        end
    end
end

local function buildFlatRoofFromFootprint(
    bldgName,
    footprint,
    holeLoops,
    topY,
    color,
    mat,
    parent,
    roofColor,
    roofMat,
    partNameBase,
    partOptions
)
    local effectiveColor = roofColor or color
    local effectiveMat = roofMat or mat
    local roofPartNameBase = partNameBase or (bldgName .. "_roof")
    local centroid, rightAxis, forwardAxis = getRoofBasis(footprint)
    local roofPoly = table.create(#footprint)
    local roofHoles = table.create(holeLoops and #holeLoops or 0)
    local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge

    for _, point in ipairs(footprint) do
        local offset = point - centroid
        local localX = offset:Dot(rightAxis)
        local localZ = offset:Dot(forwardAxis)
        roofPoly[#roofPoly + 1] = {
            x = localX,
            z = localZ,
        }
        if localX < minX then
            minX = localX
        end
        if localZ < minZ then
            minZ = localZ
        end
        if localX > maxX then
            maxX = localX
        end
        if localZ > maxZ then
            maxZ = localZ
        end
    end

    if holeLoops then
        for holeIndex, holeLoop in ipairs(holeLoops) do
            local roofHole = table.create(#holeLoop)
            for _, point in ipairs(holeLoop) do
                local offset = point - centroid
                roofHole[#roofHole + 1] = {
                    x = offset:Dot(rightAxis),
                    z = offset:Dot(forwardAxis),
                }
            end
            roofHoles[holeIndex] = roofHole
        end
    end

    local stripIndex = 0
    local roofY = topY + ROOF_THICKNESS * 0.5

    if
        #roofHoles == 0
        and tryBuildSimpleFlatRoof(
            bldgName,
            roofPartNameBase,
            roofPoly,
            centroid,
            rightAxis,
            forwardAxis,
            roofY,
            minX,
            minZ,
            maxX,
            maxZ,
            effectiveColor,
            effectiveMat,
            parent,
            partOptions
        )
    then
        return
    end

    local function emitStrip(centerX, width, runStartZ, runEndZ, gridSize)
        stripIndex += 1
        local localCenter = rightAxis * centerX + forwardAxis * ((runStartZ + runEndZ) * 0.5)
        local worldCenter = Vector3.new(centroid.X + localCenter.X, roofY, centroid.Z + localCenter.Z)

        local strip = Instance.new("Part")
        strip.Name = string.format("%s_%d", roofPartNameBase, stripIndex)
        strip.Anchored = true
        strip.CastShadow = false
        strip.Material = effectiveMat
        strip.Color = effectiveColor
        strip.Size = Vector3.new(width, ROOF_THICKNESS, runEndZ - runStartZ + gridSize)
        strip.CFrame = CFrame.lookAt(worldCenter, worldCenter + forwardAxis)
        applyRoofPartOptions(strip, partOptions)
        applyDebugRoofColor(strip)
        strip.Parent = parent
    end

    local function collectStripSegments(gridSize)
        local stripSegments = table.create(0)
        local x = minX + gridSize * 0.5
        while x <= maxX do
            local z = minZ + gridSize * 0.5
            local runStartZ
            local runEndZ

            while z <= maxZ + gridSize do
                local inside = z <= maxZ and GeoUtils.pointInPolygonWithHoles(x, z, roofPoly, roofHoles)

                if inside then
                    if not runStartZ then
                        runStartZ = z
                    end
                    runEndZ = z
                elseif runStartZ and runEndZ then
                    stripSegments[#stripSegments + 1] = {
                        centerX = x,
                        width = gridSize,
                        runStartZ = runStartZ,
                        runEndZ = runEndZ,
                    }
                    runStartZ = nil
                    runEndZ = nil
                end

                z += gridSize
            end

            x += gridSize
        end
        return stripSegments
    end

    local function emitStripSegments(stripSegments, gridSize)
        if #stripSegments == 0 then
            return false
        end

        local active = stripSegments[1]
        local function flushActive()
            emitStrip(active.centerX, active.width, active.runStartZ, active.runEndZ, gridSize)
        end

        for index = 2, #stripSegments do
            local segment = stripSegments[index]
            local expectedCenterX = active.centerX + (active.width + segment.width) * 0.5
            if
                math.abs(segment.runStartZ - active.runStartZ) <= 1e-6
                and math.abs(segment.runEndZ - active.runEndZ) <= 1e-6
                and math.abs(segment.centerX - expectedCenterX) <= 1e-6
            then
                local combinedWidth = active.width + segment.width
                active.centerX = (active.centerX * active.width + segment.centerX * segment.width) / combinedWidth
                active.width = combinedWidth
            else
                flushActive()
                active = segment
            end
        end

        flushActive()
        return true
    end

    local stripSegments = collectStripSegments(ROOF_GRID_SIZE)
    emitStripSegments(stripSegments, ROOF_GRID_SIZE)

    if stripIndex == 0 and #roofHoles > 0 then
        for _, retryGridSize in ipairs({ 4, 2, 1 }) do
            stripSegments = collectStripSegments(retryGridSize)
            if emitStripSegments(stripSegments, retryGridSize) then
                break
            end
        end
    end

    if stripIndex == 0 and #roofHoles == 0 then
        local worldCenter = Vector3.new(centroid.X, roofY, centroid.Z)
        local roof = Instance.new("Part")
        roof.Name = roofPartNameBase
        roof.Anchored = true
        roof.CastShadow = false
        roof.Material = effectiveMat
        roof.Color = effectiveColor
        roof.Size = Vector3.new(math.max(1, maxX - minX), ROOF_THICKNESS, math.max(1, maxZ - minZ))
        roof.CFrame = CFrame.lookAt(worldCenter, worldCenter + forwardAxis)
        applyRoofPartOptions(roof, partOptions)
        applyDebugRoofColor(roof)
        roof.Parent = parent
    end
end

local function buildRoofClosureDeck(bldgName, footprint, holeLoops, topY, roofColor, roofMat, parent)
    buildFlatRoofFromFootprint(
        bldgName,
        footprint,
        holeLoops,
        topY,
        roofColor,
        roofMat,
        parent,
        roofColor,
        roofMat,
        bldgName .. "_roof_closure",
        {
            transparency = 1,
            attributes = {
                ArnisRoofClosureDeck = true,
            },
        }
    )
end

local function buildFallbackFlatClosureRoof(
    bldgName,
    footprint,
    holeLoops,
    topY,
    wallColor,
    wallMat,
    parent,
    roofColor,
    roofMat
)
    buildFlatRoofFromFootprint(
        bldgName,
        footprint,
        holeLoops,
        topY,
        wallColor,
        wallMat,
        parent,
        roofColor,
        roofMat,
        bldgName .. "_roof_closure",
        {
            transparency = 1,
            attributes = {
                ArnisRoofClosureDeck = true,
            },
        }
    )
end

local function buildFallbackFlatVisibleRoof(
    bldgName,
    footprint,
    holeLoops,
    topY,
    wallColor,
    wallMat,
    parent,
    roofColor,
    roofMat
)
    buildFlatRoofFromFootprint(
        bldgName,
        footprint,
        holeLoops,
        topY,
        wallColor,
        wallMat,
        parent,
        roofColor,
        roofMat,
        bldgName .. "_roof"
    )
end

local function getBuildingHeight(building)
    -- Schema 0.4.0: building.height is already in studs at correct scale.
    -- No conversion needed.
    if building.height and building.height > 0 then
        return math.max(4, building.height)
    elseif building.levels and building.levels > 0 then
        return math.max(4, building.levels * 14)
    else
        return 33
    end
end

local function resolveBuildingBaseY(building, originStuds, _chunk)
    -- Schema 0.4.0: baseY is authoritative from DEM. Use directly.
    return originStuds.y + building.baseY
end

local function collectRenderableRoofLoop(footprint)
    local count = #footprint
    if count >= 2 and (footprint[1] - footprint[count]).Magnitude <= 0.05 then
        count -= 1
    end

    local points = table.create(count)
    for index = 1, count do
        points[index] = footprint[index]
    end
    return points
end

local function recordMeshBuildStats(stats, meshPartCount, vertexCount, triangleCount, meshCreateMs, roofMeshPartCount)
    if type(stats) ~= "table" then
        return
    end
    stats.meshPartCount += meshPartCount or 0
    stats.vertexCount += vertexCount or 0
    stats.triangleCount += triangleCount or 0
    stats.meshCreateMs += meshCreateMs or 0
    stats.roofMeshPartCount += roofMeshPartCount or 0
end

local function recordBuildingDetailPhase(stats, phaseName, elapsedMs)
    if type(stats) ~= "table" or type(phaseName) ~= "string" then
        return
    end
    stats[phaseName] = (stats[phaseName] or 0) + (elapsedMs or 0)
end

local function tryBuildRectangularHippedRoofMesh(
    bldgName,
    footprint,
    eaveY,
    rise,
    mat,
    color,
    parent,
    stats,
    meshCollisionPolicy
)
    local points = collectRenderableRoofLoop(footprint)
    if #points ~= 4 or rise <= 0.01 then
        return false
    end

    local edgeA = points[2] - points[1]
    local edgeB = points[3] - points[2]
    local lenA = edgeA.Magnitude
    local lenB = edgeB.Magnitude
    if lenA <= 0.01 or lenB <= 0.01 then
        return false
    end

    local dirA = edgeA.Unit
    local dirB = edgeB.Unit
    if math.abs(dirA:Dot(dirB)) > 0.05 or math.abs(dirA:Dot((points[4] - points[3]).Unit)) < 0.95 then
        return false
    end

    local center = Vector3.zero
    for _, point in ipairs(points) do
        center += point
    end
    center /= #points

    local ridgeAxis = if lenA >= lenB then dirA else dirB
    local crossAxis = if lenA >= lenB then dirB else dirA
    local halfLong = math.max(lenA, lenB) * 0.5
    local halfShort = math.min(lenA, lenB) * 0.5
    local ridgeHalf = math.max(0, halfLong - halfShort)
    local roofTopY = eaveY + rise

    local function localPoint(u, v, y)
        return center + (ridgeAxis * u) + (crossAxis * v) + Vector3.new(0, y, 0)
    end

    local outerNegNeg = localPoint(-halfLong, -halfShort, eaveY)
    local outerPosNeg = localPoint(halfLong, -halfShort, eaveY)
    local outerPosPos = localPoint(halfLong, halfShort, eaveY)
    local outerNegPos = localPoint(-halfLong, halfShort, eaveY)

    local ridgeNeg = localPoint(-ridgeHalf, 0, roofTopY)
    local ridgePos = localPoint(ridgeHalf, 0, roofTopY)

    local triangles = {}
    local function addTriangle(p1, p2, p3)
        local normal = (p2 - p1):Cross(p3 - p1)
        if normal.Y < 0 then
            triangles[#triangles + 1] = { p1, p3, p2 }
        else
            triangles[#triangles + 1] = { p1, p2, p3 }
        end
    end

    if ridgeHalf <= 0.01 then
        addTriangle(outerNegNeg, outerPosNeg, ridgePos)
        addTriangle(outerPosNeg, outerPosPos, ridgePos)
        addTriangle(outerPosPos, outerNegPos, ridgePos)
        addTriangle(outerNegPos, outerNegNeg, ridgePos)
    else
        addTriangle(outerNegNeg, outerPosNeg, ridgePos)
        addTriangle(outerNegNeg, ridgePos, ridgeNeg)
        addTriangle(outerNegPos, ridgeNeg, ridgePos)
        addTriangle(outerNegPos, ridgePos, outerPosPos)
        addTriangle(outerNegNeg, ridgeNeg, outerNegPos)
        addTriangle(outerPosNeg, outerPosPos, ridgePos)
    end

    local meshOk, mesh = pcall(function()
        return AssetService:CreateEditableMesh()
    end)
    if not meshOk or not mesh then
        warn("[MeshAccumulator] CreateEditableMesh failed for roof: " .. tostring(mesh))
        return false
    end

    local vertexIds = table.create(#triangles * 3)
    local vertexCount = 0
    for _, tri in ipairs(triangles) do
        local normal = (tri[2] - tri[1]):Cross(tri[3] - tri[1]).Unit
        for vertexIndex = 1, 3 do
            vertexCount += 1
            vertexIds[vertexCount] = mesh:AddVertex(tri[vertexIndex])
            trySetVertexNormal(mesh, vertexIds[vertexCount], normal)
        end
    end
    for triangleIndex = 1, #triangles do
        local base = ((triangleIndex - 1) * 3)
        mesh:AddTriangle(vertexIds[base + 1], vertexIds[base + 2], vertexIds[base + 3])
    end

    local meshCreateStartedAt = os.clock()
    local createOptions = nil
    if meshCollisionPolicy == "visual_only" then
        createOptions = {
            CollisionFidelity = Enum.CollisionFidelity.Box,
        }
    end
    local roofOk, roof = pcall(function()
        return if createOptions
            then AssetService:CreateMeshPartAsync(Content.fromObject(mesh), createOptions)
            else AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
    end)
    if not roofOk or not roof then
        warn("[MeshAccumulator] CreateMeshPartAsync failed for roof: " .. tostring(roof))
        return false
    end
    local meshCreateMs = (os.clock() - meshCreateStartedAt) * 1000
    roof.Name = bldgName .. "_roof_mesh"
    roof.Anchored = true
    roof.CanCollide = meshCollisionPolicy ~= "visual_only"
    roof.CanQuery = meshCollisionPolicy ~= "visual_only"
    roof.CastShadow = false
    roof.Material = mat
    roof.Color = color
    roof.Parent = parent
    recordMeshBuildStats(stats, 1, vertexCount, #triangles, meshCreateMs, 1)
    return true
end

local function isSimpleRectangularRoofFootprint(footprint, holeLoops)
    if holeLoops and #holeLoops > 0 then
        return false
    end

    local points = collectRenderableRoofLoop(footprint)
    if #points ~= 4 then
        return false
    end

    local edgeA = points[2] - points[1]
    local edgeB = points[3] - points[2]
    local edgeC = points[4] - points[3]
    local edgeD = points[1] - points[4]
    local lenA = edgeA.Magnitude
    local lenB = edgeB.Magnitude
    local lenC = edgeC.Magnitude
    local lenD = edgeD.Magnitude
    if lenA <= 0.01 or lenB <= 0.01 or lenC <= 0.01 or lenD <= 0.01 then
        return false
    end

    local dirA = edgeA.Unit
    local dirB = edgeB.Unit
    local dirC = edgeC.Unit
    local dirD = edgeD.Unit

    if math.abs(dirA:Dot(dirB)) > 0.05 then
        return false
    end

    if math.abs(dirA:Dot(dirC)) > 0.95 and math.abs(dirB:Dot(dirD)) > 0.95 then
        return true
    end

    return false
end

-- Build roof geometry based on building.roof shape.
-- footprint: array of world-space Vector3 points (worldPts)
local function buildRoof(building, footprint, bounds, baseY, height, color, mat, parent, stats, meshCollisionPolicy)
    local bldgName = building.id or "Building"
    local roofShape = (building.roof or "flat"):lower()
    -- Resolve roof-specific color and material (may differ from wall color/mat)
    local rc = getRoofColor(building, color)
    local rm = getRoofMaterial(building, mat)

    local minX = bounds.minX
    local minZ = bounds.minZ
    local maxX = bounds.maxX
    local maxZ = bounds.maxZ
    local footprintW = math.max(1, maxX - minX)
    local footprintL = math.max(1, maxZ - minZ)
    local centerX = (minX + maxX) * 0.5
    local centerZ = (minZ + maxZ) * 0.5
    local rectangularFootprint = isSimpleRectangularRoofFootprint(footprint, bounds.holeWorldLoops)

    if roofShape == "gabled" or roofShape == "gambrel" then
        if not rectangularFootprint then
            buildRoofClosureDeck(bldgName, footprint, bounds.holeWorldLoops, baseY + height, rc, rm, parent)
            buildFallbackFlatVisibleRoof(
                bldgName,
                footprint,
                bounds.holeWorldLoops,
                baseY + height,
                color,
                mat,
                parent,
                rc,
                rm
            )
            return
        end
        buildRoofClosureDeck(bldgName, footprint, bounds.holeWorldLoops, baseY + height, rc, rm, parent)
        -- Ridge runs along the longer axis; panels tilt inward from both shorter edges.
        -- gambrel approximated as gabled (two panels, similar silhouette)
        -- When roofDirection is present (degrees, 0=north clockwise), the ridge
        -- runs perpendicular to that direction. We project into the Z-dominant or
        -- X-dominant bucket so the existing two-panel geometry still works.
        local ridgeAxisIsZ
        if type(building.roofDirection) == "number" then
            -- roofDirection is the facing direction; ridge is perpendicular.
            -- 0=north(+Z), 90=east(+X). Ridge perpendicular to north => runs E-W (X axis).
            local dirRad = math.rad(building.roofDirection)
            -- Ridge perpendicular: rotate 90 degrees. Dot with Z axis to decide.
            local ridgeDirZ = math.abs(math.cos(dirRad + math.pi * 0.5))
            local ridgeDirX = math.abs(math.sin(dirRad + math.pi * 0.5))
            ridgeAxisIsZ = ridgeDirZ >= ridgeDirX
        else
            ridgeAxisIsZ = footprintL >= footprintW
        end
        local shortExtent = ridgeAxisIsZ and footprintW or footprintL
        local longExtent = ridgeAxisIsZ and footprintL or footprintW
        local halfWidth = shortExtent * 0.5
        -- Compute rise from roofAngle (degrees) when present, clamped to 5-60.
        -- Otherwise fall back to the existing 0.3 * shortExtent heuristic.
        local rise
        if type(building.roofAngle) == "number" then
            local clampedAngle = math.clamp(building.roofAngle, 5, 60)
            rise = halfWidth * math.tan(math.rad(clampedAngle))
        else
            rise = shortExtent * 0.3
        end
        local angle = math.atan(rise / halfWidth)
        local panelW = halfWidth / math.cos(angle)
        local cy = baseY + height + rise * 0.5

        local p1 = Instance.new("Part")
        p1.Name = bldgName .. "_roof_p1"
        p1.Anchored = true
        p1.CastShadow = false
        p1.Material = rm
        p1.Color = rc

        local p2 = Instance.new("Part")
        p2.Name = bldgName .. "_roof_p2"
        p2.Anchored = true
        p2.CastShadow = false
        p2.Material = rm
        p2.Color = rc

        if ridgeAxisIsZ then
            -- Panels tilt around Z axis: left half (+angle), right half (-angle)
            p1.Size = Vector3.new(panelW, 0.8, longExtent)
            p1.CFrame = CFrame.new(centerX - halfWidth * 0.5, cy, centerZ) * CFrame.Angles(0, 0, angle)
            p2.Size = Vector3.new(panelW, 0.8, longExtent)
            p2.CFrame = CFrame.new(centerX + halfWidth * 0.5, cy, centerZ) * CFrame.Angles(0, 0, -angle)
        else
            -- Panels tilt around X axis: front half (-angle), back half (+angle)
            p1.Size = Vector3.new(longExtent, 0.8, panelW)
            p1.CFrame = CFrame.new(centerX, cy, centerZ - halfWidth * 0.5) * CFrame.Angles(-angle, 0, 0)
            p2.Size = Vector3.new(longExtent, 0.8, panelW)
            p2.CFrame = CFrame.new(centerX, cy, centerZ + halfWidth * 0.5) * CFrame.Angles(angle, 0, 0)
        end
        applyDebugRoofColor(p1)
        applyDebugRoofColor(p2)
        p1.Parent = parent
        p2.Parent = parent
        return
    elseif roofShape == "pyramidal" or roofShape == "hipped" then
        local rise = if building.roofHeight and building.roofHeight > 0
            then building.roofHeight
            else math.min(footprintW, footprintL) * 0.3
        if
            tryBuildRectangularHippedRoofMesh(
                bldgName,
                footprint,
                baseY + height,
                rise,
                rm,
                rc,
                parent,
                stats,
                meshCollisionPolicy
            )
        then
            buildRoofClosureDeck(bldgName, footprint, bounds.holeWorldLoops, baseY + height, rc, rm, parent)
            return
        end
        buildRoofClosureDeck(bldgName, footprint, bounds.holeWorldLoops, baseY + height, rc, rm, parent)
        buildFallbackFlatVisibleRoof(
            bldgName,
            footprint,
            bounds.holeWorldLoops,
            baseY + height,
            color,
            mat,
            parent,
            rc,
            rm
        )
        return
    elseif roofShape == "dome" or roofShape == "onion" then
        buildRoofClosureDeck(bldgName, footprint, bounds.holeWorldLoops, baseY + height, rc, rm, parent)
        local radius = math.min(footprintW, footprintL) * 0.5
        local dome = Instance.new("Part")
        dome.Name = bldgName .. "_roof"
        dome.Anchored = true
        dome.Shape = Enum.PartType.Ball
        dome.Size = Vector3.new(radius * 2, roofShape == "onion" and radius * 1.4 or radius, radius * 2)
        dome.CFrame = CFrame.new(centerX, baseY + height + radius * 0.5, centerZ)
        dome.Material = rm
        dome.Color = rc
        dome.CastShadow = false
        applyDebugRoofColor(dome)
        dome.Parent = parent
        return
    elseif roofShape == "skillion" then
        if not rectangularFootprint then
            buildRoofClosureDeck(bldgName, footprint, bounds.holeWorldLoops, baseY + height, rc, rm, parent)
            buildFallbackFlatVisibleRoof(
                bldgName,
                footprint,
                bounds.holeWorldLoops,
                baseY + height,
                color,
                mat,
                parent,
                rc,
                rm
            )
            return
        end
        buildRoofClosureDeck(bldgName, footprint, bounds.holeWorldLoops, baseY + height, rc, rm, parent)
        -- Single-slope wedge across the short axis
        local rise = math.min(footprintW, footprintL) * 0.35
        local ridgeAxisIsZ = footprintL >= footprintW
        local wedge = Instance.new("WedgePart")
        wedge.Name = bldgName .. "_roof"
        wedge.Anchored = true
        wedge.CastShadow = false
        wedge.Material = rm
        wedge.Color = rc
        if ridgeAxisIsZ then
            wedge.Size = Vector3.new(footprintW, rise, footprintL)
        else
            wedge.Size = Vector3.new(footprintL, rise, footprintW)
        end
        wedge.CFrame = CFrame.new(centerX, baseY + height + rise * 0.5, centerZ)
        applyDebugRoofColor(wedge)
        wedge.Parent = parent
        return
    elseif roofShape == "mansard" then
        if not rectangularFootprint then
            buildRoofClosureDeck(bldgName, footprint, bounds.holeWorldLoops, baseY + height, rc, rm, parent)
            buildFallbackFlatVisibleRoof(
                bldgName,
                footprint,
                bounds.holeWorldLoops,
                baseY + height,
                color,
                mat,
                parent,
                rc,
                rm
            )
            return
        end
        buildRoofClosureDeck(bldgName, footprint, bounds.holeWorldLoops, baseY + height, rc, rm, parent)
        -- Flat deck (Slate) + four parapet/slope strips along the perimeter
        local slopeH = math.min(3.5, height * 0.35)
        local insetX = math.max(1, footprintW * 0.65)
        local insetZ = math.max(1, footprintL * 0.65)
        -- Flat central deck
        local deck = Instance.new("Part")
        deck.Name = bldgName .. "_roof"
        deck.Anchored = true
        deck.Size = Vector3.new(insetX, 0.5, insetZ)
        deck.CFrame = CFrame.new(centerX, baseY + height + slopeH + 0.25, centerZ)
        deck.Material = rm
        deck.Color = rc
        deck.CastShadow = false
        applyDebugRoofColor(deck)
        deck.Parent = parent
        -- Four sloped side strips
        local strips = {
            {
                Vector3.new(footprintW, slopeH, (footprintL - insetZ) * 0.5),
                centerX,
                minZ + (footprintL - insetZ) * 0.25,
            },
            {
                Vector3.new(footprintW, slopeH, (footprintL - insetZ) * 0.5),
                centerX,
                maxZ - (footprintL - insetZ) * 0.25,
            },
            {
                Vector3.new((footprintW - insetX) * 0.5, slopeH, insetZ),
                minX + (footprintW - insetX) * 0.25,
                centerZ,
            },
            {
                Vector3.new((footprintW - insetX) * 0.5, slopeH, insetZ),
                maxX - (footprintW - insetX) * 0.25,
                centerZ,
            },
        }
        for k, s in ipairs(strips) do
            if s[1].X > 0.1 and s[1].Z > 0.1 then
                local strip = Instance.new("Part")
                strip.Name = bldgName .. "_slope" .. k
                strip.Anchored = true
                strip.Size = s[1]
                strip.CFrame = CFrame.new(s[2], baseY + height + slopeH * 0.5, s[3])
                strip.Material = rm
                strip.Color = rc
                strip.CastShadow = false
                applyDebugRoofColor(strip)
                strip.Parent = parent
            end
        end
        return
    elseif roofShape == "cone" then
        buildRoofClosureDeck(bldgName, footprint, bounds.holeWorldLoops, baseY + height, rc, rm, parent)
        -- Conical roof: cylinder with cone SpecialMesh
        local rise = math.min(footprintW, footprintL) * 0.6
        local radius = math.min(footprintW, footprintL) * 0.5
        local cone = Instance.new("Part")
        cone.Name = bldgName .. "_roof"
        cone.Anchored = true
        cone.Size = Vector3.new(radius * 2, rise, radius * 2)
        cone.CFrame = CFrame.new(centerX, baseY + height + rise * 0.5, centerZ)
        cone.Material = rm
        cone.Color = rc
        cone.CastShadow = false
        local mesh = Instance.new("SpecialMesh")
        mesh.MeshType = Enum.MeshType.FileMesh
        mesh.MeshId = "rbxassetid://1078075" -- Roblox cone mesh
        mesh.Scale = Vector3.new(radius * 0.2, rise * 0.1, radius * 0.2)
        mesh.Parent = cone
        applyDebugRoofColor(cone)
        cone.Parent = parent
        return
    end

    -- Default / flat → flat slab
    buildFlatRoofFromFootprint(bldgName, footprint, bounds.holeWorldLoops, baseY + height, color, mat, parent, rc, rm)

    -- roofLevels > 1: add a stepped center section for multi-level roof complexity
    local roofLevels = tonumber(building.roofLevels) or 1
    if roofLevels > 1 and rectangularFootprint then
        local stepHeight = 1.2
        local insetFraction = 0.2
        for level = 2, math.min(roofLevels, 4) do
            local inset = insetFraction * (level - 1)
            local stepW = footprintW * (1 - inset * 2)
            local stepL = footprintL * (1 - inset * 2)
            if stepW < 2 or stepL < 2 then
                break
            end
            local stepY = baseY + height + ROOF_THICKNESS + stepHeight * (level - 1)
            local stepPart = Instance.new("Part")
            stepPart.Name = string.format("%s_roof_step_%d", bldgName, level)
            stepPart.Anchored = true
            stepPart.CastShadow = false
            stepPart.Material = rm
            stepPart.Color = rc
            stepPart.Size = Vector3.new(stepW, ROOF_THICKNESS, stepL)
            stepPart.CFrame = CFrame.new(centerX, stepY + ROOF_THICKNESS * 0.5, centerZ)
            CollectionService:AddTag(stepPart, "LOD_Detail")
            stepPart.Parent = parent
        end
    end
end

local function isRoofOnlyStructure(building)
    local usage = string.lower(tostring(building.usage or building.kind or ""))
    return usage == "roof"
end

local function normalizeRoofOnlyPlacement(building, baseY, height)
    if not isRoofOnlyStructure(building) then
        return baseY, height, false
    end

    local explicitMinHeight = tonumber(building.minHeight)
    if explicitMinHeight and explicitMinHeight > 0.25 then
        return baseY, height, true
    end

    local explicitRoofHeight = tonumber(building.roofHeight)
    local inferredRoofThickness = explicitRoofHeight
    if not inferredRoofThickness or inferredRoofThickness <= 0 then
        inferredRoofThickness = 3
    end
    inferredRoofThickness = math.max(2, inferredRoofThickness)

    if height <= inferredRoofThickness + 6 then
        return baseY, height, false
    end

    local inferredBaseY = baseY + math.max(0, height - inferredRoofThickness)
    return inferredBaseY, inferredRoofThickness, true
end

local SIMPLE_SHELL_USAGES = {
    apartments = true,
    building = true,
    detached = true,
    dormitory = true,
    house = true,
    residential = true,
    terrace = true,
    yes = true,
}

local function shouldPreferSimpleShellDetail(building, footprintPointCount, height)
    local usage = string.lower(tostring(building.usage or building.kind or "default"))
    if not SIMPLE_SHELL_USAGES[usage] then
        return false
    end

    if building.name and building.name ~= "" then
        return false
    end

    if building.roofColor or building.roofMaterial then
        return false
    end

    local roofShape = string.lower(tostring(building.roof or "flat"))
    if roofShape ~= "flat" and roofShape ~= "gabled" then
        return false
    end

    local levels = tonumber(building.levels) or math.max(1, math.floor(height / 5))
    if levels > 4 or height > 26 then
        return false
    end

    return footprintPointCount <= 8
end

local PLAY_VISIBLE_SHELL_ROOF_SHAPES = {
    flat = true,
    gabled = true,
    hipped = true,
    skillion = true,
}

local function shouldPreferPlayVisibleShellWalls(building, footprintPointCount, height, holeLoopCount)
    -- Root cause found: SetVertexNormal doesn't exist on this Roblox version.
    -- Fixed by reversing triangle winding order in addQuad/addTriangle so
    -- auto-computed normals point outward. EditableMesh should now render
    -- correctly. Restoring threshold logic for optimal draw call count.
    if shouldPreferSimpleShellDetail(building, footprintPointCount, height) then
        return true
    end

    local boundedHoleLoopCount = holeLoopCount or 0
    if boundedHoleLoopCount > 1 then
        return false
    end

    local roofShape = string.lower(tostring(building.roof or "flat"))
    if not PLAY_VISIBLE_SHELL_ROOF_SHAPES[roofShape] then
        return false
    end

    local levels = tonumber(building.levels) or math.max(1, math.floor(height / 5))
    if levels > 6 or height > 34 then
        return false
    end

    if boundedHoleLoopCount == 1 then
        return levels <= 5 and height <= 28 and footprintPointCount <= 12
    end

    return footprintPointCount <= 10
end

local function shouldEmitMergedShellReadableCues(building, footprintPointCount, height, holeLoopCount)
    if shouldPreferSimpleShellDetail(building, footprintPointCount, height) then
        return false
    end

    if shouldPreferPlayVisibleShellWalls(building, footprintPointCount, height, holeLoopCount) then
        return false
    end

    local roofShape = string.lower(tostring(building.roof or "flat"))
    if not PLAY_VISIBLE_SHELL_ROOF_SHAPES[roofShape] then
        return false
    end

    local boundedHoleLoopCount = holeLoopCount or 0
    if boundedHoleLoopCount > 1 then
        return false
    end

    local levels = tonumber(building.levels) or math.max(1, math.floor(height / 5))
    if levels > 8 or height > 40 or footprintPointCount > 12 then
        return false
    end

    return true
end

local function getMergedShellRooflineY(baseY, height)
    return baseY + math.max(height - 0.9, 1.6)
end

local function buildMergedShellRooflineCues(parent, worldPts, baseY, height)
    local rooflineY = getMergedShellRooflineY(baseY, height)
    local builtCount = 0

    for i = 1, #worldPts do
        local p1 = worldPts[i]
        local p2 = worldPts[(i % #worldPts) + 1]
        local edgeVec = p2 - p1
        local edgeLen = edgeVec.Magnitude
        if edgeLen < 4 then
            continue
        end

        local dir = edgeVec.Unit
        local outward = Vector3.new(-dir.Z, 0, dir.X) * 0.14
        local mid = (p1 + p2) * 0.5

        local roofline = Instance.new("Part")
        roofline.Name = "MergedShellRooflineCue"
        roofline.Size = Vector3.new(edgeLen + 0.2, 0.42, 0.88)
        roofline.Material = Enum.Material.Slate
        roofline.Color = Color3.fromRGB(175, 172, 166)
        roofline.Anchored = true
        roofline.CanCollide = false
        roofline.CastShadow = false
        roofline.CFrame = CFrame.lookAt(
            mid + outward + Vector3.new(0, rooflineY, 0),
            mid + outward + Vector3.new(0, rooflineY, 0) + dir
        )
        roofline.Parent = parent
        builtCount += 1
    end

    return builtCount
end

local function buildMergedShellPerimeterCues(parent, worldPts, baseY, height)
    local rooflineY = getMergedShellRooflineY(baseY, height)
    local builtCount = 0
    local cornerHeight = math.max(2.4, math.min(height * 0.28, 4.2))
    local cornerCenterY = rooflineY + cornerHeight * 0.5

    for _, pt in ipairs(worldPts) do
        local perimeterCue = Instance.new("Part")
        perimeterCue.Name = "MergedShellPerimeterCue"
        perimeterCue.Size = Vector3.new(0.46, cornerHeight, 0.46)
        perimeterCue.Material = Enum.Material.Concrete
        perimeterCue.Color = Color3.fromRGB(198, 192, 184)
        perimeterCue.Anchored = true
        perimeterCue.CanCollide = false
        perimeterCue.CastShadow = false
        perimeterCue.CFrame = CFrame.new(pt.X, cornerCenterY, pt.Z)
        perimeterCue.Parent = parent
        builtCount += 1
    end

    return builtCount
end

local function buildMergedShellWallPresenceCues(parent, worldPts, baseY, height)
    local builtCount = 0
    local wallCueHeight = math.max(2.8, math.min(height * 0.26, 5.0))
    local wallCueCenterY = baseY + math.max(wallCueHeight * 0.5 + 0.2, 1.8)

    -- Street-level exterior strips keep wall mass readable without emitting
    -- a full explicit wall loop.
    for i = 1, #worldPts do
        local p1 = worldPts[i]
        local p2 = worldPts[(i % #worldPts) + 1]
        local edgeVec = p2 - p1
        local edgeLen = edgeVec.Magnitude
        if edgeLen < 4 then
            continue
        end

        local stripLen = math.max(3.2, math.min(edgeLen * 0.38, edgeLen - 0.4))
        if stripLen < 3.2 then
            continue
        end

        local dir = edgeVec.Unit
        local outward = Vector3.new(-dir.Z, 0, dir.X) * 0.12
        local mid = (p1 + p2) * 0.5

        local wallPresence = Instance.new("Part")
        wallPresence.Name = "MergedShellWallPresenceCue"
        wallPresence.Size = Vector3.new(stripLen, wallCueHeight, 0.48)
        wallPresence.Material = Enum.Material.Concrete
        wallPresence.Color = Color3.fromRGB(190, 184, 176)
        wallPresence.Anchored = true
        wallPresence.CanCollide = false
        wallPresence.CastShadow = false
        wallPresence.CFrame = CFrame.lookAt(
            mid + outward + Vector3.new(0, wallCueCenterY, 0),
            mid + outward + Vector3.new(0, wallCueCenterY, 0) + dir
        )
        wallPresence.Parent = parent
        builtCount += 1
    end

    return builtCount
end

local function getMergedShellStreetFacadeY(baseY, height)
    return baseY + math.max(2.0, math.min(height * 0.16, 4.0))
end

local function buildMergedShellStreetFacadeCues(parent, worldPts, baseY, height)
    local builtCount = 0
    local streetFacadeY = getMergedShellStreetFacadeY(baseY, height)
    local facadeHeight = math.max(1.8, math.min(height * 0.18, 3.2))

    for i = 1, #worldPts do
        local p1 = worldPts[i]
        local p2 = worldPts[(i % #worldPts) + 1]
        local edgeVec = p2 - p1
        local edgeLen = edgeVec.Magnitude
        if edgeLen < 4 then
            continue
        end

        local stripLen = math.max(3.2, math.min(edgeLen * 0.46, edgeLen - 0.6))
        if stripLen < 3.2 then
            continue
        end

        local dir = edgeVec.Unit
        local outward = Vector3.new(-dir.Z, 0, dir.X) * 0.16
        local mid = (p1 + p2) * 0.5

        local facadeCue = Instance.new("Part")
        facadeCue.Name = "MergedShellStreetFacadeCue"
        facadeCue.Size = Vector3.new(stripLen, facadeHeight, 0.52)
        facadeCue.Material = Enum.Material.Concrete
        facadeCue.Color = Color3.fromRGB(204, 198, 190)
        facadeCue.Anchored = true
        facadeCue.CanCollide = false
        facadeCue.CastShadow = false
        facadeCue.CFrame = CFrame.lookAt(
            mid + outward + Vector3.new(0, streetFacadeY, 0),
            mid + outward + Vector3.new(0, streetFacadeY, 0) + dir
        )
        facadeCue.Parent = parent
        builtCount += 1
    end

    return builtCount
end

local collectSimpleShellReadableEdges

local function buildMergedShellDoorCue(parent, worldPts, baseY, height)
    local edges = collectSimpleShellReadableEdges(worldPts)
    if #edges == 0 then
        return 0
    end

    local doorEdge = edges[1]
    local doorHeight = math.max(3.4, math.min(height - 1.1, 4.2))
    local doorWidth = math.clamp(doorEdge.len * 0.14, 1.8, 2.6)
    local doorCenterY = baseY + doorHeight * 0.5
    local doorOutward = Vector3.new(-doorEdge.dir.Z, 0, doorEdge.dir.X) * 0.12

    local doorCue = Instance.new("Part")
    doorCue.Name = "MergedShellDoorCue"
    doorCue.Size = Vector3.new(doorWidth, doorHeight, 0.18)
    doorCue.Material = Enum.Material.WoodPlanks
    doorCue.Color = Color3.fromRGB(96, 76, 58)
    doorCue.Anchored = true
    doorCue.CanCollide = false
    doorCue.CanQuery = false
    doorCue.CastShadow = false
    doorCue.CFrame = CFrame.lookAt(
        doorEdge.mid + doorOutward + Vector3.new(0, doorCenterY, 0),
        doorEdge.mid + doorOutward + Vector3.new(0, doorCenterY, 0) + doorEdge.dir
    )
    doorCue.Parent = parent
    return 1
end

local function buildMergedShellWindowPaneCues(parent, worldPts, baseY, height)
    local edges = collectSimpleShellReadableEdges(worldPts)
    if #edges == 0 then
        return 0
    end

    local builtCount = 0
    local maxWindowEdges = math.min(#edges, 4)
    local paneHeight = math.max(1.6, math.min(height * 0.08, 2.2))
    local paneWidthMin = 1.4
    local paneWidthMax = 2.2
    local paneCenterY = baseY + math.max(3.0, math.min(height * 0.2, 5.2))

    for edgeIndex = 1, maxWindowEdges do
        local edge = edges[edgeIndex]
        local outward = Vector3.new(-edge.dir.Z, 0, edge.dir.X) * 0.15
        local paneCue = Instance.new("Part")
        paneCue.Name = "MergedShellWindowPaneCue"
        paneCue.Size = Vector3.new(math.clamp(edge.len * 0.1, paneWidthMin, paneWidthMax), paneHeight, 0.12)
        paneCue.Material = Enum.Material.Glass
        paneCue.Color = Color3.fromRGB(58, 74, 96)
        paneCue.Anchored = true
        paneCue.CanCollide = false
        paneCue.CanQuery = false
        paneCue.CastShadow = false
        paneCue.Transparency = 0.35
        paneCue:SetAttribute("BaseTransparency", 0.35)
        paneCue.CFrame = CFrame.lookAt(
            edge.mid + outward + Vector3.new(0, paneCenterY, 0),
            edge.mid + outward + Vector3.new(0, paneCenterY, 0) + edge.dir
        )
        paneCue.Parent = parent
        builtCount += 1
    end

    return builtCount
end

local function getRenderableFootprintPoints(worldPts)
    local effectiveCount = #worldPts
    if effectiveCount >= 2 and (worldPts[1] - worldPts[effectiveCount]).Magnitude <= 0.05 then
        effectiveCount -= 1
    end

    local points = {}
    for i = 1, effectiveCount do
        local point = worldPts[i]
        if #points == 0 or (point - points[#points]).Magnitude > 0.05 then
            points[#points + 1] = point
        end
    end

    return points
end

local function selectSupportPoints(worldPts, maxPosts)
    local points = getRenderableFootprintPoints(worldPts)
    if #points <= maxPosts then
        return points
    end

    local selected = {}
    local used = {}
    local step = #points / maxPosts
    for postIndex = 0, maxPosts - 1 do
        local pointIndex = math.floor(postIndex * step) + 1
        pointIndex = math.clamp(pointIndex, 1, #points)
        if not used[pointIndex] then
            used[pointIndex] = true
            selected[#selected + 1] = points[pointIndex]
        end
    end

    return selected
end

local function buildRoofOnlyStructure(
    model,
    building,
    worldPts,
    footprintData,
    baseY,
    height,
    color,
    mat,
    rooftopAttachment
)
    local shellFolder = model:FindFirstChild("Shell")
    if not shellFolder then
        shellFolder = Instance.new("Folder")
        shellFolder.Name = "Shell"
        shellFolder.Parent = model
    end

    buildRoof(building, worldPts, footprintData, baseY, height, color, mat, shellFolder)

    if rooftopAttachment then
        return
    end

    local supportHeight = math.max(2, height)
    local supportMidY = baseY + supportHeight * 0.5
    local supportPoints = selectSupportPoints(worldPts, 4)
    for _, point in ipairs(supportPoints) do
        local support = Instance.new("Part")
        support.Name = "SupportPost"
        support.Size = Vector3.new(0.45, supportHeight, 0.45)
        support.Material = Enum.Material.Metal
        support.Color = Color3.fromRGB(170, 170, 175)
        support.Anchored = true
        support.CanCollide = true
        support.CastShadow = false
        support.CFrame = CFrame.new(point.X, supportMidY, point.Z)
        support.Parent = shellFolder
    end
end

local function buildFoundation(parent, worldPts, baseY)
    for i = 1, #worldPts do
        local p1 = worldPts[i]
        local p2 = worldPts[(i % #worldPts) + 1]
        local edgeLen = (p2 - p1).Magnitude
        if edgeLen < 1 then
            continue
        end

        local mid = (p1 + p2) * 0.5
        local dir = (p2 - p1).Unit

        local foundation = Instance.new("Part")
        foundation.Name = "Foundation"
        foundation.Size = Vector3.new(edgeLen + 0.2, 1.5, 0.8)
        foundation.Material = Enum.Material.Concrete
        foundation.Color = Color3.fromRGB(160, 155, 148)
        foundation.Anchored = true
        foundation.CanCollide = true
        foundation.CastShadow = false
        foundation.CFrame = CFrame.lookAt(
            mid + Vector3.new(0, baseY + 0.75, 0),
            mid + Vector3.new(0, baseY + 0.75, 0) + dir
        ) * CFrame.new(0, 0, -0.1)
        foundation.Parent = parent
    end
end

local function getFacadeBeltlineY(baseY, height)
    local floorHeight = 5
    return baseY + math.min(math.max(floorHeight + 0.4, height * 0.32), math.max(1.8, height - 1.2))
end

local function buildFacadeBeltlines(parent, worldPts, baseY, height)
    local beltlineHeight = 0.28
    local beltlineDepth = 0.42
    local beltlineY = getFacadeBeltlineY(baseY, height)
    local builtCount = 0

    for i = 1, #worldPts do
        local p1 = worldPts[i]
        local p2 = worldPts[(i % #worldPts) + 1]
        local edgeLen = (p2 - p1).Magnitude
        if edgeLen < 4 then
            continue
        end

        local mid = (p1 + p2) * 0.5
        local dir = (p2 - p1).Unit

        local beltline = Instance.new("Part")
        beltline.Name = "FacadeBeltline"
        beltline.Size = Vector3.new(edgeLen, beltlineHeight, beltlineDepth)
        beltline.Material = Enum.Material.Concrete
        beltline.Color = Color3.fromRGB(200, 195, 185)
        beltline.Anchored = true
        beltline.CanCollide = false
        beltline.CastShadow = false
        beltline.CFrame = CFrame.lookAt(mid + Vector3.new(0, beltlineY, 0), mid + Vector3.new(0, beltlineY, 0) + dir)
            * CFrame.new(0, 0, -0.14)
        beltline.Parent = parent
        builtCount += 1
    end

    return builtCount
end

local function addFacadeBeltlinesToAccumulator(acc, worldPts, baseY, height)
    local beltlineHeight = 0.28
    local beltlineY = getFacadeBeltlineY(baseY, height)
    local builtCount = 0

    for i = 1, #worldPts do
        local p1 = worldPts[i]
        local p2 = worldPts[(i % #worldPts) + 1]
        local edgeVec = p2 - p1
        local edgeLen = edgeVec.Magnitude
        if edgeLen < 4 then
            continue
        end

        local dir = edgeVec.Unit
        local outward = Vector3.new(-dir.Z, 0, dir.X) * 0.14
        acc:addQuad(
            p1 + outward + Vector3.new(0, beltlineY - beltlineHeight * 0.5, 0),
            p2 + outward + Vector3.new(0, beltlineY - beltlineHeight * 0.5, 0),
            p2 + outward + Vector3.new(0, beltlineY + beltlineHeight * 0.5, 0),
            p1 + outward + Vector3.new(0, beltlineY + beltlineHeight * 0.5, 0),
            outward.Unit
        )
        builtCount += 1
    end

    return builtCount
end

local function buildCornice(parent, worldPts, topY)
    local builtCount = 0
    for i = 1, #worldPts do
        local p1 = worldPts[i]
        local p2 = worldPts[(i % #worldPts) + 1]
        local edgeLen = (p2 - p1).Magnitude
        if edgeLen < 1 then
            continue
        end

        local mid = (p1 + p2) * 0.5
        local dir = (p2 - p1).Unit

        local cornice = Instance.new("Part")
        cornice.Name = "Cornice"
        cornice.Size = Vector3.new(edgeLen, 0.4, 0.6)
        cornice.Material = Enum.Material.Concrete
        cornice.Color = Color3.fromRGB(210, 205, 195)
        cornice.Anchored = true
        cornice.CanCollide = false
        cornice.CastShadow = false
        cornice.CFrame = CFrame.lookAt(mid + Vector3.new(0, topY, 0), mid + Vector3.new(0, topY, 0) + dir)
            * CFrame.new(0, 0, -0.15)
        cornice.Parent = parent
        builtCount += 1
    end

    return builtCount
end

local function addCorniceToAccumulator(acc, worldPts, topY)
    local builtCount = 0
    local nPts = #worldPts
    for i = 1, nPts do
        local p1 = worldPts[i]
        local p2 = worldPts[(i % nPts) + 1]
        local edgeVec = p2 - p1
        local edgeLen = edgeVec.Magnitude
        if edgeLen < 1 then
            continue
        end

        local dir = edgeVec.Unit
        local outward = Vector3.new(-dir.Z, 0, dir.X) * 0.1
        acc:addQuad(
            p1 + outward + Vector3.new(0, topY - 0.2, 0),
            p2 + outward + Vector3.new(0, topY - 0.2, 0),
            p2 + outward + Vector3.new(0, topY + 0.2, 0),
            p1 + outward + Vector3.new(0, topY + 0.2, 0),
            outward.Unit
        )
        builtCount += 1
    end

    return builtCount
end

local function buildCornerAccents(parent, worldPts, baseY, height)
    local builtCount = 0
    local accentHeight = math.max(3, math.min(height - 1.2, height * 0.72))
    local accentCenterY = baseY + accentHeight * 0.5
    for _, pt in ipairs(worldPts) do
        local accent = Instance.new("Part")
        accent.Name = "CornerAccent"
        accent.Size = Vector3.new(0.32, accentHeight, 0.32)
        accent.Material = Enum.Material.Concrete
        accent.Color = Color3.fromRGB(205, 200, 190)
        accent.Anchored = true
        accent.CanCollide = false
        accent.CastShadow = false
        accent.CFrame = CFrame.new(pt.X, accentCenterY, pt.Z)
        accent.Parent = parent
        builtCount += 1
    end

    return builtCount
end

local function buildMergedShellReadableCues(detailFolder, worldPts, baseY, height)
    local beltlineCount = buildFacadeBeltlines(detailFolder, worldPts, baseY, height)
    local cornerAccentCount = buildCornerAccents(detailFolder, worldPts, baseY, height)
    local rooflineCueCount = buildMergedShellRooflineCues(detailFolder, worldPts, baseY, height)
    local perimeterCueCount = buildMergedShellPerimeterCues(detailFolder, worldPts, baseY, height)
    local wallPresenceCueCount = buildMergedShellWallPresenceCues(detailFolder, worldPts, baseY, height)
    local streetFacadeCueCount = buildMergedShellStreetFacadeCues(detailFolder, worldPts, baseY, height)
    local doorCueCount = buildMergedShellDoorCue(detailFolder, worldPts, baseY, height)
    local windowPaneCueCount = buildMergedShellWindowPaneCues(detailFolder, worldPts, baseY, height)
    return beltlineCount,
        cornerAccentCount,
        rooflineCueCount,
        perimeterCueCount,
        wallPresenceCueCount,
        streetFacadeCueCount,
        doorCueCount,
        windowPaneCueCount
end

local function buildPlayVisibleShellReadableCues(detailFolder, worldPts, baseY, height)
    local facadeBeltlineCount = buildFacadeBeltlines(detailFolder, worldPts, baseY, height)
    local rooflineCueCount = buildMergedShellRooflineCues(detailFolder, worldPts, baseY, height)
    local cornerAccentCount = buildCornerAccents(detailFolder, worldPts, baseY, height)
    local doorCueCount = buildMergedShellDoorCue(detailFolder, worldPts, baseY, height)
    local streetFacadeCueCount = buildMergedShellStreetFacadeCues(detailFolder, worldPts, baseY, height)
    local windowPaneCueCount = buildMergedShellWindowPaneCues(detailFolder, worldPts, baseY, height)
    return facadeBeltlineCount,
        rooflineCueCount,
        cornerAccentCount,
        doorCueCount,
        streetFacadeCueCount,
        windowPaneCueCount
end

local function addCornerAccentsToAccumulator(acc, worldPts, baseY, height)
    local builtCount = 0
    local accentHeight = math.max(3, math.min(height - 1.2, height * 0.72))
    local accentCenterY = baseY + accentHeight * 0.5
    local halfSize = Vector3.new(0.16, accentHeight * 0.5, 0.16)

    for _, pt in ipairs(worldPts) do
        addOrientedBox(
            acc,
            Vector3.new(pt.X, accentCenterY, pt.Z),
            Vector3.xAxis,
            Vector3.yAxis,
            Vector3.zAxis,
            halfSize * 2
        )
        builtCount += 1
    end

    return builtCount
end

collectSimpleShellReadableEdges = function(worldPts)
    local edges = {}
    for i = 1, #worldPts do
        local p1 = worldPts[i]
        local p2 = worldPts[(i % #worldPts) + 1]
        local edgeVec = p2 - p1
        local edgeLen = edgeVec.Magnitude
        if edgeLen >= 8 then
            edges[#edges + 1] = {
                p1 = p1,
                p2 = p2,
                dir = edgeVec.Unit,
                len = edgeLen,
                mid = (p1 + p2) * 0.5,
            }
        end
    end
    table.sort(edges, function(a, b)
        if math.abs(a.len - b.len) > 0.05 then
            return a.len > b.len
        end
        if math.abs(a.mid.X - b.mid.X) > 0.05 then
            return a.mid.X < b.mid.X
        end
        return a.mid.Z < b.mid.Z
    end)
    return edges
end

-------------------------------------------------------------------------------
-- addWindowPaneToAccumulator: convert a pane CFrame + Size into a front-face
-- quad and add it to the given MeshAccumulator.  The "front" face is the
-- +LookVector face of the CFrame (the outward-facing glass surface).
-------------------------------------------------------------------------------
local function addWindowPaneToAccumulator(acc, paneCFrame, paneSize)
    local halfW = paneSize.X * 0.5
    local halfH = paneSize.Y * 0.5
    local halfD = paneSize.Z * 0.5
    local right = paneCFrame.RightVector
    local up = paneCFrame.UpVector
    local look = paneCFrame.LookVector
    local center = paneCFrame.Position + look * halfD -- front face center

    local p1 = center - right * halfW - up * halfH
    local p2 = center + right * halfW - up * halfH
    local p3 = center + right * halfW + up * halfH
    local p4 = center - right * halfW + up * halfH
    acc:addQuad(p1, p2, p3, p4, look)

    -- Also add the back face so the pane is visible from inside
    local backCenter = paneCFrame.Position - look * halfD
    local bp1 = backCenter + right * halfW - up * halfH
    local bp2 = backCenter - right * halfW - up * halfH
    local bp3 = backCenter - right * halfW + up * halfH
    local bp4 = backCenter + right * halfW + up * halfH
    acc:addQuad(bp1, bp2, bp3, bp4, -look)
end

local function buildSimpleShellOpenings(
    parent,
    worldPts,
    baseY,
    height,
    windowBudget,
    usage,
    buildingId,
    windowAccumulators
)
    local edges = collectSimpleShellReadableEdges(worldPts)
    if #edges == 0 then
        return 0, 0
    end

    local doorCueCount = 0
    local windowPaneCount = 0
    local doorEdge = edges[1]
    local doorHeight = math.max(3.4, math.min(height - 1.1, 4.2))
    local doorWidth = math.clamp(doorEdge.len * 0.14, 1.8, 2.6)
    local doorDepth = 0.18
    local doorCenterY = baseY + doorHeight * 0.5
    local doorOutward = Vector3.new(-doorEdge.dir.Z, 0, doorEdge.dir.X) * 0.12

    local doorCue = Instance.new("Part")
    doorCue.Name = "SimpleShellDoorCue"
    doorCue.Size = Vector3.new(doorWidth, doorHeight, doorDepth)
    doorCue.Material = Enum.Material.WoodPlanks
    doorCue.Color = Color3.fromRGB(96, 76, 58)
    doorCue.Anchored = true
    doorCue.CanCollide = false
    doorCue.CastShadow = false
    doorCue.CFrame = CFrame.lookAt(
        doorEdge.mid + doorOutward + Vector3.new(0, doorCenterY, 0),
        doorEdge.mid + doorOutward + Vector3.new(0, doorCenterY, 0) + doorEdge.dir
    )
    doorCue.Parent = parent
    doorCueCount += 1

    local buildingIdHash = hashId(buildingId or "")
    local maxWindowEdges = math.min(#edges, 2)
    local maxWindows = if windowBudget and windowBudget.max then windowBudget.max else math.huge
    for edgeIndex = 1, maxWindowEdges do
        if windowBudget and windowBudget.used >= maxWindows then
            break
        end

        local edge = edges[edgeIndex]
        local paneCount = math.clamp(math.floor(edge.len / 12), 1, 2)
        local usableHalfSpan = math.max(1.4, edge.len * 0.28)
        local offsets
        if paneCount <= 1 then
            offsets = { 0 }
        else
            offsets = { -usableHalfSpan * 0.5, usableHalfSpan * 0.5 }
        end

        for _, offset in ipairs(offsets) do
            if windowBudget and windowBudget.used >= maxWindows then
                break
            end

            local paneCenter = edge.mid + edge.dir * offset
            local outward = Vector3.new(-edge.dir.Z, 0, edge.dir.X) * 0.13
            local shellTint = getWindowTint(usage, buildingIdHash, windowPaneCount)
            local paneSize = Vector3.new(math.min(2.1, math.max(1.4, edge.len * 0.08)), 1.65, 0.12)
            local paneCFrame = CFrame.lookAt(
                paneCenter + outward + Vector3.new(0, baseY + 2.9, 0),
                paneCenter + outward + Vector3.new(0, baseY + 2.9, 0) + edge.dir
            )
            if windowAccumulators then
                local tintKey = string.format(
                    "%d:%d:%d:%.2f",
                    math.floor(shellTint.color.R * 255 + 0.5),
                    math.floor(shellTint.color.G * 255 + 0.5),
                    math.floor(shellTint.color.B * 255 + 0.5),
                    shellTint.transparency
                )
                if not windowAccumulators[tintKey] then
                    windowAccumulators[tintKey] =
                        MeshAccumulator.new(parent, "window_glass_" .. tintKey, Enum.Material.Glass, shellTint.color, {
                            canCollide = false,
                            canQuery = false,
                            castShadow = false,
                            transparency = shellTint.transparency,
                            reflectance = 0.15,
                            collisionFidelity = Enum.CollisionFidelity.Box,
                        })
                end
                addWindowPaneToAccumulator(windowAccumulators[tintKey], paneCFrame, paneSize)
            else
                local pane = Instance.new("Part")
                pane.Name = "SimpleShellWindowPane"
                pane.Size = paneSize
                pane.Material = Enum.Material.Glass
                pane.Color = shellTint.color
                pane.Anchored = true
                pane.CanCollide = false
                pane.CastShadow = false
                pane.Transparency = shellTint.transparency
                pane:SetAttribute("BaseTransparency", shellTint.transparency)
                pane.CFrame = paneCFrame
                pane.Parent = parent
            end
            windowPaneCount += 1
            if windowBudget then
                windowBudget.used += 1
            end
        end
    end

    return doorCueCount, windowPaneCount
end

local function buildPilasters(parent, worldPts, baseY, height, material, color)
    for _, pt in ipairs(worldPts) do
        local pilaster = Instance.new("Part")
        pilaster.Name = "Pilaster"
        pilaster.Size = Vector3.new(0.4, height, 0.4)
        pilaster.Material = material
        -- Slightly lighter than wall for contrast
        pilaster.Color =
            Color3.new(math.min(1, color.R * 1.15), math.min(1, color.G * 1.15), math.min(1, color.B * 1.15))
        pilaster.Anchored = true
        pilaster.CanCollide = false
        pilaster.CastShadow = true
        pilaster.CFrame = CFrame.new(pt.X, baseY + height * 0.5, pt.Z)
        pilaster.Parent = parent
    end
end

local function buildRooftopParapet(parent, baseY, height, worldPts)
    local roofY = baseY + height
    local parapetHeight = 0.9
    local parapetThickness = 0.3

    for i = 1, #worldPts do
        local p1 = worldPts[i]
        local p2 = worldPts[(i % #worldPts) + 1]
        local edgeLen = (p2 - p1).Magnitude
        if edgeLen < 0.5 then
            continue
        end

        local mid = (p1 + p2) * 0.5
        local dir = (p2 - p1).Unit

        local parapet = Instance.new("Part")
        parapet.Name = "Parapet"
        parapet.Size = Vector3.new(edgeLen, parapetHeight, parapetThickness)
        parapet.Material = Enum.Material.Concrete
        parapet.Color = Color3.fromRGB(180, 175, 168)
        parapet.Anchored = true
        parapet.CanCollide = true
        parapet.CastShadow = false
        parapet.CFrame = CFrame.lookAt(
            mid + Vector3.new(0, roofY + parapetHeight * 0.5, 0),
            mid + Vector3.new(0, roofY + parapetHeight * 0.5, 0) + dir
        )
        CollectionService:AddTag(parapet, "LOD_Detail")
        parapet.Parent = parent
    end
end

local function buildRooftopEquipment(parent, building, baseY, height, worldPts)
    if not building.levels or building.levels < 3 then
        return
    end

    local cx, cz = 0, 0
    for _, p in ipairs(worldPts) do
        cx = cx + p.X
        cz = cz + p.Z
    end
    cx = cx / #worldPts
    cz = cz / #worldPts

    local roofY = baseY + height

    -- Compute footprint half-extents for offset clamping
    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    for _, p in ipairs(worldPts) do
        if p.X < minX then
            minX = p.X
        end
        if p.X > maxX then
            maxX = p.X
        end
        if p.Z < minZ then
            minZ = p.Z
        end
        if p.Z > maxZ then
            maxZ = p.Z
        end
    end
    local halfW = math.max(1, (maxX - minX) * 0.35)
    local halfD = math.max(1, (maxZ - minZ) * 0.35)

    local unitCount = math.min(3, math.floor(building.levels / 3))
    local buildingHash = hashId(building.id or "")
    local seed = buildingHash
    local equipmentType = buildingHash % 3

    for i = 1, unitCount do
        local offsetX = math.clamp(((seed * 7 + i * 13) % 20) - 10, -halfW / 0.3, halfW / 0.3)
        local offsetZ = math.clamp(((seed * 11 + i * 17) % 20) - 10, -halfD / 0.3, halfD / 0.3)

        local unit = Instance.new("Part")
        unit.Anchored = true
        unit.CanCollide = true

        if equipmentType % 3 == 1 then
            -- Antenna: thin vertical mast for taller buildings
            unit.Name = "Antenna"
            unit.Size = Vector3.new(0.3, 3, 0.3)
            unit.Material = Enum.Material.Metal
            unit.Color = Color3.fromRGB(140, 140, 145)
            unit.CFrame = CFrame.new(cx + offsetX * 0.3, roofY + 1.5, cz + offsetZ * 0.3)
        elseif equipmentType % 3 == 2 then
            -- Vent box: squat exhaust housing
            unit.Name = "VentBox"
            unit.Size = Vector3.new(1.5, 1, 1.5)
            unit.Material = Enum.Material.DiamondPlate
            unit.Color = Color3.fromRGB(150, 150, 155)
            unit.CFrame = CFrame.new(cx + offsetX * 0.3, roofY + 0.5, cz + offsetZ * 0.3)
        else
            -- AC unit (default)
            unit.Name = "ACUnit"
            unit.Size = Vector3.new(3, 2, 3)
            unit.Material = Enum.Material.Metal
            unit.Color = Color3.fromRGB(160, 160, 165)
            unit.CFrame = CFrame.new(cx + offsetX * 0.3, roofY + 1, cz + offsetZ * 0.3)
        end

        unit.Parent = parent
    end
end

local function buildAwning(parent, building, baseY, worldPts)
    local usage = building.usage or building.kind or ""
    if usage ~= "commercial" and usage ~= "retail" and usage ~= "restaurant" then
        return
    end

    -- Find the longest edge (likely the storefront)
    local bestLen = 0
    local bestP1, bestP2
    local n = #worldPts
    for i = 1, n do
        local p1 = worldPts[i]
        local p2 = worldPts[(i % n) + 1]
        local dx = p2.X - p1.X
        local dz = p2.Z - p1.Z
        local len = math.sqrt(dx * dx + dz * dz)
        if len > bestLen then
            bestLen = len
            bestP1 = p1
            bestP2 = p2
        end
    end

    if not bestP1 or bestLen < 6 then
        return
    end

    local mid = Vector3.new((bestP1.X + bestP2.X) * 0.5, 0, (bestP1.Z + bestP2.Z) * 0.5)
    local dx = bestP2.X - bestP1.X
    local dz = bestP2.Z - bestP1.Z
    local mag = math.sqrt(dx * dx + dz * dz)
    local dir = Vector3.new(dx / mag, 0, dz / mag)
    local outward = Vector3.new(-dir.Z, 0, dir.X)

    -- Deterministic awning color seeded from building ID
    local id = building.id or tostring(building)
    local h = hashId(id)
    local h2 = ((h * 33) + 7) % 2147483647
    local h3 = ((h2 * 33) + 13) % 2147483647
    local r = 120 + (h % 81) -- 120–200
    local g = 40 + (h2 % 41) -- 40–80
    local b = 30 + (h3 % 31) -- 30–60
    local awningColor = Color3.fromRGB(r, g, b)

    local awningDepth = 4 -- studs
    local awningY = baseY + 10 -- ~3m above ground floor

    local awning = Instance.new("Part")
    awning.Name = "Awning"
    awning.Size = Vector3.new(bestLen * 0.8, 0.3, awningDepth)
    awning.Material = Enum.Material.Fabric
    awning.Color = awningColor
    awning.Anchored = true
    awning.CanCollide = false
    awning.CFrame = CFrame.lookAt(
        mid + outward * (awningDepth * 0.5) + Vector3.new(0, awningY, 0),
        mid + outward * (awningDepth * 0.5) + Vector3.new(0, awningY, 0) + dir
    )
    awning.Parent = parent
end

local function setBuildingAuditAttributes(model, building, baseY, height, footprintData)
    local wallMaterial = getMaterial(building)
    local roofMaterial = getRoofMaterial(building, wallMaterial)
    local sourceId = if type(building.id) == "string" and building.id ~= "" then building.id else model.Name
    local chunkId = nil
    local importRunId = nil
    local cursor = model.Parent
    while cursor do
        if chunkId == nil then
            local candidateChunkId = cursor:GetAttribute("ArnisChunkId")
            if type(candidateChunkId) == "string" and candidateChunkId ~= "" then
                chunkId = candidateChunkId
            end
        end
        if importRunId == nil then
            local candidateImportRunId = cursor:GetAttribute("ArnisImportRunId")
            if type(candidateImportRunId) == "string" and candidateImportRunId ~= "" then
                importRunId = candidateImportRunId
            end
        end
        if chunkId ~= nil and importRunId ~= nil then
            break
        end
        cursor = cursor.Parent
    end

    model:SetAttribute("ArnisImportBuildingBaseY", baseY)
    model:SetAttribute("ArnisImportBuildingHeight", height)
    model:SetAttribute("ArnisImportBuildingTopY", baseY + height)
    model:SetAttribute("ArnisSourceId", sourceId)
    model:SetAttribute("ArnisImportSourceId", sourceId)
    if chunkId ~= nil then
        model:SetAttribute("ArnisChunkId", chunkId)
    end
    if importRunId ~= nil then
        model:SetAttribute("ArnisImportRunId", importRunId)
    end
    model:SetAttribute("ArnisImportBuildingUsage", string.lower(tostring(building.usage or building.kind or "unknown")))
    model:SetAttribute("ArnisImportRoofShape", string.lower(tostring(building.roof or "flat")))
    model:SetAttribute("ArnisImportRoofIncluded", building.roofIncluded == true)
    model:SetAttribute("ArnisImportWallMaterial", wallMaterial.Name)
    model:SetAttribute("ArnisImportRoofMaterial", roofMaterial.Name)
    if type(footprintData) == "table" then
        model:SetAttribute("ArnisImportBoundsMinX", footprintData.minX)
        model:SetAttribute("ArnisImportBoundsMaxX", footprintData.maxX)
        model:SetAttribute("ArnisImportBoundsMinZ", footprintData.minZ)
        model:SetAttribute("ArnisImportBoundsMaxZ", footprintData.maxZ)
    end
    if type(building.name) == "string" and building.name ~= "" then
        model:SetAttribute("ArnisImportBuildingName", building.name)
    end
end

-- Build a single building as polygon wall Parts + roof
-- windowBudget is an optional table { used = number, max = number } shared across a chunk.
function BuildingBuilder.FallbackBuild(parent, building, originStuds, chunk, windowBudget)
    local fp = building.footprint
    if not fp or #fp < 2 then
        return
    end

    local footprintData = buildFootprintData(fp, building.holes, originStuds)
    local baseY = resolveBuildingBaseY(building, originStuds, chunk)
    local height = getBuildingHeight(building)
    local roofOnly = isRoofOnlyStructure(building)
    local roofOnlyRooftopAttachment = false
    if roofOnly then
        baseY, height, roofOnlyRooftopAttachment = normalizeRoofOnlyPlacement(building, baseY, height)
    end
    local mat = getMaterial(building)
    local color = getColor(building)
    local bldgName = building.id or "Building"

    local model = Instance.new("Model")
    model.Name = bldgName
    trySetModelLevelOfDetail(model, Enum.ModelLevelOfDetail.Automatic)
    model.Parent = parent
    setBuildingAuditAttributes(model, building, baseY, height, footprintData)
    local shellFolder = Instance.new("Folder")
    shellFolder.Name = "Shell"
    shellFolder.Parent = model
    local detailFolder = Instance.new("Folder")
    detailFolder.Name = "Detail"
    detailFolder.Parent = model
    detailFolder:SetAttribute("ArnisLodGroupKind", "detail")
    detailFolder:SetAttribute("ArnisFacadeBeltlineCount", 0)
    detailFolder:SetAttribute("ArnisCorniceCount", 0)
    detailFolder:SetAttribute("ArnisCornerAccentCount", 0)
    detailFolder:SetAttribute("ArnisMergedShellRooflineCueCount", 0)
    detailFolder:SetAttribute("ArnisMergedShellPerimeterCueCount", 0)
    detailFolder:SetAttribute("ArnisMergedShellWallPresenceCueCount", 0)
    detailFolder:SetAttribute("ArnisMergedShellWallStripCount", 0)
    detailFolder:SetAttribute("ArnisMergedShellStreetFacadeCueCount", 0)
    detailFolder:SetAttribute("ArnisMergedShellDoorCueCount", 0)
    detailFolder:SetAttribute("ArnisMergedShellWindowPaneCueCount", 0)
    detailFolder:SetAttribute("ArnisSimpleShellDoorCueCount", 0)
    detailFolder:SetAttribute("ArnisSimpleShellWindowPaneCount", 0)
    CollectionService:AddTag(detailFolder, "LOD_DetailGroup")

    -- World coordinates of footprint vertices
    local worldPts = footprintData.worldPts
    for index, point in ipairs(worldPts) do
        worldPts[index] = Vector3.new(point.X, baseY, point.Z)
    end
    local preferSimpleShellDetail = shouldPreferSimpleShellDetail(building, #worldPts, height)
    local renderGlassFacadeBands = shouldRenderGlassFacadeBands(building, mat)

    if roofOnly then
        buildRoofOnlyStructure(
            model,
            building,
            worldPts,
            footprintData,
            baseY,
            height,
            color,
            mat,
            roofOnlyRooftopAttachment
        )
        return model
    end

    local n = #worldPts
    -- Sky-reflecting glass: higher Reflectance for that Cesium/Google Earth
    -- bluish curtain-wall sheen on near-ring towers. Named landmark
    -- buildings >20 studs tall also get a subtle PBR sheen (low reflectance
    -- bump) on any material so they read as "hero" structures in the skyline.
    local glassTransparency = if mat == Enum.Material.Glass then 0.28 else nil
    local glassReflectance = if mat == Enum.Material.Glass then 0.32 else nil
    if
        glassReflectance == nil
        and type(building.name) == "string"
        and building.name ~= ""
        and height >= 20
    then
        glassReflectance = 0.06
    end
    buildWallLoopParts(
        shellFolder,
        bldgName,
        worldPts,
        baseY,
        height,
        mat,
        color,
        "outer",
        glassTransparency,
        glassReflectance
    )
    for holeIndex, holeLoop in ipairs(footprintData.holeWorldLoops) do
        local liftedHoleLoop = table.create(#holeLoop)
        for pointIndex, point in ipairs(holeLoop) do
            liftedHoleLoop[pointIndex] = Vector3.new(point.X, baseY, point.Z)
        end
        buildWallLoopParts(
            shellFolder,
            bldgName,
            liftedHoleLoop,
            baseY,
            height,
            mat,
            color,
            string.format("inner%d", holeIndex),
            glassTransparency,
            glassReflectance
        )
    end

    -- Pilaster columns at each footprint corner for facade depth (levels >= 2 only)
    if not preferSimpleShellDetail and building.levels and building.levels >= 2 then
        buildPilasters(detailFolder, worldPts, baseY, height, mat, color)
    end

    -- Window bands for tall buildings (>= 3 floors, simple polygons only)
    -- Density varies by usage: read from WorldConfig.WindowSpacing when available,
    -- otherwise fall back to the local table. Gated by WorldConfig.EnableWindowRendering.
    local usage = building.usage or building.kind or "default"
    local WIN_SPACING = (WorldConfig.WindowSpacing and WorldConfig.WindowSpacing[usage])
        or (WorldConfig.WindowSpacing and WorldConfig.WindowSpacing.default)
        or getFacadeBandSpacing(usage, building.facadeStyle)
    local FACADE_INSET = getFacadeInset(usage)
    local buildingId = building.id or bldgName
    local FLOOR_H = 5
    local BAND_H = 2.5
    local numFloors = math.floor(height / FLOOR_H)
    local maxWindows = windowBudget and windowBudget.max
        or (WorldConfig.InstanceBudget and WorldConfig.InstanceBudget.MaxWindowsPerChunk)
        or 10000
    local facadePaneIndex = 0
    local facadeBuildingIdHash = hashId(buildingId or "")
    if
        not preferSimpleShellDetail
        and renderGlassFacadeBands
        and WorldConfig.EnableWindowRendering ~= false
        and numFloors >= 1
        and #worldPts <= 8
        and (#worldPts * numFloors * 2) <= 100
    then
        local budgetExceeded = false
        for floor = 1, math.min(numFloors - 1, 10) do
            if budgetExceeded then
                break
            end
            local bandY = baseY + floor * FLOOR_H + BAND_H * 0.5
            for i = 1, n do
                if budgetExceeded then
                    break
                end
                local p1w = worldPts[i]
                local p2w = worldPts[(i % n) + 1]
                local dx = p2w.X - p1w.X
                local dz = p2w.Z - p1w.Z
                local eLen = math.sqrt(dx * dx + dz * dz)
                if eLen < MIN_EDGE then
                    continue
                end
                local edgeUnitX = dx / eLen
                local edgeUnitZ = dz / eLen
                local numPanes = math.max(1, math.floor(eLen / WIN_SPACING))
                local bandLen = eLen * FACADE_INSET
                if numPanes >= 1 and bandLen > MIN_EDGE then
                    if windowBudget then
                        if windowBudget.used >= maxWindows then
                            budgetExceeded = true
                            break
                        end
                        windowBudget.used += 1
                    end
                    facadePaneIndex += 1
                    local tint = getWindowTint(usage, facadeBuildingIdHash, facadePaneIndex)
                    local band = Instance.new("Part")
                    band.Name = bldgName .. "_facade_" .. i .. "_" .. floor
                    band.Anchored = true
                    band.Size = Vector3.new(WALL_THICKNESS * 0.35, BAND_H * 0.8, bandLen)
                    band.CFrame = CFrame.lookAt(
                        Vector3.new((p1w.X + p2w.X) * 0.5, bandY, (p1w.Z + p2w.Z) * 0.5),
                        Vector3.new((p1w.X + p2w.X) * 0.5 + edgeUnitX, bandY, (p1w.Z + p2w.Z) * 0.5 + edgeUnitZ)
                    )
                    band.Material = Enum.Material.Glass
                    band.Color = tint.color
                    band.CastShadow = false
                    band.Transparency = tint.transparency
                    band:SetAttribute("BaseTransparency", tint.transparency)
                    band:SetAttribute("ArnisFacadePaneCount", numPanes)
                    band.Parent = detailFolder

                    -- Window sill: thin concrete ledge below each facade band
                    local paneW = bandLen
                    local windowCFrame = band.CFrame
                    local sill = Instance.new("Part")
                    sill.Name = "WindowSill"
                    sill.Size = Vector3.new(paneW + 0.4, 0.2, 0.5)
                    sill.Material = Enum.Material.Concrete
                    sill.Color = Color3.fromRGB(200, 195, 185)
                    sill.Anchored = true
                    sill.CanCollide = false
                    sill.CastShadow = false
                    sill.CFrame = windowCFrame * CFrame.new(0, -BAND_H * 0.4 - 0.1, 0.15)
                    sill.Parent = detailFolder
                end
            end
        end
    end

    -- Keep sparse low-rise shells legible with a cheap perimeter cue at street level.
    buildFoundation(detailFolder, worldPts, baseY)
    if preferSimpleShellDetail then
        detailFolder:SetAttribute(
            "ArnisFacadeBeltlineCount",
            buildFacadeBeltlines(detailFolder, worldPts, baseY, height)
        )
        detailFolder:SetAttribute("ArnisCornerAccentCount", buildCornerAccents(detailFolder, worldPts, baseY, height))
        local doorCueCount, windowPaneCount =
            buildSimpleShellOpenings(detailFolder, worldPts, baseY, height, windowBudget, usage, buildingId)
        detailFolder:SetAttribute("ArnisSimpleShellDoorCueCount", doorCueCount)
        detailFolder:SetAttribute("ArnisSimpleShellWindowPaneCount", windowPaneCount)
    end
    detailFolder:SetAttribute("ArnisCorniceCount", buildCornice(detailFolder, worldPts, baseY + height))
    if not preferSimpleShellDetail then
        buildAwning(detailFolder, building, baseY, worldPts)
    end

    -- Fill interior with terrain (uses terrain-safe floor materials only)
    fillInterior(footprintData.footprintXZ, footprintData.holeXZ, footprintData, baseY, getFloorMaterial(building))

    buildRoof(building, worldPts, footprintData, baseY, height, color, mat, shellFolder)

    if not preferSimpleShellDetail then
        buildRooftopEquipment(detailFolder, building, baseY, height, worldPts)
    end

    -- Building name label (from OSM name tag)
    if config.EnableBuildingNameLabels ~= false and building.name and building.name ~= "" then
        local nameLabel = Instance.new("BillboardGui")
        nameLabel.Name = "BuildingName"
        nameLabel.Size = UDim2.new(0, 200, 0, 50)
        nameLabel.StudsOffset = Vector3.new(0, height + 5, 0)
        nameLabel.AlwaysOnTop = false
        nameLabel.MaxDistance = 500

        local text = Instance.new("TextLabel")
        text.Size = UDim2.new(1, 0, 1, 0)
        text.BackgroundTransparency = 1
        text.Text = building.name
        text.TextColor3 = Color3.fromRGB(255, 255, 255)
        text.TextStrokeTransparency = 0.5
        text.TextSize = 18
        text.Font = Enum.Font.SourceSansBold
        text.Parent = nameLabel

        nameLabel.Parent = detailFolder
    end

    return model
end

-- PartBuild is the same as FallbackBuild (polygon walls)
BuildingBuilder.PartBuild = BuildingBuilder.FallbackBuild

function BuildingBuilder.BuildAll(parent, buildings, originStuds, chunk)
    if not buildings or #buildings == 0 then
        return {}
    end
    local windowBudget = {
        used = 0,
        max = WorldConfig.InstanceBudget and WorldConfig.InstanceBudget.MaxWindowsPerChunk or 10000,
    }
    local builtModelsById = {}
    for _, bldg in ipairs(buildings) do
        local model = BuildingBuilder.FallbackBuild(parent, bldg, originStuds, chunk, windowBudget)
        local buildingId = bldg.id
        if model and type(buildingId) == "string" and buildingId ~= "" then
            builtModelsById[buildingId] = model
        end
    end
    return builtModelsById
end

function BuildingBuilder.Build(parent, building, originStuds, chunk, windowBudget)
    return BuildingBuilder.FallbackBuild(parent, building, originStuds, chunk, windowBudget)
end

-------------------------------------------------------------------------------
-- Hero PBR Surfaces: procedural SurfaceAppearance with EditableImage textures
-- for landmark buildings in the near streaming ring.
-- Gated by WorldConfig.EnableHeroPBR (defaults true).
-------------------------------------------------------------------------------
local HERO_PBR_SIZE = 128
local HERO_PBR_MAX_PER_CHUNK = 10
local NAME_LABEL_MAX_PER_CHUNK = 50
local HERO_PBR_MIN_HEIGHT = 20

local heroPbrSupported = nil -- tri-state: nil=unknown, true/false

local function classifyPbrFacade(building)
    local usage = string.lower(tostring(building.usage or building.kind or "default"))
    if usage == "commercial" or usage == "office" or usage == "retail" then
        return "office"
    elseif usage == "industrial" or usage == "warehouse" then
        return "metal"
    else
        return "stone"
    end
end

local function generateOfficePbrTextures(size)
    local normalBuf = buffer.create(size * size * 4)
    local roughBuf = buffer.create(size * size * 4)
    local metalBuf = buffer.create(size * size * 4)
    local panelSpacing = math.floor(size / 8)
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local offset = (y * size + x) * 4
            local isJoint = (x % panelSpacing < 1) or (y % panelSpacing < 1)
            if isJoint then
                buffer.writeu8(normalBuf, offset, 128)
                buffer.writeu8(normalBuf, offset + 1, 118)
                buffer.writeu8(normalBuf, offset + 2, 230)
            else
                buffer.writeu8(normalBuf, offset, 128)
                buffer.writeu8(normalBuf, offset + 1, 128)
                buffer.writeu8(normalBuf, offset + 2, 255)
            end
            buffer.writeu8(normalBuf, offset + 3, 255)
            local roughVal = if isJoint then 90 else 51
            buffer.writeu8(roughBuf, offset, roughVal)
            buffer.writeu8(roughBuf, offset + 1, roughVal)
            buffer.writeu8(roughBuf, offset + 2, roughVal)
            buffer.writeu8(roughBuf, offset + 3, 255)
            buffer.writeu8(metalBuf, offset, 204)
            buffer.writeu8(metalBuf, offset + 1, 204)
            buffer.writeu8(metalBuf, offset + 2, 204)
            buffer.writeu8(metalBuf, offset + 3, 255)
        end
    end
    return normalBuf, roughBuf, metalBuf
end

local function generateStonePbrTextures(size)
    local normalBuf = buffer.create(size * size * 4)
    local roughBuf = buffer.create(size * size * 4)
    local metalBuf = buffer.create(size * size * 4)
    local function noise(x, y)
        local n = x * 374761393 + y * 668265263
        n = bit32.bxor(n, bit32.rshift(n, 13))
        n = n * 1274126177
        n = bit32.bxor(n, bit32.rshift(n, 16))
        return (n % 256) / 255
    end
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local offset = (y * size + x) * 4
            local n = noise(x, y)
            local nx = math.floor(128 + (n - 0.5) * 30)
            local ny = math.floor(128 + (noise(x + 37, y + 53) - 0.5) * 30)
            buffer.writeu8(normalBuf, offset, math.clamp(nx, 0, 255))
            buffer.writeu8(normalBuf, offset + 1, math.clamp(ny, 0, 255))
            buffer.writeu8(normalBuf, offset + 2, 240)
            buffer.writeu8(normalBuf, offset + 3, 255)
            local weathering = (y / size) * 30
            local roughVal = math.clamp(math.floor(153 + weathering + (n - 0.5) * 40), 0, 255)
            buffer.writeu8(roughBuf, offset, roughVal)
            buffer.writeu8(roughBuf, offset + 1, roughVal)
            buffer.writeu8(roughBuf, offset + 2, roughVal)
            buffer.writeu8(roughBuf, offset + 3, 255)
            buffer.writeu8(metalBuf, offset, 10)
            buffer.writeu8(metalBuf, offset + 1, 10)
            buffer.writeu8(metalBuf, offset + 2, 10)
            buffer.writeu8(metalBuf, offset + 3, 255)
        end
    end
    return normalBuf, roughBuf, metalBuf
end

local function generateMetalPbrTextures(size)
    local normalBuf = buffer.create(size * size * 4)
    local roughBuf = buffer.create(size * size * 4)
    local metalBuf = buffer.create(size * size * 4)
    local ribSpacing = math.floor(size / 6)
    local function noise(x, y)
        local n = x * 374761393 + y * 668265263
        n = bit32.bxor(n, bit32.rshift(n, 13))
        n = n * 1274126177
        n = bit32.bxor(n, bit32.rshift(n, 16))
        return (n % 256) / 255
    end
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local offset = (y * size + x) * 4
            local isRib = (x % ribSpacing < 2)
            if isRib then
                buffer.writeu8(normalBuf, offset, 160)
                buffer.writeu8(normalBuf, offset + 1, 128)
                buffer.writeu8(normalBuf, offset + 2, 230)
            else
                buffer.writeu8(normalBuf, offset, 128)
                buffer.writeu8(normalBuf, offset + 1, 128)
                buffer.writeu8(normalBuf, offset + 2, 255)
            end
            buffer.writeu8(normalBuf, offset + 3, 255)
            local n = noise(x, y)
            local corrosion = if n > 0.7 then 60 else 0
            local roughVal = math.clamp(math.floor(80 + corrosion + (n * 30)), 0, 255)
            buffer.writeu8(roughBuf, offset, roughVal)
            buffer.writeu8(roughBuf, offset + 1, roughVal)
            buffer.writeu8(roughBuf, offset + 2, roughVal)
            buffer.writeu8(roughBuf, offset + 3, 255)
            local metalVal = if n > 0.7 then 180 else 230
            buffer.writeu8(metalBuf, offset, metalVal)
            buffer.writeu8(metalBuf, offset + 1, metalVal)
            buffer.writeu8(metalBuf, offset + 2, metalVal)
            buffer.writeu8(metalBuf, offset + 3, 255)
        end
    end
    return normalBuf, roughBuf, metalBuf
end

local function createEditableImageFromBuffer(pixelBuf, size)
    local ok, img = pcall(function()
        return AssetService:CreateEditableImage({ Size = Vector2.new(size, size) })
    end)
    if not ok or not img then
        return nil
    end
    local writeOk = pcall(function()
        img:WritePixels(Vector2.new(0, 0), Vector2.new(size, size), pixelBuf)
    end)
    if not writeOk then
        return nil
    end
    return img
end

local function applyHeroPbrToMeshPart(meshPart, facadeType)
    if heroPbrSupported == false then
        return false
    end
    local normalBuf, roughBuf, metalBuf
    if facadeType == "office" then
        normalBuf, roughBuf, metalBuf = generateOfficePbrTextures(HERO_PBR_SIZE)
    elseif facadeType == "metal" then
        normalBuf, roughBuf, metalBuf = generateMetalPbrTextures(HERO_PBR_SIZE)
    else
        normalBuf, roughBuf, metalBuf = generateStonePbrTextures(HERO_PBR_SIZE)
    end
    local normalImg = createEditableImageFromBuffer(normalBuf, HERO_PBR_SIZE)
    local roughImg = createEditableImageFromBuffer(roughBuf, HERO_PBR_SIZE)
    local metalImg = createEditableImageFromBuffer(metalBuf, HERO_PBR_SIZE)
    if not normalImg or not roughImg or not metalImg then
        if heroPbrSupported == nil then
            heroPbrSupported = false
            warn("[HeroPBR] EditableImage creation failed — disabled for session")
        end
        return false
    end
    local saOk, sa = pcall(function()
        local surf = Instance.new("SurfaceAppearance")
        surf.NormalMap = Content.fromObject(normalImg)
        surf.RoughnessMap = Content.fromObject(roughImg)
        surf.MetalnessMap = Content.fromObject(metalImg)
        surf.Parent = meshPart
        return surf
    end)
    if not saOk then
        if heroPbrSupported == nil then
            heroPbrSupported = false
            warn("[HeroPBR] SurfaceAppearance creation failed — disabled for session: " .. tostring(sa))
        end
        return false
    end
    if heroPbrSupported == nil then
        heroPbrSupported = true
    end
    return true
end

local function isHeroPbrCandidate(building, height)
    return building.name and building.name ~= "" and height >= HERO_PBR_MIN_HEIGHT
end

local function applyHeroPbrToBuilding(shellFolder, building, height, pbrBudget)
    if pbrBudget.used >= HERO_PBR_MAX_PER_CHUNK then
        return 0
    end
    local facadeType = classifyPbrFacade(building)
    local applied = 0
    for _, child in ipairs(shellFolder:GetChildren()) do
        if pbrBudget.used >= HERO_PBR_MAX_PER_CHUNK then
            break
        end
        if child:IsA("MeshPart") then
            if applyHeroPbrToMeshPart(child, facadeType) then
                applied += 1
                pbrBudget.used += 1
            end
        end
    end
    return applied
end

-------------------------------------------------------------------------------
-- MeshBuildAll: merge wall + flat-roof geometry into per-material EditableMeshes.
-- Windows, awnings, name labels, shaped roofs, foundations, cornices, and
-- rooftop equipment remain as individual Instances (glass needs transparency,
-- shaped roofs use SpecialMesh/WedgePart).
-- Returns builtModelsById for RoomBuilder integration.
--
-- buildOptions.lodLevel controls detail generation:
--   "full"    (default/nil) = current behavior, all details
--   "reduced" = shell walls + roof only, skip windows/awnings/facade bands/rooftop equipment/name labels
--   "minimal" = single bounding-box Part per building, no EditableMesh
-------------------------------------------------------------------------------
local EMPTY_BUILD_STATS = {
    meshPartCount = 0,
    vertexCount = 0,
    triangleCount = 0,
    meshCreateMs = 0,
    shellDetailMs = 0,
    roofMeshPartCount = 0,
    roofBuildMs = 0,
    facadeDetailMs = 0,
    perimeterDetailMs = 0,
    mergedShellCueMs = 0,
    terrainFillMs = 0,
    rooftopDetailMs = 0,
    nameLabelMs = 0,
    nameLabelCount = 0,
    precomputedMeshCount = 0,
    runtimeMeshCount = 0,
}

local function buildMinimalLodBuildings(parent, buildings, originStuds, chunk, config, buildOptions)
    local builtModelsById = {}
    local buildStats = table.clone(EMPTY_BUILD_STATS)
    local meshCollisionPolicy = if type(buildOptions) == "table" then buildOptions.meshCollisionPolicy else nil
    local buildStartedAt = os.clock()

    for _, building in ipairs(buildings) do
        local fp = building.footprint
        if not fp or #fp < 2 then
            continue
        end

        local footprintData = buildFootprintData(fp, building.holes, originStuds)
        local baseY = resolveBuildingBaseY(building, originStuds, chunk)
        local height = getBuildingHeight(building)
        local roofOnly = isRoofOnlyStructure(building)
        if roofOnly then
            baseY, height = normalizeRoofOnlyPlacement(building, baseY, height)
        end
        local mat = getMaterial(building)
        local color = getColor(building)
        local bldgName = building.id or "Building"

        -- Compute bounding box from world-space footprint
        local worldPts = footprintData.worldPts
        local minX, maxX = math.huge, -math.huge
        local minZ, maxZ = math.huge, -math.huge
        for _, pt in ipairs(worldPts) do
            if pt.X < minX then minX = pt.X end
            if pt.X > maxX then maxX = pt.X end
            if pt.Z < minZ then minZ = pt.Z end
            if pt.Z > maxZ then maxZ = pt.Z end
        end
        local sizeX = math.max(maxX - minX, 0.5)
        local sizeZ = math.max(maxZ - minZ, 0.5)
        local centerX = (minX + maxX) * 0.5
        local centerZ = (minZ + maxZ) * 0.5

        local part = Instance.new("Part")
        part.Name = bldgName
        part.Anchored = true
        part.Size = Vector3.new(sizeX, height, sizeZ)
        part.CFrame = CFrame.new(centerX, baseY + height * 0.5, centerZ)
        part.Material = mat
        part.Color = color
        part.CastShadow = true
        if meshCollisionPolicy == "visual_only" then
            part.CanCollide = false
            part.CanQuery = false
        end
        part:SetAttribute("ArnisLodLevel", "minimal")
        part.Parent = parent

        local buildingId = building.id
        if type(buildingId) == "string" and buildingId ~= "" then
            builtModelsById[buildingId] = part
        end
        buildStats.meshPartCount += 1
    end

    buildStats.shellDetailMs = math.max(((os.clock() - buildStartedAt) * 1000), 0)
    return {
        builtModelsById = builtModelsById,
        stats = buildStats,
    }
end

function BuildingBuilder.MeshBuildAll(parent, buildings, originStuds, chunk, config, maybeYield, buildOptions)
    if not buildings or #buildings == 0 then
        return {
            builtModelsById = {},
            stats = table.clone(EMPTY_BUILD_STATS),
        }
    end

    config = config or WorldConfig
    local lodLevel = if type(buildOptions) == "table" then buildOptions.lodLevel else nil
    -- Normalize: nil or "full" means full detail
    if lodLevel ~= "reduced" and lodLevel ~= "minimal" then
        lodLevel = "full"
    end

    -- Minimal LOD: single bounding-box Part per building, no EditableMesh
    if lodLevel == "minimal" then
        return buildMinimalLodBuildings(parent, buildings, originStuds, chunk, config, buildOptions)
    end

    local meshCollisionPolicy = if type(buildOptions) == "table" then buildOptions.meshCollisionPolicy else nil

    local windowBudget = {
        used = 0,
        max = (config.InstanceBudget and config.InstanceBudget.MaxWindowsPerChunk) or 10000,
    }

    local builtModelsById = {}
    local buildStats = {
        meshPartCount = 0,
        vertexCount = 0,
        triangleCount = 0,
        meshCreateMs = 0,
        shellDetailMs = 0,
        roofMeshPartCount = 0,
        roofBuildMs = 0,
        facadeDetailMs = 0,
        perimeterDetailMs = 0,
        mergedShellCueMs = 0,
        terrainFillMs = 0,
        rooftopDetailMs = 0,
        nameLabelMs = 0,
        nameLabelCount = 0,
        precomputedMeshCount = 0,
        runtimeMeshCount = 0,
        heroPbrMs = 0,
        heroPbrCount = 0,
    }
    local buildStartedAt = os.clock()
    local enableHeroPbr = (config.EnableHeroPBR ~= false) and (WorldConfig.EnableHeroPBR ~= false)
    local pbrBudget = { used = 0 }

    -- Atlas consumer: decode the per-chunk PNG atlas once if available and opted-in.
    -- When the atlas is loaded, buildings with atlasUv get a shared SurfaceAppearance
    -- instead of per-building procedural EditableImage generation.
    local enableAtlas = (config.EnableBuildingAtlas == true) and (WorldConfig.EnableBuildingAtlas == true)
    local chunkAtlasImage = nil -- EditableImage from decoded RGBA atlas, or nil
    if enableAtlas and chunk and chunk.buildingAtlas and type(chunk.buildingAtlas.rgbaBase64) == "string" then
        local atlasOk, atlasImg = pcall(function()
            -- Decode base64 → raw RGBA pixel buffer via EncodingService (2025+).
            -- JSONDecode does NOT base64-decode — it only processes JSON escapes.
            local rgbaBuf = game:GetService("EncodingService"):Base64Decode(chunk.buildingAtlas.rgbaBase64)
            local img = AssetService:CreateEditableImage({
                Size = Vector2.new(
                    chunk.buildingAtlas.atlasWidth or 256,
                    chunk.buildingAtlas.atlasHeight or 256
                ),
            })
            img:WritePixelsBuffer(Vector2.new(0, 0), img.Size, rgbaBuf)
            return img
        end)
        if atlasOk and atlasImg then
            chunkAtlasImage = atlasImg
        end
    end

    for _, building in ipairs(buildings) do
        local fp = building.footprint
        if not fp or #fp < 2 then
            continue
        end

        local footprintData = buildFootprintData(fp, building.holes, originStuds)
        local baseY = resolveBuildingBaseY(building, originStuds, chunk)
        local height = getBuildingHeight(building)
        local roofOnly = isRoofOnlyStructure(building)
        local roofOnlyRooftopAttachment = false
        if roofOnly then
            baseY, height, roofOnlyRooftopAttachment = normalizeRoofOnlyPlacement(building, baseY, height)
        end
        local mat = getMaterial(building)
        local color = getColor(building)
        local bldgName = building.id or "Building"

        -- Per-building model for metadata, detail children, and RoomBuilder
        local model = Instance.new("Model")
        model.Name = bldgName
        trySetModelLevelOfDetail(model, Enum.ModelLevelOfDetail.Automatic)
        model.Parent = parent
        setBuildingAuditAttributes(model, building, baseY, height)
        model:SetAttribute("ArnisLodLevel", lodLevel)
        local shellFolder = Instance.new("Folder")
        shellFolder.Name = "Shell"
        shellFolder.Parent = model
        local detailFolder = Instance.new("Folder")
        detailFolder.Name = "Detail"
        detailFolder.Parent = model
        detailFolder:SetAttribute("ArnisLodGroupKind", "detail")
        detailFolder:SetAttribute("ArnisFacadeBeltlineCount", 0)
        detailFolder:SetAttribute("ArnisCorniceCount", 0)
        detailFolder:SetAttribute("ArnisCornerAccentCount", 0)
        detailFolder:SetAttribute("ArnisMergedShellRooflineCueCount", 0)
        detailFolder:SetAttribute("ArnisMergedShellPerimeterCueCount", 0)
        detailFolder:SetAttribute("ArnisMergedShellWallPresenceCueCount", 0)
        detailFolder:SetAttribute("ArnisMergedShellWallStripCount", 0)
        detailFolder:SetAttribute("ArnisMergedShellStreetFacadeCueCount", 0)
        detailFolder:SetAttribute("ArnisMergedShellDoorCueCount", 0)
        detailFolder:SetAttribute("ArnisSimpleShellDoorCueCount", 0)
        detailFolder:SetAttribute("ArnisSimpleShellWindowPaneCount", 0)
        CollectionService:AddTag(detailFolder, "LOD_DetailGroup")

        local buildingAccumulators = {}
        local function getAccumulator(accumMaterial, accumColor)
            local r = math.floor(accumColor.R * 255 + 0.5)
            local g = math.floor(accumColor.G * 255 + 0.5)
            local b = math.floor(accumColor.B * 255 + 0.5)
            local key = string.format("%s:%d:%d:%d", accumMaterial.Name, r, g, b)
            if not buildingAccumulators[key] then
                local accumulatorOptions = nil
                if meshCollisionPolicy == "visual_only" then
                    accumulatorOptions = {
                        canCollide = false,
                        canQuery = false,
                        collisionFidelity = Enum.CollisionFidelity.Box,
                    }
                end
                buildingAccumulators[key] =
                    MeshAccumulator.new(shellFolder, key, accumMaterial, accumColor, accumulatorOptions)
            end
            return buildingAccumulators[key]
        end

        local detailAccumulatorOptions = nil
        if meshCollisionPolicy == "visual_only" then
            detailAccumulatorOptions = {
                canCollide = false,
                canQuery = false,
                collisionFidelity = Enum.CollisionFidelity.Box,
            }
        end
        local detailAcc = MeshAccumulator.new(
            detailFolder,
            "detail_concrete",
            Enum.Material.Concrete,
            Color3.fromRGB(180, 175, 168),
            detailAccumulatorOptions
        )
        local sillAccumulatorOptions = {
            canCollide = false,
            castShadow = false,
        }
        if meshCollisionPolicy == "visual_only" then
            sillAccumulatorOptions.canQuery = false
            sillAccumulatorOptions.collisionFidelity = Enum.CollisionFidelity.Box
        end
        local sillAcc = MeshAccumulator.new(
            detailFolder,
            "window_sill",
            Enum.Material.Concrete,
            Color3.fromRGB(200, 195, 185),
            sillAccumulatorOptions
        )

        -- Window pane mesh accumulators: keyed by (color, transparency) so each
        -- distinct tint gets its own EditableMesh with correct Transparency.
        local mergeWindows = config.MergeWindowsIntoMesh ~= false
        local windowAccumulators = if mergeWindows then {} else nil
        local function getWindowAccumulator(tintColor, tintTransparency)
            if not windowAccumulators then
                return nil
            end
            local r = math.floor(tintColor.R * 255 + 0.5)
            local g = math.floor(tintColor.G * 255 + 0.5)
            local b = math.floor(tintColor.B * 255 + 0.5)
            local key = string.format("%d:%d:%d:%.2f", r, g, b, tintTransparency)
            if not windowAccumulators[key] then
                windowAccumulators[key] =
                    MeshAccumulator.new(detailFolder, "window_glass_" .. key, Enum.Material.Glass, tintColor, {
                        canCollide = false,
                        canQuery = false,
                        castShadow = false,
                        transparency = tintTransparency,
                        reflectance = 0.15,
                        collisionFidelity = Enum.CollisionFidelity.Box,
                    })
            end
            return windowAccumulators[key]
        end

        local buildingId = building.id
        if model and type(buildingId) == "string" and buildingId ~= "" then
            builtModelsById[buildingId] = model
        end

        -- World-space footprint vertices
        local worldPts = footprintData.worldPts
        for index, point in ipairs(worldPts) do
            worldPts[index] = Vector3.new(point.X, baseY, point.Z)
        end
        local preferSimpleShellDetail = shouldPreferSimpleShellDetail(building, #worldPts, height)
        local preferPlayVisibleShellWalls =
            shouldPreferPlayVisibleShellWalls(building, #worldPts, height, #footprintData.holeWorldLoops)
        local renderGlassFacadeBands = shouldRenderGlassFacadeBands(building, mat)

        if roofOnly then
            buildRoofOnlyStructure(
                model,
                building,
                worldPts,
                footprintData,
                baseY,
                height,
                color,
                mat,
                roofOnlyRooftopAttachment
            )
        else
            -- Glass buildings can't be merged (need per-face transparency)
            local isGlass = (mat == Enum.Material.Glass)

            if isGlass then
                -- Glass buildings: individual Parts (same as FallbackBuild shell)
                buildWallLoopParts(shellFolder, bldgName, worldPts, baseY, height, mat, color, "outer", 0.3, 0.15)
                for holeIndex, holeLoop in ipairs(footprintData.holeWorldLoops) do
                    local liftedHoleLoop = table.create(#holeLoop)
                    for pointIndex, point in ipairs(holeLoop) do
                        liftedHoleLoop[pointIndex] = Vector3.new(point.X, baseY, point.Z)
                    end
                    buildWallLoopParts(
                        shellFolder,
                        bldgName,
                        liftedHoleLoop,
                        baseY,
                        height,
                        mat,
                        color,
                        string.format("inner%d", holeIndex),
                        0.3,
                        0.15
                    )
                end
                local roofBuildStartedAt = os.clock()
                buildRoof(
                    building,
                    worldPts,
                    footprintData,
                    baseY,
                    height,
                    color,
                    mat,
                    shellFolder,
                    buildStats,
                    meshCollisionPolicy
                )
                recordBuildingDetailPhase(buildStats, "roofBuildMs", (os.clock() - roofBuildStartedAt) * 1000)
            else
                -- Accept both legacy JSON arrays AND B64-encoded mesh data.
                -- After the B64-only pipeline strip, vertices is nil but
                -- verticesB64 is present. Without this check, every B64
                -- building silently falls through to the runtime path and
                -- ALL osm2world precomputed geometry is discarded.
                local hasPrecomputedShellMesh =
                    building.shellMesh and (
                        (building.shellMesh.vertices and #building.shellMesh.vertices >= 9)
                        or (type(building.shellMesh.verticesB64) == "string" and #building.shellMesh.verticesB64 > 0)
                    )
                local shellMeshIncludesRoof = building.roofIncluded == true
                -- When the Rust pipeline provides a full shell mesh with roof,
                -- ALWAYS use it — even for small buildings that would normally
                -- get Part-based walls. The precomputed mesh has windowed walls
                -- and parametric roofs that look far better than the Part-based
                -- cue system, and produces 1 MeshPart instead of dozens of Parts.
                if preferPlayVisibleShellWalls and not (shellMeshIncludesRoof and hasPrecomputedShellMesh) then
                    -- Keep explicit wall parts only when no precomputed mesh exists.
                    buildWallLoopParts(shellFolder, bldgName, worldPts, baseY, height, mat, color, "outer")
                    for holeIndex, holeLoop in ipairs(footprintData.holeWorldLoops) do
                        local liftedHoleLoop = table.create(#holeLoop)
                        for pointIndex, point in ipairs(holeLoop) do
                            liftedHoleLoop[pointIndex] = Vector3.new(point.X, baseY, point.Z)
                        end
                        buildWallLoopParts(
                            shellFolder,
                            bldgName,
                            liftedHoleLoop,
                            baseY,
                            height,
                            mat,
                            color,
                            string.format("inner%d", holeIndex)
                        )
                    end
                    local playVisibleFacadeBeltlineCount, playVisibleRooflineCueCount, playVisibleCornerAccentCount, playVisibleDoorCueCount, playVisibleStreetFacadeCueCount, playVisibleWindowPaneCueCount =
                        buildPlayVisibleShellReadableCues(detailFolder, worldPts, baseY, height)
                    detailFolder:SetAttribute("ArnisFacadeBeltlineCount", playVisibleFacadeBeltlineCount)
                    detailFolder:SetAttribute("ArnisMergedShellRooflineCueCount", playVisibleRooflineCueCount)
                    detailFolder:SetAttribute("ArnisCornerAccentCount", playVisibleCornerAccentCount)
                    detailFolder:SetAttribute("ArnisMergedShellDoorCueCount", playVisibleDoorCueCount)
                    detailFolder:SetAttribute("ArnisMergedShellStreetFacadeCueCount", playVisibleStreetFacadeCueCount)
                    detailFolder:SetAttribute("ArnisMergedShellWindowPaneCueCount", playVisibleWindowPaneCueCount)
                else
                    -- Merge opaque walls into EditableMesh accumulators
                    local acc = getAccumulator(mat, color)
                    if hasPrecomputedShellMesh then
                        -- Fast path: load Rust pre-computed wall+roof mesh directly
                        acc:addPrecomputedMesh(building.shellMesh, originStuds)
                        buildStats.precomputedMeshCount += 1
                    else
                        -- Runtime path: generate wall geometry from footprint
                        buildStats.runtimeMeshCount += 1
                        addWallLoopToAccumulator(acc, worldPts, baseY, height)
                        for _, holeLoop in ipairs(footprintData.holeWorldLoops) do
                            local liftedHoleLoop = table.create(#holeLoop)
                            for pointIndex, point in ipairs(holeLoop) do
                                liftedHoleLoop[pointIndex] = Vector3.new(point.X, baseY, point.Z)
                            end
                            addWallLoopToAccumulator(acc, liftedHoleLoop, baseY, height)
                        end
                    end
                end

                if not (shellMeshIncludesRoof and hasPrecomputedShellMesh) then
                    -- Older shellMesh manifests carry walls only, so keep the explicit roof
                    -- path unless the manifest proves the precomputed mesh already contains it.
                    local roofBuildStartedAt = os.clock()
                    buildRoof(
                        building,
                        worldPts,
                        footprintData,
                        baseY,
                        height,
                        color,
                        mat,
                        shellFolder,
                        buildStats,
                        meshCollisionPolicy
                    )
                    recordBuildingDetailPhase(buildStats, "roofBuildMs", (os.clock() - roofBuildStartedAt) * 1000)
                end
            end
        end

        if not roofOnly and lodLevel == "full" then
            -- Window bands (individual glass Parts with transparency)
            local usage = building.usage or building.kind or "default"
            local WIN_SPACING = (config.WindowSpacing and config.WindowSpacing[usage])
                or (config.WindowSpacing and config.WindowSpacing.default)
                or getFacadeBandSpacing(usage, building.facadeStyle)
            local FACADE_INSET = getFacadeInset(usage)
            local buildingId = building.id or bldgName
            local FLOOR_H = 5
            local BAND_H = 2.5
            local n = #worldPts
            local numFloors = math.floor(height / FLOOR_H)
            local maxWindows = windowBudget.max
            local facadePaneIndex = 0
            local meshFacadeBuildingIdHash = hashId(buildingId or "")
            if
                not preferSimpleShellDetail
                and renderGlassFacadeBands
                and config.EnableWindowRendering ~= false
                and numFloors >= 1
                and n <= 8
                and (n * numFloors * 2) <= 100
            then
                local facadeDetailStartedAt = os.clock()
                local budgetExceeded = false
                for floor = 1, math.min(numFloors - 1, 10) do
                    if budgetExceeded then
                        break
                    end
                    local bandY = baseY + floor * FLOOR_H + BAND_H * 0.5
                    for i = 1, n do
                        if budgetExceeded then
                            break
                        end
                        local p1w = worldPts[i]
                        local p2w = worldPts[(i % n) + 1]
                        local dx = p2w.X - p1w.X
                        local dz = p2w.Z - p1w.Z
                        local eLen = math.sqrt(dx * dx + dz * dz)
                        if eLen < MIN_EDGE then
                            continue
                        end
                        local edgeUnitX = dx / eLen
                        local edgeUnitZ = dz / eLen
                        local numPanes = math.max(1, math.floor(eLen / WIN_SPACING))
                        local bandLen = eLen * FACADE_INSET
                        if numPanes >= 1 and bandLen > MIN_EDGE then
                            if windowBudget.used >= maxWindows then
                                budgetExceeded = true
                                break
                            end
                            windowBudget.used += 1
                            facadePaneIndex += 1
                            local tint = getWindowTint(usage, meshFacadeBuildingIdHash, facadePaneIndex)
                            local bandSize = Vector3.new(WALL_THICKNESS * 0.35, BAND_H * 0.8, bandLen)
                            local bandCFrame = CFrame.lookAt(
                                Vector3.new((p1w.X + p2w.X) * 0.5, bandY, (p1w.Z + p2w.Z) * 0.5),
                                Vector3.new((p1w.X + p2w.X) * 0.5 + edgeUnitX, bandY, (p1w.Z + p2w.Z) * 0.5 + edgeUnitZ)
                            )
                            local windowAcc = getWindowAccumulator(tint.color, tint.transparency)
                            if windowAcc then
                                addWindowPaneToAccumulator(windowAcc, bandCFrame, bandSize)
                            else
                                local band = Instance.new("Part")
                                band.Name = bldgName .. "_facade_" .. i .. "_" .. floor
                                band.Anchored = true
                                band.Size = bandSize
                                band.CFrame = bandCFrame
                                band.Material = Enum.Material.Glass
                                band.Color = tint.color
                                band.CastShadow = false
                                band.Transparency = tint.transparency
                                band:SetAttribute("BaseTransparency", tint.transparency)
                                band:SetAttribute("ArnisFacadePaneCount", numPanes)
                                band.Parent = detailFolder
                            end

                            local sillSize = Vector3.new(bandLen + 0.4, 0.2, 0.5)
                            local sillCenter = (bandCFrame * CFrame.new(0, -BAND_H * 0.4 - 0.1, 0.15)).Position
                            addOrientedBox(
                                sillAcc,
                                sillCenter,
                                bandCFrame.RightVector,
                                bandCFrame.UpVector,
                                bandCFrame.LookVector,
                                sillSize
                            )
                        end
                    end
                end
                recordBuildingDetailPhase(buildStats, "facadeDetailMs", (os.clock() - facadeDetailStartedAt) * 1000)
            end

            do
                local perimeterDetailStartedAt = os.clock()
                -- Foundation and cornice stay cheap enough to keep across both shell-detail paths.
                do
                    local nPts = #worldPts
                    for i = 1, nPts do
                        local p1 = worldPts[i]
                        local p2 = worldPts[(i % nPts) + 1]
                        local edgeVec = p2 - p1
                        local edgeLen = edgeVec.Magnitude
                        if edgeLen < 1 then
                            continue
                        end

                        local dir = edgeVec.Unit
                        -- Outward normal (perpendicular to edge in XZ plane)
                        local outward = Vector3.new(-dir.Z, 0, dir.X) * 0.1

                        -- Foundation: slightly protruding quad at base (1.5 studs tall)
                        detailAcc:addQuad(
                            p1 + outward + Vector3.new(0, baseY, 0),
                            p2 + outward + Vector3.new(0, baseY, 0),
                            p2 + outward + Vector3.new(0, baseY + 1.5, 0),
                            p1 + outward + Vector3.new(0, baseY + 1.5, 0),
                            outward.Unit
                        )
                    end
                end
                if preferSimpleShellDetail then
                    detailFolder:SetAttribute(
                        "ArnisFacadeBeltlineCount",
                        addFacadeBeltlinesToAccumulator(detailAcc, worldPts, baseY, height)
                    )
                    detailFolder:SetAttribute(
                        "ArnisCornerAccentCount",
                        addCornerAccentsToAccumulator(detailAcc, worldPts, baseY, height)
                    )
                    local doorCueCount, windowPaneCount = buildSimpleShellOpenings(
                        detailFolder,
                        worldPts,
                        baseY,
                        height,
                        windowBudget,
                        usage,
                        buildingId,
                        windowAccumulators
                    )
                    detailFolder:SetAttribute("ArnisSimpleShellDoorCueCount", doorCueCount)
                    detailFolder:SetAttribute("ArnisSimpleShellWindowPaneCount", windowPaneCount)
                elseif
                    shouldEmitMergedShellReadableCues(building, #worldPts, height, #footprintData.holeWorldLoops)
                then
                    local mergedShellCueStartedAt = os.clock()
                    local beltlineCount, cornerAccentCount, rooflineCueCount, perimeterCueCount, wallPresenceCueCount, streetFacadeCueCount, doorCueCount, windowPaneCueCount =
                        buildMergedShellReadableCues(detailFolder, worldPts, baseY, height)
                    detailFolder:SetAttribute("ArnisFacadeBeltlineCount", beltlineCount)
                    detailFolder:SetAttribute("ArnisCornerAccentCount", cornerAccentCount)
                    detailFolder:SetAttribute("ArnisMergedShellRooflineCueCount", rooflineCueCount)
                    detailFolder:SetAttribute("ArnisMergedShellPerimeterCueCount", perimeterCueCount)
                    detailFolder:SetAttribute("ArnisMergedShellWallPresenceCueCount", wallPresenceCueCount)
                    detailFolder:SetAttribute("ArnisMergedShellWallStripCount", wallPresenceCueCount)
                    detailFolder:SetAttribute("ArnisMergedShellStreetFacadeCueCount", streetFacadeCueCount)
                    detailFolder:SetAttribute("ArnisMergedShellDoorCueCount", doorCueCount)
                    detailFolder:SetAttribute("ArnisMergedShellWindowPaneCueCount", windowPaneCueCount)
                    recordBuildingDetailPhase(
                        buildStats,
                        "mergedShellCueMs",
                        (os.clock() - mergedShellCueStartedAt) * 1000
                    )
                end
                detailFolder:SetAttribute(
                    "ArnisCorniceCount",
                    addCorniceToAccumulator(detailAcc, worldPts, baseY + height)
                )

                if not preferSimpleShellDetail then
                    buildAwning(detailFolder, building, baseY, worldPts)
                end
                recordBuildingDetailPhase(
                    buildStats,
                    "perimeterDetailMs",
                    (os.clock() - perimeterDetailStartedAt) * 1000
                )
            end

            -- Fill interior with terrain
            if shouldFillTerrainInterior(building, config) then
                local terrainFillStartedAt = os.clock()
                fillInterior(
                    footprintData.footprintXZ,
                    footprintData.holeXZ,
                    footprintData,
                    baseY,
                    getFloorMaterial(building)
                )
                recordBuildingDetailPhase(buildStats, "terrainFillMs", (os.clock() - terrainFillStartedAt) * 1000)
            end

            if not preferSimpleShellDetail then
                local rooftopDetailStartedAt = os.clock()
                buildRooftopParapet(detailFolder, baseY, height, worldPts)
                buildRooftopEquipment(detailFolder, building, baseY, height, worldPts)
                recordBuildingDetailPhase(buildStats, "rooftopDetailMs", (os.clock() - rooftopDetailStartedAt) * 1000)
            end
        end

        -- Building name label (full LOD only, budget-capped)
        if lodLevel == "full" and config.EnableBuildingNameLabels ~= false
            and buildStats.nameLabelCount < NAME_LABEL_MAX_PER_CHUNK
            and building.name and building.name ~= "" then
            local nameLabelStartedAt = os.clock()

            -- Adornee: prefer model PrimaryPart, then first shell MeshPart
            local adornee = model.PrimaryPart
            if not adornee then
                for _, child in ipairs(shellFolder:GetChildren()) do
                    if child:IsA("MeshPart") then
                        adornee = child
                        break
                    end
                end
            end

            local nameLabel = Instance.new("BillboardGui")
            nameLabel.Name = "BuildingName"
            nameLabel.Size = UDim2.new(0, 200, 0, 50)
            nameLabel.StudsOffset = Vector3.new(0, height + 5, 0)
            nameLabel.AlwaysOnTop = false
            nameLabel.MaxDistance = 500
            if adornee then
                nameLabel.Adornee = adornee
            end

            local text = Instance.new("TextLabel")
            text.Size = UDim2.new(1, 0, 1, 0)
            text.BackgroundTransparency = 1
            text.Text = building.name
            text.TextColor3 = Color3.fromRGB(255, 255, 255)
            text.TextStrokeTransparency = 0.5
            text.TextSize = 18
            text.Font = Enum.Font.SourceSansBold
            text.Parent = nameLabel

            nameLabel.Parent = detailFolder
            buildStats.nameLabelCount += 1
            recordBuildingDetailPhase(buildStats, "nameLabelMs", (os.clock() - nameLabelStartedAt) * 1000)
        end

        for _, acc in pairs(buildingAccumulators) do
            acc:flush()
            recordMeshBuildStats(
                buildStats,
                acc.meshCount,
                acc.totalVertexCount,
                acc.totalTriangleCount,
                acc.totalMeshCreateMs,
                0
            )
            if maybeYield then
                maybeYield(false)
            end
        end
        detailAcc:flush()
        recordMeshBuildStats(
            buildStats,
            detailAcc.meshCount,
            detailAcc.totalVertexCount,
            detailAcc.totalTriangleCount,
            detailAcc.totalMeshCreateMs,
            0
        )
        if maybeYield then
            maybeYield(false)
        end
        sillAcc:flush()
        recordMeshBuildStats(
            buildStats,
            sillAcc.meshCount,
            sillAcc.totalVertexCount,
            sillAcc.totalTriangleCount,
            sillAcc.totalMeshCreateMs,
            0
        )
        if maybeYield then
            maybeYield(false)
        end
        if windowAccumulators then
            for _, wAcc in pairs(windowAccumulators) do
                wAcc:flush()
                recordMeshBuildStats(
                    buildStats,
                    wAcc.meshCount,
                    wAcc.totalVertexCount,
                    wAcc.totalTriangleCount,
                    wAcc.totalMeshCreateMs,
                    0
                )
                if maybeYield then
                    maybeYield(false)
                end
            end
        end

        -- Hero PBR: apply SurfaceAppearance to landmark buildings.
        -- Prefer chunk atlas when available; fall back to per-building procedural path.
        if enableHeroPbr and not roofOnly and isHeroPbrCandidate(building, height) then
            local heroPbrStartedAt = os.clock()
            local atlasApplied = false
            if chunkAtlasImage and building.atlasUv then
                -- Atlas fast path: crop per-building sub-image from chunk atlas
                local uv = building.atlasUv
                local atlasSize = chunkAtlasImage.Size
                local cropX = math.floor((uv.x or uv.uvX or 0) * atlasSize.X)
                local cropY = math.floor((uv.y or uv.uvY or 0) * atlasSize.Y)
                local cropW = math.clamp(math.floor((uv.width or uv.uvWidth or 0.125) * atlasSize.X), 1, atlasSize.X - cropX)
                local cropH = math.clamp(math.floor((uv.height or uv.uvHeight or 0.125) * atlasSize.Y), 1, atlasSize.Y - cropY)
                local cropOk, croppedImg = pcall(function()
                    local pixels = chunkAtlasImage:ReadPixelsBuffer(
                        Vector2.new(cropX, cropY),
                        Vector2.new(cropW, cropH)
                    )
                    local img = AssetService:CreateEditableImage({
                        Size = Vector2.new(cropW, cropH),
                    })
                    img:WritePixelsBuffer(Vector2.new(0, 0), Vector2.new(cropW, cropH), pixels)
                    return img
                end)
                if cropOk and croppedImg then
                    for _, child in ipairs(shellFolder:GetChildren()) do
                        if child:IsA("MeshPart") and pbrBudget.used < HERO_PBR_MAX_PER_CHUNK then
                            local saOk, _ = pcall(function()
                                local surf = Instance.new("SurfaceAppearance")
                                surf.ColorMap = Content.fromObject(croppedImg)
                                surf.Parent = child
                            end)
                            if saOk then
                                atlasApplied = true
                                buildStats.heroPbrCount += 1
                                pbrBudget.used += 1
                            end
                        end
                    end
                end
            end
            if not atlasApplied then
                local pbrApplied = applyHeroPbrToBuilding(shellFolder, building, height, pbrBudget)
                buildStats.heroPbrCount += pbrApplied
            end
            recordBuildingDetailPhase(buildStats, "heroPbrMs", (os.clock() - heroPbrStartedAt) * 1000)
        end

        -- Debug building visualization: color shell children and count wall parts
        if config.DebugBuildingColors then
            local debugWallCount = 0
            for _, child in ipairs(shellFolder:GetChildren()) do
                if child:IsA("BasePart") then
                    if child:GetAttribute("ArnisShellWallEvidence") then
                        child.Color = Color3.fromRGB(255, 0, 0)
                        child.Transparency = 0
                        debugWallCount += 1
                    elseif string.find(child.Name, "_roof") then
                        child.Color = Color3.fromRGB(0, 0, 255)
                        child.Transparency = 0
                    end
                elseif child:IsA("MeshPart") then
                    child.Color = Color3.fromRGB(255, 0, 0)
                    child.Transparency = 0
                    debugWallCount += 1
                end
            end
            model:SetAttribute("ArnisDebugWallCount", debugWallCount)
        end
    end

    buildStats.shellDetailMs = math.max(((os.clock() - buildStartedAt) * 1000) - buildStats.meshCreateMs, 0)

    if config.PerformanceLogging == true or WorldConfig.PerformanceLogging == true then
        -- ARNIS_BUILDER_PERF: single-line marker consumed by the harness /
        -- studio_workflow profiler to chart per-chunk builder cost. Shape is
        -- stable (key=value pairs); extend additively when adding new
        -- phases so existing parsers keep working.
        local chunkId = (chunk and chunk.ref and chunk.ref.id) or (chunk and chunk.id) or "unknown"
        print(string.format(
            "ARNIS_BUILDER_PERF chunk=%s buildings=%d lod=%s shellMs=%.2f roofMs=%.2f facadeMs=%.2f perimeterMs=%.2f rooftopMs=%.2f meshCreateMs=%.2f meshParts=%d verts=%d tris=%d precomputed=%d runtime=%d",
            tostring(chunkId),
            #buildings,
            tostring(lodLevel),
            buildStats.shellDetailMs,
            buildStats.roofBuildMs,
            buildStats.facadeDetailMs,
            buildStats.perimeterDetailMs,
            buildStats.rooftopDetailMs,
            buildStats.meshCreateMs,
            buildStats.meshPartCount,
            buildStats.vertexCount,
            buildStats.triangleCount,
            buildStats.precomputedMeshCount,
            buildStats.runtimeMeshCount
        ))
    end

    return {
        builtModelsById = builtModelsById,
        stats = buildStats,
    }
end

return BuildingBuilder
