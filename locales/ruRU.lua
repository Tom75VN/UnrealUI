-- unrealUI :: locales/ruRU.lua
--
-- Russian. See locales/enUS.lua for the catalog and the rules every locale
-- file follows (UTF-8 without BOM, placeholders kept in order, colour escapes
-- kept paired, slash commands never translated).
--
-- Russian is the reason core/locale.lua carries U.LN rather than a single
-- "one / other" pair: a counted noun takes three different forms, and the
-- form depends on the last one or two digits, not on whether the count is 1.

UnrealUI.RegisterLocale("ruRU", {

-- ---------------------------------------------------------------------------
-- Shared controls
-- ---------------------------------------------------------------------------
COMMON_OK                 = "Хорошо",
COMMON_OK_SHORT           = "ОК",
COMMON_CANCEL             = "Отмена",
COMMON_ACCEPT             = "Принять",
COMMON_CLOSE              = "Закрыть",
COMMON_SAVE               = "Сохранить",
COMMON_DELETE             = "Удалить",
COMMON_ENABLE             = "Включить",
COMMON_ARE_YOU_SURE       = "Вы уверены?",
COMMON_CANNOT_BE_UNDONE   = "Это действие нельзя отменить.",
COMMON_SELECT_COLOUR      = "Выбор цвета",
COMMON_COST               = "Цена:",
COMMON_SELL               = "Продажа:",
LOADING_TITLE             = "Подготовка UnrealUI",
LOADING_CLIENT_LIMITATION = "Загрузка нужна из-за ограничений  клиента. Чтобы избежать зависаний во время игры.",
LOADING_FPS_DEPENDENT     = "Длительность зависит от FPS. Будет убрано в будущем обновлении клиента.",

-- ---------------------------------------------------------------------------
-- Edit mode
-- ---------------------------------------------------------------------------
MOVER_TITLE               = "Редактор интерфейса",
MOVER_HINT_FREE           = "|cfff5ae0aShift + перетаскивание|r: свободное перемещение",
MOVER_HINT_MAGNET         = "|cfff5ae0aРядом с другим элементом|r: примагничивание",
MOVER_HINT_ARROWS         = "|cfff5ae0aЩелчок по рамке|r: стрелки смещают на 1 пиксель",
MOVER_SAVE_EXIT           = "Сохранить и выйти",
MOVER_RESET               = "Сбросить",
MOVER_DRAG_FIRST          = "Перетащите «%s» один раз, прежде чем смещать стрелками.",
MOVER_ENTERED             = "Режим редактирования. Перетаскивайте, примагничивайте или смещайте стрелками. |cffffff00Сохранить и выйти|r по завершении.",
MOVER_SAVED               = "Расположение сохранено. Режим редактирования закрыт.",
MOVER_RESET_ONE           = "Сброшена %d позиция рамки к значениям по умолчанию.",
MOVER_RESET_FEW           = "Сброшены %d позиции рамок к значениям по умолчанию.",
MOVER_RESET_MANY          = "Сброшено %d позиций рамок к значениям по умолчанию.",
MOVER_RESET_OTHER         = "Сброшено %d позиций рамок к значениям по умолчанию.",

MOVER_LABEL_PLAYER        = "Игрок",
MOVER_LABEL_TARGET        = "Цель",
MOVER_LABEL_TARGET_TARGET = "Цель цели",
MOVER_LABEL_PET           = "Питомец",
MOVER_LABEL_PARTY         = "Группа",
MOVER_LABEL_PARTY_N       = "Группа %d",
MOVER_LABEL_DRUID_MANA    = "Мана друида",
MOVER_LABEL_CASTBAR       = "Полоса заклинаний",
MOVER_LABEL_TARGET_CASTBAR = "Полоса заклинаний цели",
MOVER_LABEL_XP_BAR        = "Полоса опыта",
MOVER_LABEL_REP_BAR       = "Полоса репутации",
MOVER_LABEL_BREATH_BAR    = "Полоса дыхания",
MOVER_LABEL_MICRO_BAR     = "Микропанель",
MOVER_LABEL_BUFFS         = "Усиления и ослабления",
MOVER_LABEL_MINIMAP       = "Миникарта",
MOVER_LABEL_PET_BAR       = "Панель питомца",
MOVER_LABEL_STANCE_BAR    = "Панель стоек",
MOVER_LABEL_STATUS        = "Панель состояния",
MOVER_LABEL_ONLINE_COUNT  = "Счётчик игроков онлайн",
MOVER_LABEL_QUEST_TRACKER = "Отслеживание заданий",
MOVER_LABEL_BAGS          = "Сумки",
MOVER_LABEL_BANK          = "Банк",
MOVER_LABEL_ACTION_BAR    = "Панель %d",
MOVER_LABEL_MOVER_TEST    = "Проверка перемещения",

-- ---------------------------------------------------------------------------
-- Settings window
-- ---------------------------------------------------------------------------
SETTINGS_MOVE_UI          = "Переместить интерфейс",
SETTINGS_LANGUAGE_CHANGED = "Язык изменён",
SETTINGS_LANGUAGE_RELOAD  = "Введите /reload, чтобы отобразить UnrealUI на языке: %s.",

SETTINGS_PAGE_GENERAL     = "Общие",
SETTINGS_PAGE_PROFILES    = "Профили",
SETTINGS_PAGE_ROGUE       = "Разбойник",

SETTINGS_THEME_STYLE      = "Стиль оформления",
SETTINGS_THEME_CHANGED    = "Оформление изменено",
SETTINGS_THEME_RELOAD     = "Введите /reload, чтобы применить оформление «%s».",
SETTINGS_THEME_HINT       = "«Classic WoW» после перезагрузки восстанавливает исходный интерфейс клиента, сохраняя пункты UnrealUI и «Быстрые привязки» в игровом меню. «Modern WoW» ещё в разработке.",
SETTINGS_THEME_WIP        = " (в разработке)",
SETTINGS_THEMES_AVAILABLE = "доступные оформления:",

SETTINGS_QUICKBIND        = "Быстрые привязки",
SETTINGS_QUICKBIND_HINT   = "Наведите курсор на ячейку панели команд или панели стоек и нажмите клавишу, чтобы назначить её. Escape над ячейкой очищает привязку.",
SETTINGS_AUTO_ATTACK      = "Начинать автоатаку при выборе цели",
SETTINGS_AUTO_ATTACK_HINT = "Автоматически начинает автоатаку при выборе доступной для атаки цели щелчком мыши или клавишей Tab. Не срабатывает, пока разбойник или друид находится в режиме незаметности.",
SETTINGS_MICROBAR         = "Включить микропанель",
SETTINGS_MICROBAR_HINT    = "Собирает стандартные кнопки персонажа, книги заклинаний, талантов, журнала заданий, социального окна, карты, меню и помощи в один перемещаемый ряд. Отключение возвращает их на штатные места.",
SETTINGS_REPUTATION_BAR   = "Показывать полосу репутации",
SETTINGS_MINIMAP_BUTTON   = "Показывать кнопку настроек у миникарты",
SETTINGS_ZONE_LEVELS      = "Показывать диапазоны уровней зон на карте мира",
SETTINGS_ZONE_LEVELS_HINT = "При наведении на зону на карте континента рядом с названием показывается её диапазон уровней: зелёный — ниже вашего уровня, оранжевый — на вашем уровне, красный — выше вашего уровня.",

ROGUE_SETTINGS_HEADER         = "Быстрое нанесение ядов",
ROGUE_POISON_SHIFT_CLICK      = "Включить нанесение ядов по Shift",
ROGUE_POISON_SHIFT_CLICK_HINT = "В сумках нажмите Shift + левую кнопку мыши на яде для правой руки или Shift + правую кнопку для левой руки. При открытой строке чата ссылки на предметы работают как обычно.",

PROFILE_SELECT            = "Выбрать профиль",
PROFILE_SELECT_HINT       = "Выберите профиль, созданный любым персонажем этой учётной записи.",
PROFILE_NONE_OTHER        = "Других профилей нет",
PROFILE_CREATE_COPY       = "Создать копию профиля",
PROFILE_CREATE_HINT       = "Копирует текущие настройки под сгенерированным именем. Для своего имени используйте /uui profile create <имя>.",
PROFILE_COPY_FROM         = "Копировать из",
PROFILE_COPY_SETTINGS     = "Копировать настройки",
PROFILE_COPY_HINT         = "Копирует другой профиль в текущий активный профиль.",
PROFILE_COPIED            = "профиль |cffffff00%s|r скопирован в |cffffff00%s|r",
PROFILE_DELETE_SECTION    = "Удалить профиль",
PROFILE_DELETE            = "Удалить профиль",
PROFILE_DELETE_HINT       = "Удаляет профиль, не назначенный ни одному персонажу.",
PROFILE_DELETED           = "удалён профиль |cffffff00%s|r",
PROFILE_CONFIRM_DELETE    = "Подтвердить удаление",
PROFILE_RESET_SECTION     = "Сбросить текущий профиль",
PROFILE_RESET             = "Сбросить профиль",
PROFILE_CONFIRM_RESET     = "Подтвердить сброс",
PROFILE_RESET_HINT        = "Восстанавливает значения по умолчанию. Персонажи с тем же профилем используют общие настройки.",
PROFILE_CURRENT           = "Текущий профиль: |cfff5ae0a%s|r",
PROFILE_CLICK_CONFIRM_DELETE = "нажмите «Подтвердить удаление», чтобы удалить |cffffff00%s|r",
PROFILE_CLICK_CONFIRM_RESET  = "нажмите «Подтвердить сброс», чтобы восстановить значения по умолчанию текущего профиля",
PROFILE_NO_NAME_FREE      = "не удалось найти свободное имя профиля",
PROFILE_RELOAD_NOTICE     = "%s — |cffffff00/reload|r, чтобы применить",
PROFILE_SELECTED          = "выбран профиль |cffffff00%s|r",
PROFILE_CREATED           = "создан и выбран профиль |cffffff00%s|r",
PROFILE_WAS_RESET         = "профиль сброшен |cffffff00%s|r",

-- ---------------------------------------------------------------------------
-- Action bars
-- ---------------------------------------------------------------------------
ABC_GROUP                 = "Панели команд",
ABC_GENERAL               = "Общие параметры",
ABC_BAR_N                 = "Панель %d",
ABC_BUTTONS               = "Кнопки",
ABC_BUTTONS_PER_ROW       = "Кнопок в ряду",
ABC_BUTTON_SIZE           = "Размер кнопок",
ABC_BUTTON_SPACING        = "Отступ между кнопками",
ABC_HIDE_SLOT_BACKGROUND  = "Скрыть фон ячеек",
ABC_HINT_BAR1             = "Панель 1 следует за страницей команд и стандартными привязками основной панели.",
ABC_HINT_MULTIBAR         = "Для этих ячеек используются стандартные привязки дополнительных панелей.",
ABC_HINT_PAGE_ONLY        = "Панель только для страниц: в этом клиенте для неё нет команды привязки, поэтому её ячейки работают только мышью.",
ABC_RESERVED_FOR          = "Зарезервировано для: %s",
ABC_RESERVED_ROGUE        = "Незаметность разбойника",
ABC_RESERVED_WARRIOR      = "Стойки воина",
ABC_RESERVED_DRUID        = "Формы друида",
ABC_RESERVED_GENERIC      = "Страницы класса/форм",
ABC_RESERVED_TOOLTIP      = "Зарезервировано для: %s. Панель 1 использует эту страницу автоматически.",
ABC_RESERVED_EXPLANATION  = "Эта страница команд используется панелью 1 автоматически, пока активно состояние «%s». Показ её как отдельной панели вывел бы одни и те же ячейки дважды, поэтому настройки её расположения заблокированы на этом персонаже.",
ABC_RESERVED_SAVED        = "Общие для учётной записи настройки этой страницы сохранены. Они остаются доступны на персонажах, чей класс её не резервирует.",
ABC_SHOW_KEYBIND          = "Показывать привязки клавиш",
ABC_SHOW_MACRO            = "Показывать названия макросов",
ABC_SHOW_COUNT            = "Показывать количество предметов",
ABC_SHOW_COOLDOWN         = "Показывать таймеры восстановления",
ABC_SHOW_GCD              = "Показывать общее время восстановления",
ABC_GENERAL_HINT          = "Доступно независимых панелей: %d. Страницы, используемые формами этого класса, отображаются только на панели 1.",
ABC_BIND_HINT             = "Наведите курсор на ячейку и нажмите клавишу, чтобы назначить её. Escape над ячейкой очищает привязку. Панели 1–5 поддерживают привязки; для панелей 6–10 в этом клиенте нет команды клавиши, поэтому они отображаются, но привязку принять не могут.",

-- ---------------------------------------------------------------------------
-- Quick binding
-- ---------------------------------------------------------------------------
QUICKBIND_TITLE           = "Быстрые привязки",
QUICKBIND_OPENED          = "Быстрые привязки. Наведите курсор на ячейку и нажмите клавишу. |cffffff00Сохранить|r применяет изменения, |cffffff00Отмена|r или Escape отбрасывает их.",
QUICKBIND_NO_ACTIONBARS   = "панели команд недоступны, поэтому быстрым привязкам нечего назначать.",
QUICKBIND_NO_SLOTS        = "ни одна ячейка панели команд не видна, поэтому назначать нечего.",
QUICKBIND_UNAVAILABLE     = "быстрые привязки недоступны в этой сборке.",
QUICKBIND_CLEARED         = "Привязка очищена: панель %s, ячейка %s.",
QUICKBIND_CLEARED_STANCE  = "Привязка очищена: панель стоек, ячейка %s.",
QUICKBIND_NO_COMMAND      = "В этом клиенте нет команды клавиши для панели %s. Привязки поддерживают только панели 1–5.",
QUICKBIND_SAVED_ONE       = "Сохранено %d изменение привязки.",
QUICKBIND_SAVED_FEW       = "Сохранено %d изменения привязок.",
QUICKBIND_SAVED_MANY      = "Сохранено %d изменений привязок.",
QUICKBIND_SAVED_OTHER     = "Сохранено %d изменений привязок.",
QUICKBIND_NOTHING_CHANGED = "Быстрые привязки закрыты. Ничего не изменилось.",
QUICKBIND_REVERTED_ONE    = "Быстрые привязки отменены. %d изменение возвращено.",
QUICKBIND_REVERTED_FEW    = "Быстрые привязки отменены. %d изменения возвращены.",
QUICKBIND_REVERTED_MANY   = "Быстрые привязки отменены. %d изменений возвращено.",
QUICKBIND_REVERTED_OTHER  = "Быстрые привязки отменены. %d изменений возвращено.",
QUICKBIND_CLOSED          = "Быстрые привязки закрыты.",
QUICKBIND_COMBAT          = "Быстрые привязки закрыты: начался бой.",
QUICKBIND_NO_SETBINDING   = "|cffff5555SetBinding недоступен в этом клиенте; быстрые привязки не могут изменять клавиши.|r",
QUICKBIND_SAVE_UNAVAILABLE = "|cffff5555SaveBindings недоступен в этом клиенте:|r клавиши работают сейчас, но не сохранятся после выхода.",
QUICKBIND_SAVE_FAILED     = "|cffff5555Ошибка SaveBindings;|r клавиши работают сейчас, но могут не сохраниться после выхода.",
QUICKBIND_SLOT_COUNT_ONE  = "В этом режиме %d ячейка.",
QUICKBIND_SLOT_COUNT_FEW  = "В этом режиме %d ячейки.",
QUICKBIND_SLOT_COUNT_MANY = "В этом режиме %d ячеек.",
QUICKBIND_SLOT_COUNT_OTHER = "В этом режиме %d ячейки.",

-- ---------------------------------------------------------------------------
-- Unit frames and auras
-- ---------------------------------------------------------------------------
UF_PAGE                   = "Рамки существ",
UF_COLORS_HEADER          = "Цвета рамок существ",
UF_CUSTOM_BAR_COLORS      = "Использовать свои цвета полос",
UF_HEALTH_BAR_COLOR       = "Цвет полосы здоровья",
UF_CLASS_COLORS           = "Использовать цвета классов для полос здоровья игроков",
UF_POWER_BAR_COLORS       = "Цвета полос ресурса",
UF_POWER_MANA             = "Мана",
UF_POWER_RAGE             = "Ярость",
UF_POWER_FOCUS            = "Фокус",
UF_POWER_ENERGY           = "Энергия",

UF_PARTY_HEADER           = "Рамки группы",
UF_PARTY_PETS             = "Показывать питомцев членов группы",

AURAS_HEADER              = "Эффекты на рамках существ",
AURAS_ON_PLAYER_FRAME     = "Показывать эффекты на рамке игрока",
AURAS_NEAR_MINIMAP        = "Показывать эффекты у миникарты",
AURAS_PLAYER_DEBUFFS      = "Дебаффы на рамке игрока",
AURAS_PLAYER_BUFFS        = "Баффы на рамке игрока",
AURAS_TARGET_DEBUFFS      = "Дебаффы на рамке цели",
AURAS_TARGET_BUFFS        = "Баффы на рамке цели",
AURAS_PARTY_DEBUFFS       = "Дебаффы на рамках группы",
AURAS_PARTY_BUFFS         = "Баффы на рамках группы",
AURAS_SHOW_TIMERS         = "Таймеры на значках эффектов",
AURAS_BELOW_FRAME         = "Эффекты игрока и цели под рамками",
AURAS_DISPEL_HEADER       = "Показывать дебаффы по типу рассеивания",
AURAS_MAGIC               = "Магия",
AURAS_CURSE               = "Проклятие",
AURAS_POISON              = "Яд",
AURAS_DISEASE             = "Болезнь",
AURAS_OTHER               = "Физический / прочее",
AURAS_HINT                = "Точны только таймеры ваших собственных эффектов. Для других существ клиент не сообщает длительность, поэтому она оценивается по таблице заклинаний: уже действующий эффект выглядит только что наложенным, а отсутствующий в таблице — без таймера. Введите /uui aura, чтобы увидеть, какой из них какой.",

-- ---------------------------------------------------------------------------
-- Bags and bank
-- ---------------------------------------------------------------------------
BAGS_TITLE                = "Сумки",
BAGS_TOGGLE_KEYRING       = "Показать/скрыть связку ключей",
BAGS_KEYRING_HINT         = "Показать связку ключей.",
BAGS_TOGGLE_BAGS          = "Показать/скрыть сумки",
BAGS_BAG_SLOTS_HINT       = "Показать ячейки надетых сумок.",
BAGS_VENDOR_GRAYS         = "Продать / удалить серые предметы",
BAGS_GREYS_HINT           = "Продаёт серые предметы у торговца; в остальных случаях предлагает удалить их.",
BAGS_PICK_LOCK            = "Взлом замка",
BAGS_PICK_LOCK_HINT       = "Активируйте «Взлом замка», затем нажмите на запертый ящик в сумках.",
BAGS_PICK_LOCK_ACTION_HINT = "Поместите «Взлом замка» на панель команд, чтобы использовать кнопку у сумок.",
BAGS_DELETE_CONFIRM_ONE   = "Удалить %d серый предмет?",
BAGS_DELETE_CONFIRM_FEW   = "Удалить %d серых предмета?",
BAGS_DELETE_CONFIRM_MANY  = "Удалить %d серых предметов?",
BAGS_DELETE_CONFIRM_OTHER = "Удалить %d серых предметов?",
BAGS_SOLD_GREYS           = "Серые предметы проданы за %s.",
BAGS_DELETED_GREYS_ONE    = "Удалён %d серый предмет.",
BAGS_DELETED_GREYS_FEW    = "Удалено %d серых предмета.",
BAGS_DELETED_GREYS_MANY   = "Удалено %d серых предметов.",
BAGS_DELETED_GREYS_OTHER  = "Удалено %d серых предмета.",
BAGS_NO_GREYS             = "Серых предметов не найдено.",
BANK_TITLE                = "Банк",
BANK_BAG_LABEL            = "Банковская сумка",
BANK_BUY_SLOT             = "Купить ещё одну ячейку для банковской сумки?",
BANK_PURCHASE             = "Купить",
BANK_PURCHASE_TITLE       = "Купить банковскую сумку",
BANK_TRANSFER_PICKUP      = "Перенос через банк остановлен в вашем инвентаре; снова возьмите предмет, чтобы продолжить.",
BANK_TRANSFER_EMPTY_SLOT  = "Для переноса предметов между банковскими сумками нужна промежуточная ячейка в сумках персонажа; подходящей не нашлось.",
BANK_SLOT_TEMPLATE_FALLBACK = "%s недоступен в этом клиенте; для ячеек банка используется шаблон ячеек сумки.",
BANK_SLOTS_LOADING        = "Клиент ещё не сообщил ячейки банка; повторяем попытку, пока окно открыто.",

-- ---------------------------------------------------------------------------
-- Item comparison (modules/tooltip.lua)
-- ---------------------------------------------------------------------------
TOOLTIP_COMPARE_SUMMARY   = "Если заменить этот предмет:",

-- ---------------------------------------------------------------------------
-- Overlays and native screens
-- ---------------------------------------------------------------------------
STATUS_FPS                = "Кадр/с:",
STATUS_LATENCY            = "Мс:",
STATUS_DURABILITY         = "Прочность:",
STATUS_ONLINE             = "игроков в сети",

WORLDMAP_CURSOR           = "Курсор: --, --",
WORLDMAP_CURSOR_OFF_MAP   = "Курсор: вне карты",
QUESTLOG_LEVELS           = "Уровни",
GAMEMENU_OPTIONS          = "Настройки",

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
CMD_HEADER                = "v%s, команды:",
CMD_SETTINGS              = "  |cffffff00/uui|r — открыть настройки",
CMD_UNLOCK                = "  |cffffff00/uui unlock|r — разблокировать рамки для перемещения",
CMD_LOCK                  = "  |cffffff00/uui lock|r — заблокировать рамки",
CMD_RESET                 = "  |cffffff00/uui reset|r — сбросить все позиции рамок",
CMD_BIND                  = "  |cffffff00/uui bind|r — открыть быстрые привязки",
CMD_CHECK                 = "  |cffffff00/uui check|r — самопроверка среды выполнения",
CMD_THEME                 = "  |cffffff00/uui theme <style>|r — выбрать оформление (нужен /reload)",
CMD_LANGUAGE              = "  |cffffff00/uui lang <en/cn/ru/fr>|r — выбрать язык (нужен /reload)",
CMD_PROFILE               = "  |cffffff00/uui profile create <имя>|r — создать и выбрать общий профиль",
CMD_DEBUG                 = "  |cffffff00/uui debug|r — включить/выключить отладочный вывод",
CMD_DIAGNOSTICS           = "  |cffffff00/uui help diag|r — список диагностических дампов",
CMD_UNKNOWN               = "неизвестная команда: %s",
CMD_SETTINGS_UNAVAILABLE  = "интерфейс настроек пока недоступен в этой сборке.",
CMD_LANGUAGE_CURRENT      = "язык: |cffffff00%s|r",
CMD_LANGUAGE_AVAILABLE    = "доступные языки:",
CMD_PROFILE_CURRENT       = "текущий профиль: |cffffff00%s|r",
CMD_PROFILE_CREATE_USAGE  = "  |cffffff00/uui profile create <имя>|r",
CMD_PROFILE_UNAVAILABLE   = "управление профилями недоступно в этой сборке",
CMD_PROFILE_EXISTS        = "профиль с именем |cffffff00%s|r уже существует",
CMD_PROFILE_NAME_RULES    = "имя профиля может содержать буквы, цифры, пробелы, дефисы и подчёркивания (не более 64 символов)",
CMD_PROFILE_CREATED       = "создан и выбран профиль |cffffff00%s|r — |cffffff00/reload|r, чтобы применить",

})

-- Russian counted-noun forms. The rule is the standard CLDR one and depends on
-- the last two digits, so 11-14 take the "many" form even though they end in
-- 1-4: 21 позиция, but 11 позиций.
UnrealUI.RegisterLocalePlural("ruRU", function(n)
  if n ~= math.floor(n) then return "OTHER" end

  local mod10 = math.mod(n, 10)
  local mod100 = math.mod(n, 100)

  if mod10 == 1 and mod100 ~= 11 then return "ONE" end
  if mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14) then
    return "FEW"
  end
  return "MANY"
end)
