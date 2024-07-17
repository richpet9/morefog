-- Author: Richard Petrosino
-- Modification with permission of software created by GIANTS Software GmbH.
-- Do not monetize, commercialize, or reproduce without permission.
-- July 15, 2024. 
MoreFog = {}
MoreFog.modName = g_currentModName

MoreFog.const = {}
MoreFog.const.FOG_EVENING_HOUR_START = 17
MoreFog.const.FOG_EVENING_HOUR_END = 22

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

    -- Override the default fog timing so that the arithmetic further down remains deterministic.
    self.defaultFog.fadeIn = MoreFog.const.FOG_FADE_IN
    self.defaultFog.fadeOut = MoreFog.const.FOG_FADE_OUT

    self.fogMorningStart = self.defaultFog.startHour - 1
    self.fogMorningEnd = self.defaultFog.endHour

    self.fogEveningStart = MoreFog.const.FOG_EVENING_HOUR_START
    self.fogEveningEnd = MoreFog.const.FOG_EVENING_HOUR_END

    self.isPrecipFogEnabled = false

    g_messageCenter:unsubscribeAll(self)
    g_messageCenter:subscribe(MessageType.HOUR_CHANGED, self.onHourChanged, self)
    g_messageCenter:subscribe(MessageType.MINUTE_CHANGED, self.onMinuteChanged, self)
end

function MoreFog:onHourChanged()
    local currentHour = self.environment.currentHour
    if not self.isPrecipFogEnabled then
        self:updateMorningFog(currentHour)
        self:updateEveningFog(currentHour)
    end

    self:updatePrecipFog()
end

function MoreFog:onMinuteChanged()
    self.weather.fogUpdater:setHeight(self:getHeightFromTime())
end

function MoreFog:updateMorningFog(currentHour)
    if currentHour == self.fogMorningStart then
        self:toggleFog(true, MoreFog.const.FOG_FADE_IN, self:getMorningFogType())
    elseif currentHour == self.fogMorningEnd then
        self:toggleFog(false, MoreFog.const.FOG_FADE_OUT)
    elseif currentHour == self.fogMorningEnd + self.weather.fog.fadeOut then
        self:resetFog()
    end
end

function MoreFog:updateEveningFog(currentHour)
    if currentHour == self.fogEveningStart then
        self:toggleFog(true, MoreFog.const.FOG_FADE_IN, self:getEveningFogType())
    elseif currentHour == self.fogEveningEnd then
        self:toggleFog(false, MoreFog.const.FOG_FADE_OUT)
    elseif currentHour == self.fogEveningEnd + self.weather.fog.fadeOut then
        self:resetFog()
    end
end

function MoreFog:updatePrecipFog()
    local currentTemperature = self.weather:getCurrentTemperature()
    local _, _, isPrecip, willPrecip = self:getCurrentWeatherInfo()

    print("MoreFog: Determining precip. " ..
              string.format(
            "isPrecip = %s, willPrecip = %s, isPrecipFogEnabled = %s, timeSinceLastRain = %s",
            isPrecip, willPrecip, self.isPrecipFogEnabled, self.weather.timeSinceLastRain))

    if not self.isPrecipFogEnabled then
        if isPrecip and currentTemperature > 28 then
            self:toggleFog(true, MoreFog.const.FOG_RAIN_FADE_IN, MoreFog.FogType.HEAVY)
            self.isPrecipFogEnabled = true
        elseif isPrecip and currentTemperature > 20 then
            self:toggleFog(true, MoreFog.const.FOG_RAIN_FADE_IN, MoreFog.FogType.MEDIUM)
            self.isPrecipFogEnabled = true
        elseif willPrecip and currentTemperature > 32 then
            self:toggleFog(true, MoreFog.const.FOG_RAIN_FADE_IN, MoreFog.FogType.HEAVY)
            self.isPrecipFogEnabled = true
        elseif willPrecip and currentTemperature > 25 then
            self:toggleFog(true, MoreFog.const.FOG_RAIN_FADE_IN, MoreFog.FogType.LIGHT)
            self.isPrecipFogEnabled = true
        elseif willPrecip and currentTemperature > 15 then
            self:toggleFog(true, MoreFog.const.FOG_RAIN_FADE_IN, MoreFog.FogType.HAZE)
            self.isPrecipFogEnabled = true
        end
    elseif self.weather:getTimeSinceLastRain() > 120 then
        print("MoreFog: Resetting fog from precip.")
        self:resetFog()
        self.isPrecipFogEnabled = false
    end
end

