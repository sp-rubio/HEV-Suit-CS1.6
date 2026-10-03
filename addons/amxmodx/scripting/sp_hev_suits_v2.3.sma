/*
    sp_hev_suits_v2.3.sma - HEV Suit Mark IV + Immersive Survival Edition
    Version: 2.3 (Final Masterpiece)

    Features:
    - Full sp_hev_suit native library (API for child plugins)
    - Crash-safe restore_default_weapon_model (switch-based)
    - Immersive Boot Sequence (FVOX + typewriter HUD)
    - FVOX Damage Diagnosis by damage type
    - Heartbeat / Breathing / Blink effects by HP tier
    - DHUD Integrity Bar + BPM counter (bottom of screen)
    - Geiger proximity + EMP interference (HEV Zombie vs Human)
    - Long Jump + wind sound
    - Security Firewall (blocks zombie hit every 10s)
    - Manual Syringe (drop key with wrench)
    - Wrench sound replacement for knife
    - HEV Zombie: corrupted FVOX, Xen Displacement Orb (DROP ability)
    - Death Portal (Black Hole) on HEV Zombie death
    - Anti-Stuck teleportation (from displacer logic)
    - Integrated: H.E.V Armor Battery (10 AP, +25 Armor, limit 2/round)
    - Integrated: H.E.V Medical Kit (10 AP, +25 HP, limit 2/round)
    - INI reader for extra weapon viewmodels
    - HEV Suit Speed & Gravity Penalty (-15% speed, +15% gravity for normal players)
    - Admin / VIP privilege tiers: configurable flags with reduced or no movement penalty

    Author: sp_rubio && LyesMC
    Compatible: AMX Mod X 1.8+ | Zombie Plague 4.3+
*/

// ============================================================
// INCLUDES
// ============================================================
#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <fun>
#include <cstrike>
#include <zombieplague>
#include <colorchat>
#include <dhudmessage>
#include <sp_hev_suit>

#pragma semicolon 1

// ============================================================
// CONSTANTS & CONFIGURATION
// ============================================================
#define PLUGIN_NAME     "[ZP] HEV Suit Mark IV v2.3 Immersive"
#define PLUGIN_VERSION  "2.3"
#define PLUGIN_AUTHOR   "sp_rubio && LyesMC"

#define MAX_PLAYERS     32
#define MAX_WEAPONS     64
#define MAX_MODEL_LEN   128
#define MAX_NAME_LEN    32

// Reason codes
#define HEV_REMOVE_DEATH        0
#define HEV_REMOVE_INFECTION    1
#define HEV_REMOVE_ROUNDEND     2
#define HEV_REMOVE_MANUAL       3
#define HEV_REMOVE_DISCONNECT   4

// Suit systems
#define MAX_POWER       100
#define JUMP_COST       60
#define REGEN_TICK      1
#define RECHARGE_DELAY  3.0
#define BOOST_THRES     1
#define BOOST_VALUE     50
#define HP_THRESHOLD    25
#define HP_BOOST_TO     100
#define HEV_ANIM_TIME   3.0
#define HEV_ANIM_SEQ    0
#define ADRENALINE_TIME 2.2
#define HUD_TYPING_SPD  0.13

// Immersive health thresholds
#define HEALTH_CRITICAL 20
#define HEALTH_LOW      35
#define HEALTH_MEDIUM   60

// Heartbeat / breathing intervals
#define HEARTBEAT_FAST   0.5
#define HEARTBEAT_MEDIUM 0.8
#define HEARTBEAT_SLOW   1.2
#define BREATHING_FAST   2.0
#define BREATHING_MEDIUM 3.0
#define BREATHING_SLOW   4.0

// Task ID offsets
#define TASK_HEARTBEAT      1000
#define TASK_BREATHING      2000
#define TASK_BLINK_EFFECT   3000
#define TASK_DEATH_FADE     5000
#define TASK_INJECTION_ANIM 6000
#define TASK_BOOT_SEQ       7000
#define TASK_TYPING_HUD     8000
#define TASK_SAW_FIX        9000
#define TASK_HEAL_GLOW      10000
#define TASK_PINK_GLOW      11000
#define TASK_DIAG_CHAIN     12000
#define TASK_WIND           14000
#define TASK_WARN_DELAY     15000
#define TASK_HEV_HEAD       19500
#define TASK_PORTAL_REMOVE  20000   // Death Portal removal
#define TASK_PORTAL_PULL    21000   // Portal gravity pull loop
#define TASK_ORB_ANIMATE    22000   // Xen Orb animation
#define TASK_HP_REGEN       23000   // HP regeneration tick (+1 HP/s)
#define TASK_HP_COOLDOWN    24000   // HP regen resume after 3s no-damage
#define ID_HEV_HEAD         (taskid - TASK_HEV_HEAD)

// Screen fade
#define FADE_DURATION 512
#define FADE_HOLD     256
#define FADE_IN       0x0000
#define FADE_OUT      0x0001
#define FADE_STAYOUT  0x0002

// Damage bit flags
#define DMG_FALL   (1<<5)
#define DMG_BURN   (1<<3)
#define DMG_SLASH  (1<<2)
#define DMG_SHOCK  (1<<8)
#define DMG_BULLET (1<<1)

// Diagnosis cooldown
#define DIAG_COOLDOWN 4.0

// Status icon states
#define STATUSICON_HIDE  0
#define STATUSICON_SHOW  1
#define STATUSICON_FLASH 2

// Manual syringe
#define HEALTH_ADRENALINE_MAX 30
#define HEALTH_ADRENALINE_SET 70
#define ANIM_INJECT           0
#define INJECT_DELAY          2.0

// Per-round limits
const GLOBAL_HEV_LIMIT = 8;
const BOT_HEV_LIMIT    = 3;

//         HEV Suit Speed & Gravity Penalty 
// The suit is heavy - normal players move slower and feel heavier.
// VIPs and Admins get reduced penalties as a privilege.

// Access flags - change these to match your server
#define HEV_ADMIN_FLAG  ADMIN_LEVEL_A   // flag 'a' = standard admin
#define HEV_VIP_FLAG    ADMIN_LEVEL_H   // flag 'h' = VIP (custom flag)

// Let's say normal player speed is 240
// Normal HEV player (no privilege)
#define HEV_SPEED_NORMAL    225.0       // default CS speed is ~240
#define HEV_GRAVITY_NORMAL  1.15        // heavier than default (1.0)

// VIP - smaller penalty
#define HEV_SPEED_VIP       232.0
#define HEV_GRAVITY_VIP     1.08

// Admin - no penalty 
#define HEV_SPEED_ADMIN     240.0
#define HEV_GRAVITY_ADMIN   1.0

// Integrated items limits
#define BATTERY_ARMOR_GIVE  25
#define BATTERY_ARMOR_MAX   100
#define BATTERY_LIMIT       2
#define HP_GIVE             25
#define HP_MAX              255
#define HP_KIT_LIMIT        2

// ZP extra items
new const ITEM_NAME[]        = "H.E.V Mark IV:";
new const ITEM_BATTERY_NAME[]= "H.E.V Armor Battery";
new const ITEM_MEDKIT_NAME[] = "H.E.V Medical Kit";
const ITEM_COST         = 30;
const ITEM_BATTERY_COST = 10;
const ITEM_MEDKIT_COST  = 10;

// Xen Displacement Orb
#define ORB_CLASSNAME   "xen_orb"
#define ORB_HP_COST     1500
#define ORB_COOLDOWN    40.0
#define ORB_SPEED       600.0
#define ORB_PULL_RADIUS 250.0
#define PORTAL_DURATION 5.0
#define PORTAL_CLASSNAME "hev_death_portal"

// INI config
new const HEV_INI_FILE[] = "addons/amxmodx/configs/hev_weapons.ini";
new g_IniOriginalModels[MAX_WEAPONS][MAX_MODEL_LEN];
new g_IniHEVModels[MAX_WEAPONS][MAX_MODEL_LEN];
new g_IniWeaponCount;

// ============================================================
// MODEL & SOUND PATHS
// ============================================================
new const HEV_MODEL_SHORT[]  = "player_hev";
new const HEV_ZOMBIE_FULL[]  = "models/player/hev_zombie/hev_zombie.mdl";
new const HEV_ZOMBIE_SHORT[] = "hev_zombie";

new const V_HEV_MODEL[]        = "models/v_hev.mdl";
new const V_HEV_ADRENALINE[]   = "models/v_hev_adrenaline_injector.mdl";
new const V_HEV_ZOMBIE_KNIFE[] = "models/v_hev_zombie.mdl";

new const g_InjectorV[] = "models/v_adrenaline_injector.mdl";
new const g_InjectorP[] = "models/p_adrenaline_injector.mdl";

// HEV weapon view models
new const V_HEV_AK47[]      = "models/sp_weapons_opposing_force_hve/v_sp_ak47.mdl";
new const V_HEV_M4A1[]      = "models/sp_weapons_opposing_force_hve/v_sp_m4a1.mdl";
new const V_HEV_MP5NAVY[]   = "models/sp_weapons_opposing_force_hve/v_sp_mp5.mdl";
new const V_HEV_DEAGLE[]    = "models/sp_weapons_opposing_force_hve/v_sp_deagle.mdl";
new const V_HEV_AUG[]       = "models/sp_weapons_opposing_force_hve/v_sp_aug.mdl";
new const V_HEV_M249[]      = "models/sp_weapons_opposing_force_hve/v_sp_m249.mdl";
new const V_HEV_M3[]        = "models/sp_weapons_opposing_force_hve/v_sp_m3.mdl";
new const V_HEV_XM1014[]    = "models/sp_weapons_opposing_force_hve/v_sp_xm1014.mdl";
new const V_HEV_USP[]       = "models/sp_weapons_opposing_force_hve/v_sp_usp.mdl";
new const V_HEV_P228[]      = "models/sp_weapons_opposing_force_hve/v_sp_p228.mdl";
new const V_HEV_SG550[]     = "models/sp_weapons_opposing_force_hve/v_sp_sg550.mdl";
new const V_HEV_G3SG1[]     = "models/sp_weapons_opposing_force_hve/v_sp_g3sg1.mdl";
new const V_HEV_GLOCK18[]   = "models/sp_weapons_opposing_force_hve/v_sp_glock18.mdl";
new const V_HEV_SG552[]     = "models/sp_weapons_opposing_force_hve/v_sp_sg552.mdl";
new const V_HEV_SAW[]       = "models/sp_weapons_opposing_force_hve/v_sp_m249.mdl";
new const V_HEV_ELITE[]     = "models/sp_weapons_opposing_force_hve/v_sp_elite.mdl";
new const V_HEV_FAMAS[]     = "models/sp_weapons_opposing_force_hve/v_sp_famas.mdl";
new const V_HEV_FIVESEVEN[] = "models/sp_weapons_opposing_force_hve/v_sp_fiveseven.mdl";
new const V_HEV_GALIL[]     = "models/sp_weapons_opposing_force_hve/v_sp_galil.mdl";
new const V_HEV_MAC10[]     = "models/sp_weapons_opposing_force_hve/v_sp_mac10.mdl";
new const V_HEV_P90[]       = "models/sp_weapons_opposing_force_hve/v_sp_p90.mdl";
new const V_HEV_SCOUT[]     = "models/sp_weapons_opposing_force_hve/v_sp_scout.mdl";
new const V_HEV_TMP[]       = "models/sp_weapons_opposing_force_hve/v_sp_tmp.mdl";
new const V_HEV_UMP45[]     = "models/sp_weapons_opposing_force_hve/v_sp_ump45.mdl";
new const V_HEV_AWP[]       = "models/sp_weapons_opposing_force_hve/v_sp_awp.mdl";

// Grenades
new const V_HEV_HEGREN[]    = "models/sp_grenade_hev/v_sp_hegrenade.mdl";
new const V_HEV_SMOKEGREN[] = "models/sp_grenade_hev/v_sp_grenades_flare.mdl";
new const V_HEV_FLASHBANG[] = "models/sp_grenade_hev/v_sp_grenades_frost.mdl";

// Wrench
new const V_HEV_WRENCH[]    = "models/hev_weapons/v_wrench.mdl";
new const P_HEV_WRENCH[]    = "models/hev_weapons/p_wrench.mdl";

// p_ grenade models
new const P_HEV_HEGREN[]    = "models/hev_weapons/p_napalm_grenade.mdl";
new const P_HEV_SMOKEGREN[] = "models/hev_weapons/p_flare_grenade.mdl";
new const P_HEV_FLASHBANG[] = "models/hev_weapons/p_frost_grenade.mdl";

new const HEV_HEAD_MDL[] = "models/hev_head.mdl";

// Wrench sounds
new const SND_WRENCH_DEPLOY[]  = "weapons/wrench_deploy.wav";
new const SND_WRENCH_HIT[]     = "weapons/wrench_hit.wav";
new const SND_WRENCH_HITWALL[] = "weapons/wrench_hitwall.wav";
new const SND_WRENCH_SLASH[]   = "weapons/wrench_slash.wav";
new const SND_WRENCH_STAB[]    = "weapons/wrench_stab.wav";

// HEV Zombie corrupted FVOX
new const SND_ZHV_DAMAGE[]    = "sp_hev_zombie/sp_fvox/sp_hev_damage.wav";
new const SND_ZHV_BLOODLOSS[] = "sp_hev_zombie/sp_fvox/sp_blood_loss.wav";
new const SND_ZHV_WARNING[]   = "sp_hev_zombie/sp_fvox/sp_warning.wav";
new const SND_ZHV_CRITICAL[]  = "sp_hev_zombie/sp_fvox/sp_hev_critical_fail.wav";
new const SND_ZHV_SHUTDOWN[]  = "sp_hev_zombie/sp_fvox/sp_hev_shutdown.wav";
new const SND_ZHV_ACQUIRED[]  = "sp_hev_zombie/sp_fvox/sp_acquired.wav";
new const SND_ZHV_HEAT[]      = "sp_hev_zombie/sp_fvox/sp_heat_damage.wav";
new const SND_ZHV_POWER_LOW[] = "sp_hev_zombie/sp_fvox/sp_power_below.wav";
new const SND_ZHV_FIFTEEN[]   = "sp_hev_zombie/sp_fvox/sp_fifteen.wav";
new const SND_ZHV_SHOCK[]     = "sp_hev_zombie/sp_fvox/sp_shock_damage.wav";

// Integrated item sounds
new const SND_BATTERY_ACTIVATED[] = "sp_armor_hev/sp_armor_activated.wav";
new const SND_BATTERY_FULL[]      = "sp_armor_hev/sp_armor_is.wav";
new const SND_BATTERY_HUNDRED[]   = "sp_hev_zombie/sp_fvox/sp_onehundred.wav";
new const SND_MEDKIT_GET[]        = "fvox/get_medkit.wav";
new const SND_MEDKIT_FULL[]       = "fvox/health_is.wav";
new const SND_MEDKIT_HUNDRED[]    = "fvox/onehundred.wav";

// System FVOX sounds
new const SOUND_HEV_LOGON[]         = "fvox/hev_logon.wav";
new const SOUND_VITALSIGNS[]        = "fvox/vitalsigns_on.wav";
new const SOUND_ATMOSPHERICS[]      = "fvox/atmospherics_on.wav";
new const SOUND_AUTOMEDIC[]         = "fvox/automedic_on.wav";
new const SOUND_SAFE_DAY[]          = "fvox/safe_day.wav";
new const SOUND_HEALTH_CRITICAL[]   = "fvox/health_critical.wav";
new const SOUND_NEAR_DEATH[]        = "fvox/near_death.wav";
new const SOUND_ARMOR_COMPROMISED[] = "fvox/armor_compromised.wav";
new const SOUND_ARMOR_GONE[]        = "fvox/armor_gone.wav";
new const SOUND_MINOR_FRACTURE[]    = "fvox/minor_fracture.wav";
new const SOUND_MAJOR_FRACTURE[]    = "fvox/major_fracture.wav";
new const SOUND_HEAT_DAMAGE[]       = "fvox/heat_damage.wav";
new const SOUND_MINOR_LACERATION[]  = "fvox/minor_lacerations.wav";
new const SOUND_MAJOR_LACERATION[]  = "fvox/major_lacerations.wav";
new const SOUND_BLOOD_TOXINS[]      = "fvox/blood_toxins.wav";
new const SOUND_BIOHAZARD[]         = "fvox/biohazard_detected.wav";
new const SOUND_SHOCK_DAMAGE[]      = "fvox/shock_damage.wav";
new const SOUND_MORPHINE_SHOT[]     = "fvox/morphine_shot.wav";
new const SOUND_FLATLINE[]          = "fvox/flatline.wav";
new const SOUND_POWER_RESTORED[]    = "fvox/power_restored.wav";
new const SOUND_WARNING[]           = "fvox/warning.wav";
new const SOUND_HEALTH_DROPPING[]   = "fvox/health_dropping.wav";
new const SOUND_MORPHINE_ADMIN[]    = "fvox/administer_medical.wav";
new const SOUND_ADRENALINE_SHOT[]   = "fvox/adrenaline_shot.wav";
new const SOUND_BLEEDING_STOPPED[]  = "fvox/bleeding_stopped.wav";
new const SOUND_ZP_INFECTED[]       = "zombie_plague/hev_player_infected.wav";
new const SOUND_LONG_JUMP[]         = "sp_long_jump_hev/sp_long_jump_hev.wav";
new const SOUND_ACCESS_DENIED[]     = "zombie_plague/access_denied.wav";
new const SOUND_FAILURE[]           = "items/failure.wav";
new const SOUND_MEDSHOT[]           = "items/medshot4.wav";
new const SOUND_RIC_METAL1[]        = "weapons/ric_metal-1.wav";
new const SOUND_RIC_METAL2[]        = "weapons/ric_metal-2.wav";
new const SOUND_GEIGER[]            = "player/geiger1.wav";
new const SOUND_WIND[]              = "ambience/wind1.wav";

