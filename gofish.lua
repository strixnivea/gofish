--[[
Copyright © 2023, StrixNivea
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Yield nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL StrixNivea BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]]

addon.name = 'GoFish';
addon.description = 'Calculate and view LSB fishing data using Imgui.';
addon.author = 'StrixNivea';
addon.version = '1.0.0';
addon.commands = {'/gofish', '/gf'};

-- Locals
require 'fishing_db';
require 'helpers';
require 'enums';

-- Ashita
require 'common';
local imgui = require('imgui');

---------------------------------------------------------------------------------------------------
-- desc: Default Status configuration table.
---------------------------------------------------------------------------------------------------
local default_config =
{
    window =
    {
        position    = {  40,  40 },
        dimensions  = { 400, 400},
        visible   = true,
    }
};
local configs = default_config;

----------------------------------------------------------------------------------------------------
-- Variables
----------------------------------------------------------------------------------------------------
local ashitaDataManager     = AshitaCore:GetMemoryManager();
local ashitaPtrManager      = AshitaCore:GetPointerManager();
local ashitaResourceManager = AshitaCore:GetResourceManager();

local ashitaPlayer    = ashitaDataManager:GetPlayer();
local ashitaParty     = ashitaDataManager:GetParty();
local ashitaInventory = ashitaDataManager:GetInventory();
local ashitaEntity    = ashitaDataManager:GetEntity();

local vanatimePtr = ashita.memory.find('FFXiMain.dll', 0, 'B0015EC390518B4C24088D4424005068', 0x34, 0);
local weatherPtr  = ashita.memory.find('FFXiMain.dll', 0, '66A1????????663D????72', 0x02, 0);

----------------------------------------------------------------------------------------------------
-- State Variables
----------------------------------------------------------------------------------------------------
astrology =
{
	ts = 0,
	hour = 0,
	phase = 0,
	month = 0,
	weather = 0
}

fisherman =
{
	zoneID = 0,
	rodID = 0,
	baitID = 0,
	rod = { },
	bait = { },
	zone = { },
	area = { },
	pos = { x=0, y=0, z=0 },
	skill = 95
}

gui_variables =
{
	fishChance = 0,
	itemChance = 0,
	mobChance  = 0,
	noChance   = 0,
	fishChances = { }
}

----------------------------------------------------------------------------------------------------
-- func: get_raw_timestamp
-- desc: Returns the current raw Vana'diel timestamp.
----------------------------------------------------------------------------------------------------
local function get_raw_timestamp()
    local pointer = ashita.memory.read_uint32(vanatimePtr);
    return ashita.memory.read_uint32(pointer + 0x0C);
end

----------------------------------------------------------------------------------------------------
-- func: get_current_date
-- desc: Returns a table with the current Vana'diel date.
----------------------------------------------------------------------------------------------------
local function get_current_date()
	local vanadate = { };
	
    local timestamp = get_raw_timestamp();
    local ts = (timestamp + 92514960) * 25;
    local day = math.floor(ts / 86400);

    -- Calculate the moon phase and normalized percentage
    local mphase = (day + 26) % 84;
    local mpercent = (((42 - mphase) * 100)  / 42);
    if (0 > mpercent) then
        mpercent = math.abs(mpercent);
    end
	
	-- Calculate the moon direction
	if mphase == 42 or mphase == 0 then
		vanadate.moon_direction = 0; -- None
	elseif mphase < 42 then
		vanadate.moon_direction = 1; -- Waning (decreasing)
	else
		vanadate.moon_direction = 2; -- Waxing (increasing)
	end

    -- Build the date information..
    vanadate.weekday        = (day % 8);
	vanadate.hour           = math.floor(ts / 3600) % 24;
    vanadate.day            = (day % 30) + 1;
    vanadate.month          = math.floor((day % 360) / 30) + 1;
    vanadate.year           = math.floor(day / 360);
    vanadate.moon_percent   = math.floor(mpercent + 0.5);

	-- Calculate the Ashita Moon Phase
    if (38 <= mphase) then  
        vanadate.ashita_moon_phase = math.floor((mphase - 38) / 7);
    else
        vanadate.ashita_moon_phase = math.floor((mphase + 46) / 7);
    end
	
	-- Convert to the Moon Phase that LSB uses for Fishing
	vanadate.moon_phase = math.floor((vanadate.ashita_moon_phase+1)*21/32); -- Just happens to work

    return vanadate;
