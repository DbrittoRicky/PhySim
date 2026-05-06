# PhySim

A Godot 4.x-based physics simulation environment inspired by tools like Endorphin, focused on interactive runtime editing, ragdoll experimentation, and extensible simulation "world states" (e.g., vacuum vs atmosphere). The long-term goal is to integrate AI-driven optimization strategies to reduce CPU workload while preserving believable motion.

> **This project is licensed under the [GNU General Public License v3.0](COPYING).** See the [License](#license) section for details.

---

## Project Status

This project is under active development. Core interaction, selection, UI tooling, and ragdoll workflows are in place, with larger simulation systems (fluids, soft bodies, procedural animation) planned.

---

## Key Features

- **Blender-like editor workflow**
  Outliner + object properties panel, runtime editing, scene-style organization

- **3D viewport interaction**
  Select objects via mouse click directly in 3D space

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
  Multiple simulation modes that affect external forces and resistance, including:
  - Vacuum (no external drag/resistance)
  - Atmosphere (air drag/resistance)

---

## Why This Exists

Most game engines provide solid physics, but experimentation-heavy simulation workflows often need:

- Fast iteration with live parameter tuning
- Clear per-part control (especially for ragdolls)
- Simple toggles for world "conditions" (vacuum/air, etc.)
- A path toward smarter performance strategies beyond brute-force CPU stepping

*This project aims to become a focused sandbox for that style of work — eventually with AI-assisted optimization.*

---

## Planned Features

- **AI-driven performance optimization**
  Techniques under consideration include adaptive stepping, sleeping/activation heuristics, LOD-like simulation fidelity, constraint simplification, and scenario-specific approximations

- **Fluid dynamics**
  Research + prototyping planned (approach TBD)

- **Soft body physics**
  Deformable bodies and constraints (approach TBD)

- **Procedural animation**
  Layered procedural controllers that can complement physics-driven motion

---

## Getting Started

**Requirements:**
Godot Engine 4.x

**Run locally**

Clone the repository:

```bash
git clone <repo-url>
```

Open the project in Godot:

```
Import the folder containing project.godot
```

Press **Play** to run the simulation environment.

---

## Design Notes (High Level)

- Physics parameters are intended to be hot-editable for rapid iteration
- World "states" act like presets or profiles that modify external forces and resistance consistently across the scene

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
- Research prototypes for fluids/soft bodies

By contributing to this project, you agree that your contributions will be licensed under the same **GNU General Public License v3.0** that covers the project. Please ensure you have read and understood the license before submitting a pull request.

---

## Roadmap (Suggested Milestones)

**Milestone 1: Simulation scalability**
- Stress-test scenes with many objects/ragdolls
- Add scalable simulation controls (quality tiers, selective activation)

**Milestone 2: AI optimization layer**
- Collect telemetry from simulation runs
- Train or tune heuristics to reduce compute while maintaining motion quality
- Add "optimize scene" suggestions (sleep thresholds, solver settings, etc.)

**Milestone 3: New physics domains**
- Fluids prototype
- Soft bodies prototype
- Procedural animation layer

---

## License

PhySim is free software: you can redistribute it and/or modify it under the terms of the **GNU General Public License** as published by the Free Software Foundation, either **version 3 of the License**, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but **WITHOUT ANY WARRANTY**; without even the implied warranty of **MERCHANTABILITY** or **FITNESS FOR A PARTICULAR PURPOSE**. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.

The full license text is available in the [COPYING](COPYING) file included in this repository.

For a list of all copyright holders, see the [AUTHORS](AUTHORS) file.
