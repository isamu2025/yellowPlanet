package;

import away3d.containers.ObjectContainer3D;
import away3d.core.base.Geometry;
import away3d.core.base.SubGeometry;
import away3d.entities.Mesh;
import away3d.materials.MaterialBase;
import openfl.Vector;

class MaterialGroup
{
	public var vertices:Vector<Float> = new Vector<Float>();
	public var uvs:Vector<Float> = new Vector<Float>();
	public var normals:Vector<Float> = new Vector<Float>();
	public var indices:Vector<UInt> = new Vector<UInt>();
	public var vertexMap:Map<String, Int> = new Map<String, Int>();

	public function new() {}
}

/**
 * Fast, self-contained Wavefront OBJ loader for Away3D.
 * Supports multi-material grouping via `usemtl`, UV flipping for Stage3D, and clean Geometry creation.
 */
class SimpleObjLoader
{
	public static function parse(objText:String, material:MaterialBase = null):Mesh
	{
		var map:Map<String, MaterialBase> = new Map<String, MaterialBase>();
		if (material != null) map.set("default", material);
		var container = parseMulti(objText, map, material);
		if (container.numChildren > 0 && Std.isOfType(container.getChildAt(0), Mesh))
		{
			return cast container.getChildAt(0);
		}
		var emptyGeom = new Geometry();
		return new Mesh(emptyGeom, material);
	}

	public static function parseMulti(objText:String, materials:Map<String, MaterialBase>, defaultMaterial:MaterialBase = null):ObjectContainer3D
	{
		var rawPositions:Array<Float> = [];
		var rawUVs:Array<Float> = [];
		var rawNormals:Array<Float> = [];

		var groups:Map<String, MaterialGroup> = new Map<String, MaterialGroup>();
		var currentGroup:MaterialGroup = new MaterialGroup();
		var currentMtlName:String = "default";
		groups.set(currentMtlName, currentGroup);

		var lines:Array<String> = objText.split("\n");

		for (line in lines)
		{
			var l:String = StringTools.trim(line);
			if (l.length == 0 || l.charAt(0) == '#')
				continue;

			if (StringTools.startsWith(l, "v "))
			{
				var parts:Array<String> = l.split(" ");
				var p:Array<Float> = [];
				for (i in 1...parts.length)
				{
					var s:String = StringTools.trim(parts[i]);
					if (s.length > 0) p.push(Std.parseFloat(s));
				}
				if (p.length >= 3)
				{
					rawPositions.push(p[0]);
					rawPositions.push(p[1]);
					rawPositions.push(p[2]);
				}
			}
			else if (StringTools.startsWith(l, "vt "))
			{
				var parts:Array<String> = l.split(" ");
				var p:Array<Float> = [];
				for (i in 1...parts.length)
				{
					var s:String = StringTools.trim(parts[i]);
					if (s.length > 0) p.push(Std.parseFloat(s));
				}
				if (p.length >= 2)
				{
					rawUVs.push(p[0]);
					rawUVs.push(1.0 - p[1]);
				}
			}
			else if (StringTools.startsWith(l, "vn "))
			{
				var parts:Array<String> = l.split(" ");
				var p:Array<Float> = [];
				for (i in 1...parts.length)
				{
					var s:String = StringTools.trim(parts[i]);
					if (s.length > 0) p.push(Std.parseFloat(s));
				}
				if (p.length >= 3)
				{
					rawNormals.push(p[0]);
					rawNormals.push(p[1]);
					rawNormals.push(p[2]);
				}
			}
			else if (StringTools.startsWith(l, "usemtl "))
			{
				var mtlName:String = StringTools.trim(l.substr(7));
				currentMtlName = mtlName;
				if (!groups.exists(currentMtlName))
				{
					groups.set(currentMtlName, new MaterialGroup());
				}
				currentGroup = groups.get(currentMtlName);
			}
			else if (StringTools.startsWith(l, "f "))
			{
				var parts:Array<String> = l.split(" ");
				var faceVerts:Array<String> = [];
				for (i in 1...parts.length)
				{
					var s:String = StringTools.trim(parts[i]);
					if (s.length > 0) faceVerts.push(s);
				}

				if (faceVerts.length >= 3)
				{
					for (i in 1...(faceVerts.length - 1))
					{
						addVertexIndex(faceVerts[0], rawPositions, rawUVs, rawNormals, currentGroup);
						addVertexIndex(faceVerts[i], rawPositions, rawUVs, rawNormals, currentGroup);
						addVertexIndex(faceVerts[i + 1], rawPositions, rawUVs, rawNormals, currentGroup);
					}
				}
			}
		}

		var container:ObjectContainer3D = new ObjectContainer3D();

		for (mtlName in groups.keys())
		{
			var grp:MaterialGroup = groups.get(mtlName);
			if (grp.indices.length == 0 || grp.vertices.length == 0)
				continue;

			var subGeom:SubGeometry = new SubGeometry();
			subGeom.updateVertexData(grp.vertices);
			if (grp.uvs.length == Std.int(grp.vertices.length / 3) * 2)
			{
				subGeom.updateUVData(grp.uvs);
			}
			else
			{
				subGeom.autoDeriveVertexTangents = true;
			}

			if (grp.normals.length == grp.vertices.length)
			{
				subGeom.updateVertexNormalData(grp.normals);
			}
			else
			{
				subGeom.autoDeriveVertexNormals = true;
			}

			subGeom.updateIndexData(grp.indices);

			var geom:Geometry = new Geometry();
			geom.addSubGeometry(subGeom);

			var mat:MaterialBase = null;
			if (materials.exists(mtlName))
			{
				mat = materials.get(mtlName);
			}
			else if (defaultMaterial != null)
			{
				mat = defaultMaterial;
			}

			var mesh:Mesh = new Mesh(geom, mat);
			mesh.name = mtlName;
			container.addChild(mesh);
		}

		return container;
	}

