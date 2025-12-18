# System Ordering

Detailed explanation of how systems are ordered and executed in Zenithor.

## Overview

System execution order is determined by three factors:
1. **Stage** - Fixed execution phases within each frame
2. **Registration Order** - The order systems are registered (plugin expansion order + declaration order)
3. **Priority & Constraints** - Explicit ordering within a stage (priority sort + before/after constraints)

## Execution Stages

Systems run in a fixed sequence of stages every frame:

```
Frame N:
  1. first          ← Early setup (Time update, ImGui frame start)
  2. pre_update     ← Pre-game logic
  3. update         ← Main game logic (movement, AI, physics)
  4. post_update    ← Post-game logic (collision resolution)
  5. pre_render     ← Rendering prep (GL setup, projection matrix)
  6. render         ← Drawing (2D shapes, 3D meshes, pass submission)
  7. post_render    ← Pass finalization (commit)
  8. last           ← Late cleanup (Input reset, frame increment)
  9. post_process   ← Post-frame processing
```

### Stage Purpose Guidelines

| Stage | Purpose | Examples |
|-------|---------|----------|
| `first` | Early frame initialization | Time delta calculation, ImGui frame start |
| `pre_update` | Pre-game logic, input preprocessing | Input buffering, command queue preparation |
| `update` | Core game logic | Movement, AI, gameplay rules |
| `post_update` | Post-game logic, constraint resolution | Collision response, transform hierarchies |
| `pre_render` | Rendering preparation | Camera matrix updates, culling |
| `render` | Drawing operations | Shape rendering, mesh drawing, ImGui render |
| `post_render` | Rendering cleanup | Pass commit, framebuffer reset |
| `last` | Late frame cleanup | Input state reset, frame counters |
| `post_process` | Post-frame work | Async operations, profiling |

## Ordering Within a Stage

Within each stage, systems are ordered by:

### 1. Registration Order (Implicit)

Within a stage, the *default* order (before any priority/constraints are applied) is the order systems are registered:

- Plugins are expanded via `Requires` so dependencies come before dependents.
- The engine iterates plugins in that expanded order and registers each plugin's `systems.*` lists in declaration order.

This means that when priorities are equal and there are no constraints, dependency plugins tend to run before dependents simply because they were registered first.

### 2. Priority-Based Ordering (Explicit)

Use `priority` to control order within a stage:

```zig
pub const systems = .{
    .main = &.{
        // Runs first (lowest priority)
        .{ .system = earlySystem, .stage = .update, .config = .{
            .priority = -50
        } },

        // Runs second (default priority)
        .{ .system = normalSystem, .stage = .update },

        // Runs last (highest priority)
        .{ .system = lateSystem, .stage = .update, .config = .{
            .priority = 100
        } },
    },
};
```

**Priority rules**:
- Lower values run **first**: `-100 < -50 < 0 < 50 < 100`
- Default priority is `0`
- Valid range: `i16` (`-32768` to `32767`)
- Systems with equal priority run in registration order (stable sort)

**Priority overrides registration order**: even if PluginB depends on PluginA, a lower priority value in PluginB can cause its system to run earlier within the same stage.

### 3. Constraint-Based Ordering (Tags)

Use `before` and `after` constraints for relative ordering:

```zig
pub const systems = .{
    .main = &.{
        // Tag this system
        .{ .system = physicsUpdate, .stage = .update, .config = .{
            .tags = &.{"physics"},
        } },

        // Run after physics
        .{ .system = collisionCheck, .stage = .update, .config = .{
            .after = &.{"physics"},
        } },

        // Run before physics
        .{ .system = inputGathering, .stage = .update, .config = .{
            .before = &.{"physics"},
        } },

        // Multiple constraints
        .{ .system = render, .stage = .render, .config = .{
            .tags = &.{"rendering"},
            .after = &.{"scene-update", "camera"},
            .before = &.{"ui"},
        } },
    },
};
```

**Constraint rules**:
- `tags` - Tag this system for reference by others
- `after = &.{"tag1", "tag2"}` - Run after **all** systems with these tags
- `before = &.{"tag1"}` - Run before **all** systems with this tag
- Constraints are **stage-scoped** (only affect systems in the same stage)
- Constraints are applied *after* priority sort; the resolver keeps the priority-sorted order whenever constraints don't require reordering

## Ordering Resolution Algorithm

Systems are sorted within each stage using this process:

### Step 1: Priority Sort

Sort systems by priority (ascending) using stable sort:

```
Input systems (registration order):
  systemA (priority=0)
  systemB (priority=-10)
  systemC (priority=0)
  systemD (priority=5)

After priority sort:
  systemB (priority=-10)
  systemA (priority=0)    ← Stable: registration order preserved
  systemC (priority=0)
  systemD (priority=5)
```

### Step 2: Constraint Resolution

Apply `before`/`after` constraints via topological sort starting from the priority-sorted order:

```zig
// Example systems
.main = &.{
    .{ .system = A, .stage = .update, .config = .{
        .priority = 0,
        .tags = &.{"early"},
    } },

    .{ .system = B, .stage = .update, .config = .{
        .priority = 0,
        .after = &.{"early"},
        .tags = &.{"middle"},
    } },

    .{ .system = C, .stage = .update, .config = .{
        .priority = 0,
        .after = &.{"middle"},
    } },
};

// Constraint graph (within priority group):
//   A -> B -> C

// Final order:
//   A, B, C
```

**Topological sort rules**:
- Respects dependency edges (after/before)
- Preserves priority grouping
- Detects circular constraints (panics in Debug/ReleaseSafe during `finalize()`)

### Step 3: Validation (Debug/ReleaseSafe Only)

The engine validates constraints during startup when `SystemScheduler.finalize()` runs (Debug and ReleaseSafe builds):

**Missing Tag Error**:
```zig
.{ .system = foo, .stage = .update, .config = .{
    .after = &.{"nonexistent-tag"},  // Debug/ReleaseSafe: panic during finalize()
} }
```

**Circular Dependency Error**:
```zig
.{ .system = A, .stage = .update, .config = .{
    .tags = &.{"tag-a"},
    .after = &.{"tag-b"},
} },
.{ .system = B, .stage = .update, .config = .{
    .tags = &.{"tag-b"},
    .after = &.{"tag-a"},  // Debug/ReleaseSafe: panic during finalize()
} }
```

**In ReleaseFast/ReleaseSmall**: Validation panics are skipped for performance. Invalid constraints are typically ignored (no matching tags → no edges), which may leave systems in priority-sorted order.

## Examples

### Example 1: Basic Priority

```zig
pub const systems = .{
    .main = &.{
        .{ .system = gatherInput, .stage = .first, .config = .{
            .priority = -100  // Run very early
        } },

        .{ .system = updateGame, .stage = .update },  // Default (0)

        .{ .system = renderScene, .stage = .render, .config = .{
            .priority = 50  // Run late in render stage
        } },
    },
};
```

**Execution order**:
```
.first stage:
  gatherInput (priority=-100)

.update stage:
  updateGame (priority=0)

.render stage:
  renderScene (priority=50)
```

### Example 2: Tags and Constraints

```zig
pub const systems = .{
    .main = &.{
        // Physics simulation
        .{ .system = applyForces, .stage = .update, .config = .{
            .tags = &.{"physics"},
            .priority = -10,
        } },

        // Collision detection (after physics)
        .{ .system = detectCollisions, .stage = .update, .config = .{
            .after = &.{"physics"},
            .tags = &.{"collision"},
        } },

        // Collision resolution (after detection)
        .{ .system = resolveCollisions, .stage = .post_update, .config = .{
            .after = &.{"collision"},
        } },

        // Animation (independent, runs in parallel conceptually)
        .{ .system = updateAnimations, .stage = .update, .config = .{
            .priority = 0,
        } },
    },
};
```

**Execution order**:
```
.update stage:
  applyForces (priority=-10, tag=physics)
  detectCollisions (priority=0, after=physics, tag=collision)
  updateAnimations (priority=0)

.post_update stage:
  resolveCollisions (priority=0, after=collision)
```

### Example 3: Plugin Dependencies

```zig
// PluginA (no dependencies)
pub const PluginA = struct {
    pub const Components = .{};
    pub const Resources = .{};
    pub const Events = .{};

    pub const systems = .{
        .main = &.{
            .{ .system = systemA, .stage = .update },
        },
    };
};

// PluginB (depends on PluginA)
pub const PluginB = struct {
    pub const Requires = .{PluginA};

    pub const Components = .{};
    pub const Resources = .{};
    pub const Events = .{};

    pub const systems = .{
        .main = &.{
            .{ .system = systemB, .stage = .update },
        },
    };
};

// PluginC (depends on PluginB, transitively on PluginA)
pub const PluginC = struct {
    pub const Requires = .{PluginB};

    pub const Components = .{};
    pub const Resources = .{};
    pub const Events = .{};

    pub const systems = .{
        .main = &.{
            .{ .system = systemC, .stage = .update },
        },
    };
};

// Application
pub fn main() void {
    zenithor.run(.{PluginC}, .{});
    // Automatically includes: PluginA, PluginB, PluginC
}
```

**Execution order** (.update stage):
```
1. PluginA.systemA
2. PluginB.systemB
3. PluginC.systemC
```

### Example 4: Priority Override

Priority can override plugin dependency ordering:

```zig
// PluginA
pub const PluginA = struct {
    pub const systems = .{
        .main = &.{
            .{ .system = systemA, .stage = .update, .config = .{
                .priority = 10,  // Late priority
            } },
        },
    };
};

// PluginB depends on PluginA
pub const PluginB = struct {
    pub const Requires = .{PluginA};

    pub const systems = .{
        .main = &.{
            .{ .system = systemB, .stage = .update, .config = .{
                .priority = -10,  // Early priority
            } },
        },
    };
};
```