// Xen Orb sounds (reuse from displacer)
new const SND_ORB_FIRE[]       = "weapons/displacer_fire.wav";
new const SND_ORB_TELEPORT[]   = "weapons/displacer_teleport.wav";
new const SND_ORB_SELF[]       = "weapons/displacer_self.wav";

// Immersive ambient audio
new const g_HeartbeatSounds[][] = {
    "sp_sound_Immersive/sp_heartbeat1.wav",
    "sp_sound_Immersive/sp_heartbeat2.wav",
    "sp_sound_Immersive/sp_heartbeat3.wav"
};
new const g_BreathingSounds[][] = {
    "sp_sound_Immersive/sp_breathing1.wav",
    "sp_sound_Immersive/sp_breathing2.wav",
    "sp_sound_Immersive/sp_breathing3.wav"
};
new const g_DeathPulseSound[] = "sp_sound_Immersive/sp_death_pulse.wav";

// ============================================================
// PLAYER IMMERSIVE DATA
// ============================================================
enum _:PlayerImmersiveData
{
    bool:IM_HEARTBEAT_ACTIVE,
    bool:IM_BREATHING_ACTIVE,
    bool:IM_BLINK_ACTIVE,
    bool:IM_SYRINGE_USED,
    IM_HEARTBEAT_LEVEL,
    IM_BREATHING_LEVEL,
    Float:IM_LAST_HEALTH,
    IM_PREV_HEALTH_STATE,
    Float:IM_LAST_DIAG_TIME,
    bool:IM_IS_BURNING,
    bool:IM_IS_POISONED,
    bool:IM_IS_BLEEDING,
    IM_BOOT_STEP,
    Float:IM_LAST_ARMOR
};
new g_ImData[MAX_PLAYERS + 1][PlayerImmersiveData];

// ============================================================
// GLOBALS Player state
// ============================================================
new bool:g_bHasHEV[MAX_PLAYERS + 1];
new bool:g_bIsHEVZombie[MAX_PLAYERS + 1];
new bool:g_bBoughtThisRound[MAX_PLAYERS + 1];
new bool:g_bMorphineUsed[MAX_PLAYERS + 1];
new bool:g_bArmorBoostUsed[MAX_PLAYERS + 1];
new bool:g_bIsInjecting[MAX_PLAYERS + 1];
new bool:g_bCriticalPlayed[MAX_PLAYERS + 1];
new bool:g_bHevIconShown[MAX_PLAYERS + 1];
new bool:g_bArmorWarned50[MAX_PLAYERS + 1];
new bool:g_bArmorWarnedGone[MAX_PLAYERS + 1];
new bool:g_bZombieLoopCritical[MAX_PLAYERS + 1];

new g_iSuitPower[MAX_PLAYERS + 1];
new g_iRegenCounter[MAX_PLAYERS + 1];
new g_ent_playermodel[MAX_PLAYERS + 1];
new Float:g_fLastDamageTime[MAX_PLAYERS + 1];
new Float:g_fLastFlashTime[MAX_PLAYERS + 1];
new Float:g_fLastFirewall[MAX_PLAYERS + 1];
new Float:g_fLastEMPSound[MAX_PLAYERS + 1];
new Float:g_MeltdownOrigin[MAX_PLAYERS + 1][3];
new Float:g_fLastLongJump[MAX_PLAYERS + 1];

new g_iRepulsorUses[MAX_PLAYERS + 1];
new g_iLightningSprite;

// Integrated items
new g_iBatteryBought[MAX_PLAYERS + 1];
new g_iMedKitBought[MAX_PLAYERS + 1];

// HP Regeneration system
new bool:g_bHpRegening[MAX_PLAYERS + 1];     // Is HP regen currently ticking?
new bool:g_bHpRecentDamage[MAX_PLAYERS + 1]; // Is damage cooldown running?

// Xen Displacement Orb
new Float:g_fOrbCooldown[MAX_PLAYERS + 1]; // gametime of last fire
new g_iOrbEnt[MAX_PLAYERS + 1];           // orb entity per zombie

// Death Portal
new g_iPortalEnt[MAX_PLAYERS + 1];        // portal entity per dead zombie

// ============================================================
// GLOBALS Plugin
// ============================================================
new g_iItemId;
new g_iItemBattery;
new g_iItemMedKit;
new g_maxPlayers;
new g_msgSyncBoot;
new g_msgSyncArmor;       // HUD sync for custom armor % display
new g_msgSyncHealth;      // HUD sync for custom HP display
new g_msgStatusIcon;
new g_msgScreenFade;
new g_msgBattery;         // Intercepted (no longer needed but kept)
new g_msgHideWeapon;      // Used to hide native health+armor HUD
new g_msgScreenShake;

#define HIDEHUD_HEALTH  (1<<3)    // bit 3 hides both HP bar and armor icon
new g_cvArmor, g_cvHealthBonus, g_cvDamageReduction, g_cvLongJump, g_cvMaxDamage;
new g_CvarEnabled;
new g_cvHudReplace;  // 1 = hide native HP/armor + show custom integrity %, 0 = keep vanilla HUD
new g_hev_total_sold;
new g_hev_bot_sold;
new g_iGreenExplosionSprite;
new g_iPortalSprite;
new g_iRingSprite;

// Forwards
new g_fwHevActivated;
new g_fwHevRemoved;
new g_fwBecameHevZombie;
new g_fwReturn;

// ============================================================
// GLOBALS Extra weapon registry
// ============================================================
new g_ExtraWeaponNames[MAX_WEAPONS][MAX_NAME_LEN];
new g_ExtraWeaponNormalModels[MAX_WEAPONS][MAX_MODEL_LEN];
new g_ExtraWeaponHevModels[MAX_WEAPONS][MAX_MODEL_LEN];
new g_ExtraWeaponCount;

// ============================================================
// GLOBALS DHUD typewriter
// ============================================================
enum _:PlayerTypingData
{
    TypingTarget[128],
    TypingCurrent[128],
    TypingPos,
    TypingX,
    TypingY
}
new g_TypingData[MAX_PLAYERS + 1][PlayerTypingData];

// ============================================================
// plugin_natives - registers sp_hev_suit library
// ============================================================
public plugin_natives()
{
    register_library("sp_hev_suit");
    register_native("sp_has_user_hev",             "native_has_user_hev");
    register_native("sp_is_hev_zombie",            "native_is_hev_zombie");
    register_native("sp_get_hev_power",            "native_get_hev_power");
    register_native("sp_set_extra_viewmodel",      "native_set_extra_viewmodel");
    register_native("sp_register_extra_weapon",    "native_register_extra_weapon");
    register_native("sp_apply_extra_viewmodel",    "native_apply_extra_viewmodel");
    register_native("sp_restore_default_viewmodel","native_restore_default_viewmodel");
}

// ============================================================
// NATIVE IMPLEMENTATIONS
// ============================================================
public native_has_user_hev(plugin, params)
{
    new id = get_param(1);
    if (id < 1 || id > MAX_PLAYERS) return 0;
    return g_bHasHEV[id] ? 1 : 0;
}

public native_is_hev_zombie(plugin, params)
{
    new id = get_param(1);
    if (id < 1 || id > MAX_PLAYERS) return 0;
    return g_bIsHEVZombie[id] ? 1 : 0;
}

public native_get_hev_power(plugin, params)
{
    new id = get_param(1);
    if (id < 1 || id > MAX_PLAYERS) return -1;
    if (!g_bHasHEV[id]) return -1;
    return g_iSuitPower[id];
}

public native_set_extra_viewmodel(plugin, params)
{
    new id = get_param(1);
    if (id < 1 || id > MAX_PLAYERS || !is_user_alive(id)) return -1;
    new normal_model[MAX_MODEL_LEN], hev_model[MAX_MODEL_LEN];
    get_string(2, normal_model, charsmax(normal_model));
    get_string(3, hev_model,   charsmax(hev_model));
    if (g_bHasHEV[id] && !zp_get_user_zombie(id) && strlen(hev_model) > 0)
    {
        set_pev(id, pev_viewmodel2, hev_model);
        return 1;
    }
    if (strlen(normal_model) > 0)
        set_pev(id, pev_viewmodel2, normal_model);
    return 0;
}

public native_register_extra_weapon(plugin, params)
{
    if (g_ExtraWeaponCount >= MAX_WEAPONS) return -1;
    new weapon_name[MAX_NAME_LEN], normal_model[MAX_MODEL_LEN], hev_model[MAX_MODEL_LEN];
    get_string(1, weapon_name,  charsmax(weapon_name));
    get_string(2, normal_model, charsmax(normal_model));
    get_string(3, hev_model,    charsmax(hev_model));
    if (strlen(weapon_name) == 0) return -1;
    new idx = g_ExtraWeaponCount;
    copy(g_ExtraWeaponNames[idx],        charsmax(g_ExtraWeaponNames[]),        weapon_name);
    copy(g_ExtraWeaponNormalModels[idx], charsmax(g_ExtraWeaponNormalModels[]), normal_model);
    copy(g_ExtraWeaponHevModels[idx],    charsmax(g_ExtraWeaponHevModels[]),    hev_model);
    g_ExtraWeaponCount++;
    return idx;
}

public native_apply_extra_viewmodel(plugin, params)
{
    new id = get_param(1);
    if (id < 1 || id > MAX_PLAYERS || !is_user_alive(id)) return -1;
    new weapon_name[MAX_NAME_LEN];
    get_string(2, weapon_name, charsmax(weapon_name));
    for (new i = 0; i < g_ExtraWeaponCount; i++)
    {
        if (!equal(g_ExtraWeaponNames[i], weapon_name)) continue;
        if (g_bHasHEV[id] && !zp_get_user_zombie(id) && strlen(g_ExtraWeaponHevModels[i]) > 0)
            set_pev(id, pev_viewmodel2, g_ExtraWeaponHevModels[i]);
        else if (strlen(g_ExtraWeaponNormalModels[i]) > 0)
            set_pev(id, pev_viewmodel2, g_ExtraWeaponNormalModels[i]);
        return 1;
    }
    return 0;
}

public native_restore_default_viewmodel(plugin, params)
{
    new id = get_param(1);
    if (id < 1 || id > MAX_PLAYERS || !is_user_alive(id)) return 0;
    restore_default_weapon_model(id);
    return 1;
}

// ============================================================
// INI READER
// ============================================================
public plugin_cfg()
{
    new file = fopen(HEV_INI_FILE, "rt");
    if (!file) return;
    new line[256], orig[MAX_MODEL_LEN], hev[MAX_MODEL_LEN];
    while (!feof(file))
    {
        fgets(file, line, charsmax(line));
        trim(line);
        if (line[0] == ';' || line[0] == 0) continue;
        if (parse(line, orig, charsmax(orig), hev, charsmax(hev)) >= 2)
        {
            if (g_IniWeaponCount < MAX_WEAPONS)
            {
                copy(g_IniOriginalModels[g_IniWeaponCount], charsmax(g_IniOriginalModels[]), orig);
                copy(g_IniHEVModels[g_IniWeaponCount],      charsmax(g_IniHEVModels[]),      hev);
                precache_model(hev); // precache at cfg load time
                g_IniWeaponCount++;
            }
        }
    }
    fclose(file);
}

// ============================================================
// PRECACHE
// ============================================================
public plugin_precache()
{
    g_iGreenExplosionSprite = precache_model("sprites/zerogxplode.spr");
    precache_model("sprites/plasma.spr"); // used by orb entity SetModel
    g_iPortalSprite         = precache_model("sprites/exit1.spr");
    g_iRingSprite           = precache_model("sprites/displacer_ring.spr");
    g_iLightningSprite      = precache_model("sprites/lgtning.spr");

    static model_path[128];
    formatex(model_path, charsmax(model_path), "models/player/%s/%s.mdl", HEV_MODEL_SHORT, HEV_MODEL_SHORT);
    precache_model(model_path);
    precache_model(HEV_ZOMBIE_FULL);
    precache_model(V_HEV_MODEL);
    precache_model(V_HEV_ADRENALINE);
    precache_model(V_HEV_ZOMBIE_KNIFE);
    precache_model(g_InjectorV);
    precache_model(g_InjectorP);

    // HEV weapon models
    precache_model(V_HEV_AK47);   precache_model(V_HEV_M4A1);
    precache_model(V_HEV_MP5NAVY);precache_model(V_HEV_DEAGLE);
    precache_model(V_HEV_AUG);    precache_model(V_HEV_M249);
    precache_model(V_HEV_M3);     precache_model(V_HEV_XM1014);
    precache_model(V_HEV_USP);    precache_model(V_HEV_P228);
    precache_model(V_HEV_SG550);  precache_model(V_HEV_G3SG1);
    precache_model(V_HEV_GLOCK18);precache_model(V_HEV_SG552);
    precache_model(V_HEV_ELITE);  precache_model(V_HEV_FAMAS);
    precache_model(V_HEV_FIVESEVEN);precache_model(V_HEV_GALIL);
    precache_model(V_HEV_MAC10);  precache_model(V_HEV_P90);
    precache_model(V_HEV_SCOUT);  precache_model(V_HEV_TMP);
    precache_model(V_HEV_UMP45);  precache_model(V_HEV_AWP);
    precache_model(V_HEV_HEGREN); precache_model(V_HEV_SMOKEGREN);
    precache_model(V_HEV_FLASHBANG);
    precache_model(V_HEV_WRENCH); precache_model(P_HEV_WRENCH);
    precache_model(P_HEV_HEGREN); precache_model(P_HEV_SMOKEGREN);
    precache_model(P_HEV_FLASHBANG);
    precache_model(HEV_HEAD_MDL);

    // Wrench sounds
    precache_sound(SND_WRENCH_DEPLOY);  precache_sound(SND_WRENCH_HIT);
    precache_sound(SND_WRENCH_HITWALL); precache_sound(SND_WRENCH_SLASH);
    precache_sound(SND_WRENCH_STAB);

    // HEV Zombie FVOX sounds
    precache_sound(SND_ZHV_DAMAGE);   precache_sound(SND_ZHV_BLOODLOSS);
    precache_sound(SND_ZHV_WARNING);  precache_sound(SND_ZHV_CRITICAL);
    precache_sound(SND_ZHV_SHUTDOWN); precache_sound(SND_ZHV_ACQUIRED);
    precache_sound(SND_ZHV_HEAT);     precache_sound(SND_ZHV_POWER_LOW);
    precache_sound(SND_ZHV_FIFTEEN);  precache_sound(SND_ZHV_SHOCK);

    // Integrated item sounds
    precache_sound(SND_BATTERY_ACTIVATED); precache_sound(SND_BATTERY_FULL);
    precache_sound(SND_BATTERY_HUNDRED);
    precache_sound(SND_MEDKIT_GET);        precache_sound(SND_MEDKIT_FULL);
    precache_sound(SND_MEDKIT_HUNDRED);

    // Orb sounds
    precache_sound(SND_ORB_FIRE);
    precache_sound(SND_ORB_TELEPORT);
    precache_sound(SND_ORB_SELF);

    // EMP sound
    precache_sound("ambience/port_warn.wav");

    // System FVOX
    precache_sound(SOUND_HEV_LOGON);      precache_sound(SOUND_VITALSIGNS);
    precache_sound(SOUND_ATMOSPHERICS);   precache_sound(SOUND_AUTOMEDIC);
    precache_sound(SOUND_SAFE_DAY);       precache_sound(SOUND_HEALTH_CRITICAL);
    precache_sound(SOUND_NEAR_DEATH);     precache_sound(SOUND_ARMOR_COMPROMISED);
    precache_sound(SOUND_ARMOR_GONE);     precache_sound(SOUND_MINOR_FRACTURE);
    precache_sound(SOUND_MAJOR_FRACTURE); precache_sound(SOUND_HEAT_DAMAGE);
    precache_sound(SOUND_MINOR_LACERATION);precache_sound(SOUND_MAJOR_LACERATION);
    precache_sound(SOUND_BLOOD_TOXINS);   precache_sound(SOUND_BIOHAZARD);
    precache_sound(SOUND_SHOCK_DAMAGE);   precache_sound(SOUND_MORPHINE_SHOT);
    precache_sound(SOUND_FLATLINE);       precache_sound(SOUND_POWER_RESTORED);
    precache_sound(SOUND_WARNING);        precache_sound(SOUND_HEALTH_DROPPING);
    precache_sound(SOUND_MORPHINE_ADMIN); precache_sound(SOUND_ADRENALINE_SHOT);
    precache_sound(SOUND_BLEEDING_STOPPED);precache_sound(SOUND_ZP_INFECTED);
    precache_sound(SOUND_LONG_JUMP);      precache_sound(SOUND_ACCESS_DENIED);
    precache_sound(SOUND_FAILURE);        precache_sound(SOUND_MEDSHOT);
    precache_sound(SOUND_RIC_METAL1);     precache_sound(SOUND_RIC_METAL2);
    precache_sound(SOUND_GEIGER);         precache_sound(SOUND_WIND);
    precache_sound("weapons/electro4.wav");

    // Immersive ambient
    for (new i = 0; i < sizeof(g_HeartbeatSounds); i++)
        precache_sound(g_HeartbeatSounds[i]);
    for (new i = 0; i < sizeof(g_BreathingSounds); i++)
        precache_sound(g_BreathingSounds[i]);
    precache_sound(g_DeathPulseSound);
}

