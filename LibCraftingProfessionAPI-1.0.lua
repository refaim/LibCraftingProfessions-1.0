---@type LibStubDef
local LibStub = getglobal("LibStub")
assert(LibStub ~= nil)

local MAJOR, MINOR = "LibCraftingProfessionAPI-1.0", 1
local library, _ = LibStub:NewLibrary(MAJOR, MINOR)
if not library then
    return
end

---@class LibCraftingProfessionAPI

local LibCraftingProfessionAPI = --[[---@type LibCraftingProfessionAPI]] library

local AceEvent, _ = LibStub("AceEvent-3.0", false)

---@shape LpProfession
---@field name string
---@field cur_rank number

---@shape LpSkill
---@field name string
---@field item_link string
---@field difficulty "trivial" | "easy" | "medium" | "optimal" | "difficult"
---@field num_available number

---@type table<string, LpSkill[]>
local skills_by_profession = {}

---@return boolean
local function ready(value)
    if value == nil then
        return false
    end
    if type(value) == "table" then
        return next(value) ~= nil
    end
    return value ~= "" and value ~= 0
end

---@return string[]
function LibCraftingProfessionAPI:GetAllKnownProfessions()
    return {
        "Alchemy",
        "Blacksmithing",
        "Cooking",
        "Enchanting",
        "Engineering",
        "First Aid",
        "Leatherworking",
        "Mining",
        "Tailoring",
    }
end

---@return LpProfession[]|nil
function LibCraftingProfessionAPI:GetProfessionsKnownByCharacter()
    local num_of_professions = GetNumSkillLines()
    if not ready(num_of_professions) then
        return nil
    end

    ---@type table<string, true>
    local set_of_known_professions = {}
    for _, profession in ipairs(self:GetAllKnownProfessions()) do
        set_of_known_professions[profession] = true
    end

    ---@type LpProfession[]
    local professions = {}
    for i = 1, num_of_professions do
        local name, is_header, _, rank, _, _, _, _, _, _, _, _, _ = GetSkillLineInfo(i)
        if not is_header then
            if not ready(name) or not ready(rank) then
                return nil
            end
            if set_of_known_professions[name] ~= nil then
                ---@type LpProfession
                local profession = {name = name, cur_rank = rank}
                tinsert(professions, profession)
            end
        end
    end

    return professions
end

---@param profession string
---@return LpSkill[]|nil
function LibCraftingProfessionAPI:GetSkillsKnownByCharacter(profession) return skills_by_profession[profession] end

---@shape _LpTradeSkillFilterOption
---@field name string
---@field type "inv_slot" | "subclass"

---@shape _LpProfessionAdapter
---@field GetProfessionInfo fun():string|nil, number|nil, number|nil
---@field GetNumSkills fun():number|nil
---@field GetSkillInfo fun(index:number):string|nil, string|nil, number|nil, wowboolean
---@field GetSkillItemLink fun(index:number):string|nil
---@field ExpandHeader fun(index:number):void
---@field CollapseHeader fun(index:number):void
---@field DisableFilters fun():void

---@param adapter _LpProfessionAdapter
---@return LpSkill[]|nil
local function scan_skills(adapter)
    local profession, cur_rank, max_rank = adapter.GetProfessionInfo()
    if not ready(profession) or not ready(cur_rank) or not ready(max_rank) then
        return nil
    end

    adapter:DisableFilters()

    local num_of_skills_before_expansion = adapter.GetNumSkills()
    if not ready(num_of_skills_before_expansion) then
        return nil
    end

    ---@type table<string, true>
    local set_of_headers_to_collapse = {}
    for i = 1, num_of_skills_before_expansion do
        local skill_name, skill_type_or_difficulty, _, is_expanded = adapter.GetSkillInfo(i)
        if not ready(skill_name) or not ready(skill_type_or_difficulty) then
            return nil
        end
        if skill_type_or_difficulty == "header" and is_expanded == nil then
            set_of_headers_to_collapse[ --[[---@not nil]] skill_name] = true
        end
    end
    adapter.ExpandHeader(0)

    local num_of_skills_after_expansion = adapter.GetNumSkills()
    if not ready(num_of_skills_after_expansion) then
        return nil
    end

    ---@type LpSkill[]
    local skills = {}
    for i = 1, num_of_skills_after_expansion do
        local skill_name, skill_type_or_difficulty, num_available, _ = adapter.GetSkillInfo(i)
        if not ready(skill_name) or not ready(skill_type_or_difficulty) then
            return nil
        end
        if skill_type_or_difficulty ~= "header" then
            local item_link = adapter.GetSkillItemLink(i)
            if num_available == nil or not ready(item_link) then
                return nil
            end
            ---@type LpSkill
            local skill = {
                name = --[[---@not nil]] skill_name,
                item_link = --[[---@not nil]] item_link,
                difficulty = --[[---@type "trivial" | "easy" | "medium" | "optimal" | "difficult"]] skill_type_or_difficulty,
                num_available = --[[---@not nil]] num_available,
            }
            tinsert(skills, skill)
        end
    end

    for i = adapter.GetNumSkills(), 1, -1 do
        local skill_name, skill_type_or_difficulty, _, _ = adapter.GetSkillInfo(i)
        if skill_type_or_difficulty == "header" and set_of_headers_to_collapse[ --[[---@not nil]] skill_name] ~= nil then
            adapter.CollapseHeader(i)
        end
    end

    return skills