**Execution order** (.update stage):
```
1. PluginB.systemB (priority=-10)  ← Runs first despite depending on A
2. PluginA.systemA (priority=10)
```

**Why**: Priority takes precedence over plugin dependencies. Use this carefully!

## Complex Example: Full Game Loop (Hypothetical Plugins)

```zig
const TimePlugin = @import("time_plugin");
const InputPlugin = @import("input_plugin");
const PhysicsPlugin = @import("physics_plugin");
const RenderPlugin = @import("render_plugin");

pub const GamePlugin = struct {
    pub const Requires = .{ TimePlugin, InputPlugin, PhysicsPlugin, RenderPlugin };

    pub const systems = .{
        .main = &.{
            // Input processing (early)
            .{ .system = processInput, .stage = .pre_update, .config = .{
                .priority = -50,
                .tags = &.{"input-processing"},
            } },

            // AI decisions (after input, before physics)
            .{ .system = updateAI, .stage = .update, .config = .{
                .after = &.{"input-processing"},
                .before = &.{"physics"},
                .tags = &.{"ai"},
            } },

            // Physics update (depends on TimePlugin via Requires)
            .{ .system = stepPhysics, .stage = .update, .config = .{
                .tags = &.{"physics"},
            } },

            // Collision detection (after physics)
            .{ .system = detectCollisions, .stage = .update, .config = .{
                .after = &.{"physics"},
                .tags = &.{"collision"},
            } },

            // Game logic (after collisions)
            .{ .system = updateGameState, .stage = .post_update, .config = .{
                .after = &.{"collision"},
                .tags = &.{"game-logic"},
            } },

            // Camera tracking (before render)
            .{ .system = updateCamera, .stage = .pre_render, .config = .{
                .priority = -10,
                .tags = &.{"camera"},
            } },

            // Scene rendering (after camera)
            .{ .system = renderScene, .stage = .render, .config = .{
                .after = &.{"camera"},
                .tags = &.{"scene-render"},
            } },

            // UI rendering (after scene)
            .{ .system = renderUI, .stage = .render, .config = .{
                .after = &.{"scene-render"},
                .priority = 100,  // Ensure UI is on top
            } },
        },
    };
};
```

**Execution order**:
```
.pre_update:
  processInput (priority=-50, tag=input-processing)

.update:
  TimePlugin.updateTime (dependency)
  updateAI (after=input-processing, before=physics, tag=ai)
  stepPhysics (tag=physics)
  PhysicsPlugin.integrateVelocity (dependency)
  detectCollisions (after=physics, tag=collision)

.post_update:
  updateGameState (after=collision, tag=game-logic)

.pre_render:
  updateCamera (priority=-10, tag=camera)

.render:
  renderScene (after=camera, tag=scene-render)
  renderUI (after=scene-render, priority=100)
```

## Debugging System Order

To debug system execution order:

1. **Add debug prints in systems**:
```zig
fn mySystem() !void {
    std.debug.print("Running mySystem\n", .{});
    // ... system logic
}
```

2. **Run in Debug mode**:
```bash
zig build run-system_ordering
```

3. **Check for constraint violations**:
   - In Debug/ReleaseSafe, invalid constraints cause a panic during `finalize()` (startup)
   - Missing tags: panic mentioning the non-existent tag
   - Circular constraints: panic mentioning a circular dependency

4. **Verify stage timing**:
   - Use Time plugin to measure frame delta
   - Profile with ImGui plugin for per-system timing

## Performance Considerations

- **Stage boundaries are cheap**: Stages are a fixed enum order; the scheduler iterates stages and runs registered functions
- **Priority sorting**: One-time cost at initialization
- **Constraint resolution**: One-time topological sort at initialization
- **No runtime overhead**: System order is fixed after `finalize()`
- **Release builds**: Constraint validation removed for maximum performance

## Best Practices

### Do's
- ✅ Use stages for coarse-grained ordering (input → update → render)
- ✅ Use priority for fine-grained control within a stage
- ✅ Use tags+constraints for readable, maintainable ordering
- ✅ Keep constraints local (within a plugin) when possible
- ✅ Document why systems need specific ordering

### Don'ts
- ❌ Don't overuse constraints (prefer priority for simple cases)
- ❌ Don't create circular constraints (Debug/ReleaseSafe panic during finalize)
- ❌ Don't depend on exact registration order (use priority instead)
- ❌ Don't use priority to override critical plugin dependencies
- ❌ Don't forget to finalize schedulers (done automatically by engine)

## See Also

- docs/PLUGIN_DEVELOPMENT.md - Plugin creation guide
- docs/APPLICATION_LIFECYCLE.md - Engine initialization
- src/core/system.zig:finalize() - Sorting implementation