// ============================================================
// AUDIO ENGINE HELPER
// ============================================================
stock play_fvox(id, const sound[])
{
    new pitch;
    if      (g_bIsHEVZombie[id]) pitch = 80;
    else if (g_bHasHEV[id])      pitch = 92;
    else                         pitch = PITCH_NORM;
    emit_sound(id, CHAN_VOICE, sound, 0.9, ATTN_NORM, 0, pitch);
}

// ============================================================
// PLUGIN INIT
// ============================================================
public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    g_iItemId      = zp_register_extra_item(ITEM_NAME,        ITEM_COST,         ZP_TEAM_HUMAN);
    g_iItemBattery = zp_register_extra_item(ITEM_BATTERY_NAME,ITEM_BATTERY_COST, ZP_TEAM_HUMAN);
    g_iItemMedKit  = zp_register_extra_item(ITEM_MEDKIT_NAME, ITEM_MEDKIT_COST,  ZP_TEAM_HUMAN);

    g_cvArmor           = register_cvar("zp_hev_armor",            "85");
    g_cvHealthBonus     = register_cvar("zp_hev_health_bonus",     "0");
    g_cvDamageReduction = register_cvar("zp_hev_damage_reduction", "0");
    g_cvLongJump        = register_cvar("zp_hev_longjump",         "1");
    g_cvMaxDamage       = register_cvar("zp_hev_max_damage",       "65");
    g_CvarEnabled       = register_cvar("immersive_enabled",       "1");
    g_cvHudReplace      = register_cvar("zp_hev_hud_replace",      "1"); // 1=custom integrity HUD, 0=vanilla HP+armor

    RegisterHam(Ham_TakeDamage,  "player", "fw_TakeDamage");
    RegisterHam(Ham_TakeDamage,  "player", "fw_TakeDamage_Diag_Post", 1);
    RegisterHam(Ham_Spawn,       "player", "fw_PlayerSpawn_Post", 1);
    RegisterHam(Ham_Killed,      "player", "fw_PlayerKilled", 1);

    RegisterHam(Ham_TraceAttack, "player", "fw_TraceAttack");

    register_forward(FM_PlayerPostThink, "fw_HEV_PostThink");
    register_forward(FM_PlayerPreThink,  "fw_PlayerPreThink");
    register_forward(FM_Touch,           "fw_TouchHandler");
    register_forward(FM_EmitSound,       "fw_EmitSound");

    register_event("CurWeapon", "Event_CurWeapon",   "be", "1=1");
    register_event("HLTV",      "event_NewRound",    "a",  "1=0", "2=0");
    register_event("Damage",    "event_PlayerDamage","b",  "2>0");
    register_event("Health",    "event_HealthChange","b");

    register_clcmd("drop", "cmd_DropKey");

    new const weapon_list[][] = {
        "weapon_ak47",  "weapon_m4a1",  "weapon_mp5navy",
        "weapon_deagle","weapon_aug",   "weapon_usp",    "weapon_glock18",
        "weapon_m249",  "weapon_m3",    "weapon_xm1014",
        "weapon_p228",  "weapon_sg550", "weapon_g3sg1",  "weapon_sg552",
        "weapon_elite", "weapon_famas", "weapon_fiveseven","weapon_galil",
        "weapon_mac10", "weapon_p90",   "weapon_scout",  "weapon_tmp",
        "weapon_ump45", "weapon_awp",
        "weapon_hegrenade", "weapon_smokegrenade", "weapon_flashbang",
        "weapon_knife"
    };
    for (new i = 0; i < sizeof weapon_list; i++)
        RegisterHam(Ham_Item_Deploy, weapon_list[i], "fw_Weapon_Deploy_Post", 1);

    g_maxPlayers    = get_maxplayers();
    g_msgSyncBoot   = CreateHudSyncObj();
    g_msgSyncArmor  = CreateHudSyncObj();
    g_msgSyncHealth = CreateHudSyncObj();
    g_msgStatusIcon = get_user_msgid("StatusIcon");
    g_msgScreenFade = get_user_msgid("ScreenFade");
    g_msgBattery    = get_user_msgid("Battery");
    g_msgHideWeapon = get_user_msgid("HideWeapon");
    g_msgScreenShake= get_user_msgid("ScreenShake");

    register_message(g_msgBattery, "msg_Battery");

    g_fwHevActivated    = CreateMultiForward("sp_user_hev_activated",     ET_IGNORE, FP_CELL);
    g_fwHevRemoved      = CreateMultiForward("sp_user_hev_removed",       ET_IGNORE, FP_CELL, FP_CELL);
    g_fwBecameHevZombie = CreateMultiForward("sp_user_became_hev_zombie", ET_IGNORE, FP_CELL);

    set_task(1.0, "HEV_MainLoop", _, _, _, "b");
}

// ============================================================
// ZP EXTRA ITEM HANDLER
// ============================================================
public zp_extra_item_selected(id, itemid)
{
    // ── H.E.V Mark IV ───────────────────────────────────────
    if (itemid == g_iItemId)
    {
        if (!zp_has_round_started())
        {
            ColorChat(id, RED, "^1[^4H.E.V^1]: Systems offline...");
            client_cmd(id, "spk %s", SOUND_ACCESS_DENIED);
            return ZP_PLUGIN_HANDLED;
        }
        if (IsBossClass(id) || g_bHasHEV[id] || g_bBoughtThisRound[id])
        {
            ColorChat(id, RED, "^1[^4H.E.V^1]: Already equipped or not available!");
            return ZP_PLUGIN_HANDLED;
        }
        if (g_hev_total_sold >= GLOBAL_HEV_LIMIT)
        {
            ColorChat(id, RED, "^1[^4H.E.V^1]: Global limit ^3[%d/%d]^1 reached!",
                g_hev_total_sold, GLOBAL_HEV_LIMIT);
            client_cmd(id, "spk %s", SOUND_ACCESS_DENIED);
            return ZP_PLUGIN_HANDLED;
        }
        if (is_user_bot(id) && g_hev_bot_sold >= BOT_HEV_LIMIT)
            return ZP_PLUGIN_HANDLED;
        ActivateHEV(id);
        ColorChat(id, RED, "^1[^4H.E.V^1]: Damage Reduction active ^430%%");
        return PLUGIN_CONTINUE;
    }

    // ── H.E.V Armor Battery ──────────────────────────────────
    if (itemid == g_iItemBattery)
    {
        if (!g_bHasHEV[id] || zp_get_user_zombie(id))
        {
            ColorChat(id, RED, "^1[^4H.E.V^1]: No suit detected!");
            client_cmd(id, "spk %s", SOUND_ACCESS_DENIED);
            return ZP_PLUGIN_HANDLED;
        }
        if (g_iBatteryBought[id] >= BATTERY_LIMIT)
        {
            ColorChat(id, RED, "^1[^4H.E.V^1]: Battery limit ^3[%d/%d]^1 reached!",
                g_iBatteryBought[id], BATTERY_LIMIT);
            client_cmd(id, "spk %s", SOUND_ACCESS_DENIED);
            return ZP_PLUGIN_HANDLED;
        }
        new Float:cur_armor;
        pev(id, pev_armorvalue, cur_armor);
        if (cur_armor >= float(BATTERY_ARMOR_MAX))
        {
            ColorChat(id, RED, "^1[^4H.E.V^1]: Armor at ^3MAXIMUM^1!");
            emit_sound(id, CHAN_ITEM, SND_BATTERY_FULL, 0.9, ATTN_NORM, 0, PITCH_NORM);
            return ZP_PLUGIN_HANDLED;
        }
        g_iBatteryBought[id]++;
        new Float:new_armor = floatmin(cur_armor + float(BATTERY_ARMOR_GIVE), float(BATTERY_ARMOR_MAX));
        set_pev(id, pev_armorvalue, new_armor);
        new i_armor = floatround(new_armor);
        if (i_armor >= BATTERY_ARMOR_MAX)
        {
            emit_sound(id, CHAN_ITEM, SND_BATTERY_FULL,    0.9, ATTN_NORM, 0, PITCH_NORM);
            emit_sound(id, CHAN_VOICE,SND_BATTERY_HUNDRED, 0.9, ATTN_NORM, 0, PITCH_NORM);
            ColorChat(id, GREEN, "^1[^4H.E.V^1]: ^4+%d AP^1 applied. Armor: ^4100%% ^3[MAXIMUM]", BATTERY_ARMOR_GIVE);
        }
        else
        {
            emit_sound(id, CHAN_ITEM, SND_BATTERY_ACTIVATED, 0.9, ATTN_NORM, 0, PITCH_NORM);
            ColorChat(id, GREEN, "^1[^4H.E.V^1]: ^4+%d AP^1 applied. Armor: ^4%d^1/^4%d ^1(^4%d^1/^4%d^1 used)",
                BATTERY_ARMOR_GIVE, i_armor, BATTERY_ARMOR_MAX, g_iBatteryBought[id], BATTERY_LIMIT);
        }
        return PLUGIN_CONTINUE;
    }

    // ── H.E.V Medical Kit ────────────────────────────────────
    if (itemid == g_iItemMedKit)
    {
        if (!g_bHasHEV[id] || zp_get_user_zombie(id))
        {
            ColorChat(id, RED, "^1[^4H.E.V^1]: No suit detected!");
            client_cmd(id, "spk %s", SOUND_ACCESS_DENIED);
            return ZP_PLUGIN_HANDLED;
        }
        if (g_iMedKitBought[id] >= HP_KIT_LIMIT)
        {
            ColorChat(id, RED, "^1[^4H.E.V^1]: Medical Kit limit ^3[%d/%d]^1 reached!",
                g_iMedKitBought[id], HP_KIT_LIMIT);
            client_cmd(id, "spk %s", SOUND_ACCESS_DENIED);
            return ZP_PLUGIN_HANDLED;
        }
        new cur_hp = get_user_health(id);
        if (cur_hp >= HP_MAX)
        {
            ColorChat(id, RED, "^1[^4H.E.V^1]: Health at ^3MAXIMUM^1!");
            emit_sound(id, CHAN_ITEM, SND_MEDKIT_FULL, 0.9, ATTN_NORM, 0, PITCH_NORM);
            return ZP_PLUGIN_HANDLED;
        }
        g_iMedKitBought[id]++;
        new new_hp = min(cur_hp + HP_GIVE, HP_MAX);
        set_user_health(id, new_hp);
        emit_sound(id, CHAN_ITEM, SND_MEDKIT_GET, 0.9, ATTN_NORM, 0, PITCH_NORM);
        if (new_hp >= HP_MAX)
        {
            emit_sound(id, CHAN_VOICE, SND_MEDKIT_HUNDRED, 0.9, ATTN_NORM, 0, PITCH_NORM);
            ColorChat(id, GREEN, "^1[^4H.E.V^1]: ^4+%d HP^1 injected. Health: ^4255 ^3[MAXIMUM]", HP_GIVE);
        }
        else
        {
            ColorChat(id, GREEN, "^1[^4H.E.V^1]: ^4+%d HP^1 injected. Health: ^4%d^1/^4%d ^1(^4%d^1/^4%d^1 used)",
                HP_GIVE, new_hp, HP_MAX, g_iMedKitBought[id], HP_KIT_LIMIT);
        }
        return PLUGIN_CONTINUE;
    }

    return PLUGIN_CONTINUE;
}

// ============================================================
// ACTIVATE / REMOVE HEV
// ============================================================
ActivateHEV(id)
{
    g_hev_total_sold++;
    if (is_user_bot(id)) g_hev_bot_sold++;

    new name[32];
    get_user_name(id, name, charsmax(name));
    ColorChat(0, BLUE, "^1[^4H.E.V^1]: ^3%s^1 deployed a Suit! ^4[^1%d^4/^1%d^4]",
        name, g_hev_total_sold, GLOBAL_HEV_LIMIT);

    g_bHasHEV[id]           = true;
    g_bBoughtThisRound[id]  = true;
    g_bMorphineUsed[id]     = false;
    g_bArmorBoostUsed[id]   = false;
    g_bIsHEVZombie[id]      = false;
    g_bIsInjecting[id]      = false;
    g_bArmorWarned50[id]    = false;
    g_bArmorWarnedGone[id]  = false;
    g_iSuitPower[id]        = MAX_POWER;
    g_fLastDamageTime[id]   = 0.0;
    g_fLastFirewall[id]     = 0.0;
    g_iRegenCounter[id]     = 0;

    fm_remove_model_ent(id);

    if (is_user_connected(id))
    {
        cs_set_user_model(id, HEV_MODEL_SHORT);
        set_pev(id, pev_viewmodel2, V_HEV_MODEL);
        util_play_weapon_animation(id, HEV_ANIM_SEQ);
        remove_task(id);
        set_task(HEV_ANIM_TIME, "restore_weapon_model", id);
    }

    set_user_health(id, get_user_health(id) + get_pcvar_num(g_cvHealthBonus));
    cs_set_user_armor(id, get_pcvar_num(g_cvArmor), CS_ARMOR_VESTHELM);
    g_ImData[id][IM_LAST_ARMOR] = float(get_pcvar_num(g_cvArmor));

    // Hide native HP + armor HUD replaced by custom HUDs in HEV_MainLoop (only if cvar on)
    if (get_pcvar_num(g_cvHudReplace))
    {
        message_begin(MSG_ONE, g_msgHideWeapon, _, id);
        write_byte(HIDEHUD_HEALTH);
        message_end();
    }

    // Start HP regeneration (+1 HP/s, pauses on damage, resumes 3s after)
    g_bHpRegening[id]     = true;
    g_bHpRecentDamage[id] = false;
    remove_task(id + TASK_HP_REGEN);
    remove_task(id + TASK_HP_COOLDOWN);
    set_task(1.0, "task_hp_regen", id + TASK_HP_REGEN, _, _, "b");

    play_fvox(id, SOUND_HEV_LOGON);
    show_boot_typewriter(id, "H.E.V [Hazardous Environment Suit] Mark IV", -1.0, 0.45);
    start_boot_sequence(id);

    ExecuteForward(g_fwHevActivated, g_fwReturn, id);
}

stock ApplyManualDamage(id, Float:damage, attacker)
{
    new Float:armor, Float:health;
    pev(id, pev_armorvalue, armor);
    pev(id, pev_health, health);

    new Float:hDmg = damage * 0.2;
    new Float:aDmg = damage * 0.4;

    if (armor > 0.0)
    {
        armor  -= aDmg;
        if (armor < 0.0) { hDmg -= armor; armor = 0.0; }
        health -= hDmg;
    }
    else health -= damage;

    set_pev(id, pev_armorvalue, armor);

    if (health <= 0.0)
    {
        if (zp_get_human_count() > 1)
            zp_infect_user(id, attacker);
        else
        {
            set_pev(id, pev_health, 0.0);
            ExecuteHamB(Ham_Killed, id, attacker, 0);
        }
    }
    else
    {
        set_pev(id, pev_health, health);
        CheckSuitSystems(id);
    }
}

public fw_TraceAttack(victim, attacker, Float:damage, Float:direction[3], tracehandle, damagebits)
{
    if (!is_user_alive(victim) || !g_bHasHEV[victim] || zp_get_user_zombie(victim))
        return HAM_IGNORED;
    if (!is_user_connected(attacker) || !zp_get_user_zombie(attacker))
        return HAM_IGNORED;

    new Float:fReduction = float(get_pcvar_num(g_cvDamageReduction)) / 100.0;
    new Float:fMax       = float(get_pcvar_num(g_cvMaxDamage));
    new Float:fFinal     = damage * (1.0 - fReduction);
    if (fFinal > fMax) fFinal = fMax;
    if (fFinal < 0.0)  fFinal = 0.0;

    g_fLastDamageTime[victim] = get_gametime();

    // Pause HP regen on zombie melee every hit resets the 3s cooldown
    g_bHpRegening[victim]     = false;
    g_bHpRecentDamage[victim] = true;
    remove_task(victim + TASK_HP_COOLDOWN);
    set_task(3.0, "task_resume_hp_regen", victim + TASK_HP_COOLDOWN);

    ApplyManualDamage(victim, fFinal, attacker);
    emit_sound(victim, CHAN_BODY,
        (random_num(0,1) ? SOUND_RIC_METAL1 : SOUND_RIC_METAL2),
        0.7, ATTN_NORM, 0, PITCH_NORM);

    return HAM_SUPERCEDE;
}