end

----------------------------------------------------------------------------------------------------
-- func: get_weather
-- desc: Returns the current weather id.
----------------------------------------------------------------------------------------------------
function get_weather()
    local pointer = ashita.memory.read_uint32(weatherPtr);
    return ashita.memory.read_uint8(pointer);
end 

----------------------------------------------------------------------------------------------------
-- func: isInsideCylinder
-- desc: Helper function to calculate if a Player position is in the coordinates of a cylinder
--  ret: True or False
----------------------------------------------------------------------------------------------------
function isInsideCylinder(area)
	local pos = fisherman.pos;
	local center = { x=area["center_x"], y=area["center_y"], z=area["center_z"] };
	local radius = area["bound_radius"];
	local height = area["bound_height"];

	if pos.y < (center.y - (height / 2)) or pos.y > (center.y + (height/ 2 )) then return false; end

	local dx = math.abs(pos.x - center.x);
	if dx > radius then return false; end

	local dz = math.abs(pos.z - center.z);
	if dz > radius then return false; end

	if dx + dz <= radius then return true; end

	return dx * dx + dz *dz <= radius * radius;
end

----------------------------------------------------------------------------------------------------
-- func: isInsidePoly
-- desc: Helper function to calculate if a Player position is in the coordinates of a polygon
--  ret: True or False
----------------------------------------------------------------------------------------------------
function isInsidePoly(area)
	-- TODO Figure out how to import bounds hex data from passed area
	return false;
end

----------------------------------------------------------------------------------------------------
-- func: COSPATTERN
-- desc: Helper function to calculate pattern functions
--  ret: Numerical return of the specified pattern
----------------------------------------------------------------------------------------------------
function COSPATTERN(x, A, B, C, D)
	return math.clamp(A * math.cos(B*x+C) + D, 0.0, 1.0);
end

----------------------------------------------------------------------------------------------------
-- func: HOURPATTERN
-- desc: Helper function to calculate hour pattern functions
--  ret: Numerical return of the specified pattern
----------------------------------------------------------------------------------------------------
function HOURPATTERN_1(x) return COSPATTERN(x, 0.50, 0.82, 0.16, 0.50); end
function HOURPATTERN_2(x) return COSPATTERN(x, 0.50, 0.60, 3.50, 0.50); end
function HOURPATTERN_3(x) return COSPATTERN(x, 0.50, 0.53, 0.00, 0.50); end
function HOURPATTERN_4(x) return COSPATTERN(x, 0.50, 0.23, 3.53, 0.50); end

----------------------------------------------------------------------------------------------------
-- func: MOONPATTERN
-- desc: Helper function to calculate moon pattern functions
--  ret: Numerical return of the specified pattern
----------------------------------------------------------------------------------------------------
function MOONPATTERN_1(x) return COSPATTERN(x, 0.50, 1.75, 0.10, 0.50); end
function MOONPATTERN_2(x) return COSPATTERN(x, 0.50, 1.75, 3.30, 0.50); end
function MOONPATTERN_3(x) return math.clamp(1-(x/7.0), 0.0, 1.0); end
function MOONPATTERN_4(x) return COSPATTERN(x, 0.50, 0.90, 3.14, 0.50); end
function MOONPATTERN_5(x) return COSPATTERN(x, 0.50, 0.90, 0.00, 0.50); end

----------------------------------------------------------------------------------------------------
-- func: MONTHPATTERN
-- desc: Helper function to calculate month pattern functions
--  ret: Numerical return of the specified pattern
----------------------------------------------------------------------------------------------------
function MONTHPATTERN_1(x) return COSPATTERN(x, 0.50, 0.40, -1.60, 0.50); end
function MONTHPATTERN_2(x) return COSPATTERN(x, 0.50, 0.60, -1.00, 0.50); end
function MONTHPATTERN_3(x) return COSPATTERN(x, 0.50, 0.50,  3.05, 0.50); end
function MONTHPATTERN_4(x) return COSPATTERN(x, 0.50, 1.04,  0.00, 0.50); end
function MONTHPATTERN_5(x) return COSPATTERN(x, 0.50, 0.40,  3.50, 0.50); end
function MONTHPATTERN_6(x) return COSPATTERN(x, 0.50, 0.90, -2.00, 0.50); end
function MONTHPATTERN_7(x) return COSPATTERN(x, 0.50, 0.49,  1.63, 0.50); end
function MONTHPATTERN_8(x) return COSPATTERN(x, 0.50, 1.04, -2.60, 0.50); end
function MONTHPATTERN_9(x) return COSPATTERN(x, 0.50, 0.49, -1.25, 0.50); end
function MONTHPATTERN_10(x) return COSPATTERN(x, 0.50, 0.50,  0.53, 0.50); end

