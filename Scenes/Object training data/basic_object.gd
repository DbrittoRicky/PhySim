extends Node3D

# Basic Object Testing Scenario
# Similar to ragdoll testing but for primitive shapes

## Configuration
const NUM_SIMULATIONS = 100  # Number of test runs
const SIMULATION_DURATION = 5.0  # Seconds per simulation
const LOG_FREQUENCY = 0.016  # Log every physics frame (~60 FPS)

## File Output Configuration
@export var custom_output_path: String = "D:/Godot Projects/training-data-objects/Data/"  # Set in inspector or leave empty for default

const USE_CUSTOM_PATH = true  # Set to true to use CUSTOM_SAVE_PATH below
const CUSTOM_SAVE_PATH = "D:/Godot Projects/training-data-objects/Data/"  # Change this to your desired path

const DEFAULT_FILENAME = "basic_objects_simulation_data.json"
const USE_TIMESTAMP = true  # Add timestamp to filename to avoid overwriting

## Object types
enum ObjectType { SPHERE, CUBE, CYLINDER, CAPSULE }

## Spawn area bounds
const SPAWN_HEIGHT_MIN = 2.0
const SPAWN_HEIGHT_MAX = 8.0
const SPAWN_HORIZONTAL_RANGE = 3.0

## Property ranges
const MASS_MIN = 0.0
const MASS_MAX = 1000.0
const GRAVITY_SCALE_MIN = -8.0
const GRAVITY_SCALE_MAX = 8.0
const FRICTION_MIN = 0.0
const FRICTION_MAX = 1.0
const BOUNCE_MIN = 0.0
const BOUNCE_MAX = 1.0

## State tracking
var current_simulation = 0
var simulation_time = 0.0
var current_object: RigidBody3D = null
var simulation_data = []
var frame_log = []
var current_properties = {}
var is_transitioning = false  # NEW: Prevents multiple simulation endings

## Floor reference
var floor: StaticBody3D = null

func _ready():
	print("=" )
	print("PhySimAI - Basic Objects Testing Scenario")
	print("=" )
	print_output_path_info()
	setup_environment()
	start_next_simulation()

func print_output_path_info():
	"""Display where files will be saved"""
	var output_path = get_output_file_path()
	print("\nOutput Configuration:")
	print("  File will be saved to: %s" % output_path)
	print("  Absolute path: %s" % ProjectSettings.globalize_path(output_path))
	print("")

func get_output_file_path() -> String:
	"""Determine the output file path based on configuration"""
	var filename = DEFAULT_FILENAME
	
	# Add timestamp to filename if enabled
	if USE_TIMESTAMP:
		var time_dict = Time.get_datetime_dict_from_system()
		var timestamp = "%04d%02d%02d_%02d%02d%02d" % [
			time_dict.year, time_dict.month, time_dict.day,
			time_dict.hour, time_dict.minute, time_dict.second
		]
		filename = "basic_objects_%s.json" % timestamp
	
	# Priority 1: Inspector export variable
	if custom_output_path != "":
		return custom_output_path.path_join(filename)
	
	# Priority 2: Constant custom path
	if USE_CUSTOM_PATH and CUSTOM_SAVE_PATH != "":
		return CUSTOM_SAVE_PATH.path_join(filename)
	
	# Priority 3: Default to user directory
	return "user://".path_join(filename)

func ensure_directory_exists(file_path: String) -> bool:
	"""Create directory if it doesn't exist"""
	var dir_path = file_path.get_base_dir()
	
	# Convert to absolute path for directory operations
	var abs_dir_path = ProjectSettings.globalize_path(dir_path)
	
	if not DirAccess.dir_exists_absolute(abs_dir_path):
		print("Creating directory: %s" % abs_dir_path)
		var error = DirAccess.make_dir_recursive_absolute(abs_dir_path)
		if error != OK:
			push_error("Failed to create directory: %s (Error code: %d)" % [abs_dir_path, error])
			return false
		print("Directory created successfully!")
	
	return true

func setup_environment():
	"""Create the testing environment with floor and lighting"""
	# Create floor
	floor = StaticBody3D.new()
	var floor_collision = CollisionShape3D.new()
	var floor_shape = BoxShape3D.new()
	floor_shape.size = Vector3(20, 0.5, 20)
	floor_collision.shape = floor_shape
	floor.add_child(floor_collision)
	
	var floor_mesh_instance = MeshInstance3D.new()
	var floor_mesh = BoxMesh.new()
	floor_mesh.size = Vector3(20, 0.5, 20)
	floor_mesh_instance.mesh = floor_mesh
	floor.add_child(floor_mesh_instance)
	
	floor.position = Vector3(0, -0.25, 0)
	add_child(floor)
	
	# Create directional light if not present
	if not get_node_or_null("DirectionalLight3D"):
		var light = DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45, 30, 0)
		light.shadow_enabled = true
		add_child(light)

