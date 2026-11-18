-- Pawn by Vger-Azjol-Nerub
-- www.vgermods.com
-- © 2006-2026 Travis Spomer.  This mod is released under the Creative Commons Attribution-NonCommercial-NoDerivs 3.0 license.
-- See Readme.md for more information.
--
-- WoW Forever scales
-- Druid weights from Pawn Forever 1.2.0 (https://github.com/turlockmike/pawn-forever, MIT license), which converts the
-- Forever weight tables in GearQuest Forever by weber8210 to Pawn's units.  Restoration Spirit is set to 0.35 times Mp5:
-- with Forever's 50% Reflection, a point of Spirit is worth about 0.25 Mp5 while casting and 0.5 Mp5 while not.
-- There are no leveling scales: GearQuest's leveling weights multiply the same few stats for every class and spec by
-- fixed amounts that aren't based on anything in Forever.
------------------------------------------------------------

local ScaleProviderName = "Forever"

function PawnForeverScaleProvider_AddScales()
	if not VgerCore.IsForever then return end

	-- Druids can't use these, the same as Pawn's built-in druid scales.
	local function DruidValues(Stats)
		local Values = PawnGetStatValuesForTemplate(PawnFindScaleTemplate(11), true) -- unusable items only
		for StatName, Value in pairs(Stats) do Values[StatName] = Value end
		return Values
	end

	-- These scales get a druid spec's icon, but not its class and spec IDs: those would show the spec's name in tooltips
	-- instead of each scale's, and turn these scales on for new druids along with the starter scales.
	local function AddDruidScale(ScaleInternalName, LocalizedName, SpecID, Stats)
		local Color
		if RAID_CLASS_COLORS.DRUID and RAID_CLASS_COLORS.DRUID.colorStr then Color = strsub(RAID_CLASS_COLORS.DRUID.colorStr, 3) end
		PawnAddPluginScale(ScaleProviderName, ScaleInternalName, LocalizedName, Color, DruidValues(Stats))
		local NewScale = PawnCommon.Scales[PawnGetProviderScaleName(ScaleProviderName, ScaleInternalName)]
		if NewScale then
			local _
			_, _, _, NewScale.IconTexturePath = PawnGetSpecializationInfoForClassID(11, SpecID)
		end
	end

	local Resists = { ArcaneResist = 0.03, FireResist = 0.03, FrostResist = 0.03, NatureResist = 0.03, ShadowResist = 0.03 }
	local function WithResists(Stats)
		for StatName, Value in pairs(Resists) do Stats[StatName] = Value end
		return Stats
	end

	AddDruidScale("DruidCat", "Druid: Cat", 2, WithResists(
		{ Agility = 1, Strength = 0.7, MeleeDps = 4.9, Ap = 0.35, FeralAp = 0.35, CritRating = 11.9, HitRating = 13, ExpertiseRating = 13, HasteRating = 6,
		Stamina = 0.12, Armor = 0.006, DodgeRating = 1.2, DefenseRating = 0.02, Hp5 = 0.05, Intellect = 0.03, Mp5 = 0.02, Spirit = 0.01 }
	))

	AddDruidScale("DruidBear", "Druid: Bear", 3, WithResists(
		{ Stamina = 1, Agility = 0.55, Strength = 0.35, MeleeDps = 4.9, Ap = 0.18, FeralAp = 0.18, Armor = 0.1, DefenseRating = 0.85, DodgeRating = 8.4,
		HitRating = 4, CritRating = 3.5, ExpertiseRating = 6, HasteRating = 1, Hp5 = 0.05, Intellect = 0.05, Mp5 = 0.05, Spirit = 0.02 }
	))

	AddDruidScale("DruidRestoration", "Druid: Restoration", 4, WithResists(
		{ Healing = 1, SpellDamage = 0.3, Intellect = 0.55, Spirit = 0.77, Mp5 = 2.2, CritRating = 4.9, HasteRating = 4,
		Stamina = 0.08, Armor = 0.004, Agility = 0.05, DodgeRating = 0.6, DefenseRating = 0.02, Hp5 = 0.05 }
	))

	-- After this function terminates there's no need for it anymore, so cause it to self-destruct to save memory.
	PawnForeverScaleProvider_AddScales = nil

end -- PawnForeverScaleProvider_AddScales

------------------------------------------------------------

-- Initiate self-destruct sequence.
PawnAddPluginScaleProvider(ScaleProviderName, PawnLocal.UI.ForeverProvider, PawnForeverScaleProvider_AddScales)
PawnForeverScaleProvider_AddScales = nil
