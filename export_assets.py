import bpy
import os
import json

out_dir = r'D:\ai\my-llm-test\gemini-3.8-flash\yellowPlanet\assets\models'
os.makedirs(out_dir, exist_ok=True)

# 1. Export astronaut
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=r'D:\ai\my-llm-test\gemini-3.8-flash\astronaut.glb')
astro_obj = [o for o in bpy.data.objects if o.name == 'astronaut'][0]
bpy.ops.object.select_all(action='DESELECT')
astro_obj.select_set(True)
bpy.context.view_layer.objects.active = astro_obj
bpy.ops.wm.obj_export(filepath=os.path.join(out_dir, 'astronaut.obj'), export_selected_objects=True)
print('Exported astronaut.obj')

# 2. Process planet
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=r'D:\ai\my-llm-test\gemini-3.8-flash\planet.glb')

scene_data = {
    'start': None,
    'points': [],
    'fans': [],
    'mines': [],
    'obstacles': []
}

for obj in bpy.data.objects:
    pos = [round(obj.location.x, 3), round(obj.location.y, 3), round(obj.location.z, 3)]
    rot = [round(obj.rotation_euler.x, 3), round(obj.rotation_euler.y, 3), round(obj.rotation_euler.z, 3)]
    scale = [round(obj.scale.x, 3), round(obj.scale.y, 3), round(obj.scale.z, 3)]
    item = {'name': obj.name, 'pos': pos, 'rot': rot, 'scale': scale}
    
    if obj.name == 'start':
        scene_data['start'] = item
    elif obj.name.startswith('point'):
        scene_data['points'].append(item)
    elif obj.name.startswith('fan'):
        scene_data['fans'].append(item)
    elif obj.name.startswith('mine'):
        scene_data['mines'].append(item)
    elif obj.name.startswith('obstacle'):
        scene_data['obstacles'].append(item)

with open(os.path.join(out_dir, 'scene_data.json'), 'w') as f:
    json.dump(scene_data, f, indent=2)
print('Exported scene_data.json successfully')

# Export floor (planet body)
floor_obj = [o for o in bpy.data.objects if o.name == 'floor'][0]
bpy.ops.object.select_all(action='DESELECT')
floor_obj.select_set(True)
bpy.context.view_layer.objects.active = floor_obj
bpy.ops.wm.obj_export(filepath=os.path.join(out_dir, 'planet_floor.obj'), export_selected_objects=True)
print('Exported planet_floor.obj')

# Export one representative mine and fan
mine_obj = [o for o in bpy.data.objects if o.name == 'mine'][0]
bpy.ops.object.select_all(action='DESELECT')
mine_obj.select_set(True)
bpy.context.view_layer.objects.active = mine_obj
bpy.ops.wm.obj_export(filepath=os.path.join(out_dir, 'mine.obj'), export_selected_objects=True)
print('Exported mine.obj')

fan_obj = [o for o in bpy.data.objects if o.name == 'fan'][0]
bpy.ops.object.select_all(action='DESELECT')
fan_obj.select_set(True)
bpy.context.view_layer.objects.active = fan_obj
bpy.ops.wm.obj_export(filepath=os.path.join(out_dir, 'fan.obj'), export_selected_objects=True)
print('Exported fan.obj')

# Export all obstacles combined into a single static mesh (best for rendering performance!)
obs_objs = [o for o in bpy.data.objects if o.name.startswith('obstacle')]
bpy.ops.object.select_all(action='DESELECT')
for o in obs_objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = obs_objs[0]
bpy.ops.wm.obj_export(filepath=os.path.join(out_dir, 'obstacles_combined.obj'), export_selected_objects=True)
print('Exported obstacles_combined.obj')