func start_next_simulation():
	"""Initialize and start a new simulation run"""
	is_transitioning = false  # Reset transition flag
	
	if current_simulation >= NUM_SIMULATIONS:
		save_all_data()
		print("\n" + "=")
		print("All simulations complete!")
		print("=" )
		get_tree().quit()
		return
	
	# Clean up previous object
	if current_object:
		current_object.queue_free()
		current_object = null
	
	# Reset tracking
	simulation_time = 0.0
	frame_log = []
	
	# Generate random properties
	current_properties = generate_random_properties()
	
	# Create object with properties
	current_object = create_object(current_properties)
	add_child(current_object)
	
	print("Starting simulation %d/%d" % [current_simulation + 1, NUM_SIMULATIONS])
	print("  Object: %s" % ObjectType.keys()[current_properties.type])
	print("  Mass: %.2f | Gravity: %.2f | Friction: %.2f | Bounce: %.2f" % [
		current_properties.mass,
		current_properties.gravity_scale,
		current_properties.friction,
		current_properties.bounce
	])

func generate_random_properties() -> Dictionary:
	"""Generate randomized physical properties for an object"""
	return {
		"type": randi() % 4,  # SPHERE, CUBE, CYLINDER, or CAPSULE
		"mass": randf_range(MASS_MIN, MASS_MAX),
		"gravity_scale": randf_range(GRAVITY_SCALE_MIN, GRAVITY_SCALE_MAX),
		"friction": randf_range(FRICTION_MIN, FRICTION_MAX),
		"bounce": randf_range(BOUNCE_MIN, BOUNCE_MAX),
		"rough": randf() > 0.5,  # Boolean checkbox property
		"absorbent": randf() > 0.5,  # Boolean checkbox property
		"spawn_position": Vector3(
			randf_range(-SPAWN_HORIZONTAL_RANGE, SPAWN_HORIZONTAL_RANGE),
			randf_range(SPAWN_HEIGHT_MIN, SPAWN_HEIGHT_MAX),
			randf_range(-SPAWN_HORIZONTAL_RANGE, SPAWN_HORIZONTAL_RANGE)
		),
		"initial_velocity": Vector3(
			randf_range(-2.0, 2.0),
			randf_range(-1.0, 1.0),
			randf_range(-2.0, 2.0)
		),
		"initial_angular_velocity": Vector3(
			randf_range(-5.0, 5.0),
			randf_range(-5.0, 5.0),
			randf_range(-5.0, 5.0)
		)
	}

func create_object(properties: Dictionary) -> RigidBody3D:
	"""Instantiate a RigidBody3D with specified properties - no scene file needed"""
	var body = RigidBody3D.new()
	
	# Create collision shape
	var collision = CollisionShape3D.new()
	var shape
	
	match properties.type:
		ObjectType.SPHERE:
			shape = SphereShape3D.new()
			shape.radius = 0.5
		ObjectType.CUBE:
			shape = BoxShape3D.new()
			shape.size = Vector3(1, 1, 1)
		ObjectType.CYLINDER:
			shape = CylinderShape3D.new()
			shape.radius = 0.5
			shape.height = 1.0
		ObjectType.CAPSULE:
			shape = CapsuleShape3D.new()
			shape.radius = 0.5
			shape.height = 1.0
	
	collision.shape = shape
	body.add_child(collision)
	
	# Create visual mesh
	var mesh_instance = MeshInstance3D.new()
	match properties.type:
		ObjectType.SPHERE:
			var sphere_mesh = SphereMesh.new()
			sphere_mesh.radius = 0.5
			sphere_mesh.height = 1.0
			mesh_instance.mesh = sphere_mesh
		ObjectType.CUBE:
			var box_mesh = BoxMesh.new()
			box_mesh.size = Vector3(1, 1, 1)
			mesh_instance.mesh = box_mesh
		ObjectType.CYLINDER:
			var cylinder_mesh = CylinderMesh.new()
			cylinder_mesh.top_radius = 0.5
			cylinder_mesh.bottom_radius = 0.5
			cylinder_mesh.height = 1.0
			mesh_instance.mesh = cylinder_mesh
		ObjectType.CAPSULE:
			var capsule_mesh = CapsuleMesh.new()
			capsule_mesh.radius = 0.5
			capsule_mesh.height = 1.0
			mesh_instance.mesh = capsule_mesh
	
	# Random color for visualization
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(randf(), randf(), randf())
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	
	# Set physics properties
	body.mass = properties.mass
	body.gravity_scale = properties.gravity_scale
	
	# Create and configure physics material
	body.physics_material_override = PhysicsMaterial.new()
	body.physics_material_override.friction = properties.friction
	body.physics_material_override.bounce = properties.bounce
	
	# Rough property affects friction behavior
	if properties.rough:
		body.physics_material_override.rough = true
		# Rough surfaces have higher friction coefficient
		body.physics_material_override.friction = min(1.0, properties.friction * 1.5)
	else:
		body.physics_material_override.rough = false
	
	# Absorbent property affects damping (energy absorption)
	if properties.absorbent:
		body.linear_damp = 2.0
		body.angular_damp = 2.0
		# Absorbent materials also reduce bounce
		body.physics_material_override.bounce = properties.bounce * 0.5
	else:
		body.linear_damp = 0.1
		body.angular_damp = 0.1
	
	# Set initial transform and velocity
	body.position = properties.spawn_position
	body.linear_velocity = properties.initial_velocity
	body.angular_velocity = properties.initial_angular_velocity
	
	return body

