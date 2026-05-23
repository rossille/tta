# Tank Arena — Step 1: Driving + Firing

A single tank drives around an empty arena and fires bullets.

---

## How to run

```
godot --path .
```

Or open `project.godot` in the Godot 4 editor and press **F5**.

**Minimum Godot version:** 4.3 (GL Compatibility renderer)

---

## Controls

| Key | Action |
|-----|--------|
| W or Up | Accelerate forward |
| S or Down | Brake / accelerate in reverse |
| A or Left | Turn left |
| D or Right | Turn right |
| Space | Fire |

---

## Where to tune

Open **`config/tank_config.gd`** — single source of truth for all parameters.
Change a number, save, re-run, feel the difference.

### Movement

| Constant | Value | Description |
|---|---|---|
| `MAX_FORWARD_SPEED` | `250.0` px/s | Top forward speed |
| `MAX_REVERSE_SPEED` | `120.0` px/s | Top reverse speed (intentionally slower) |
| `ACCELERATION` | `400.0` px/s² | Forward throttle ramp rate |
| `REVERSE_ACCELERATION` | `250.0` px/s² | Reverse throttle ramp rate |
| `FRICTION` | `300.0` px/s² | Coast-to-stop deceleration when no input |
| `TURN_RATE_RAD_PER_SEC` | `2.5` rad/s | Maximum rotation speed |
| `TURN_RATE_SCALES_WITH_SPEED` | `true` | If true, can't turn while stationary (tank-like) |

### Firing

| Constant | Value | Description |
|---|---|---|
| `BULLET_SPEED` | `600.0` px/s | Bullet travel speed |
| `FIRE_COOLDOWN` | `0.3` s | Minimum time between shots |
| `BULLET_LIFETIME` | `2.0` s | Bullet auto-removes after this duration |

All constants are also exposed as **exported variables** on each scene node,
so you can tweak them live in the Godot Inspector without restarting.

---

## Project structure

```
.
├── project.godot          # Engine config, window size, input map, autoloads
├── README.md
├── config/
│   └── tank_config.gd     # ALL tunable constants (autoloaded as TankConfig)
├── scenes/
│   ├── main.tscn          # Arena background + tank instance
│   ├── tank.tscn          # Tank (CharacterBody2D + visuals + collision)
│   └── bullet.tscn        # Bullet (Area2D + visuals + collision)
└── scripts/
    ├── tank.gd            # Movement + firing logic
    └── bullet.gd          # Bullet travel + lifetime
```

---

## What step 2 will add

- Rectangular arena walls (StaticBody2D) that the tank bounces off.
- Collision response so the tank can't drive off-screen.
