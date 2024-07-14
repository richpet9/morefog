-- by Rich
MoreFog = {}
MoreFog.modName = g_currentModName

MoreFog.const = {}
MoreFog.const.MORNING_FOG_START = 4
MoreFog.const.MORNING_FOG_END = 8
MoreFog.const.EVENING_FOG_START = 17
MoreFog.const.EVENING_FOG_END = 0

MoreFog.const.FOG_FADE_IN = 3
MoreFog.const.FOG_FADE_OUT = 3
MoreFog.const.FOG_RAIN_FADE_IN = 0.5

MoreFog.const.MIE_SCALE_MAX_HEAVY = 900
MoreFog.const.MIE_SCALE_MAX_MEDIUM = 400
MoreFog.const.MIE_SCALE_MAX_LIGHT = 100

MoreFog.const.MIE_SCALE_MIN_HEAVY = 0
MoreFog.const.MIE_SCALE_MIN_MEDIUM = 0
MoreFog.const.MIE_SCALE_MIN_LIGHT = 0

MoreFog.FogType = {
    NONE = 0,
    HAZE = 1,
    LIGHT = 2,
    MEDIUM = 3,
    HEAVY = 4
}

local MoreFog_mt = Class(MoreFog)

function MoreFog.new(weather)
    self = setmetatable({}, MoreFog_mt)
    self.weather = weather
    self.environment = weather.owner

    addConsoleCommand("gsMoreFogSet",
        "Sets the MoreFog amount. Values: 'NONE', 'LIGHT', 'MEDIUM', or 'HEAVY'.",
        "consoleCommandSetFog", self)

    return self
end

function MoreFog:load()
    self.defaultFog = table.copy(self.weather.fog)
    self.defaultFog.fadeIn = MoreFog.const.FOG_FADE_IN
    self.defaultFog.fadeOut = MoreFog.const.FOG_FADE_OUT
    self.defaultFog.dayFactor = 1
    self.defaultFog.nightFactor = 1

    self.currentHour = self.environment.currentHour
    self.currentMinute = self.environment.currentMinute

    g_messageCenter:unsubscribeAll(self)
    g_messageCenter:subscribe(MessageType.HOUR_CHANGED, self.onHourChanged, self)
    g_messageCenter:subscribe(MessageType.MINUTE_CHANGED, self.onMinuteChanged, self)
end

function MoreFog:onHourChanged()
    self.currentHour = self.environment.currentHour
    self:maybeSetMorningFog()
    self:maybeSetEveningFog()
    self:maybeSetPrecipFog()
end

function MoreFog:onMinuteChanged()
    self.currentMinute = self.environment.currentMinute
    self.weather.fogUpdater:setHeight(self:getHeightFromTime())
end

function MoreFog:maybeSetMorningFog()
    if self.currentHour == MoreFog.const.MORNING_FOG_START then
        local morningFogType = self:getMorningFogType()
        self.weather.fog = self:getFogTableFromType(morningFogType)
        self.weather:toggleFog(true, MathUtil.hoursToMs(self.weather.fog.fadeIn))
    elseif self.currentHour == MoreFog.const.MORNING_FOG_END then
        self.weather:toggleFog(false, MathUtil.hoursToMs(self.weather.fog.fadeOut))
    elseif self.currentHour == MoreFog.const.MORNING_FOG_END + self.weather.fog.fadeOut then
        self:resetFog()
    end
end

function MoreFog:maybeSetEveningFog()
    if self.currentHour == MoreFog.const.EVENING_FOG_START then
        local eveningFogType = self:getEveningFogType()
        self.weather.fog = self:getFogTableFromType(eveningFogType)
        self.weather:toggleFog(true, MathUtil.hoursToMs(self.weather.fog.fadeIn))
    elseif self.currentHour == MoreFog.const.EVENING_FOG_END then
        self.weather:toggleFog(false, MathUtil.hoursToMs(self.weather.fog.fadeOut))
    elseif self.currentHour == MoreFog.const.EVENING_FOG_END + self.weather.fog.fadeOut then
        self:resetFog()
    end
end

function MoreFog:maybeSetPrecipFog()
    local _, _, isPrecip, _ = self:getCurrentWeatherInfo()
    if isPrecip then
        self.weather.fog = self:getFogTableFromType(MoreFog.FogType.HEAVY)
        self.weather:toggleFog(true, MathUtil.hoursToMs(MoreFog.const.FOG_RAIN_FADE_IN))
    elseif self.weather.timeSinceLastRain ~= nil and self.weather.timeSinceLastRain < 2 then
        self:resetFog()
    end
end

function MoreFog:getFogTableFromType(fogType)
    local fog = table.copy(self.defaultFog)

    if fogType == nil then
        print("MoreFog: FogType was nil")
        return fog
    end

    if fogType == MoreFog.FogType.NONE then
        print("MoreFog: Setting fog to NONE")
        fog.minMieScale = 0
        fog.maxMieScale = 0
    elseif fogType == MoreFog.FogType.HEAVY then
        print("MoreFog: Setting fog to HEAVY")
        fog.minMieScale = MoreFog.const.MIE_SCALE_MIN_HEAVY
        fog.maxMieScale = MoreFog.const.MIE_SCALE_MAX_HEAVY
    elseif fogType == MoreFog.FogType.MEDIUM then
        print("MoreFog: Setting fog to MEDIUM")
        fog.minMieScale = MoreFog.const.MIE_SCALE_MIN_MEDIUM
        fog.maxMieScale = MoreFog.const.MIE_SCALE_MAX_MEDIUM
    elseif fogType == MoreFog.FogType.LIGHT then
        print("MoreFog: Setting fog to LIGHT")
        fog.minMieScale = MoreFog.const.MIE_SCALE_MIN_LIGHT
        fog.maxMieScale = MoreFog.const.MIE_SCALE_MAX_LIGHT
    end

    -- NOTE: "HAZE" is default fog value, fall through.

    return fog;