----------------------------------------------------------------------------------------------------
-- func: GetHourlyModifier
-- desc: Calls the appropriate HOURPATTERN for a specified fish entry and hour from Ashita API
--  ret: Modifier value between 0.25-1.25 from the selected hour pattern
----------------------------------------------------------------------------------------------------
function GetHourlyModifier(fish)
	local modifier = 0.5;
	local hourPattern = fish["hour_pattern"];
	local hour = astrology.hour;

	if     hourPattern == 1 then modifier = HOURPATTERN_1(hour);
	elseif hourPattern == 2 then
		if hour ~= 5 and hour ~= 17 then modifier = 1.0 end
	elseif hourPattern == 3 then
		if hour == 5 and hour == 17 then modifier = 1.0 end
	elseif hourPattern == 4 then
		if hour > 19 or  hour <  4  then modifier = 1.0 end
	elseif hourPattern == 5 then modifier = HOURPATTERN_2(hour);
	elseif hourPattern == 6 then modifier = HOURPATTERN_3(hour);
	elseif hourPattern == 7 then modifier = HOURPATTERN_4(hour);
	end

	return modifier + 0.25;
end

----------------------------------------------------------------------------------------------------
-- func: GetMoonModifier
-- desc: Calls the appropriate MOONPATTERN for a specified fish entry
--  ret: Modifier value between 0.25-1.25 from the selected moon pattern
----------------------------------------------------------------------------------------------------
function GetMoonModifier(fish)
	local modifier = 1.0;
	local moonPattern = fish["moon_pattern"]
	local moonPhase = astrology.phase;

	if     moonPattern == 1 then modifier = MOONPATTERN_1(moonPhase);
	elseif moonPattern == 2 then modifier = MOONPATTERN_2(moonPhase);
	elseif moonPattern == 3 then modifier = MOONPATTERN_3(moonPhase);
	elseif moonPattern == 4 then modifier = MOONPATTERN_4(moonPhase);
	elseif moonPattern == 5 then modifier = MOONPATTERN_4(moonPhase); -- Not a typo
	end

	return modifier + 0.25;

end

----------------------------------------------------------------------------------------------------
-- func: GetMonthlyTidalInfluence
-- desc: Calls the appropriate MONTHPATTERN for a specified fish entry and month from Ashita API
--  ret: Modifier value between 0.25-1.25 from the selected month pattern
----------------------------------------------------------------------------------------------------
function GetMonthlyTidalInfluence(fish)
	local modifier = 0.5;
	local monthPattern = fish["month_pattern"];
	local month = astrology.month;

	if     monthPattern == 1 then modifier = MONTHPATTERN_1(month);
	elseif monthPattern == 2 then modifier = MONTHPATTERN_2(month);
	elseif monthPattern == 3 then modifier = MONTHPATTERN_3(month);
	elseif monthPattern == 4 then modifier = MONTHPATTERN_4(month);
	elseif monthPattern == 5 then modifier = MONTHPATTERN_5(month);
	elseif monthPattern == 6 then modifier = MONTHPATTERN_6(month);
	elseif monthPattern == 7 then modifier = MONTHPATTERN_7(month);
	elseif monthPattern == 8 then modifier = MONTHPATTERN_8(month);
	elseif monthPattern == 9 then modifier = MONTHPATTERN_9(month);
	elseif monthPattern == 10 then modifier = MONTHPATTERN_10(month);
	end

	return modifier + 0.25;
end

----------------------------------------------------------------------------------------------------
-- func: GetWeatherModifier
-- desc: Gets the weather from Ashita API and checks for rain or squall
--  ret: Modifier value between 1.0-1.2
----------------------------------------------------------------------------------------------------
function GetWeatherModifier()
	local weather = astrology.weather;
	local modifier = 1.0;

	if     weather == WEATHER.RAIN   then modifier = 1.1;
	elseif weather == WEATHER.SQUALL then modifier = 1.2;
	end

	return modifier;
end