stock zp_remove_hev(id, reason = HEV_REMOVE_MANUAL)
{
    if (!g_bHasHEV[id] && !g_bIsHEVZombie[id]) return;

    g_bHasHEV[id]           = false;
    g_bCriticalPlayed[id]   = false;
    g_bMorphineUsed[id]     = false;
    g_bArmorBoostUsed[id]   = false;
    g_bIsInjecting[id]      = false;
    g_bArmorWarned50[id]    = false;
    g_bArmorWarnedGone[id]  = false;

    stop_immersive_effects(id);
    clear_all_status_icons(id);

    // Restore native HP + armor HUD and clear our custom ones (only if cvar was on)
    if (get_pcvar_num(g_cvHudReplace))
    {
        message_begin(MSG_ONE, g_msgHideWeapon, _, id);
        write_byte(0);
        message_end();
        ClearSyncHud(id, g_msgSyncArmor);
        ClearSyncHud(id, g_msgSyncHealth);
    }

    remove_task(id + TASK_BOOT_SEQ);
    remove_task(id + TASK_TYPING_HUD);
    remove_task(id + TASK_DIAG_CHAIN);
    remove_task(id + TASK_WIND);
    remove_task(id + TASK_WARN_DELAY);

    if (reason != HEV_REMOVE_INFECTION)
    {
        g_bIsHEVZombie[id] = false;
        if (is_user_connected(id))
        {
            cs_reset_user_model(id);
            restore_default_weapon_model(id);
            // Restore movement to engine defaults
            set_pev(id, pev_maxspeed, 250.0);
            set_pev(id, pev_gravity,  1.0);
        }
    }

    fm_remove_model_ent(id);
    remove_task(id);
    remove_task(id + TASK_SAW_FIX);
    remove_task(id + TASK_HP_REGEN);
    remove_task(id + TASK_HP_COOLDOWN);
    g_bHpRegening[id]     = false;
    g_bHpRecentDamage[id] = false;

    ExecuteForward(g_fwHevRemoved, g_fwReturn, id, reason);
}

// ============================================================
// HEV BOOT SEQUENCE
// ============================================================
start_boot_sequence(id)
{
    remove_task(id + TASK_BOOT_SEQ);
    remove_task(id + TASK_TYPING_HUD);
    g_ImData[id][IM_BOOT_STEP] = 0;
    set_task(4.0, "task_boot_step", id + TASK_BOOT_SEQ);
}

public task_boot_step(taskid)
{
    new id = taskid - TASK_BOOT_SEQ;
    if (!is_user_alive(id) || !g_bHasHEV[id] || zp_get_user_zombie(id)) return;

    new step = g_ImData[id][IM_BOOT_STEP];
    switch (step)
    {
        case 0:
        {
            play_fvox(id, SOUND_VITALSIGNS);
            show_boot_typewriter(id, "VITAL SIGN MONITORING: ONLINE", -1.0, 0.45);
            g_ImData[id][IM_BOOT_STEP] = 1;
            set_task(4.0, "task_boot_step", id + TASK_BOOT_SEQ);
        }
        case 1:
        {
            play_fvox(id, SOUND_ATMOSPHERICS);
            show_boot_typewriter(id, "ATMOSPHERIC SENSORS: ACTIVE", -1.0, 0.45);
            g_ImData[id][IM_BOOT_STEP] = 2;
            set_task(4.5, "task_boot_step", id + TASK_BOOT_SEQ);
        }
        case 2:
        {
            play_fvox(id, SOUND_AUTOMEDIC);
            show_boot_typewriter(id, "AUTOMATIC MEDICAL SYSTEM: ENGAGED", -1.0, 0.45);
            g_ImData[id][IM_BOOT_STEP] = 3;
            set_task(4.0, "task_boot_step", id + TASK_BOOT_SEQ); // long audio
        }
        case 3:
        {
            play_fvox(id, SOUND_SAFE_DAY);
            show_boot_typewriter(id, "HAVE A VERY SAFE DAY", -1.0, 0.45);
            g_ImData[id][IM_BOOT_STEP] = 4; // boot complete
        }
    }
}

show_boot_typewriter(id, const message[], Float:x, Float:y)
{
    remove_task(id + TASK_TYPING_HUD);
    copy(g_TypingData[id][TypingTarget], charsmax(g_TypingData[][TypingTarget]), message);
    g_TypingData[id][TypingCurrent][0] = 0;
    g_TypingData[id][TypingPos] = 0;
    g_TypingData[id][TypingX]   = _:x;
    g_TypingData[id][TypingY]   = _:y;
    set_task(HUD_TYPING_SPD, "task_type_boot_hud", id + TASK_TYPING_HUD);
}

public task_type_boot_hud(taskid)
{
    new id = taskid - TASK_TYPING_HUD;
    if (!is_user_connected(id)) return;

    new pos = g_TypingData[id][TypingPos];
    new target[128];
    copy(target, charsmax(target), g_TypingData[id][TypingTarget]);
    new total_len = strlen(target);

    for (new i = 0; i < 2 && pos < total_len; i++, pos++)
    {
        g_TypingData[id][TypingCurrent][pos]   = target[pos];
        g_TypingData[id][TypingCurrent][pos+1] = 0;
        g_TypingData[id][TypingPos]++;
    }

    set_hudmessage(255, 170, 0,
        Float:g_TypingData[id][TypingX], Float:g_TypingData[id][TypingY],
        0, 0.1, 2.0, 0.02, 0.02, -1);
    ShowSyncHudMsg(id, g_msgSyncBoot, g_TypingData[id][TypingCurrent]);

    if (pos < total_len)
        set_task(HUD_TYPING_SPD, "task_type_boot_hud", taskid);
}

// ============================================================
// DAMAGE DIAGNOSIS (FVOX + DHUD)
// ============================================================
stock show_diag_dhud(id, const text[])
{
    set_dhudmessage(255, 140, 0, -1.0, 0.15, 0, 0.0, 2.0, 0.1, 0.1);
    show_dhudmessage(id, text);
}

public fw_TakeDamage_Diag_Post(victim, inflictor, attacker, Float:damage, dmgbits)
{
    if (!is_user_alive(victim) || !get_pcvar_num(g_CvarEnabled))
        return HAM_IGNORED;

    // Allow HEV Zombie diagnosis, block regular zombie
    if (!g_bHasHEV[victim] && !g_bIsHEVZombie[victim])
        return HAM_IGNORED;
    if (zp_get_user_zombie(victim) && !g_bIsHEVZombie[victim])
        return HAM_IGNORED;
    if (IsBossClass(victim)) return HAM_IGNORED;

    new Float:now = get_gametime();
    if ((now - g_ImData[victim][IM_LAST_DIAG_TIME]) < DIAG_COOLDOWN)
        return HAM_IGNORED;

    new Float:health = float(get_user_health(victim));

    // DMG_BLAST HE Grenade / Explosion
    if (dmgbits & DMG_BLAST)
    {
        g_ImData[victim][IM_LAST_DIAG_TIME] = now;
        play_fvox(victim, SOUND_WARNING);
        show_diag_dhud(victim, "[BLAST DAMAGE DETECTED]");
        set_task(1.2, "task_diag_blast_followup", victim + TASK_DIAG_CHAIN);
        return HAM_IGNORED;
    }

    // DMG_NERVEGAS | DMG_POISON
    if ((dmgbits & DMG_NERVEGAS) || (dmgbits & DMG_POISON))
    {
        g_ImData[victim][IM_LAST_DIAG_TIME] = now;
        play_fvox(victim, SOUND_BIOHAZARD);
        show_diag_dhud(victim, "[BIOHAZARD DETECTED]");
        set_task(1.5, "task_diag_biohazard", victim + TASK_DIAG_CHAIN);
        if (!g_ImData[victim][IM_IS_POISONED])
        {
            g_ImData[victim][IM_IS_POISONED] = true;
            update_status_icon(victim, "dmg_poison", STATUSICON_FLASH, 0, 255, 0);
        }
        return HAM_IGNORED;
    }

    if (health > 0.0 && health <= float(HEALTH_CRITICAL))
    {
        g_ImData[victim][IM_LAST_DIAG_TIME] = now;
        play_fvox(victim, SOUND_HEALTH_CRITICAL);
        show_diag_dhud(victim, "[HEALTH CRITICAL]");
        set_task(1.2, "task_diag_near_death", victim + TASK_DIAG_CHAIN);
        return HAM_IGNORED;
    }

    if (dmgbits & DMG_FALL)
    {
        g_ImData[victim][IM_LAST_DIAG_TIME] = now;
        if (damage >= 30.0) { play_fvox(victim, SOUND_MAJOR_FRACTURE); show_diag_dhud(victim, "[MAJOR FRACTURE DETECTED]"); }
        else                { play_fvox(victim, SOUND_MINOR_FRACTURE); show_diag_dhud(victim, "[FRACTURE DETECTED]"); }
        return HAM_IGNORED;
    }

    if (dmgbits & DMG_BURN)
    {
        g_ImData[victim][IM_LAST_DIAG_TIME] = now;
        if (g_bIsHEVZombie[victim])
        {
            emit_sound(victim, CHAN_VOICE, SND_ZHV_HEAT, 0.9, ATTN_NORM, 0, 80);
            show_diag_dhud(victim, "[THERMAL DAMAGE DETECTED]");
        }
        else
        {
            play_fvox(victim, SOUND_HEAT_DAMAGE);
            show_diag_dhud(victim, "[HEAT DAMAGE DETECTED]");
        }
        if (!g_ImData[victim][IM_IS_BURNING])
        {
            g_ImData[victim][IM_IS_BURNING] = true;
            update_status_icon(victim, "dmg_heat", STATUSICON_SHOW, 255, 50, 0);
        }
        return HAM_IGNORED;
    }

    if (dmgbits & DMG_SLASH)
    {
        g_ImData[victim][IM_LAST_DIAG_TIME] = now;
        if (damage >= 40.0) { play_fvox(victim, SOUND_MAJOR_LACERATION); show_diag_dhud(victim, "[MAJOR LACERATION DETECTED]"); }
        else                { play_fvox(victim, SOUND_MINOR_LACERATION); show_diag_dhud(victim, "[LACERATION DETECTED]"); }
        if (!g_ImData[victim][IM_IS_BLEEDING])
        {
            g_ImData[victim][IM_IS_BLEEDING] = true;
            update_status_icon(victim, "dmg_bio", STATUSICON_SHOW, 255, 0, 0);
        }
        return HAM_IGNORED;
    }

    if ((dmgbits & DMG_POISON) || (dmgbits & DMG_NERVEGAS))
    {
        g_ImData[victim][IM_LAST_DIAG_TIME] = now;
        play_fvox(victim, SOUND_BLOOD_TOXINS);
        show_diag_dhud(victim, "[BIOHAZARD DETECTED]");
        set_task(1.5, "task_diag_biohazard", victim + TASK_DIAG_CHAIN);
        if (!g_ImData[victim][IM_IS_POISONED])
        {
            g_ImData[victim][IM_IS_POISONED] = true;
            update_status_icon(victim, "dmg_poison", STATUSICON_FLASH, 0, 255, 0);
        }
        return HAM_IGNORED;
    }

    if (dmgbits & DMG_SHOCK)
    {
        g_ImData[victim][IM_LAST_DIAG_TIME] = now;
        play_fvox(victim, SOUND_SHOCK_DAMAGE);
        show_diag_dhud(victim, "[SHOCK DAMAGE DETECTED]");
        return HAM_IGNORED;
    }

    // Armor status only for human HEV
    if (g_bHasHEV[victim] && !zp_get_user_zombie(victim))
    {
        new Float:armorVal;
        pev(victim, pev_armorvalue, armorVal);
        new Float:maxArmor = float(get_pcvar_num(g_cvArmor));
        if (maxArmor > 0.0)
        {
            if (armorVal <= 0.0 && !g_bArmorWarnedGone[victim])
            {
                g_bArmorWarnedGone[victim] = true;
                g_ImData[victim][IM_LAST_DIAG_TIME] = now;
                play_fvox(victim, SOUND_ARMOR_GONE);
                show_diag_dhud(victim, "[WARNING: ARMOR DEPLETED]");
            }
            else if (armorVal > 0.0 && armorVal <= (maxArmor * 0.5) && !g_bArmorWarned50[victim])
            {
                g_bArmorWarned50[victim] = true;
                g_ImData[victim][IM_LAST_DIAG_TIME] = now;
                play_fvox(victim, SOUND_ARMOR_COMPROMISED);
                show_diag_dhud(victim, "[ARMOR COMPROMISED - 50 Percent]");
            }
        }
    }

    return HAM_IGNORED;
}

public task_diag_blast_followup(taskid)
{
    new id = taskid - TASK_DIAG_CHAIN;
    if (!is_user_alive(id)) return;
    play_fvox(id, SOUND_ARMOR_COMPROMISED);
}

public task_diag_near_death(taskid)
{
    new id = taskid - TASK_DIAG_CHAIN;
    if (!is_user_alive(id)) return;
    play_fvox(id, SOUND_NEAR_DEATH);
}

public task_diag_biohazard(taskid)
{
    new id = taskid - TASK_DIAG_CHAIN;
    if (!is_user_alive(id)) return;
    play_fvox(id, SOUND_BIOHAZARD);
}

public task_warn_delay(taskid)
{
    new id = taskid - TASK_WARN_DELAY;
    if (!is_user_alive(id)) return;
    play_fvox(id, SOUND_WARNING);
}

// ============================================================
// HUD STATUS ICONS
// ============================================================
stock update_status_icon(id, const sprite[], status, r, g, b)
{
    message_begin(MSG_ONE, g_msgStatusIcon, _, id);
    write_byte(status);
    write_string(sprite);
    if (status != STATUSICON_HIDE)
    {
        write_byte(r); write_byte(g); write_byte(b);
    }
    message_end();
}

clear_all_status_icons(id)
{
    if (g_ImData[id][IM_IS_BURNING])   { g_ImData[id][IM_IS_BURNING]  = false; update_status_icon(id, "dmg_heat",   STATUSICON_HIDE, 0, 0, 0); }
    if (g_ImData[id][IM_IS_POISONED])  { g_ImData[id][IM_IS_POISONED] = false; update_status_icon(id, "dmg_poison", STATUSICON_HIDE, 0, 0, 0); }
    if (g_ImData[id][IM_IS_BLEEDING])  { g_ImData[id][IM_IS_BLEEDING] = false; update_status_icon(id, "dmg_bio",    STATUSICON_HIDE, 0, 0, 0); }
    if (g_bHevIconShown[id])
    {
        g_bHevIconShown[id] = false;
        message_begin(MSG_ONE, g_msgStatusIcon, {0,0,0}, id);
        write_byte(STATUSICON_HIDE); write_string("item_battery");
        write_byte(0); write_byte(0); write_byte(0);
        message_end();
    }
}

// ============================================================
// BATTERY MESSAGE INTERCEPT
// ============================================================
public msg_Battery(msg_id, msg_dest, msg_entity)
{
    if (!get_pcvar_num(g_cvHudReplace))
        return PLUGIN_CONTINUE;

    if (!g_bHasHEV[msg_entity] || zp_get_user_zombie(msg_entity))
        return PLUGIN_CONTINUE;

    // Overwrite arg 1 (the armor short) with 0 client HUD shows nothing
    // -1 forces CHudBattery to skip drawing entirely (icon + number both gone)
    set_msg_arg_int(1, ARG_SHORT, -1);
    return PLUGIN_CONTINUE;
}

// ============================================================
// IMMERSIVE HEALTH EFFECTS
// ============================================================
handle_immersive_health(id, Float:health)
{
    if (health <= 0.0 || zp_get_user_zombie(id) || IsBossClass(id)) return;
    if (!get_pcvar_num(g_CvarEnabled)) return;
    stop_immersive_effects(id);
    new prev = g_ImData[id][IM_PREV_HEALTH_STATE];
    if (prev <= HEALTH_CRITICAL && floatround(health) > HEALTH_CRITICAL) show_healing_effects(id);
    g_ImData[id][IM_PREV_HEALTH_STATE] = floatround(health);
    if      (health <= float(HEALTH_CRITICAL)) start_critical_effects(id);
    else if (health <= float(HEALTH_LOW))      start_low_health_effects(id);
    else if (health <= float(HEALTH_MEDIUM))   start_medium_health_effects(id);
}

start_critical_effects(id)
{
    g_ImData[id][IM_HEARTBEAT_LEVEL]  = 2;
    g_ImData[id][IM_HEARTBEAT_ACTIVE] = true;
    set_task(HEARTBEAT_FAST,   "task_heartbeat",    id + TASK_HEARTBEAT,    _, _, "b");
    g_ImData[id][IM_BREATHING_LEVEL]  = 2;
    g_ImData[id][IM_BREATHING_ACTIVE] = true;
    set_task(BREATHING_FAST,   "task_breathing",    id + TASK_BREATHING,    _, _, "b");
    g_ImData[id][IM_BLINK_ACTIVE] = true;
    set_task(random_float(0.8, 2.0), "task_blink_effect", id + TASK_BLINK_EFFECT);
}

start_low_health_effects(id)
{
    g_ImData[id][IM_HEARTBEAT_LEVEL]  = 1;
    g_ImData[id][IM_HEARTBEAT_ACTIVE] = true;
    set_task(HEARTBEAT_MEDIUM, "task_heartbeat", id + TASK_HEARTBEAT, _, _, "b");
    g_ImData[id][IM_BREATHING_LEVEL]  = 1;
    g_ImData[id][IM_BREATHING_ACTIVE] = true;
    set_task(BREATHING_MEDIUM, "task_breathing", id + TASK_BREATHING, _, _, "b");
}