func _physics_process(delta):
	"""Log data and manage simulation progression"""
	if not current_object or is_transitioning:
		return
	
	simulation_time += delta
	
	# Log current frame data
	log_frame_data()
	
	# Check if simulation is complete
	if simulation_time >= SIMULATION_DURATION:
		is_transitioning = true  # Prevent multiple triggers
		finalize_simulation()
		current_simulation += 1
		
		# Use call_deferred to avoid issues with physics process
		call_deferred("transition_to_next_simulation")

func transition_to_next_simulation():
	"""Handles the transition between simulations"""
	get_tree().create_timer(0.5).timeout.connect(start_next_simulation, CONNECT_ONE_SHOT)

func log_frame_data():
	"""Capture current frame state"""
	var frame_data = {
		"timestamp": simulation_time,
		"position": {
			"x": current_object.position.x,
			"y": current_object.position.y,
			"z": current_object.position.z
		},
		"rotation": {
			"x": current_object.rotation.x,
			"y": current_object.rotation.y,
			"z": current_object.rotation.z
		},
		"linear_velocity": {
			"x": current_object.linear_velocity.x,
			"y": current_object.linear_velocity.y,
			"z": current_object.linear_velocity.z
		},
		"angular_velocity": {
			"x": current_object.angular_velocity.x,
			"y": current_object.angular_velocity.y,
			"z": current_object.angular_velocity.z
		},
		"kinetic_energy": 0.5 * current_object.mass * current_object.linear_velocity.length_squared(),
		"potential_energy": current_object.mass * abs(current_object.gravity_scale) * 9.81 * current_object.position.y
	}
	
	frame_log.append(frame_data)

func finalize_simulation():
	"""Package simulation data and add to collection"""
	var sim_record = {
		"simulation_id": current_simulation,
		"object_type": ObjectType.keys()[current_properties.type],
		"properties": {
			"mass": current_properties.mass,
			"gravity_scale": current_properties.gravity_scale,
			"friction": current_properties.friction,
			"bounce": current_properties.bounce,
			"rough": current_properties.rough,
			"absorbent": current_properties.absorbent
		},
		"initial_conditions": {
			"spawn_position": {
				"x": current_properties.spawn_position.x,
				"y": current_properties.spawn_position.y,
				"z": current_properties.spawn_position.z
			},
			"initial_velocity": {
				"x": current_properties.initial_velocity.x,
				"y": current_properties.initial_velocity.y,
				"z": current_properties.initial_velocity.z
			},
			"initial_angular_velocity": {
				"x": current_properties.initial_angular_velocity.x,
				"y": current_properties.initial_angular_velocity.y,
				"z": current_properties.initial_angular_velocity.z
			}
		},
		"duration": simulation_time,
		"frames": frame_log.duplicate(),
		"summary": calculate_summary_stats()
	}
	
	simulation_data.append(sim_record)
	print("  ✓ Simulation %d complete (%d frames logged)" % [current_simulation + 1, frame_log.size()])