----------------------------------------------------------------------------------------------------
-- func: GetCurrentZoneId
-- desc: Gets the Player's current ZoneID through the Ashita API
--  ret: Enum value for zoneid
----------------------------------------------------------------------------------------------------
function GetCurrentZoneId()
    return ashitaParty:GetMemberZone(0); --APICALL
end

----------------------------------------------------------------------------------------------------
-- func: GetZoneInfo
-- desc: Gets the zone information from the fishing_zone db table
--  ret: Found fishing_zone entry
----------------------------------------------------------------------------------------------------
function GetZoneInfo(zoneID)
	return find_by_1(fishing_zone, test_by_1, "zoneid", zoneID);
end

----------------------------------------------------------------------------------------------------
-- func: GetAreasInZone
-- desc: Gets all areas in the fishing_area db table with given zoneID
--  ret: Table of fishing_area entries
----------------------------------------------------------------------------------------------------
function GetAreasInZone(zoneID)
	return table_stripkeys(filter_by_1(fishing_area, test_by_1, "zoneid", zoneID));
end

----------------------------------------------------------------------------------------------------
-- func: GetFishingArea
-- desc: Gets which area the player is currently in within a given zoneID
--  ret: Table of fishing_area entries
----------------------------------------------------------------------------------------------------
function GetFishingArea(zoneID)
	local bound_type;
	local ret = { };
	
	-- Sort the areas in the zone by bound_type so that the default(0) comes last
	local areaTable = GetAreasInZone(zoneID);
	table.sort(areaTable, function(k1, k2) return k1.bound_type > k2.bound_type end );
	
	for _, v in ipairs(areaTable) do
		bound_type = v["bound_type"];
		if bound_type == 0 then
			ret = v;
			break;
		elseif bound_type == 1 then
			if isInsideCylinder(v) then
				ret = v;
				break;
			end
		elseif bound_type == 2 then
			if isInsidePoly() then
				ret = v;
				break;
			end
		end
	end
	return ret;
end


----------------------------------------------------------------------------------------------------
-- func: GetFish
-- desc: Gets fishing_fish db entry for given fishid
--  ret: fishing_fish db entry
----------------------------------------------------------------------------------------------------
function GetFish(fishID)
	return find_by_1(fishing_fish, test_by_1, "fishid", fishID);
end

----------------------------------------------------------------------------------------------------
-- func: GetRod
-- desc: Gets fishing_rod db entry for given rodID
--  ret: fishing_rod db entry
----------------------------------------------------------------------------------------------------
function GetRod(rodID)
	return find_by_1(fishing_rod, test_by_1, "rodid", rodID);
end

----------------------------------------------------------------------------------------------------
-- func: GetBait
-- desc: Gets fishing_bait db entry for given baitID
--  ret: fishing_bait db entry
----------------------------------------------------------------------------------------------------
function GetBait(baitID)
	return find_by_1(fishing_bait, test_by_1, "baitid", baitID);
end

----------------------------------------------------------------------------------------------------
-- func: GetFishInGroup
-- desc: Get fishing_group entries by groupID and check if the fishing_fish entry is a fish
--  ret: A table of fishing_group and fishing_fish entry pairs
----------------------------------------------------------------------------------------------------
function GetFishInGroup(groupID)
	local pool = { }
	local group_pool = filter_by_1(fishing_group, test_by_1, "groupid", groupID);
	local fish;
	for _, v in pairs(group_pool) do
		fish = GetFish(v["fishid"]);
		if fish["item"] == 0 then
			table.insert(pool,{group_entry = v, fish_entry = fish});
		end
	end
	return pool;
end

----------------------------------------------------------------------------------------------------
-- func: GetItemsInGroup
-- desc: Get fishing_group entries by groupID and check if the fishing_fish entry is a item
--  ret: A table of fishing_group and fishing_fish entry pairs
----------------------------------------------------------------------------------------------------
function GetItemsInGroup(groupID)
	local pool = { }
	local group_pool = filter_by_1(fishing_group, test_by_1, "groupid", groupID);
	local fish;
	for _, v in pairs(group_pool) do
		fish = GetFish(v["fishid"]);
		if fish["item"] == 1 then
			-- Generate a new table to pair the fishing_group to the fishing_fish
			table.insert(pool,{group_entry = v, fish_entry = fish});
		end
	end
	return pool;
end

