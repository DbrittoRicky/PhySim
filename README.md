# PhySim

A Godot 4.x-based physics simulation environment inspired by tools like Endorphin, focused on interactive runtime editing, ragdoll experimentation, and extensible simulation "world states" (e.g., vacuum vs atmosphere). The long-term goal is to integrate AI-driven optimization strategies to reduce CPU workload while preserving believable motion.

> **This project is licensed under the [GNU General Public License v3.0](COPYING).** See the [License](#license) section for details.

---

## Project Status

This project is under active development. Core interaction, selection, UI tooling, ragdoll workflows, fluid dynamics, and ML inference are in place, with larger simulation systems (soft bodies, procedural animation) planned.

---

## Key Features

- **Blender-like editor workflow**
  Outliner + object properties panel, runtime editing, scene-style organization

- **3D viewport interaction**
  Select objects via mouse click directly in 3D space, with visual highlight/outline on selected objects

- **Drag & drop object manipulation**
  Grab and move rigid bodies directly in 3D space at runtime using raycasting; supports flick/throw velocity and floor collision awareness

- **Runtime physics authoring for basic rigid bodies**
  Edit common properties at runtime for primitives (cube, sphere, etc.), including:
  - Mass
  - Gravity scale
  - Friction
  - Absorbent
  - Rough
  - Bounce
  - Angular damping
  - Linear damping

- **Ragdolls with per-bone control**
  Ragdolls are implemented and support runtime editing per bone, including:
  - Mass (per bone)
  - Gravity scale (per bone)
  - Angular damping (per bone)
  - Linear damping (per bone)

- **Switchable environment states**
  Multiple simulation modes managed by a global `EnvironmentManager` autoload that applies external forces consistently across the scene, including:
  - Vacuum (no external drag/resistance)
  - Atmosphere (air drag/resistance applied as per-tick forces)

- **Fluid dynamics (FluidVolume)**
  Spawnable `Area3D`-based fluid volumes with configurable density, buoyancy, and drag. Objects and ragdoll bones interact with fluid volumes based on their own density, with visual color indication for placed volumes.

- **ONNX-based ML inference (via GDExtension)**
  Integrates the [Godot ONNX AI Models Loader](https://github.com/mat490/Godot-ONNX-AI-Models-Loaders) GDExtension to load and run pre-trained `.onnx` models directly inside Godot. Exposes an `ONNXLoader` node with `load_model(path)` and `predict(input_data)` methods, enabling in-engine ML inference as a foundation for the planned AI optimization layer.

---

## Why This Exists

Most game engines provide solid physics, but experimentation-heavy simulation workflows often need:

- Fast iteration with live parameter tuning
- Clear per-part control (especially for ragdolls)
- Simple toggles for world "conditions" (vacuum/air, etc.)
- A path toward smarter performance strategies beyond brute-force CPU stepping

*This project aims to become a focused sandbox for that style of work — eventually with AI-assisted optimization.*

---

## Dependencies

### Godot ONNX AI Models Loader (GDExtension)

PhySim uses the **[Godot ONNX AI Models Loader](https://github.com/mat490/Godot-ONNX-AI-Models-Loaders)** by [mat490](https://github.com/mat490) to enable ML model inference inside Godot.

This GDExtension is built on top of [ONNX Runtime](https://onnxruntime.ai/) and adds the `ONNXLoader` node to Godot, which is used as the inference backend for PhySim's planned AI-driven optimization layer.

**To set it up:**
1. Download or clone the [Godot-ONNX-AI-Models-Loaders](https://github.com/mat490/Godot-ONNX-AI-Models-Loaders) repository
2. Copy the `bin/` folder from that repository into the root of your PhySim project directory
3. Godot will automatically detect the `.gdextension` file and register the `ONNXLoader` node

> ⚠️ The `ONNXLoader` node requires models that accept integers, floats, or strings as inputs. Ensure any `.onnx` model used with PhySim is compatible with this format.

---

## Planned Features

- **AI-driven performance optimization**
  Techniques under consideration include adaptive stepping, sleeping/activation heuristics, LOD-like simulation fidelity, constraint simplification, and scenario-specific approximations. The `ONNXLoader` GDExtension is already integrated as the inference layer for this work.

- **Soft body physics**
  Deformable bodies and constraints (approach TBD)

- **Procedural animation**
  Layered procedural controllers that can complement physics-driven motion

---

## Getting Started

**Requirements:**
- Godot Engine 4.x
- The `bin/` folder from [Godot-ONNX-AI-Models-Loaders](https://github.com/mat490/Godot-ONNX-AI-Models-Loaders) placed in the project root (see [Dependencies](#dependencies))

**Run locally**

Clone the repository:

```bash
git clone https://github.com/DbrittoRicky/PhySim.git
```

Set up the ONNX GDExtension (see [Dependencies](#dependencies)).

Open the project in Godot:

```
Import the folder containing project.godot
```

Press **Play** to run the simulation environment.

---

## Design Notes (High Level)

- Physics parameters are intended to be hot-editable for rapid iteration
- World "states" act like presets or profiles that modify external forces and resistance consistently across the scene, managed by the `EnvironmentManager` autoload
- The `ONNXLoader` node is the inference entry point for future AI-driven features — models are loaded at startup and queried during simulation

---

## Screenshots / Demos

![PhySim Editor](https://github.com/user-attachments/assets/1eb0800f-7324-4e65-94ba-cee6210c1b53)

![PhySim Demo Recording](https://github.com/user-attachments/assets/25bd2714-cf54-4462-a265-bfea41e948b8)

---

## Contributing

Contributions are welcome, especially in these areas:

- UI/UX polish for editor-like workflows
- Stability improvements for ragdolls and constraints
- Performance profiling and benchmarking tooling
- Environment state system (more modes, better parameterization)
- Research prototypes for soft bodies and procedural animation
- ML model training and integration via the ONNX inference layer

By contributing to this project, you agree that your contributions will be licensed under the same **GNU General Public License v3.0** that covers the project. Please ensure you have read and understood the license before submitting a pull request.

---

## Roadmap (Suggested Milestones)

**Milestone 1: Simulation scalability**
- Stress-test scenes with many objects/ragdolls
- Add scalable simulation controls (quality tiers, selective activation)

**Milestone 2: AI optimization layer**
- Collect telemetry from simulation runs
- Train or tune `.onnx` heuristics to reduce compute while maintaining motion quality
- Add "optimize scene" suggestions (sleep thresholds, solver settings, etc.) powered by the integrated `ONNXLoader`

**Milestone 3: New physics domains**
- Soft bodies prototype
- Procedural animation layer

---

## Third-Party Acknowledgements

This project uses the following third-party component:

- **[Godot ONNX AI Models Loader](https://github.com/mat490/Godot-ONNX-AI-Models-Loaders)** by mat490 — a GDExtension for loading and running ONNX models in Godot 4. Used here as the ML inference backend. *(License: see upstream repository)*

---

## License

PhySim is free software: you can redistribute it and/or modify it under the terms of the **GNU General Public License** as published by the Free Software Foundation, either **version 3 of the License**, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but **WITHOUT ANY WARRANTY**; without even the implied warranty of **MERCHANTABILITY** or **FITNESS FOR A PARTICULAR PURPOSE**. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.

The full license text is available in the [COPYING](COPYING.txt) file included in this repository.

For a list of all copyright holders, see the [AUTHORS](AUTHORS.txt) file.

> **Note on third-party components:** The `bin/` folder from the Godot ONNX AI Models Loader GDExtension is a binary dependency and is governed by its own upstream license. PhySim's GPL license applies to PhySim's own source code only.
