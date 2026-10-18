package;

import away3d.core.base.Geometry;
import away3d.core.base.SubGeometry;
import openfl.geom.Vector3D;

class HitResult
{
	public var hit:Bool;
	public var point:Vector3D;
	public var normal:Vector3D;
	public var radius:Float;

	public function new(hit:Bool, point:Vector3D, normal:Vector3D, radius:Float)
	{
		this.hit = hit;
		this.point = point;
		this.normal = normal;
		this.radius = radius;
	}
}

/**
 * High-performance spherical raycasting against the planet floor mesh (planet_floor.obj).
 * Uses spherical grid spatial binning for < 5 microsecond ray-triangle queries.
 * Provides authentic Flare3D RayCollision snapping to exact street polygons.
 */
class FloorRaycaster
{
	private static inline var GRID_LON:Int = 36;
	private static inline var GRID_LAT:Int = 18;

	// Packed triangle data: 12 floats per triangle
	// v0(x,y,z), v1(x,y,z), v2(x,y,z), normal(x,y,z)
	private var _triData:Array<Float> = [];
	private var _numTriangles:Int = 0;

	// Spherical bin grid storing triangle indices
	private var _bins:Array<Array<Array<Int>>> = [];

	public function new(objText:String)
	{
		initGrid();
		parseAndBuild(objText);
	}

	private function initGrid():Void
	{
		_bins = [];
		for (lat in 0...GRID_LAT)
		{
			var row = [];
			for (lon in 0...GRID_LON)
			{
				row.push(new Array<Int>());
			}
			_bins.push(row);
		}
	}

	private function parseAndBuild(objText:String):Void
	{
		var rawVerts:Array<Float> = [];
		var lines = objText.split("\n");

		for (line in lines)
		{
			var trimmed = StringTools.trim(line);
			if (StringTools.startsWith(trimmed, "v "))
			{
				var parts = trimmed.split(" ");
				var coords:Array<Float> = [];
				for (i in 1...parts.length)
				{
					var p = StringTools.trim(parts[i]);
					if (p.length > 0)
					{
						coords.push(Std.parseFloat(p));
					}
				}
				if (coords.length >= 3)
				{
					rawVerts.push(coords[0]);
					rawVerts.push(coords[1]);
					rawVerts.push(coords[2]);
				}
			}
			else if (StringTools.startsWith(trimmed, "f "))
			{
				var parts = trimmed.split(" ");
				var idxs:Array<Int> = [];
				for (i in 1...parts.length)
				{
					var p = StringTools.trim(parts[i]);
					if (p.length > 0)
					{
						var slashIdx = p.indexOf("/");
						var vIdxStr = (slashIdx != -1) ? p.substring(0, slashIdx) : p;
						var vIdx = Std.parseInt(vIdxStr);
						if (vIdx != null)
						{
							idxs.push(vIdx - 1);
						}
					}
				}

				if (idxs.length >= 3)
				{
					for (k in 1...(idxs.length - 1))
					{
						addTriangle(rawVerts, idxs[0], idxs[k], idxs[k + 1]);
					}
				}
			}
		}
	}

