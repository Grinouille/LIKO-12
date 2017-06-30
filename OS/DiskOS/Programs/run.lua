--This file loads a lk12 disk and executes it

--First we will start by obtaining the disk data
--We will run the current code in the editor
local term = require("C://terminal")
local eapi = require("C://Editors")
local mapobj = require("C://Libraries/map")

local sprid = 3 --"spritesheet"
local codeid = 2 --"luacode"
local tileid = 4 --"tilemap"

local swidth, sheight = screenSize()

--Load the spritesheet
local SpriteMap, FlagsData
local sheetImage = image(eapi.leditors[sprid]:exportImage())
local FlagsData = eapi.leditors[sprid]:getFlags()
local sheetW, sheetH = sheetImage:width()/8, sheetImage:height()/8
SpriteMap = SpriteSheet(sheetImage,sheetW,sheetH)

--Load the tilemap
local mapData = eapi.leditors[tileid]:export()
local mapW, mapH = swidth*0.75, sheight
local TileMap = mapobj(mapW,mapH,SpriteMap)
TileMap:import(mapData)

--Load the code
local luacode = eapi.leditors[codeid]:export()
luacode = luacode .. "\n__".."_autoEventLoop()" --Because trible _ are not allowed in LIKO-12
local diskchunk, err = loadstring(luacode)
if not diskchunk then
  local err = tostring(err)
  local pos = string.find(err,":")
  err = err:sub(pos+1,-1)
  color(8) print("Compile ERR: "..err )
  return
end

--Upload the data to the ram
local SpriteSheetAddr = binToNum(memget(0x0054, 4))
local MapDataAddr = binToNum(memget(0x0058, 4))
local LuaCodeAddr = binToNum(memget(0x0068, 4))
local SpriteFlagsAddr = SpriteSheetAddr + 12*1024

memset(SpriteSheetAddr, imgToBin(sheetImage))
memset(SpriteFlagsAddr, FlagsData)
memset(MapDataAddr, mapToBin(TileMap))
memset(LuaCodeAddr, codeToBin(luacode:sub(1,20*1024)))

--Create the sandboxed global variables
local glob = _Freshglobals()
glob._G = glob --Magic ;)

local co

glob.getfenv = function(f)
  if type(f) ~= "function" then return error("bad argument #1 to 'getfenv' (function expected, got "..type(f)) end
  local ok, env = pcall(getfenv,f)
  if not ok then return error(env) end
  if env == _G then env = {} end --Protection
  return env
end
glob.setfenv = function(f,env)
  if type(f) ~= "function" then return error("bad argument #1 to 'setfenv' (function expected, got "..type(f)) end
  if type(env) ~= "table" then return error("bad argument #2 to 'setfenv' (table expected, got "..type(env)) end
  local oldenv = getfenv(f)
  if oldenv == _G then return end --Trying to make a crash ! evil.
  local ok, err = pcall(setfenv,f,env)
  if not ok then return error(err) end
end
glob.loadstring = function(data)
  local chunk, err = loadstring(data)
  if not chunk then return nil, err end
  setfenv(chunk,glob)
  return chunk
end
glob.coroutine.running = function()
  local curco = coroutine.running()
  if co and curco == co then return end
  return curco
end

--Add peripherals api
local blocklist = { HDD = true, WEB = true, Floppy = true }
local perglob = {GPU = true, CPU = true, Keyboard = true, RAM = true} --The perihperals to make global not in a table.

local _,directapi = coroutine.yield("BIOS:DirectAPI"); directapi = directapi or {}
local _,perlist = coroutine.yield("BIOS:listPeripherals")
for k, v in pairs(blocklist) do perlist[k] = nil end
for peripheral,funcs in pairs(perlist) do
 local holder = glob; if not perglob[peripheral] then glob[peripheral] = {}; holder = glob[peripheral] end
 for _,func in ipairs(funcs) do
  if func:sub(1,1) ~= "_" then
   if directapi[peripheral] and directapi[peripheral][func] then
    holder[func] = directapi[peripheral][func]
   else
    local command = peripheral..":"..func
    holder[func] = function(...)
     local args = {coroutine.yield(command,...)}
     if not args[1] then return error(args[2]) end
     local nargs = {}
     for k,v in ipairs(args) do
      if k >1 then table.insert(nargs,k-1,v) end
     end
     return unpack(nargs)
    end
   end
  end
 end
end

local apiloader = loadstring(fs.read("C://api.lua"))
setfenv(apiloader,glob) apiloader()

local function autoEventLoop()
  if glob._init and type(glob._init) == "function" then
    glob._init()
  end
  if type(glob._eventLoop) == "boolean" and not glob._eventLoop then return end --Skip the auto eventLoop.
  if glob._update or glob._draw or glob._eventLoop then
    eventLoop()
  end
end

setfenv(autoEventLoop,glob)

--Add special disk api
glob.SpriteMap = SpriteMap
glob.SheetFlagsData = FlagsData
glob.TileMap = TileMap
glob.MapObj = mapobj

local UsedDoFile = false --So it can be only used for once
glob.dofile = function(path)
  if UsedDoFile then return error("dofile() can be only used for once !") end
  UsedDoFile = true
  local chunk, err = fs.load(path)
  if not chunk then return error(err) end
  setfenv(chunk,glob)
  local ok, err = pcall(chunk)
  if not ok then return error(err) end
end
glob["__".."_".."autoEventLoop"] = autoEventLoop --Because trible _ are not allowed in LIKO-12

local helpersloader, err = loadstring(fs.read("C://Libraries/diskHelpers.lua"))
if not helpersloader then error(err) end
setfenv(helpersloader,glob) helpersloader()

--Apply the sandbox
setfenv(diskchunk,glob)

--Create the coroutine
co = coroutine.create(diskchunk)

--Too Long Without Yielding
local checkclock = true
local eventclock = os.clock()
local lastclock = os.clock()
coroutine.sethook(co,function()
  if os.clock() > lastclock + 3.5 and checkclock then
    error("Too Long Without Yielding",2)
  end
end,"",10000)

--Run the thing !
local function extractArgs(args,factor)
  local nargs = {}
  for k,v in ipairs(args) do
    if k > factor then table.insert(nargs,v) end
  end
  return nargs
end

local lastArgs = {}
while true do
  if coroutine.status(co) == "dead" then break end
  
  if os.clock() > eventclock + 3.5 then
    color(8) print("Too Long Without Pulling Event / Flipping") break
  end
  
  local args = {coroutine.resume(co,unpack(lastArgs))}
  checkclock = false
  if not args[1] then
    local err = tostring(args[2])
    local pos = string.find(err,":") or 0
    err = err:sub(pos+1,-1); color(8) print("ERR: "..err ); break
  end
  if args[2] then
    lastArgs = {coroutine.yield(args[2],unpack(extractArgs(args,2)))}
    if args[2] == "CPU:pullEvent" or args[2] == "CPU:rawPullEvent" or args[2] == "GPU:flip" or args[2] == "CPU:sleep" then
      eventclock = os.clock()
      if args[2] == "GPU:flip" or args[2] == "CPU:sleep" then
        local name, key = rawPullEvent()
        if name == "keypressed" and key == "escape" then
          break
        end
      else
        if lastArgs[1] and lastArgs[2] == "keypressed" and lastArgs[3] == "escape" then
          break
        end
      end
    end
    lastclock = os.clock()
    checkclock = true
  end
end

coroutine.sethook(co)
clearEStack()
print("")