start_medium_health_effects(id)
{
    g_ImData[id][IM_HEARTBEAT_LEVEL]  = 0;
    g_ImData[id][IM_HEARTBEAT_ACTIVE] = true;
    set_task(HEARTBEAT_SLOW,   "task_heartbeat", id + TASK_HEARTBEAT, _, _, "b");
    g_ImData[id][IM_BREATHING_LEVEL]  = 0;
    g_ImData[id][IM_BREATHING_ACTIVE] = true;
    set_task(BREATHING_SLOW,   "task_breathing", id + TASK_BREATHING, _, _, "b");
}

public task_heartbeat(taskid)
{
    new id = taskid - TASK_HEARTBEAT;
    if (!is_user_alive(id) || !g_ImData[id][IM_HEARTBEAT_ACTIVE] || zp_get_user_zombie(id))
    { remove_task(taskid); return; }
    new level = clamp(g_ImData[id][IM_HEARTBEAT_LEVEL], 0, 2);
    emit_sound(id, CHAN_BODY, g_HeartbeatSounds[level], 0.7, ATTN_NORM, 0, PITCH_NORM);
}

public task_breathing(taskid)
{
    new id = taskid - TASK_BREATHING;
    if (!is_user_alive(id) || !g_ImData[id][IM_BREATHING_ACTIVE]) { remove_task(taskid); return; }
    new level = clamp(g_ImData[id][IM_BREATHING_LEVEL], 0, 2);
    new Float:vol = g_bHasHEV[id] ? 0.35 : 0.5;
    new pitch = g_bHasHEV[id] ? 85 : PITCH_NORM;
    emit_sound(id, CHAN_VOICE, g_BreathingSounds[level], vol, ATTN_NORM, 0, pitch);
}

public task_blink_effect(taskid)
{
    new id = taskid - TASK_BLINK_EFFECT;
    if (!is_user_alive(id) || !g_ImData[id][IM_BLINK_ACTIVE]) return;
    create_screen_fade(id, FADE_DURATION / 2, FADE_DURATION / 4, FADE_IN, 255, 120, 0, 120);
    if (g_ImData[id][IM_BLINK_ACTIVE])
        set_task(random_float(0.8, 2.0), "task_blink_effect", id + TASK_BLINK_EFFECT);
}

show_healing_effects(id)
{
    create_screen_fade(id, FADE_DURATION / 2, FADE_DURATION / 8, FADE_STAYOUT, 0, 255, 0, 100);
    emit_sound(id, CHAN_ITEM, SOUND_MEDSHOT, 0.8, ATTN_NORM, 0, PITCH_NORM);
    set_pev(id, pev_rendermode,  kRenderNormal);
    set_pev(id, pev_renderfx,    kRenderFxGlowShell);
    set_pev(id, pev_rendercolor, {255.0, 20.0, 147.0});
    set_pev(id, pev_renderamt,   25.0);
    set_task(2.0, "task_remove_heal_glow", id + TASK_HEAL_GLOW);
    if (g_bHasHEV[id]) play_fvox(id, SOUND_BLEEDING_STOPPED);
}

stop_immersive_effects(id)
{
    remove_task(id + TASK_HEARTBEAT);
    remove_task(id + TASK_BREATHING);
    remove_task(id + TASK_BLINK_EFFECT);
    remove_task(id + TASK_WIND);
    remove_task(id + TASK_WARN_DELAY);
    g_ImData[id][IM_HEARTBEAT_ACTIVE] = false;
    g_ImData[id][IM_BREATHING_ACTIVE] = false;
    g_ImData[id][IM_BLINK_ACTIVE]     = false;
}

public task_remove_heal_glow(taskid)
{
    new id = taskid - TASK_HEAL_GLOW;
    if (!is_user_connected(id)) return;
    set_pev(id, pev_rendermode, kRenderNormal);
    set_pev(id, pev_renderfx,   kRenderFxNone);
}

public task_remove_pink_glow(taskid)
{
    new id = taskid - TASK_PINK_GLOW;
    if (!is_user_connected(id)) return;
    set_pev(id, pev_rendermode, kRenderNormal);
    set_pev(id, pev_renderfx,   kRenderFxNone);
}

// ============================================================
// IMMERSIVE DATA RESET
// ============================================================
reset_immersive_data(id)
{
    g_ImData[id][IM_HEARTBEAT_ACTIVE]  = false;
    g_ImData[id][IM_BREATHING_ACTIVE]  = false;
    g_ImData[id][IM_BLINK_ACTIVE]      = false;
    g_ImData[id][IM_SYRINGE_USED]      = false;
    g_ImData[id][IM_HEARTBEAT_LEVEL]   = 0;
    g_ImData[id][IM_BREATHING_LEVEL]   = 0;
    g_ImData[id][IM_LAST_HEALTH]       = 100.0;
    g_ImData[id][IM_PREV_HEALTH_STATE] = 100;
    g_ImData[id][IM_LAST_DIAG_TIME]    = 0.0;
    g_ImData[id][IM_IS_BURNING]        = false;
    g_ImData[id][IM_IS_POISONED]       = false;
    g_ImData[id][IM_IS_BLEEDING]       = false;
    g_ImData[id][IM_BOOT_STEP]         = 0;
    g_ImData[id][IM_LAST_ARMOR]        = 0.0;
    g_bZombieLoopCritical[id]          = false;
    g_iRegenCounter[id]                = 0;
    g_fLastEMPSound[id]                = 0.0;
    g_fOrbCooldown[id]                 = 0.0;
    g_iOrbEnt[id]                      = 0;
    g_iRepulsorUses[id]                = 0;
    g_fLastLongJump[id]                = 0.0;
}

// ============================================================
// WEAPON MODEL HELPERS
// ============================================================
public restore_weapon_model(taskid)
{
    new id = (taskid > MAX_PLAYERS) ? (taskid - TASK_SAW_FIX) : taskid;
    if (!is_user_alive(id) || zp_get_user_zombie(id)) return;
    if (g_bIsInjecting[id]) return;
    set_hev_weapon_model(id, get_user_weapon(id));
}

stock set_hev_weapon_model(id, iWpn)
{
    if (!is_user_alive(id) || !g_bHasHEV[id] || zp_get_user_zombie(id)) return;
    if (g_bIsInjecting[id]) return;

    static current_model[128];
    pev(id, pev_viewmodel2, current_model, charsmax(current_model));

    // Guard: keep equip animation running
    if (equal(current_model, V_HEV_MODEL)) return;

    // INI override Extra Items compatibility
    for (new k = 0; k < g_IniWeaponCount; k++)
    {
        if (equal(current_model, g_IniOriginalModels[k]))
        {
            set_pev(id, pev_viewmodel2, g_IniHEVModels[k]);
            return;
        }
    }

    // p_ models
    switch (iWpn)
    {
        case CSW_KNIFE:       set_pev(id, pev_weaponmodel2, P_HEV_WRENCH);
        case CSW_HEGRENADE:   set_pev(id, pev_weaponmodel2, P_HEV_HEGREN);
        case CSW_SMOKEGRENADE:set_pev(id, pev_weaponmodel2, P_HEV_SMOKEGREN);
        case CSW_FLASHBANG:   set_pev(id, pev_weaponmodel2, P_HEV_FLASHBANG);
    }

    // v_ HEV models
    switch (iWpn)
    {
        case CSW_AK47:         set_pev(id, pev_viewmodel2, V_HEV_AK47);
        case CSW_M4A1:         set_pev(id, pev_viewmodel2, V_HEV_M4A1);
        case CSW_DEAGLE:       set_pev(id, pev_viewmodel2, V_HEV_DEAGLE);
        case CSW_AUG:          set_pev(id, pev_viewmodel2, V_HEV_AUG);
        case CSW_M3:           set_pev(id, pev_viewmodel2, V_HEV_M3);
        case CSW_XM1014:       set_pev(id, pev_viewmodel2, V_HEV_XM1014);
        case CSW_G3SG1:        set_pev(id, pev_viewmodel2, V_HEV_G3SG1);
        case CSW_SG552:        set_pev(id, pev_viewmodel2, V_HEV_SG552);
        case CSW_GLOCK18:      set_pev(id, pev_viewmodel2, V_HEV_GLOCK18);
        case CSW_HEGRENADE:    set_pev(id, pev_viewmodel2, V_HEV_HEGREN);
        case CSW_SMOKEGRENADE: set_pev(id, pev_viewmodel2, V_HEV_SMOKEGREN);
        case CSW_FLASHBANG:    set_pev(id, pev_viewmodel2, V_HEV_FLASHBANG);
        case CSW_P228:         set_pev(id, pev_viewmodel2, V_HEV_P228);
        case CSW_SG550:        set_pev(id, pev_viewmodel2, V_HEV_SG550);
        case CSW_MP5NAVY:      set_pev(id, pev_viewmodel2, V_HEV_MP5NAVY);
        case CSW_USP:          set_pev(id, pev_viewmodel2, V_HEV_USP);
        case CSW_ELITE:        set_pev(id, pev_viewmodel2, V_HEV_ELITE);
        case CSW_FAMAS:        set_pev(id, pev_viewmodel2, V_HEV_FAMAS);
        case CSW_FIVESEVEN:    set_pev(id, pev_viewmodel2, V_HEV_FIVESEVEN);
        case CSW_GALIL:        set_pev(id, pev_viewmodel2, V_HEV_GALIL);
        case CSW_MAC10:        set_pev(id, pev_viewmodel2, V_HEV_MAC10);
        case CSW_P90:          set_pev(id, pev_viewmodel2, V_HEV_P90);
        case CSW_SCOUT:        set_pev(id, pev_viewmodel2, V_HEV_SCOUT);
        case CSW_TMP:          set_pev(id, pev_viewmodel2, V_HEV_TMP);
        case CSW_UMP45:        set_pev(id, pev_viewmodel2, V_HEV_UMP45);
        case CSW_AWP:          set_pev(id, pev_viewmodel2, V_HEV_AWP);
        case CSW_KNIFE:
        {
            if (containi(current_model, "lasermine") != -1) return;
            set_pev(id, pev_viewmodel2, V_HEV_WRENCH);
        }
        case CSW_M249:
        {
            if (containi(current_model, "saw") != -1) set_pev(id, pev_viewmodel2, V_HEV_SAW);
            else                                      set_pev(id, pev_viewmodel2, V_HEV_M249);
        }
    }
}

// ============================================================
// EVENTS & FORWARDS
// ============================================================
public Event_CurWeapon(id)
{
    if (!is_user_alive(id)) return;

    // HEV Zombie: force zombie knife
    if (g_bIsHEVZombie[id] && get_user_weapon(id) == CSW_KNIFE)
    {
        set_pev(id, pev_viewmodel2, V_HEV_ZOMBIE_KNIFE);
        return;
    }

    if (!g_bHasHEV[id] || zp_get_user_zombie(id)) return;
    if (g_ImData[id][IM_BOOT_STEP] < 4) return; // block during boot
    if (g_bIsInjecting[id]) return;

    static current_model[64];
    pev(id, pev_viewmodel2, current_model, charsmax(current_model));

    if (get_user_weapon(id) == CSW_M249)
    {
        remove_task(id + TASK_SAW_FIX);
        set_task(0.2, "restore_weapon_model", id + TASK_SAW_FIX);
    }
    else if (containi(current_model, "sp_weapons_opposing_force_hve") == -1 &&
             containi(current_model, "sp_grenade_hev")                == -1 &&
             containi(current_model, "hev_weapons")                   == -1)
    {
        set_hev_weapon_model(id, get_user_weapon(id));
    }
}

public fw_Weapon_Deploy_Post(ent)
{
    if (!pev_valid(ent)) return HAM_IGNORED;

    static id;
    id = get_pdata_cbase(ent, 41, 4);

    // HEV Zombie: force zombie knife
    if (g_bIsHEVZombie[id] && get_user_weapon(id) == CSW_KNIFE)
    {
        set_pev(id, pev_viewmodel2, V_HEV_ZOMBIE_KNIFE);
        return HAM_IGNORED;
    }

    if (!is_user_alive(id) || zp_get_user_zombie(id)) return HAM_IGNORED;
    if (g_ImData[id][IM_BOOT_STEP] < 4) return HAM_IGNORED;

    if (g_bHasHEV[id])
    {
        if (g_bIsInjecting[id]) return HAM_IGNORED;
        remove_task(id);
        set_task(0.2, "restore_weapon_model", id);
    }
    return HAM_IGNORED;
}

public zp_user_unfrozen(id)
{
    if (is_user_alive(id) && zp_get_user_zombie(id) && g_bIsHEVZombie[id])
    {
        cs_set_user_model(id, HEV_ZOMBIE_SHORT);
        if (get_user_weapon(id) == CSW_KNIFE)
            set_pev(id, pev_viewmodel2, V_HEV_ZOMBIE_KNIFE);
    }
}

// ZP Freeze forward 
public zp_user_frozen(id)
{
    if (!g_bIsHEVZombie[id] && !g_bHasHEV[id]) return;
    new pitch = g_bIsHEVZombie[id] ? 80 : 92;
    emit_sound(id, CHAN_VOICE, SND_ZHV_POWER_LOW, 0.9, ATTN_NORM, 0, pitch);
    set_task(1.5, "task_zhv_frozen_followup", id);
}

public task_zhv_frozen_followup(id)
{
    if (!is_user_connected(id)) return;
    new pitch = g_bIsHEVZombie[id] ? 80 : 92;
    emit_sound(id, CHAN_VOICE, SND_ZHV_FIFTEEN, 0.9, ATTN_NORM, 0, pitch);
}

