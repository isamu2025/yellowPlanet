package;

import away3d.containers.ObjectContainer3D;
import away3d.containers.View3D;
import away3d.core.base.Geometry;
import away3d.core.base.SubGeometry;
import away3d.entities.Mesh;
import away3d.lights.DirectionalLight;
import away3d.materials.ColorMaterial;
import away3d.materials.MaterialBase;
import away3d.materials.TextureMaterial;
import away3d.materials.lightpickers.StaticLightPicker;
import away3d.primitives.CubeGeometry;
import away3d.primitives.SphereGeometry;
import away3d.utils.Cast;
import haxe.Json;
import lime.media.AudioBuffer;
import openfl.Assets;
import openfl.display.BitmapData;
import openfl.display.BlendMode;
import openfl.display.CapsStyle;
import openfl.display.GradientType;
import openfl.display.JointStyle;
import openfl.display.LineScaleMode;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.display.StageAlign;
import openfl.display.StageScaleMode;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.events.MouseEvent;
import openfl.events.TouchEvent;
import openfl.filters.DropShadowFilter;
import openfl.filters.GlowFilter;
import openfl.geom.Matrix;
import openfl.geom.Matrix3D;
import openfl.geom.Vector3D;
import openfl.media.Sound;
import openfl.media.SoundChannel;
import openfl.media.SoundTransform;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.ui.Keyboard;
import openfl.utils.ByteArray;
import openfl.utils.Endian;
import openfl.Vector;

/**
 * Modernized Yellow Planet 3D Game using OpenFL and Away3D.
 * Faithful recreation of the original Flare3D Stage3D title:
 * - Real-time FloorRaycaster ground snapping to exact 3D street polygons (no zero-G floating)
 * - Obstacle sliding collision (recreating Flare3D SphereCollision.slider() against all 81 buildings)
 * - Authentic Jump & Gravity physics (jumpValue = 4.0, gravity -= 0.3)
 * - Ground contact shadow beneath astronaut (shadow.obj + shadow.png)
 * - Procedural animated running stride (bobbing, swagger roll, forward lean, banking turns)
 * - Unlit vivid blue cosmic starry sky dome (Space.jpg)
 * - Authentic Flash UI & sound effects
 */
class Main extends Sprite
{
	// Away3D engine
	private var _view:View3D;
	private var _light:DirectionalLight;
	private var _lightPicker:StaticLightPicker;

	// Materials
	private var _floorMaterials:Map<String, MaterialBase> = new Map<String, MaterialBase>();
	private var _obstacleMaterials:Map<String, MaterialBase> = new Map<String, MaterialBase>();
	private var _mineMaterials:Map<String, MaterialBase> = new Map<String, MaterialBase>();
	private var _fanMaterial:TextureMaterial;
	private var _astronautMaterial:TextureMaterial;
	private var _backpackMaterial:TextureMaterial;
	private var _helmetMaterial:TextureMaterial;
	private var _shadowMaterial:TextureMaterial;
	private var _energyMaterial:TextureMaterial;
	private var _orbMaterial:ColorMaterial;
	private var _fireMaterial:ColorMaterial;
	private var _skyMaterial:TextureMaterial;

	// 3D Objects
	private var _skyMesh:Mesh;
	private var _planetFloorContainer:ObjectContainer3D;
	private var _obstaclesContainer:ObjectContainer3D;

	// Ground container: positioned directly on planet floor surface via FloorRaycaster
	private var _groundContainer:ObjectContainer3D;
	private var _shadowMesh:Mesh;
	private var _astronautMesh:ObjectContainer3D;
	private var _suitSubGeom:SubGeometry;
	private var _backpackSubGeom:SubGeometry;
	private var _helmetSubGeom:SubGeometry;
	private var _suitFrames:Array<Vector<Float>> = [];
	private var _backpackFrames:Array<Vector<Float>> = [];
	private var _helmetFrames:Array<Vector<Float>> = [];
	private var _hasAnimatedAstronaut:Bool = false;
	private var _animFrame:Int = -1;
	private var _animTimer:Float = 0.0;
	private var _jetpackFlame:Mesh;

	private var _energyContainer:ObjectContainer3D;
	private var _energyMesh:Mesh;
	private var _energyOrbs:Array<Mesh> = [];
	private var _energyPoints:Array<Vector3D> = [];
	private var _energyMatrices:Array<Array<Float>> = [];
	private var _currentEnergyIndex:Int = 0;

	private var _mines:Array<ObjectContainer3D> = [];
	private var _mineMeshes:Array<ObjectContainer3D> = [];
	private var _mineRotSpeeds:Array<Float> = [];
	private var _mineFrequencies:Array<Float> = [];
	private var _minePositions:Array<Vector3D> = [];
	private var _mineNormals:Array<Vector3D> = [];
	private var _mineVisible:Array<Bool> = [];

	private var _fans:Array<Mesh> = [];
	private var _fanContainers:Array<ObjectContainer3D> = [];
	private var _fanSpeeds:Array<Float> = [];
	private var _fanPositions:Array<Vector3D> = [];
	private var _fanScales:Array<Float> = [];

	// Physics & Collisions
	private var _floorRaycaster:FloorRaycaster;
	private var _obstacleCollider:ObstacleCollider;

	// Authentic start coordinates from planet.f3d / planet.glb
	private var _playerPos:Vector3D = new Vector3D(46.048, 41.432, -78.398);
	private var _surfaceNormal:Vector3D = new Vector3D(0.481, 0.441, -0.758);
	private var _forwardDir:Vector3D = new Vector3D(-0.1768, 0.9237, 0.3397);

	private var _jumpHeight:Float = 0.0;
	private var _jumpVelocity:Float = 0.0;
	private var _speed:Float = 0.28;
	private var _speedLevel:Int = 1;
	private var _energyCount:Int = 0;
	private var _score:Int = 0;
	private var _bestScore:Int = 0;
	private var _state:String = "start"; // start, run, jump, fan, die, boost
	private var _stateTimer:Int = 0;
	private var _shakeFactor:Float = 0.0;
	private var _runTimer:Float = 0.0;
	private var _lastFrameTime:Float = 0.0;
	private var _camPos:Vector3D = null;
	private var _camFocus:Vector3D = null;
	private var _camUp:Vector3D = null;

	// Input controls
	private var _leftPressed:Bool = false;
	private var _rightPressed:Bool = false;

	// Audio
	private var _sndStart:Sound;
	private var _sndJump:Sound;
	private var _sndCoin:Sound;
	private var _sndMine:Sound;
	private var _sndFan:Sound;
	private var _sndDead:Sound;
	private var _sndPower:Sound;
	private var _sndMusic:Sound;
	private var _musicChannel:SoundChannel;

	// Authentic UI Elements
	private var _hudLayer:Sprite;
	private var _pointsPanel:Sprite;
	private var _pointsScoreText:TextField;
	private var _bestScoreText:TextField;
	private var _energyPanel:Sprite;
	private var _energyCountText:TextField;
	private var _stageLevelText:TextField;
	private var _instructionsModal:Sprite;
	private var _scoreModal:Sprite;
	private var _scoreModalValueText:TextField;

	// Stage Cleared & Speed Up Banner (Authentic Flare3D gui.speed)
	private var _speedBanner:Sprite;
	private var _stageClearTitle:TextField;
	private var _speedValueText:TextField;
	private var _bonusScoreText:TextField;
	private var _continueBtnText:TextField;
	private var _speedBannerTimer:Int = 0;
	private var _powerBurstParticles:Array<Sprite> = [];
	private var _powerParticleVels:Array<Vector3D> = [];
	private var _powerParticleLife:Array<Float> = [];

	public function new()
	{
		super();

		stage.scaleMode = StageScaleMode.NO_SCALE;
		stage.align = StageAlign.TOP_LEFT;

		init3D();
		initMaterials();
		loadAssetsAndBuildWorld();
		initSounds();
		initAuthenticUI();
		initEvents();
		resetGame();
	}

	private function init3D():Void
	{
		_view = new View3D();
		_view.backgroundColor = 0x071D3E; // Vibrant deep celestial blue
		_view.backgroundAlpha = 1.0;
		_view.antiAlias = 2;
		addChild(_view);

		_light = new DirectionalLight(-0.6, -1.2, 0.7);
		_light.ambient = 0.5;
		_light.diffuse = 0.95;
		_light.specular = 0.45;
		_view.scene.addChild(_light);

		_lightPicker = new StaticLightPicker([_light]);

		_view.camera.lens.near = 1.0;
		_view.camera.lens.far = 10000.0;
		if (Std.isOfType(_view.camera.lens, away3d.cameras.lenses.PerspectiveLens))
		{
			cast(_view.camera.lens, away3d.cameras.lenses.PerspectiveLens).fieldOfView = 65.0;
		}
	}

