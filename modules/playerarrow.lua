-- unrealUI :: modules/playerarrow.lua

local U = UnrealUI
local M = U.media
local ARROW = U.RegisterModule("playerarrow")

local state = {}

local function NumberMethod(object, method)
  if not object or type(object[method]) ~= "function" then return nil end
  local ok, value = pcall(object[method], object)
  if ok then return tonumber(value) end
  return nil
end

local function MakeArrow(name, parent, size, texturePath)
  if not parent then return nil end
  local frame = CreateFrame("Frame", name, parent)
  if not frame then return nil end

  frame:Hide()
  frame:SetWidth(size)
  frame:SetHeight(size)
  frame:SetFrameLevel((NumberMethod(parent, "GetFrameLevel") or 0) + 8)
  if frame.EnableMouse then frame:EnableMouse(false) end

  local texture = frame:CreateTexture(nil, "OVERLAY")
  if not texture then
    frame:Hide()
    return nil
  end
  texture:SetTexture(texturePath or M.playerArrow.texture)
  texture:SetAllPoints(frame)
  frame.arrow = texture
  return frame
end

local function SetCell(texture, cell, layout)
  layout = layout or M.playerArrow
  local columns = layout.columns
  local row = math.floor(cell / columns)
  local column = cell - row * columns
  texture:SetTexCoord(column / columns, (column + 1) / columns,
    row / columns, (row + 1) / columns)
end

local function FacingCell()
  local getFacing = U.G("GetPlayerFacing")
  if type(getFacing) ~= "function" then return nil end
  local ok, facing = pcall(getFacing)
  if not ok or type(facing) ~= "number" then return nil end

  local turn = math.pi * 2
  facing = facing - math.floor(facing / turn) * turn
  local cell = math.floor(facing / turn * M.playerArrow.frames + 0.5)
  if cell >= M.playerArrow.frames then cell = 0 end
  return cell
end

local function Atan2(y, x)
  if x > 0 then return math.atan(y / x) end
  if x < 0 then
    if y >= 0 then return math.atan(y / x) + math.pi end
    return math.atan(y / x) - math.pi
  end
  if y > 0 then return math.pi / 2 end
  if y < 0 then return -math.pi / 2 end
  return 0
end

local function ApplyWorldMapStockPosition(point, relativeTo, relativePoint, x, y)
  local frame = state.worldMap
  if not frame or type(point) ~= "string" or not relativeTo or
     type(relativePoint) ~= "string" or type(x) ~= "number" or
     type(y) ~= "number" then return end

  local getPosition = U.G("GetPlayerMapPosition")
  local valid, mapX, mapY
  if type(getPosition) == "function" then
    valid, mapX, mapY = pcall(getPosition, "player")
  end
  if not valid or type(mapX) ~= "number" or type(mapY) ~= "number" or
     (mapX <= 0 and mapY <= 0) then
    frame:Hide()
    return
  end

  frame:ClearAllPoints()
  local ok = pcall(frame.SetPoint, frame, point, relativeTo, relativePoint, x, y)
  if not ok then
    frame:Hide()
    return
  end
  frame:Show()
end

local function UpdateWorldMapPosition()
  local frame = state.worldMap
  local canvas = U.G("WorldMapButton")
  local getPosition = U.G("GetPlayerMapPosition")
  if not frame or not canvas or type(getPosition) ~= "function" then return end

  local ok, x, y = pcall(getPosition, "player")
  local width = NumberMethod(canvas, "GetWidth")
  local height = NumberMethod(canvas, "GetHeight")
  if not ok or type(x) ~= "number" or type(y) ~= "number" or
     not width or not height or width <= 0 or height <= 0 or
     (x <= 0 and y <= 0) then
    frame:Hide()
    return
  end

  frame:ClearAllPoints()
  frame:SetPoint("CENTER", canvas, "TOPLEFT", x * width, -y * height)
  frame:Show()
end

-- The native corpse pointer cannot be removed on this client: SetArrowModel,
-- SetIconTexture and SetBlipTexture leave it unchanged and no other Minimap
-- method or widget reaches it (knowledge.json /
-- minimap.corpse_pointer_not_removable). The gold arrow is drawn beside it.
local function HideCorpseArrow()
  if state.corpse then state.corpse:Hide() end
end