----------------------------------------------------------------------------------------------------
-- func: GetMobsInZone
-- desc: Get fishing_mob entries for specified zoneID
--  ret: A table of fishing_mob entries
----------------------------------------------------------------------------------------------------
function GetMobsInZone(zoneID)
	return filter_by_1(fishing_mob, test_by_1, "zoneid", zoneID);
end

----------------------------------------------------------------------------------------------------
-- func: GetCatchGroupID
-- desc: Get the GroupID of a zoneID and areaID pair from fishing_catch db
--  ret: Numerical value of groupid
----------------------------------------------------------------------------------------------------
function GetCatchGroupID(zoneID, areaID)
	return find_by_2(fishing_catch, test_by_2, "zoneid", "areaid", zoneID, areaID)["groupid"];
end

----------------------------------------------------------------------------------------------------
-- func: isBaitValid
-- desc: Make sure there is an entry for the given fishID and baitID in the fishing_bait_affinity db
--  ret: Numerical value of groupid
----------------------------------------------------------------------------------------------------
function isBaitValid(fishID, baitID)
	return exists_by_2(fishing_bait_affinity, test_by_2, "fishid", "baitid", fishID, baitID);
end

----------------------------------------------------------------------------------------------------
-- func: GetBaitPower
-- desc: Get the bait power for the given fishID and baitID in the fishing_bait_affinity db
--  ret: Numerical value of bait power
----------------------------------------------------------------------------------------------------
function GetBaitPower(fishID, baitID)
	return find_by_2(fishing_bait_affinity, test_by_2, "fishid", "baitid", fishID, baitID)["power"];
end

----------------------------------------------------------------------------------------------------
-- func: GetFishPool
-- desc: Use zoneID and areaID to find the groupID. Search all fish in the groupID to check if bait
--       is valid by baitID
--  ret: Table of fishing_fish db entries
----------------------------------------------------------------------------------------------------
function GetFishPool(zoneID, areaID, baitID)
	local pool = { };
	local groupID = GetCatchGroupID(zoneID, areaID);
	local group_pool = GetFishInGroup(groupID);

	-- Check if bait is valid and make new table
	for _, v in pairs(group_pool) do
		if isBaitValid(v["group_entry"]["fishid"], baitID) then
			table.insert(pool,v);
		end
	end

	return pool
end

----------------------------------------------------------------------------------------------------
-- func: GetItemPool
-- desc: Use zoneID and areaID to find the groupID. Search all items in the groupID
--  ret: Table of fishing_fish db entries
----------------------------------------------------------------------------------------------------
function GetItemPool(zoneID, areaID)
	local groupID = GetCatchGroupID(zoneID, areaID);
	return table_stripkeys(GetItemsInGroup(groupID));
end

----------------------------------------------------------------------------------------------------
-- func: GetMobPool
-- desc: Use zoneID to find mobs
--  ret: Table of fishing_mob db entries
----------------------------------------------------------------------------------------------------
function GetMobPool(zoneID)
	return table_stripkeys(GetMobsInZone(zoneID));
end

----------------------------------------------------------------------------------------------------
-- func: GetAshitaMoonPhase
-- desc: Access the Ashita API vanatime and get the moon_phase enum that spans 0-11
--  ret: Enum value of moon phase
----------------------------------------------------------------------------------------------------
function GetAshitaMoonPhase()
	return get_current_date().ashita_moon_phase; --APICALL
end

----------------------------------------------------------------------------------------------------
-- func: GetMoonPhase
-- desc: Convert the Ashita vanatime moon phase to LSB moon phase
--  ret: Enum value of moon phase
----------------------------------------------------------------------------------------------------
function GetMoonPhase()
	return get_current_date().moon_phase;
end

----------------------------------------------------------------------------------------------------
-- func: GetItemInEquipSlot
-- desc: Get the itemID of the item equipped in the specified slot
--  ret: Enum value of moon phase
----------------------------------------------------------------------------------------------------
function GetItemInEquipSlot(slot)
	local item = ashitaInventory:GetEquippedItem(slot); -- get the equipment_t
	if item then
		local iitem = ashitaInventory:GetContainerItem(bit.band(item.Index, 0xFF00) / 0x0100, item.Index % 0x0100);
		return iitem.Id;
	end
	return nil; -- Default/Error
end