	private function initMaterials():Void
	{
		// 1. Sky cosmic material - unlit so starry cosmos stays vivid and bright
		_skyMaterial = createTextureMaterial("assets/textures/Space.jpg", 0x1A4F9C);
		_skyMaterial.lightPicker = null; // Unshaded, fully luminous
		_skyMaterial.bothSides = true;
		_skyMaterial.repeat = true;
		_skyMaterial.ambient = 1.0;
		_skyMaterial.specular = 0.0;
		_skyMaterial.mipmap = false;

		// 2. Planet floor materials
		_floorMaterials.set("Material_#449", createTextureMaterial("assets/textures/planet_base1.jpg", 0xDEB843));
		_floorMaterials.set("Material_#448", createTextureMaterial("assets/textures/planet_base2.jpg", 0xCEA038));
		_floorMaterials.set("Material_#440", createTextureMaterial("assets/textures/planet_craters.jpg", 0xB5882E));
		_floorMaterials.set("Material_#443", createTextureMaterial("assets/textures/square01.jpg", 0x4DA0B5)); // cyan floor panel
		_floorMaterials.set("Material_#444", createTextureMaterial("assets/textures/square02.jpg", 0xB6953D)); // sand floor panel
		_floorMaterials.set("Material_#445", createTextureMaterial("assets/textures/square03.jpg", 0xBA740D)); // terracotta floor panel
		_floorMaterials.set("Material_#446", createTextureMaterial("assets/textures/square04.jpg", 0xB6AD36)); // sage floor panel

		// 3. Obstacles pastel architectural materials
		_obstacleMaterials.set("Material_#44", createTextureMaterial("assets/textures/vent_08.JPG", 0xF89A7B)); // peach/terracotta
		_obstacleMaterials.set("Material_#42", createTextureMaterial("assets/textures/vent_07.JPG", 0xF7CA7A)); // khaki/sand
		_obstacleMaterials.set("13_-_Default", createTextureMaterial("assets/textures/vent_06.JPG", 0xDCF382)); // pastel sage green
		_obstacleMaterials.set("14_-_Default", createTextureMaterial("assets/textures/vent_01.jpg", 0x5DB8F3)); // pastel sky cyan

		// 4. Mine materials
		_mineMaterials.set("23_-_Default", createTextureMaterial("assets/textures/mine_base.jpg", 0x3377CC));
		var legMat = new ColorMaterial(0xEE2A11, 1.0);
		legMat.lightPicker = _lightPicker;
		legMat.specular = 0.6;
		_mineMaterials.set("04_-_Default", legMat);

		// 5. Fan material
		_fanMaterial = createTextureMaterial("assets/textures/Fan.JPG", 0x5599DD);
		_fanMaterial.bothSides = true;

		// 6. Astronaut multi-materials
		_astronautMaterial = createTextureMaterial("assets/textures/astronaut.jpg", 0xDFE5EB);
		_backpackMaterial = createTextureMaterial("assets/textures/equipment.png", 0x445566);

		// Authentic glowing transparent bubble space helmet with additive blending (Flare3D AS3: ONE, ONE)
		_helmetMaterial = createTextureMaterial("assets/textures/glassy.png", 0x00A0FF);
		_helmetMaterial.blendMode = BlendMode.ADD;
		_helmetMaterial.bothSides = true;
		_helmetMaterial.ambient = 1.0;
		_helmetMaterial.specular = 1.0;
		_helmetMaterial.alphaBlending = true;

		// 7. Ground shadow material (soft circular shadow disk)
		_shadowMaterial = createTextureMaterial("assets/textures/shadow.png", 0x000000);
		_shadowMaterial.lightPicker = null;
		_shadowMaterial.alphaBlending = true;
		_shadowMaterial.bothSides = true;
		_shadowMaterial.ambient = 1.0;

		// 8. Energy capsule & orbiting orbs
		_energyMaterial = createTextureMaterial("assets/textures/energyboost.jpg", 0x36FF00);
		_energyMaterial.bothSides = true;
		_energyMaterial.ambient = 0.8;
		_orbMaterial = new ColorMaterial(0x36FF00, 1.0);
		_orbMaterial.lightPicker = null;

		// 9. Jetpack exhaust flame
		_fireMaterial = new ColorMaterial(0xFFAA00, 0.9);
		_fireMaterial.lightPicker = null;
		_fireMaterial.bothSides = true;
	}

	private function ensurePowerOfTwo(bmd:BitmapData):BitmapData
	{
		var w = bmd.width;
		var h = bmd.height;
		var isPotW = (w > 0) && ((w & (w - 1)) == 0);
		var isPotH = (h > 0) && ((h & (h - 1)) == 0);
		if (isPotW && isPotH && w <= 2048 && h <= 2048)
			return bmd;

		var newW = 1;
		while (newW < w && newW < 2048) newW <<= 1;
		var newH = 1;
		while (newH < h && newH < 2048) newH <<= 1;

		var potBmd = new BitmapData(newW, newH, bmd.transparent, 0x000000);
		var matrix = new Matrix();
		matrix.scale(newW / w, newH / h);
		potBmd.draw(bmd, matrix, null, null, null, true);
		return potBmd;
	}

	private function createTextureMaterial(assetPath:String, fallbackColor:Int):TextureMaterial
	{
		var bmd:BitmapData = null;
		try
		{
			if (Assets.exists(assetPath))
			{
				bmd = Assets.getBitmapData(assetPath);
			}
		}
		catch (e:Dynamic) {}

		var mat:TextureMaterial;
		if (bmd != null)
		{
			bmd = ensurePowerOfTwo(bmd);
			mat = new TextureMaterial(Cast.bitmapTexture(bmd));
		}
		else
		{
			var fb:BitmapData = new BitmapData(64, 64, false, fallbackColor);
			mat = new TextureMaterial(Cast.bitmapTexture(fb));
		}
		mat.repeat = true;
		mat.lightPicker = _lightPicker;
		mat.specular = 0.35;
		mat.ambient = 0.4;
		return mat;
	}

	private function loadAssetsAndBuildWorld():Void
	{
		// 1. Authentic Blue Sky Model (sky.obj with cyan-to-royal-blue cosmos)
		if (Assets.exists("assets/models/sky.obj"))
		{
			var skyText = Assets.getText("assets/models/sky.obj");
			_skyMesh = SimpleObjLoader.parse(skyText, _skyMaterial);
			_skyMesh.castsShadows = false;
			_view.scene.addChild(_skyMesh);
		}
		else
		{
			var skyGeom = new SphereGeometry(2800, 32, 24);
			_skyMesh = new Mesh(skyGeom, _skyMaterial);
			_skyMesh.castsShadows = false;
			_view.scene.addChild(_skyMesh);
		}

		// 2. Planet floor with multi-material support
		if (Assets.exists("assets/models/planet_floor.obj"))
		{
			var floorText = Assets.getText("assets/models/planet_floor.obj");
			_planetFloorContainer = SimpleObjLoader.parseMulti(floorText, _floorMaterials, _floorMaterials.get("Material_#449"));
			_view.scene.addChild(_planetFloorContainer);

			// Initialize spherical raycaster against floor polygons
			_floorRaycaster = new FloorRaycaster(floorText);
		}

		// 3. Obstacles with authentic pastel building materials
		if (Assets.exists("assets/models/obstacles_combined.obj"))
		{
			var obsText = Assets.getText("assets/models/obstacles_combined.obj");
			_obstaclesContainer = SimpleObjLoader.parseMulti(obsText, _obstacleMaterials, _obstacleMaterials.get("Material_#44"));
			_view.scene.addChild(_obstaclesContainer);

			// Initialize obstacle sliding collider
			_obstacleCollider = new ObstacleCollider(obsText);
		}

		// 4. Ground container (snapped directly to floor surface)
		_groundContainer = new ObjectContainer3D();
		_view.scene.addChild(_groundContainer);

		// Ground contact shadow
		if (Assets.exists("assets/models/shadow.obj"))
		{
			var shadowText = Assets.getText("assets/models/shadow.obj");
			_shadowMesh = SimpleObjLoader.parse(shadowText, _shadowMaterial);
		}
		else
		{
			_shadowMesh = new Mesh(new CubeGeometry(5.0, 0.05, 5.0), _shadowMaterial);
		}
		_shadowMesh.y = 0.08; // Just above ground polygon to avoid z-fighting
		_shadowMesh.scale(2.2);
		_groundContainer.addChild(_shadowMesh);

		// Astronaut model with full animated skeletal subgeometries (Suit, Backpack, Helmet)
		loadAnimatedAstronaut();

		// Jetpack exhaust flame
		_jetpackFlame = new Mesh(new SphereGeometry(0.35, 6, 6), _fireMaterial);
		_jetpackFlame.z = -1.3;
		_jetpackFlame.y = 2.8;
		_jetpackFlame.visible = false;
		_groundContainer.addChild(_jetpackFlame);

		// 5. Energy Canister + Orbiting particles
		_energyContainer = new ObjectContainer3D();
		_view.scene.addChild(_energyContainer);

		if (Assets.exists("assets/models/energy.obj"))
		{
			var energyText = Assets.getText("assets/models/energy.obj");
			_energyMesh = SimpleObjLoader.parse(energyText, _energyMaterial);
		}
		else
		{
			_energyMesh = new Mesh(new CubeGeometry(2.0, 6.0, 2.0), _energyMaterial);
		}
		_energyMesh.y = 5.0; // Hovers at height 5.0 along local normal
		_energyMesh.scale(1.5);
		_energyContainer.addChild(_energyMesh);

		_energyOrbs = [];
		for (i in 0...3)
		{
			var orb = new Mesh(new SphereGeometry(0.5, 8, 8), _orbMaterial);
			_energyContainer.addChild(orb);
			_energyOrbs.push(orb);
		}

		// 6. Parse scene spawns (points, mines, fans)
		parseSceneData();
	}

