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
local imgui     = require('imgui');
local settings  = require('settings');

---------------------------------------------------------------------------------------------------
-- desc: Default ImGui Window Settings
---------------------------------------------------------------------------------------------------
local default_config =
{
    window =
    {
        position   = {  40,  40 },
        dimensions = { 420, 320 }
    },
    
    config_window =
    {
        position   = {  40,  40 },
        dimensions = { 264, 240 }
    },
    
    eula_window =
    {
        position   = { 100, 100 },
        dimensions = { 640, 240 }
    }
};

----------------------------------------------------------------------------------------------------
-- Variables
----------------------------------------------------------------------------------------------------
local ashitaDataManager = AshitaCore:GetMemoryManager();

local ashitaPlayer    = ashitaDataManager:GetPlayer();
local ashitaParty     = ashitaDataManager:GetParty();
local ashitaInventory = ashitaDataManager:GetInventory();
local ashitaEntity    = ashitaDataManager:GetEntity();

local vanatimePtr = ashita.memory.find('FFXiMain.dll', 0, 'B0015EC390518B4C24088D4424005068', 0x34, 0);
local weatherPtr  = ashita.memory.find('FFXiMain.dll', 0, '66A1????????663D????72', 0x02, 0);

local gSettings = nil;
local default_settings = T{
    showColumns = T{
        Pool  = T{false,},
        Rate  = T{false,},
        Lose  = T{true,},
        Snap  = T{true,},
        Break = T{true,},
        Up    = T{false,}
    },
    showConfig = T{false,},
    hideEula   = T{false,},
    skillupmul = T{"3",},
};

local eula_literal =
[[This addon statistically determines the approximate results of
LandSandBoat-based private servers' implementation of retail FFXI
fishing. In other words, it is an approximation of a simulation.
This addon does not get any of the actual calculation results from
the server itself. Therefore it is only 'accurate' as long as the
server implementation does not change. Any deviations are the fault
of the addon and NOT the server. By using this addon, the user agrees
to accept the results as approximations and only submit bug reports
to StrixNivea on GitHub and not server administrators.]];

----------------------------------------------------------------------------------------------------
-- State Variables
----------------------------------------------------------------------------------------------------
astrology =
{
    hour    = 0,
    phase   = 0,
    moondir = 0,
    moonper = 0,
    month   = 0,
    weather = 0
}