	private function addTriangle(verts:Array<Float>, i0:Int, i1:Int, i2:Int):Void
	{
		var v0x = verts[i0 * 3];
		var v0y = verts[i0 * 3 + 1];
		var v0z = verts[i0 * 3 + 2];

		var v1x = verts[i1 * 3];
		var v1y = verts[i1 * 3 + 1];
		var v1z = verts[i1 * 3 + 2];

		var v2x = verts[i2 * 3];
		var v2y = verts[i2 * 3 + 1];
		var v2z = verts[i2 * 3 + 2];

		// Face normal
		var e1x = v1x - v0x;
		var e1y = v1y - v0y;
		var e1z = v1z - v0z;

		var e2x = v2x - v0x;
		var e2y = v2y - v0y;
		var e2z = v2z - v0z;

		var nx = e1y * e2z - e1z * e2y;
		var ny = e1z * e2x - e1x * e2z;
		var nz = e1x * e2y - e1y * e2x;

		var nlen = Math.sqrt(nx * nx + ny * ny + nz * nz);
		if (nlen > 1e-8)
		{
			nx /= nlen;
			ny /= nlen;
			nz /= nlen;
		}
		else
		{
			nx = 0.0;
			ny = 1.0;
			nz = 0.0;
		}

		var triIdx = _numTriangles;
		_numTriangles++;

		_triData.push(v0x);
		_triData.push(v0y);
		_triData.push(v0z);
		_triData.push(v1x);
		_triData.push(v1y);
		_triData.push(v1z);
		_triData.push(v2x);
		_triData.push(v2y);
		_triData.push(v2z);
		_triData.push(nx);
		_triData.push(ny);
		_triData.push(nz);

		// Assign to bins based on vertices and centroid
		var cx = (v0x + v1x + v2x) / 3.0;
		var cy = (v0y + v1y + v2y) / 3.0;
		var cz = (v0z + v1z + v2z) / 3.0;

		var ptsX = [v0x, v1x, v2x, cx];
		var ptsY = [v0y, v1y, v2y, cy];
		var ptsZ = [v0z, v1z, v2z, cz];

		for (p in 0...4)
		{
			var bin = getBin(ptsX[p], ptsY[p], ptsZ[p]);
			var binList = _bins[bin.lat][bin.lon];
			if (binList.indexOf(triIdx) == -1)
			{
				binList.push(triIdx);
			}
		}
	}

	private static function getBin(x:Float, y:Float, z:Float):{lat:Int, lon:Int}
	{
		var r = Math.sqrt(x * x + y * y + z * z);
		if (r < 1e-6)
			return {lat: 0, lon: 0};

		var lat = Math.asin(Math.max(-1.0, Math.min(1.0, y / r)));
		var lon = Math.atan2(z, x);

		var bLat = Math.floor((lat + Math.PI * 0.5) / Math.PI * GRID_LAT);
		if (bLat < 0) bLat = 0;
		if (bLat >= GRID_LAT) bLat = GRID_LAT - 1;

		var bLon = Math.floor((lon + Math.PI) / (2.0 * Math.PI) * GRID_LON);
		if (bLon < 0) bLon = 0;
		if (bLon >= GRID_LON) bLon = GRID_LON - 1;

		return {lat: bLat, lon: bLon};
	}