----------------------------------------------------------------------------------------------------
-- func: UpdateFisherman
-- desc: Updates all the Player state variables by calling Ashita API
--  ret: None
----------------------------------------------------------------------------------------------------
function UpdateFisherman()
	local fishingData = ashitaPlayer:GetCraftSkill(0);
	fisherman.skill = fishingData:GetSkill();

	local index = ashitaParty:GetMemberTargetIndex(0);
    local posX  = ashitaEntity:GetLocalPositionX(index);
    local posY  = ashitaEntity:GetLocalPositionZ(index); -- swapped with Z
	local posZ  = ashitaEntity:GetLocalPositionY(index); -- swapped with Y
	fisherman.pos = { x = posX, y = posY, z = posZ };

	fisherman.zoneID = GetCurrentZoneId() --Calls ashitaParty:GetMemberZone(0)
	fisherman.rodID  = GetItemInEquipSlot(EQUIPMENTSLOTS.RANGE);
	fisherman.baitID = GetItemInEquipSlot(EQUIPMENTSLOTS.AMMO);

	fisherman.area = GetFishingArea(fisherman.zoneID);
	fisherman.rod  = GetRod(fisherman.rodID);
	fisherman.bait = GetBait(fisherman.baitID);
end

----------------------------------------------------------------------------------------------------
-- func: UpdateAstrology
-- desc: Updates all the Astrological state variables by calling Ashita API
--  ret: None
----------------------------------------------------------------------------------------------------
function UpdateAstrology()
	astrology.ts      = get_raw_timestamp();
	astrology.hour    = get_current_date().hour;
	astrology.phase   = get_current_date().moon_phase;
	astrology.month   = get_current_date().month;
	astrology.weather = get_weather();
end

----------------------------------------------------------------------------------------------------
-- func: CalculateHookChance
-- desc: Calculate the chance to hook a fish based on time, bait, and rod
--  ret: A weighted value ranged between 0-120
----------------------------------------------------------------------------------------------------
function CalculateHookChance(fishingSkill, fish, bait, rod)
	local monthModifier = GetMonthlyTidalInfluence(fish);
	local hourModifier  = GetHourlyModifier(fish) * 2;
	local moonModifier  = GetMoonModifier(fish) * 3;
	local modifier      = math.max(0, (moonModifier + hourModifier + monthModifier) / 3);
	local hookChance    = math.floor(25*modifier);

	-- Adjust for the fish/bait affinity
	local baitPower = GetBaitPower(fish["fish_entry"]["fishid"],bait["baitid"]);
	if baitPower == 1 then
		if bait["type"] == FISHINGBAITTYPE.LURE then
			hookChance = hookChance + 30;
		else
			hookChance = hookChance + 35;
		end
	elseif baitPower == 2 then
		if bait["type"] == FISHINGBAITTYPE.LURE then
			hookChance = hookChance + 60;
		else
			hookChance = hookChance + 65;
		end
	elseif baitPower == 3 then
		if bait["type"] == FISHINGBAITTYPE.LURE then
			hookChance = hookChance + 75;
		else
			hookChance = hookChance + 80;
		end
	else
		hookChance = 0; -- Added to catch errors if somehow the isBaitValid filter didn't work
	end

	-- Level too low Penalty
	if fish["fish_entry"]["skill_level"] > fishingSkill then
		hookChance = hookChance - math.clamp(math.floor((fish["fish_entry"]["skill_level"]-fishingSkill) * 0.25), 0, hookChance);
	end

	-- Level too high Penalty
	if fishingSkill - 10 > fish["fish_entry"]["skill_level"] then
		hookChance = hookChance - math.clamp(math.floor((fishingSkill - 10 - fish["fish_entry"]["skill_level"]) * 0.15), 0, hookChance);
	end

	-- Rod size mismatch penalty
	if rod["legendary"] ~= 1 then
		if fish["fish_entry"]["size_type"] < rod["size_type"] then
			hookChance = hookChance - math.clamp(3, 0, hookChance);
		elseif fish["fish_entry"]["size_type"] > rod["size_type"] then
			hookChance = hookChance - math.clamp(5, 0, hookChance);
		end
	end

	-- TODO Shellfish Affinity

	-- Adjustment for fish rarity
	local multiplier;
	if fish["group_entry"]["rarity"] < 1000 then
		multiplier = fish["group_entry"]["rarity"] / 1000;
		hookChance = math.floor(hookChance * multiplier);
	end

	return math.clamp(hookChance, 20, 120);
end

