-- unrealUI :: locales/frFR.lua
--
-- French. See locales/enUS.lua for the catalog and the rules every locale
-- file follows (UTF-8 without BOM, placeholders kept in order, colour escapes
-- kept paired, slash commands never translated).
--
-- Terminology follows the French WoW client where it has a settled word:
-- amelioration / affaiblissement for buff / debuff, raccourci for keybind,
-- minicarte, incantation, familier.

UnrealUI.RegisterLocale("frFR", {

-- Opt-in custom pet bar (native remains the default).
CMD_PETBAR                = "  |cffffff00/uui petbar <native/custom>|r - choisir la barre du familier (necessite /reload)",
PETBAR_MODE_NATIVE        = "Native",
PETBAR_MODE_CUSTOM        = "Personnalisee (Moderne)",
PETBAR_MODE_STATUS        = "Barre du familier : %s. Choix au prochain rechargement : %s.",
PETBAR_MODE_SELECTED      = "Barre du familier choisie : %s. Tapez /reload pour appliquer.",
PETBAR_CUSTOM_WARNING     = "Barre du familier personnalisee experimentale : ce client bloque le lancement des sorts par clic. Retrouvez les sorts natifs avec /uui petbar native, puis /reload.",
PETBAR_ACTION_UNAVAILABLE = "Cette action du familier est indisponible sur ce client.",
PETBAR_UNAVAILABLE        = "Le choix de la barre du familier est indisponible dans cette session.",

-- ---------------------------------------------------------------------------
-- Shared controls
-- ---------------------------------------------------------------------------
COMMON_OK                 = "Accepter",
COMMON_OK_SHORT           = "OK",
COMMON_CANCEL             = "Annuler",
COMMON_ACCEPT             = "Accepter",
COMMON_CLOSE              = "Fermer",
COMMON_SAVE               = "Enregistrer",
COMMON_DELETE             = "Supprimer",
COMMON_ENABLE             = "Activer",
COMMON_ARE_YOU_SURE       = "Etes-vous sur ?",
COMMON_CANNOT_BE_UNDONE   = "Cette action est irreversible.",
COMMON_SELECT_COLOUR      = "Choisir une couleur",
COMMON_COST               = "Cout :",
COMMON_SELL               = "Vente :",
LOADING_TITLE             = "Preparation d'UnrealUI",
LOADING_CLIENT_LIMITATION = "Chargement requis a cause des limites du client actuel. Pour eviter les blocages pendant le jeu.",
LOADING_FPS_DEPENDENT     = "La duree depend des FPS. Retire dans une future mise a jour du client.",

-- ---------------------------------------------------------------------------
-- Edit mode
-- ---------------------------------------------------------------------------
MOVER_TITLE               = "Editer l'interface",
MOVER_HINT_FREE           = "|cfff5ae0aMaj + glisser|r : deplacement libre",
MOVER_HINT_MAGNET         = "|cfff5ae0aPres d'un autre element|r : aimantation",
MOVER_HINT_ARROWS         = "|cfff5ae0aCliquez un cadre|r : les fleches le deplacent d'1 px",
MOVER_SAVE_EXIT           = "Enregistrer et quitter",
MOVER_RESET               = "Reinitialiser",
MOVER_DRAG_FIRST          = "Deplacez %s une fois avant de l'ajuster.",
MOVER_ENTERED             = "Mode edition. Glissez, aimantez ou ajustez avec les fleches. |cffffff00Enregistrer et quitter|r une fois termine.",
MOVER_SAVED               = "Disposition enregistree. Mode edition ferme.",
MOVER_RESET_ONE           = "%d position de cadre reinitialisee par defaut.",
MOVER_RESET_OTHER         = "%d positions de cadre reinitialisees par defaut.",

MOVER_LABEL_PLAYER        = "Joueur",
MOVER_LABEL_TARGET        = "Cible",
MOVER_LABEL_TARGET_TARGET = "Cible de la cible",
MOVER_LABEL_PET           = "Familier",
MOVER_LABEL_PARTY         = "Groupe",
MOVER_LABEL_PARTY_N       = "Groupe %d",
MOVER_LABEL_DRUID_MANA    = "Mana du druide",
MOVER_LABEL_CASTBAR       = "Barre d'incantation",
MOVER_LABEL_TARGET_CASTBAR = "Incantation de la cible",
MOVER_LABEL_PET_CASTBAR   = "Incantation du familier",
MOVER_LABEL_XP_BAR        = "Barre d'experience",
MOVER_LABEL_REP_BAR       = "Barre de reputation",
MOVER_LABEL_BREATH_BAR    = "Barre de souffle",
MOVER_LABEL_SWING_BAR     = "Attaque auto : barre d'attaque",
MOVER_LABEL_MICRO_BAR     = "Micro-barre",
MOVER_LABEL_BUFFS         = "Ameliorations et affaiblissements",
MOVER_LABEL_MINIMAP       = "Minicarte",
MOVER_LABEL_PET_BAR       = "Barre du familier",
MOVER_LABEL_STANCE_BAR    = "Barre de posture",
MOVER_LABEL_STATUS        = "Surcouche d'etat",
MOVER_LABEL_ONLINE_COUNT  = "Surcouche des connectes",
MOVER_LABEL_QUEST_TRACKER = "Suivi de quetes",
MOVER_LABEL_BAGS          = "Sacs",
MOVER_LABEL_BANK          = "Banque",
MOVER_LABEL_ACTION_BAR    = "Barre %d",
MOVER_LABEL_MOVER_TEST    = "Test de deplacement",

-- ---------------------------------------------------------------------------
-- Settings window
-- ---------------------------------------------------------------------------
SETTINGS_MOVE_UI          = "Deplacer l'interface",
SETTINGS_LANGUAGE_CHANGED = "Langue modifiee",
SETTINGS_LANGUAGE_RELOAD  = "Tapez /reload pour afficher UnrealUI en %s.",

SETTINGS_PAGE_GENERAL     = "General",
SETTINGS_PAGE_PROFILES    = "Profils",
SETTINGS_PAGE_ROGUE       = "Voleur",

SETTINGS_THEME_STYLE      = "Style du theme",
SETTINGS_THEME_CHANGED    = "Theme modifie",
SETTINGS_THEME_RELOAD     = "Tapez /reload pour appliquer le theme %s.",
SETTINGS_THEME_HINT       = "Classic WoW restaure l'interface native d'origine apres un rechargement, en conservant les entrees UnrealUI et Raccourcis rapides dans le menu du jeu. Modern WoW est encore en developpement.",
SETTINGS_THEME_WIP        = " (en cours)",
SETTINGS_THEMES_AVAILABLE = "themes disponibles :",

SETTINGS_QUICKBIND        = "Raccourcis rapides",
SETTINGS_QUICKBIND_HINT   = "Survolez un emplacement de barre d'action ou de barre de posture et appuyez sur une touche pour l'assigner. Echap sur un emplacement l'efface.",
SETTINGS_AUTO_ATTACK      = "Demarrer l'attaque automatique au ciblage",
SETTINGS_AUTO_ATTACK_HINT = "Demarre automatiquement l'attaque contre une cible attaquable selectionnee par clic ou avec Tab. Ne se declenche jamais quand un voleur ou un druide est camoufle.",
SETTINGS_SWING_BAR        = "Afficher la barre d'attaque automatique",
SETTINGS_SWING_BAR_HINT   = "Affiche le rythme de la main droite, de la main gauche et de l'arc ou arme a distance tant que la cible est a portee. Se deplace via le mode interface.",
SETTINGS_MICROBAR         = "Activer la micro-barre",
SETTINGS_MICROBAR_HINT    = "Regroupe les boutons natifs personnage/grimoire/talents/journal de quetes/social/carte/menu/aide en une seule rangee deplacable. La desactiver les remet a leur emplacement d'origine.",
SETTINGS_REPUTATION_BAR   = "Afficher la barre de reputation",
SETTINGS_MINIMAP_BUTTON   = "Afficher le bouton des reglages sur la minicarte",
SETTINGS_ZONE_LEVELS      = "Afficher les niveaux des zones sur la carte du monde",
SETTINGS_ZONE_LEVELS_HINT = "Survoler une zone sur une carte de continent affiche sa plage de niveaux a cote du nom : vert en dessous de votre niveau, orange a votre niveau, rouge au-dessus.",

SWING_BAR_MAIN            = "MD",
SWING_BAR_OFF             = "MG",
SWING_BAR_RANGED          = "Dist.",

ROGUE_SETTINGS_HEADER         = "Raccourcis de poison",
ROGUE_POISON_SHIFT_CLICK      = "Activer les clics Shift pour les poisons",
ROGUE_POISON_SHIFT_CLICK_HINT = "Dans les sacs, Shift-clic gauche sur un poison l'applique a la main droite et Shift-clic droit a la main gauche. Les liens dans le chat restent inchanges quand la saisie est ouverte.",

PROFILE_SELECT            = "Choisir un profil",
PROFILE_SELECT_HINT       = "Choisissez un profil cree par n'importe quel personnage de ce compte.",
PROFILE_NONE_OTHER        = "Aucun autre profil",
PROFILE_CREATE_COPY       = "Creer une copie du profil",
PROFILE_CREATE_HINT       = "Copie les reglages actuels sous un nom genere. Pour un nom personnalise, utilisez /uui profile create <nom>.",
PROFILE_COPY_FROM         = "Copier depuis",
PROFILE_COPY_SETTINGS     = "Copier les reglages",
PROFILE_COPY_HINT         = "Copie un autre profil dans le profil actuellement actif.",
PROFILE_COPIED            = "profil |cffffff00%s|r copie dans |cffffff00%s|r",
PROFILE_DELETE_SECTION    = "Supprimer un profil",
PROFILE_DELETE            = "Supprimer le profil",
PROFILE_DELETE_HINT       = "Supprime un profil qui n'est attribue a aucun personnage.",
PROFILE_DELETED           = "profil |cffffff00%s|r supprime",
PROFILE_CONFIRM_DELETE    = "Confirmer la suppression",
PROFILE_RESET_SECTION     = "Reinitialiser le profil actuel",
PROFILE_RESET             = "Reinitialiser le profil",
PROFILE_CONFIRM_RESET     = "Confirmer la reinitialisation",
PROFILE_RESET_HINT        = "Restaure les valeurs par defaut. Les personnages utilisant le meme profil en partagent les reglages.",
PROFILE_CURRENT           = "Profil actuel : |cfff5ae0a%s|r",
PROFILE_CLICK_CONFIRM_DELETE = "cliquez sur Confirmer la suppression pour retirer |cffffff00%s|r",
PROFILE_CLICK_CONFIRM_RESET  = "cliquez sur Confirmer la reinitialisation pour restaurer les valeurs par defaut du profil actuel",
PROFILE_NO_NAME_FREE      = "impossible de trouver un nom de profil disponible",
PROFILE_RELOAD_NOTICE     = "%s - |cffffff00/reload|r pour l'appliquer",
PROFILE_SELECTED          = "profil selectionne |cffffff00%s|r",
PROFILE_CREATED           = "profil cree et selectionne |cffffff00%s|r",
PROFILE_WAS_RESET         = "profil reinitialise |cffffff00%s|r",

-- ---------------------------------------------------------------------------
-- Action bars
-- ---------------------------------------------------------------------------
ABC_GROUP                 = "Barres d'action",
ABC_GENERAL               = "Options generales",
ABC_BAR_N                 = "Barre %d",
ABC_BUTTONS               = "Boutons",
ABC_BUTTONS_PER_ROW       = "Boutons par rangee",
ABC_BUTTON_SIZE           = "Taille des boutons",
ABC_BUTTON_SPACING        = "Espacement des boutons",
ABC_HIDE_SLOT_BACKGROUND  = "Masquer le fond des emplacements",
ABC_HINT_BAR1             = "La barre 1 suit la page d'action et les raccourcis de la barre native.",
ABC_HINT_MULTIBAR         = "Utilise les raccourcis natifs des barres multiples pour ces emplacements.",
ABC_HINT_PAGE_ONLY        = "Barre de page uniquement : ce client n'a aucune commande de raccourci pour elle, ses emplacements sont donc utilisables a la souris seulement.",
ABC_RESERVED_FOR          = "Reservee a %s",
ABC_RESERVED_ROGUE        = "Camouflage du voleur",
ABC_RESERVED_WARRIOR      = "Postures du guerrier",
ABC_RESERVED_DRUID        = "Formes du druide",
ABC_RESERVED_GENERIC      = "Pages de classe/formes",
ABC_RESERVED_TOOLTIP      = "Reservee a %s. La barre 1 utilise cette page automatiquement.",
ABC_RESERVED_EXPLANATION  = "Cette page d'action est utilisee automatiquement par la barre 1 tant que %s est active. L'afficher comme une autre barre physique exposerait deux fois les memes emplacements, ses reglages de disposition sont donc verrouilles sur ce personnage.",
ABC_RESERVED_SAVED        = "Les reglages de cette page, communs au compte, sont conserves. Ils restent disponibles sur les personnages dont la classe ne la reserve pas.",
ABC_SHOW_KEYBIND          = "Afficher les raccourcis",
ABC_SHOW_MACRO            = "Afficher les noms de macro",
ABC_SHOW_COUNT            = "Afficher le nombre d'objets",
ABC_SHOW_COOLDOWN         = "Afficher les temps de recharge",
ABC_SHOW_GCD              = "Afficher le temps de recharge global",
ABC_GENERAL_HINT          = "%d barres independantes sont disponibles. Les pages utilisees par les formes de cette classe s'affichent uniquement sur la barre 1.",
ABC_BIND_HINT             = "Survolez un emplacement et appuyez sur une touche pour l'assigner. Echap sur un emplacement l'efface. Les barres 1 a 5 sont assignables ; les barres 6 a 10 n'ont aucune commande de touche dans ce client, elles sont donc affichees mais ne peuvent rien recevoir.",

-- ---------------------------------------------------------------------------
-- Quick binding
-- ---------------------------------------------------------------------------
QUICKBIND_TITLE           = "Raccourcis rapides",
QUICKBIND_OPENED          = "Raccourcis rapides. Survolez un emplacement et appuyez sur une touche. |cffffff00Enregistrer|r conserve les modifications, |cffffff00Annuler|r ou Echap les abandonne.",
QUICKBIND_NO_ACTIONBARS   = "les barres d'action ne sont pas disponibles, les raccourcis rapides n'ont donc rien a assigner.",
QUICKBIND_NO_SLOTS        = "aucun emplacement de barre d'action n'est visible, il n'y a donc rien a assigner.",
QUICKBIND_UNAVAILABLE     = "les raccourcis rapides ne sont pas disponibles dans cette version.",
QUICKBIND_CLEARED         = "Raccourci efface sur la barre %s, emplacement %s.",
QUICKBIND_CLEARED_STANCE  = "Raccourci efface sur la barre de posture, emplacement %s.",
QUICKBIND_NO_COMMAND      = "Ce client n'a aucune commande de touche pour la barre %s. Seules les barres 1 a 5 sont assignables.",
QUICKBIND_SAVED_ONE       = "%d modification de raccourci enregistree.",
QUICKBIND_SAVED_OTHER     = "%d modifications de raccourci enregistrees.",
QUICKBIND_NOTHING_CHANGED = "Raccourcis rapides fermes. Aucun changement.",
QUICKBIND_REVERTED_ONE    = "Raccourcis rapides annules. %d modification retablie.",
QUICKBIND_REVERTED_OTHER  = "Raccourcis rapides annules. %d modifications retablies.",
QUICKBIND_CLOSED          = "Raccourcis rapides fermes.",
QUICKBIND_COMBAT          = "Raccourcis rapides fermes : le combat a commence.",
QUICKBIND_NO_SETBINDING   = "|cffff5555SetBinding n'est pas disponible dans ce client ; les raccourcis rapides ne peuvent pas modifier les touches.|r",
QUICKBIND_SAVE_UNAVAILABLE = "|cffff5555SaveBindings n'est pas disponible dans ce client :|r les touches fonctionnent maintenant, mais ne seront pas conservees apres la deconnexion.",
QUICKBIND_SAVE_FAILED     = "|cffff5555Echec de SaveBindings ;|r les touches fonctionnent maintenant, mais risquent de ne pas etre conservees apres la deconnexion.",
QUICKBIND_SLOT_COUNT_ONE  = "%d emplacement dans ce mode.",
QUICKBIND_SLOT_COUNT_OTHER = "%d emplacements dans ce mode.",

-- ---------------------------------------------------------------------------
-- Unit frames and auras
-- ---------------------------------------------------------------------------
UF_PAGE                   = "Cadres d'unite",
UF_COLORS_HEADER          = "Couleurs des cadres d'unite",
UF_CUSTOM_BAR_COLORS      = "Utiliser des couleurs de barre personnalisees",
UF_HEALTH_BAR_COLOR       = "Couleur de la barre de vie",
UF_CLASS_COLORS           = "Utiliser les couleurs de classe pour les barres de vie des joueurs",
UF_POWER_BAR_COLORS       = "Couleurs des barres de ressource",
UF_POWER_MANA             = "Mana",
UF_POWER_RAGE             = "Rage",
UF_POWER_FOCUS            = "Focalisation",
UF_POWER_ENERGY           = "Energie",

UF_PARTY_HEADER           = "Cadres de groupe",
UF_PARTY_PETS             = "Afficher les familiers des membres du groupe",
UF_POWER_TICK_HEADER      = "Cycle de ressource du joueur",
UF_MANA_TICK              = "Afficher le cycle de mana",
UF_ENERGY_TICK            = "Afficher le cycle d'energie",
UF_COMBO_POINTS_HEADER    = "Points de combo",
UF_COMBO_POINTS_PLAYER_FRAME = "Cadre joueur",
UF_COMBO_POINTS_TARGET_FRAME = "Cadre cible",

AURAS_HEADER              = "Auras des cadres d'unite",
AURAS_ON_PLAYER_FRAME     = "Afficher les auras sur le cadre joueur",
AURAS_NEAR_MINIMAP        = "Afficher les auras pres de la minicarte",
AURAS_PLAYER_DEBUFFS      = "Affaiblissements du cadre joueur",
AURAS_PLAYER_BUFFS        = "Ameliorations du cadre joueur",
AURAS_TARGET_DEBUFFS      = "Affaiblissements du cadre cible",
AURAS_TARGET_BUFFS        = "Ameliorations du cadre cible",
AURAS_PARTY_DEBUFFS       = "Affaiblissements des cadres de groupe",
AURAS_PARTY_BUFFS         = "Ameliorations des cadres de groupe",
AURAS_SHOW_TIMERS         = "Minuteurs sur les icones d'aura",
AURAS_BELOW_FRAME         = "Auras joueur / cible sous les cadres",
AURAS_DISPEL_HEADER       = "Afficher les affaiblissements par type de dissipation",
AURAS_MAGIC               = "Magie",
AURAS_CURSE               = "Malediction",
AURAS_POISON              = "Poison",
AURAS_DISEASE             = "Maladie",
AURAS_OTHER               = "Physique / autre",
AURAS_HINT                = "Seuls les minuteurs de vos propres auras sont exacts. Ce client n'indique aucune duree pour les autres unites : ces minuteurs sont estimes d'apres une table de sorts. Une aura deja active parait fraiche, une aura absente de la table n'affiche rien. Tapez /uui aura pour voir laquelle est laquelle.",

-- ---------------------------------------------------------------------------
-- Bags and bank
-- ---------------------------------------------------------------------------
BAGS_TITLE                = "Sacs",
BAGS_TOGGLE_KEYRING       = "Afficher/masquer le porte-cles",
BAGS_KEYRING_HINT         = "Afficher le porte-cles.",
BAGS_TOGGLE_BAGS          = "Afficher/masquer les sacs",
BAGS_BAG_SLOTS_HINT       = "Afficher les emplacements des sacs equipes.",
BAGS_VENDOR_GRAYS         = "Vendre / supprimer les objets gris",
BAGS_GREYS_HINT           = "Vend les objets gris chez un marchand ; sinon, demande leur suppression.",
BAGS_PICK_LOCK            = "Crochetage",
BAGS_PICK_LOCK_HINT       = "Active Crochetage, puis cliquez sur un coffre verrouille dans les sacs.",
BAGS_PICK_LOCK_ACTION_HINT = "Placez Crochetage sur une barre d'action pour utiliser le raccourci des sacs.",
BAGS_DELETE_CONFIRM_ONE   = "Supprimer %d objet gris ?",
BAGS_DELETE_CONFIRM_OTHER = "Supprimer %d objets gris ?",
BAGS_SOLD_GREYS           = "Objets gris vendus pour %s.",
BAGS_DELETED_GREYS_ONE    = "%d objet gris supprime.",
BAGS_DELETED_GREYS_OTHER  = "%d objets gris supprimes.",
BAGS_NO_GREYS             = "Aucun objet gris trouve.",
BANK_TITLE                = "Banque",
BANK_BAG_LABEL            = "Sac de banque",
BANK_BUY_SLOT             = "Acheter un emplacement de sac de banque supplementaire ?",
BANK_PURCHASE             = "Acheter",
BANK_PURCHASE_TITLE       = "Acheter un sac de banque",
BANK_TRANSFER_PICKUP      = "Le transfert bancaire s'est arrete dans votre inventaire ; reprenez l'objet pour continuer.",
BANK_TRANSFER_EMPTY_SLOT  = "Deplacer des objets entre les sacs de banque necessite un emplacement de sac du personnage comme relais ; aucun n'etait utilisable.",
BANK_SLOT_TEMPLATE_FALLBACK = "%s n'est pas disponible dans ce client ; les emplacements de banque utilisent le modele des sacs.",
BANK_SLOTS_LOADING        = "Le client n'a pas encore signale les emplacements de banque ; nouvelle tentative tant que la fenetre reste ouverte.",

-- ---------------------------------------------------------------------------
-- Item comparison (modules/tooltip.lua)
-- ---------------------------------------------------------------------------
TOOLTIP_COMPARE_SUMMARY   = "Si vous remplacez cet objet :",

-- ---------------------------------------------------------------------------
-- Overlays and native screens
-- ---------------------------------------------------------------------------
STATUS_FPS                = "IPS :",
STATUS_LATENCY            = "MS :",
STATUS_DURABILITY         = "Durabilite :",
STATUS_ONLINE             = "joueurs en ligne",

WORLDMAP_CURSOR           = "Curseur : --, --",
WORLDMAP_CURSOR_OFF_MAP   = "Curseur : hors carte",
QUESTLOG_LEVELS           = "Niveaux",
SPELLBOOK_HIGHEST_RANK    = "Rang maximal",
SPELLBOOK_HIGHEST_RANK_TOOLTIP = "Affiche seulement le dernier rang de chaque sort.",
SPELLBOOK_BAR_HINT        = "Absent des barres",
SPELLBOOK_BAR_HINT_TOOLTIP = "Surligne les sorts absents des barres.",
GAMEMENU_OPTIONS          = "Options",

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
CMD_HEADER                = "v%s commandes :",
CMD_SETTINGS              = "  |cffffff00/uui|r - ouvrir les reglages",
CMD_UNLOCK                = "  |cffffff00/uui unlock|r - deverrouiller les cadres pour les deplacer",
CMD_LOCK                  = "  |cffffff00/uui lock|r - verrouiller les cadres",
CMD_RESET                 = "  |cffffff00/uui reset|r - reinitialiser toutes les positions",
CMD_BIND                  = "  |cffffff00/uui bind|r - ouvrir les raccourcis rapides",
CMD_CHECK                 = "  |cffffff00/uui check|r - verification du runtime",
CMD_THEME                 = "  |cffffff00/uui theme <style>|r - choisir un theme (necessite /reload)",
CMD_LANGUAGE              = "  |cffffff00/uui lang <en/cn/ru/fr>|r - choisir une langue (necessite /reload)",
CMD_PROFILE               = "  |cffffff00/uui profile create <nom>|r - creer et selectionner un profil partage",
CMD_DEBUG                 = "  |cffffff00/uui debug|r - activer/desactiver la sortie de debogage",
CMD_DIAGNOSTICS           = "  |cffffff00/uui help diag|r - lister les diagnostics",
CMD_UNKNOWN               = "commande inconnue : %s",
CMD_SETTINGS_UNAVAILABLE  = "l'interface de reglages n'est pas encore disponible dans cette version.",
CMD_LANGUAGE_CURRENT      = "langue : |cffffff00%s|r",
CMD_LANGUAGE_AVAILABLE    = "langues disponibles :",
CMD_PROFILE_CURRENT       = "profil actuel : |cffffff00%s|r",
CMD_PROFILE_CREATE_USAGE  = "  |cffffff00/uui profile create <nom>|r",
CMD_PROFILE_UNAVAILABLE   = "la gestion des profils n'est pas disponible dans cette version",
CMD_PROFILE_EXISTS        = "un profil nomme |cffffff00%s|r existe deja",
CMD_PROFILE_NAME_RULES    = "les noms de profil peuvent contenir des lettres, des chiffres, des espaces, des tirets et des traits de soulignement (64 caracteres maximum)",
CMD_PROFILE_CREATED       = "profil |cffffff00%s|r cree et selectionne - |cffffff00/reload|r pour l'appliquer",

})
