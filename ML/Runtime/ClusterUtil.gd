# ML/Runtime/ClusterUtil.gd
# Static helpers for XZ-plane proximity clustering (Sonata-II regime).
# No instance state. Call as ClusterUtil.cluster_by_xz(bodies).

class_name ClusterUtil
extends RefCounted

const XZ_RADIUS : float = 3.0    # metres
const MAX_CLUSTER_SIZE : int = 6  # = NMAX

# Returns Array of Arrays of RigidBody3D.
# Each inner array is one cluster, len ≤ MAX_CLUSTER_SIZE.
# Greedy single-pass — fast enough for ≤100 active objects.
static func cluster_by_xz(bodies: Array) -> Array:
	var clusters  : Array = []
	var assigned  : Dictionary = {}

	for body in bodies:
		if assigned.has(body): continue
		var cluster : Array = [body]
		assigned[body] = true

		for other in bodies:
			if assigned.has(other): continue
			if cluster.size() >= MAX_CLUSTER_SIZE: break
			var bp : Vector3= body.global_position
			var op : Vector3= other.global_position
			var d  := Vector2(bp.x - op.x, bp.z - op.z).length()
			if d <= XZ_RADIUS:
				cluster.append(other)
				assigned[other] = true

		clusters.append(cluster)
	return clusters