----------------------------------------------------------------------------------------------------
-- func: FishingCheck
-- desc: Simulate how LSB determines the chances of catching everything in a fishing area based on
--       Player location, gear, and fishing skill
--  ret: That's a good question...
----------------------------------------------------------------------------------------------------
function FishingCheck(fishingSkill, rod, bait, area)
	local FishPoolWeight = 0;
	local ItemPoolWeight = 0;
	local MobPoolWeight = 0;
	local NoCatchWeight = 0;

	local mphase = astrology.phase;
	local fishPoolMoonModifier = MOONPATTERN_4(mphase);
	local itemPoolMoonModifier = MOONPATTERN_2(mphase);
	local mobPoolMoonModifier  = MOONPATTERN_3(mphase);
	local noCatchMoonModifier  = MOONPATTERN_5(mphase);

	local CZoneID   = fisherman.zoneID;
	local CZoneInfo = GetZoneInfo(CZoneID);
	fisherman.zone  = CZoneInfo

	-- Adjust weights by whether or not the player is in a city
	if CZoneInfo["type"] % 2 == 1 then
		FishPoolWeight =      math.floor(15*fishPoolMoonModifier);
		ItemPoolWeight = 25 + math.floor(20*itemPoolMoonModifier);
		MobPoolWeight  = 0;
		NoCatchWeight  = 30 + math.floor(15*noCatchMoonModifier);
	else
		FishPoolWeight =      math.floor(25*fishPoolMoonModifier);
		ItemPoolWeight = 10 + math.floor(15*itemPoolMoonModifier);
		MobPoolWeight  = 15 + math.floor(15*mobPoolMoonModifier);
		NoCatchWeight  = 15 + math.floor(20*noCatchMoonModifier);
	end

	local FishHookChanceTotal = 0;
	local ItemHookChanceTotal = 0;

	local FishHookPool = { };
	local ItemHookPool = { };
	local MobHookPool  = { };

	-- Populate the pools based on all possibilities in that zone
	local FishPool = GetFishPool(CZoneID, area["areaid"], bait["baitid"]);
	local ItemPool = GetItemPool(CZoneID, area["areaid"]);
	local MobPool  = GetMobPool(CZoneID);

	-- Add to the FishHookPool all fish that are eligible to catch and their weighted chance
	local hookChance;
	local maxChance = 0;
	for _, v in pairs(FishPool) do
		if fishingSkill >= v["fish_entry"]["skill_level"] or v["fish_entry"]["skill_level"] - fishingSkill <= 100 then
			hookChance = CalculateHookChance(fishingSkill, v, bait, rod);
			-- Attach the calculated hook chance to the fetched entries
			table.insert(FishHookPool, {chance = hookChance, fish = v["fish_entry"], group = v["group_entry"]});
			FishHookChanceTotal = FishHookChanceTotal + hookChance;
			if hookChance > maxChance then
				maxChance = hookChance;
			end
		end
	end
	FishPoolWeight = math.clamp(FishPoolWeight + maxChance, 20, 120); -- Only increase the FishPoolWeight by chance of most likely fish

	-- Add to the ItemHookPool all items that are eligible to catch
	-- TODO Implement full code for ItemHookPool, but for now, just filter out quest items
	for _, v in pairs(ItemPool) do
		if v["fish_entry"]["quest"] == 255 and v["fish_entry"]["log"] == 255 then
			table.insert(ItemHookPool, v["fish_entry"])
		end
	end

	-- Add to the MobHookPool all mobs that are eligible to catch
	-- TODO Implement NM and Quest mobs
	for _, v in pairs(MobPool) do
		if v["nm"] == 0 and (v["areaid"] == 0 or v["areaid"] == area["areaid"]) then
			table.insert(MobHookPool, v);
		end
	end

	-- Adjust the FishPoolWeight for if the weather is rain or a squall
	FishPoolWeight = math.floor(FishPoolWeight * GetWeatherModifier());

	-- Adjust the NoCatchWeight by the difficulty of the current zone
	if CZoneInfo["difficulty"] > 0 then
		NoCatchWeight = NoCatchWeight + CZoneInfo["difficulty"] * 25; --Assume average of 20 and 30
	end

	-- TODO Fishing Apron Adjustment

	-- TODO Poor Fish Bait Flag Adjustment

	-- If there are no fish that could be hooked, adjust the weights
	if table_count(FishHookPool) > 0 then
		-- TODO Lu Shang and Ebisu adjustments to FishPoolWeight
	else
		NoCatchWeight = math.floor(NoCatchWeight + FishPoolWeight/2);
		FishPoolWeight = 0;
	end

	-- If there are no items that could be hooked, adjust the weights
	if table_count(ItemHookPool) == 0 then
		NoCatchWeight = math.floor(NoCatchWeight + ItemPoolWeight/2);
		ItemPoolWeight = 0;
	end

	-- If there are no mobs that could be hooked, adjust the weights
	if table_count(MobHookPool) == 0 then
		NoCatchWeight = math.floor(NoCatchWeight + MobPoolWeight/2);
		MobPoolWeight = 0;
	end

	-- If you are just wasting your time, adjust the weights
	if FishPoolWeight == 0 and ItemPoolWeight == 0 and MobPoolWeight == 0 then
		NoCatchWeight = 1000;
	end

	-- Total up the weights and find the percent chance for each catch type
	local totalWeight = FishPoolWeight + ItemPoolWeight + MobPoolWeight + NoCatchWeight;
	local fishChance  = FishPoolWeight / totalWeight;
	local itemChance  = ItemPoolWeight / totalWeight;
	local mobChance   = MobPoolWeight  / totalWeight;
	local noChance    = NoCatchWeight  / totalWeight;

	gui_variables.fishChance = fishChance * 100;
	gui_variables.itemChance = itemChance * 100;
	gui_variables.mobChance  = mobChance  * 100;
	gui_variables.noChance   = noChance   * 100;

	local chance, fish_name, pool_size, restock_rate;
	gui_variables.fishChances = { };
	for _, entry in pairs(FishHookPool) do
		chance = entry["chance"] / FishHookChanceTotal * gui_variables.fishChance;
		fish_name  = entry["fish"].name;
		pool_size = entry["group"].pool_size;
		restock_rate = entry["group"].restock_rate;
		table.insert(gui_variables.fishChances, { chance, fish_name, pool_size, restock_rate });
	end