	private function parseSceneData():Void
	{
		if (!Assets.exists("assets/models/scene_data.json"))
			return;

		var jsonStr = Assets.getText("assets/models/scene_data.json");
		var data:Dynamic = Json.parse(jsonStr);

		// Start point
		if (data.start != null && data.start.pos != null)
		{
			_playerPos = new Vector3D(data.start.pos[0], data.start.pos[1], data.start.pos[2]);
		}

		// Energy spawn points
		_energyPoints = [];
		_energyMatrices = [];
		if (data.points != null)
		{
			var pts:Array<Dynamic> = cast data.points;
			for (p in pts)
			{
				_energyPoints.push(new Vector3D(p.pos[0], p.pos[1], p.pos[2]));
				if (p.matrix != null)
				{
					var mList:Array<Float> = [];
					for (val in cast(p.matrix, Array<Dynamic>)) mList.push(cast val);
					_energyMatrices.push(mList);
				}
			}
		}
		if (_energyPoints.length == 0)
		{
			_energyPoints.push(new Vector3D(0, 100, 0));
		}

		// Template OBJ for fans
		var fanTemplate:Mesh = null;
		if (Assets.exists("assets/models/fan.obj"))
		{
			fanTemplate = SimpleObjLoader.parse(Assets.getText("assets/models/fan.obj"), _fanMaterial);
		}

		var mineObjText:String = Assets.exists("assets/models/mine.obj") ? Assets.getText("assets/models/mine.obj") : "";

		// Spawn Mines
		_mines = [];
		_mineMeshes = [];
		_minePositions = [];
		_mineRotSpeeds = [];
		_mineFrequencies = [];
		_mineVisible = [];
		if (data.mines != null)
		{
			var mList:Array<Dynamic> = cast data.mines;
			for (m in mList)
			{
				var pos = new Vector3D(m.pos[0], m.pos[1], m.pos[2]);
				var mineContainer = new ObjectContainer3D();

				if (m.matrix != null)
				{
					setContainerMatrix(mineContainer, cast m.matrix);
				}
				else
				{
					mineContainer.position = pos;
					var normal = pos.clone();
					normal.normalize();
					orientObjectToNormal(mineContainer, pos, normal);
				}

				var mineMesh:ObjectContainer3D;
				if (mineObjText.length > 0)
				{
					mineMesh = SimpleObjLoader.parseMulti(mineObjText, _mineMaterials, _mineMaterials.get("23_-_Default"));
				}
				else
				{
					mineMesh = new ObjectContainer3D();
					var fallbackMesh = new Mesh(new SphereGeometry(2.5, 12, 10), _mineMaterials.get("23_-_Default"));
					mineMesh.addChild(fallbackMesh);
				}
				mineMesh.scale(1.1);
				mineContainer.addChild(mineMesh);
				_view.scene.addChild(mineContainer);

				_mines.push(mineContainer);
				_mineMeshes.push(mineMesh);
				_minePositions.push(pos);
				_mineRotSpeeds.push(2.5 + Math.random() * 3.5);
				_mineFrequencies.push(Math.random() * 500);
				_mineVisible.push(true);
			}
		}

		// Spawn Fans
		_fans = [];
		_fanContainers = [];
		_fanPositions = [];
		_fanSpeeds = [];
		_fanScales = [];
		if (data.fans != null)
		{
			var fList:Array<Dynamic> = cast data.fans;
			for (f in fList)
			{
				var pos = new Vector3D(f.pos[0], f.pos[1], f.pos[2]);
				var s:Float = (f.scale != null && f.scale[0] != null) ? f.scale[0] : 1.0;

				var fanContainer = new ObjectContainer3D();
				if (f.matrix != null)
				{
					setContainerMatrix(fanContainer, cast f.matrix);
				}
				else
				{
					fanContainer.position = pos;
					var normal = pos.clone();
					normal.normalize();
					orientObjectToNormal(fanContainer, pos, normal);
				}

				var fanMesh:Mesh;
				if (fanTemplate != null)
				{
					fanMesh = cast fanTemplate.clone();
				}
				else
				{
					fanMesh = new Mesh(new CubeGeometry(6.0, 0.8, 6.0), _fanMaterial);
				}

				fanContainer.addChild(fanMesh);
				_view.scene.addChild(fanContainer);

				_fans.push(fanMesh);
				_fanContainers.push(fanContainer);
				_fanPositions.push(pos);
				_fanSpeeds.push(7.0 + Math.random() * 8.0);
				_fanScales.push(s);
			}
		}
	}

	private function loadAnimatedAstronaut():Void
	{
		_astronautMesh = new ObjectContainer3D();

		if (Assets.exists("assets/models/astronaut_anim.bin"))
		{
			try
			{
				var ba:ByteArray = Assets.getBytes("assets/models/astronaut_anim.bin");
				ba.endian = Endian.LITTLE_ENDIAN;
				ba.position = 0;

				var magic = ba.readUTFBytes(4);
				if (magic == "ANIM")
				{
					var numSubmeshes = ba.readUnsignedShort();
					var numFrames = ba.readUnsignedShort();
					var runStart = ba.readUnsignedShort();
					var runCount = ba.readUnsignedShort();
					var jumpStart = ba.readUnsignedShort();
					var jumpCount = ba.readUnsignedShort();
					var idleFrame = ba.readUnsignedShort();

					// Submesh 0: Suit
					var suitVertCount = ba.readUnsignedInt();
					var suitUVs = new Vector<Float>(suitVertCount * 2, true);
					for (i in 0...(suitVertCount * 2))
					{
						suitUVs[i] = ba.readFloat();
					}
					var suitIndices = new Vector<UInt>(suitVertCount, true);
					for (i in 0...suitVertCount)
					{
						suitIndices[i] = i;
					}
					_suitFrames = [];
					for (f in 0...numFrames)
					{
						var fv = new Vector<Float>(suitVertCount * 3, true);
						for (i in 0...(suitVertCount * 3))
						{
							fv[i] = ba.readFloat();
						}
						_suitFrames.push(fv);
					}

					_suitSubGeom = new SubGeometry();
					_suitSubGeom.autoDeriveVertexNormals = false;
					_suitSubGeom.updateUVData(suitUVs);
					_suitSubGeom.updateIndexData(suitIndices);
					_suitSubGeom.updateVertexData(_suitFrames[idleFrame]);

					var suitGeom = new Geometry();
					suitGeom.addSubGeometry(_suitSubGeom);
					var suitMesh = new Mesh(suitGeom, _astronautMaterial);
					_astronautMesh.addChild(suitMesh);

					// Submesh 1: Backpack
					var bpVertCount = ba.readUnsignedInt();
					var bpUVs = new Vector<Float>(bpVertCount * 2, true);
					for (i in 0...(bpVertCount * 2))
					{
						bpUVs[i] = ba.readFloat();
					}
					var bpIndices = new Vector<UInt>(bpVertCount, true);
					for (i in 0...bpVertCount)
					{
						bpIndices[i] = i;
					}
					_backpackFrames = [];
					for (f in 0...numFrames)
					{
						var fv = new Vector<Float>(bpVertCount * 3, true);
						for (i in 0...(bpVertCount * 3))
						{
							fv[i] = ba.readFloat();
						}
						_backpackFrames.push(fv);
					}

					_backpackSubGeom = new SubGeometry();
					_backpackSubGeom.autoDeriveVertexNormals = false;
					_backpackSubGeom.updateUVData(bpUVs);
					_backpackSubGeom.updateIndexData(bpIndices);
					_backpackSubGeom.updateVertexData(_backpackFrames[idleFrame]);

					var bpGeom = new Geometry();
					bpGeom.addSubGeometry(_backpackSubGeom);
					var bpMesh = new Mesh(bpGeom, _backpackMaterial);
					_astronautMesh.addChild(bpMesh);

					// Submesh 2: Helmet
					var helmetVertCount = ba.readUnsignedInt();
					var helmetUVs = new Vector<Float>(helmetVertCount * 2, true);
					for (i in 0...(helmetVertCount * 2))
					{
						helmetUVs[i] = ba.readFloat();
					}
					var helmetIndices = new Vector<UInt>(helmetVertCount, true);
					for (i in 0...helmetVertCount)
					{
						helmetIndices[i] = i;
					}
					_helmetFrames = [];
					for (f in 0...numFrames)
					{
						var fv = new Vector<Float>(helmetVertCount * 3, true);
						for (i in 0...(helmetVertCount * 3))
						{
							fv[i] = ba.readFloat();
						}
						_helmetFrames.push(fv);
					}

					_helmetSubGeom = new SubGeometry();
					_helmetSubGeom.autoDeriveVertexNormals = false;
					_helmetSubGeom.updateUVData(helmetUVs);
					_helmetSubGeom.updateIndexData(helmetIndices);
					_helmetSubGeom.updateVertexData(_helmetFrames[idleFrame]);

					var helmetGeom = new Geometry();
					helmetGeom.addSubGeometry(_helmetSubGeom);
					var helmetMesh = new Mesh(helmetGeom, _helmetMaterial);
					_astronautMesh.addChild(helmetMesh);

					_hasAnimatedAstronaut = true;
					_animFrame = idleFrame;
				}
			}
			catch (e:Dynamic)
			{
				trace("Error loading animated astronaut: " + e);
			}
		}

		if (!_hasAnimatedAstronaut)
		{
			if (Assets.exists("assets/models/astronaut.obj"))
			{
				var astroText = Assets.getText("assets/models/astronaut.obj");
				var mats = new Map<String, MaterialBase>();
				mats.set("Material_#25", _astronautMaterial);
				mats.set("Material_#27", _backpackMaterial);
				mats.set("head", _helmetMaterial);
				var multiMesh = SimpleObjLoader.parseMulti(astroText, mats, _astronautMaterial);
				_astronautMesh.addChild(multiMesh);
			}
			else
			{
				var cube = new Mesh(new CubeGeometry(1.6, 3.2, 1.2), _astronautMaterial);
				cube.y = 1.6;
				_astronautMesh.addChild(cube);
			}
		}

		_astronautMesh.scale(4.5);
		_astronautMesh.y = 0.0;
		_groundContainer.addChild(_astronautMesh);
	}

	private function setAstronautFrame(frame:Int):Void
	{
		if (!_hasAnimatedAstronaut || frame == _animFrame) return;
		_animFrame = frame;
		if (_suitFrames.length > frame && _suitSubGeom != null)
			_suitSubGeom.updateVertexData(_suitFrames[frame]);
		if (_backpackFrames.length > frame && _backpackSubGeom != null)
			_backpackSubGeom.updateVertexData(_backpackFrames[frame]);
		if (_helmetFrames.length > frame && _helmetSubGeom != null)
			_helmetSubGeom.updateVertexData(_helmetFrames[frame]);
	}

	private function setContainerMatrix(obj:ObjectContainer3D, matrix16:Array<Dynamic>):Void
	{
		var raw = new openfl.Vector<Float>(16);
		for (i in 0...16)
		{
			raw[i] = cast matrix16[i];
		}
		var mat = new Matrix3D(raw);
		obj.transform = mat;
	}

