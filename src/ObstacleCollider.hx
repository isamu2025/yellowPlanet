package;

import openfl.geom.Vector3D;

class ObstacleBuilding
{
	public var name:String;
	public var center:Vector3D;
	public var radius:Float;
	public var triangles:Array<Float> = []; // 9 floats per triangle: ax, ay, az, bx, by, bz, cx, cy, cz

	public function new(name:String)
	{
		this.name = name;
		this.center = new Vector3D();
		this.radius = 0.0;
	}

	public function finalizeBounds():Void
	{
		if (triangles.length == 0) return;
		var minX:Float = 1e9, minY:Float = 1e9, minZ:Float = 1e9;
		var maxX:Float = -1e9, maxY:Float = -1e9, maxZ:Float = -1e9;

		var i = 0;
		while (i < triangles.length)
		{
			var x = triangles[i];
			var y = triangles[i + 1];
			var z = triangles[i + 2];
			if (x < minX) minX = x; if (x > maxX) maxX = x;
			if (y < minY) minY = y; if (y > maxY) maxY = y;
			if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
			i += 3;
		}

		center.x = (minX + maxX) * 0.5;
		center.y = (minY + maxY) * 0.5;
		center.z = (minZ + maxZ) * 0.5;

		var maxR:Float = 0.0;
		i = 0;
		while (i < triangles.length)
		{
			var dx = triangles[i] - center.x;
			var dy = triangles[i + 1] - center.y;
			var dz = triangles[i + 2] - center.z;
			var d2 = dx * dx + dy * dy + dz * dz;
			if (d2 > maxR) maxR = d2;
			i += 3;
		}
		radius = Math.sqrt(maxR);
	}
}

/**
 * Robust triangle-mesh obstacle sliding collision system (recreating Flare3D SphereCollision.slider()).
 * Detects triangle walls/faces of all 81 building obstacles, keeping player strictly within the roadway avenue.
 */
class ObstacleCollider
{
	private var _obstacles:Array<ObstacleBuilding> = [];

	public function new(objText:String)
	{
		parse(objText);
	}