func calculate_summary_stats() -> Dictionary:
	"""Calculate summary statistics for the simulation"""
	if frame_log.is_empty():
		return {}
	
	var max_height = -INF
	var min_height = INF
	var max_speed = 0.0
	var total_distance = 0.0
	var num_bounces = 0
	var avg_speed = 0.0
	
	for i in range(frame_log.size()):
		var frame = frame_log[i]
		max_height = max(max_height, frame.position.y)
		min_height = min(min_height, frame.position.y)
		
		var speed = sqrt(
			frame.linear_velocity.x ** 2 +
			frame.linear_velocity.y ** 2 +
			frame.linear_velocity.z ** 2
		)
		max_speed = max(max_speed, speed)
		avg_speed += speed
		
		# Detect bounces (y-velocity sign change from negative to positive)
		if i > 0:
			var prev_frame = frame_log[i - 1]
			var current_y_vel = frame.linear_velocity.y
			var prev_y_vel = prev_frame.linear_velocity.y
			
			if prev_y_vel < -0.5 and current_y_vel > 0.5:
				num_bounces += 1
			
			# Calculate distance traveled
			var dx = frame.position.x - prev_frame.position.x
			var dy = frame.position.y - prev_frame.position.y
			var dz = frame.position.z - prev_frame.position.z
			total_distance += sqrt(dx*dx + dy*dy + dz*dz)
	
	avg_speed /= frame_log.size()
	
	# Calculate final velocity magnitude from dictionary
	var final_vel = frame_log[-1].linear_velocity
	var final_speed = sqrt(
		final_vel.x ** 2 +
		final_vel.y ** 2 +
		final_vel.z ** 2
	)
	
	return {
		"max_height": max_height,
		"min_height": min_height,
		"max_speed": max_speed,
		"average_speed": avg_speed,
		"total_distance_traveled": total_distance,
		"estimated_bounces": num_bounces,
		"final_position": {
			"x": frame_log[-1].position.x,
			"y": frame_log[-1].position.y,
			"z": frame_log[-1].position.z
		},
		"final_velocity": {
			"x": frame_log[-1].linear_velocity.x,
			"y": frame_log[-1].linear_velocity.y,
			"z": frame_log[-1].linear_velocity.z
		},
		"came_to_rest": final_speed < 0.1
	}

func save_all_data():
	"""Save all simulation data to JSON file"""
	print("\nPreparing to save data...")
	
	var output = {
		"metadata": {
			"total_simulations": NUM_SIMULATIONS,
			"simulation_duration": SIMULATION_DURATION,
			"log_frequency": LOG_FREQUENCY,
			"property_ranges": {
				"mass": {"min": MASS_MIN, "max": MASS_MAX},
				"gravity_scale": {"min": GRAVITY_SCALE_MIN, "max": GRAVITY_SCALE_MAX},
				"friction": {"min": FRICTION_MIN, "max": FRICTION_MAX},
				"bounce": {"min": BOUNCE_MIN, "max": BOUNCE_MAX}
			},
			"object_types": ["SPHERE", "CUBE", "CYLINDER", "CAPSULE"],
			"generated_timestamp": Time.get_datetime_string_from_system()
		},
		"simulations": simulation_data
	}
	
	print("Converting to JSON...")
	var json_result = JSON.stringify(output, "\t")
	var json_string = str(json_result)
	
	var file_path = get_output_file_path()
	print("Target file path: %s" % file_path)
	
	# Ensure directory exists
	if not ensure_directory_exists(file_path):
		push_error("Cannot save file - directory creation failed")
		return
	
	# Use absolute path for file operations
	var abs_file_path = ProjectSettings.globalize_path(file_path)
	print("Absolute file path: %s" % abs_file_path)
	
	print("Opening file for writing...")
	var file = FileAccess.open(abs_file_path, FileAccess.WRITE)
	if file:
		print("Writing data...")
		file.store_string(json_string)
		var bytes_written = file.get_length()
		file.close()
		
		print("\n" + "=")
		print("SUCCESS: Data saved successfully!")
		print("=")
		print("File path: %s" % abs_file_path)
		print("File size: %.2f MB" % (bytes_written / 1024.0 / 1024.0))
		print("Total simulations: %d" % simulation_data.size())
		print("Total frames logged: %d" % get_total_frames())
		print("=")
	else:
		push_error("Failed to save data file!")
		push_error("Path: %s" % abs_file_path)
		push_error("Error code: %d" % FileAccess.get_open_error())

func get_total_frames() -> int:
	"""Count total frames across all simulations"""
	var total = 0
	for sim in simulation_data:
		total += sim.frames.size()
	return total