	private function orientObjectToNormal(object:ObjectContainer3D, surfacePos:Vector3D, normal:Vector3D):Void
	{
		var tangent = Math.abs(normal.y) < 0.9 ? new Vector3D(0, 1, 0) : new Vector3D(1, 0, 0);
		tangent = tangent.crossProduct(normal);
		tangent.normalize();
		object.position = surfacePos;
		object.lookAt(surfacePos.add(tangent), normal);
	}

	private function initSounds():Void
	{
		_sndStart = loadSoundSafe("assets/audio/StartSound");
		_sndJump = loadSoundSafe("assets/audio/JumpSound");
		_sndCoin = loadSoundSafe("assets/audio/CoinSound");
		_sndMine = loadSoundSafe("assets/audio/MineSound");
		_sndFan = loadSoundSafe("assets/audio/FanSound");
		_sndDead = loadSoundSafe("assets/audio/DeadSound");
		_sndPower = loadSoundSafe("assets/audio/ResetSound");
		_sndMusic = loadSoundSafe("assets/audio/MusicSound");

		playMusic();
	}

	private function loadSoundSafe(basePath:String):Sound
	{
		var cleanPath = basePath;
		if (cleanPath.lastIndexOf(".") > cleanPath.lastIndexOf("/"))
		{
			cleanPath = cleanPath.substr(0, cleanPath.lastIndexOf("."));
		}

		var exts = [".ogg", ".wav", ".mp3"];
		for (ext in exts)
		{
			var candidate = cleanPath + ext;
			try
			{
				if (Assets.exists(candidate))
				{
					var s = Assets.getSound(candidate);
					if (s != null) return s;
				}
			}
			catch (e:Dynamic) {}

			try
			{
				var buf = AudioBuffer.fromFile(candidate);
				if (buf != null)
				{
					var s = Sound.fromAudioBuffer(buf);
					if (s != null) return s;
				}
			}
			catch (e:Dynamic) {}
		}
		return null;
	}

	private function playSound(snd:Sound, vol:Float = 1.0):Void
	{
		if (snd == null) return;
		try
		{
			snd.play(0, 0, new SoundTransform(vol));
		}
		catch (e:Dynamic) {}
	}

	private function playMusic():Void
	{
		if (_sndMusic == null) return;
		try
		{
			if (_musicChannel != null)
			{
				_musicChannel.stop();
			}
			_musicChannel = _sndMusic.play(0, 999999, new SoundTransform(0.55));
		}
		catch (e:Dynamic) {}
	}