	private function parse(objText:String):Void
	{
		_obstacles = [];
		var rawVerts:Array<Float> = [];
		var lines = objText.split("\n");
		var currentBuilding:ObstacleBuilding = null;

		for (line in lines)
		{
			var trimmed = StringTools.trim(line);
			if (trimmed.length == 0 || trimmed.charAt(0) == '#') continue;

			if (StringTools.startsWith(trimmed, "o "))
			{
				if (currentBuilding != null && currentBuilding.triangles.length > 0)
				{
					currentBuilding.finalizeBounds();
					_obstacles.push(currentBuilding);
				}
				var parts = trimmed.split(" ");
				var name = parts.length > 1 ? parts[1] : "obstacle";
				currentBuilding = new ObstacleBuilding(name);
			}
			else if (StringTools.startsWith(trimmed, "v "))
			{
				var parts = trimmed.split(" ");
				var coords:Array<Float> = [];
				for (i in 1...parts.length)
				{
					var p = StringTools.trim(parts[i]);
					if (p.length > 0) coords.push(Std.parseFloat(p));
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
				if (currentBuilding == null)
				{
					currentBuilding = new ObstacleBuilding("obstacle");
				}

				var parts = trimmed.split(" ");
				var idxs:Array<Int> = [];
				for (i in 1...parts.length)
				{
					var p = StringTools.trim(parts[i]);
					if (p.length == 0) continue;
					var slash = p.indexOf("/");
					var vIdxStr = slash != -1 ? p.substr(0, slash) : p;
					var vIdx = Std.parseInt(vIdxStr);
					if (vIdx != null && vIdx > 0)
					{
						idxs.push(vIdx - 1);
					}
				}

				// Fan triangulate polygon if 3 or 4 vertices
				if (idxs.length >= 3)
				{
					for (k in 1...(idxs.length - 1))
					{
						var i0 = idxs[0] * 3;
						var i1 = idxs[k] * 3;
						var i2 = idxs[k + 1] * 3;
						if (i0 + 2 < rawVerts.length && i1 + 2 < rawVerts.length && i2 + 2 < rawVerts.length)
						{
							currentBuilding.triangles.push(rawVerts[i0]);
							currentBuilding.triangles.push(rawVerts[i0 + 1]);
							currentBuilding.triangles.push(rawVerts[i0 + 2]);

							currentBuilding.triangles.push(rawVerts[i1]);
							currentBuilding.triangles.push(rawVerts[i1 + 1]);
							currentBuilding.triangles.push(rawVerts[i1 + 2]);

							currentBuilding.triangles.push(rawVerts[i2]);
							currentBuilding.triangles.push(rawVerts[i2 + 1]);
							currentBuilding.triangles.push(rawVerts[i2 + 2]);
						}
					}
				}
			}
		}

		if (currentBuilding != null && currentBuilding.triangles.length > 0)
		{
			currentBuilding.finalizeBounds();
			_obstacles.push(currentBuilding);
		}
	}

	/**
	 * Sphere slider collision displacement against building triangle meshes.
	 * Displaces playerPos along tangent plane to slide along building walls without penetration.
	 */
	public function slider(playerPos:Vector3D, surfaceNormal:Vector3D, playerRadius:Float = 3.5):Vector3D
	{
		var curPos = playerPos.clone();
		// Test collision sphere at torso level
		var sphereCenter = new Vector3D(curPos.x + surfaceNormal.x * 2.5,
			curPos.y + surfaceNormal.y * 2.5,
			curPos.z + surfaceNormal.z * 2.5);

		var rSq = playerRadius * playerRadius;

		// Perform up to 3 sliding relaxation iterations
		for (iter in 0...3)
		{
			var hasCollision = false;

			for (obs in _obstacles)
			{
				// Broad phase
				var cdx = sphereCenter.x - obs.center.x;
				var cdy = sphereCenter.y - obs.center.y;
				var cdz = sphereCenter.z - obs.center.z;
				var broadDistSq = cdx * cdx + cdy * cdy + cdz * cdz;
				var maxDist = obs.radius + playerRadius + 1.0;
				if (broadDistSq > maxDist * maxDist) continue;

				// Narrow phase against each triangle of this obstacle building
				var tris = obs.triangles;
				var tLen = tris.length;
				var i = 0;
				while (i < tLen)
				{
					var ax = tris[i], ay = tris[i + 1], az = tris[i + 2];
					var bx = tris[i + 3], by = tris[i + 4], bz = tris[i + 5];
					var cx = tris[i + 6], cy = tris[i + 7], cz = tris[i + 8];

					// Closest point on triangle to sphereCenter
					var abx = bx - ax, aby = by - ay, abz = bz - az;
					var acx = cx - ax, acy = cy - ay, acz = cz - az;
					var apx = sphereCenter.x - ax, apy = sphereCenter.y - ay, apz = sphereCenter.z - az;

					var d1 = abx * apx + aby * apy + abz * apz;
					var d2 = acx * apx + acy * apy + acz * apz;

					var closeX:Float, closeY:Float, closeZ:Float;

					if (d1 <= 0.0 && d2 <= 0.0)
					{
						closeX = ax; closeY = ay; closeZ = az;
					}
					else
					{
						var bpx = sphereCenter.x - bx, bpy = sphereCenter.y - by, bpz = sphereCenter.z - bz;
						var d3 = abx * bpx + aby * bpy + abz * bpz;
						var d4 = acx * bpx + acy * bpy + acz * bpz;
						if (d3 >= 0.0 && d4 <= d3)
						{
							closeX = bx; closeY = by; closeZ = bz;
						}
						else
						{
							var vc = d1 * d4 - d3 * d2;
							if (vc <= 0.0 && d1 >= 0.0 && d3 <= 0.0)
							{
								var v = d1 / (d1 - d3);
								closeX = ax + abx * v; closeY = ay + aby * v; closeZ = az + abz * v;
							}
							else
							{
								var cpx = sphereCenter.x - cx, cpy = sphereCenter.y - cy, cpz = sphereCenter.z - cz;
								var d5 = abx * cpx + aby * cpy + abz * cpz;
								var d6 = acx * cpx + acy * cpy + acz * cpz;
								if (d6 >= 0.0 && d5 <= d6)
								{
									closeX = cx; closeY = cy; closeZ = cz;
								}
								else
								{
									var vb = d5 * d2 - d1 * d6;
									if (vb <= 0.0 && d2 >= 0.0 && d6 <= 0.0)
									{
										var w = d2 / (d2 - d6);
										closeX = ax + acx * w; closeY = ay + acy * w; closeZ = az + acz * w;
									}
									else
									{
										var va = d3 * d6 - d5 * d4;
										if (va <= 0.0 && (d4 - d3) >= 0.0 && (d5 - d6) >= 0.0)
										{
											var w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
											closeX = bx + (cx - bx) * w; closeY = by + (cy - by) * w; closeZ = bz + (cz - bz) * w;
										}
										else
										{
											var denom = 1.0 / (va + vb + vc);
											var v = vb * denom;
											var w = vc * denom;
											closeX = ax + abx * v + acx * w;
											closeY = ay + aby * v + acy * w;
											closeZ = az + abz * v + acz * w;
										}
									}
								}
							}
						}
					}

					var dx = sphereCenter.x - closeX;
					var dy = sphereCenter.y - closeY;
					var dz = sphereCenter.z - closeZ;
					var d2 = dx * dx + dy * dy + dz * dz;

					if (d2 < rSq)
					{
						var d = Math.sqrt(d2);
						var overlap = playerRadius - d;
						var pushX:Float, pushY:Float, pushZ:Float;

						if (d > 1e-4)
						{
							pushX = (dx / d) * overlap;
							pushY = (dy / d) * overlap;
							pushZ = (dz / d) * overlap;
						}
						else
						{
							// Deep inside: push outward along vector from obstacle center to player
							var cx = sphereCenter.x - obs.center.x;
							var cy = sphereCenter.y - obs.center.y;
							var cz = sphereCenter.z - obs.center.z;
							var clen = Math.sqrt(cx * cx + cy * cy + cz * cz);
							if (clen > 1e-4)
							{
								pushX = (cx / clen) * playerRadius;
								pushY = (cy / clen) * playerRadius;
								pushZ = (cz / clen) * playerRadius;
							}
							else
							{
								pushX = surfaceNormal.x * playerRadius;
								pushY = surfaceNormal.y * playerRadius;
								pushZ = surfaceNormal.z * playerRadius;
							}
						}

						// Project push vector onto surface tangent plane (perpendicular to surfaceNormal)
						var normProj = pushX * surfaceNormal.x + pushY * surfaceNormal.y + pushZ * surfaceNormal.z;
						var tangPushX = pushX - surfaceNormal.x * normProj;
						var tangPushY = pushY - surfaceNormal.y * normProj;
						var tangPushZ = pushZ - surfaceNormal.z * normProj;
						var tLenSq = tangPushX * tangPushX + tangPushY * tangPushY + tangPushZ * tangPushZ;
						if (tLenSq > 1e-6)
						{
							var tLen = Math.sqrt(tLenSq);
							tangPushX = (tangPushX / tLen) * overlap;
							tangPushY = (tangPushY / tLen) * overlap;
							tangPushZ = (tangPushZ / tLen) * overlap;
						}

						curPos.x += tangPushX;
						curPos.y += tangPushY;
						curPos.z += tangPushZ;

						sphereCenter.x += tangPushX;
						sphereCenter.y += tangPushY;
						sphereCenter.z += tangPushZ;

						hasCollision = true;
					}

					i += 9;
				}
			}

			if (!hasCollision) break;
		}

		return curPos;
	}
}