end

local function scan_craft_frame()
    ---@type _LpProfessionAdapter
    local adapter = {
        GetProfessionInfo = function()
            local name, cur_rank, max_rank = GetCraftDisplaySkillLine()
            if name == nil then -- GetCraftDisplaySkillLine() returns nil for the "Beast Training" frame
                name = GetCraftName()
            end
            return name, cur_rank, max_rank
        end,
        GetNumSkills = GetNumCrafts,
        GetSkillInfo = function(i)
            local name, _, type, num_available, is_expanded = GetCraftInfo(i)
            return name, type, num_available, is_expanded
        end,
        GetSkillItemLink = GetCraftItemLink,
        ExpandHeader = ExpandCraftSkillLine,
        CollapseHeader = CollapseCraftSkillLine,
        DisableFilters = function() end,
    }

    local profession, _, _ = adapter.GetProfessionInfo()
    if not ready(profession) or profession == "Beast Training" then
        return
    end

    local skills = scan_skills(adapter)
    if not ready(profession) or not ready(skills) then
        return
    end

    skills_by_profession[ --[[---@not nil]] profession] = skills
end

---@shape _LpSkillFilterAdapter
---@field GetType fun(): "inv_slot" | "subclass"
---@field GetOptions fun(): string...
---@field GetOptionState fun(index:number): wowboolean
---@field SetOptionState fun(index:number, enable:wowboolean, exclusive:wowboolean): void

---@param adapter _LpSkillFilterAdapter
---@return _LpTradeSkillFilterOption[]
local function disable_trade_skill_filters(adapter)
    if adapter.GetOptionState(0) == 1 then
        return {}
    end

    ---@type _LpTradeSkillFilterOption[]
    local selected_options = {}
    for i, option in ipairs({adapter.GetOptions()}) do
        if adapter.GetOptionState(i) == 1 then
            tinsert(selected_options, {name = option, type = adapter.GetType()})
        end
    end

    adapter.SetOptionState(0, 1, 1)

    return selected_options
end

local function scan_trade_skill_frame()
    ---@type _LpSkillFilterAdapter
    local inv_slot_filter_adapter = {
        GetType = function() return "inv_slot" end,
        GetOptions = GetTradeSkillInvSlots,
        GetOptionState = GetTradeSkillInvSlotFilter,
        SetOptionState = SetTradeSkillInvSlotFilter,
    }

    ---@type _LpSkillFilterAdapter
    local subclass_filter_adapter = {
        GetType = function() return "subclass" end,
        GetOptions = GetTradeSkillSubClasses,
        GetOptionState = GetTradeSkillSubClassFilter,
        SetOptionState = SetTradeSkillSubClassFilter,
    }

    ---@type _LpProfessionAdapter
    local profession_adapter = {
        GetProfessionInfo = GetTradeSkillLine,
        GetNumSkills = GetNumTradeSkills,
        GetSkillInfo = GetTradeSkillInfo,
        GetSkillItemLink = GetTradeSkillItemLink,
        ExpandHeader = ExpandTradeSkillSubClass,
        CollapseHeader = CollapseTradeSkillSubClass,
        DisableFilters = function()
            for _, adapter in ipairs({inv_slot_filter_adapter, subclass_filter_adapter}) do
                disable_trade_skill_filters(adapter)
            end
        end,
    }

    local profession, _, _ = profession_adapter.GetProfessionInfo()
    if not ready(profession) then
        return
    end

    local skills = scan_skills(profession_adapter)
    if not ready(skills) then
        return
    end

    skills_by_profession[ --[[---@not nil]] profession] = skills
end

local incoming_events = AceEvent:Embed({})
incoming_events:RegisterEvent("CRAFT_SHOW", scan_craft_frame)
incoming_events:RegisterEvent("TRADE_SKILL_SHOW", scan_trade_skill_frame)