	private function initAuthenticUI():Void
	{
		_hudLayer = new Sprite();
		addChild(_hudLayer);

		var shadow = new DropShadowFilter(3, 45, 0x000000, 0.85, 4, 4);

		// ==================== 1. TOP-LEFT POINTS PANEL ====================
		_pointsPanel = new Sprite();
		_hudLayer.addChild(_pointsPanel);

		var g = _pointsPanel.graphics;
		g.lineStyle(3, 0xD4E63C, 1.0, true, LineScaleMode.NORMAL, CapsStyle.ROUND, JointStyle.ROUND);
		g.beginFill(0x567D1E, 0.92);
		g.moveTo(0, 0);
		g.lineTo(170, 0);
		g.lineTo(195, 45);
		g.lineTo(150, 75);
		g.lineTo(0, 70);
		g.lineTo(0, 0);
		g.endFill();

		g.lineStyle(2, 0x365012, 1.0);
		g.beginFill(0x27380D, 0.95);
		g.drawRoundRect(105, 8, 48, 25, 6, 6);
		g.drawRoundRect(105, 40, 48, 25, 6, 6);
		g.endFill();

		var lblPoints = new TextField();
		lblPoints.defaultTextFormat = new TextFormat("_sans", 17, 0xF9B219, true);
		lblPoints.text = "points";
		lblPoints.x = 14;
		lblPoints.y = 8;
		lblPoints.selectable = false;
		lblPoints.filters = [shadow];
		_pointsPanel.addChild(lblPoints);

		_pointsScoreText = new TextField();
		_pointsScoreText.defaultTextFormat = new TextFormat("_sans", 16, 0x5CD620, true, null, null, null, null, TextFormatAlign.CENTER);
		_pointsScoreText.text = "0";
		_pointsScoreText.x = 105;
		_pointsScoreText.y = 10;
		_pointsScoreText.width = 48;
		_pointsScoreText.selectable = false;
		_pointsPanel.addChild(_pointsScoreText);

		var lblBest = new TextField();
		lblBest.defaultTextFormat = new TextFormat("_sans", 17, 0xF9B219, true);
		lblBest.text = "best";
		lblBest.x = 14;
		lblBest.y = 40;
		lblBest.selectable = false;
		lblBest.filters = [shadow];
		_pointsPanel.addChild(lblBest);

		_bestScoreText = new TextField();
		_bestScoreText.defaultTextFormat = new TextFormat("_sans", 16, 0xF9B219, true, null, null, null, null, TextFormatAlign.CENTER);
		_bestScoreText.text = "0";
		_bestScoreText.x = 105;
		_bestScoreText.y = 42;
		_bestScoreText.width = 48;
		_bestScoreText.selectable = false;
		_pointsPanel.addChild(_bestScoreText);

		_pointsPanel.x = 15;
		_pointsPanel.y = 15;

		// ==================== 2. TOP-RIGHT ENERGY PANEL ====================
		_energyPanel = new Sprite();
		_hudLayer.addChild(_energyPanel);

		var eg = _energyPanel.graphics;
		eg.lineStyle(3, 0x1E5B5B, 1.0, true, LineScaleMode.NORMAL, CapsStyle.ROUND, JointStyle.ROUND);
		eg.beginFill(0x133946, 0.88);
		eg.moveTo(25, 0);
		eg.lineTo(165, 0);
		eg.lineTo(165, 78);
		eg.lineTo(0, 78);
		eg.lineTo(25, 0);
		eg.endFill();

		eg.lineStyle(2, 0x00FF88, 1.0);
		eg.beginFill(0x008844, 1.0);
		eg.drawRoundRect(28, 14, 16, 48, 8, 8);
		eg.endFill();
		eg.lineStyle(0, 0, 0);
		eg.beginFill(0x00FF88, 1.0);
		eg.drawRect(26, 22, 20, 4);
		eg.drawRect(26, 36, 20, 4);
		eg.drawRect(26, 50, 20, 4);
		eg.endFill();

		var lblEnergy = new TextField();
		lblEnergy.defaultTextFormat = new TextFormat("_sans", 17, 0x00E588, true);
		lblEnergy.text = "energy";
		lblEnergy.x = 60;
		lblEnergy.y = 6;
		lblEnergy.selectable = false;
		lblEnergy.filters = [shadow];
		_energyPanel.addChild(lblEnergy);

		_energyCountText = new TextField();
		_energyCountText.defaultTextFormat = new TextFormat("_sans", 20, 0x33FFFF, true);
		_energyCountText.text = "0/3";
		_energyCountText.x = 75;
		_energyCountText.y = 28;
		_energyCountText.selectable = false;
		_energyCountText.filters = [shadow];
		_energyPanel.addChild(_energyCountText);

		_stageLevelText = new TextField();
		_stageLevelText.defaultTextFormat = new TextFormat("_sans", 13, 0xFFDF33, true);
		_stageLevelText.text = "STAGE 1";
		_stageLevelText.x = 60;
		_stageLevelText.y = 52;
		_stageLevelText.selectable = false;
		_stageLevelText.filters = [shadow];
		_energyPanel.addChild(_stageLevelText);

		// ==================== 3. INSTRUCTIONS MODAL CARD ====================
		_instructionsModal = new Sprite();
		_hudLayer.addChild(_instructionsModal);

		var mw:Float = 480;
		var mh:Float = 330;
		var mg = _instructionsModal.graphics;

		mg.lineStyle(4, 0x00FFFF, 1.0);
		mg.beginFill(0x18BEE4, 0.96);
		mg.drawRoundRect(-mw * 0.5, -mh * 0.5, mw, mh, 20, 20);
		mg.endFill();

		mg.lineStyle(0, 0, 0);
		mg.beginFill(0xF7B519, 1.0);
		mg.drawRect(-mw * 0.5 + 4, -mh * 0.5 + 16, mw - 8, 36);
		mg.endFill();

		var titleFormat = new TextFormat("_sans", 22, 0xFFFFFF, true, null, null, null, null, TextFormatAlign.CENTER);
		var tfInstructions = new TextField();
		tfInstructions.defaultTextFormat = titleFormat;
		tfInstructions.text = "INSTRUCTIONS";
		tfInstructions.x = -mw * 0.5;
		tfInstructions.y = -mh * 0.5 + 18;
		tfInstructions.width = mw * 0.5;
		tfInstructions.filters = [new GlowFilter(0x003366, 0.9, 4, 4, 3)];
		tfInstructions.selectable = false;
		_instructionsModal.addChild(tfInstructions);

		var tfControls = new TextField();
		tfControls.defaultTextFormat = titleFormat;
		tfControls.text = "CONTROLS";
		tfControls.x = 0;
		tfControls.y = -mh * 0.5 + 18;
		tfControls.width = mw * 0.5;
		tfControls.filters = [new GlowFilter(0x003366, 0.9, 4, 4, 3)];
		tfControls.selectable = false;
		_instructionsModal.addChild(tfControls);

		var goldFormat = new TextFormat("_sans", 15, 0xFFB71E, true, null, null, null, null, TextFormatAlign.CENTER);

		var lblPick = new TextField();
		lblPick.defaultTextFormat = goldFormat;
		lblPick.text = "PICK UP 3 ENERGY";
		lblPick.x = -mw * 0.5;
		lblPick.y = -mh * 0.5 + 68;
		lblPick.width = mw * 0.5;
		lblPick.filters = [shadow];
		lblPick.selectable = false;
		_instructionsModal.addChild(lblPick);

		mg.lineStyle(2, 0x003311, 1.0);
		mg.beginFill(0x00FF66, 1.0);
		mg.drawRoundRect(-135, -mh * 0.5 + 98, 22, 44, 10, 10);
		mg.endFill();
		mg.beginFill(0x004411, 1.0);
		mg.drawRect(-138, -mh * 0.5 + 108, 28, 5);
		mg.drawRect(-138, -mh * 0.5 + 124, 28, 5);
		mg.endFill();

		var lblDestroy = new TextField();
		lblDestroy.defaultTextFormat = goldFormat;
		lblDestroy.text = "JUMP TO DESTROY";
		lblDestroy.x = -mw * 0.5;
		lblDestroy.y = -mh * 0.5 + 160;
		lblDestroy.width = mw * 0.5;
		lblDestroy.filters = [shadow];
		lblDestroy.selectable = false;
		_instructionsModal.addChild(lblDestroy);

		mg.lineStyle(2, 0x003388, 1.0);
		mg.beginFill(0x2288EE, 1.0);
		mg.drawEllipse(-145, -mh * 0.5 + 200, 42, 18);
		mg.endFill();
		mg.beginFill(0xFF5500, 1.0);
		mg.drawEllipse(-135, -mh * 0.5 + 196, 22, 14);
		mg.endFill();
		mg.beginFill(0xFF1100, 1.0);
		mg.drawCircle(-152, -mh * 0.5 + 200, 5);
		mg.drawCircle(-96, -mh * 0.5 + 200, 5);
		mg.drawCircle(-146, -mh * 0.5 + 224, 5);
		mg.drawCircle(-102, -mh * 0.5 + 224, 5);
		mg.endFill();

		var lblMove = new TextField();
		lblMove.defaultTextFormat = goldFormat;
		lblMove.text = "MOVE WITH";
		lblMove.x = 0;
		lblMove.y = -mh * 0.5 + 68;
		lblMove.width = mw * 0.5;
		lblMove.filters = [shadow];
		lblMove.selectable = false;
		_instructionsModal.addChild(lblMove);

		mg.lineStyle(2, 0x888888, 1.0);
		mg.beginFill(0xEEEEEE, 1.0);
		mg.drawRoundRect(70, -mh * 0.5 + 102, 34, 30, 6, 6);
		mg.drawRoundRect(115, -mh * 0.5 + 102, 34, 30, 6, 6);
		mg.endFill();

		var arrowFormat = new TextFormat("_sans", 16, 0x333333, true, null, null, null, null, TextFormatAlign.CENTER);
		var arrLeft = new TextField();
		arrLeft.defaultTextFormat = arrowFormat;
		arrLeft.text = "◄";
		arrLeft.x = 70;
		arrLeft.y = -mh * 0.5 + 106;
		arrLeft.width = 34;
		arrLeft.selectable = false;
		_instructionsModal.addChild(arrLeft);

		var arrRight = new TextField();
		arrRight.defaultTextFormat = arrowFormat;
		arrRight.text = "►";
		arrRight.x = 115;
		arrRight.y = -mh * 0.5 + 106;
		arrRight.width = 34;
		arrRight.selectable = false;
		_instructionsModal.addChild(arrRight);

		var lblJump = new TextField();
		lblJump.defaultTextFormat = goldFormat;
		lblJump.text = "JUMP WITH";
		lblJump.x = 0;
		lblJump.y = -mh * 0.5 + 160;
		lblJump.width = mw * 0.5;
		lblJump.filters = [shadow];
		lblJump.selectable = false;
		_instructionsModal.addChild(lblJump);

		mg.lineStyle(2, 0x888888, 1.0);
		mg.beginFill(0xEEEEEE, 1.0);
		mg.drawRoundRect(35, -mh * 0.5 + 195, 150, 32, 6, 6);
		mg.endFill();

		var spaceFormat = new TextFormat("_sans", 12, 0x666666, true, null, null, null, null, TextFormatAlign.CENTER);
		var tfSpace = new TextField();
		tfSpace.defaultTextFormat = spaceFormat;
		tfSpace.text = "SPACEBAR";
		tfSpace.x = 35;
		tfSpace.y = -mh * 0.5 + 201;
		tfSpace.width = 150;
		tfSpace.selectable = false;
		_instructionsModal.addChild(tfSpace);

		var speedTuneFormat = new TextFormat("_sans", 11, 0xFFFFFF, true, null, null, null, null, TextFormatAlign.CENTER);
		var tfSpeedTune = new TextField();
		tfSpeedTune.defaultTextFormat = speedTuneFormat;
		tfSpeedTune.text = "ADJUST SPEED: [-] SLOWER / [+] FASTER";
		tfSpeedTune.x = -mw * 0.5;
		tfSpeedTune.y = -mh * 0.5 + 236;
		tfSpeedTune.width = mw;
		tfSpeedTune.selectable = false;
		tfSpeedTune.filters = [shadow];
		_instructionsModal.addChild(tfSpeedTune);

		mg.lineStyle(3, 0x00FFFF, 1.0);
		mg.beginFill(0x00D9FF, 1.0);
		mg.moveTo(-160, mh * 0.5 - 12);
		mg.lineTo(160, mh * 0.5 - 12);
		mg.lineTo(140, mh * 0.5 + 32);
		mg.lineTo(-140, mh * 0.5 + 32);
		mg.lineTo(-160, mh * 0.5 - 12);
		mg.endFill();

		var startFormat = new TextFormat("_sans", 18, 0xFFB71E, true, null, null, null, null, TextFormatAlign.CENTER);
		var tfStart = new TextField();
		tfStart.defaultTextFormat = startFormat;
		tfStart.text = "press spacebar to start";
		tfStart.x = -150;
		tfStart.y = mh * 0.5 + 2;
		tfStart.width = 300;
		tfStart.filters = [shadow];
		tfStart.selectable = false;
		_instructionsModal.addChild(tfStart);

		// ==================== 4. GAME OVER SCORE BANNER ====================
		_scoreModal = new Sprite();
		_hudLayer.addChild(_scoreModal);

		var sg = _scoreModal.graphics;
		sg.lineStyle(3, 0x00FFFF, 1.0);
		sg.beginFill(0x27C9F2, 0.95);
		sg.drawRoundRect(-120, -45, 290, 85, 12, 12);
		sg.endFill();

		drawStar(sg, -135, -5, 5, 52, 24, 0xF8B918, 0xE09508);

		var starFormat = new TextFormat("_sans", 18, 0x1B2C68, true, null, null, null, null, TextFormatAlign.CENTER);
		var tfStar = new TextField();
		tfStar.defaultTextFormat = starFormat;
		tfStar.text = "SCORE";
		tfStar.x = -170;
		tfStar.y = -15;
		tfStar.width = 70;
		tfStar.selectable = false;
		_scoreModal.addChild(tfStar);

		var scoreValFormat = new TextFormat("_sans", 46, 0x1B2C68, true, null, null, null, null, TextFormatAlign.CENTER);
		_scoreModalValueText = new TextField();
		_scoreModalValueText.defaultTextFormat = scoreValFormat;
		_scoreModalValueText.text = "0";
		_scoreModalValueText.x = -60;
		_scoreModalValueText.y = -35;
		_scoreModalValueText.width = 200;
		_scoreModalValueText.filters = [new GlowFilter(0xFFFFFF, 0.8, 4, 4, 2)];
		_scoreModalValueText.selectable = false;
		_scoreModal.addChild(_scoreModalValueText);

		sg.lineStyle(3, 0x00FFFF, 1.0);
		sg.beginFill(0x00D9FF, 1.0);
		sg.drawRoundRect(-150, 60, 300, 38, 8, 8);
		sg.endFill();

		var retryFormat = new TextFormat("_sans", 16, 0xFFB71E, true, null, null, null, null, TextFormatAlign.CENTER);
		var tfRetry = new TextField();
		tfRetry.defaultTextFormat = retryFormat;
		tfRetry.text = "press spacebar to restart";
		tfRetry.x = -150;
		tfRetry.y = 68;
		tfRetry.width = 300;
		tfRetry.filters = [shadow];
		tfRetry.selectable = false;
		_scoreModal.addChild(tfRetry);

		_scoreModal.visible = false;

		// ==================== 5. STAGE CLEARED & SPEED UP BANNER ====================
		_speedBanner = new Sprite();
		_hudLayer.addChild(_speedBanner);

		var bw = 380;
		var bh = 210;
		var bg = _speedBanner.graphics;
		bg.lineStyle(4, 0x00FFFF, 1.0);
		bg.beginFill(0x081F36, 0.96);
		bg.drawRoundRect(-bw * 0.5, -bh * 0.5, bw, bh, 20, 20);
		bg.endFill();

		bg.lineStyle(2, 0xFFDF33, 0.9);
		bg.drawRoundRect(-bw * 0.5 + 8, -bh * 0.5 + 8, bw - 16, bh - 16, 16, 16);

		// Action button background
		bg.lineStyle(2, 0x00FFFF, 1.0);
		bg.beginFill(0x0077B3, 0.92);
		bg.drawRoundRect(-155, bh * 0.5 - 46, 310, 36, 10, 10);
		bg.endFill();

		_speedBanner.filters = [new GlowFilter(0x00E5FF, 0.85, 20, 20, 2), shadow];

		_stageClearTitle = new TextField();
		_stageClearTitle.defaultTextFormat = new TextFormat("_sans", 22, 0xFFDF33, true, null, null, null, null, TextFormatAlign.CENTER);
		_stageClearTitle.text = "★ STAGE CLEARED! ★";
		_stageClearTitle.x = -bw * 0.5;
		_stageClearTitle.y = -bh * 0.5 + 14;
		_stageClearTitle.width = bw;
		_stageClearTitle.selectable = false;
		_stageClearTitle.filters = [shadow];
		_speedBanner.addChild(_stageClearTitle);

		_speedValueText = new TextField();
		_speedValueText.defaultTextFormat = new TextFormat("_sans", 38, 0x00FFFF, true, null, null, null, null, TextFormatAlign.CENTER);
		_speedValueText.text = "SPEED x2";
		_speedValueText.x = -bw * 0.5;
		_speedValueText.y = -bh * 0.5 + 46;
		_speedValueText.width = bw;
		_speedValueText.selectable = false;
		_speedValueText.filters = [new GlowFilter(0x00FFFF, 0.9, 8, 8, 2)];
		_speedBanner.addChild(_speedValueText);

		_bonusScoreText = new TextField();
		_bonusScoreText.defaultTextFormat = new TextFormat("_sans", 18, 0x5CD620, true, null, null, null, null, TextFormatAlign.CENTER);
		_bonusScoreText.text = "+3000 BONUS PTS!";
		_bonusScoreText.x = -bw * 0.5;
		_bonusScoreText.y = -bh * 0.5 + 94;
		_bonusScoreText.width = bw;
		_bonusScoreText.selectable = false;
		_bonusScoreText.filters = [shadow];
		_speedBanner.addChild(_bonusScoreText);

		var subText = new TextField();
		subText.defaultTextFormat = new TextFormat("_sans", 12, 0xCCEEFF, false, null, null, null, null, TextFormatAlign.CENTER);
		subText.text = "ENERGY 3/3 COMPLETED • READY FOR NEXT SPEED";
		subText.x = -bw * 0.5;
		subText.y = -bh * 0.5 + 122;
		subText.width = bw;
		subText.selectable = false;
		_speedBanner.addChild(subText);

		_continueBtnText = new TextField();
		_continueBtnText.defaultTextFormat = new TextFormat("_sans", 14, 0xFFFFFF, true, null, null, null, null, TextFormatAlign.CENTER);
		_continueBtnText.text = "PRESS SPACEBAR TO CONTINUE ▶";
		_continueBtnText.x = -155;
		_continueBtnText.y = bh * 0.5 - 38;
		_continueBtnText.width = 310;
		_continueBtnText.selectable = false;
		_continueBtnText.filters = [shadow];
		_speedBanner.addChild(_continueBtnText);

		_speedBanner.buttonMode = true;
		_speedBanner.useHandCursor = true;
		_speedBanner.addEventListener(MouseEvent.CLICK, function(e:MouseEvent) {
			handleActionTrigger();
		});

		_speedBanner.visible = false;
	}

