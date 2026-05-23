# Audio sources & licenses

All audio in this directory is **CC0 (Creative Commons Zero / Public Domain)** —
no attribution required, free for any use including commercial. The table
below records origin for traceability anyway.

If you ever want to swap a file, alternates from the same searches live in
`tools/audio-source/` (gitignored from Godot via `tools/.gdignore`). Re-run
the search by visiting the source URL in a browser.

## SFX

| File | Source | URL | License |
|------|--------|-----|---------|
| `sfx/tank_fire.mp3` | Freesound · GaryQ · "Tank fire Mixed" | https://freesound.org/people/GaryQ/sounds/127845/ | CC0 |
| `sfx/bullet_hit.ogg` | Kenney · Impact Sounds · `impactMetal_heavy_000` | https://kenney.nl/assets/impact-sounds | CC0 |
| `sfx/bullet_explode.mp3` | Freesound · "Sharp Explosion 4 (of 5)" | https://freesound.org/sounds/336011/ | CC0 |
| `sfx/explosion.mp3` | Freesound · ProjectsU012 · "Alpha-11 Warhead Explosion" | https://freesound.org/people/ProjectsU012/sounds/568877/ | CC0 |
| `sfx/ram_impact.mp3` | Freesound · "ANI Big Pipe Hit" | https://freesound.org/people/Q.K./sounds/244983/ | CC0 |
| `sfx/engine_idle.mp3` | Freesound · "Engine, motor (loopable)" | https://freesound.org/people/leandros.ntounis/sounds/398675/ | CC0 |
| `sfx/tracks.mp3` | Freesound · "tracks moving" | https://freesound.org/sounds/849062/ | CC0 |
| `sfx/wall_bump.mp3` | Freesound · "Heavy Metal Thud on Ground" | https://freesound.org/sounds/640204/ | CC0 |
| `sfx/pickup_ammo.ogg` | Kenney · Digital Audio · `powerUp8` | https://kenney.nl/assets/digital-audio | CC0 |
| `sfx/pickup_health.ogg` | Kenney · Digital Audio · `threeTone2` | https://kenney.nl/assets/digital-audio | CC0 |
| `sfx/countdown_beep.ogg` | Kenney · Digital Audio · `twoTone1` | https://kenney.nl/assets/digital-audio | CC0 |
| `sfx/match_go.ogg` | Kenney · Digital Audio · `highUp` | https://kenney.nl/assets/digital-audio | CC0 |
| `sfx/victory.mp3` | Freesound · "Success Fanfare Trumpets" | https://freesound.org/sounds/456966/ | CC0 |
| `sfx/defeat.mp3` | Freesound · "You failed (game jingle)" | https://freesound.org/sounds/626260/ | CC0 |

## UI

| File | Source | URL | License |
|------|--------|-----|---------|
| `ui/click.ogg` | Kenney · Interface Sounds · `click_002` | https://kenney.nl/assets/interface-sounds | CC0 |
| `ui/hover.ogg` | Kenney · Interface Sounds · `select_002` | https://kenney.nl/assets/interface-sounds | CC0 |
| `ui/confirm.ogg` | Kenney · Interface Sounds · `confirmation_001` | https://kenney.nl/assets/interface-sounds | CC0 |
| `ui/back.ogg` | Kenney · Interface Sounds · `back_002` | https://kenney.nl/assets/interface-sounds | CC0 |
| `ui/error.ogg` | Kenney · Interface Sounds · `error_005` | https://kenney.nl/assets/interface-sounds | CC0 |

## Music

| File | Source | URL | License |
|------|--------|-----|---------|
| `music/lobby.mp3` | Freesound · "Dark Ambient Loop" | https://freesound.org/sounds/371277/ | CC0 |
| `music/arena.mp3` | Freesound · "Action music loop with dark ambient drones" | https://freesound.org/sounds/155139/ | CC0 |

## Format notes

- **Kenney** files arrive as `.ogg` (Vorbis) — Godot's preferred format. Cleanly loopable.
- **Freesound** previews are 128 kbps MP3 (the full-quality WAVs require a free account). Adequate for a hobby game; convert to OGG later if you want to drop the slight loop-gap that MP3 has.
- Convert MP3 → OGG when needed: `ffmpeg -i in.mp3 -c:a libvorbis -q:a 5 out.ogg`

## Picks I made blind

I curated without listening (no audio playback in my toolchain). After Samuel's
first listen, these were swapped to better candidates:

- ~~`victory.ogg` (Kenney STEEL00)~~ → **`victory.mp3` (Freesound trumpet fanfare)** — original was a tiny beep
- ~~`defeat.ogg` (Kenney STEEL14)~~ → **`defeat.mp3` (Freesound "you failed" jingle)** — paired swap with victory
- ~~`wall_bump.ogg` (Kenney synth)~~ → **`wall_bump.mp3` (Freesound real metal thud)** — original was a beep, not a thud

Other candidates to A/B test:

- **`engine_idle.mp3`** — explicitly tagged "loopable" but cleanliness varies.
  Alternates in `tools/audio-source/freesound/diesel-engine/`.
- **`victory.mp3`** — alternates with different vibes:
  - `tools/audio-source/freesound/victory-fanfare/607407_Fanfare_3_Rpg.mp3` (RPG style)
  - `tools/audio-source/freesound/victory-fanfare/812467_Angelic_Fanfare_1.mp3` (celestial)
  - `tools/audio-source/freesound/victory-fanfare/677859_Game_Success_Fanfare.mp3` (game-y)
- **`tank_fire.mp3`** — 4 alternates in `tools/audio-source/freesound/tank-cannon/`,
  including `cannon.mp3` and an 11-second `6 Pdr gun.wav` with multiple shots.

Quick preview:
```sh
afplay assets/audio/sfx/victory.mp3
afplay assets/audio/sfx/wall_bump.mp3
afplay tools/audio-source/freesound/victory-fanfare/607407_Fanfare_3_Rpg.mp3
```

## Gaps

The hero gameplay sounds (especially `tank_fire`) come from compressed 128 kbps
MP3 previews, which is fine but not punchy-cinematic. If you want top-tier audio,
the ElevenLabs prompts from earlier still apply — generate a single high-quality
tank cannon and drop it in as `sfx/tank_fire.wav`. Everything else is solid as-is.