end

----------------------------------------------------------------------------------------------------s
-- func: load
-- desc: Event called when the addon is being loaded.
----------------------------------------------------------------------------------------------------
ashita.events.register("load", "load_cb", function ()
	UpdateFisherman();
	UpdateAstrology();
	FishingCheck(fisherman.skill, fisherman.rod, fisherman.bait, fisherman.area);
end);

----------------------------------------------------------------------------------------------------
-- func: render
-- desc: Hook up to the Ashita render tick
----------------------------------------------------------------------------------------------------
ashita.events.register("d3d_present", "present_cb", function()
	imgui.SetNextWindowSize(default_config.window.dimensions, ImGuiCond_FirstUseEver);
	imgui.SetNextWindowPos(default_config.window.position, ImGuiCond_FirstUseEver);
	
	index = ashitaParty:GetMemberTargetIndex(0);
    local posX  = ashitaEntity:GetLocalPositionX(index);
    local posY  = ashitaEntity:GetLocalPositionZ(index); -- swapped with Z
	local posZ  = ashitaEntity:GetLocalPositionY(index); -- swapped with Y

	if imgui.Begin("GoFishMainWindow", true) then
		imgui.Text(string.format("Skill: %d", fisherman.skill));
		imgui.Text(string.format("Zone: %s(%d)", fisherman.zone["name"], GetCurrentZoneId()));
		imgui.Text(string.format("Area: %s(%d)", fisherman.area["name"], fisherman.area["areaid"]));
		imgui.Text(string.format("Rod: %s(%d)", fisherman.rod["name"], fisherman.rodID));
		imgui.Text(string.format("Bait: %s(%d)", fisherman.bait["name"], fisherman.baitID));
		for _, entry in pairs(gui_variables.fishChances) do
			imgui.Text (string.format("Chance: %.2f  Name: %s", entry[1], entry[2]));
		end
		imgui.Text(string.format("Chance: %.2f  Name: %s", gui_variables.itemChance, "Item"));
		imgui.Text(string.format("Chance: %.2f  Name: %s", gui_variables.mobChance, "Mob"));
		imgui.Text(string.format("Chance: %.2f  Name: %s", gui_variables.noChance, "No Catch"));
		imgui.Text(string.format("h:%d p:%d m:%d", astrology.hour, astrology.phase, astrology.month));
		imgui.Text(string.format("x:%.2f y:%.2f z:%.2f", posX, posY, posZ));
		imgui.End();
	end
end);