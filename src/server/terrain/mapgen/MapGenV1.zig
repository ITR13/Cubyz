const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Array2D = main.utils.Array2D;
const random = main.random;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const MapFragment = terrain.SurfaceMap.MapFragment;
const noise = terrain.noise;
const FractalNoise = noise.FractalNoise;
const RandomlyWeightedFractalNoise = noise.RandomlyWeightedFractalNoise;
const PerlinNoise = noise.PerlinNoise;

pub const id = "cubyz:mapgen_v1";

pub fn init(parameters: JsonElement) void {
	_ = parameters;
}

pub fn deinit() void {

}

/// Assumes the 4 points are at tᵢ = (-1, 0, 1, 2)
fn cubicInterpolationWeights(t: f32) [4]f32 {
	const t2 = t*t;
	const t3 = t*t2;
	return [4]f32 { // Using the Lagrange polynomials:
		-1.0/6.0*(t3 - 3*t2 + 2*t),
		 1.0/2.0*(t3 - 2*t2 - t + 2),
		-1.0/2.0*(t3 - t2 - 2*t),
		 1.0/6.0*(t3 - t),
	};
}

pub fn generateMapFragment(map: *MapFragment, worldSeed: u64) Allocator.Error!void {
	const scaledSize = MapFragment.mapSize;
	const mapSize = scaledSize*map.pos.voxelSize;
	const biomeSize = MapFragment.biomeSize;
	const offset = 8;
	const biomePositions = try terrain.ClimateMap.getBiomeMap(main.threadAllocator, map.pos.wx - offset*biomeSize, map.pos.wz - offset*biomeSize, mapSize + 2*offset*biomeSize, mapSize + 2*offset*biomeSize);
	defer biomePositions.deinit(main.threadAllocator);
	const TerrainData = struct {
		height: f32,
		roughness: f32,
		hills: f32,
		mountains: f32,
	};
	const terrainData = try Array2D(TerrainData).init(main.threadAllocator, biomePositions.width, biomePositions.height);
	defer terrainData.deinit(main.threadAllocator);
	for(biomePositions.mem, terrainData.mem) |biomePoint, *terrainPoint| {
		//var seed: u64 = biomePoint.seed ^ 54738964378901;
		terrainPoint.* = .{
			.height = @as(f32, @floatFromInt(biomePoint.biome.minHeight)) + 0.5*@as(f32, @floatFromInt(biomePoint.biome.maxHeight - biomePoint.biome.minHeight)), // TODO: Randomize
			.roughness = biomePoint.biome.roughness,
			.hills = biomePoint.biome.hills,
			.mountains = biomePoint.biome.mountains,
		};
	}
	for(0..0) |_| { // TODO? Smooth the biome heights.
		for(1..biomePositions.width-1) |x| {
			for(1..biomePositions.height-1) |z| {
				var minHeight: f32 = std.math.floatMax(f32);
				var maxHeight: f32 = -std.math.floatMax(f32);
				for(0..3) |dx| {
					for(0..3) |dz| {
						minHeight = @min(minHeight, terrainData.get(x - 1 + dx, z - 1 + dz).height);
						maxHeight = @max(maxHeight, terrainData.get(x - 1 + dx, z - 1 + dz).height);
					}
				}
				var newHeight = (minHeight + maxHeight)/2;
				newHeight = @min(newHeight, @as(f32, @floatFromInt(biomePositions.get(x, z).biome.maxHeight)));
				newHeight = @max(newHeight, @as(f32, @floatFromInt(biomePositions.get(x, z).biome.minHeight)));
				terrainData.ptr(x, z).height = newHeight;
			}
		}
	}
	var seed = worldSeed;
	random.scrambleSeed(&seed);
	seed = @as(u32, @bitCast((random.nextInt(i32, &seed) | 1)*%map.pos.wx ^ (random.nextInt(i32, &seed) | 1)*%map.pos.wz)); // TODO: Use random.initSeed2D();
	random.scrambleSeed(&seed);
	
	const xOffsetMap = try Array2D(f32).init(main.threadAllocator, scaledSize, scaledSize);
	defer xOffsetMap.deinit(main.threadAllocator);
	const zOffsetMap = try Array2D(f32).init(main.threadAllocator, scaledSize, scaledSize);
	defer zOffsetMap.deinit(main.threadAllocator);
	try FractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wz, biomeSize*4, worldSeed ^ 675396758496549, xOffsetMap, map.pos.voxelSize);
	try FractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wz, biomeSize*4, worldSeed ^ 543864367373859, zOffsetMap, map.pos.voxelSize);

	// A ridgid noise map to generate interesting mountains.
	const mountainMap = try Array2D(f32).init(main.threadAllocator, scaledSize, scaledSize);
	defer mountainMap.deinit(main.threadAllocator);
	try RandomlyWeightedFractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wz, 64, worldSeed ^ 6758947592930535, mountainMap, map.pos.voxelSize);

	// A smooth map for smaller hills.
	const hillMap = try PerlinNoise.generateSmoothNoise(main.threadAllocator, map.pos.wx, map.pos.wz, mapSize, mapSize, 128, 32, worldSeed ^ 157839765839495820, map.pos.voxelSize, 0.5);
	defer hillMap.deinit(main.threadAllocator);

	// A fractal map to generate high-detail roughness.
	const roughMap = try Array2D(f32).init(main.threadAllocator, scaledSize, scaledSize);
	defer roughMap.deinit(main.threadAllocator);
	try FractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wz, 64, worldSeed ^ 954936678493, roughMap, map.pos.voxelSize);

	var x: u31 = 0;
	while(x < map.heightMap.len) : (x += 1) {
		var z: u31 = 0;
		while(z < map.heightMap.len) : (z += 1) {
			// Do the biome interpolation:
			var height: f32 = 0;
			var roughness: f32 = 0;
			var hills: f32 = 0;
			var mountains: f32 = 0;
			const wx: f32 = @floatFromInt(x*map.pos.voxelSize + map.pos.wx);
			const wz: f32 = @floatFromInt(z*map.pos.voxelSize + map.pos.wz);
			var updatedX = wx + (xOffsetMap.get(x, z) - 0.5)*biomeSize*4;
			var updatedZ = wz + (zOffsetMap.get(x, z) - 0.5)*biomeSize*4;
			var xBiome: i32 = @intFromFloat(@floor((updatedX - @as(f32, @floatFromInt(map.pos.wx)))/biomeSize));
			var zBiome: i32 = @intFromFloat(@floor((updatedZ - @as(f32, @floatFromInt(map.pos.wz)))/biomeSize));
			var relXBiome = (0.5 + updatedX - @as(f32, @floatFromInt(map.pos.wx +% xBiome*biomeSize)))/biomeSize;
			xBiome += offset;
			var relZBiome = (0.5 + updatedZ - @as(f32, @floatFromInt(map.pos.wz +% zBiome*biomeSize)))/biomeSize;
			zBiome += offset;
			const coefficientsX = cubicInterpolationWeights(relXBiome);
			const coefficientsZ = cubicInterpolationWeights(relZBiome);
			for(0..4) |dx| {
				for(0..4) |dz| {
					const biomeMapX = @as(usize, @intCast(xBiome)) + dx - 1;
					const biomeMapZ = @as(usize, @intCast(zBiome)) + dz - 1;
					const weight = coefficientsX[dx]*coefficientsZ[dz];
					const terrainPoint = terrainData.get(biomeMapX, biomeMapZ);
					height += terrainPoint.height*weight;
					roughness += terrainPoint.roughness*weight;
					hills += terrainPoint.hills*weight;
					mountains += terrainPoint.mountains*weight;
				}
			}
			height += (roughMap.get(x, z) - 0.5)*2*roughness;
			height += (hillMap.get(x, z) - 0.5)*2*hills;
			height += (mountainMap.get(x, z) - 0.5)*2*mountains;
			map.heightMap[x][z] = height;
			map.minHeight = @min(map.minHeight, height);
			map.minHeight = @max(map.minHeight, 0);
			map.maxHeight = @max(map.maxHeight, height);


			// Select a biome. Also adding some white noise to make a smoother transition.
			updatedX += random.nextFloatSigned(&seed)*3.5*biomeSize/128;
			updatedZ += random.nextFloatSigned(&seed)*3.5*biomeSize/128;
			xBiome = @intFromFloat(@round((updatedX - @as(f32, @floatFromInt(map.pos.wx)))/biomeSize));
			xBiome += offset;
			zBiome = @intFromFloat(@round((updatedZ - @as(f32, @floatFromInt(map.pos.wz)))/biomeSize));
			zBiome += offset;
			var shortestDist: f32 = std.math.floatMax(f32);
			var shortestBiomePoint: terrain.ClimateMap.BiomePoint = undefined;
			var x0 = xBiome;
			while(x0 <= xBiome + 2) : (x0 += 1) {
				var z0 = zBiome;
				while(z0 <= zBiome + 2) : (z0 += 1) {
					const distSquare = biomePositions.get(@intCast(xBiome), @intCast(zBiome)).distSquare(updatedX, updatedZ);
					if(distSquare < shortestDist) {
						shortestDist = distSquare;
						shortestBiomePoint = biomePositions.get(@intCast(xBiome), @intCast(zBiome));
					}
				}
			}
			map.biomeMap[x][z] = shortestBiomePoint.getFittingReplacement(@intFromFloat(height + random.nextFloat(&seed)*4 - 2));
		}
	}
}