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
MoreFog.const.FOG_RAIN_FADE_IN = 1

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

    self.isPrecipFogActive = false

    g_messageCenter:unsubscribeAll(self)
    g_messageCenter:subscribe(MessageType.HOUR_CHANGED, self.onHourChanged, self)
    g_messageCenter:subscribe(MessageType.MINUTE_CHANGED, self.onMinuteChanged, self)
end

function MoreFog:onHourChanged()
    local currentHour = self.environment.currentHour
    if not self.isPrecipFogActive and not self.weather:getIsRaining() then
        self:updateMorningFog(currentHour)
        self:updateEveningFog(currentHour)
    end

    self:updatePrecipFog()
end

function MoreFog:onMinuteChanged()
    self.weather.fogUpdater:setHeight(self:getHeightFromTime())

    if (self.weather:getIsRaining() and not self.isPrecipFogActive) or
        (not self.weather:getIsRaining() and self.isPrecipFogActive) then
        self:updatePrecipFog()
    end
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

    print("MoreFog: Determining precip. " ..
              string.format(
            "isPrecip = %s, willRain = %s, isPrecipFogActive = %s, timeSinceLastRain = %s",
            self.weather:getIsRaining(), self:willRain(), self.isPrecipFogActive,
            self.weather:getTimeSinceLastRain()))

    if not self.isPrecipFogActive then
        if self.weather:getIsRaining() and currentTemperature < 15 then
            self:toggleFog(true, MoreFog.const.FOG_RAIN_FADE_IN, MoreFog.FogType.HEAVY)
            self.isPrecipFogActive = true
        elseif self.weather:getIsRaining() and currentTemperature < 25 then
            self:toggleFog(true, MoreFog.const.FOG_RAIN_FADE_IN, MoreFog.FogType.MEDIUM)
            self.isPrecipFogActive = true
        elseif self:willRain() and currentTemperature < 4 then
            self:toggleFog(true, MoreFog.const.FOG_RAIN_FADE_IN, MoreFog.FogType.MEDIUM)
            self.isPrecipFogActive = true
        elseif self:willRain() and currentTemperature < 15 then
            self:toggleFog(true, MoreFog.const.FOG_RAIN_FADE_IN, MoreFog.FogType.LIGHT)
            self.isPrecipFogActive = true
        elseif self:willRain() then
            self:toggleFog(true, MoreFog.const.FOG_RAIN_FADE_IN, MoreFog.FogType.HAZE)
            self.isPrecipFogActive = true
        end
    elseif self.weather:getTimeSinceLastRain() > 30 and not self:willRain() then
        print("MoreFog: Ending fog from precip.")
        self:toggleFog(true, MoreFog.const.FOG_RAIN_FADE_IN, MoreFog.FogType.HAZE)
        self.isPrecipFogActive = false
    end
end

function MoreFog:getMorningFogType()
    local timeSinceLastRain = self.weather:getTimeSinceLastRain()
    local rainedInLast4Hours = timeSinceLastRain > 0 and timeSinceLastRain < 240
    local rainedInLast1Hour = timeSinceLastRain > 0 and timeSinceLastRain < 60
    local currentTemperature = self.weather:getCurrentTemperature()
    local _, highTemp = self.weather:getCurrentMinMaxTemperatures()

    if rainedInLast1Hour and currentTemperature < 0 then
        return MoreFog.FogType.HEAVY
    end

    if rainedInLast1Hour and currentTemperature < 10 then
        return MoreFog.FogType.MEDIUM
    end

    if rainedInLast4Hours or self:isCloudy() and currentTemperature < 0 then
        return MoreFog.FogType.MEDIUM
    end

    if self:isSunny() and currentTemperature < 15 then
        return MoreFog.FogType.LIGHT
    end

    if self:getRandomSeasonalFog(1.0) then
        print("MoreFog: Setting fog from random seasonal fog.")
        return MoreFog.FogType.LIGHT
    end

    return MoreFog.FogType.HAZE
end