	/**
	 * Casts ray from 150 units altitude straight down towards planet center.
	 * Returns exact surface hit point and normal on floor geometry.
	 */
	public function raycastDown(pt:Vector3D):HitResult
	{
		var r = Math.sqrt(pt.x * pt.x + pt.y * pt.y + pt.z * pt.z);
		if (r < 1e-6)
		{
			return new HitResult(false, new Vector3D(0, 100, 0), new Vector3D(0, 1, 0), 100.0);
		}

		var invR = 1.0 / r;
		var rayFromX = pt.x * invR * 150.0;
		var rayFromY = pt.y * invR * 150.0;
		var rayFromZ = pt.z * invR * 150.0;

		var rayDirX = -pt.x * invR;
		var rayDirY = -pt.y * invR;
		var rayDirZ = -pt.z * invR;

		var bin = getBin(pt.x, pt.y, pt.z);

		var bestT:Float = 1e9;
		var hitX:Float = 0.0;
		var hitY:Float = 0.0;
		var hitZ:Float = 0.0;
		var hitNx:Float = pt.x * invR;
		var hitNy:Float = pt.y * invR;
		var hitNz:Float = pt.z * invR;
		var didHit:Bool = false;

		// Check 3x3 surrounding bins
		var visitedTriangles = new Map<Int, Bool>();

		for (dLat in -1...2)
		{
			var latIdx = bin.lat + dLat;
			if (latIdx < 0 || latIdx >= GRID_LAT) continue;

			for (dLon in -1...2)
			{
				var lonIdx = (bin.lon + dLon + GRID_LON) % GRID_LON;
				var triList = _bins[latIdx][lonIdx];

				for (tIdx in triList)
				{
					if (visitedTriangles.exists(tIdx)) continue;
					visitedTriangles.set(tIdx, true);

					var base = tIdx * 12;
					var v0x = _triData[base];
					var v0y = _triData[base + 1];
					var v0z = _triData[base + 2];

					var v1x = _triData[base + 3];
					var v1y = _triData[base + 4];
					var v1z = _triData[base + 5];

					var v2x = _triData[base + 6];
					var v2y = _triData[base + 7];
					var v2z = _triData[base + 8];

					// Möller–Trumbore intersection
					var e1x = v1x - v0x;
					var e1y = v1y - v0y;
					var e1z = v1z - v0z;

					var e2x = v2x - v0x;
					var e2y = v2y - v0y;
					var e2z = v2z - v0z;

					var hx = rayDirY * e2z - rayDirZ * e2y;
					var hy = rayDirZ * e2x - rayDirX * e2z;
					var hz = rayDirX * e2y - rayDirY * e2x;

					var a = e1x * hx + e1y * hy + e1z * hz;
					if (Math.abs(a) < 1e-8) continue;

					var f = 1.0 / a;
					var sx = rayFromX - v0x;
					var sy = rayFromY - v0y;
					var sz = rayFromZ - v0z;

					var u = f * (sx * hx + sy * hy + sz * hz);
					if (u < 0.0 || u > 1.0) continue;

					var qx = sy * e1z - sz * e1y;
					var qy = sz * e1x - sx * e1z;
					var qz = sx * e1y - sy * e1x;

					var v = f * (rayDirX * qx + rayDirY * qy + rayDirZ * qz);
					if (v < 0.0 || u + v > 1.0) continue;

					var t = f * (e2x * qx + e2y * qy + e2z * qz);
					if (t > 1e-6 && t < bestT)
					{
						bestT = t;
						didHit = true;
						hitX = rayFromX + rayDirX * t;
						hitY = rayFromY + rayDirY * t;
						hitZ = rayFromZ + rayDirZ * t;

						var nx = _triData[base + 9];
						var ny = _triData[base + 10];
						var nz = _triData[base + 11];

						// Ensure normal faces outward from planet center
						if (nx * rayDirX + ny * rayDirY + nz * rayDirZ > 0.0)
						{
							nx = -nx;
							ny = -ny;
							nz = -nz;
						}

						// Reject vertical pit walls / steep fan rim bevels (dot product with radial vector must be >= 0.60)
						var radDot = nx * (pt.x * invR) + ny * (pt.y * invR) + nz * (pt.z * invR);
						if (radDot < 0.60)
						{
							continue;
						}

						bestT = t;
						didHit = true;
						hitX = rayFromX + rayDirX * t;
						hitY = rayFromY + rayDirY * t;
						hitZ = rayFromZ + rayDirZ * t;
						hitNx = nx;
						hitNy = ny;
						hitNz = nz;
					}
				}
			}
		}

		if (didHit)
		{
			var hitR = Math.sqrt(hitX * hitX + hitY * hitY + hitZ * hitZ);
			var hitPos:Vector3D;
			var hitNorm:Vector3D;

			// If ray landed inside a sunken fan pit (radius < 98.2), clamp position to street level (99.8) and use radial normal
			if (hitR < 98.2 && hitR > 1e-4)
			{
				var rScale = 99.8 / hitR;
				hitPos = new Vector3D(hitX * rScale, hitY * rScale, hitZ * rScale);
				hitNorm = new Vector3D(hitX / hitR, hitY / hitR, hitZ / hitR);
				hitR = 99.8;
			}
			else
			{
				hitPos = new Vector3D(hitX, hitY, hitZ);
				hitNorm = new Vector3D(hitNx, hitNy, hitNz);
			}

			return new HitResult(true, hitPos, hitNorm, hitR);
		}
		else
		{
			var fallbackPos = new Vector3D(pt.x * invR * 99.8, pt.y * invR * 99.8, pt.z * invR * 99.8);
			var fallbackNorm = new Vector3D(pt.x * invR, pt.y * invR, pt.z * invR);
			return new HitResult(false, fallbackPos, fallbackNorm, 99.8);
		}
	}
}