local function UpdateCorpseArrow()
  local frame = state.corpse
  local minimap = U.G("Minimap")
  local layout = M.corpseArrow
  local isDead = U.G("UnitIsDeadOrGhost")
  local getPlayer = U.G("GetPlayerMapPosition")
  local getCorpse = U.G("GetCorpseMapPosition")
  if not frame or not minimap or not layout or type(isDead) ~= "function" or
     type(getPlayer) ~= "function" or type(getCorpse) ~= "function" then
    HideCorpseArrow()
    return
  end

  local deadOK, dead = pcall(isDead, "player")
  local playerOK, playerX, playerY = pcall(getPlayer, "player")
  local corpseOK, corpseX, corpseY = pcall(getCorpse)
  local width = NumberMethod(minimap, "GetWidth")
  local height = NumberMethod(minimap, "GetHeight")
  if not deadOK or not dead or not playerOK or not corpseOK or
     type(playerX) ~= "number" or type(playerY) ~= "number" or
     type(corpseX) ~= "number" or type(corpseY) ~= "number" or
     not width or not height or width <= 0 or height <= 0 or
     (playerX <= 0 and playerY <= 0) or
     (corpseX <= 0 and corpseY <= 0) then
    HideCorpseArrow()
    return
  end

  -- Map UVs are not square: a zone map spans about 1.5 times as many yards
  -- across as down, so scale each axis by the map canvas before the bearing.
  local canvas = U.G("WorldMapButton")
  local mapWidth = NumberMethod(canvas, "GetWidth")
  local mapHeight = NumberMethod(canvas, "GetHeight")
  if not mapWidth or not mapHeight or mapWidth <= 0 or mapHeight <= 0 then
    mapWidth, mapHeight = layout.mapAspect, 1
  end
  local dx = (corpseX - playerX) * mapWidth
  local dy = (corpseY - playerY) * mapHeight
  if dx == 0 and dy == 0 then
    HideCorpseArrow()
    return
  end
  local turn = math.pi * 2
  local angle = Atan2(-dx, -dy)
  if angle < 0 then angle = angle + turn end
  local cell = math.floor(angle / turn * layout.frames + 0.5)
  if cell >= layout.frames then cell = 0 end
  if cell ~= state.corpseCell then
    state.corpseCell = cell
    SetCell(frame.arrow, cell, layout)
  end

  local inset = layout.visibleSize / 2
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", minimap, "CENTER",
    -math.sin(angle) * (width / 2 - inset),
    math.cos(angle) * (height / 2 - inset))
  frame:Show()
end

local function Refresh()
  local cell = FacingCell()
  if cell ~= nil and cell ~= state.cell then
    state.cell = cell
    if state.minimap then SetCell(state.minimap.arrow, cell) end
    if state.worldMap then SetCell(state.worldMap.arrow, cell) end
  end
  UpdateWorldMapPosition()
  UpdateCorpseArrow()
end

local function InstallWorldMapPark()
  local original = U.G("PositionWorldMapArrowFrame")
  if type(original) ~= "function" then return false end

  local park = M.playerArrow.parkOffset
  local function Wrapped(a1, a2, a3, a4, a5, a6)
    ApplyWorldMapStockPosition(a1, a2, a3, a4, a5)
    if type(a2) == "number" then a2 = park end
    if type(a3) == "number" then a3 = park end
    if type(a4) == "number" then a4 = park end
    if type(a5) == "number" then a5 = park end
    return original(a1, a2, a3, a4, a5, a6)
  end

  PositionWorldMapArrowFrame = Wrapped
  if U.G("PositionWorldMapArrowFrame") ~= Wrapped then return false end
  state.originalWorldMapPosition = original
  pcall(original, "CENTER", park, park)
  return true
end

local function BuildMinimapArrow()
  local minimap = U.G("Minimap")
  if not minimap or type(minimap.SetPlayerModel) ~= "function" then return nil end
  local frame = MakeArrow("UnrealUIPlayerArrowMinimap", minimap,
    M.playerArrow.minimapTextureSize)
  if not frame then return nil end
  frame:SetPoint("CENTER", minimap, "CENTER", 0, 0)
  if not pcall(minimap.SetPlayerModel, minimap, "") then
    frame:Hide()
    return nil
  end
  return frame
end

local function BuildMinimapCorpseArrow()
  local minimap = U.G("Minimap")
  local layout = M.corpseArrow
  if not minimap or not layout then return nil end
  return MakeArrow("UnrealUIPlayerCorpseArrowMinimap", minimap,
    layout.textureSize, layout.texture)
end

local function BuildWorldMapArrow()
  local canvas = U.G("WorldMapButton")
  if not canvas then return nil end
  local frame = MakeArrow("UnrealUIPlayerArrowWorldMap", canvas,
    M.playerArrow.worldMapTextureSize)
  if frame then frame:Hide() end
  return frame
end

function ARROW:OnEnable()
  if state.enabled then return end
  if not M.playerArrow or type(U.G("GetPlayerFacing")) ~= "function" then
    U.Debug("player arrow: facing or media unavailable; native arrows retained")
    return
  end

  local initialCell = FacingCell()
  if initialCell == nil then
    U.Debug("player arrow: facing unreadable; native arrows retained")
    return
  end

  state.minimap = BuildMinimapArrow()
  state.corpse = BuildMinimapCorpseArrow()
  state.worldMap = BuildWorldMapArrow()
  if state.worldMap and not InstallWorldMapPark() then
    state.worldMap:Hide()
    state.worldMap = nil
  end

  if not state.minimap and not state.worldMap and not state.corpse then
    U.Debug("player arrow: replacement unavailable; native arrows retained")
    return
  end

  state.cell = initialCell
  if state.minimap then
    SetCell(state.minimap.arrow, initialCell)
    state.minimap:Show()
  end
  if state.worldMap then SetCell(state.worldMap.arrow, initialCell) end
  state.enabled = true
  Refresh()
  U.RegisterUpdate("playerarrow.refresh", M.playerArrow.updateInterval, Refresh)
end