function MoreFog:getMorningFogType()
    local timeSinceLastRain = self.weather:getTimeSinceLastRain()
    local rainedInLast4Hours = timeSinceLastRain > 0 and timeSinceLastRain < 240
    local rainedInLast1Hour = timeSinceLastRain > 0 and timeSinceLastRain < 60
    local currentTemperature = self.weather:getCurrentTemperature()
    local _, highTemp = self.weather:getCurrentMinMaxTemperatures()
    local isSunny, _, _, _ = self:getCurrentWeatherInfo()

    if rainedInLast4Hours and currentTemperature > 30 and isSunny then
        return MoreFog.FogType.HEAVY
    end

    if rainedInLast1Hour and currentTemperature < 26 then
        return MoreFog.FogType.HEAVY
    end

    if currentTemperature > 33 and isSunny then
        return MoreFog.FogType.MEDIUM
    end

    if currentTemperature > 26 then
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
    local isSunny, isCloudy, _, _ = self:getCurrentWeatherInfo()

    if rainedInLast1Hour and currentTemperature > 18 and isSunny then
        return MoreFog.FogType.LIGHT
    end

    if rainedInLast4Hours and currentTemperature > 20 and isSunny then
        return MoreFog.FogType.LIGHT
    end

    if highTemp - currentTemperature > 7 then
        return MoreFog.FogType.LIGHT
    end

    if isCloudy then
        return MoreFog.FogType.HAZE
    end

    return MoreFog.FogType.NONE
end

function MoreFog:getFogTableFromType(fogType)
    local fog = table.copy(self.defaultFog)

    if fogType == nil then
        return fog
    end

    fog.dayFactor = 1
    fog.nightFactor = 1

    if fogType == MoreFog.FogType.NONE then
        fog.minMieScale = 0
        fog.maxMieScale = 0
    elseif fogType == MoreFog.FogType.HEAVY then
        fog.minMieScale = MoreFog.const.MIE_SCALE_MIN_HEAVY
        fog.maxMieScale = MoreFog.const.MIE_SCALE_MAX_HEAVY
    elseif fogType == MoreFog.FogType.MEDIUM then
        fog.minMieScale = MoreFog.const.MIE_SCALE_MIN_MEDIUM
        fog.maxMieScale = MoreFog.const.MIE_SCALE_MAX_MEDIUM
    elseif fogType == MoreFog.FogType.LIGHT then
        fog.minMieScale = MoreFog.const.MIE_SCALE_MIN_LIGHT
        fog.maxMieScale = MoreFog.const.MIE_SCALE_MAX_LIGHT
    end

    -- NOTE: "HAZE" uses the default fog value, so fall through.
    return fog;
end

function MoreFog:getCurrentWeatherInfo()
    local oneHr = 3600000
    local timeForFog = oneHr * MoreFog.const.FOG_FADE_IN
    local currentWeather = self.weather:getCurrentWeatherType()

    local isSunny = currentWeather == WeatherType.SUN
    local isSunny = isCloudy
    local isPrecip = self.weather:getIsRaining()
    local willPrecip = self.weather:getTimeUntilRain() < dayPlusFogTime

    return isSunny, isCloudy, isPrecip, willPrecip
end

function MoreFog:toggleFog(enable, fadeTimeHrs, fogType)
    print(string.format("MoreFog: toggleFog(%s, %s, %s)", enable, fadeTimeHrs,
        MoreFog.fogTypeToString(fogType)))

    if fogType ~= nil then
        self.weather.fog = self:getFogTableFromType(fogType)
    end
    self.weather:toggleFog(enable, MathUtil.hoursToMs(fadeTimeHrs))
end

function MoreFog:resetFog()
    print("MoreFog: Resetting fog to default.")
    self.weather.fog = table.copy(self.defaultFog)
    self.weather:toggleFog(false, MathUtil.hoursToMs(1))
end

function MoreFog:getHeightFromTime()
    local minute = self.environment.currentMinute
    local hour = self.environment.currentHour

    if minute == 0 then
        -- Not sure why TimeUpdater does this.
        hour = hour + 1
    end

    local dayMinute = hour * 60 + minute
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

function MoreFog.fogTypeToString(fogType)
    if fogType == nil then
        return "nil"
    elseif fogType == MoreFog.FogType.NONE then
        return "NONE"
    elseif fogType == MoreFog.FogType.HEAVY then
        return "HEAVY"
    elseif fogType == MoreFog.FogType.MEDIUM then
        return "MEDIUM"
    elseif fogType == MoreFog.FogType.LIGHT then
        return "LIGHT"
    end

    return "HAZE"
end

local function weatherLoad(weather)
    weather.moreFog = MoreFog.new(weather)
    weather.moreFog:load()
end

Weather.load = Utils.appendedFunction(Weather.load, weatherLoad)
