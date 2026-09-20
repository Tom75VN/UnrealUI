# Talent Advisor data

The bundled catalog targets the original World of Warcraft 1.12.1 talent system (client build 5875). It stores exact rank digits per canonical talent tree; tree totals are display metadata only and never drive highlights.

## Validation sources

- The client remains authoritative for localized talent names, current ranks, rank caps, prerequisites, tab order, and whether a point is currently learnable.
- Vanilla tree order and tree sizes were cross-checked against maladr0it/classic-talent-calculator; the live client remains authoritative for rank caps.
- Build endpoints were transcribed from the supplied TalentAdvisorBuilds_1121.lua, preserved Legacy-WoW calculators, and the linked Classic guides below. Calculator codes were normalized into one string per canonical tree.
- The Priest leveling endpoint preserves the supplied guide's Spirit Tap / Wand Specialization opening sequence; other endpoints use their primary tree first and always defer to the live prerequisite result.
- The advisor rejects a build at runtime if a client tree has a different talent count, a stored digit exceeds the live maximum rank, or the class/tree identity cannot be resolved.

## Guide references

- https://legacy-wow.com/vanilla-priest/
- https://legacy-wow.com/warlock-leveling-guide-1-60/
- https://legacy-wow.com/vanilla-shaman-guide/
- https://legacy-wow.com/vanilla-fury-warrior-guide/
- https://www.wowhead.com/classic/guide/classes/warrior/fury/dps-talent-builds-pve
- https://www.wowhead.com/classic/guide/classes/priest/healer-talent-builds-pve
- https://www.wowhead.com/classic/guide/classes/shaman/healer-talent-builds-pve
- https://www.wowhead.com/classic/guide/classes/warlock/dps-talent-builds-pve
- https://www.wowhead.com/classic/guide/classes/paladin/dps-talent-builds-pve
- https://www.wowhead.com/classic/guide/classes/hunter/beast-mastery/leveling-tips

The catalog intentionally excludes Season of Discovery runes, Burning Crusade talents, Turtle/custom-server talents, and modern retail talent systems.
