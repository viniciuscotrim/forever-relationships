-- Groups: personal labels for the players in your Circle. Local only: never sent,
-- never shown to anyone else.
-- Built-in groups fill themselves from what the game recorded (thresholds in
-- Settings › Groups); you can add anyone to any group, remove someone from an
-- automatic group (that choice sticks), and create, rename or delete your own groups.
--   ForeverRelationshipsDB.groups = { custom = { { key, name } }, manual = { [guid] = { [key] = true|false } }, nextId }
local _, FR = ...

local Groups = {}
FR.Groups = Groups

local MAX_CUSTOM = 30
local MAX_NAME = 32

-- Built-in groups and the rule that fills each one (r = relationship, rv = rival counters).
Groups.BUILTIN = {
  { key = "questHelper", name = "Quest Helper", desc = "Quests completed together, or help received while questing.",
    auto = function(r) return r and (r.quests + (r.helpReceivedTotal or 0)) >= FR.Params:Get("groups.questHelper") end },
  { key = "dungeonBuddy", name = "Dungeon Buddy", desc = "Dungeons completed together.",
    auto = function(r) return r and r.dungeons >= FR.Params:Get("groups.dungeonBuddy") end },
  { key = "raidChampion", name = "Raid Champion", desc = "Raids completed together.",
    auto = function(r) return r and r.raids >= FR.Params:Get("groups.raidChampion") end },
  { key = "rival", name = "Rival", desc = "Opposite-faction players you fought.",
    auto = function(_, rv) return rv and rv.battles >= FR.Params:Get("groups.rival") end },
}
Groups.BY_KEY = {}
for _, g in ipairs(Groups.BUILTIN) do Groups.BY_KEY[g.key] = g end

function Groups:Store()
  FR.db.groups = FR.db.groups or {}
  local s = FR.db.groups
  s.custom = s.custom or {}
  s.manual = s.manual or {}
  s.nextId = s.nextId or 1
  return s
end

-- Every group, built-in first: { key, name, builtin, desc }
function Groups:All()
  local out = {}
  for _, g in ipairs(self.BUILTIN) do out[#out + 1] = { key = g.key, name = FR.L[g.name], builtin = true, desc = FR.L[g.desc] } end
  for _, g in ipairs(self:Store().custom) do out[#out + 1] = { key = g.key, name = g.name, builtin = false } end
  return out
end

function Groups:Name(key)
  local b = self.BY_KEY[key]
  if b then return FR.L[b.name] end
  for _, g in ipairs(self:Store().custom) do if g.key == key then return g.name end end
  return nil
end

local function Clean(name)
  if type(name) ~= "string" then return nil end
  name = name:gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return nil end
  return name:sub(1, MAX_NAME)
end

function Groups:Create(name)
  name = Clean(name)
  local s = self:Store()
  if not name then return nil, FR.L["Type a name for the group."] end
  if #s.custom >= MAX_CUSTOM then return nil, FR.L["You can have up to 30 groups of your own."] end
  for _, g in ipairs(self:All()) do
    if g.name:lower() == name:lower() then return nil, FR.L["A group with this name already exists."] end
  end
  local key = "c" .. s.nextId
  s.nextId = s.nextId + 1
  table.insert(s.custom, { key = key, name = name })
  FR:Fire("GROUPS_CHANGED")
  return key
end

function Groups:Rename(key, name)
  name = Clean(name)
  if not name then return false end
  for _, g in ipairs(self:Store().custom) do
    if g.key == key then g.name = name; FR:Fire("GROUPS_CHANGED"); return true end
  end
  return false
end

function Groups:Delete(key)
  local s = self:Store()
  for i, g in ipairs(s.custom) do
    if g.key == key then
      table.remove(s.custom, i)
      for _, m in pairs(s.manual) do m[key] = nil end
      FR:Fire("GROUPS_CHANGED")
      return true
    end
  end
  return false
end

-- Automatic membership from the recorded facts.
function Groups:Auto(guid)
  local out = {}
  local r = FR.db.players[guid] and FR.Rel:Compute(guid) or nil
  if r then
    r.helpReceivedTotal = 0
    for _, n in pairs(r.helpReceived or {}) do r.helpReceivedTotal = r.helpReceivedTotal + n end
  end
  local rv = FR.Rivals and FR.Rivals:Get(guid)
  for _, g in ipairs(self.BUILTIN) do
    if g.auto(r, rv) then out[g.key] = true end
  end
  return out
end

-- Effective membership: automatic, plus your additions, minus your removals.
function Groups:Of(guid)
  local set = self:Auto(guid)
  local auto = {}
  for k in pairs(set) do auto[k] = true end
  for k, v in pairs(self:Store().manual[guid] or {}) do
    if v == true and (self.BY_KEY[k] or self:Name(k)) then set[k] = true elseif v == false then set[k] = nil end
  end
  return set, auto
end

function Groups:Has(guid, key)
  return self:Of(guid)[key] == true
end

-- Toggle a player in a group. Turning off an automatic group is remembered.
function Groups:Set(guid, key, on)
  local s = self:Store()
  local auto = self:Auto(guid)[key] == true
  s.manual[guid] = s.manual[guid] or {}
  -- remember only what differs from the automatic rule (true = added, false = removed)
  local v = nil
  if on and not auto then v = true elseif not on and auto then v = false end
  s.manual[guid][key] = v
  if next(s.manual[guid]) == nil then s.manual[guid] = nil end
  FR:Fire("GROUPS_CHANGED")
end

-- Sorted group names for one player ("Dungeon Buddy, Raiders").
function Groups:Label(guid)
  local set = self:Of(guid)
  local names = {}
  for _, g in ipairs(self:All()) do if set[g.key] then names[#names + 1] = g.name end end
  return table.concat(names, ", ")
end

return Groups
