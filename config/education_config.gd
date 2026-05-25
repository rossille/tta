# education_config.gd
# Optional educational module: teach multiplication tables to a child during
# gameplay. Activates only in real solo (host + zero connected guests).
#
# Master switch — two ways to disable:
#   1. Set ENABLED = false below (code-level default).
#   2. Launch with EDU=off in the environment:
#        EDU=off ./TankArena   (or set it in your shell before running)
#      Any value other than "off" (case-insensitive) keeps the module on.
#
# Registered as the "EducationConfig" autoload singleton in project.godot,
# which makes EducationConfig.CONSTANT_NAME available globally.

extends Node

## Master switch. Overridden at runtime by the EDU environment variable.
## EDU=off  → disabled regardless of this value.
## EDU=<anything else> or unset → uses this value.
var ENABLED: bool = true

func _ready() -> void:
	var env: String = OS.get_environment("EDU").strip_edges().to_lower()
	if env == "off":
		ENABLED = false

## Multiplication tables the child practices.
## Add 6, 7, ... here as the child progresses.
const TABLES: Array = [3, 4, 5]

## Range of the right-hand multiplier (e.g. [1, 10] => 3x1 .. 3x10).
const MULTIPLIER_MIN: int = 1
const MULTIPLIER_MAX: int = 10

## How many distinct equations are shown in each "learn" overlay.
const EQUATIONS_PER_SESSION: int = 3

## Seconds before the very first educational session after match start.
const FIRST_SESSION_DELAY: float = 15.0

## Seconds of gameplay between subsequent educational sessions.
## Timer only advances when the game is NOT paused — so opening the
## pause menu doesn't bring the overlay sooner.
const SESSION_INTERVAL: float = 30.0

const DELAY_BEFORE_QUIZ: float = 10.0

const PENALTY_REVIEW_DURATION: float = 15.0

const PENALTY_DELAY_BEFORE_RETRY: float = 10.0

## Ammo granted for a correct answer.
const AMMO_REWARD: int = 5

## Answer-grid range. The grid shows every integer from GRID_MIN to GRID_MAX
## (inclusive) arranged in GRID_COLUMNS columns.
const GRID_MIN: int = 1
const GRID_MAX: int = 100
const GRID_COLUMNS: int = 10