	private function showStageClearBanner():Void
	{
		_state = "stage_clear";
		_speedBanner.visible = true;
		_speedBanner.alpha = 1.0;
		_speedBanner.scaleX = 1.0;
		_speedBanner.scaleY = 1.0;

		_stageClearTitle.text = "★ STAGE " + (_speedLevel - 1) + " CLEARED! ★";
		_speedValueText.text = "SPEED x" + _speedLevel;
		_bonusScoreText.text = "+3000 BONUS PTS!";
		_continueBtnText.text = "PRESS SPACEBAR FOR STAGE " + _speedLevel + " ▶";
		_shakeFactor = 3.5;
	}

	private function spawnPowerBurst():Void
	{
		var colors = [0xFFDF33, 0x00FFFF, 0xFF44AA, 0x5CD620, 0xFFFFFF];
		var cx = stage != null ? stage.stageWidth * 0.5 : 512.0;
		var cy = stage != null ? stage.stageHeight * 0.42 : 250.0;
		for (i in 0...25)
		{
			var p = new Sprite();
			var g = p.graphics;
			var col = colors[i % colors.length];
			g.beginFill(col, 1.0);
			var size = 4.0 + Math.random() * 6.0;
			g.drawRect(-size * 0.5, -size * 0.5, size, size);
			g.endFill();
			p.x = cx;
			p.y = cy;

			var angle = Math.random() * Math.PI * 2.0;
			var spd = 6.0 + Math.random() * 12.0;
			_hudLayer.addChild(p);
			_powerBurstParticles.push(p);
			_powerParticleVels.push(new Vector3D(Math.cos(angle) * spd, Math.sin(angle) * spd, 0));
			_powerParticleLife.push(1.0);
		}
	}

	private static function drawStar(g:openfl.display.Graphics, x:Float, y:Float, points:Int, outerRadius:Float, innerRadius:Float, fillCol:Int, lineCol:Int):Void
	{
		g.lineStyle(3, lineCol, 1.0);
		g.beginFill(fillCol, 1.0);
		var step = Math.PI / points;
		var angle = -Math.PI * 0.5;
		g.moveTo(x + Math.cos(angle) * outerRadius, y + Math.sin(angle) * outerRadius);
		for (i in 0...points)
		{
			angle += step;
			g.lineTo(x + Math.cos(angle) * innerRadius, y + Math.sin(angle) * innerRadius);
			angle += step;
			g.lineTo(x + Math.cos(angle) * outerRadius, y + Math.sin(angle) * outerRadius);
		}
		g.endFill();
	}

	private function updateHUDText():Void
	{
		if (_score > _bestScore) _bestScore = _score;
		_pointsScoreText.text = Std.string(_score);
		_bestScoreText.text = Std.string(_bestScore);
		_energyCountText.text = _energyCount + "/3";
		if (_stageLevelText != null)
		{
			_stageLevelText.text = "STAGE " + _speedLevel;
		}
		if (_scoreModalValueText != null)
		{
			_scoreModalValueText.text = Std.string(_score);
		}
	}

	private function initEvents():Void
	{
		addEventListener(Event.ENTER_FRAME, onEnterFrame);
		stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
		stage.addEventListener(KeyboardEvent.KEY_UP, onKeyUp);
		stage.addEventListener(MouseEvent.MOUSE_DOWN, onScreenTouch);
		stage.addEventListener(TouchEvent.TOUCH_BEGIN, onScreenTouch);
		stage.addEventListener(Event.RESIZE, onResize);
		onResize();
	}

	private function resetGame():Void
	{
		_state = "start";
		_score = 0;
		_speed = 0.28;
		_speedLevel = 1;
		_energyCount = 0;
		_jumpHeight = 0.0;
		_jumpVelocity = 0.0;
		_shakeFactor = 0.0;
		_runTimer = 0.0;
		_lastFrameTime = 0.0;
		_camPos = null;
		_camFocus = null;
		_camUp = null;

		_groundContainer.visible = true;
		_astronautMesh.visible = true;
		_jetpackFlame.visible = false;
		setAstronautFrame(51);
		_animTimer = 0.0;

		// Snap to authentic start point on the planet floor
		var rawStart = new Vector3D(47.075, 42.356, -80.147);
		if (_floorRaycaster != null)
		{
			var hit = _floorRaycaster.raycastDown(rawStart);
			_playerPos = hit.point;
			_surfaceNormal = hit.normal;
		}
		else
		{
			_playerPos = rawStart;
			_surfaceNormal = rawStart.clone();
			_surfaceNormal.normalize();
		}

		// Authentic forward tangent vector running down the runway
		_forwardDir = new Vector3D(-0.1768, 0.9237, 0.3397);
		var proj = _forwardDir.dotProduct(_surfaceNormal);
		_forwardDir = new Vector3D(_forwardDir.x - _surfaceNormal.x * proj,
			_forwardDir.y - _surfaceNormal.y * proj,
			_forwardDir.z - _surfaceNormal.z * proj);
		_forwardDir.normalize();

		// Spawn initial energy canister
		_currentEnergyIndex = 0;
		if (_energyPoints.length > 0)
		{
			setEnergyIndex(_currentEnergyIndex);
			_energyContainer.visible = true;
		}

		// Reset all mines
		for (i in 0..._mines.length)
		{
			_mines[i].visible = true;
			_mineVisible[i] = true;
		}

		_instructionsModal.visible = true;
		_scoreModal.visible = false;
		_speedBannerTimer = 0;
		if (_speedBanner != null) _speedBanner.visible = false;

		for (p in _powerBurstParticles)
		{
			if (p.parent != null) p.parent.removeChild(p);
		}
		_powerBurstParticles = [];
		_powerParticleVels = [];
		_powerParticleLife = [];

		updateHUDText();

		// Snap camera high overhead looking forward down the track
		snapCameraToStart();
	}

	private function setEnergyIndex(index:Int):Void
	{
		_currentEnergyIndex = index;
		if (_energyMatrices.length > _currentEnergyIndex)
		{
			setContainerMatrix(_energyContainer, _energyMatrices[_currentEnergyIndex]);
		}
		else if (_energyPoints.length > _currentEnergyIndex)
		{
			var pos = _energyPoints[_currentEnergyIndex];
			var normal = pos.clone();
			normal.normalize();
			orientObjectToNormal(_energyContainer, pos, normal);
		}
	}

	private function snapCameraToStart():Void
	{
		var camPos = _playerPos.add(new Vector3D(_surfaceNormal.x * 55.0 - _forwardDir.x * 32.0,
			_surfaceNormal.y * 55.0 - _forwardDir.y * 32.0,
			_surfaceNormal.z * 55.0 - _forwardDir.z * 32.0));
		_view.camera.moveTo(camPos.x, camPos.y, camPos.z);
		var lookAhead = 26.0;
		var playerFocus = _playerPos.add(new Vector3D(
			_surfaceNormal.x * 3.0 + _forwardDir.x * lookAhead,
			_surfaceNormal.y * 3.0 + _forwardDir.y * lookAhead,
			_surfaceNormal.z * 3.0 + _forwardDir.z * lookAhead));

		_camPos = camPos.clone();
		_camFocus = playerFocus.clone();
		_camUp = _surfaceNormal.clone();
		_view.camera.lookAt(_camFocus, _camUp);
	}

