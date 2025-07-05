local suppressLogging = false

local inputFile = arg[1] or "script.lua"
local outputFile = inputFile:gsub("%.lua$", "-deob.lua")

-- Override default tostring behavior
local original_tostring = tostring
function tostring(obj)
    if type(obj) == "function" then
        return "function"
    elseif type(obj) == "table" then
        if getmetatable(obj) == objectMeta and obj.__name then
            return obj.__name
        end
        return "table"
    else
        return original_tostring(obj)
    end
end

-- Custom function representation
local function formatFunction(f, name)
    if name then
        return "function "..name.."(...) end"
    else
        return "function(...) end"
    end
end

local log, name_counts, objects = {}, {}, {}
local declared_locals, declared_functions = {}

local function declareTable(name, tbl)
    log[#log+1] = ("local %s = {"):format(name)
    for k, v in pairs(tbl) do
        local key = type(k) == "string" and k or ("[" .. tostring(k) .. "]")
        local val
        if type(v) == "string" then
            val = ("%q"):format(v)
        elseif type(v) == "boolean" or type(v) == "number" then
            val = tostring(v)
        elseif type(v) == "table" and tostring(v):match("^Color3") then
            val = tostring(v)
        else
            val = "nil"
        end
        log[#log+1] = ("    %s = %s,"):format(key, val)
    end
    log[#log+1] = "}"
end


local function formatKey(k)
    if type(k) ~= "string" then return "[" .. tostring(k) .. "]"
    elseif k:match("^[%a_][%w_]*$") then return "." .. k
    else return "[" .. ("%q"):format(k) .. "]" end
end

local function getNiceName(base)
    base = base:gsub("^%l", string.upper)
    local count = (name_counts[base] or 0) + 1
    name_counts[base] = count
    local clean = base:sub(1,1):lower() .. base:sub(2)
    return count > 1 and (clean .. count) or clean
end


local function logCall(name, ...)
    local args = {...}
    for i,v in ipairs(args) do args[i] = type(v) == "string" and ("%q"):format(v) or tostring(v) end
    return name .. "(" .. table.concat(args, ", ") .. ")"
end

local function genEnvTable(name)
    local data = {}
    return setmetatable({}, {
        __index = function(_, k)
            local val = data[k]
            if val ~= nil then
                log[#log+1] = ("-- accessed %s%s (%s)"):format(name, formatKey(k), tostring(val))
                return val
            else
                local dummy = function(...) log[#log+1] = ("-- dummy function %s%s called"):format(name, formatKey(k)) end
                data[k] = dummy
                return dummy
            end
        end,
        __newindex = function(_, k, v)
            local function formatValue(v)
    if type(v) == "string" then
        return ("%q"):format(v)
    elseif type(v) == "function" then
        return nil -- Skip functions entirely
    elseif type(v) == "table" then
        if getmetatable(v) == objectMeta and v.__name then
            return v.__name -- Return object name if it's one of our tracked objects
        end
        -- Handle array-style tables
        if #v > 0 then
            local items = {}
            for i, val in ipairs(v) do
                table.insert(items, formatValue(val))
            end
            return ("{ %s }"):format(table.concat(items, ", "))
        end
        return "{}" -- Empty table
    else
        return tostring(v)
    end
end

local function formatKey(k)
    if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        return "." .. k
    else
        return "[" .. formatValue(k) .. "]"
    end
end

data[k] = v
local vs = formatValue(v)
log[#log+1] = ("%s%s = %s"):format(name or "fenv", formatKey(k), vs)


        end
    })
end


local function trackFunction(name)
    local fname = name or "anonFunc" .. tostring(#declared_functions + 1)
    log[#log+1] = string.format("function %s(...)", fname)
    log[#log+1] = "    -- traced logic"
    log[#log+1] = "end"
    table.insert(declared_functions, fname)
    return function(...) end
end



local function declareVariable(name, value)
    local val = type(value) == "string" and ("%q"):format(value) or tostring(value)
    log[#log+1] = ("local %s = %s"):format(name, val)
    declared_locals[name] = true
    return value
end

local function Vector3_new(x,y,z)
    return setmetatable({}, { __tostring = function() return logCall("Vector3.new", x, y, z) end })
end

local function UDim2_new(a,b,c,d)
    return setmetatable({}, { __tostring = function() return logCall("UDim2.new", a,b,c,d) end })
end

local function Color3_fromRGB(r,g,b)
    return setmetatable({}, { __tostring = function() return logCall("Color3.fromRGB", r,g,b) end })
end

local function UDim_new(scale, offset)
    return setmetatable({}, {
        __tostring = function() return ("UDim.new(%s, %s)"):format(scale, offset) end
    })
end

local lastHttpGetUrl = nil
local objectMeta = {}
local function makeObject(name)
    return setmetatable({ __name = name }, objectMeta)
end
local loggedMethods = {
    Kick = true,
    FireServer = true,
    MoveTo = true,
    Destroy = true,
    Clone = true,
    Play = true,
    Stop = true,
    Pause = true,
    Resume = true,
    Disconnect = true,
    Remove = true,
    TweenSize = true,
    SetCore = true,
    Create = true  -- ADDED FOR TWEENSERVICE
}



local methodsWithReturn = {
    Clone = true,
    FindFirstChild = true,
    WaitForChild = true
}

objectMeta.__index = function(t, k)
    local objName = t.__name

    -- Connection handler for all event types
    if k == "Connect" then
        return function(_, callback)
            log[#log+1] = ("%s:Connect(function()"):format(objName)
            log[#log+1] = "end)"
            return makeObject(objName.."_connection") -- Return mock connection object
        end
    end

    -- Special methods
    if k == "WaitForChild" or k == "FindFirstChild" then
        return function(_, child)
            local cname = objName .. "_" .. child
            log[#log+1] = ("local %s = %s:%s(%q)"):format(cname, objName, k, child)
            return makeObject(cname)
        end
    end

    if k == "GetDescendants" then
        return function()
            local varName = objName .. "_descendants"
            log[#log+1] = ("local %s = %s:GetDescendants()"):format(varName, objName)
            return {}
        end
    end

    if k == "IsA" then
        return function(_, class)
            log[#log+1] = ("%s:IsA(%q)"):format(objName, class)
            return true
        end
    end

    -- Logged methods
    if loggedMethods[k] then
        return function(_, ...)
            local args = { ... }

            if k == "SetCore" and type(args[2]) == "table" then
                local props = {}
                for key, val in pairs(args[2]) do
                    table.insert(props, ("%s = %s"):format(
                        key,
                        type(val) == "string" and ("%q"):format(val) or tostring(val)
                    ))
                end
                log[#log+1] = ("%s:SetCore(%q, { %s })"):format(
                    objName,
                    tostring(args[1]),
                    table.concat(props, ", ")
                )
            elseif methodsWithReturn[k] then
                local resultVar = getNiceName(k)
                log[#log+1] = ("local %s = %s:%s(...)"):format(resultVar, objName, k)
                return makeObject(resultVar)
            else
                log[#log+1] = ("%s:%s(...)"):format(objName, k)
            end
            return nil
        end
    end

    -- Event types
    if k == "MouseButton1Click" or k == "RenderStepped" or k == "Heartbeat"
    or k == "ChildAdded" or k == "Touched" or k == "FocusLost"
    or k == "InputBegan" or k == "InputChanged" then
        return makeObject(objName.."_"..k) -- Create mock event object
    end

    -- Property changed signal
    if k == "GetPropertyChangedSignal" then
        return function(_, prop)
            local signalName = objName.."_"..prop.."_signal"
            log[#log+1] = ("local %s = %s:GetPropertyChangedSignal(%q)"):format(signalName, objName, prop)
            return makeObject(signalName)
        end
    end

    -- Default behavior for unknown properties/methods
    return setmetatable({}, {
        __call = function(_, ...)
            log[#log+1] = ("%s:%s(...)"):format(objName, k)
            return nil
        end,
        __index = function()
            local vname = getNiceName(k)
            log[#log+1] = ("local %s = %s.%s"):format(vname, objName, k)
            return makeObject(vname)
        end
    })
end






objectMeta.__newindex = function(t, k, v)
    if not suppressLogging then
        if k == "Parent" and type(v) == "table" and v.__name then
            log[#log+1] = ("%s.Parent = %s"):format(t.__name, v.__name)
            return
        end

        local val
        if type(v) == "string" then
            val = ("%q"):format(v)
        elseif type(v) == "table" and getmetatable(v) == objectMeta then
            val = v.__name
        elseif type(v) == "table" and tostring(v):match("^UDim2") then
            val = tostring(v)
        elseif type(v) == "table" and tostring(v):match("^Color3") then
            val = tostring(v)
        else
            val = tostring(v)
        end

        log[#log+1] = ("%s.%s = %s"):format(t.__name, k, val)

        -- Update object name if .Name is changed
        if k == "Name" and type(v) == "string" then
            name_counts[v] = (name_counts[v] or 0) + 1
            t.__name = v .. (name_counts[v] > 1 and name_counts[v] or "")
        end
    end
    rawset(t, k, v)
end




local function Instance_new(class, parent)
    local v = getNiceName(class)
    log[#log+1] = ("local %s = Instance.new(%q%s)"):format(v, class, parent and (", " .. parent.__name) or "")

    if parent then
        log[#log+1] = ("%s.Parent = %s"):format(v, parent.__name)
    end

    if class == "LocalScript" then
        log[#log+1] = ("-- %s created, behavior assumed in separate script"):format(v)
    end

    return makeObject(v)
end



local services = {
    TweenService = makeObject("TweenService"),
    UserInputService = makeObject("UserInputService"),
    SoundService = makeObject("SoundService"),
    Players = {
        LocalPlayer = localPlayer
    }
}

local function game_GetService(_, name)
    if services[name] then return services[name] end
    local var = getNiceName(name)
    log[#log+1] = ("local %s = game:GetService(%q)"):format(var, name)
    local obj = makeObject(var)
    services[name] = obj
    return obj
end

local gameEnv -- declare first to allow reference later

gameEnv = setmetatable({}, {
    __index = function(_, k)
        return gameEnv.GetService(_, k)
    end
})

gameEnv.GetService = function(_, service)
    log[#log+1] = ('game:GetService(%q)'):format(service)

    if services[service] then
        return services[service]
    end

    local obj = makeObject(service)
    services[service] = obj
    return obj
end

gameEnv.HttpGet = function(_, url)
    -- Store URL but delay logging until we know if it's used directly or inside loadstring
    lastHttpGetUrl = url
    return "-- remote content"
end


gameEnv.PlaceId = 123456
gameEnv.JobId = "ABCDEF"



    

-- Simulate task.wait
local task = {
    wait = function(t)
    if t == nil then
        log[#log+1] = "task.wait()"
    else
        log[#log+1] = ("task.wait(%s)"):format(tostring(t))
    end
end,

    spawn = function(fn)
        -- Start task.spawn block
        log[#log+1] = "task.spawn(function()"

        -- Snapshot log before calling function
        local preCallLen = #log
        local ok, err = pcall(fn)

        -- Capture only new log entries
        local innerLog = {}
        for i = preCallLen + 1, #log do
            local line = log[i]

            -- Skip unwanted lines like "pairs(...) called"
            if not line:match("^%-%- pairs%(%.%%.%.%) called") then
                table.insert(innerLog, line)
            end
        end

        -- Clear the unfiltered lines
        for i = #log, preCallLen + 1, -1 do
            table.remove(log, i)
        end

        -- Reinsert filtered lines with 4-space indentation
        for _, line in ipairs(innerLog) do
            log[#log+1] = "    " .. line
        end

        -- Close the function block
        log[#log+1] = "end)"
        log[#log+1] = ""

        -- Log errors if any
        if not ok then
            log[#log+1] = "-- task.spawn error: " .. tostring(err)
        end
    end
}




-- Simulate Enum values
-- Simulate Enum values
local Enum = {
    Font = {
        SourceSans = "Enum.Font.SourceSans",
        SourceSansBold = "Enum.Font.SourceSansBold",
        Gotham = "Enum.Font.Gotham",
        GothamBlack = "Enum.Font.GothamBlack",
        GothamBold = "Enum.Font.GothamBold",
        GothamMedium = "Enum.Font.GothamMedium"
    },
    KeyCode = {
        E = "Enum.KeyCode.E",
        K = "Enum.KeyCode.K"
    },
    UserInputType = {
        MouseButton1 = "Enum.UserInputType.MouseButton1",
        MouseButton2 = "Enum.UserInputType.MouseButton2",
        MouseMovement = "Enum.UserInputType.MouseMovement"
    },
    RaycastFilterType = {
        Blacklist = "Enum.RaycastFilterType.Blacklist"
    },
    Material = {
        ForceField = "Enum.Material.ForceField",
        Neon = "Enum.Material.Neon"
    }
}

-- Simulate LocalPlayer and its PlayerGui
suppressLogging = true
local localPlayer = makeObject("localPlayer")
local playerGui = makeObject("PlayerGui")
localPlayer.PlayerGui = playerGui
services["Players"] = {
    LocalPlayer = localPlayer
}
suppressLogging = false

local function Color3_fromRGB(r,g,b)
    return setmetatable({}, { __tostring = function() return ("Color3.fromRGB(%d, %d, %d)"):format(r,g,b) end })
end

local function UDim2_new(a,b,c,d)
    return setmetatable({}, { __tostring = function() return ("UDim2.new(%s, %s, %s, %s)"):format(a,b,c,d) end })
end


local env = {
    print = function(...) log[#log+1] = ("print(%q)"):format(table.concat({...}, " ")) end,

UDim = {
    new = UDim_new
},

  wait = task.wait,

    __le = function(a, b)
        if a == nil or b == nil then
            log[#log+1] = ("-- Attempted comparison with nil: %s <= %s"):format(tostring(a), tostring(b))
            return false
        end
        return a <= b
    end,  -- THIS COMMA WAS MISSING
    
    request = function(tbl)
        log[#log+1] = ("request({ Method = %q, Url = %q })"):format(tbl.Method or "?", tbl.Url or "?")
        return {
            StatusCode = 200
        }
    end,
     request = function(tbl)
        log[#log+1] = ("request({ Method = %q, Url = %q })"):format(tbl.Method or "?", tbl.Url or "?")
        return {
            StatusCode = 200
        }
    end,  -- THIS COMMA WAS MISSING

    pairs = function(tbl)
        log[#log+1] = "-- pairs(...) called"
        return _G.pairs(tbl)  -- Use the original global pairs function
    end,



    loadstring = function(code)
    if lastHttpGetUrl then
        log[#log+1] = ('loadstring(game:HttpGet(%q))()'):format(lastHttpGetUrl)
        lastHttpGetUrl = nil
    else
        log[#log+1] = ('loadstring(%q)()'):format(code)
    end
    -- ✅ Actually compile and return the loaded function using env sandbox
    return assert(load(code, "loadstring_chunk", "t", env))
end,


    getgenv = function()
        log[#log+1] = ""
        return genEnvTable("getgenv()")
    end,

    identifyexecutor = function()
        log[#log+1] = "-- identifyexecutor() called"
        return "Delta"
    end,

    require = function(mod)
        log[#log+1] = ("require(%s)"):format(tostring(mod))
        return {}
    end,

setclipboard = function(text)
    log[#log+1] = ("setclipboard(%q)"):format(tostring(text))
end,

typeof = function(val)
    log[#log+1] = "-- typeof(...) called"
    return type(val)
end,


typeof = function(val)
    log[#log+1] = "-- typeof(...) called"
    return type(val)
end,


    Vector3 = {
        new = Vector3_new
    },

    Vector2 = {
        new = function(x, y)
            return setmetatable({x = x, y = y}, {
                __tostring = function() return ("Vector2.new(%s, %s)"):format(x, y) end
            })
        end
    },

    RaycastParams = {
        new = function()
            log[#log+1] = "local raycastParams = RaycastParams.new()"
            return {
                FilterDescendantsInstances = {},
                FilterType = "Enum.RaycastFilterType.Blacklist"
            }
        end
    },

    UDim2 = {
        new = UDim2_new
    },

    Color3 = {
        fromRGB = Color3_fromRGB,
        fromHSV = function(h, s, v)
            return setmetatable({}, { __tostring = function() return ("Color3.fromHSV(%s, %s, %s)"):format(h, s, v) end })
        end
    },

    CFrame = {
        new = function(...)
            return setmetatable({}, { __tostring = function() return "CFrame.new(...)" end })
        end
    },

    Instance = {
        new = Instance_new
    },

    Enum = {
    Font = {
        SourceSans = "Enum.Font.SourceSans",
        SourceSansBold = "Enum.Font.SourceSansBold",
        Gotham = "Enum.Font.Gotham",
        GothamBlack = "Enum.Font.GothamBlack",
        GothamBold = "Enum.Font.GothamBold",
        GothamMedium = "Enum.Font.GothamMedium",
        Arial = "Enum.Font.Arial",
        ArialBold = "Enum.Font.ArialBold",
        Code = "Enum.Font.Code",
        HighWay = "Enum.Font.HighWay"
    },
    KeyCode = {
        K = "Enum.KeyCode.K",
        E = "Enum.KeyCode.E",
        F = "Enum.KeyCode.F",
        Q = "Enum.KeyCode.Q",
        R = "Enum.KeyCode.R",
        T = "Enum.KeyCode.T",
        One = "Enum.KeyCode.One",
        Two = "Enum.KeyCode.Two",
        Three = "Enum.KeyCode.Three",
        Space = "Enum.KeyCode.Space",
        LeftShift = "Enum.KeyCode.LeftShift",
        RightShift = "Enum.KeyCode.RightShift"
    },
    UserInputType = {
        MouseButton1 = "Enum.UserInputType.MouseButton1",
        MouseButton2 = "Enum.UserInputType.MouseButton2",
        MouseMovement = "Enum.UserInputType.MouseMovement",
        Keyboard = "Enum.UserInputType.Keyboard",
        Touch = "Enum.UserInputType.Touch",
        Gamepad1 = "Enum.UserInputType.Gamepad1"
    },
    RaycastFilterType = {
        Blacklist = "Enum.RaycastFilterType.Blacklist",
        Whitelist = "Enum.RaycastFilterType.Whitelist",
        Include = "Enum.RaycastFilterType.Include"
    },
    Material = {
        ForceField = "Enum.Material.ForceField",
        Neon = "Enum.Material.Neon",
        Plastic = "Enum.Material.Plastic",
        Wood = "Enum.Material.Wood",
        Slate = "Enum.Material.Slate",
        Concrete = "Enum.Material.Concrete",
        CorrodedMetal = "Enum.Material.CorrodedMetal"
    },
    EasingStyle = {
        Linear = "Enum.EasingStyle.Linear",
        Sine = "Enum.EasingStyle.Sine",
        Back = "Enum.EasingStyle.Back",
        Quad = "Enum.EasingStyle.Quad",
        Quart = "Enum.EasingStyle.Quart",
        Quint = "Enum.EasingStyle.Quint",
        Bounce = "Enum.EasingStyle.Bounce"
    },
    EasingDirection = {
        In = "Enum.EasingDirection.In",
        Out = "Enum.EasingDirection.Out",
        InOut = "Enum.EasingDirection.InOut"
    }
},

    mousemoverel = function(x, y)
        log[#log+1] = ("mousemoverel(%s, %s)"):format(x, y)
    end,

    task = task,
    declare = declareVariable,
    func = trackFunction,

    game = gameEnv,

    workspace = setmetatable({
        CurrentCamera = makeObject("Camera")
    }, {
        __index = function(_, k)
            local obj = makeObject("workspace_" .. k)
            log[#log+1] = ("local %s = workspace.%s"):format(obj.__name, k)
            return obj
        end
    }),

    script = makeObject("script"),
shared = genEnvTable("shared"),
fenv = setmetatable({
    ["625MlQt0QJdZvT"] = {},
    ["7s4m8rO83M8DwL"] = {},
    ghLwu5gbxAjuL6 = {},
    HGuKNq3Ogokj = {},
    tSTCQTG0ZVj0w = {},
    CsKjMK0D90GQ = {},
}, {
    __index = function(_, k)
        local dummy = {}
        log[#log+1] = ("-- accessed fenv[%q] (dummy table returned)"):format(tostring(k))
        return dummy
    end,
    __newindex = function(_, k, v)
        local vs
if type(v) == "string" then
    vs = ("%q"):format(v)
elseif type(v) == "function" then
    vs = "function(...) ... end"
elseif type(v) == "table" then
    vs = "{}"
else
    vs = tostring(v)
end

local keyFormatted = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and ("." .. k) or ("[%q]"):format(k)
log[#log+1] = ("fenv%s = %s"):format(keyFormatted, vs)

    end
}),
_G = genEnvTable("_G"),
localPlayer = localPlayer,


    Library = {
        CreateLib = function(title, theme)
            log[#log+1] = ("local Window = Library.CreateLib(%q, %q)"):format(title, theme)

            if not declared_locals.settings then
                declareTable("settings", {
                    AimbotEnabled = false,
                    ShowFOV = true,
                    FOVRadius = 100,
                    FOVColor = Color3.fromRGB(255, 0, 0),
                    FOVTransparency = 0.7,
                    FOVThickness = 1,
                    WallCheck = false,
                    UIKey = Enum.KeyCode.K,
                    Smoothness = 0.2,
                    AimPart = "Head",
                    ESPEnabled = false,
                    ChamColor = Color3.fromRGB(0, 255, 0),
                    ChamTransparency = 0.5,
                    CameraFOV = 70,
                    Walkspeed = 16,
                    Jumppower = 50
                })
                declared_locals.settings = true
            end

            return {
                NewTab = function(tabName)
                    local tabVar = tabName:gsub("%s+", "") .. "Tab"
                    log[#log+1] = ("local %s = Window:NewTab(%q)"):format(tabVar, tabName)
                    return {
                        NewSection = function(sectionName)
                            local sectionVar = sectionName:gsub("%s+", "") .. "Section"
                            log[#log+1] = ("local %s = %s:NewSection(%q)"):format(sectionVar, tabVar, sectionName)
                            return {
                                NewToggle = function(name, desc, callback)
                                    log[#log+1] = ("%s:NewToggle(%q, %q, function(state) ... end)"):format(sectionVar, name, desc)
                                    if callback then callback(false) end
                                end,
                                NewSlider = function(name, desc, max, min, callback)
                                    log[#log+1] = ("%s:NewSlider(%q, %q, %s, %s, function(val) ... end)"):format(sectionVar, name, desc, max, min)
                                    if callback then callback((max + min) // 2) end
                                end,
                                NewDropdown = function(name, desc, options, callback)
                                    log[#log+1] = ("%s:NewDropdown(%q, %q, {%s}, function(option) ... end)"):format(
                                        sectionVar, name, desc, table.concat(options, ", "))
                                    if callback then callback(options[1]) end
                                end,
                                NewButton = function(name, desc, callback)
                                    log[#log+1] = ("%s:NewButton(%q, %q, function() ... end)"):format(sectionVar, name, desc)
                                    if callback then callback() end
                                end,
                                NewColorPicker = function(name, desc, defaultColor, callback)
                                    log[#log+1] = ("%s:NewColorPicker(%q, %q, %s, function(color) ... end)"):format(sectionVar, name, desc, tostring(defaultColor))
                                    if callback then callback(defaultColor) end
                                end
                            }
                        end
                    }
                end
            }
        end
    }
} -- ✅ Properly closes env = { ... } table


coroutine = {
    wrap = function(fn)
        local wrappedName = "wrappedFunc" .. tostring(#declared_functions + 1)
        log[#log+1] = ("local %s = coroutine.wrap(function() ... end)"):format(wrappedName)
        return function() log[#log+1] = ("%s()"):format(wrappedName) end
    end
}






    env.getgenv = function()
    
    return genEnvTable("getgenv()")
end

env.getfenv = function(level)
    local accessedKeys = {}
    local suppressKeys = {
        -- Standard Lua and Luau globals
        pcall = true, tostring = true, tonumber = true, error = true,
        math = true, table = true, string = true, type = true, select = true,
        ipairs = true, pairs = true, unpack = true, coroutine = true,
        debug = true, next = true, assert = true, rawget = true,
        rawset = true, setmetatable = true, getfenv = true, loadstring = true,
        game = true,

        -- Known junk or filler keys used by obfuscators
        ADbO4sP58kOJWx = true, YaBNYL7bSzFRwD = true, BazJO6MozIlCGY = true,
        c6S8Ml6JyyqCG6 = true, AeV6tvQKeRFS = true, BecfNMFmVlWNe = true,
        k6qmR9jevjg53 = true, ["08oAj63mn0sv"] = true, czOBnnAWqp0A9 = true,
        hotqBAivOnfrUw = true
    }

    local proxy = {}
    return setmetatable(proxy, {
        __index = function(_, k)
            local val = env[k]
            return val
        end,
        __newindex = function(_, k, v)
            if type(v) == "function" then return end -- Skip function assignments completely
            
            local vs
            if type(v) == "string" then
                vs = ("%q"):format(v)
            elseif type(v) == "table" then
                if #v > 0 then -- Array-style tables
                    local items = {}
                    for i, val in ipairs(v) do
                        table.insert(items, type(val) == "string" and ("%q"):format(val) or tostring(val))
                    end
                    vs = ("{ %s }"):format(table.concat(items, ", "))
                else
                    vs = "{}"
                end
            else
                vs = tostring(v)
            end

            local keyFormatted = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and ("." .. k) or ("[%q]"):format(k)
            log[#log+1] = ("fenv%s = %s"):format(keyFormatted, vs)
        end
    }) -- This closes the setmetatable call
end -- This closes the getfenv function






-- UI Simulation
local function fakeComponent(name)
    return {
        Section = function(info)
            log[#log+1] = ("%s:Section({ Title = %q })"):format(name, info.Title or "")
        end,
        Toggle = function(info)
            log[#log+1] = ("%s:Toggle({ Title = %q })"):format(name, info.Title or "")
            if info.Callback then info.Callback(info.Value or false) end
        end,
        Button = function(info)
            log[#log+1] = ("%s:Button({ Title = %q })"):format(name, info.Title or "")
            if info.Callback then info.Callback() end
        end,
        Keybind = function(info)
            log[#log+1] = ("%s:Keybind({ Title = %q })"):format(name, info.Title or "")
            if info.Callback then info.Callback() end
        end,
        Slider = function(info)
            log[#log+1] = ("%s:Slider({ Title = %q })"):format(name, info.Title or "")
            if info.Callback and info.Value then info.Callback(info.Value.Default or 1) end
        end
    }
end

local Window = {
    Tab = function(info)
        -- Extract title and icon with fallbacks
        local title = (info and info.Title) or "Unknown"
        local icon = (info and info.Icon) or "nil"

        -- ✅ Log the actual data from the input script
        log[#log+1] = ("Window:Tab({ Title = %q, Icon = %q })"):format(title, icon)

        -- 🛠 Store a reference to info to pass down
        local componentName = "Tabs." .. title:gsub("%W", "")  -- sanitize key
        return fakeComponent(componentName)
    end,

    SelectTab = function(index)
        log[#log+1] = ("Window:SelectTab(%d)"):format(index)
    end
}





env.Window = Window
env.Tabs = {
    Match = fakeComponent("Tabs.Match"),
    Player = fakeComponent("Tabs.Player")
}

env.Library = {
    CreateLib = function(title, theme)
        log[#log+1] = ("local Window = Library.CreateLib(%q, %q)"):format(title, theme)

        return {
            NewTab = function(tabName)
                local tabVar = tabName:gsub("%s+", "") .. "Tab"
                log[#log+1] = ("local %s = Window:NewTab(%q)"):format(tabVar, tabName)

                return {
                    NewSection = function(sectionName)
                        local sectionVar = sectionName:gsub("%s+", "") .. "Section"
                        log[#log+1] = ("local %s = %s:NewSection(%q)"):format(sectionVar, tabVar, sectionName)

                        return {
                            NewToggle = function(name, desc, callback)
                                log[#log+1] = ("%s:NewToggle(%q, %q, function(state) ... end)"):format(sectionVar, name, desc)
                                if callback then callback(false) end
                            end,
                            NewSlider = function(name, desc, max, min, callback)
                                log[#log+1] = ("%s:NewSlider(%q, %q, %s, %s, function(val) ... end)"):format(sectionVar, name, desc, max, min)
                                if callback then callback((max + min) // 2) end
                            end,
                            NewDropdown = function(name, desc, options, callback)
                                log[#log+1] = ("%s:NewDropdown(%q, %q, {%s}, function(option) ... end)"):format(
                                    sectionVar, name, desc, table.concat(options, ", "))
                                if callback then callback(options[1]) end
                            end,
                            NewButton = function(name, desc, callback)
                                log[#log+1] = ("%s:NewButton(%q, %q, function() ... end)"):format(sectionVar, name, desc)
                                if callback then callback() end
                            end
                        }
                    end
                }
            end
        }
    end
}



-- Roblox service shorthands for scripts that use them directly


env._G = env._G  -- explicitly assign your custom _G into env
setmetatable(env, {
    __index = function(_, k)
        return rawget(env, k) or _G[k]
    end
})


setmetatable(env, {
    __index = function(t, k)
        local commonServices = {
            ReplicatedStorage = true,
            TweenService = true,
            RunService = true,
            StarterGui = true,
            ReplicatedFirst = true
        }

        if commonServices[k] then
            local service = gameEnv:GetService(k)
            rawset(t, k, service)
            return service
        end

        return rawget(t, k) or _G[k]
    end
})


local f = io.open(inputFile, "r") if not f then error("❌ Can't open input file") end
local code = f:read("*a") f:close()

local fn, err = load(code, inputFile, "t", env)
if not fn then error(err) end

local ok, err = pcall(fn)
if not ok then
    log[#log+1] = ("-- [ERROR] Script execution halted: %s"):format(tostring(err))
    log[#log+1] = "-- Continuing with logged operations..."
end

local function beautifyLog(lines)
    local beautified = {}
    local indent = 0
    for _, line in ipairs(lines) do
        if line:find("^%s*end") or line:find("^%s*})") then
            indent = indent - 1
        end
        beautified[#beautified+1] = string.rep("    ", indent) .. line
        if line:find("then$") or line:find("do$") or line:find("function") then
            indent = indent + 1
        end
    end
    return beautified
end
-- Filter out all lines containing "= function"
-- Final log processing
local filteredLog = {}
for _, line in ipairs(log) do
    -- Skip function assignments and empty lines
    if not line:match("= function") and line:gsub("%s", "") ~= "" then
        table.insert(filteredLog, line)
    end
end

local out = io.open(outputFile, "w")
out:write("-- ts file was envlogged by makeittakeit\n\n")
for _, line in ipairs(beautifyLog(filteredLog)) do  -- Use filteredLog instead of log
    out:write(line .. "\n")
end
out:close()

print("✅ Saved to:", outputFile)
