-- Project: PonyTiled a Corona Tiled Map Loader
--
-- Loads LUA saved map files from Tiled http://www.mapeditor.org/

local M = {}
local physics = require "physics"

local FlippedHorizontallyFlag   = 0x80000000
local FlippedVerticallyFlag     = 0x40000000
local FlippedDiagonallyFlag     = 0x20000000
local ClearFlag                 = 0x1FFFFFFF

local function hasbit(x, p) return x % (p + p) >= p end
local function setbit(x, p) return hasbit(x, p) and x or x + p end
local function clearbit(x, p) return hasbit(x, p) and x - p or x end

local function inherit(image, properties)
  for k,v in pairs(properties) do
    image[k] = v
  end
  return image
end

local function centerAnchor(image)
  if image.contentBounds then 
    local bounds = image.contentBounds
    local actualCenterX, actualCenterY =  (bounds.xMin + bounds.xMax)/2 , (bounds.yMin + bounds.yMax)/2
    image.anchorX, image.anchorY = 0.5, 0.5  
    image.x = actualCenterX
    image.y = actualCenterY 
  end
end

local function decodeTiledColor(hex)
  hex = hex or "#FF888888"
  hex = hex:gsub("#","")
  local function hexToFloat(part)
    return tonumber("0x".. part or "00") / 255
  end
  local a, r, g, b =  hexToFloat(hex:sub(1,2)), hexToFloat(hex:sub(3,4)), hexToFloat(hex:sub(5,6)) , hexToFloat(hex:sub(7,8)) 
  return r,g,b,a
end

function M.new(data)
  local map = display.newGroup()  

  local layers = data.layers
  local tilesets = data.tilesets
  local width, height = data.width * data.tilewidth, data.height * data.tileheight

  local function gidLookup(gid)
    -- turn a gid into a filename
    for i = 1, #tilesets do
      local tileset = tilesets[i]
      local firstgid = tileset.firstgid
      local lastgid = firstgid + tileset.tilecount 
      if gid >= firstgid and gid <= lastgid then
        for k,v in pairs(tileset.tiles) do
          local tile = tileset.tiles[j]
          if (v.id or tonumber(k)) == (gid - firstgid) then
            return v.image -- may need updating with documents directory
          end
        end
      end
    end
    return false
  end

  for i = 1, #layers do
    local layer = layers[i]
    layer.properties = layer.properties or {} -- make sure we have a properties table
    if layer.type == "objectgroup" then
      local objectGroup = display.newGroup()
      for j = 1, #layer.objects do
        local object = layer.objects[j]
        object.properties = object.properties or {} -- make sure we have a properties table
        if object.gid then
          -- Flipping merged from code by Sergey Lerg
          local gid = object.gid
          local flip = {}
          flip.x = hasbit(gid, FlippedHorizontallyFlag)
          flip.y = hasbit(gid, FlippedVerticallyFlag)          
          flip.xy = hasbit(gid, FlippedDiagonallyFlag) 
          gid = clearbit(gid, FlippedHorizontallyFlag)
          gid = clearbit(gid, FlippedVerticallyFlag)
          gid = clearbit(gid, FlippedDiagonallyFlag)
          gid = gidLookup(gid)
          if gid then
            local image = display.newImageRect(gid, object.width, object.height)
            -- name and type
            image.name = object.name
            image.type = object.type        
            -- apply base properties
            image.anchorX, image.anchorY = 0, 1
            image.x, image.y = object.x, object.y
            image.rotation = object.rotation
            image.isVisible = object.visible
            centerAnchor(image)
            -- flip it
            if flip.xy then
              print("WARNING: Unsupported Tiled rotation x,y in ", object.name)
            else
              if flip.x then
                image.xScale = -1
              end
              if flip.y then
                image.yScale = -1
              end
            end          
            -- simple phyics
            if object.properties.bodyType then
              physics.addBody(image, object.properties.bodyType, object.properties)
            end          
            -- apply custom properties
            image = inherit(image, object.properties)
            image = inherit(image, layer.properties)
            objectGroup:insert(image)
          end
        else -- if all else fails make a simple rect
          local rect = display.newRect(0,0, object.width, object.height)
          rect.anchorX, rect.anchorY = 0, 0
          rect.x, rect.y = object.x, object.y
          centerAnchor(rect)
          -- apply custom properties
          rect = inherit(rect, object.properties)
          rect = inherit(rect, layer.properties)          
          if rect.fillColor then rect:setFillColor(decodeTiledColor(rect.fillColor)) end
          if rect.strokeColor then rect:setStrokeColor(decodeTiledColor(rect.strokeColor)) end                
          objectGroup:insert(rect)
        end
      end
      objectGroup.name = layer.name
      objectGroup.isVisible = layer.visible
      objectGroup.alpha = layer.opacity
      map:insert(objectGroup)
    end
  end

  function map:extend(...)
    local plugins = arg or {}
    -- each custom object above has its own ponywolf.plugin module
    for t = 1, #plugins do 
      -- load each module based on type
      local plugin = require ("com.ponywolf.plugins." .. plugins[t])
      -- find each type of tiled object
      local images = map:listTypes(plugins[t])
      if images then 
        -- do we have at least one?
        for i = 1, #images do
          -- extend the display object with its own custom code
          images[i] = plugin.new(images[i])
        end
      end  
    end
  end

  -- return first display object with name
  function map:findObject(name)
    for layers = self.numChildren,1,-1 do
      local layer = self[layers]
      if layer.numChildren then
        for i = layer.numChildren,1,-1 do
          if layer[i].name == name then
            return layer[i]
          end
        end
      end
    end
    return false
  end

  -- return all display objects with type
  function map:listTypes(...)
    local objects = {}
    for layers = self.numChildren,1,-1 do
      local layer = self[layers]
      if layer.numChildren then
        for i = layer.numChildren,1,-1 do
          for j = 1, #arg do 
            if arg[j]==nil or layer[i].type == arg[j] then
              objects[#objects+1] = layer[i]
            end
          end
        end
      end
    end
    return objects
  end

  -- add helpful values to the map itself
  map.designedWidth, map.designedHeight = width, height
  return map
end

return M