	private function onKeyDown(e:KeyboardEvent):Void
	{
		if (e.keyCode == Keyboard.LEFT || e.keyCode == 65) // A
			_leftPressed = true;
		if (e.keyCode == Keyboard.RIGHT || e.keyCode == 68) // D
			_rightPressed = true;
		if (e.keyCode == Keyboard.SPACE || e.keyCode == Keyboard.UP || e.keyCode == 87 || e.keyCode == Keyboard.ENTER)
		{
			handleActionTrigger();
		}
		if (e.keyCode == 189 || e.keyCode == 109 || e.keyCode == 219) // - or NumPad - or [
		{
			_speed = Math.max(0.12, _speed - 0.03);
			updateHUDText();
		}
		if (e.keyCode == 187 || e.keyCode == 107 || e.keyCode == 221 || e.keyCode == 61) // + or = or NumPad + or ]
		{
			_speed = Math.min(1.20, _speed + 0.03);
			updateHUDText();
		}
		if (e.keyCode == 69) // E key: collect energy / test stage progression
		{
			playSound(_sndCoin);
			_score += 300;
			_energyCount++;
			if (_energyCount >= 3)
			{
				_energyCount = 0;
				_speedLevel++;
				_speed += 0.04;
				_score += 3000;
				_state = "stage_clear";
				playSound(_sndPower);
				showStageClearBanner();
				spawnPowerBurst();
			}
			updateHUDText();
		}
	}

	private function onKeyUp(e:KeyboardEvent):Void
	{
		if (e.keyCode == Keyboard.LEFT || e.keyCode == 65)
			_leftPressed = false;
		if (e.keyCode == Keyboard.RIGHT || e.keyCode == 68)
			_rightPressed = false;
	}

	private function onScreenTouch(e:Dynamic):Void
	{
		handleActionTrigger();
	}

	private function handleActionTrigger():Void
	{
		if (_sndMusic != null && _musicChannel == null)
		{
			playMusic();
		}

		if (_state == "start")
		{
			_state = "run";
			_jumpHeight = 0.0;
			_jumpVelocity = 0.0;
			_instructionsModal.visible = false;
			_scoreModal.visible = false;
			_speedBanner.visible = false;
			playSound(_sndStart);
		}
		else if (_state == "stage_clear")
		{
			// Advance into the newly unlocked speed stage!
			_state = "run";
			_speedBanner.visible = false;
			_jumpHeight = 0.0;
			_jumpVelocity = 0.0;
			playSound(_sndStart);
		}
		else if ((_state == "run" || _state == "boost") && _jumpHeight <= 0.05)
		{
			// Authentic Flare3D jump velocity with comfortable hang-time
			_state = "jump";
			_jumpVelocity = 3.2;
			playSound(_sndJump);
		}
		else if (_state == "die" || _state == "fan")
		{
			resetGame();
		}
	}

	private function onEnterFrame(e:Event):Void
	{
		var currentTime = openfl.Lib.getTimer();
		var dtScale:Float = 1.0;
		if (_lastFrameTime > 0.0)
		{
			var deltaMs = currentTime - _lastFrameTime;
			dtScale = deltaMs / 16.667;
			if (dtScale < 0.2) dtScale = 0.2;
			if (dtScale > 2.0) dtScale = 2.0;
		}
		_lastFrameTime = currentTime;

		// Subtle cosmic sky rotation
		if (_skyMesh != null)
		{
			_skyMesh.yaw(0.005 * dtScale);
		}

		// Stage Cleared button pulsing animation
		if (_state == "stage_clear" && _continueBtnText != null)
		{
			_continueBtnText.alpha = 0.75 + Math.sin(openfl.Lib.getTimer() * 0.009) * 0.25;
		}

		// Update celebratory power burst particles
		var pIdx = _powerBurstParticles.length - 1;
		while (pIdx >= 0)
		{
			var p = _powerBurstParticles[pIdx];
			var v = _powerParticleVels[pIdx];
			p.x += v.x * dtScale;
			p.y += v.y * dtScale;
			v.y += 0.28 * dtScale;
			v.x *= 0.95;
			v.y *= 0.95;
			_powerParticleLife[pIdx] -= 0.022 * dtScale;
			var life = _powerParticleLife[pIdx];
			p.alpha = life;
			p.scaleX = life;
			p.scaleY = life;
			if (life <= 0)
			{
				if (p.parent != null) p.parent.removeChild(p);
				_powerBurstParticles.splice(pIdx, 1);
				_powerParticleVels.splice(pIdx, 1);
				_powerParticleLife.splice(pIdx, 1);
			}
			pIdx--;
		}

		updateGamePhysics(dtScale);
		updateEntities(dtScale);
		updateCamera(dtScale);

		_view.render();
	}

	private function updateGamePhysics(dtScale:Float = 1.0):Void
	{
		// 1. Steering rotation around surface normal: responsive 0.052 rad per frame at 60fps
		var steerSpeed:Float = 0.052 * dtScale;
		if (_leftPressed)
		{
			_forwardDir = rotateVectorAroundAxis(_forwardDir, _surfaceNormal, -steerSpeed);
			_forwardDir.normalize();
		}
		if (_rightPressed)
		{
			_forwardDir = rotateVectorAroundAxis(_forwardDir, _surfaceNormal, steerSpeed);
			_forwardDir.normalize();
		}

		// 2. Forward movement along spherical terrain during active gameplay
		if (_state == "run" || _state == "jump" || _state == "boost")
		{
			var currentSpeed = (_state == "boost") ? _speed * 1.35 : _speed;
			var moveDist = currentSpeed * dtScale;
			var nextPos = new Vector3D(_playerPos.x + _forwardDir.x * moveDist,
				_playerPos.y + _forwardDir.y * moveDist,
				_playerPos.z + _forwardDir.z * moveDist);

			// Authentic Flare3D RayCollision: Snap next position directly to floor geometry with smooth normal orientation
			if (_floorRaycaster != null)
			{
				var hit = _floorRaycaster.raycastDown(nextPos);
				_playerPos = hit.point;
				var targetNorm = hit.normal;
				var sphereNorm = _playerPos.clone();
				sphereNorm.normalize();
				if (targetNorm.dotProduct(sphereNorm) < 0.70)
				{
					targetNorm = sphereNorm;
				}
				var normLerp = Math.min(1.0, 0.15 * dtScale);
				_surfaceNormal.x += (targetNorm.x - _surfaceNormal.x) * normLerp;
				_surfaceNormal.y += (targetNorm.y - _surfaceNormal.y) * normLerp;
				_surfaceNormal.z += (targetNorm.z - _surfaceNormal.z) * normLerp;
				_surfaceNormal.normalize();
			}
			else
			{
				_playerPos = nextPos;
			}

			// Authentic Flare3D SphereCollision.slider(): keep player smoothly between obstacle walls
			if (_obstacleCollider != null)
			{
				_playerPos = _obstacleCollider.slider(_playerPos, _surfaceNormal, 3.0);
			}

			// Ensure forward vector remains strictly tangent to surface normal
			var proj = _forwardDir.dotProduct(_surfaceNormal);
			_forwardDir = new Vector3D(_forwardDir.x - _surfaceNormal.x * proj,
				_forwardDir.y - _surfaceNormal.y * proj,
				_forwardDir.z - _surfaceNormal.z * proj);
			_forwardDir.normalize();
		}

		// 3. Authentic Flare3D gravity & jump physics with comfortable hang-time
		if (_state == "jump" || _jumpHeight > 0.0)
		{
			// Gravity acceleration
			_jumpVelocity -= 0.18 * dtScale;
			_jumpHeight += _jumpVelocity * dtScale;

			// Land safely back on the ground surface
			if (_jumpHeight <= 0.0)
			{
				_jumpHeight = 0.0;
				_jumpVelocity = 0.0;
				if (_state == "jump")
				{
					_state = "run";
				}
			}
		}
		else
		{
			_jumpHeight = 0.0;
			_jumpVelocity = 0.0;
		}

		// 4. Fan hazard launch into outer space
		if (_state == "fan")
		{
			_jumpVelocity = 3.5;
			_jumpHeight += _jumpVelocity * dtScale;
			_shakeFactor = 1.2;

			// Spin wildly out of control
			_astronautMesh.rotationY += 22.0 * dtScale;

			// If blown far enough, show score modal to restart
			if (_jumpHeight > 350.0)
			{
				_speedBanner.visible = false;
				_scoreModal.visible = true;
			}
		}

		// State timers
		if (_state == "boost")
		{
			_stateTimer--;
			if (_stateTimer <= 0) _state = "run";
		}
		else if (_state == "die")
		{
			_stateTimer--;
			if (_stateTimer <= 0)
			{
				_speedBanner.visible = false;
				_scoreModal.visible = true;
			}
		}

		// Position ground container directly on the floor polygon
		_groundContainer.position = _playerPos;
		_groundContainer.lookAt(_playerPos.add(_forwardDir), _surfaceNormal);

		// Contact shadow stays on the ground surface beneath astronaut
		if (_shadowMesh != null)
		{
			var shadowScale = Math.max(0.6, 1.6 - _jumpHeight * 0.04);
			_shadowMesh.scaleX = shadowScale;
			_shadowMesh.scaleZ = shadowScale;
			_shadowMesh.visible = (_state != "die" && _jumpHeight < 250.0);
		}

		// 5. Authentic running, jumping, and idle animation
		if (_state == "run" || _state == "boost")
		{
			if (_hasAnimatedAstronaut)
			{
				_animTimer += ((_state == "boost") ? 0.048 : 0.035) * dtScale;
				var runFrame = Std.int(_animTimer * 30.0) % 22;
				setAstronautFrame(runFrame);
			}

			_runTimer += _speed * 0.45 * dtScale;

			// Stride vertical bobbing (footstep bounce)
			var strideBob = Math.abs(Math.sin(_runTimer)) * 0.4;
			_astronautMesh.y = strideBob;

			// Banking into turns
			var bankRoll = 0.0;
			if (_leftPressed) bankRoll = -12.0;
			if (_rightPressed) bankRoll = 12.0;

			_astronautMesh.rotationZ = bankRoll;
			// Forward running lean
			_astronautMesh.rotationX = 10.0;
			_astronautMesh.rotationY = 0.0;

			_jetpackFlame.visible = (_speed > 0.6 || _state == "boost");
		}
		else if (_state == "jump")
		{
			if (_hasAnimatedAstronaut)
			{
				var jumpProgress = Math.min(1.0, Math.max(0.0, 1.0 - (_jumpVelocity + 3.2) / 6.4));
				var jumpFrame = 22 + Std.int(jumpProgress * 43.0);
				if (jumpFrame > 65) jumpFrame = 65;
				setAstronautFrame(jumpFrame);
			}

			_astronautMesh.y = _jumpHeight;
			_astronautMesh.rotationX = -8.0; // Arching in mid-air
			_astronautMesh.rotationZ = 0.0;
			_astronautMesh.rotationY = 0.0;
			_jetpackFlame.visible = true;
		}
		else if (_state == "fan")
		{
			if (_hasAnimatedAstronaut)
			{
				setAstronautFrame(35); // Mid-air splay pose
			}

			_astronautMesh.y = _jumpHeight;
			_astronautMesh.rotationX = 25.0;
			_jetpackFlame.visible = true;
		}
		else
		{
			if (_hasAnimatedAstronaut)
			{
				setAstronautFrame(51); // Standing idle pose
			}

			_astronautMesh.y = 0.0;
			_astronautMesh.rotationX = 0.0;
			_astronautMesh.rotationY = 0.0;
			_astronautMesh.rotationZ = 0.0;
			_jetpackFlame.visible = false;
		}
	}