end

function MoreFog:getMorningFogType()
    local timeSinceLastRain = self.weather.timeSinceLastRain
    local rainedInLast4Hours = timeSinceLastRain ~= nil and timeSinceLastRain > 0 and
                                   timeSinceLastRain < 5
    local rainedInLast1Hour = timeSinceLastRain ~= nil and timeSinceLastRain > 0 and
                                  timeSinceLastRain < 2
    local currentTemperature = self.weather:getCurrentTemperature()
    local _, highTemp = self.weather:getCurrentMinMaxTemperatures()
    local currentWeather, nextWeather, isPrecip, willPrecip = self:getCurrentWeatherInfo()

    if rainedInLast4Hours and currentTemperature > 15 and currentWeather == WeatherType.SUN then
        return MoreFog.FogType.HEAVY
    end

    if rainedInLast1Hour and currentTemperature < 15 then
        return MoreFog.FogType.HEAVY
    end

    if isPrecip then
        return MoreFog.FogType.MEDIUM
    end

    if currentTemperature < 10 and willPrecip then
        return MoreFog.FogType.LIGHT
    end

    if currentTemperature > 25 then
        return MoreFog.FogType.LIGHT
    end

    return MoreFog.FogType.HAZE
end

function MoreFog:getEveningFogType()
    local timeSinceLastRain = self.weather.timeSinceLastRain
    local rainedInLast4Hours = timeSinceLastRain ~= nil and timeSinceLastRain > 0 and
                                   timeSinceLastRain < 5
    local rainedInLast1Hour = timeSinceLastRain ~= nil and timeSinceLastRain > 0 and
                                  timeSinceLastRain < 2
    local currentTemperature = self.weather:getCurrentTemperature()
    local _, highTemp = self.weather:getCurrentMinMaxTemperatures()
    local currentWeather, nextWeather, isPrecip, willPrecip = self:getCurrentWeatherInfo()

    if rainedInLast1Hour and currentTemperature > 18 and currentWeather == WeatherType.SUN then
        return MoreFog.FogType.LIGHT
    end

    if rainedInLast4Hours and currentTemperature > 20 and currentWeather == WeatherType.SUN then
        return MoreFog.FogType.LIGHT
    end

    if highTemp - currentTemperature > 7 then
        return MoreFog.FogType.LIGHT
    end

    if currentWeather == WeatherType.CLOUDY then
        return MoreFog.FogType.HAZE
    end

    return MoreFog.FogType.NONE
end

function MoreFog:getCurrentWeatherInfo()
    local sixHours = 21600000
    local env = self.environment
    local dayPlus6h, timePlus6h = env:getDayAndDayTime(env.dayTime + sixHours,
        env.currentMonotonicDay)

    local currentWeather = self.weather:getCurrentWeatherType()
    local nextWeather = self.weather:getNextWeatherType(dayPlus6h, timePlus6h)

    local isPrecip = currentWeather == WeatherType.RAIN or currentWeather == WeatherType.SNOW
    local willPrecip = nextWeather == WeatherType.RAIN or nextWeather == WeatherType.SNOW

    return currentWeather, nextWeather, isPrecip, willPrecip
end

function MoreFog:resetFog()
    self.weather.fog = table.copy(self.defaultFog)
    self.weather:toggleFog(false, MathUtil.hoursToMs(1))
end

function MoreFog:getHeightFromTime()
    local dayMinute = self.currentHour * 60 + self.currentMinute
    -- Height will peak at hour 6 with a value of 120, and the lowest point is hour 12 with a
    -- value of 70, on a 12-hour period. This helps avoid insanely bright fog duiring the hours 
    -- when the sun is low on the horizon.
    return 25 * math.sin(math.pi / 360 * (dayMinute - 180)) + 95
end

function MoreFog:consoleCommandSetFog(fogType)
    if fogType == "NONE" then
        self.weather.fog = self:getFogTableFromType(MoreFog.FogType.NONE)
        self.weather:toggleFog(true, 0)
        return "Fog set to NONE."
    elseif fogType == "HAZE" then
        self.weather.fog = self:getFogTableFromType(MoreFog.FogType.HAZE)
        self.weather:toggleFog(true, 0)
        return "Fog set to HAZE."
    elseif fogType == "LIGHT" then
        self.weather.fog = self:getFogTableFromType(MoreFog.FogType.LIGHT)
        self.weather:toggleFog(true, 0)
        return "Fog set to LIGHT."
    elseif fogType == "MEDIUM" then
        self.weather.fog = self:getFogTableFromType(MoreFog.FogType.MEDIUM)
        self.weather:toggleFog(true, 0)
        return "Fog set to MEDIUM."
    elseif fogType == "HEAVY" then
        self.weather.fog = self:getFogTableFromType(MoreFog.FogType.HEAVY)
        self.weather:toggleFog(true, 0)
        return "Fog set to HEAVY."
    end

    return string.format(
        "Invalid fog type: %s | Valid types: 'NONE', 'HAZE', 'LIGHT', 'MEDIUM', or 'HEAVY'.",
        fogType)
end

local function weatherLoad(weather)
    weather.moreFog = MoreFog.new(weather)
    weather.moreFog:load()
end

Weather.load = Utils.appendedFunction(Weather.load, weatherLoad)
