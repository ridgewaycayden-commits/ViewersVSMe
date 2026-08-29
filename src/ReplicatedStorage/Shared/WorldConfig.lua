--[[
    WorldConfig — Central configuration for the Arnis HD Pipeline.

    All rendering parameters are configurable here. For open-source users:
    adjust these values based on your hardware capabilities.

    Hardware reference:
    - "insane" preset: M5 Max 36-128GB, RTX 4090+ equivalent
    - "high" preset: M3 Pro 18GB, RTX 3070 equivalent
    - "medium" preset: M1 8GB, GTX 1660 equivalent
]]

local WorldConfig = {
    -- ═══════════════════════════════════════════════════════════════
    -- CHUNK & SCALE
    -- ═══════════════════════════════════════════════════════════════
    ChunkSizeStuds = 256,

    -- ═══════════════════════════════════════════════════════════════
    -- MANIFEST SOURCE
    -- ═══════════════════════════════════════════════════════════════
    -- Controls where ManifestLoader pulls world data from. The default
    -- "embedded" path uses the Lua shards under
    -- `roblox/src/ServerStorage/SampleData/`. For shipping to the Roblox
    -- platform — where place files are capped at ~100MB-2GB — use
    -- "external_url" or "roblox_asset" so the place file stays small
    -- (~10MB of scripts) and the manifest streams from external storage.
    --
    -- Failures in any non-embedded mode automatically fall back to the
    -- embedded SampleData path so harness/dev workflows keep working.
    ManifestSource = {
        mode = "external_url", -- "embedded" | "external_url" | "roblox_asset"
        externalUrl = "https://planetary.adpena.workers.dev/manifests/austin/index.json",
        robloxAssetId = 0,
    },

    -- ═══════════════════════════════════════════════════════════════
    -- PLANETARY FILLER
    -- ═══════════════════════════════════════════════════════════════
    -- True infinite-scale streaming: when the player crosses outside any
    -- compiled city manifest region, PlanetaryFiller generates procedural
    -- ocean or satellite-textured terrain tiles on demand. This is the
    -- difference between "islands of detailed cities in a void" and
    -- "real Earth-scale planet you can fly anywhere across".
    PlanetaryFiller = {
        enabled = false, -- opt-in until satellite tile pipeline is fully proven
        seaLevelStuds = 0,
        tileChunkSize = 256,
        satelliteTileZoom = 14, -- coarser than city zoom 17 for performance
        oceanColor = Color3.fromRGB(20, 60, 100),
        -- Tile source — defaults to ESRI World Imagery (free, no key).
        -- Override with a Cloudflare Worker URL that decodes JPEG → RGBA:
        -- "https://planetary.adpena.workers.dev/tile/esri/{z}/{x}/{y}"
        tileUrlTemplate = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
        maxFillerTilesPerUpdate = 4, -- budget per streaming tick
    },

    -- ═══════════════════════════════════════════════════════════════
    -- RENDER MODES
    -- ═══════════════════════════════════════════════════════════════
    TerrainMode = "voxel", -- "none" | "debugParts" | "voxel"
    RoadMode = "mesh", -- "none" | "parts" | "mesh" | "hybrid"
    BuildingMode = "shellMesh", -- "none" | "shellParts" | "shellMesh" | "prefab"
    WaterMode = "mesh", -- "none" | "mesh"
    LanduseMode = "fill", -- "none" | "fill"

    -- ═══════════════════════════════════════════════════════════════
    -- TERRAIN FIDELITY
    -- ═══════════════════════════════════════════════════════════════
    VoxelSize = 1, -- studs; 1 = maximum smoothness (4 = fast, 2 = balanced)
    TerrainThickness = 8, -- studs below surface to fill with solid terrain
    SlopeRockThreshold = 1.0, -- rise/run ratio above which terrain becomes Rock (≈45°)
    SlopeGroundThreshold = 0.47, -- rise/run ratio above which terrain becomes Ground (≈25°)
    EnableTerrainSatelliteOverlay = true, -- overlay EditableMesh with satellite texture when available

    -- ═══════════════════════════════════════════════════════════════
    -- BUILDING FIDELITY
    -- ═══════════════════════════════════════════════════════════════
    EnableWindowRendering = true,
    MergeWindowsIntoMesh = true, -- batch window panes into EditableMesh (massive draw call reduction)
    EnableRoomInteriors = true,
    EnableHeroPBR = true,
    -- Tranche-3 streaming optimization: when true, the importer will look for
    -- a pre-baked chunk-scoped facade atlas (`chunk.buildingAtlas`) emitted by
    -- the Rust pipeline and index it via `building.atlasUv` instead of running
    -- the per-building EditableImage hero PBR path. Default off; flip on once
    -- the runtime atlas applier lands.
    EnableBuildingAtlas = false,
    EnableBuildingNameLabels = true,
    -- When true, BuildingBuilder.MeshBuildAll emits an ARNIS_BUILDER_PERF
    -- marker per chunk summarising time spent in shell / roof / facade /
    -- perimeter / rooftop / mesh-create phases. Off by default so production
    -- logs stay quiet; flip on when capturing a perf trace via the harness.
    PerformanceLogging = false,
    WindowSpacing = { -- studs between windows by building usage
        office = 4,
        residential = 6,
        apartments = 6,
        house = 6,
        warehouse = 12,
        industrial = 12,
        default = 8,
    },

    -- ═══════════════════════════════════════════════════════════════
    -- ROAD FIDELITY
    -- ═══════════════════════════════════════════════════════════════
    LaneWidth = 12, -- studs per lane (~3.6m at 0.3 m/stud)
    GroundRoadClearance = 0.75, -- studs above sampled terrain for roads/pathways to avoid burial/z-fighting
    EnableStreetLighting = true,
    StreetLightInterval = 50, -- studs between street lights
    StreetLightRange = 40, -- PointLight range in studs

    -- ═══════════════════════════════════════════════════════════════
    -- WATER FIDELITY
    -- ═══════════════════════════════════════════════════════════════
    WaterCarveDepth = 4, -- studs to carve below water surface

    -- ═══════════════════════════════════════════════════════════════
    -- TERRAIN MESH MODE (experimental)
    -- ═══════════════════════════════════════════════════════════════
    TerrainMeshMode = false, -- when true, use pre-computed heightfield MeshPart instead of per-cell FillBlock

    -- ═══════════════════════════════════════════════════════════════
    -- PROP FIDELITY
    -- ═══════════════════════════════════════════════════════════════
    TreeMetersToStuds = 1 / 0.3, -- conversion factor for real-world tree heights
    EnablePalmRendering = true,

    -- ═══════════════════════════════════════════════════════════════
    -- BUILDING LOD POLICY
    -- ═══════════════════════════════════════════════════════════════
    -- Controls building detail level per streaming ring.
    -- "full"    = all facade elements, windows, rooftop equipment, PBR surfaces
    -- "reduced" = shell walls + roof only, no windows/awnings/facade bands/rooftop equipment/name labels
    -- "minimal" = single bounding-box Part per building, no EditableMesh
    BuildingLodPolicy = {
        NearRingLod = "full",
        MidRingLod = "reduced",
        FarRingLod = "minimal",
    },
    EnableLodReimport = true, -- re-import buildings at higher detail when chunks move to a nearer ring

    -- ═══════════════════════════════════════════════════════════════
    -- STREAMING & LOD
    -- ═══════════════════════════════════════════════════════════════
    StreamingProfile = "local_dev", -- "local_dev" | "production_server"
    StreamingEnabled = false,
    StreamingTargetRadius = 4096,
    HighDetailRadius = 2048,
    StreamingUpdateIntervalSeconds = 0.15, -- faster update for smoother streaming (was 0.25)
    StreamingMaxWorkItemsPerUpdate = 6, -- more chunks per tick
    StreamingLookaheadSeconds = 1,
    StreamingMaxLookaheadStuds = 512,
    StreamingImportFrameBudgetSeconds = 1 / 240,
    -- ─── AIRCRAFT / HIGH-VELOCITY PREFETCH ───
    -- Controls how lookahead scales with player velocity. Walking-speed players
    -- use the base lookahead; vehicles and aircraft scale up so the streaming
    -- queue stays ahead of the player and avoids fall-through into empty chunks.
    -- Speeds are in studs/second; multipliers compose with StreamingLookaheadSeconds
    -- and are still capped by StreamingMaxLookaheadStuds.
    AircraftStreamingPolicy = {
        WalkingSpeedThreshold = 32,
        VehicleSpeedThreshold = 128,
        AircraftLookaheadMultiplier = 4,
        VehicleLookaheadMultiplier = 2,
        HighVelocityForcesMinimalLod = true,
    },
    -- NOTE: These top-level ring defaults are only used when no StreamingProfile
    -- matches. The active profile is "local_dev" which has reduced budgets
    -- (16/24/32 chunks) safe for 8GB tertiary. These larger values are for
    -- high-memory production hosts.
    StreamingRings = {
        near = {
            MaxRadiusStuds = 1024,
            EstimatedBudgetBytes = 1536 * 1024 * 1024,
            MaxChunkCount = 64,
        },
        mid = {
            MaxRadiusStuds = 1536,
            EstimatedBudgetBytes = 1536 * 1024 * 1024,
            MaxChunkCount = 96,
        },
        far = {
            MaxRadiusStuds = 2048,
            EstimatedBudgetBytes = 1024 * 1024 * 1024,
            MaxChunkCount = 128,
        },
    },
    MemoryGuardrails = {
        Enabled = true,
        EstimatedBudgetBytes = 4 * 1024 * 1024 * 1024,
        ResumeBudgetRatio = 0.85,
        CountResidentChunkCost = true,
        CountInFlightCost = true,
        HostProbe = {
            Enabled = false,
            CriticalAvailableBytes = nil,
            CriticalPressureLevel = nil,
        },
    },
    SubplanRollout = {
        Enabled = true,
        AllowedLayers = {},
        AllowedChunkIds = {},
    },
    -- ─── MULTIPLAYER STREAMING ───
    -- Server-authoritative multi-player chunk streaming. When enabled, the
    -- server tracks every connected player's focus position (camera + velocity)
    -- and computes the desired chunk set as the union across all players' near
    -- rings, with per-chunk LOD set to the maximum demanded by any player.
    -- Default is OFF to preserve the existing single-player client-driven path.
    -- Opt in for multi-player worlds by overriding in a StreamingProfile or at
    -- runtime.
    MultiplayerStreaming = {
        enabled = false,
        maxPlayers = 8,
        perPlayerStreamingRadius = 1024,
        -- How many seconds ahead of each player to predict for prefetch (server
        -- extrapolates position from the most recently reported velocity).
        velocityPredictionSeconds = 2,
        -- Cadence at which clients should report camera position to the server.
        clientReportIntervalSeconds = 0.1,
        -- If a player has not reported a position in this many seconds, fall
        -- back to the player's HumanoidRootPart position (if any) and finally
        -- skip them entirely. Prevents stale focal points from pinning chunks.
        staleFocusTimeoutSeconds = 5,
    },
    StreamingProfiles = {
        local_dev = {
            StreamingEnabled = true,
            StreamingTargetRadius = 3072,
            HighDetailRadius = 1536,
            StreamingMaxWorkItemsPerUpdate = 4, -- doubled for faster chunk throughput
            StreamingLookaheadSeconds = 2, -- look further ahead for aircraft/jetpack
            StreamingMaxLookaheadStuds = 1024, -- 4 chunks ahead at speed
            StreamingRings = {
                near = {
                    MaxRadiusStuds = 768,
                    -- Post-osm2world: chunks average 3.3MB with windowed walls + roofs.
                    -- At 768-stud radius with 256-stud chunks, the near ring covers
                    -- ~6×6 = 36 chunks. MaxChunkCount must be >= 36 or chunks cycle
                    -- in/out causing visible flicker. Budget raised proportionally.
                    EstimatedBudgetBytes = 2 * 1024 * 1024 * 1024,
                    MaxChunkCount = 48,
                },
                mid = {
                    MaxRadiusStuds = 1536,
                    EstimatedBudgetBytes = 2 * 1024 * 1024 * 1024,
                    MaxChunkCount = 64,
                },
                far = {
                    MaxRadiusStuds = 3072,
                    EstimatedBudgetBytes = 1024 * 1024 * 1024,
                    MaxChunkCount = 64,
                },
            },
            MemoryGuardrails = {
                Enabled = true,
                -- Post-osm2world: richer geometry needs more headroom.
                EstimatedBudgetBytes = 6 * 1024 * 1024 * 1024,
                ResumeBudgetRatio = 0.85,
                HostProbe = {
                    Enabled = true,
                    CriticalAvailableBytes = 256 * 1024 * 1024,
                    CriticalPressureLevel = 0.95,
                },
            },
            SubplanRollout = {
                Enabled = true,
                AllowedLayers = {},
                AllowedChunkIds = {},
            },
        },
        production_server = {
            StreamingEnabled = true,
            StreamingTargetRadius = 8192, -- 8km visibility radius for planetary streaming
            HighDetailRadius = 4096,
            StreamingMaxWorkItemsPerUpdate = 12, -- aggressive chunk throughput
            StreamingLookaheadSeconds = 3, -- 3 seconds ahead at aircraft speed
            StreamingMaxLookaheadStuds = 2048, -- 8 chunks ahead
            StreamingImportFrameBudgetSeconds = 1 / 90, -- ~11ms budget per frame (leaves 5ms for rendering)
            StreamingRings = {
                near = {
                    MaxRadiusStuds = 3072,
                    EstimatedBudgetBytes = 3 * 1024 * 1024 * 1024,
                    MaxChunkCount = 128,
                },
                mid = {
                    MaxRadiusStuds = 4608,
                    EstimatedBudgetBytes = 3 * 1024 * 1024 * 1024,
                    MaxChunkCount = 192,
                },
                far = {
                    MaxRadiusStuds = 6144,
                    EstimatedBudgetBytes = 2 * 1024 * 1024 * 1024,
                    MaxChunkCount = 256,
                },
            },
            MemoryGuardrails = {
                Enabled = true,
                EstimatedBudgetBytes = 8 * 1024 * 1024 * 1024,
                ResumeBudgetRatio = 0.9,
                HostProbe = {
                    Enabled = false,
                },
            },
            SubplanRollout = {
                Enabled = true,
                AllowedLayers = {},
                AllowedChunkIds = {},
            },
        },
    },

    -- ═══════════════════════════════════════════════════════════════
    -- ATMOSPHERE & LIGHTING
    -- ═══════════════════════════════════════════════════════════════
    EnableAtmosphere = true, -- set false to skip cinematic lighting setup
    EnableDayNightCycle = true,
    DayNightSpeed = 60, -- 60 = 1 game-day per 24 minutes, 0 = frozen
    DateTime = "2024-06-15T14:00", -- Fixed midday for consistent visual proof; change to "auto" for real-time
    AtmosphereDensity = 0.1, -- minimal; previous values were compounding with DayNightCycle
    AtmosphereOffset = 0.1,
    AtmosphereHaze = 0.0, -- zero additive haze; DayNightCycle provides its own

    -- ═══════════════════════════════════════════════════════════════
    -- MINIMAP
    -- ═══════════════════════════════════════════════════════════════
    EnableMinimap = true,
    MinimapRadius = 400, -- world studs visible in minimap
    MinimapSize = 200, -- pixel resolution

    -- ═══════════════════════════════════════════════════════════════
    -- AMBIENT CITY LIFE
    -- ═══════════════════════════════════════════════════════════════
    EnableAmbientLife = true,
    MaxParkedCarsPerChunk = 30,
    MaxNPCsPerChunk = 8,

    -- ═══════════════════════════════════════════════════════════════
    -- VEHICLE / TRAVERSAL PHYSICS
    -- ═══════════════════════════════════════════════════════════════
    -- These values are reference documentation for the VehicleController.
    -- To tune, edit the constants at the top of VehicleController.client.lua.
    VehiclePhysics = {
        CarMaxSpeed = 120,
        CarMotorAngularVel = 45,
        CarTorque = 1800,
        CarSteerAngle = 35,
        CarHighSpeedSteerFactor = 0.4,
        SuspensionStiffness = 1200,
        SuspensionDamping = 120,
    },
    JetpackPhysics = {
        MaxThrust = 5000,
        RampTime = 0.4,
        Damping = 0.55,
        MaxHorizontalSpeed = 80,
        MaxVerticalSpeed = 60,
        FuelMax = 60,
    },
    ParachutePhysics = {
        GlideRatio = 3.0,
        DescentRate = 8,
        TurnRate = 1.6,
        FlareLift = 5,
        FlareStallTime = 3.0,
        HorizontalDrag = 0.15,
    },

    -- ═══════════════════════════════════════════════════════════════
    -- DEBUG VISUALIZATION
    -- ═══════════════════════════════════════════════════════════════
    DebugBuildingColors = false, -- walls=RED, roofs=BLUE, floors=YELLOW; makes broken buildings instantly visible

    -- ═══════════════════════════════════════════════════════════════
    -- INSTANCE BUDGETS (set high for powerful hardware)
    -- ═══════════════════════════════════════════════════════════════
    InstanceBudget = {
        MaxPerChunk = 8000,
        MaxPropsPerChunk = 2000,
        MaxWindowsPerChunk = 10000, -- effectively unlimited on M5 Max
    },
}

return WorldConfig
