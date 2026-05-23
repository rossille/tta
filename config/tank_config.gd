# tank_config.gd
# All tunable movement parameters for the tank.
# Change a value here, re-run the game, and feel the difference.
# These constants are read by tank.gd and exposed as exported variables
# so you can also tweak them live via the Godot Inspector.
#
# Registered as the "TankConfig" autoload singleton in project.godot,
# which makes TankConfig.CONSTANT_NAME available globally in all scripts.

extends Node

## Maximum speed when driving forward (pixels/second)
const MAX_FORWARD_SPEED: float = 220.0

## Maximum speed when reversing — intentionally lower than forward (pixels/second)
const MAX_REVERSE_SPEED: float = 120.0

## How quickly the tank builds forward speed (pixels/second²)
const ACCELERATION: float = 150.0

## How quickly the tank builds reverse speed (pixels/second²)
const REVERSE_ACCELERATION: float = 100.0

## How quickly the tank bleeds off speed when no throttle input is given (pixels/second²)
const FRICTION: float = 80.0

## Rotation speed at full turn input (radians/second)
const TURN_RATE_RAD_PER_SEC: float = 2.2

## If true, turning speed scales with current speed — can't spin on the spot.
## Gives a more realistic, tank-like feel.
const TURN_RATE_SCALES_WITH_SPEED: bool = false

# ---------------------------------------------------------------------------
# Bullet / firing
# ---------------------------------------------------------------------------

## Speed of a fired bullet (pixels/second)
const BULLET_SPEED: float = 600.0

## Minimum time between shots (seconds)
const FIRE_COOLDOWN: float = 0.3

## How long a bullet lives before being removed (seconds)
const BULLET_LIFETIME: float = 2.0

# ---------------------------------------------------------------------------
# Combat / damage
# ---------------------------------------------------------------------------

## Damage per px/s of relative impact speed when two tanks collide.
## e.g. relative speed 150 px/s → 150 * 0.12 = 18 HP each.
const RAM_DAMAGE_FACTOR: float = 0.12

## Minimum relative approach speed (px/s) required to deal any ram damage.
## Tanks nudging each other below this threshold take no damage.
const RAM_MIN_SPEED: float = 60.0

## Seconds before the same pair of tanks can deal ram damage to each other again.
## Prevents multi-frame grinding from draining HP every tick.
const RAM_COOLDOWN: float = 0.4

## Damage a single bullet deals on hit
const BULLET_DAMAGE: float = 25.0

## Tank starting HP (also used as max HP)
const MAX_HP: float = 100.0

# ---------------------------------------------------------------------------
# Ammo
# ---------------------------------------------------------------------------

## Maximum ammo a tank can carry
const MAX_AMMO: int = 10

## Ammo each tank starts with
const START_AMMO: int = 0

## Ammo granted by each pickup
const AMMO_PER_PICKUP: int = 3

## How many pickups exist simultaneously in the arena
const AMMO_PICKUP_COUNT: int = 1

## Seconds after a pickup is collected before it respawns at a new random location
const AMMO_RESPAWN_TIME: float = 5.0

## Seconds a pickup stays in one place before teleporting to a new random location
const AMMO_RELOCATE_TIME: float = 20.0

# ---------------------------------------------------------------------------
# Health pickup
# ---------------------------------------------------------------------------

## Seconds between health pickup spawns (starts counting from match start)
const HEALTH_PICKUP_INTERVAL: float = 30.0