function MoreFog:getEveningFogType()
    local timeSinceLastRain = self.weather:getTimeSinceLastRain()
    local rainedInLast4Hours = timeSinceLastRain > 0 and timeSinceLastRain < 240
    local rainedInLast1Hour = timeSinceLastRain > 0 and timeSinceLastRain < 60
    local currentTemperature = self.weather:getCurrentTemperature()
    local _, highTemp = self.weather:getCurrentMinMaxTemperatures()

    if rainedInLast1Hour and currentTemperature > 18 and self:isSunny() then
        return MoreFog.FogType.LIGHT
    end

    if rainedInLast4Hours and currentTemperature > 20 and self:isSunny() then
        return MoreFog.FogType.LIGHT
    end

    if highTemp - currentTemperature > 7 then
        return MoreFog.FogType.LIGHT
    end

    if self:isCloudy() then
        return MoreFog.FogType.HAZE
    end

    if self:getRandomSeasonalFog(0.5) then
        print("MoreFog: Setting fog from random seasonal fog.")
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
    DebugUtil.printTableRecursively(fog)
    return fog;
end

function MoreFog:getRandomSeasonalFog(probabilityScaler)
    return (self:isWinter() and math.random() > 0.25 * probabilityScaler) or
               (self:isFall() and math.random() > 0.5 * probabilityScaler) or
               (self:isSpring() and math.random() > 0.65 * probabilityScaler) or
               (self:isSummer() and math.random() > 0.75 * probabilityScaler)
end

function MoreFog:isSunny()
    return self.weather:getCurrentWeatherType() == WeatherType.SUN
end

function MoreFog:isCloudy()
    return self.weather:getCurrentWeatherType() == WeatherType.CLOUDY
end

function MoreFog:willRain()
    local oneHr = 3600000
    local timeForFogFadeIn = oneHr * MoreFog.const.FOG_RAIN_FADE_IN
    return self.weather:getTimeUntilRain() < timeForFogFadeIn
end

function MoreFog:isWinter()
    return self.environment.currentVisualSeason == Environment.SEASON.WINTER
end

function MoreFog:isSpring()
    return self.environment.currentVisualSeason == Environment.SEASON.SPRING
end

function MoreFog:isSummer()
    return self.environment.currentVisualSeason == Environment.SEASON.SUMMER
end

function MoreFog:isFall()
    return self.environment.currentVisualSeason == Environment.SEASON.FALL
end

function MoreFog:toggleFog(enable, fadeTimeHrs, fogType)
    print("MoreFog: Setting fog to: " .. MoreFog.fogTypeToString(fogType))

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
    -- Height will peak at hour 6 with a value of 125, and the lowest point is hour 12 with a
    -- value of 75, on a 12-hour period. This helps avoid insanely bright fog duiring the hours 
    -- when the sun is low on the horizon.
    return 25 * math.sin(math.pi / 360 * (dayMinute - 180)) + 100
end

function MoreFog:consoleCommandSetFog(fogType)
    if fogType == "NONE" then
        self:toggleFog(true, 0, MoreFog.FogType.NONE)
        return "Fog set to NONE."
    elseif fogType == "HAZE" then
        self:toggleFog(true, 0, MoreFog.FogType.HAZE)
        return "Fog set to HAZE."
    elseif fogType == "LIGHT" then
        self:toggleFog(true, 0, MoreFog.FogType.LIGHT)
        return "Fog set to LIGHT."
    elseif fogType == "MEDIUM" then
        self:toggleFog(true, 0, MoreFog.FogType.MEDIUM)
        return "Fog set to MEDIUM."
    elseif fogType == "HEAVY" then
        self:toggleFog(true, 0, MoreFog.FogType.HEAVY)
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

local function weatherLoadCloudPresets(weather, xmlFile, key, cloudPresets)
    -- Clamp all the light damping for all cloud presets. Low fog depends on 
    -- lots of light being present, otherwise the lighting gets very dark. This
    -- is simpler than doing it at runtime and attempting to lerp the differences.
    for _, preset in pairs(cloudPresets) do
        if preset.lightDamping > 0.8 then
            preset.lightDamping = 0.8
        end
    end
end

local function weatherLoad(weather)
    weather.moreFog = MoreFog.new(weather)
    weather.moreFog:load()
end

Weather.load = Utils.appendedFunction(Weather.load, weatherLoad)
Weather.loadCloudPresets = Utils.appendedFunction(Weather.loadCloudPresets, weatherLoadCloudPresets)

