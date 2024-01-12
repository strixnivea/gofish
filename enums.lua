WEATHER =
{
    RAIN   = 6,
    SQUALL = 7
}

MOONPHASE =
{
    NEW             = 0,
    WAXING_CRESCENT = 1,
    FIRST_QUARTER   = 2,
    WAXING_GIBBOUS  = 3,
    FULL            = 4,
    WANING_GIBBOUS  = 5,
    LAST_QUARTER    = 6,
    WAXING_CRESENT  = 7
}

FISHINGBAITTYPE =
{
    BAIT    = 0,
    LURE    = 1,
    SPECIAL = 2
}

FISHINGSIZETYPE =
{
    SMALL = 0,
    LARGE = 1
}

FISHINGCATCHTYPE =
{
    NONE         = 0,
    SMALLFISH    = 1,
    BIGFISH      = 2,
    ITEM         = 3,
    MOB          = 4,
    CHEST        = 5,
    SMALL_CUSTOM = 6,
    LARGE_CUSTOM = 7,
    MOB_CUSTOM   = 8
}

FISHINGGEAR =
{
    -- head
    TLAHTLAMAH_GLASSES  = 25608,
    TRAINEES_SPECTACLES = 11499,
    -- neck
    FISHERS_TORQUE      = 10925,
    -- body
    FISHERMANS_TUNICA   = 13808,
    ANGLERS_TUNICA      = 13809,
    FISHERMANS_APRON    = 14400,
    FISHERMANS_SMOCK    = 11337,
    -- hands
    FISHERMANS_GLOVES   = 14070,
    ANGLERS_GLOVES      = 14071,
    -- waist
    FISHERS_ROPE        = 11768,
    FISHERMANS_BELT     = 15452,
    -- legs
    FISHERMANS_HOSE     = 14292,
    ANGLERS_HOSE        = 14293,
    -- feet
    FISHERMANS_BOOTS    = 14171,
    ANGLERS_BOOTS       = 14172,
    WADERS              = 14195
}

FISHINGROD =
{
    WILLOW          = 17391,
    YEW             = 17390,
    BAMBOO          = 17389,
    FASTWATER       = 17388,
    TARUTARU        = 17387,
    LU_SHANG        = 17386,
    GLASS_FIBER     = 17385,
    CARBON          = 17384,
    CLOTHESPOLE     = 17383,
    SINGLE_HOOK     = 17382,
    COMPOSITE       = 17381,
    MITHRAN         = 17380,
    HALCYON         = 17015,
    HUME            = 17014,
    JUDGE           = 17012,
    GOLDFISH_BASKET = 17013,
    EBISU           = 17011,
    MAZE_MONGER     = 19319,
    LU_SHANG_1      = 19320,
    EBISU_1         = 19321
}

CONTAINERS =
{
    INVENTORY = 0,
    WARDROBE  = 8,
    WARDROBE2 = 10,
    WARDROBE3 = 11,
    WARDROBE4 = 12,
    WARDROBE5 = 13,
    WARDROBE6 = 14,
    WARDROBE7 = 15,
    WARDROBE8 = 16
}

EQUIPMENTSLOTS =
{
    MAIN  = 0,
    SUB   = 1,
    RANGE = 2,
    AMMO  = 3,
    HEAD  = 4,
    BODY  = 5,
    HANDS = 6,
    LEGS  = 7,
    FEET  = 8,
    NECK  = 9,
    WAIST = 10,
    EAR1  = 11,
    EAR2  = 12,
    RING1 = 13,
    RING2 = 14,
    BACK  = 15
}

WEEKDAY =
{
    FIRESDAY     = 0,
    EARTHSDAY    = 1,
    WATERSDAY    = 2,
    WINDSDAY     = 3,
    ICEDAY       = 4,
    LIGHTNINGDAY = 5,
    LIGHTSDAY    = 6,
    DARKSDAY     = 7
}

EVENTS =
{
    FISHING_OUT  = 0x01A,
    ZONEIN_IN    = 0x00A,
    ZONEOUT_IN   = 0x00B,
	EQUIPCHG_OUT = 0x050,
	EQUIPCHG_IN  = 0x051,
	ZONEDONE_IN  = 0x112,
    INVREADY_IN  = 0x01D
}

return {
    WEATHER          = WEATHER,
    MOONPHASE        = MOONPHASE,
    FISHINGBAITTYPE  = FISHINGBAITTYPE,
	FISHINGSIZETYPE  = FISHINGSIZETYPE,
	FISHINGCATCHTYPE = FISHINGCATCHTYPE,
	FISHINGGEAR      = FISHINGGEAR,
	FISHINGROD       = FISHINGROD,
    CONTAINERS       = CONTAINERS,
    EQUIPMENTSLOTS   = EQUIPMENTSLOTS,
    WEEKDAY          = WEEKDAY,
    EVENTS           = EVENTS
}