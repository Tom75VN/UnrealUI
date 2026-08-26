-- unrealUI :: core/locale.lua
--
-- The addon's translation layer: a key -> text lookup with a fixed English
-- fallback, and the language selection that drives it.
--
-- This is deliberately not a locale framework. There is no runtime string
-- extraction, no per-module registry and no automatic client-locale mapping:
-- locales/*.lua register one flat table each, every UI string is fetched
-- through U.L at build time, and the selected language is one short identifier
-- in the profile store.
--
-- Client locale is NOT the default. environment.json / calls/GetLocale
-- returned "enUS" on this installation, and the client documentation lists the
-- other WoW locale tokens as possible returns, but the addon's language is a
-- user preference that has to survive playing an enUS client in French.
-- English is therefore the install default, and GetLocale is consulted only as
-- a first-run hint (see U.LoadLanguage).
--
-- knowledge.json / config.savedvariables_backslash_corruption: the stored
-- value is a four-letter code validated against the known list before it is
-- used, so a mangled or hand-edited saved file falls back to English rather
-- than reaching a lookup as a corrupt key.
--
-- knowledge.json / fonts.setfont_silent_failure (RUNTIME_FAILURE_CONFIRMED):
-- addon-bundled TTFs do not load on this client, so every translated string is
-- drawn by the inherited native FontObject. Whether Cyrillic and CJK glyphs
-- render at all is a property of the client's own font and is not something
-- this addon can fix by shipping one. The selector stays legible in every
-- language because its choices use flags (with an ASCII fallback for any
-- locale without artwork), so a player who sees missing glyphs can always
-- find their way back.
--
-- Encoding: locales/*.lua are UTF-8 without a BOM. The client counts EditBox
-- limits in UTF-8 bytes (documentation.json / EditBox:SetMaxBytes), so the
-- string type is byte-oriented UTF-8 as expected. Never use string.len or
-- string.sub to trim a translated string for display: on any non-ASCII
-- language that cuts a multi-byte character in half.

local U = UnrealUI

local DEFAULT_LANGUAGE = "enUS"

-- Ordered for the selector in modules/settings.lua. `short` is the two-letter
-- fallback drawn when flag artwork is unavailable; `label` is the language's
-- own name, which is what a player looking for their language scans for.
U.languages = {
  { code = "enUS", short = "EN", label = "English" },
  { code = "zhCN", short = "CN", label = "简体中文" },
  { code = "ruRU", short = "RU", label = "Русский" },
  { code = "frFR", short = "FR", label = "Français" },
}

local languageByCode = {}
local languageIndex
for languageIndex = 1, table.getn(U.languages) do
  local entry = U.languages[languageIndex]
  entry.index = languageIndex
  languageByCode[entry.code] = entry
end

-- code -> { key = text }. locales/*.lua fill these at file load; nothing here
-- runs before they do.
local strings = {}
-- code -> function(n) -> plural form name. Only a locale whose plural rules
-- differ from "one / other" needs to register one.
local plurals = {}

local active = DEFAULT_LANGUAGE
local activeStrings
local fallbackStrings

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

-- Called once per file in locales/. Merging rather than assigning means a
-- language can be split across several files later without changing callers.
function U.RegisterLocale(code, entries)
  if not languageByCode[code] then
    U.Error("unknown locale: " .. tostring(code))
    return
  end
  if type(entries) ~= "table" then return end

  local target = strings[code]
  if not target then
    target = {}
    strings[code] = target
  end

  local key, text
  for key, text in pairs(entries) do
    if type(key) == "string" and type(text) == "string" then
      target[key] = text
    end
  end

  if code == DEFAULT_LANGUAGE then fallbackStrings = target end
  if code == active then activeStrings = target end
end

-- selector(n) must return one of the form names used as a key suffix:
-- "ONE", "FEW", "MANY" or "OTHER". A locale without one gets the English rule.
function U.RegisterLocalePlural(code, selector)
  if languageByCode[code] and type(selector) == "function" then
    plurals[code] = selector
  end
end

local function EnglishPlural(n)
  if n == 1 then return "ONE" end
  return "OTHER"
end

-- ---------------------------------------------------------------------------
-- Lookup
-- ---------------------------------------------------------------------------

-- A missing key returns the key itself. That is deliberate: an untranslated
-- string then shows up in game as a visible upper-case identifier instead of
-- an empty label, which is the failure mode that is actually findable.
local function Resolve(key)
  if type(key) ~= "string" then return "" end
  if activeStrings then
    local text = activeStrings[key]
    if text then return text end
  end
  if fallbackStrings then
    local text = fallbackStrings[key]
    if text then return text end
  end
  return key
end

-- U.L("KEY")        -> the translated string
-- U.L("KEY", a, b)  -> string.format of it with those arguments
--
-- The format call is guarded because the pattern comes from a translation
-- file: a translator dropping a %s must not take a settings page down with it.
-- On a bad pattern the unformatted string is shown, which is wrong but legible.
function U.L(key, a, b, c, d)
  local text = Resolve(key)
  if a == nil then return text end

  local ok, formatted = pcall(string.format, text, a, b, c, d)
  if ok and type(formatted) == "string" then return formatted end
  return text
end

-- Plural form of a counted string. The catalog holds one key per form,
-- suffixed "_ONE" / "_FEW" / "_MANY" / "_OTHER"; only the forms a language
-- actually uses need to exist, and the count is passed to the format as %d.
function U.LN(key, n, a, b)
  local count = tonumber(n) or 0
  local selector = plurals[active] or EnglishPlural
  local ok, form = pcall(selector, count)
  if not ok or type(form) ~= "string" then form = EnglishPlural(count) end

  -- Fall through to the general form before giving up, so a locale that
  -- defines only _OTHER still renders instead of showing a raw key.
  local suffixed = key .. "_" .. form
  if Resolve(suffixed) == suffixed then suffixed = key .. "_OTHER" end

  if a == nil then return U.L(suffixed, count) end
  return U.L(suffixed, count, a, b)
end

-- ---------------------------------------------------------------------------
-- Selection
-- ---------------------------------------------------------------------------
function U.GetLanguages()
  return U.languages
end

function U.GetLanguage()
  return active
end

function U.GetLanguageLabel(code)
  local entry = languageByCode[code or active]
  return entry and entry.label or tostring(code)
end

function U.IsValidLanguage(code)
  return languageByCode[code] ~= nil
end

local function Activate(code)
  active = code
  activeStrings = strings[code]
  fallbackStrings = strings[DEFAULT_LANGUAGE]
end

-- Persists the choice and points the lookup at the new table. Text already on
-- screen is not retranslated: every UnrealUI label is written once when its
-- page or frame is built, so the caller (modules/settings.lua) asks for a
-- /reload, exactly as core/theme.lua does for a theme change.
--
-- Returns true when the language actually changed.
function U.SetLanguage(code)
  if not languageByCode[code] then return false end
  if code == active then return false end

  Activate(code)
  U.StoreLanguage(code)   -- core/config.lua
  return true
end

-- Applied from core/init.lua's Initialise, after U.LoadConfig has run and
-- before any module builds UI. Nothing in the addon may call U.L at file
-- scope: at file-load time the saved language is not known yet, so every such
-- lookup would answer in English for the rest of the session.
function U.LoadLanguage()
  local stored = U.StoredLanguage()   -- core/config.lua
  if languageByCode[stored] then
    Activate(stored)
    return active
  end

  -- First run on this installation. English is the documented default; a
  -- client already running in one of the addon's other languages is a better
  -- opening guess than English, and the player can still change it.
  local code = DEFAULT_LANGUAGE
  local getLocale = U.G("GetLocale")
  if type(getLocale) == "function" then
    local ok, clientLocale = pcall(getLocale)
    if ok and languageByCode[clientLocale] then code = clientLocale end
  end

  Activate(code)
  U.StoreLanguage(code)
  return active
end

Activate(DEFAULT_LANGUAGE)