// ============================================================
// HEV MAIN LOOP (1s tick)
// ============================================================
public HEV_MainLoop()
{
    static Float:fCurrentTime;
    fCurrentTime = get_gametime();

    for (new i = 1; i <= g_maxPlayers; i++)
    {
        if (!is_user_connected(i)) { g_bHevIconShown[i] = false; continue; }
        if (!is_user_alive(i)) continue;

        // ── HEV ZOMBIE: Critical Loop Sound ──────────────────
        if (g_bIsHEVZombie[i] && zp_get_user_zombie(i))
        {
            new hp_z  = get_user_health(i);
            new max_z = 3000; // default ZP zombie HP adjust if your server differs
            if (max_z > 0 && hp_z <= floatround(float(max_z) * 0.15))
            {
                if (!g_bZombieLoopCritical[i])
                {
                    g_bZombieLoopCritical[i] = true;
                    emit_sound(i, CHAN_STATIC, SND_ZHV_CRITICAL, 0.8, ATTN_NORM, 0, 75);
                }
            }
            else g_bZombieLoopCritical[i] = false;
            continue;
        }

        // ── Auto-clear status icons at higher HP ─────────────
        if (g_bHasHEV[i] && !zp_get_user_zombie(i))
        {
            new hp = get_user_health(i);
            if (hp > HEALTH_LOW && g_ImData[i][IM_IS_BLEEDING])
                { g_ImData[i][IM_IS_BLEEDING] = false; update_status_icon(i, "dmg_bio", STATUSICON_HIDE, 0, 0, 0); }
            if (hp > HEALTH_MEDIUM)
            {
                if (g_ImData[i][IM_IS_BURNING])  { g_ImData[i][IM_IS_BURNING]  = false; update_status_icon(i, "dmg_heat",   STATUSICON_HIDE, 0, 0, 0); }
                if (g_ImData[i][IM_IS_POISONED]) { g_ImData[i][IM_IS_POISONED] = false; update_status_icon(i, "dmg_poison", STATUSICON_HIDE, 0, 0, 0); }
            }
        }

        new bool:bShow = (g_bHasHEV[i] && !IsBossClass(i) && !zp_get_user_zombie(i));

        // Battery icon
        if (bShow && !g_bHevIconShown[i])
        {
            message_begin(MSG_ONE, g_msgStatusIcon, {0,0,0}, i);
            write_byte(STATUSICON_SHOW); write_string("item_battery");
            write_byte(255); write_byte(170); write_byte(0);
            message_end();
            g_bHevIconShown[i] = true;
        }
        else if (!bShow && g_bHevIconShown[i])
        {
            message_begin(MSG_ONE, g_msgStatusIcon, {0,0,0}, i);
            write_byte(STATUSICON_HIDE); write_string("item_battery");
            write_byte(0); write_byte(0); write_byte(0);
            message_end();
            // Clear custom armor HUD when suit is off
            if (get_pcvar_num(g_cvHudReplace))
            {
                set_hudmessage(0, 0, 0, -1.0, 0.75, 0, 0.0, 0.01, 0.0, 0.0, -1);
                ShowSyncHudMsg(i, g_msgSyncArmor, "");
            }
            g_bHevIconShown[i] = false;
        }

        if (!bShow) continue;

        // Combined INTEGRITY HUD (HP + Armor) / 200 * 100 only shown if cvar on
        if (get_pcvar_num(g_cvHudReplace))
        {
            new Float:ap;
            pev(i, pev_armorvalue, ap);
            new apInt = floatround(ap);
            if (apInt < 0) apInt = 0;
            if (apInt > 100) apInt = 100;

            new hp = get_user_health(i);
            if (hp < 0) hp = 0;
            if (hp > 100) hp = 100;

            new integrity = (hp + apInt) / 2; // 0-100%

            new r, g, b;
            if      (integrity >= 70) { r = 255; g = 80;   b = 0;  } // green
            else if (integrity >= 40) { r = 200; g = 200;  b = 0;  } // yellow
            else if (integrity >= 20) { r = 200; g = 60;   b = 60; } // red
            else                      { r = 255; g = 0;    b = 0;  } // red

            new Float:xPos = (integrity == 100) ? 0.019 : 0.022;
            set_hudmessage(r, g, b, xPos, 0.40, 0, 0.0, 1.1, 0.05, 0.05, -1);
            ShowSyncHudMsg(i, g_msgSyncArmor, "%d%%", integrity);
        }

        // Suit Power Regen 1 tick every 3 seconds 
        if (g_iSuitPower[i] < MAX_POWER &&
            (fCurrentTime - g_fLastDamageTime[i]) >= RECHARGE_DELAY)
        {
            g_iRegenCounter[i]++;
            if (g_iRegenCounter[i] >= 3)
            {
                g_iRegenCounter[i] = 0;
                g_iSuitPower[i] = min(MAX_POWER, g_iSuitPower[i] + REGEN_TICK);
            }
        }
        else if ((fCurrentTime - g_fLastDamageTime[i]) < RECHARGE_DELAY)
            g_iRegenCounter[i] = 0;

        new hp           = get_user_health(i);
        new Float:health = float(hp);
        new Float:armorVal;
        pev(i, pev_armorvalue, armorVal);
        new Float:maxArmor = float(get_pcvar_num(g_cvArmor));
        if (maxArmor < 1.0) maxArmor = 100.0;

        // ── Get origin (used by EMP + Geiger) ─────────────────
        new Float:myOrigin[3];
        pev(i, pev_origin, myOrigin);

        // ── EMP Interference ──────────────────────────────────
        new bool:bEMPActive = false;
        for (new j = 1; j <= g_maxPlayers; j++)
        {
            if (j == i || !is_user_alive(j) || !g_bIsHEVZombie[j]) continue;
            new Float:zOrig[3];
            pev(j, pev_origin, zOrig);
            if (get_distance_f(myOrigin, zOrig) < 200.0) { bEMPActive = true; break; }
        }

        if (bEMPActive)
        {
            set_dhudmessage(255, 0, 0, -1.0, 0.85, 2, 0.0, 1.1, 0.05, 0.05);
            show_dhudmessage(i, "[ HEV ERROR ] | Integrity: [??????????] ERR Percent | EMP DETECTED");
            set_dhudmessage(255, 0, 0, -1.0, 0.91, 2, 0.0, 1.1, 0.05, 0.05);
            show_dhudmessage(i, "BPM: ??? | Suit Power: ??? Percent");
            if ((fCurrentTime - g_fLastEMPSound[i]) >= 2.0)
            {
                emit_sound(i, CHAN_STATIC, "ambience/port_warn.wav", 0.6, ATTN_NORM, 0, 120);
                g_fLastEMPSound[i] = fCurrentTime;
            }
            continue;
        }

        // ── DHUD Integrity Bar ────────────────────────────────
        new Float:healthPct = (health / 100.0) * 60.0;
        new Float:armorPct  = (armorVal / maxArmor) * 40.0;
        new Float:integrity = healthPct + armorPct;
        if (integrity > 100.0) integrity = 100.0;
        if (integrity <   0.0) integrity = 0.0;
        new integ = floatround(integrity);

        new bar[12];
        new filled = integ / 10;
        for (new b = 0; b < 10; b++) bar[b] = (b < filled) ? '|' : '.';
        bar[10] = 0;

        new status_text[16];
        if      (integ >= 70) copy(status_text, charsmax(status_text), "OPTIMIZED");
        else if (integ >= 35) copy(status_text, charsmax(status_text), "OPERATIONAL");
        else if (integ >= 15) copy(status_text, charsmax(status_text), "CRITICAL");
        else                  copy(status_text, charsmax(status_text), "FAILURE");

        new r, g, b;
        if      (integ >= 70) { r = 255; g = 170; b = 0; }
        else if (integ >= 35) { r = 255; g = 100; b = 0; }
        else                  { r = 255; g = 0;   b = 0; }

        new dhud_text[128];
        if (hp < 15 && random_num(0, 1) == 0)
        {
            formatex(dhud_text, charsmax(dhud_text), "[ERR_0x%04X] SYSTEM MALFUNCTION | INTEGRITY: ????Percent",
                random_num(0, 65535));
            r = 255; g = 0; b = 0;
        }
        else
            formatex(dhud_text, charsmax(dhud_text), "[ HEV Mark IV ] | Integrity: [%s] %d Percent | %s", bar, integ, status_text);

        set_dhudmessage(r, g, b, -1.0, 0.85, 2, 0.0, 1.1, 0.05, 0.05);
        show_dhudmessage(i, dhud_text);

        // BPM + Suit Power
        new Float:vel[3];
        pev(i, pev_velocity, vel);
        new Float:speed = floatsqroot(vel[0]*vel[0] + vel[1]*vel[1] + vel[2]*vel[2]);
        new Float:spd_f = speed / 10.0;
        if (spd_f > 40.0) spd_f = 40.0;
        new bpm = floatround(60.0 + (100.0 - health) * 1.2 + spd_f);

        new bpm_text[64];
        formatex(bpm_text, charsmax(bpm_text), "BPM: %d | Suit Power: %d Percent", bpm, g_iSuitPower[i]);
        set_dhudmessage(r, g, b, -1.0, 0.91, 2, 0.0, 1.1, 0.05, 0.05);
        show_dhudmessage(i, bpm_text);

        // Critical screen flash
        if (hp <= 25 && (fCurrentTime - g_fLastFlashTime[i]) >= 3.0)
        {
            new orange[3];
            orange[0] = 255; orange[1] = 128; orange[2] = 0;
            ScreenFade(i, orange, 0.5, 0.5);
            g_fLastFlashTime[i] = fCurrentTime;
            if (!g_bCriticalPlayed[i])
            {
                play_fvox(i, SOUND_HEALTH_CRITICAL);
                g_bCriticalPlayed[i] = true;
            }
        }
        else if (hp > 25 && g_bCriticalPlayed[i])
            g_bCriticalPlayed[i] = false;

        // Geiger: zombie proximity
        for (new j = 1; j <= g_maxPlayers; j++)
        {
            if (j == i || !is_user_alive(j) || !zp_get_user_zombie(j)) continue;
            new Float:zOrigin[3];
            pev(j, pev_origin, zOrigin);
            if (get_distance_f(myOrigin, zOrigin) <= 300.0)
            {
                emit_sound(i, CHAN_ITEM, SOUND_GEIGER, 0.4, ATTN_NORM, 0, PITCH_NORM);
                break;
            }
        }
    }
}

// ============================================================
// EVENTS (Damage, Health)
// ============================================================
public event_PlayerDamage(id)
{
    if (!is_user_alive(id) || !get_pcvar_num(g_CvarEnabled)) return;
    if (zp_get_user_zombie(id) || IsBossClass(id)) return;

    new Float:current_health = float(get_user_health(id));
    new Float:damage_taken   = g_ImData[id][IM_LAST_HEALTH] - current_health;

    if (damage_taken > 0.0)
    {
        handle_immersive_health(id, current_health);
        if (damage_taken >= 10.0 && g_ImData[id][IM_HEARTBEAT_ACTIVE])
        {
            new level = clamp(g_ImData[id][IM_HEARTBEAT_LEVEL], 0, 2);
            emit_sound(id, CHAN_BODY, g_HeartbeatSounds[level], 0.8, ATTN_NORM, 0, PITCH_NORM);
        }
        if (damage_taken >= 20.0 && current_health < 50.0 && g_bHasHEV[id])
        {
            play_fvox(id, SOUND_HEALTH_DROPPING);
            set_dhudmessage(255, 140, 0, -1.0, 0.15, 0, 0.0, 2.5, 0.1, 0.1);
            show_dhudmessage(id, ">> RAPID HEALTH LOSS DETECTED <<");
            remove_task(id + TASK_WARN_DELAY);
            set_task(1.5, "task_warn_delay", id + TASK_WARN_DELAY);
        }
    }
    g_ImData[id][IM_LAST_HEALTH] = current_health;
}

public event_HealthChange(id)
{
    if (!is_user_alive(id) || !get_pcvar_num(g_CvarEnabled)) return;
    if (zp_get_user_zombie(id)) return;
    new Float:current_health = float(get_user_health(id));
    handle_immersive_health(id, current_health);
    g_ImData[id][IM_LAST_HEALTH] = current_health;
}

public fw_TakeDamage(victim, inflictor, attacker, Float:damage, damageBits)
{
    if (!is_user_alive(victim) || !g_bHasHEV[victim] || zp_get_user_zombie(victim))
        return HAM_IGNORED;

    new Float:now = get_gametime();
    if (damage > 0.0) g_fLastDamageTime[victim] = now;

    // Pause HP regen on any damage - every hit resets the 3s cooldown
    if (damage > 0.0 && g_bHasHEV[victim])
    {
        g_bHpRegening[victim]     = false;
        g_bHpRecentDamage[victim] = true;
        remove_task(victim + TASK_HP_COOLDOWN);
        set_task(3.0, "task_resume_hp_regen", victim + TASK_HP_COOLDOWN);
    }

    // Spit detection
    if (pev_valid(inflictor))
    {
        static szClassname[32];
        pev(inflictor, pev_classname, szClassname, charsmax(szClassname));
        if (equal(szClassname, "spit_projectile"))
        {
            client_cmd(victim, "spk fvox/chemical_detected");
            message_begin(MSG_ONE_UNRELIABLE, get_user_msgid("Damage"), _, victim);
            write_byte(0); write_byte(0); write_long(1<<17);
            write_coord(0); write_coord(0); write_coord(0);
            message_end();
        }
    }

    // Security Firewall
    if (is_user_connected(attacker) && zp_get_user_zombie(attacker))
    {
        if ((now - g_fLastFirewall[victim]) >= 10.0)
        {
            g_fLastFirewall[victim] = now;
            emit_sound(victim, CHAN_ITEM, SOUND_RIC_METAL1, 0.5, ATTN_NORM, 0, 70);
            set_dhudmessage(0, 255, 255, -1.0, 0.25, 0, 0.0, 2.0, 0.1, 0.1);
            show_dhudmessage(victim, "[SECURITY FIREWALL: BREACH BLOCKED]");
            SetHamParamFloat(4, 0.0);
            return HAM_HANDLED;
        }
        // TraceAttack already handled damage
        return HAM_HANDLED;
    }
    return HAM_IGNORED;
}

stock CheckSuitSystems(id)
{
    if (!g_bArmorBoostUsed[id] && get_user_armor(id) <= BOOST_THRES)
    {
        g_bArmorBoostUsed[id] = true;
        cs_set_user_armor(id, BOOST_VALUE, CS_ARMOR_VESTHELM);
        play_fvox(id, SOUND_POWER_RESTORED);
        ScreenFade(id, {255, 255, 0}, 0.5, 0.3);
    }
}

// ============================================================
// LONG JUMP + WIND
// ============================================================
public fw_HEV_PostThink(id)
{
    if (!is_user_alive(id) || !g_bHasHEV[id] || zp_get_user_zombie(id))
        return FMRES_IGNORED;
    if (g_bIsInjecting[id]) return FMRES_IGNORED;

    if (!g_bMorphineUsed[id] && get_user_health(id) <= HP_THRESHOLD)
    {
        ActivateMorphine(id);
        return FMRES_IGNORED;
    }

    static current_model[64];
    pev(id, pev_viewmodel2, current_model, charsmax(current_model));

    if (containi(current_model, "sp_weapons_opposing_force_hve") != -1 ||
        containi(current_model, "sp_grenade_hev")                != -1 ||
        containi(current_model, "hev_weapons")                   != -1)
        return FMRES_IGNORED;

    new iWpn = get_user_weapon(id);
    if (iWpn == CSW_M249)
    {
        if (containi(current_model, "saw") != -1) set_pev(id, pev_viewmodel2, V_HEV_SAW);
        else                                      set_pev(id, pev_viewmodel2, V_HEV_M249);
    }
    else
        set_hev_weapon_model(id, iWpn);

    return FMRES_IGNORED;
}

public fw_PlayerPreThink(id)
{
    if (!is_user_alive(id) || !g_bHasHEV[id] || !get_pcvar_num(g_cvLongJump) || zp_get_user_zombie(id))
        return FMRES_IGNORED;

    // ── HEV Speed & Gravity Penalty ──────────────────────────
    // Applied every frame so nothing overrides it mid-play.
    new iFlags = get_user_flags(id);
    if (iFlags & HEV_ADMIN_FLAG)
    {
        set_pev(id, pev_maxspeed, HEV_SPEED_ADMIN);
        set_pev(id, pev_gravity,  HEV_GRAVITY_ADMIN);
    }
    else if (iFlags & HEV_VIP_FLAG)
    {
        set_pev(id, pev_maxspeed, HEV_SPEED_VIP);
        set_pev(id, pev_gravity,  HEV_GRAVITY_VIP);
    }
    else
    {
        set_pev(id, pev_maxspeed, HEV_SPEED_NORMAL);
        set_pev(id, pev_gravity,  HEV_GRAVITY_NORMAL);
    }
    // ─────────────────────────────────────────────────────────

    static button, oldbutton, flags;
    button    = pev(id, pev_button);
    oldbutton = pev(id, pev_oldbuttons);
    flags     = pev(id, pev_flags);

    if ((button & IN_JUMP) && !(oldbutton & IN_JUMP) && (button & IN_DUCK) && (flags & FL_ONGROUND))
    {
        new Float:now = get_gametime();
        if ((now - g_fLastLongJump[id]) < 5.0)
        {
            new Float:remaining = 5.0 - (now - g_fLastLongJump[id]);
            set_dhudmessage(255, 100, 0, -1.0, 0.70, 0, 0.0, 1.0, 0.05, 0.05);
            show_dhudmessage(id, "[LONG JUMP: Cooldown %.0fs remaining]", remaining);
            return FMRES_IGNORED;
        }
        if (g_iSuitPower[id] >= JUMP_COST)
        {
            g_iSuitPower[id] -= JUMP_COST;
            g_fLastLongJump[id] = now;
            static Float:vel[3];
            velocity_by_aim(id, 500, vel);
            vel[2] = 250.0;
            set_pev(id, pev_velocity, vel);
            emit_sound(id, CHAN_WEAPON, SOUND_LONG_JUMP, 0.8, ATTN_NORM, 0, PITCH_NORM);
            remove_task(id + TASK_WIND);
            set_task(0.3, "task_wind_sound", id + TASK_WIND, _, _, "b");
        }
        else
        {
            set_dhudmessage(255, 100, 0, -1.0, 0.70, 0, 0.0, 1.0, 0.05, 0.05);
            show_dhudmessage(id, "[LONG JUMP: Insufficient Suit Power!]");
        }
    }
    return FMRES_IGNORED;
}

public task_wind_sound(taskid)
{
    new id = taskid - TASK_WIND;
    if (!is_user_alive(id) || !g_bHasHEV[id]) { remove_task(taskid); return; }
    if (pev(id, pev_flags) & FL_ONGROUND)     { remove_task(taskid); return; }
    emit_sound(id, CHAN_ITEM, SOUND_WIND, 0.3, ATTN_NORM, 0, PITCH_NORM);
}

// ============================================================
// AUTO-MORPHINE
// ============================================================
ActivateMorphine(id)
{
    g_bMorphineUsed[id] = true;
    g_bIsInjecting[id]  = true;
    set_pev(id, pev_viewmodel2, V_HEV_ADRENALINE);
    util_play_weapon_animation(id, 0);
    set_user_health(id, HP_BOOST_TO);
    play_fvox(id, SOUND_MORPHINE_SHOT);
    ScreenFade(id, {0, 100, 255}, 0.5, 0.5);
    client_print(id, print_center, "--- EMERGENCY MORPHINE ADMINISTERED ---");
    set_task(ADRENALINE_TIME, "task_end_adrenaline", id);
}

public task_end_adrenaline(id)
{
    if (!is_user_connected(id)) return;
    g_bIsInjecting[id] = false;
    if (is_user_alive(id) && !zp_get_user_zombie(id) && g_bHasHEV[id])
        set_hev_weapon_model(id, get_user_weapon(id));
}

