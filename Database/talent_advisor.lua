local U = UnrealUI

U.TalentAdvisorBuilds = {
  schemaVersion = 2,
  clientBuild = 5875,
  contexts = { "LEVELING", "PVP", "RAID" },
  classRoles = {
    WARRIOR = { "DPS", "TANK" },
    DRUID = { "DPS", "TANK", "HEALER", "HYBRID" },
    HUNTER = { "DPS" },
    MAGE = { "DPS" },
    PALADIN = { "DPS", "TANK", "HEALER", "HYBRID" },
    PRIEST = { "DPS", "HEALER" },
    ROGUE = { "DPS" },
    SHAMAN = { "DPS", "HEALER", "HYBRID" },
    WARLOCK = { "DPS" },
  },
  trees = {
    WARRIOR = { { "WarriorArms", 18 }, { "WarriorFury", 17 }, { "WarriorProtection", 17 } },
    DRUID = { { "DruidBalance", 16 }, { "DruidFeralCombat", 16 }, { "DruidRestoration", 15 } },
    HUNTER = { { "HunterBeastMastery", 16 }, { "HunterMarksmanship", 14 }, { "HunterSurvival", 16 } },
    MAGE = { { "MageArcane", 16 }, { "MageFire", 16 }, { "MageFrost", 17 } },
    PALADIN = { { "PaladinHoly", 14 }, { "PaladinProtection", 15 }, { "PaladinCombat", 15 } },
    PRIEST = { { "PriestDiscipline", 15 }, { "PriestHoly", 16 }, { "PriestShadow", 16 } },
    ROGUE = { { "RogueAssassination", 15 }, { "RogueCombat", 19 }, { "RogueSubtlety", 17 } },
    SHAMAN = { { "ShamanElementalCombat", 15 }, { "ShamanEnhancement", 16 }, { "ShamanRestoration", 15 } },
    WARLOCK = { { "WarlockCurses", 17 }, { "WarlockSummoning", 17 }, { "WarlockDestruction", 16 } },
  },
  builds = {
    WARRIOR = {
      ARMS = { label = "TA_BUILD_ARMS", split = "31/20/0", primary = 1, codes = { "313050203525100001", "05050104005", "" } },
      FURY = { label = "TA_BUILD_FURY", split = "17/34/0", primary = 2, codes = { "02305020302", "05050025005510051", "" } },
      PROTECTION = { label = "TA_BUILD_PROTECTION", split = "5/13/33", primary = 3, codes = { "05", "0505003", "55050033500001051" } },
    },
    DRUID = {
      FERAL = { label = "TA_BUILD_FERAL", split = "11/35/5", primary = 2, codes = { "014005001", "5050301323222151", "05" } },
      HOTW = { label = "TA_BUILD_HOTW_NS", split = "1/29/21", primary = 2, codes = { "01", "503202130321214", "05550311001" } },
      BALANCE = { label = "TA_BUILD_BALANCE_NS", split = "30/0/21", primary = 1, codes = { "510050300250135", "", "05530310031" } },
      MOONGLOW = { label = "TA_BUILD_MOONGLOW", split = "24/0/27", primary = 3, codes = { "4100500302501300", "", "505003125203010" } },
      RESTORATION = { label = "TA_BUILD_RESTORATION", split = "5/0/46", primary = 3, codes = { "014", "", "505503155315251" } },
    },
    HUNTER = {
      BEAST_MASTERY = { label = "TA_BUILD_BEAST_MASTERY", split = "31/20/0", primary = 1, codes = { "2500300050521251", "051510305", "" } },
      MARKSMAN = { label = "TA_BUILD_MARKSMAN", split = "11/34/6", primary = 2, codes = { "500500001", "05551030513051", "33" } },
      MARKSMAN_PVP = { label = "TA_BUILD_MARKSMAN_SURVIVAL", split = "0/31/20", primary = 2, codes = { "", "25051030513051", "032520201032" } },
    },
    MAGE = {
      FROST = { label = "TA_BUILD_FROST", split = "17/0/34", primary = 3, codes = { "2030052210200000", "", "05053231122051301" } },
      POM_FIRE = { label = "TA_BUILD_POM_FIRE", split = "21/30/0", primary = 2, codes = { "2030052210231000", "5042320122003150", "" } },
      AP_FROST = { label = "TA_BUILD_AP_FROST", split = "31/0/20", primary = 1, codes = { "2300550010231531", "", "053500030013" } },
      WINTERS_CHILL = { label = "TA_BUILD_WINTERS_CHILL", split = "19/0/32", primary = 3, codes = { "230045200003", "", "05350023022301051" } },
      FIRE = { label = "TA_BUILD_FIRE", split = "17/31/3", primary = 2, codes = { "230035200002", "5052020023033051", "003" } },
    },
    PALADIN = {
      RETRIBUTION = { label = "TA_BUILD_RETRIBUTION", split = "0/18/33", primary = 3, codes = { "", "503041005", "552050500203051" } },
      HOLY_PVP = { label = "TA_BUILD_HOLY_PVP", split = "31/20/0", primary = 1, codes = { "05503122511051", "05024103023", "" } },
      HOLY = { label = "TA_BUILD_HOLY", split = "32/14/5", primary = 1, codes = { "05503002521351", "500051003", "5" } },
      PROTECTION = { label = "TA_BUILD_PROTECTION", split = "0/37/14", primary = 2, codes = { "", "053051335001551", "05005301" } },
      HOLY_RETRIBUTION = { label = "TA_BUILD_HOLY_RETRIBUTION", split = "30/0/21", primary = 1, codes = { "54500120521050", "", "0523205120001" } },
    },
    PRIEST = {
      SHADOW_LEVELING = { label = "TA_BUILD_SHADOW_LEVELING", split = "20/0/31", primary = 3, codes = { "1502301332", "", "5302520100511051" }, sequence = { "3:1", "1:2", "3:1", "1:2", "3:1", "1:2", "3:1", "1:2", "3:1", "1:2" } },
      SHADOW = { label = "TA_BUILD_SHADOW", split = "13/0/38", primary = 3, codes = { "50500003", "", "5030505123501251" } },
      HOLY = { label = "TA_BUILD_HOLY", split = "18/33/0", primary = 2, codes = { "50523003", "2350500303001551", "" } },
      DISCIPLINE = { label = "TA_BUILD_DISCIPLINE", split = "33/18/0", primary = 1, codes = { "500232130515051", "2150511003", "" } },
    },
    ROGUE = {
      COMBAT_LEVELING = { label = "TA_BUILD_COMBAT_SWORDS", split = "19/32/0", primary = 2, codes = { "005323105", "0230152020050150231", "" } },
      HEMORRHAGE = { label = "TA_BUILD_HEMORRHAGE", split = "21/3/27", primary = 3, codes = { "305320115001", "3", "500243100332121" } },
      COMBAT_SWORDS = { label = "TA_BUILD_COMBAT_SWORDS", split = "19/32/0", primary = 2, codes = { "00502310503", "0230152020050150231", "" } },
      COMBAT_DAGGERS = { label = "TA_BUILD_COMBAT_DAGGERS", split = "15/31/5", primary = 2, codes = { "005023104", "0233052020550100201", "05" } },
    },
    SHAMAN = {
      ENHANCEMENT = { label = "TA_BUILD_ENHANCEMENT", split = "0/30/21", primary = 2, codes = { "", "050503210500315", "0510535100001" } },
      ELEMENTAL = { label = "TA_BUILD_ELEMENTAL_NS", split = "30/0/21", primary = 1, codes = { "55020155000115", "", "5500200030501" } },
      RESTORATION = { label = "TA_BUILD_RESTORATION", split = "0/5/46", primary = 3, codes = { "", "5", "551353013553151" } },
      ENH_RESTO = { label = "TA_BUILD_ENH_RESTO", split = "0/20/31", primary = 3, codes = { "", "5005202105", "050350011550051" } },
    },
    WARLOCK = {
      AFFLICTION = { label = "TA_BUILD_AFFLICTION", split = "30/21/0", primary = 1, codes = { "55022032122010050", "2050340100501", "" } },
      SOUL_LINK = { label = "TA_BUILD_SOUL_LINK", split = "9/31/11", primary = 2, codes = { "25002", "2050310152501051", "50500001" } },
      DS_RUIN = { label = "TA_BUILD_DS_RUIN", split = "9/21/21", primary = 2, codes = { "25002", "2350300142001", "52500051020001" } },
      SM_RUIN = { label = "TA_BUILD_SM_RUIN", split = "30/0/21", primary = 1, codes = { "5500200512201115", "", "52500051020001" } },
    },
  },
  catalog = {
    WARRIOR = {
      LEVELING = { DPS = { "ARMS" }, TANK = { "ARMS" } },
      PVP = { DPS = { "ARMS" }, TANK = { "PROTECTION", "ARMS" } },
      RAID = { DPS = { "FURY", "ARMS" }, TANK = { "PROTECTION" } },
    },
    DRUID = {
      LEVELING = { DPS = { "FERAL", "BALANCE" }, TANK = { "FERAL" }, HEALER = { "HOTW", "MOONGLOW" }, HYBRID = { "HOTW" } },
      PVP = { DPS = { "HOTW", "BALANCE" }, TANK = { "HOTW" }, HEALER = { "HOTW", "MOONGLOW" }, HYBRID = { "HOTW", "BALANCE" } },
      RAID = { DPS = { "FERAL", "BALANCE" }, TANK = { "FERAL" }, HEALER = { "RESTORATION", "MOONGLOW" }, HYBRID = { "MOONGLOW", "HOTW" } },
    },
    HUNTER = {
      LEVELING = { DPS = { "BEAST_MASTERY" } },
      PVP = { DPS = { "MARKSMAN_PVP", "BEAST_MASTERY" } },
      RAID = { DPS = { "MARKSMAN", "MARKSMAN_PVP" } },
    },
    MAGE = {
      LEVELING = { DPS = { "FROST", "POM_FIRE" } },
      PVP = { DPS = { "FROST", "POM_FIRE", "AP_FROST" } },
      RAID = { DPS = { "WINTERS_CHILL", "FROST", "FIRE" } },
    },
    PALADIN = {
      LEVELING = { DPS = { "RETRIBUTION" }, TANK = { "PROTECTION", "RETRIBUTION" }, HEALER = { "HOLY_RETRIBUTION", "HOLY" }, HYBRID = { "HOLY_RETRIBUTION", "RETRIBUTION" } },
      PVP = { DPS = { "RETRIBUTION" }, TANK = { "PROTECTION", "HOLY_PVP" }, HEALER = { "HOLY_PVP" }, HYBRID = { "HOLY_RETRIBUTION", "HOLY_PVP" } },
      RAID = { DPS = { "RETRIBUTION" }, TANK = { "PROTECTION" }, HEALER = { "HOLY", "HOLY_RETRIBUTION" }, HYBRID = { "HOLY_RETRIBUTION", "HOLY" } },
    },
    PRIEST = {
      LEVELING = { DPS = { "SHADOW_LEVELING" }, HEALER = { "HOLY", "SHADOW_LEVELING" } },
      PVP = { DPS = { "SHADOW" }, HEALER = { "DISCIPLINE", "HOLY" } },
      RAID = { DPS = { "SHADOW" }, HEALER = { "HOLY", "DISCIPLINE" } },
    },
    ROGUE = {
      LEVELING = { DPS = { "COMBAT_LEVELING" } },
      PVP = { DPS = { "HEMORRHAGE", "COMBAT_SWORDS" } },
      RAID = { DPS = { "COMBAT_SWORDS", "COMBAT_DAGGERS" } },
    },
    SHAMAN = {
      LEVELING = { DPS = { "ENHANCEMENT", "ELEMENTAL" }, HEALER = { "ENH_RESTO", "RESTORATION" }, HYBRID = { "ENH_RESTO", "ELEMENTAL" } },
      PVP = { DPS = { "ELEMENTAL", "ENHANCEMENT" }, HEALER = { "ELEMENTAL", "RESTORATION" }, HYBRID = { "ELEMENTAL", "ENH_RESTO" } },
      RAID = { DPS = { "ELEMENTAL", "ENHANCEMENT" }, HEALER = { "RESTORATION", "ENH_RESTO" }, HYBRID = { "ENH_RESTO", "ELEMENTAL" } },
    },
    WARLOCK = {
      LEVELING = { DPS = { "AFFLICTION" } },
      PVP = { DPS = { "SOUL_LINK", "SM_RUIN" } },
      RAID = { DPS = { "DS_RUIN", "SM_RUIN" } },
    },
  },
}