	private static function addVertexIndex(token:String,
		rawPositions:Array<Float>,
		rawUVs:Array<Float>,
		rawNormals:Array<Float>,
		group:MaterialGroup):Void
	{
		var existingIndex:Null<Int> = group.vertexMap.get(token);
		if (existingIndex != null)
		{
			group.indices.push(existingIndex);
			return;
		}

		var newIndex:Int = Std.int(group.vertices.length / 3);
		group.vertexMap.set(token, newIndex);
		group.indices.push(newIndex);

		var indices:Array<String> = token.split("/");
		var posIdx:Int = Std.parseInt(indices[0]);
		if (posIdx < 0) posIdx = Std.int(rawPositions.length / 3) + posIdx + 1;
		var pBase:Int = (posIdx - 1) * 3;

		if (pBase >= 0 && pBase + 2 < rawPositions.length)
		{
			group.vertices.push(rawPositions[pBase]);
			group.vertices.push(rawPositions[pBase + 1]);
			group.vertices.push(rawPositions[pBase + 2]);
		}
		else
		{
			group.vertices.push(0);
			group.vertices.push(0);
			group.vertices.push(0);
		}

		// UV
		if (indices.length > 1 && indices[1].length > 0)
		{
			var uvIdx:Int = Std.parseInt(indices[1]);
			if (uvIdx < 0) uvIdx = Std.int(rawUVs.length / 2) + uvIdx + 1;
			var uvBase:Int = (uvIdx - 1) * 2;
			if (uvBase >= 0 && uvBase + 1 < rawUVs.length)
			{
				group.uvs.push(rawUVs[uvBase]);
				group.uvs.push(rawUVs[uvBase + 1]);
			}
			else
			{
				group.uvs.push(0);
				group.uvs.push(0);
			}
		}
		else
		{
			group.uvs.push(0);
			group.uvs.push(0);
		}

		// Normal
		if (indices.length > 2 && indices[2].length > 0)
		{
			var normIdx:Int = Std.parseInt(indices[2]);
			if (normIdx < 0) normIdx = Std.int(rawNormals.length / 3) + normIdx + 1;
			var nBase:Int = (normIdx - 1) * 3;
			if (nBase >= 0 && nBase + 2 < rawNormals.length)
			{
				group.normals.push(rawNormals[nBase]);
				group.normals.push(rawNormals[nBase + 1]);
				group.normals.push(rawNormals[nBase + 2]);
			}
		}
	}
}