// ============================================================
// ============================================================
// KINETIC REPULSOR (Human HEV - G key with Wrench)
// ============================================================
cmd_KineticRepulsor(id)
{
    if (g_iRepulsorUses[id] >= 2)
    {
        set_dhudmessage(255, 100, 0, -1.0, 0.70, 0, 0.0, 1.0, 0.05, 0.05);
        show_dhudmessage(id, "[KINETIC REPULSOR]: Max uses reached (2/2)!");
        return;
    }
    if (g_iSuitPower[id] < 50)
    {
        set_dhudmessage(255, 100, 0, -1.0, 0.70, 0, 0.0, 1.0, 0.05, 0.05);
        show_dhudmessage(id, "[KINETIC REPULSOR]: Insufficient Suit Power! Need 50.");
        return;
    }

    g_iRepulsorUses[id]++;
    g_iSuitPower[id] -= 50;

    static Float:myOrig[3];
    pev(id, pev_origin, myOrig);

    // TE_BEAMCYLINDER - electric shockwave ring
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMCYLINDER);
    write_coord(floatround(myOrig[0]));
    write_coord(floatround(myOrig[1]));
    write_coord(floatround(myOrig[2]));
    write_coord(floatround(myOrig[0]));
    write_coord(floatround(myOrig[1]));
    write_coord(floatround(myOrig[2]) + 250);
    write_short(g_iLightningSprite);
    write_byte(0);   // startframe
    write_byte(8);   // framerate
    write_byte(4);   // life (0.4s)
    write_byte(25);  // width
    write_byte(10);  // noise
    write_byte(100); write_byte(200); write_byte(255); write_byte(220); // RGBA
    write_byte(200); // speed
    message_end();

    // White/Blue screen flash for the shooter
    message_begin(MSG_ONE_UNRELIABLE, g_msgScreenFade, _, id);
    write_short(FADE_DURATION / 4);
    write_short(FADE_HOLD / 4);
    write_short(FADE_IN);
    write_byte(120); write_byte(180); write_byte(255); write_byte(160);
    message_end();

    // Screen shake for the shooter
    message_begin(MSG_ONE_UNRELIABLE, g_msgScreenShake, _, id);
    write_short(1<<12); // amplitude
    write_short(1<<12); // duration (0.25s in fixed point)
    write_short(1<<13); // frequency
    message_end();

    emit_sound(id, CHAN_WEAPON, "weapons/electro4.wav", 1.0, ATTN_NORM, 0, PITCH_NORM);

    // Knockback all zombies within 200 units
    for (new j = 1; j <= g_maxPlayers; j++)
    {
        if (!is_user_alive(j) || !zp_get_user_zombie(j)) continue;
        new Float:zOrig[3];
        pev(j, pev_origin, zOrig);
        if (get_distance_f(myOrig, zOrig) > 200.0) continue;

        new Float:pushDir[3];
        pushDir[0] = zOrig[0] - myOrig[0];
        pushDir[1] = zOrig[1] - myOrig[1];
        pushDir[2] = 200.0;
        new Float:len = floatsqroot(pushDir[0]*pushDir[0] + pushDir[1]*pushDir[1]);
        if (len > 0.0)
        {
            pushDir[0] = pushDir[0] / len * 900.0;
            pushDir[1] = pushDir[1] / len * 900.0;
        }
        set_pev(j, pev_velocity, pushDir);
    }

    set_dhudmessage(0, 200, 255, -1.0, 0.70, 0, 0.0, 1.5, 0.05, 0.05);
    show_dhudmessage(id, "[KINETIC REPULSOR]: Discharged! (%d/2 used) | Power: %d%%",
        g_iRepulsorUses[id], g_iSuitPower[id]);
}

// ============================================================
// CMD DROP KEY (G) - Xen Orb (HEV Zombie) | Repulsor (Human)
// ============================================================
public cmd_DropKey(id)
{
    if (!is_user_alive(id)) return PLUGIN_CONTINUE;

    // HEV Zombie: Xen Displacement Orb - always first
    if (g_bIsHEVZombie[id] && zp_get_user_zombie(id))
    {
        fire_xen_orb(id);
        return PLUGIN_HANDLED;
    }

    // Non-knife - allow normal weapon drop
    if (get_user_weapon(id) != CSW_KNIFE)
        return PLUGIN_CONTINUE;

    // Human HEV + Wrench held → Kinetic Repulsor
    if (g_bHasHEV[id] && !zp_get_user_zombie(id) && get_pcvar_num(g_CvarEnabled))
    {
        cmd_KineticRepulsor(id);
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

// ============================================================
// XEN DISPLACEMENT ORB (HEV Zombie ability - DROP key)
// ============================================================
fire_xen_orb(id)
{
    new Float:now = get_gametime();

    // Cooldown check
    if ((now - g_fOrbCooldown[id]) < ORB_COOLDOWN)
    {
        new Float:remaining = ORB_COOLDOWN - (now - g_fOrbCooldown[id]);
        set_dhudmessage(255, 100, 0, -1.0, 0.70, 0, 0.0, 1.0, 0.05, 0.05);
        show_dhudmessage(id, "[XEN ORB: Recharging - %.0fs remaining]", remaining);
        return;
    }

    // HP cost check
    new hp = get_user_health(id);
    if (hp <= ORB_HP_COST)
    {
	set_dhudmessage(255, 100, 0, -1.0, 0.70, 0, 0.0, 1.0, 0.05, 0.05);
	show_dhudmessage(id, "[XEN ORB: Insufficient energy - Need >1500 HP]");
        emit_sound(id, CHAN_VOICE, SND_ZHV_POWER_LOW, 0.9, ATTN_NORM, 0, 80);
        return;
    }

    g_fOrbCooldown[id] = now;
    set_pev(id, pev_health, float(hp - ORB_HP_COST));

    // Create orb entity
    new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
    if (!pev_valid(ent)) return;

    g_iOrbEnt[id] = ent;

    static Float:origin[3], Float:viewOfs[3], Float:aimDir[3];
    pev(id, pev_origin, origin);
    pev(id, pev_view_ofs, viewOfs);
    origin[0] += viewOfs[0]; origin[1] += viewOfs[1]; origin[2] += viewOfs[2];

    velocity_by_aim(id, 1, aimDir);

    set_pev(ent, pev_classname, ORB_CLASSNAME);
    set_pev(ent, pev_owner,     id);
    engfunc(EngFunc_SetOrigin,  ent, origin);
    engfunc(EngFunc_SetModel,   ent, "sprites/plasma.spr");
    engfunc(EngFunc_SetSize,    ent, Float:{-4.0,-4.0,-4.0}, Float:{4.0,4.0,4.0});
    set_pev(ent, pev_movetype,  MOVETYPE_FLY);
    set_pev(ent, pev_solid,     SOLID_BBOX);
    set_pev(ent, pev_rendermode,kRenderTransAdd);
    set_pev(ent, pev_renderamt, 200.0);
    set_pev(ent, pev_scale,     0.5);
    set_pev(ent, pev_framerate, 10.0);
    set_pev(ent, pev_effects,   EF_BRIGHTLIGHT);
    set_pev(ent, pev_fuser1,    now + 8.0); // lifetime

    aimDir[0] *= ORB_SPEED; aimDir[1] *= ORB_SPEED; aimDir[2] *= ORB_SPEED;
    set_pev(ent, pev_velocity, aimDir);

    emit_sound(id, CHAN_WEAPON, SND_ORB_FIRE, 1.0, ATTN_NORM, 0, PITCH_NORM);

    // Trail effect
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMFOLLOW);
    write_short(ent);
    write_short(g_iRingSprite);
    write_byte(10); write_byte(5);
    write_byte(0); write_byte(200); write_byte(255); write_byte(200);
    message_end();

    set_dhudmessage(0, 200, 100, -1.0, 0.70, 0, 0.0, 1.5, 0.05, 0.05);
    show_dhudmessage(id, "[XEN ORB: Fired! HP Cost: %d]", ORB_HP_COST);

    // Auto-remove after 8s
    set_task(8.0, "task_remove_orb", ent + TASK_ORB_ANIMATE);
}

public task_remove_orb(taskid)
{
    new ent = taskid - TASK_ORB_ANIMATE;
    if (pev_valid(ent))
    {
        static Float:orig[3];
        pev(ent, pev_origin, orig);
        // Small explosion on expire
        message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
        write_byte(TE_EXPLOSION);
        write_coord(floatround(orig[0]));
        write_coord(floatround(orig[1]));
        write_coord(floatround(orig[2]));
        write_short(g_iGreenExplosionSprite);
        write_byte(10); write_byte(15); write_byte(4);
        message_end();
        engfunc(EngFunc_RemoveEntity, ent);
    }
}

// ============================================================
// ZP CALLBACKS
// ============================================================
public zp_user_infected_post(id)
{
    if (g_bIsHEVZombie[id] || g_bHasHEV[id])
    {
        if (IsBossClass(id))
        {
            g_bIsHEVZombie[id] = false;
            zp_remove_hev(id, HEV_REMOVE_MANUAL);
            return;
        }
        emit_sound(id, CHAN_VOICE, "fvox/hevSuit_get_infected_alert2.wav", 1.0, ATTN_NORM, 0, PITCH_NORM);
        emit_sound(id, CHAN_BODY,   SOUND_ZP_INFECTED, 0.8, ATTN_NORM, 0, PITCH_NORM);
        spawn_hev_head(id);
        zp_remove_hev(id, HEV_REMOVE_INFECTION);
        g_bIsHEVZombie[id] = true;
        clear_all_status_icons(id);
        stop_immersive_effects(id);
        set_task(0.1, "task_set_zombie_model", id);
        ExecuteForward(g_fwBecameHevZombie, g_fwReturn, id);
    }
}

public zp_user_humanized_post(id)
{
    g_bBoughtThisRound[id] = false;
    if (g_bIsHEVZombie[id]) { g_bIsHEVZombie[id] = false; cs_reset_user_model(id); }
}

public task_set_zombie_model(id)
{
    if (!is_user_connected(id) || !zp_get_user_zombie(id) || !g_bIsHEVZombie[id]) return;
    cs_set_user_model(id, HEV_ZOMBIE_SHORT);
    if (get_user_weapon(id) == CSW_KNIFE)
        set_pev(id, pev_viewmodel2, V_HEV_ZOMBIE_KNIFE);
}

// ============================================================
// SPAWN / KILL / ROUND
// ============================================================
public event_NewRound()
{
    g_hev_total_sold = 0;
    g_hev_bot_sold   = 0;
    for (new i = 1; i <= g_maxPlayers; i++)
    {
        g_bBoughtThisRound[i] = false;
        g_iBatteryBought[i]   = 0;
        g_iMedKitBought[i]    = 0;
        g_iRepulsorUses[i]    = 0;
        g_bHpRegening[i]      = false;
        g_bHpRecentDamage[i]  = false;
        remove_task(i + TASK_HP_REGEN);
        remove_task(i + TASK_HP_COOLDOWN);
        zp_remove_hev(i, HEV_REMOVE_ROUNDEND);
        reset_immersive_data(i);
        stop_immersive_effects(i);
        clear_all_status_icons(i);
        g_fLastFirewall[i] = 0.0;
    }
}

public fw_PlayerKilled(victim, attacker, shouldgib)
{
    if (g_bHasHEV[victim])
    {
        play_fvox(victim, SOUND_FLATLINE);
        spawn_hev_head(victim);
    }

    // ── HEV Zombie Death: Bio-Reactor Meltdown + Death Portal ─
    if (g_bIsHEVZombie[victim])
    {
        emit_sound(victim, CHAN_VOICE, SND_ZHV_SHUTDOWN, 1.0, ATTN_NORM, 0, PITCH_NORM);

        static Float:orig[3];
        pev(victim, pev_origin, orig);

        // Green explosion TE
        message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
        write_byte(TE_EXPLOSION);
        write_coord(floatround(orig[0]));
        write_coord(floatround(orig[1]));
        write_coord(floatround(orig[2]));
        write_short(g_iGreenExplosionSprite);
        write_byte(20); write_byte(15); write_byte(4);
        message_end();

        // Store for meltdown acid damage
        g_MeltdownOrigin[victim][0] = orig[0];
        g_MeltdownOrigin[victim][1] = orig[1];
        g_MeltdownOrigin[victim][2] = orig[2];
        set_task(0.5, "task_meltdown_damage", victim + TASK_DEATH_FADE, _, _, "b");
        set_task(3.5, "task_stop_meltdown",   victim + TASK_DEATH_FADE + 1);

        // Spawn Death Portal
        spawn_death_portal(victim, orig);
    }

    trigger_death_effects(victim);
    clear_all_status_icons(victim);
    stop_immersive_effects(victim);
    zp_remove_hev(victim, HEV_REMOVE_DEATH);
    return HAM_IGNORED;
}

// ── Bio-Reactor Meltdown (acid damage loop)
public task_meltdown_damage(taskid)
{
    new victim = taskid - TASK_DEATH_FADE;
    for (new i = 1; i <= g_maxPlayers; i++)
    {
        if (!is_user_alive(i) || zp_get_user_zombie(i)) continue;
        if (!g_bHasHEV[i]) continue;
        new Float:playerOrig[3];
        pev(i, pev_origin, playerOrig);
        if (get_distance_f(playerOrig, g_MeltdownOrigin[victim]) <= 200.0)
        {
            new Float:armor;
            pev(i, pev_armorvalue, armor);
            armor -= 10.0;
            if (armor < 0.0) armor = 0.0;
            set_pev(i, pev_armorvalue, armor);
            set_dhudmessage(0, 255, 0, -1.0, 0.15, 0, 0.0, 1.0, 0.1, 0.1);
            show_dhudmessage(i, "[BIO-REACTOR MELTDOWN: ACID DAMAGE]");
        }
    }
}

public task_stop_meltdown(taskid)
{
    remove_task(taskid - 1);
}

trigger_death_effects(id)
{
    create_screen_fade(id, FADE_DURATION * 4, FADE_DURATION * 4, FADE_OUT, 0, 0, 0, 255);
    set_task(1.0, "task_death_pulse", id + TASK_DEATH_FADE);
}

public task_death_pulse(taskid)
{
    new id = taskid - TASK_DEATH_FADE;
    if (!is_user_connected(id)) return;
    emit_sound(id, CHAN_STATIC, g_DeathPulseSound, 1.0, ATTN_NORM, 0, PITCH_NORM);
}

public fw_PlayerSpawn_Post(id)
{
    if (!is_user_alive(id)) return;
    if (zp_get_user_zombie(id) && g_bIsHEVZombie[id])
        set_task(0.2, "task_set_zombie_model", id);
    else
        zp_remove_hev(id, HEV_REMOVE_MANUAL);
    reset_immersive_data(id);
    stop_immersive_effects(id);
    clear_all_status_icons(id);
    g_ImData[id][IM_LAST_HEALTH] = float(get_user_health(id));

    if (g_bHasHEV[id] && !zp_get_user_zombie(id))
    {
        set_dhudmessage(255, 170, 0, -1.0, 0.85, 2, 0.0, 3.0, 0.1, 0.1);
        show_dhudmessage(id, "[HEV-LOG]: Battery: 100 Percent | Bio-Signals: STABLE");
    }
}

public client_connected(id) { reset_immersive_data(id); }

public client_disconnected(id)
{
    stop_immersive_effects(id);
    clear_all_status_icons(id);
    zp_remove_hev(id, HEV_REMOVE_DISCONNECT);
    reset_immersive_data(id);
}

// ============================================================
// DEATH PORTAL (BLACK HOLE)
// ============================================================
spawn_death_portal(owner_id, const Float:orig[3])
{
    new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
    if (!pev_valid(ent)) return;

    g_iPortalEnt[owner_id] = ent;

    set_pev(ent, pev_classname, PORTAL_CLASSNAME);
    set_pev(ent, pev_owner,     owner_id);
    engfunc(EngFunc_SetOrigin,  ent, orig);
    engfunc(EngFunc_SetModel,   ent, "sprites/exit1.spr");
    engfunc(EngFunc_SetSize,    ent, Float:{-32.0,-32.0,-32.0}, Float:{32.0,32.0,32.0});
    set_pev(ent, pev_movetype,  MOVETYPE_NONE);
    set_pev(ent, pev_solid,     SOLID_TRIGGER);
    set_pev(ent, pev_rendermode,kRenderTransAdd);
    set_pev(ent, pev_renderamt, 200.0);
    set_pev(ent, pev_scale,     1.5);
    set_pev(ent, pev_framerate, 10.0);
    set_pev(ent, pev_effects,   EF_BRIGHTLIGHT);

    // Glow light
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_DLIGHT);
    write_coord(floatround(orig[0]));
    write_coord(floatround(orig[1]));
    write_coord(floatround(orig[2]));
    write_byte(30);
    write_byte(0); write_byte(200); write_byte(50);
    write_byte(50); write_byte(10); write_byte(1);
    message_end();

    // Gravity pull loop every 0.2s
    set_task(0.2, "task_portal_pull", ent + TASK_PORTAL_PULL, _, _, "b");
    // Remove portal after PORTAL_DURATION
    set_task(PORTAL_DURATION, "task_portal_remove", ent + TASK_PORTAL_REMOVE);
}

public task_portal_pull(taskid)
{
    new ent = taskid - TASK_PORTAL_PULL;
    if (!pev_valid(ent)) { remove_task(taskid); return; }

    static Float:portalOrig[3];
    pev(ent, pev_origin, portalOrig);

    for (new i = 1; i <= g_maxPlayers; i++)
    {
        if (!is_user_alive(i) || !g_bHasHEV[i] || zp_get_user_zombie(i)) continue;

        new Float:playerOrig[3];
        pev(i, pev_origin, playerOrig);
        new Float:dist = get_distance_f(playerOrig, portalOrig);

        if (dist <= ORB_PULL_RADIUS && dist > 1.0)
        {
            // Pull vector toward portal
            new Float:pull[3];
            pull[0] = (portalOrig[0] - playerOrig[0]) / dist * 120.0;
            pull[1] = (portalOrig[1] - playerOrig[1]) / dist * 120.0;
            pull[2] = (portalOrig[2] - playerOrig[2]) / dist * 80.0;

            new Float:vel[3];
            pev(i, pev_velocity, vel);
            vel[0] += pull[0]; vel[1] += pull[1]; vel[2] += pull[2];
            set_pev(i, pev_velocity, vel);
        }
    }
}