	private function updateEntities(dtScale:Float = 1.0):Void
	{
		var headOffset = _jumpHeight + 3.0;
		var playerHeadPos = _groundContainer.position.add(new Vector3D(_surfaceNormal.x * headOffset, _surfaceNormal.y * headOffset, _surfaceNormal.z * headOffset));

		// 1. Fans update and collision
		for (i in 0..._fans.length)
		{
			var fan = _fans[i];
			fan.yaw(_fanSpeeds[i] * dtScale);

			var dist = Vector3D.distance(_fanPositions[i], _groundContainer.position);
			var threshold = 15.0 * _fanScales[i];

			// Only trigger if player touches fan at ground level
			if (dist < threshold && _jumpHeight < 3.5 && _state != "fan" && _state != "die" && _state != "start" && _state != "stage_clear")
			{
				_state = "fan";
				_jumpVelocity = 3.5;
				_speedBanner.visible = false;
				playSound(_sndFan);
				_shakeFactor = 1.5;
				_scoreModal.visible = true;
				updateHUDText();
			}
		}

		// 2. Mines update and collision
		var timer = openfl.Lib.getTimer() * 0.003;
		for (i in 0..._mines.length)
		{
			if (!_mineVisible[i])
			{
				// Authentic Flash game: respawn mine when player runs to opposite side of planet
				var dot = _minePositions[i].x * _playerPos.x + _minePositions[i].y * _playerPos.y + _minePositions[i].z * _playerPos.z;
				if (dot < 0)
				{
					_mineVisible[i] = true;
					_mines[i].visible = true;
				}
				continue;
			}

			var mineMesh = _mineMeshes[i];
			mineMesh.yaw(_mineRotSpeeds[i] * dtScale);
			mineMesh.y = Math.sin(timer + i) * 0.35;

			var dist = Vector3D.distance(_minePositions[i], playerHeadPos);
			if (dist < 8.0 && _state != "die" && _state != "start" && _state != "fan" && _state != "stage_clear")
			{
				if (_jumpHeight > 1.2 && _jumpVelocity < 0.5)
				{
					// Stomp on mine from above!
					_mineVisible[i] = false;
					_mines[i].visible = false;
					_jumpVelocity = 3.2; // Bounce up from stomp
					_score += 100;
					if (_score > _bestScore) _bestScore = _score;
					_shakeFactor = 2.5;
					playSound(_sndMine);
					updateHUDText();
				}
				else if (_jumpHeight <= 1.2 && (_state == "run" || _state == "boost"))
				{
					// Crashed into mine on ground level!
					_state = "die";
					_stateTimer = 45;
					_groundContainer.visible = false;
					_speedBanner.visible = false;
					_shakeFactor = 7.0;
					playSound(_sndDead);
				}
			}
		}

		// 3. Energy Canister update, orb rotation, and pickup
		if (_energyContainer.visible && _energyPoints.length > 0)
		{
			_energyMesh.yaw(3.5 * dtScale);

			// Rotate 3 orbiting green energy orbs around capsule
			var orbTime = openfl.Lib.getTimer() * 0.004;
			for (i in 0..._energyOrbs.length)
			{
				var a = orbTime + (i * (Math.PI * 2 / 3));
				_energyOrbs[i].x = Math.cos(a) * 3.5;
				_energyOrbs[i].z = Math.sin(a) * 3.5;
				_energyOrbs[i].y = 5.0 + Math.sin(a * 2.0) * 0.8;
			}

			var dist = Vector3D.distance(_energyContainer.position, playerHeadPos);
			var distFeet = Vector3D.distance(_energyContainer.position, _groundContainer.position);
			if ((dist < 12.0 || distFeet < 12.0) && _state != "die" && _state != "fan" && _state != "stage_clear")
			{
				playSound(_sndCoin);
				_score += 300;
				if (_score > _bestScore) _bestScore = _score;
				_energyCount++;

				if (_energyCount >= 3)
				{
					_energyCount = 0;
					_speedLevel++;
					_speed += 0.04;
					_score += 3000;
					if (_score > _bestScore) _bestScore = _score;
					_state = "stage_clear";
					playSound(_sndPower);
					showStageClearBanner();
					spawnPowerBurst();
				}

				// Pick new random point
				var nextIdx = Std.random(_energyPoints.length);
				if (nextIdx == _currentEnergyIndex)
				{
					nextIdx = (nextIdx + 1) % _energyPoints.length;
				}
				setEnergyIndex(nextIdx);

				updateHUDText();
			}
		}
	}

	private function updateCamera(dtScale:Float = 1.0):Void
	{
		// Camera anchors to ground position and looks forward along track towards upcoming obstacles
		var focusOffset = _jumpHeight * 0.4 + 3.0;
		var lookAhead = 26.0;
		var targetFocus = _playerPos.add(new Vector3D(
			_surfaceNormal.x * focusOffset + _forwardDir.x * lookAhead,
			_surfaceNormal.y * focusOffset + _forwardDir.y * lookAhead,
			_surfaceNormal.z * focusOffset + _forwardDir.z * lookAhead));

		var targetCamPos = _playerPos.add(new Vector3D(
			_surfaceNormal.x * 55.0 - _forwardDir.x * 32.0,
			_surfaceNormal.y * 55.0 - _forwardDir.y * 32.0,
			_surfaceNormal.z * 55.0 - _forwardDir.z * 32.0));

		var targetUp = _surfaceNormal;

		if (_camPos == null) _camPos = targetCamPos.clone();
		if (_camFocus == null) _camFocus = targetFocus.clone();
		if (_camUp == null) _camUp = targetUp.clone();

		// Smooth chase camera interpolation with frame-rate scaling
		var posLerp = Math.min(1.0, 0.08 * dtScale);
		_camPos.x += (targetCamPos.x - _camPos.x) * posLerp;
		_camPos.y += (targetCamPos.y - _camPos.y) * posLerp;
		_camPos.z += (targetCamPos.z - _camPos.z) * posLerp;

		var focusLerp = Math.min(1.0, 0.10 * dtScale);
		_camFocus.x += (targetFocus.x - _camFocus.x) * focusLerp;
		_camFocus.y += (targetFocus.y - _camFocus.y) * focusLerp;
		_camFocus.z += (targetFocus.z - _camFocus.z) * focusLerp;

		var upLerp = Math.min(1.0, 0.10 * dtScale);
		_camUp.x += (targetUp.x - _camUp.x) * upLerp;
		_camUp.y += (targetUp.y - _camUp.y) * upLerp;
		_camUp.z += (targetUp.z - _camUp.z) * upLerp;
		_camUp.normalize();

		var cx = _camPos.x;
		var cy = _camPos.y;
		var cz = _camPos.z;

		// Screen shake
		if (_shakeFactor > 0.1)
		{
			cx += (Math.random() - 0.5) * _shakeFactor;
			cy += (Math.random() - 0.5) * _shakeFactor;
			cz += (Math.random() - 0.5) * _shakeFactor;
			_shakeFactor *= 0.9;
		}

		_view.camera.moveTo(cx, cy, cz);
		_view.camera.lookAt(_camFocus, _camUp);
	}

	/**
	 * Rodrigues' rotation formula: Rotates vector v around unit axis by theta radians.
	 */
	private static function rotateVectorAroundAxis(v:Vector3D, axis:Vector3D, theta:Float):Vector3D
	{
		var cosT = Math.cos(theta);
		var sinT = Math.sin(theta);
		var dot = v.dotProduct(axis);
		var cross = axis.crossProduct(v);

		return new Vector3D(v.x * cosT + cross.x * sinT + axis.x * dot * (1.0 - cosT),
			v.y * cosT + cross.y * sinT + axis.y * dot * (1.0 - cosT),
			v.z * cosT + cross.z * sinT + axis.z * dot * (1.0 - cosT));
	}

	private function onResize(e:Event = null):Void
	{
		if (stage == null) return;
		_view.width = stage.stageWidth;
		_view.height = stage.stageHeight;

		if (_energyPanel != null)
		{
			_energyPanel.x = stage.stageWidth - 175;
			_energyPanel.y = 15;
		}

		if (_instructionsModal != null)
		{
			_instructionsModal.x = stage.stageWidth * 0.5;
			_instructionsModal.y = stage.stageHeight * 0.36;
			_instructionsModal.scaleX = 0.85;
			_instructionsModal.scaleY = 0.85;
		}

		if (_scoreModal != null)
		{
			_scoreModal.x = stage.stageWidth * 0.5;
			_scoreModal.y = stage.stageHeight * 0.5;
		}

		if (_speedBanner != null)
		{
			_speedBanner.x = stage.stageWidth * 0.5;
			_speedBanner.y = stage.stageHeight * 0.42;
		}
	}
}
