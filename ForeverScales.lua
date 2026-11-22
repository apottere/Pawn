-- Pawn by Vger-Azjol-Nerub
-- www.vgermods.com
-- © 2006-2026 Travis Spomer.  This mod is released under the Creative Commons Attribution-NonCommercial-NoDerivs 3.0 license.
-- See Readme.md for more information.
--
-- WoW Forever scales
-- Weights from Pawn Forever 1.2.0 (https://github.com/turlockmike/pawn-forever, MIT license), which converts the Forever
-- weight tables in GearQuest Forever by weber8210 to Pawn's units, with these changes:
--	Druid Restoration: Spirit is 0.35 times Mp5.  With Forever's 50% Reflection, a point of Spirit is worth about 0.25 Mp5
--		while casting and 0.5 Mp5 while not.
--	Shaman Elemental: Fire spell damage is 0.3 and Nature 0.65 (from 0.08 and 0.8), since Forever's Lava Burst and Flame Shock
--		make Fire a large share of Elemental damage.
--	Shaman Enhancement: Agility is 0.6 (from 1).  Shamans get no attack power from Agility, only about 1% crit per 20 Agility
--		and 2 armor per point.  Haste is 10 (from 5.5), close to crit, since Flurry makes attack speed worth about as much.
-- There are no leveling scales: GearQuest's leveling weights multiply the same few stats for every class and spec by
-- fixed amounts that aren't based on anything in Forever.
------------------------------------------------------------

local ScaleProviderName = "Forever"

function PawnForeverScaleProvider_AddScales()
	if not VgerCore.IsForever then return end

	-- These scales get a spec's icon and the class color, but not the class and spec IDs: those would show the spec's
	-- name in tooltips instead of each scale's, and turn these scales on for new characters along with the starter scales.
	-- Items the class can't use are marked unusable, the same as Pawn's built-in scales for that class.
	local function AddScale(ClassID, ClassToken, ScaleInternalName, LocalizedName, SpecID, ResistValue, Stats)
		local Values = PawnGetStatValuesForTemplate(PawnFindScaleTemplate(ClassID), true) -- unusable items only
		for StatName, Value in pairs(Stats) do Values[StatName] = Value end
		for _, StatName in pairs({ "ArcaneResist", "FireResist", "FrostResist", "NatureResist", "ShadowResist" }) do Values[StatName] = ResistValue end

		local Color
		local ClassColor = RAID_CLASS_COLORS[ClassToken]
		if ClassColor and ClassColor.colorStr then Color = strsub(ClassColor.colorStr, 3) end
		PawnAddPluginScale(ScaleProviderName, ScaleInternalName, LocalizedName, Color, Values)
		local NewScale = PawnCommon.Scales[PawnGetProviderScaleName(ScaleProviderName, ScaleInternalName)]
		if NewScale then
			local _
			_, _, _, NewScale.IconTexturePath = PawnGetSpecializationInfoForClassID(ClassID, SpecID)
		end
	end

	-- Druid
	AddScale(11, "DRUID", "DruidCat", "Druid: Cat", 2, 0.03,
		{ Agility = 1, Strength = 0.7, MeleeDps = 4.9, Ap = 0.35, FeralAp = 0.35, CritRating = 11.9, HitRating = 13, ExpertiseRating = 13, HasteRating = 6,
		Stamina = 0.12, Armor = 0.006, DodgeRating = 1.2, DefenseRating = 0.02, Hp5 = 0.05, Intellect = 0.03, Mp5 = 0.02, Spirit = 0.01 })

	AddScale(11, "DRUID", "DruidBear", "Druid: Bear", 3, 0.03,
		{ Stamina = 1, Agility = 0.55, Strength = 0.35, MeleeDps = 4.9, Ap = 0.18, FeralAp = 0.18, Armor = 0.1, DefenseRating = 0.85, DodgeRating = 8.4,
		HitRating = 4, CritRating = 3.5, ExpertiseRating = 6, HasteRating = 1, Hp5 = 0.05, Intellect = 0.05, Mp5 = 0.05, Spirit = 0.02 })

	AddScale(11, "DRUID", "DruidRestoration", "Druid: Restoration", 4, 0.03,
		{ Healing = 1, SpellDamage = 0.3, Intellect = 0.55, Spirit = 0.77, Mp5 = 2.2, CritRating = 4.9, HasteRating = 4,
		Stamina = 0.08, Armor = 0.004, Agility = 0.05, DodgeRating = 0.6, DefenseRating = 0.02, Hp5 = 0.05 })

	-- Shaman
	AddScale(7, "SHAMAN", "ShamanElemental", "Shaman: Elemental", 1, 0.02,
		{ SpellDamage = 1, NatureSpellDamage = 0.65, FireSpellDamage = 0.3, FrostSpellDamage = 0.05, Intellect = 0.45, Spirit = 0.1, Mp5 = 0.35,
		CritRating = 10.5, HitRating = 12.5, HasteRating = 6, Stamina = 0.1, Armor = 0.005, DodgeRating = 0.6, ParryRating = 0.3, DefenseRating = 0.02, Hp5 = 0.02 })

	AddScale(7, "SHAMAN", "ShamanEnhancement", "Shaman: Enhancement", 2, 0.02,
		{ Strength = 1.1, Agility = 0.6, Ap = 0.55, Intellect = 0.7, MeleeDps = 18, CritRating = 11.9, HitRating = 14, ExpertiseRating = 14, HasteRating = 10,
		SpellDamage = 0.2, Healing = 0.05, Stamina = 0.15, Armor = 0.005, DodgeRating = 0.6, ParryRating = 0.3, DefenseRating = 0.02, Hp5 = 0.02, Mp5 = 0.05 })

	AddScale(7, "SHAMAN", "ShamanRestoration", "Shaman: Restoration", 3, 0.02,
		{ Healing = 1, SpellDamage = 0.3, Intellect = 0.55, Spirit = 0.35, Mp5 = 2.1, CritRating = 4.9, HasteRating = 4,
		Stamina = 0.1, Armor = 0.005, DodgeRating = 0.6, ParryRating = 0.3, DefenseRating = 0.02, Hp5 = 0.02 })

	-- After this function terminates there's no need for it anymore, so cause it to self-destruct to save memory.
	PawnForeverScaleProvider_AddScales = nil

end -- PawnForeverScaleProvider_AddScales

------------------------------------------------------------

-- Initiate self-destruct sequence.
PawnAddPluginScaleProvider(ScaleProviderName, PawnLocal.UI.ForeverProvider, PawnForeverScaleProvider_AddScales)
PawnForeverScaleProvider_AddScales = nil