public task_portal_remove(taskid)
{
    new ent = taskid - TASK_PORTAL_REMOVE;
    if (pev_valid(ent))
    {
        remove_task(ent + TASK_PORTAL_PULL);
        engfunc(EngFunc_RemoveEntity, ent);
    }
}

// ============================================================
// TOUCH HANDLER (HEV Head + Orb + Portal)
// ============================================================
public fw_TouchHandler(ent, victim)
{
    if (!pev_valid(ent)) return FMRES_IGNORED;

    static szClass[32];
    pev(ent, pev_classname, szClass, charsmax(szClass));

    // ── HEV Head: Battery Scavenging ─────────────────────────
    if (equal(szClass, "hev_head"))
    {
        if (is_user_alive(victim) && g_bHasHEV[victim] && !zp_get_user_zombie(victim))
        {
            g_iSuitPower[victim] = MAX_POWER;
            cs_set_user_armor(victim, get_pcvar_num(g_cvArmor), CS_ARMOR_VESTHELM);
            emit_sound(victim, CHAN_ITEM, SND_ZHV_ACQUIRED, 0.9, ATTN_NORM, 0, PITCH_NORM);
            ColorChat(victim, GREEN, "^1[^4H.E.V^1]: Battery scavenged! Suit Power ^3100 Percent^1 restored.");
            remove_task(ent + TASK_HEV_HEAD);
            engfunc(EngFunc_RemoveEntity, ent);
            return FMRES_SUPERCEDE;
        }

        new Float:readyTime;
        pev(ent, pev_fuser1, readyTime);
        if (get_gametime() < readyTime) return FMRES_IGNORED;

        set_pev(ent, pev_movetype, MOVETYPE_TOSS);
        set_pev(ent, pev_solid,    SOLID_NOT);

        static Float:zero[3];
        new Float:vel[3];
        pev(ent, pev_velocity, vel);
        vel[0] *= 0.2; vel[1] *= 0.2; vel[2] = 0.0;
        set_pev(ent, pev_velocity, vel);
        set_pev(ent, pev_avelocity, zero);

        return FMRES_IGNORED;
    }

    // ── Xen Orb: hit a player → teleport ─────────────────────
    if (equal(szClass, ORB_CLASSNAME))
    {
        if (!is_user_alive(victim)) return FMRES_IGNORED;

        new owner = pev(ent, pev_owner);

        // Must hit a human (not the owner)
        if (victim == owner) return FMRES_IGNORED;
        if (!zp_get_user_zombie(victim)) // hit a human
        {
            emit_sound(victim, CHAN_VOICE, SND_ZHV_SHOCK, 0.9, ATTN_NORM, 0, PITCH_NORM);
            create_screen_fade(victim, FADE_DURATION, FADE_HOLD, FADE_STAYOUT, 100, 0, 200, 180);
            TeleportToRandomSpawn(victim);
            remove_task(ent + TASK_ORB_ANIMATE);
            engfunc(EngFunc_RemoveEntity, ent);
            return FMRES_SUPERCEDE;
        }
        return FMRES_IGNORED;
    }

    // ── Death Portal: Human enters ────────────────────────────
    if (equal(szClass, PORTAL_CLASSNAME))
    {
        if (!is_user_alive(victim)) return FMRES_IGNORED;

        if (!zp_get_user_zombie(victim) && g_bHasHEV[victim])
        {
            // Human sacrifice: HP and Armor cut by 50%
            new Float:hp;
            pev(victim, pev_health, hp);
            hp *= 0.5;
            if (hp < 1.0) hp = 1.0;
            set_pev(victim, pev_health, hp);

            new Float:armor;
            pev(victim, pev_armorvalue, armor);
            armor *= 0.5;
            if (armor < 0.0) armor = 0.0;
            set_pev(victim, pev_armorvalue, armor);

            emit_sound(victim, CHAN_VOICE, SND_ZHV_CRITICAL, 0.9, ATTN_NORM, 0, 80);
            create_screen_fade(victim, FADE_DURATION, FADE_HOLD, FADE_STAYOUT, 200, 0, 0, 180);
            show_diag_dhud(victim, "[PORTAL EXPOSURE: HP and ARMOR -50 Percent]");
            TeleportToRandomSpawn(victim);
            return FMRES_SUPERCEDE;
        }

        if (zp_get_user_zombie(victim)) // Zombie breach
        {
            TeleportToRandomSpawn(victim);
            return FMRES_SUPERCEDE;
        }
        return FMRES_IGNORED;
    }

    return FMRES_IGNORED;
}

// ============================================================
// ANTI-STUCK TELEPORTATION
// ============================================================
bool:IsSpawnPointValid(const spawn_ent)
{
    if (!pev_valid(spawn_ent)) return false;
    new ent = -1;
    new Float:origin[3];
    pev(spawn_ent, pev_origin, origin);
    while ((ent = engfunc(EngFunc_FindEntityInSphere, ent, origin, 64.0)) > 0)
    {
        if (1 <= ent <= g_maxPlayers && is_user_alive(ent))
            return false;
    }
    return true;
}

TeleportToRandomSpawn(id)
{
    // Build list of all spawn points
    new spawn_ents[64], spawn_count;
    new ent = -1;

    while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "info_player_deathmatch")) > 0)
    {
        if (spawn_count < 64 && IsSpawnPointValid(ent))
            spawn_ents[spawn_count++] = ent;
    }
    while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "info_player_start")) > 0)
    {
        if (spawn_count < 64 && IsSpawnPointValid(ent))
            spawn_ents[spawn_count++] = ent;
    }

    if (spawn_count == 0) return; // no valid spawn found

    new chosen = spawn_ents[random_num(0, spawn_count - 1)];
    new Float:dest[3], Float:angles[3];
    pev(chosen, pev_origin, dest);
    pev(chosen, pev_angles, angles);

    // Teleport
    set_pev(id, pev_velocity,    Float:{0.0,0.0,0.0});
    set_pev(id, pev_basevelocity,Float:{0.0,0.0,0.0});
    engfunc(EngFunc_SetOrigin, id, dest);
    set_pev(id, pev_angles,  angles);
    set_pev(id, pev_fixangle, 1);

    emit_sound(id, CHAN_WEAPON, SND_ORB_SELF, 0.9, ATTN_NORM, 0, PITCH_NORM);

    // Arrival effect
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_SPRITE);
    write_coord(floatround(dest[0]));
    write_coord(floatround(dest[1]));
    write_coord(floatround(dest[2]));
    write_short(g_iPortalSprite);
    write_byte(10); write_byte(128);
    message_end();
}

// ============================================================
// HEV HEAD DROP
// ============================================================
stock spawn_hev_head(id)
{
    static Float:origin[3], Float:viewOfs[3];
    pev(id, pev_origin, origin);
    pev(id, pev_view_ofs, viewOfs);
    origin[2] += viewOfs[2] + 8.0;

    new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
    if (!pev_valid(ent)) return;

    set_pev(ent, pev_classname, "hev_head");
    engfunc(EngFunc_SetOrigin, ent, origin);
    engfunc(EngFunc_SetModel,  ent, HEV_HEAD_MDL);
    engfunc(EngFunc_SetSize,   ent, Float:{-2.0,-2.0,-2.0}, Float:{2.0,2.0,2.0});
    set_pev(ent, pev_movetype,   MOVETYPE_BOUNCE);
    set_pev(ent, pev_solid,      SOLID_TRIGGER);
    set_pev(ent, pev_gravity,    1.8);
    set_pev(ent, pev_takedamage, DAMAGE_NO);
    set_pev(ent, pev_fuser1,     get_gametime() + 0.5);

    static Float:avel[3];
    avel[0] = random_float(-300.0, 300.0);
    avel[1] = random_float(-300.0, 300.0);
    avel[2] = random_float(-150.0, 150.0);
    set_pev(ent, pev_avelocity, avel);

    static Float:vel[3];
    vel[0] = random_float(-50.0, 50.0);
    vel[1] = random_float(-50.0, 50.0);
    vel[2] = -80.0;
    set_pev(ent, pev_velocity, vel);

    set_task(4.0, "task_remove_hev_head", ent + TASK_HEV_HEAD);
}

public task_remove_hev_head(taskid)
{
    new ent = taskid - TASK_HEV_HEAD;
    if (pev_valid(ent)) engfunc(EngFunc_RemoveEntity, ent);
}

// ============================================================
// HP REGENERATION - +1 HP/s, max 100, pause on damage, resume 3s after
// ============================================================
public task_hp_regen(taskid)
{
    new id = taskid - TASK_HP_REGEN;
    if (!is_user_alive(id) || !g_bHasHEV[id] || zp_get_user_zombie(id))
        return;

    if (!g_bHpRegening[id] || g_bHpRecentDamage[id])
        return;

    new hp = get_user_health(id);
    if (hp < 100)
        set_user_health(id, min(hp + 1, 100));
}

public task_resume_hp_regen(taskid)
{
    new id = taskid - TASK_HP_COOLDOWN;
    if (!is_user_alive(id) || !g_bHasHEV[id] || zp_get_user_zombie(id))
        return;

    g_bHpRecentDamage[id] = false;
    g_bHpRegening[id]     = true;
}

// ============================================================
// EMIT SOUND HOOK
// ============================================================
public fw_EmitSound(id, channel, const sample[], Float:volume, Float:attn, flags, pitch)
{
    // Block zombie pain/body sounds
    if (sample[0] == 'p' && sample[1] == 'l' && sample[2] == 'a' && sample[3] == 'y'
        && sample[4] == 'e' && sample[5] == 'r' && sample[6] == '/')
    {
        if ((sample[7] == 'b' && sample[8] == 'h' && sample[9] == 'i' && sample[10] == 't') ||
            (sample[7] == 'p' && sample[8] == 'l' && sample[9] == 'a' && sample[10] == 'i' && sample[11] == 'n'))
        {
            if (is_user_connected(id) && (zp_get_user_zombie(id) || IsBossClass(id)))
                return FMRES_SUPERCEDE;
        }
    }

    if (!is_user_connected(id)) return FMRES_IGNORED;

    // HEV Zombie: replace zombie pain/hit sounds with corrupted FVOX
    if (g_bIsHEVZombie[id])
    {
        if (containi(sample, "zombie/") != -1 || containi(sample, "pain") != -1)
        {
            new snd_pick = random_num(0, 2);
            new snd_to_play[64];
            switch (snd_pick)
            {
                case 0: copy(snd_to_play, charsmax(snd_to_play), SND_ZHV_DAMAGE);
                case 1: copy(snd_to_play, charsmax(snd_to_play), SND_ZHV_BLOODLOSS);
                case 2: copy(snd_to_play, charsmax(snd_to_play), SND_ZHV_WARNING);
            }
            emit_sound(id, CHAN_VOICE, snd_to_play, 0.9, ATTN_NORM, 0, 80);
            return FMRES_SUPERCEDE;
        }
    }

    // Replace knife sounds with Wrench when player has HEV
    if (!g_bHasHEV[id] || zp_get_user_zombie(id)) return FMRES_IGNORED;

    if (sample[8] == 'k' && sample[9] == 'n' && sample[10] == 'i')
    {
        if (equal(sample, "weapons/knife_deploy1.wav"))
        {
            emit_sound(id, channel, SND_WRENCH_DEPLOY, volume, attn, flags, pitch);
            return FMRES_SUPERCEDE;
        }
        if (containi(sample, "hitwall") != -1)
        {
            emit_sound(id, channel, SND_WRENCH_HITWALL, volume, attn, flags, pitch);
            return FMRES_SUPERCEDE;
        }
        if (containi(sample, "hit") != -1)
        {
            emit_sound(id, channel, SND_WRENCH_HIT, volume, attn, flags, pitch);
            return FMRES_SUPERCEDE;
        }
        if (containi(sample, "slash") != -1)
        {
            emit_sound(id, channel, SND_WRENCH_SLASH, volume, attn, flags, pitch);
            return FMRES_SUPERCEDE;
        }
        if (equal(sample, "weapons/knife_stab.wav"))
        {
            emit_sound(id, channel, SND_WRENCH_STAB, volume, attn, flags, pitch);
            return FMRES_SUPERCEDE;
        }
    }

    return FMRES_IGNORED;
}

// ============================================================
// UTILITY STOCKS
// ============================================================
stock bool:IsBossClass(id)
{
    if (zp_get_user_survivor(id)) return true;
#if defined zp_get_user_alien
    if (zp_get_user_alien(id)) return true;
#endif
#if defined zp_get_user_predator
    if (zp_get_user_predator(id)) return true;
#endif
#if defined zp_get_user_soulreaper
    if (zp_get_user_soulreaper(id)) return true;
#endif
#if defined zp_get_user_plasmor
    if (zp_get_user_plasmor(id)) return true;
#endif
    return false;
}

stock fm_remove_model_ent(id)
{
    if (pev_valid(g_ent_playermodel[id]))
    {
        engfunc(EngFunc_RemoveEntity, g_ent_playermodel[id]);
        g_ent_playermodel[id] = 0;
    }
}

stock ScreenFade(id, color[3], Float:duration, Float:hold)
{
    message_begin(MSG_ONE, g_msgScreenFade, _, id);
    write_short(floatround(duration * (1<<12)));
    write_short(floatround(hold * (1<<12)));
    write_short(0x0000);
    write_byte(color[0]); write_byte(color[1]); write_byte(color[2]); write_byte(100);
    message_end();
}

create_screen_fade(id, duration, hold, type, red, green, blue, alpha)
{
    if (zp_get_user_zombie(id)) return;
    message_begin(MSG_ONE_UNRELIABLE, g_msgScreenFade, {0,0,0}, id);
    write_short(duration); write_short(hold); write_short(type);
    write_byte(red); write_byte(green); write_byte(blue); write_byte(alpha);
    message_end();
}

stock util_play_weapon_animation(const Player, const Sequence)
{
    set_pev(Player, pev_weaponanim, Sequence);
    message_begin(MSG_ONE_UNRELIABLE, SVC_WEAPONANIM, .player = Player);
    write_byte(Sequence);
    write_byte(pev(Player, pev_body));
    message_end();
}

// ============================================================
// restore_default_weapon_model - CRASH-SAFE switch
// WARNING: Do NOT modify this function.
// ============================================================
stock restore_default_weapon_model(id)
{
    if (!is_user_alive(id)) return;
    new wpn_id = get_user_weapon(id);
    static szModel[64];
    switch(wpn_id)
    {
        case CSW_P228:        copy(szModel, charsmax(szModel), "models/v_p228.mdl");
        case CSW_SCOUT:       copy(szModel, charsmax(szModel), "models/v_scout.mdl");
        case CSW_HEGRENADE:   copy(szModel, charsmax(szModel), "models/v_hegrenade.mdl");
        case CSW_XM1014:      copy(szModel, charsmax(szModel), "models/v_xm1014.mdl");
        case CSW_C4:          copy(szModel, charsmax(szModel), "models/v_c4.mdl");
        case CSW_MAC10:       copy(szModel, charsmax(szModel), "models/v_mac10.mdl");
        case CSW_AUG:         copy(szModel, charsmax(szModel), "models/v_aug.mdl");
        case CSW_SMOKEGRENADE:copy(szModel, charsmax(szModel), "models/v_smokegrenade.mdl");
        case CSW_ELITE:       copy(szModel, charsmax(szModel), "models/v_elite.mdl");
        case CSW_FIVESEVEN:   copy(szModel, charsmax(szModel), "models/v_fiveseven.mdl");
        case CSW_UMP45:       copy(szModel, charsmax(szModel), "models/v_ump45.mdl");
        case CSW_SG550:       copy(szModel, charsmax(szModel), "models/v_sg550.mdl");
        case CSW_GALIL:       copy(szModel, charsmax(szModel), "models/v_galil.mdl");
        case CSW_FAMAS:       copy(szModel, charsmax(szModel), "models/v_famas.mdl");
        case CSW_USP:         copy(szModel, charsmax(szModel), "models/v_usp.mdl");
        case CSW_GLOCK18:     copy(szModel, charsmax(szModel), "models/v_glock18.mdl");
        case CSW_AWP:         copy(szModel, charsmax(szModel), "models/v_awp.mdl");
        case CSW_MP5NAVY:     copy(szModel, charsmax(szModel), "models/v_mp5.mdl");
        case CSW_M249:        copy(szModel, charsmax(szModel), "models/v_m249.mdl");
        case CSW_M3:          copy(szModel, charsmax(szModel), "models/v_m3.mdl");
        case CSW_M4A1:        copy(szModel, charsmax(szModel), "models/v_m4a1.mdl");
        case CSW_TMP:         copy(szModel, charsmax(szModel), "models/v_tmp.mdl");
        case CSW_G3SG1:       copy(szModel, charsmax(szModel), "models/v_g3sg1.mdl");
        case CSW_FLASHBANG:   copy(szModel, charsmax(szModel), "models/v_flashbang.mdl");
        case CSW_DEAGLE:      copy(szModel, charsmax(szModel), "models/v_deagle.mdl");
        case CSW_SG552:       copy(szModel, charsmax(szModel), "models/v_sg552.mdl");
        case CSW_AK47:        copy(szModel, charsmax(szModel), "models/v_ak47.mdl");
        case CSW_KNIFE:       copy(szModel, charsmax(szModel), "models/v_knife.mdl");
        case CSW_P90:         copy(szModel, charsmax(szModel), "models/v_p90.mdl");
        default: return;
    }
    set_pev(id, pev_viewmodel2, szModel);
}