fisherman =
{
    zoneID  = 0,
    rodID   = 0,
    baitID  = 0,
    headID  = 0;
    neckID  = 0;
    bodyID  = 0;
    handsID = 0;
    waistID = 0;
    legsID = 0;
    feetID = 0;
    zone = { },
    area = { },
    rod  = { },
    bait = { },
    valid_area = false,
    valid_rod  = false,
    valid_bait = false,
    pos = { x=0, y=0, z=0 },
    skill     = 0,
    skill_raw = 0,
    skill_mod = 0,
    equip_changed = false,
    zoning        = false,
    in_city       = false,
    loaded        = false
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
    vanadate.timestamp    = timestamp;
    vanadate.weekday      = (day % 8);
    vanadate.hour         = math.floor(ts / 3600) % 24;
    vanadate.day          = (day % 30) + 1;
    vanadate.month        = math.floor((day % 360) / 30) + 1;
    vanadate.year         = math.floor(day / 360);
    vanadate.moon_percent = math.floor(mpercent + 0.5);

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
-- func: onSegment
-- desc: Checks if point q lies on line segment pr
--  ret: True or False.
----------------------------------------------------------------------------------------------------
function onSegment(p, q, r)
    local t1 = (q.x <= math.max(p.x, r.x));
    local t2 = (q.x >= math.min(p.x, r.x));
    local t3 = (q.z <= math.max(p.z, r.z));
    local t4 = (q.z <= math.min(p.z, r.z));

    return t1 and t2 and t3 and t4;
end

----------------------------------------------------------------------------------------------------
-- func: orientation
-- desc: Finds orientation of ordered point triplet
--  ret: 0, 1, 2.
----------------------------------------------------------------------------------------------------
function orientation(p, q, r)
    local val = (q.z - p.z) * (r.x - q.x) - (q.x - p.x) * (r.z - q.z);
    local r_val = math.floor(val+0.5) -- Lua does not have a round()

    if r_val == 0 then
        return 0;
    elseif r_val > 0 then
        return 1;
    else
        return 2;
    end
end

----------------------------------------------------------------------------------------------------
-- func: doIntersect
-- desc: Checks if line segments p1q1 and p2q2 intersect
--  ret: True or False.
----------------------------------------------------------------------------------------------------
function doIntersect(p1, q1, p2, q2)
    local o1 = orientation(p1, q1, p2);
    local o2 = orientation(p1, q1, q2);
    local o3 = orientation(p2, q2, p1);
    local o4 = orientation(p2, q2, q1);

    if o1 ~= o2 and o3 ~= o4              then return true; end
    if o1 == 0  and onSegment(p1, p2, q1) then return true; end
    if o2 == 0  and onSegment(p1, q2, q1) then return true; end
    if o3 == 0  and onSegment(p2, p1, q2) then return true; end
    if o4 == 0  and onSegment(p2, q1, q2) then return true; end

    return false;
end

----------------------------------------------------------------------------------------------------
-- func: isInsidePoly
-- desc: Helper function to calculate if a Player position is in the coordinates of a polygon
--  ret: True or False
----------------------------------------------------------------------------------------------------
function isInsidePoly(area)
    local p          = fisherman.pos;
    local posy       = area["center_y"];
    local height     = area["bound_height"];
    local polygon    = area["bounds"];
    local n          = table_count(area["bounds"]);
    local MAX_POINTS = 10000;

    -- Return early if the point doesn't satisfy the easiest test: the y position
    if p.y < (posy - (height / 2)) or p.y > (posy + (height / 2)) then return false; end

    -- Otherwise do the polygon math
    local extreme = { x = MAX_POINTS, y = p.z, z = 0 };

    local count = 0;
    local i     = 0;

    repeat
        local next = (i+1) % n;
        if doIntersect(polygon[i+1], polygon[next+1], p, extreme) then
            if orientation(polygon[i+1], p, polygon[next+1]) == 0 then
                return onSegment(polygon[i+1], p, polygon[next+1]);
            end
            count = count + 1;
        end
        i = next;
    until i == 0;

    return (count % 2) == 1;
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

    if pos.y < (center.y - (height / 2)) or pos.y > (center.y + (height / 2)) then return false; end

    local dx = math.abs(pos.x - center.x);
    if dx > radius then return false; end

    local dz = math.abs(pos.z - center.z);
    if dz > radius then return false; end

    if dx + dz <= radius then return true; end

    return dx * dx + dz *dz <= radius * radius;
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
    local modifier    = 0.5;
    local hourPattern = fish["hour_pattern"];
    local hour        = astrology.hour;

    if     hourPattern == 1 then modifier = HOURPATTERN_1(hour);
    elseif hourPattern == 2 then
        if hour ~= 5 and hour ~= 17 then modifier = 1.0 end
    elseif hourPattern == 3 then
        if hour == 5 or  hour == 17 then modifier = 1.0 end
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
    local modifier    = 1.0;
    local moonPattern = fish["moon_pattern"]
    local moonPhase   = astrology.phase;

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
    local modifier     = 0.5;
    local monthPattern = fish["month_pattern"];
    local month        = astrology.month;

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
    local weather  = astrology.weather;
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
            if isInsidePoly(v) then
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
--  ret: True or False
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
-- func: isKeyItemReq
-- desc: Check if the given fish requires a key item to hook
--  ret: True or False
----------------------------------------------------------------------------------------------------
function isKeyItemReq(fish)
    return fish["required_keyitem"] > 0;
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
-- func: GetSkillMod
-- desc: Determine by how much the Player equipment increases fishing skill
--  ret: Additional fishing skill from equipment
----------------------------------------------------------------------------------------------------
function GetSkillMod()
    local skillMod = 0;

    if     fisherman.headID  == FISHINGGEAR.TLAHTLAMAH_GLASSES then skillMod = skillMod + 1; end
    if     fisherman.neckID  == FISHINGGEAR.FISHERS_TORQUE     then skillMod = skillMod + 2; end

    if     fisherman.bodyID  == FISHINGGEAR.FISHERMANS_TUNICA  then skillMod = skillMod + 1;
    elseif fisherman.bodyID  == FISHINGGEAR.ANGLERS_TUNICA     then skillMod = skillMod + 1;
    elseif fisherman.bodyID  == FISHINGGEAR.FISHERMANS_SMOCK   then skillMod = skillMod + 1;
    end

    if     fisherman.handsID == FISHINGGEAR.FISHERMANS_GLOVES  then skillMod = skillMod + 1;
    elseif fisherman.handsID == FISHINGGEAR.ANGLERS_GLOVES     then skillMod = skillMod + 1;
    end

    if     fisherman.legsID  == FISHINGGEAR.FISHERMANS_HOSE    then skillMod = skillMod + 1;
    elseif fisherman.legsID  == FISHINGGEAR.ANGLERS_HOSE       then skillMod = skillMod + 1;
    end

    if     fisherman.feetID  == FISHINGGEAR.FISHERMANS_BOOTS   then skillMod = skillMod + 1;
    elseif fisherman.feetID  == FISHINGGEAR.ANGLERS_BOOTS      then skillMod = skillMod + 1;
    elseif fisherman.feetID  == FISHINGGEAR.WADERS             then skillMod = skillMod + 2;
    end

    --if fisherman.headID == FISHINGGEAR.TRAINEES_SPECTACLES and fisherman.skill < 40 then
    --    skillMod = skillMod + 1;
    --end

    return skillMod;
end

----------------------------------------------------------------------------------------------------
-- func: UpdateEquipment
-- desc: Updates all the Player equipment variables by calling Ashita API
--  ret: None
----------------------------------------------------------------------------------------------------
function UpdateEquipment()
    fisherman.rodID   = GetItemInEquipSlot(EQUIPMENTSLOTS.RANGE);
    fisherman.baitID  = GetItemInEquipSlot(EQUIPMENTSLOTS.AMMO);
    fisherman.headID  = GetItemInEquipSlot(EQUIPMENTSLOTS.HEAD);
    fisherman.neckID  = GetItemInEquipSlot(EQUIPMENTSLOTS.NECK);
    fisherman.bodyID  = GetItemInEquipSlot(EQUIPMENTSLOTS.BODY);
    fisherman.handsID = GetItemInEquipSlot(EQUIPMENTSLOTS.HANDS);
    fisherman.waistID = GetItemInEquipSlot(EQUIPMENTSLOTS.WAIST);
    fisherman.legsID  = GetItemInEquipSlot(EQUIPMENTSLOTS.LEGS);
    fisherman.feetID  = GetItemInEquipSlot(EQUIPMENTSLOTS.FEET);

    fisherman.rod  = GetRod(fisherman.rodID);
    fisherman.bait = GetBait(fisherman.baitID);
end

----------------------------------------------------------------------------------------------------
-- func: UpdateFisherman
-- desc: Updates all the Player state variables by calling Ashita API
--  ret: None
----------------------------------------------------------------------------------------------------
function UpdateFisherman()
    -- Update Player fishing skill
    local fishingData   = ashitaPlayer:GetCraftSkill(0); -- Fishing is first in craftskills_t
    fisherman.skill_raw = fishingData:GetSkill();

    -- Update Player additional fishing skill from equipment
    UpdateEquipment();
    fisherman.skill_mod = GetSkillMod();

    -- Total Player fishing skill
    fisherman.skill = fisherman.skill_raw + fisherman.skill_mod;

    -- Update Player location
    local index = ashitaParty:GetMemberTargetIndex(0);
    local posX  = ashitaEntity:GetLocalPositionX(index);
    local posY  = ashitaEntity:GetLocalPositionZ(index); -- swapped with Z
    local posZ  = ashitaEntity:GetLocalPositionY(index); -- swapped with Y
    fisherman.pos = { x = posX, y = posY, z = posZ };

    fisherman.zoneID  = GetCurrentZoneId() --Calls ashitaParty:GetMemberZone(0)
    fisherman.zone    = GetZoneInfo(fisherman.zoneID)
    fisherman.area    = GetFishingArea(fisherman.zoneID);
    fisherman.in_city = (fisherman.zone["type"] % 2 == 1); -- Need to do bit.band if enum changes

    -- Update related state variables
    if table_isempty(fisherman.area) then fisherman.valid_area = false;
    else                                  fisherman.valid_area = true;
    end

    if table_isempty(fisherman.rod)  then fisherman.valid_rod  = false;
    else                                  fisherman.valid_rod  = true;
    end

    if table_isempty(fisherman.bait) then fisherman.valid_bait = false;
    else                                  fisherman.valid_bait = true;
    end
end

----------------------------------------------------------------------------------------------------
-- func: UpdateAstrology
-- desc: Updates all the Astrological state variables by calling Ashita API
--  ret: None
----------------------------------------------------------------------------------------------------
function UpdateAstrology()
    local vanadate    = get_current_date();

    astrology.hour    = vanadate.hour;
    astrology.phase   = vanadate.moon_phase;
    astrology.moondir = vanadate.moon_direction;
    astrology.moonper = vanadate.moon_percent;
    astrology.month   = vanadate.month;
    astrology.weather = get_weather();
end

----------------------------------------------------------------------------------------------------
-- func: FishingSkillup
-- desc: Calculate the chance that a given fish will result in a skillup
--  ret: Percent chance of skillup
----------------------------------------------------------------------------------------------------
function FishingSkillup(fish)
    local levelDifference = 0;
    --local maxSkillAmount = 1;
    local charSkillLevel = math.floor(fisherman.skill_raw)

    if fish["skill_level"] > charSkillLevel then
        levelDifference = fish["skill_level"] - charSkillLevel;
    end

    if fish["skill_level"] <= charSkillLevel or levelDifference > 50 then
        return 0.0;
    end

    -- TODO: Could check the players fishing rank and see if skill is capped

    local skillRoll = 90;
    --local bonusChanceRoll = 8;

    if not table_isempty(fisherman.rod) and charSkillLevel < 50 and fisherman.rodID == FISHINGROD.LU_SHANG then
        skillRoll = skillRoll + 20;
    end

    local normDist = math.exp(-0.5 * math.log(2 * math.pi) - math.log(5) - (levelDifference - 11)^2 / 50);
    local distMod  = math.floor(normDist * 200);
    local lowerLevelBonus = math.floor((100 - charSkillLevel) / 10);
    local skillLevelPenalty = math.floor(charSkillLevel / 10);

    local maxChance = math.max(4, distMod + lowerLevelBonus - skillLevelPenalty);

    local moonDirection = astrology.moondir;
    local phase         = astrology.moonper;
    if moonDirection == 0 then
        if phase == 0 then
            skillRoll = skillRoll - 20;
            --bonusChanceRoll = bonusChanceRoll - 3;
        elseif phase == 100 then
            skillRoll = skillRoll + 10;
            --bonusChanceRoll = bonusChanceRoll + 3;
        end
    elseif moonDirection == 1 then
        if phase <= 10 then
            skillRoll = skillRoll - 15;
            --bonusChanceRoll = bonusChanceRoll - 2;
        elseif phase >= 95 and phase <= 100 then
            skillRoll = skillRoll + 5;
            --bonusChanceRoll = bonusChanceRoll + 2;
        end
    elseif moonDirection == 2 then
        if phase <= 5 then
            skillRoll = skillRoll - 10;
            --bonusChanceRoll = bonusChanceRoll - 1;
        --elseif phase >= 90 and phase <= 100 then
            --bonusChanceRoll = bonusChanceRoll + 1;
        end
    end

    if not fisherman.in_city then
        skillRoll = skillRoll - 10;
    end

    if charSkillLevel < 50 then
        skillRoll = skillRoll - (20 - math.floor(charSkillLevel / 3));
    end

    --maxSkillAmount = math.min(1 + math.floor(levelDifference / 5), 3)

    -- TODO: Could calculate outcomes for bonusChanceRoll and cap skill increase based rank skill cap

    -- Normally LSB would 'if math.rand(skillRoll) < maxChance', but this fuction returns a percent chance
    return maxChance / skillRoll * 100;
end

----------------------------------------------------------------------------------------------------
-- func: CalculateBreakChance
-- desc: Calculate the chance that a given fish will break the currently equipped rod
--  ret: Percent chance to break rod
----------------------------------------------------------------------------------------------------
function CalculateBreakChance(fish)
    local levelDiffBonus = 0;
    local legendaryBonus = 0;
    local sizePenalty    = 0;

    if fisherman.rod["breakable"] == 0 then
        return 0.0;
    end

    if fisherman.skill + 10 > fish["skill_level"] then
        levelDiffBonus = 2;
    end

    if fisherman.rod["legendary"] == 0 and fish["size_type"] > fisherman.rod["size_type"] then
        sizePenalty = 2;
    elseif fisherman.rod["legendary"] == 1 and fish["size_type"] == FISHINGSIZETYPE.LARGE then
        legendaryBonus = 1;
    end

    if fisherman.rod["legendary"] == 0 and fish["legendary"] == 1 then
        sizePenalty = 5;
    end

    if fish["ranking"] > fisherman.rod["max_rank"] + levelDiffBonus + legendaryBonus then
        local strDuraDiff = fish["ranking"] - (fisherman.rod["max_rank"] + levelDiffBonus + legendaryBonus);
        return math.clamp(math.floor((strDuraDiff + sizePenalty) * 1.3), 0, 55);
    else
        return 0.0;
    end
end

----------------------------------------------------------------------------------------------------
-- func: CalculateSnapChance
-- desc: Calculate the chance that a given fish will snap the line of the currently equipped rod
--  ret: Percent chance to snap line
----------------------------------------------------------------------------------------------------
function CalculateSnapChance(fish)
    local levelDiffBonus  = 0;
    local legendaryBonus  = 0;
    local sizePenalty     = 0;

    if fisherman.skill + 10 > fish["skill_level"] then
        levelDiffBonus = 2;
    end

    if fisherman.rod["legendary"] == 0 and fish["size_type"] > fisherman.rod["size_type"] then
        sizePenalty = 2;
    end

    if fish["legendary"] == 1 then
        if fisherman.rod["legendary"] == 0 then
            sizePenalty = sizePenalty + 3;
        else
            legendaryBonus = 1;
        end
    end

    local totalDurability = fisherman.rod["max_rank"] + levelDiffBonus + legendaryBonus - sizePenalty;

    if fish["ranking"] > totalDurability then
        return math.clamp(math.floor((fish["ranking"] - totalDurability) * 8.5), 0, 55);
    else
        return 0.0;
    end
end

----------------------------------------------------------------------------------------------------
-- func: CalculateLoseChance
-- desc: Calculate the chance that a given fish be lost due to skill (and other variables)
--  ret: Percent chance to lose catch
----------------------------------------------------------------------------------------------------
function CalculateLoseChance(fish)
    local tooBigChance   = 0;
    local tooSmallChance = 0;
    local lowSkillChance = 0;

    local catchType;
    if fish["size_type"] == FISHINGSIZETYPE.SMALL then catchType = FISHINGCATCHTYPE.SMALLFISH;
    else                                               catchType = FISHINGCATCHTYPE.BIGFISH;
    end

    if fisherman.rod["legendary"] == 0 then
        if     fish["size_type"] > fisherman.rod["size_type"] and fish["ranking"] > fisherman.rod["max_rank"] then
            tooBigChance = 50 + fish["skill_level"] - fisherman.skill;
        elseif fish["size_type"] < fisherman.rod["size_type"] and fish["ranking"] < fisherman.rod["min_rank"] then
            tooSmallChance = 50;
            if fisherman.skill < fish["skill_level"] then
                tooSmallChance = tooSmallChance + fish["skill_level"] - fisherman.skill;
            end
            if fisherman.skill > fish["skill_level"] then
                tooSmallChance = tooSmallChance - math.min(fisherman.skill - fish["skill_level"], tooSmallChance);
            end
        end
    end

    if catchType < FISHINGCATCHTYPE.ITEM and fisherman.skill + 7 < fish["skill_level"] then
        lowSkillChance = math.floor((fish["skill_level"] - (fisherman.skill + 7)) * 0.8);
    end

    if     tooBigChance   > 0 and tooBigChance   > lowSkillChance   then return math.clamp(tooBigChance, 0 , 50);
    elseif tooSmallChance > 0 and tooSmallChance > lowSkillChance   then return math.clamp(tooSmallChance, 0, 50);
    elseif catchType < FISHINGCATCHTYPE.ITEM and lowSkillChance > 0 then return math.clamp(lowSkillChance, 0, 55);
    else                                                                 return 0.0;
    end
end

----------------------------------------------------------------------------------------------------
-- func: CalculateHookChance
-- desc: Calculate the chance to hook a fish based on time, bait, and rod
--  ret: A weighted value ranged between 20-120
----------------------------------------------------------------------------------------------------
function CalculateHookChance(fishingSkill, fish, bait, rod)
    local monthModifier = GetMonthlyTidalInfluence(fish["fish_entry"]);
    local hourModifier  = GetHourlyModifier(fish["fish_entry"]) * 2;
    local moonModifier  = GetMoonModifier(fish["fish_entry"]) * 3;
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
        local lowPenalty = math.floor((fish["fish_entry"]["skill_level"]-fishingSkill) * 0.25);
        hookChance = hookChance - math.clamp(lowPenalty, 0, hookChance);
    end

    -- Level too high Penalty
    if fishingSkill - 10 > fish["fish_entry"]["skill_level"] then
        local highPenalty = math.floor((fishingSkill - 10 - fish["fish_entry"]["skill_level"]) * 0.15);
        hookChance = hookChance - math.clamp(highPenalty, 0, hookChance);
    end

    -- Rod size mismatch penalty
    if rod["legendary"] ~= 1 then
        if fish["fish_entry"]["size_type"] < rod["size_type"] then
            hookChance = hookChance - math.clamp(3, 0, hookChance);
        elseif fish["fish_entry"]["size_type"] > rod["size_type"] then
            hookChance = hookChance - math.clamp(5, 0, hookChance);
        end
    end

    -- Shellfish Affinity
    if bit.band(fisherman.bait["flags"], BAITFLAG.SHELLFISH_AFFINITY) and bit.band(fish["fish_entry"]["flags"], FISHFLAG.SHELLFISH) then
        hookChance = hookChance + 50;
    end

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
    local CZoneInfo = fisherman.zone;

    -- Adjust weights by whether or not the player is in a city
    if fisherman.in_city then
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
    --local ItemHookChanceTotal = 0;

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
        local fish = v["fish_entry"];
        if (fishingSkill >= fish["skill_level"] or fish["skill_level"] - fishingSkill <= 100) and 
         (not isKeyItemReq(fish) or ashitaPlayer:HasKeyItem(fish["required_keyitem"])) then
            hookChance = CalculateHookChance(fishingSkill, v, bait, rod);
            -- Attach the calculated hook chance to the fetched entries
            table.insert(FishHookPool, {chance = hookChance, fish = fish, group = v["group_entry"]});
            FishHookChanceTotal = FishHookChanceTotal + hookChance;
            if hookChance > maxChance then
                maxChance = hookChance;
            end
        end
    end
    -- Only increase the FishPoolWeight by chance of most likely fish
    FishPoolWeight = math.clamp(FishPoolWeight + maxChance, 20, 120);

    -- Add to the ItemHookPool all items that are eligible to catch
    for _, v in pairs(ItemPool) do
        if v["fish_entry"]["quest"] == 255 and v["fish_entry"]["log"] == 255 then
            table.insert(ItemHookPool, v["fish_entry"])
        end
    end

    -- Add to the MobHookPool all mobs that are eligible to catch
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

    -- Fishing Apron Adjustment
    if fisherman.bodyID == FISHINGGEAR.FISHERMANS_APRON and ItemPoolWeight > 0 then
        local sub = math.floor(ItemPoolWeight * 0.25);
        if sub > 0 then
            ItemPoolWeight = ItemPoolWeight - sub;
            NoCatchWeight  = NoCatchWeight  + sub;
        end
    end

    -- Poor Fish Bait Flag Adjustment
    if bit.band(fisherman.bait["flags"], BAITFLAG.POOR_FISH) and FishPoolWeight > 0 then
        FishPoolWeight = FishPoolWeight - math.floor(FishPoolWeight * 0.25);
        ItemPoolWeight = FishPoolWeight + math.floor(FishPoolWeight * 0.10);
        NoCatchWeight  = NoCatchWeight  + math.floor(NoCatchWeight  * 0.25);
    end

    -- Normally this loop would select the hooked fish from the fish pool and apply the LU_SHANG/EBISU bonus based on
    -- that fish. Instead this loop calculates the added pool weight for each fish
    if table_count(FishHookPool) > 0 then
        if fisherman.rodID == FISHINGROD.LU_SHANG or fisherman.rodID == FISHINGROD.EBISU then
            for _, entry in pairs(FishHookPool) do
                local fish = entry["fish"];

                if fisherman.skill > fish["skill_level"] + 7 then
                    local skilldiff    = fisherman.skill - fish["skill_level"];
                    local initialBonus = 10;
                    local divisor      = 15;
                    if fisherman.rodID == FISHINGROD.EBISU then
                        initialBonus = 15;
                        divisor      = 13;
                    end
                    local skillmultiplier = 1 + math.floor(skilldiff / divisor);
                    local addWeight = initialBonus + math.floor((skilldiff * skillmultiplier) / (fish["size_type"] + 1));
                    -- Tack on the additional weight to the entry in FishHookPool
                    entry["addWeight"] = addWeight;
                else
                    entry["addWeight"] = 0;
                end
            end
        end
    -- If there are no fish that could be hooked, adjust the weights
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
    
    -- Initialize basic chance variables
    local fishChance  = 0;
    local itemChance  = 0;
    local mobChance   = 0;
    local noChance    = 0;
        
    -- Check if the equipped rod needs to adjust the pool weights
    if fisherman.rodID == FISHINGROD.LU_SHANG or fisherman.rodID == FISHINGROD.EBISU then
        if table_count(FishHookPool) > 0 then
            for _, entry in pairs(FishHookPool) do
                local chance = entry["chance"] / FishHookChanceTotal;
                entry["chance_adj"] = chance * ( FishPoolWeight + entry["addWeight"] ) / ( totalWeight + entry["addWeight"] );
                fishChance = fishChance + entry["chance_adj"];
                itemChance = itemChance + chance * ( ItemPoolWeight ) / ( totalWeight + entry["addWeight"] );
                mobChance  = mobChance  + chance * ( MobPoolWeight )  / ( totalWeight + entry["addWeight"] );
                noChance   = noChance   + chance * ( NoCatchWeight )  / ( totalWeight + entry["addWeight"] );        
            end
        else
            fishChance = 0;
            itemChance = ItemPoolWeight / totalWeight;
            mobChance  = MobPoolWeight  / totalWeight;
            noChance   = NoCatchWeight  / totalWeight;
        end
    -- Or do simple calculations if the rod is boring
    else
        for _, entry in pairs(FishHookPool) do
            entry["chance_adj"] = (entry["chance"] / FishHookChanceTotal) * (FishPoolWeight / totalWeight);
        end
        fishChance = FishPoolWeight / totalWeight;
        itemChance = ItemPoolWeight / totalWeight;
        mobChance  = MobPoolWeight  / totalWeight;
        noChance   = NoCatchWeight  / totalWeight;
    end
    
    -- Prepare GUI variables table
    gui_variables.fishChance = fishChance * 100;
    gui_variables.itemChance = itemChance * 100;
    gui_variables.mobChance  = mobChance  * 100;
    gui_variables.noChance   = noChance   * 100;
    
    -- Make sure user input for multiplier is a number
    local skillupmul = tonumber(gSettings.skillupmul[1])
    if not skillupmul then skillupmul = 1; end
        
    -- Loop through FishHookPool and fill out variables for GUI
    local chance, fish_name, pool_size, restock_rate, chance_lose, chance_snap, chance_break, chance_up;
    gui_variables.fishChances = { };
    for _, entry in pairs(FishHookPool) do
        chance       = entry["chance_adj"] * 100;
        fish_name    = entry["fish"].name;
        pool_size    = entry["group"].pool_size;
        restock_rate = entry["group"].restock_rate;
        chance_lose  = CalculateLoseChance(entry.fish);
        chance_snap  = CalculateSnapChance(entry.fish);
        chance_break = CalculateBreakChance(entry.fish);
        chance_up    = FishingSkillup(entry.fish) * skillupmul;
        table.insert(gui_variables.fishChances,
            { chance, fish_name, pool_size, restock_rate, chance_lose, chance_snap, chance_break, chance_up }
        );
    end
end

----------------------------------------------------------------------------------------------------
-- func: Update
-- desc: Update the Fisherman and Astrology states, then run Fishing calculations
--  ret: Nothing
----------------------------------------------------------------------------------------------------
function Update()
    UpdateFisherman(); -- Updates the fisherman.valid_xxx variables below
    UpdateAstrology();
    if fisherman.valid_rod and fisherman.valid_bait and fisherman.valid_area then
        FishingCheck(fisherman.skill, fisherman.rod, fisherman.bait, fisherman.area);
    end
end

----------------------------------------------------------------------------------------------------s
-- func: load
-- desc: Event called when the addon is being loaded.
----------------------------------------------------------------------------------------------------
ashita.events.register("load", "load_cb", function ()
    -- Load saved settings else default
    gSettings = settings.load(default_settings);
    
    -- Player must have loaded the addon manually, so set loaded flag
    if ashitaInventory:GetContainerUpdateFlags() > 0 then
        fisherman.loaded = true;
    end
    
    Update();
end);

----------------------------------------------------------------------------------------------------s
-- func: unload
-- desc: Event called when the addon is being unloaded.
----------------------------------------------------------------------------------------------------
ashita.events.register("unload", "unload_cb", function ()
    settings.save();
end);

----------------------------------------------------------------------------------------------------
-- func: packet_out
-- desc: Event called when the client is sending a packet to the server.
----------------------------------------------------------------------------------------------------
ashita.events.register('packet_out', 'gofish_out_packet', function(e)
    if e.id == EVENTS.FISHING_OUT and struct.unpack("H", e.data, 0x0A) == 0x0E04 then
        Update();
    elseif e.id == EVENTS.EQUIPCHG_OUT then
        fisherman.equip_changed = true;
    end
end);

----------------------------------------------------------------------------------------------------
-- func: packet_in
-- desc: Event called when the client is receiving a packet from the server.
----------------------------------------------------------------------------------------------------
ashita.events.register('packet_in', 'gofish_in_packet', function(e)
    -- Code to handle if addon was auto-loaded
    if not fisherman.loaded and e.id == EVENTS.ZONEIN_IN then
        fisherman.loaded = true;
        fisherman.zoning = true;
    end
    -- Handle events
    if e.id == EVENTS.ZONEOUT_IN then -- zoning out
        fisherman.zoning = true;
    elseif (e.id == EVENTS.ZONEDONE_IN and fisherman.zoning) then -- Equipment ready after zoning
        Update();
        fisherman.zoning = false;
    elseif (e.id == EVENTS.EQUIPCHG_IN and fisherman.equip_changed) then
        Update();
        fisherman.equip_changed = false;
    end
end);

----------------------------------------------------------------------------------------------------
-- func: command
-- desc: Event called when the client sends a command to Ashita
----------------------------------------------------------------------------------------------------
ashita.events.register('command', 'gofish_command', function(e)
    local args = e.command:args();
    if #args == 0 then return; end

    local valid_command = false;
    args[1] = string.lower(args[1]);
    for _, entry in pairs(addon.commands) do
        if args[1] == entry then
            valid_command = true;
            break;
        end
    end
    if valid_command == false then return; end

    if #args > 1 then
        if string.lower(args[2]) == "update" then
            Update();
        elseif string.lower(args[2]) == "config" then
            gSettings.showConfig[1] = true;
        end
    end
end);

----------------------------------------------------------------------------------------------------
-- func: settings
-- desc: Registers a callback for the settings to monitor for character switches.
----------------------------------------------------------------------------------------------------
settings.register('settings', 'settings_update', function(s)
    if (s ~= nil) then
        gSettings = s;
    end
    
    settings.save();
end);

----------------------------------------------------------------------------------------------------
-- func: d3d_present
-- desc: Hook up to the Ashita render tick
----------------------------------------------------------------------------------------------------
ashita.events.register("d3d_present", "present_cb", function()
    --index = ashitaParty:GetMemberTargetIndex(0);
    --local posX = ashitaEntity:GetLocalPositionX(index);
    --local posY = ashitaEntity:GetLocalPositionZ(index); -- swapped with Z
    --local posZ = ashitaEntity:GetLocalPositionY(index); -- swapped with Y
    
    local addonStyle =
    {
        [ImGuiCol_Text]             = { 0.85, 0.85, 0.85, 1.0 },
        [ImGuiCol_WindowBg]         = { 0.10, 0.10, 0.10, 0.9 },
        [ImGuiCol_TitleBg]          = { 0.00, 0.28, 0.67, 1.0 },
        [ImGuiCol_TitleBgActive]    = { 0.00, 0.28, 0.67, 1.0 },
        [ImGuiCol_TitleBgCollapsed] = { 0.00, 0.28, 0.67, 0.5 },
        [ImGuiCol_ButtonHovered]    = { 0.00, 0.14, 0.33, 1.0 },
        [ImGuiCol_HeaderHovered]    = { 0.00, 0.14, 0.33, 1.0 }
    }
    
    -- Push all the Imgui Style Color data onto the stack
    for k, v in pairs(addonStyle) do
        imgui.PushStyleColor(k, v);
    end
    
    if fisherman.loaded and not fisherman.zoning then
        -- Draw Main Go Fish ImGui Window
        imgui.SetNextWindowSize(default_config.window.dimensions, ImGuiCond_FirstUseEver);
        imgui.SetNextWindowPos(default_config.window.position, ImGuiCond_FirstUseEver);
        if imgui.Begin("Go Fish", true) then
            imgui.Text(string.format("Skill: %d(%d)", fisherman.skill_raw, fisherman.skill_mod));
            imgui.Text(string.format("Zone: %s", fisherman.zone["name"]:gsub("_"," ")));
            if fisherman.valid_area then
                imgui.Text(string.format("Area: %s", fisherman.area["name"]:gsub("_"," ")));
            else
                imgui.Text("Area: None");
            end
            if fisherman.valid_rod then
                imgui.Text(string.format("Rod:  %s", fisherman.rod["name"]));
            else
                imgui.Text("Rod:  None");
            end
            if fisherman.valid_bait then
                imgui.Text(string.format("Bait: %s", fisherman.bait["name"]));
            else
                imgui.Text("Bait: None");
            end
            if fisherman.valid_area and fisherman.valid_rod and fisherman.valid_bait then
                -- Count the table columns that have been enabled, including the 2 static columns
                local column_count = 2;
                for _, v in pairs(gSettings.showColumns) do
                    if v[1] == true then column_count = column_count + 1; end
                end
                -- Draw the calculation results table
                if imgui.BeginTable("resultTable", column_count) then
                    local c_width = 0.6 / (column_count - 1);
                    imgui.TableSetupColumn("Name", 16, 0.4);
                    imgui.TableSetupColumn("Hook", 16, c_width);
                    if gSettings.showColumns.Up[1]    then imgui.TableSetupColumn("Up", 16, c_width); end
                    if gSettings.showColumns.Lose[1]  then imgui.TableSetupColumn("Lose", 16, c_width); end
                    if gSettings.showColumns.Snap[1]  then imgui.TableSetupColumn("Snap", 16, c_width); end
                    if gSettings.showColumns.Break[1] then imgui.TableSetupColumn("Break", 16, c_width); end
                    if gSettings.showColumns.Pool[1]  then imgui.TableSetupColumn("Pool", 16, c_width); end
                    if gSettings.showColumns.Rate[1]  then imgui.TableSetupColumn("Rate", 16, c_width); end
                    imgui.TableHeadersRow();
                    for _, entry in pairs(gui_variables.fishChances) do
                        imgui.TableNextRow();
                        imgui.TableSetColumnIndex(0);
                        imgui.Text(string.format("%s", entry[2]));
                        imgui.TableSetColumnIndex(1);
                        imgui.Text(string.format("%.1f", entry[1]));
                        if gSettings.showColumns.Up[1] then
                            imgui.TableNextColumn();
                            imgui.Text(string.format("%.1f", entry[8]));
                        end
                        if gSettings.showColumns.Lose[1] then
                            imgui.TableNextColumn();
                            imgui.Text(string.format("%.1f", entry[5]));
                        end
                        if gSettings.showColumns.Snap[1] then
                            imgui.TableNextColumn();
                            imgui.Text(string.format("%.1f", entry[6]));
                        end
                        if gSettings.showColumns.Break[1] then
                            imgui.TableNextColumn();
                            imgui.Text(string.format("%.1f", entry[7]));
                        end
                        if gSettings.showColumns.Pool[1] then
                            imgui.TableNextColumn();
                            imgui.Text(string.format("%d", entry[3]));
                        end
                        if gSettings.showColumns.Rate[1] then
                            imgui.TableNextColumn();
                            imgui.Text(string.format("%d", entry[4]));
                        end
                    end
                    imgui.TableNextRow();
                    imgui.TableSetColumnIndex(0);
                    imgui.Text("Item");
                    imgui.TableSetColumnIndex(1);
                    imgui.Text(string.format("%.1f", gui_variables.itemChance));
                    imgui.TableNextRow();
                    imgui.TableSetColumnIndex(0);
                    imgui.Text("Mob");
                    imgui.TableSetColumnIndex(1);
                    imgui.Text(string.format("%.1f", gui_variables.mobChance));
                    imgui.TableNextRow();
                    imgui.TableSetColumnIndex(0);
                    imgui.Text("No Catch");
                    imgui.TableSetColumnIndex(1);
                    imgui.Text(string.format("%.1f", gui_variables.noChance));

                    imgui.EndTable();
                end
            end
            --imgui.Text(string.format("h:%d p:%d m:%d", astrology.hour, astrology.phase, astrology.month));
            --imgui.Text(string.format("x:%.2f y:%.2f z:%.2f", posX, posY, posZ));
            imgui.End();
        else
            imgui.End();
        end
        
        -- Conditionally draw Go Fish Config ImGui Window
        if gSettings.showConfig[1] then
            imgui.SetNextWindowSize(default_config.config_window.dimensions, ImGuiCond_FirstUseEver);
            imgui.SetNextWindowPos(default_config.config_window.position, ImGuiCond_FirstUseEver);
            if imgui.Begin("Go Fish Config", gSettings.showConfig) then  
                imgui.Checkbox("Show Skillup Chance", gSettings.showColumns.Up);
                imgui.Checkbox("Show Catch Lose Chance", gSettings.showColumns.Lose);
                imgui.Checkbox("Show Line Snap Chance", gSettings.showColumns.Snap);
                imgui.Checkbox("Show Rod Break Chance", gSettings.showColumns.Break);
                imgui.Checkbox("Show Pool Size", gSettings.showColumns.Pool);
                imgui.Checkbox("Show Restock Rate", gSettings.showColumns.Rate);
                imgui.PushItemWidth(36);
                imgui.InputText("##multi", gSettings.skillupmul, 4, ImGuiInputTextFlags_CharsDecimal);
                imgui.PopItemWidth()
                imgui.SameLine();
                imgui.Text("Skillup Chance Multi");
                imgui.End();
            else
                imgui.End();
            end
        end
        
        -- Conditionally draw Go Fish Config ImGui Window
        if not gSettings.hideEula[1] then
            imgui.SetNextWindowSize(default_config.eula_window.dimensions, ImGuiCond_FirstUseEver);
            imgui.SetNextWindowPos(default_config.eula_window.position, ImGuiCond_FirstUseEver);
            if imgui.Begin("Go Fish EULA", gSettings.showConfig) then  
                imgui.Text(eula_literal);
                imgui.Checkbox("Do not show again", gSettings.hideEula); 
                imgui.End();
            else
                imgui.End();
            end
        end
    end
    
    -- Pop all the Imgui Style Color data off the stack
    for _, _ in pairs(addonStyle) do
        imgui.PopStyleColor();
    end
end);