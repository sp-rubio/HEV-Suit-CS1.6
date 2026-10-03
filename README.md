# [ZP Extra] HEV Suit Mark IV - CS 1.6

A fully featured, Half-Life inspired HEV Suit extra item system developed for Counter-Strike 1.6 Zombie Plague servers. Optimized for stability and lower resource overhead.

## Key Features

- **Human Abilities:**
  - **Passive Protection:** 20% flat damage reduction with dynamic armor/HP regeneration mechanics.
  - **Kinetic Repulsor:** Releases an EMP shockwave pushing back nearby zombies (Consumes 50% Suit Power).
  - **Long Jump System:** Directional velocity boost triggered via `Duck + Jump` sequence.
  - **FVOX Audio Alerts:** Integrated diagnostic voice feedback for critical environmental and combat damage.

- **HEV Zombie Abilities:**
  - **Xen Displacement Orb:** Ranged projectile that teleports targeted human players to random spawn points.
  - **Death Portal:** Deploys a localized gravity hazard upon death, inflicting 50% HP/Armor damage on contact.

- **System Compatibility:**
  - Standard AMX Mod X API integration without external third-party module dependencies.
  - Core logic optimized for Linux server environments to eliminate runtime crashes.

## Downloads & Installation

Full installation packages containing precompiled binaries (`.amxx`), 3D models (`.mdl`), and audio assets (`.wav`) are hosted in the [Releases](../../releases) section.

1. Download the latest `sp_hev_suits_v2.3.zip` archive from the Releases page.
2. Extract the archive structure directly into your server's `cstrike/` directory.
3. Register `sp_hev_suits_v2.3.amxx` in `cstrike/addons/amxmodx/configs/plugins.ini`.

## Credits

- **Lead Developer:** sp-rubio
- **Co-Developer:** LyesMC
- **3D Asset Porting:** Bogdan
