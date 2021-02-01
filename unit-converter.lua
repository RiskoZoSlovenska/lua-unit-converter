--[[--
	@module unit-converter
	@author RiskoZoSlovenska
	@version 1.0.1
	@date Feb 2021
	@license MIT

	A Lua unit conversion library.

	So, welcome to this mess I call a unit converter! :D

	Mind that, well, I'm not the best at this, so just bear with me. Or make your own, I don't care.
	Also note that I originally made this for a (private) Discord bot, and that's why I went through the pain of
	unit aliases and stuff.

	I've tried my best to document the library's functions in LDoc (not sure if it's even valid tbh). I'll try to give
	a quick explanation of how this thing works (mostly because I like explaining stuff).

	When it comes to converting, storing a number for each possible conversion (metres -> inches, inches -> metres,
	metres -> kilometres, kilometres -> metres and so on.) is brutally inefficient. Instead, for each unit type I've defined
	one unit to act as a "base" - metres for distance, for example. Then, for each other unit I only need to remember one number,
	which can be used to convert from that unit to the base by multiplying (and from the base to that unit by dividing). So, if
	for example I want to convert from inches to kilometres, I first convert inches to metres and then metres to kilometres.

	Not all units work like this (a good example is converting from Celsius to Fahrenheit or Kelvin, as 0 Celsius ~= 0 Fahrenheit ~= 0 Kelvin),
	and so a function can be used instead of a number.


	In terms of string matching and unit aliases, each unit has a list of possible aliases and when a string is to be searched for num-unit
	pairs, I perform a string.gsub call on each possible alias. Yes, I know this is ugly and potentially slow. I did have an alternate,
	hopefully faster albeit much more complex system, but I decided to go with the mass gsub-ing for the sake of simplicity and because
	performance wasn't my priority (note that unit-to-unit conversions should still be kinda fast (I think)).


	Oh right! I almost forgot, unit key documentation: Each unit has a unit key, which is a short string. This string is to be passed
	to the convert function.

	The currently supported unit (keys) are:

		Time
			us
			w
			d
			s
			ps
			ms
			ns
			min
			h
			y
			fs
		Length
			ft
			in
			km
			mm
			nm
			yd
			m
			mi
			cm
			ly
			um
			au
		Weight
			g
			ct
			mg
			t
			kg
			oz
			lb
		Temperature
			c
			f
			k
		Area
			mi2
			km2
			in2
			yd2
			mm2
			cm2
			m2
			ac
			ft2
			ha
			um2
		Volume
			cm3
			um3
			ft3
			dl
			m3
			in3
			km3
			mi3
			mm3
			yd3
			l
			ml

	Sorry for the horrible formatting and everything. When in doubt, just Ctrl + F (or take a look at the UNIT_DATA table).

	Lastly, because this library was meant to be used by a Discord bot, for utility it also supports "common unit counterparts" -
	each unit has a designated other unit to which a number can be converted by suppling only the source unit.
]]


--- A table of basic character replacements to be performed on messages at first
local PRE_REPLACEMENTS = {
	-- Metres
	["nm"] = {"㎚"},
	["um"] = {"㎛", "μm"},
	["mm"] = {"㎜"},
	["cm"] = {"㎝"},
	["km"] = {"㎞"},

	-- Metres squared
	["mm2"] = {"㎣"},
	["cm2"] = {"㎠"},
	["m2"] = {"㎡"},
	["km2"] = {"㎢"},

	-- Metres cubed
	["mm3"] = {"㎣"},
	["cm3"] = {"㎤"},
	["m3"] = {"㎥"},
	["km3"] = {"㎦"},
	
	-- Squared/cubed suffixes
	["2"] = {"²", "%^2"},
	["3"] = {"³", "%^3"},

	--[[ Metres / second (currently not supported)
	["mps"] = {"㎧"},
	["mps2"] = {"㎨"},
	]]

	-- Seconds
	["ps"] = {"㎰"},
	["ns"] = {"㎱"},
	["us"] = {"㎲", "μs"},
	["ms"] = {"㎳"},

	--[[ -- Pascals (currently not supported)
	["pa"] = {"㎩"},
	["kpa"] = {"㎪"},
	["mpa"] = {"㎫"},
	["gpa"] = {"㎬"},
	]]
	
	--[[ -- Volts (currently not supported)
	["pv"] = {"㎴"},
	["nv"] = {"㎵"},
	["uv"] = {"㎶", "μv"},
	["mv"] = {"㎷"},
	["kv"] = {"㎸"},
	["mv"] = {"㎹"}, -- Duplicate index (case-sensitivity required?)
	]]

	-- Temperature
	["c"] = {"℃"},
	["f"] = {"℉"},
	["k"] = {"K"},

	-- Different spellings
	["metre"] = {"meter"},
	["litre"] = {"liter"},

	-- Other
	[""] = {"[^%P%^%.%+%-%/]"}, -- All punctuation except ^.-+/ -- Possibly also include $?
}

local unitAliases = {} -- These will be initialized right below
local unitConverters = {}
local unitTypes = {}
local unitCommonCounterparts = {}
do -- We will be able to throw away much of everything in this block

	--[[--
		Builds a list of unit aliases by prepending or appending strings.

		@param string[] modifiable all the base strings to prepend/append things to
		@param string[] prepends all the prefixes to prepend to each base string
		@param string[] appends all the suffixes to append to each base string
		@param string[] exceptions base strings to which no prepends/appends will be made
		@param boolean includeOriginal determines whether to inclide unmodified copies of each string
			in the modifiable array
		
		@return string[] the result of the build, as dictated by parameters
	]]
	local function buildAliases(modifiable, prepends, appends, exceptions, includeOriginal)
		local res = exceptions or {}

		for _, item in ipairs(modifiable) do
			if includeOriginal then
				table.insert(res, item)
			end

			for _, prepend in ipairs(prepends) do
				table.insert(res, prepend .. item)
			end

			for _, append in ipairs(appends) do
				table.insert(res, item .. append)
			end
		end

		return res
	end

	--[[--
		Appends an "s" to a list of aliases.

		Wrapper for @{buildAliases}.

		@param string[] modifiable string to which to append 's'
		@param string[] nonPluralable of strings to which to not append 's'

		@return string[] which contains all element of modifiable appended with an 's',
			all the original elements of modifiable as well as all the elements of nonPluralable
	]]
	local function buildAliasesNormal(modifiable, nonPluralable)
		return buildAliases(
			modifiable,
			{},
			{"s"},
			nonPluralable,
			true
		)
	end

	--[[
		Generates a list of aliases for square units by prepending and appending strings.

		Wrapper for @{buildAliases}.

		@param string[] modifiable the base strings which will be pluralized and prepended/appended to
		@param string[] exceptions the base string which will be left unmodified
		@param string[] nonPluralable the baseString which will not be pluralized, but will be prepended/appended to

		@return string[] the resulting aliases
	]]
	local function buildAliasesSquare(modifiable, exceptions, nonPluralable)
		return buildAliases(
			buildAliasesNormal(modifiable, nonPluralable),
			{ -- Prepends
				"square ",
				"sqr ",
			},
			{ -- Appends
				" squared",
				" sqrd",
				"2",
			},
			exceptions,
			false
		)
	end

	--[[
		Generates a list of aliases for cube units by prepending and appending strings.

		Wrapper for @{buildAliases}.

		@see @{buildAliasesSquare}

		@param string[] modifiable the base strings which will be pluralized and prepended/appended to
		@param string[] exceptions the base string which will be left unmodified
		@param string[] nonPluralable the baseString which will not be pluralized, but will be prepended/appended to

		@return string[] the resulting aliases
	]]
	local function buildAliasesCube(modifiable, exceptions, nonPluralable)
		return buildAliases(
			buildAliasesNormal(modifiable, nonPluralable),
			{ -- Prepends
				"cube ",
				"cb ",
			},
			{ -- Appends
				" cubed",
				" cbd",
				"3",
			},
			exceptions,
			false
		)
	end

	local UNIT_DATA = { -- This table will be thrown away
		length = { -- Length
			["m"] = { -- Metres
				aliases = buildAliasesNormal({"metre"}, {"m"}),
				convert = 1,
				commonCounterpart = "ft",
			},
			["km"] = { -- Kilometres
				aliases = buildAliasesNormal({"km", "kilometre"}),
				convert = 1000, -- (1e3)
				commonCounterpart = "mi",
			},
			["cm"] = { -- Centimetres
				aliases = buildAliasesNormal({"cm", "centimetre"}),
				convert = 1e-2,
				commonCounterpart = "in",
			},
			["mm"] = { -- Millimetres
				aliases = buildAliasesNormal({"mm", "millimetre"}),
				convert = 1e-3,
				commonCounterpart = "cm",
			},
			["um"] = { -- Micrometres
				aliases = buildAliasesNormal({"um", "micrometre"}),
				convert = 1e-6,
				commonCounterpart = "cm",
			},
			["nm"] = { -- Nanometres
				aliases = buildAliasesNormal({"nm", "nanometre"}),
				convert = 1e-9,
				commonCounterpart = "cm",
			},

			["mi"] = { -- Miles
				aliases = buildAliasesNormal({"mi", "mile"}),
				convert = 1609.344, -- https://en.wikipedia.org/wiki/Mile
				commonCounterpart = "km",
			},
			["yd"] = { -- Yards
				aliases = buildAliasesNormal({"yd", "yard"}),
				convert = 0.9144, -- https://en.wikipedia.org/wiki/Yard
				commonCounterpart = "m",
			},
			["ft"] = { -- Feet
				aliases = buildAliasesNormal({"ft"}, {"foot", "feet"}),
				convert = 0.3048, -- https://en.wikipedia.org/wiki/Foot_(unit)
				commonCounterpart = "m",
			},
			["in"] = { -- Inches
				aliases = buildAliasesNormal({"in"}, {"inch", "inches"}),
				convert = 0.0254, -- https://en.wikipedia.org/wiki/Inch
				commonCounterpart = "cm",
			},

			["au"] = { -- Astronomical units
				aliases = buildAliasesNormal({"au", "astronomicalunit", "astronomical unit", "astronomical"}),
				convert = 149597870700, -- https://en.wikipedia.org/wiki/Astronomical_unit
				commonCounterpart = "km",
			},
			["ly"] = { -- Light years
				aliases = buildAliasesNormal({"ly", "lightyear", "light year"}),
				convert = 9460730472580800, -- https://en.wikipedia.org/wiki/Light-year#Definitions
				commonCounterpart = "km",
			},
		},
		temperature = { -- Temperature
			["c"] = { -- Celsius
				aliases = {"c", "celsius", "centigrade"},
				convert = 1,
				commonCounterpart = "f",
			},
			["f"] = { -- Fahrenheit
				aliases = {"f", "fahrenheit"},
				convert = function(num, toBase) -- https://en.wikipedia.org/wiki/Fahrenheit#Definition_and_conversion
					if toBase then
						return (num - 32) * 5/9
					else
						return (num * 9/5) + 32
					end
				end,
				commonCounterpart = "c",
			},
			["k"] = { -- Kelvin
				aliases = {"k", "kelvin"},
				convert = function(num, toBase) -- https://en.wikipedia.org/wiki/Kelvin#Practical_uses
					if toBase then
						return num - 273.15
					else
						return num + 273.15
					end
				end,
				commonCounterpart = "c",
			},
		},
		area = { -- Area
			["m2"] = { -- Square Metres
				aliases = buildAliasesSquare({"m", "metre"}),
				convert = 1,
				commonCounterpart = "ft2",
			},
			["km2"] = { -- Square Kilometres
				aliases = buildAliasesSquare({"km", "kilometre"}),
				convert = 1e6,
				commonCounterpart = "mi2",
			},
			["cm2"] = { -- Square Centimetres
				aliases = buildAliasesSquare({"cm", "centimetre"}),
				convert = 1e-4,
				commonCounterpart = "in2",
			},
			["mm2"] = { -- Square Millimetres
				aliases = buildAliasesSquare({"mm", "millimetre"}),
				convert = 1e-6,
				commonCounterpart = "in2",
			},
			["um2"] = { -- Square Micrometres
				aliases = buildAliasesSquare({"um", "micrometre"}),
				convert = 1e-12,
				commonCounterpart = "in2",
			},
			["ha"] = { -- Hectares
				aliases = buildAliasesNormal({"hectare"}, {"ha", "hec"}),
				convert = 1e4, -- (10000) -- https://en.wikipedia.org/wiki/Hectare#Conversions
				commonCounterpart = "ac",
			},

			["mi2"] = { -- Square Miles
				aliases = buildAliasesSquare({"mi", "mile"}),
				convert = 2589988.110336,
				commonCounterpart = "km2",
			},
			["yd2"] = { -- Square Yards
				aliases = buildAliasesSquare({"yd", "yard"}),
				convert = 0.83612736,
				commonCounterpart = "m2",
			},
			["ft2"] = { -- Square Feet
				aliases = buildAliasesSquare({"ft"}, {}, {"feet", "foot"}),
				convert = 0.09290304,
				commonCounterpart = "m2",
			},
			["in2"] = { -- Square Inches
				aliases = buildAliasesSquare({"in"}, {}, {"inch", "inches"}),
				convert = 0.00064516,
				commonCounterpart = "cm2",
			},
			["ac"] = { -- Acres
				aliases = buildAliasesNormal({"ac", "acre"}),
				convert = 4046.8564224, -- https://en.wikipedia.org/wiki/Acre#Equivalence_to_other_units_of_area
				commonCounterpart = "ha",
			},
		},
		volume = { -- Volume
			["m3"] = { -- Cubic Metres
				aliases = buildAliasesCube({"m", "metre"}),
				convert = 1,
				commonCounterpart = "ft3",
			},
			["km3"] = { -- Cubic Kilometres
				aliases = buildAliasesCube({"km", "kilometre"}),
				convert = 1e9,
				commonCounterpart = "mi3",
			},
			["cm3"] = { -- Cubic Centimetres
				aliases = buildAliasesCube({"cm", "centimetre"}),
				convert = 1e-6,
				commonCounterpart = "ft3",
			},
			["mm3"] = { -- Cubic Millimetres
				aliases = buildAliasesCube({"mm", "millimetre"}),
				convert = 1e-9,
				commonCounterpart = "in3",
			},
			["um3"] = { -- Cubic Micrometres
				aliases = buildAliasesCube({"um", "micrometre"}),
				convert = 1e-18,
				commonCounterpart = "in3",
			},

			["mi3"] = { -- Cubic Miles
				aliases = buildAliasesCube({"mi", "mile"}),
				convert = 4168181825.440579584,
				commonCounterpart = "km3",
			},
			["yd3"] = { -- Cubic Yards
				aliases = buildAliasesCube({"yd", "yard"}),
				convert = 0.764554857984,
				commonCounterpart = "m3",
			},
			["ft3"] = { -- Cubic Feet
				aliases = buildAliasesCube({"ft"}, {}, {"foot", "feet"}),
				convert = 0.028316846592,
				commonCounterpart = "cm3",
			},
			["in3"] = { -- Cubic Inches
				aliases = buildAliasesCube({"in"}, {}, {"inch", "inches"}),
				convert = 0.000016387064,
				commonCounterpart = "cm3",
			},

			["l"] = { -- Litres
				aliases = buildAliasesNormal({"l", "litre"}),
				convert = 1e-3, -- https://en.wikipedia.org/wiki/Litre#Definition
				commonCounterpart = "cm3",
			},
			["dl"] = { -- Decilitres
				aliases = buildAliasesNormal({"dl", "decilitre"}, {"deci"}),
				convert = 1e-4,
				commonCounterpart = "cm3",
			},
			["ml"] = { -- Millilitres
				aliases = buildAliasesNormal({"ml", "millilitre"}),
				convert = 1e-6,
				commonCounterpart = "cm3",
			},

			--[[
			TODO: Add these

			["usgal"] = {}, -- US Gallon
			["usquart"] = {}, -- US Quart
			["uspint"] = {}, -- US Pint
			["uscup"] = {}, -- US Cup
			["usfluidounce"] = {}, -- US Fluid Ounce
			["ustbsp"] = {}, -- US Tablespoon
			["sutsp"] = {}, -- US Teaspoon

			["impgal"] = {}, -- Imperial Gallon
			["imptbsp"] = {}, -- Imperial Tablespoon
			["imptsp"] = {}, -- Imperial Teaspoon
			]]
		},
		weight = { -- Weight
			["g"] = { -- Grams
				aliases = buildAliasesNormal({"g", "gram"}),
				convert = 1,
				commonCounterpart = "oz",
			},
			["kg"] = { -- Kilograms
				aliases = buildAliasesNormal({"kg", "kilogram", "kilo"}),
				convert = 1e3, -- (1000)
				commonCounterpart = "lb",
			},
			["mg"] = { -- Milligrams
				aliases = buildAliasesNormal({"mg", "milligram"}),
				convert = 1e-3,
				commonCounterpart = "oz",
			},
			["t"] = { -- Metric Tonnes
				aliases = buildAliasesNormal({"t", "tonne", "ton", "metric tonne", "metric ton"}),
				convert = 1e6,
				commonCounterpart = "lb",
			},

			["lb"] = { -- Pounds
				aliases = buildAliasesNormal({"lb", "pound"}),
				convert = 453.59237, -- https://en.wikipedia.org/wiki/Pound_(mass)#Current_use
				commonCounterpart = "kg",
			},
			["oz"] = { -- International avoirdupois ounces
				aliases = buildAliasesNormal({"oz", "pound"}),
				convert = 28.349523125, -- https://en.wikipedia.org/wiki/Ounce#International_avoirdupois_ounce
				commonCounterpart = "g",
			},

			["ct"] = { -- Carats
				aliases = buildAliasesNormal({"ct", "carat", "karat"}),
				convert = 0.2, -- https://en.wikipedia.org/wiki/Carat_(mass)
				commonCounterpart = "kg",
			},
			-- TODO: Add long ton, short ton, atomicmass
		},
		time = { -- Time
			["s"] = { -- Seconds
				aliases = buildAliasesNormal({"s", "second", "sec"}),
				convert = 1,
				commonCounterpart = "ms",
			},
			["ms"] = { -- Milliseconds
				aliases = buildAliasesNormal({"ms", "millisecond", "milli"}),
				convert = 1e-3,
				commonCounterpart = "s",
			},
			["us"] = { -- Microseconds
				aliases = buildAliasesNormal({"us", "microsecond", "micro"}),
				convert = 1e-6,
				commonCounterpart = "s",
			},
			["ns"] = { -- Nanoseconds
				aliases = buildAliasesNormal({"ns", "nanosecond"}),
				convert = 1e-9,
				commonCounterpart = "s",
			},
			["ps"] = { -- Picoseconds
				aliases = buildAliasesNormal({"ps", "picosecond"}),
				convert = 1e-12,
				commonCounterpart = "s",
			},
			["fs"] = { -- Femtoseconds
				aliases = buildAliasesNormal({"fs", "femtosecond"}),
				convert = 1e-15,
				commonCounterpart = "s",
			},

			["min"] = { -- Minutes
				aliases = buildAliasesNormal({"min", "minute"}),
				convert = 60, -- (1000)
				commonCounterpart = "s",
			},
			["h"] = { -- Hours
				aliases = buildAliasesNormal({"h", "hr", "hour"}),
				convert = 360,
				commonCounterpart = "s",
			},
			["d"] = { -- Days
				aliases = buildAliasesNormal({"d", "day"}),
				convert = 86400,
				commonCounterpart = "s",
			},
			["w"] = { -- Weeks
				aliases = buildAliasesNormal({"w", "week"}),
				convert = 604800,
				commonCounterpart = "s",
			},
			["y"] = { -- Gregorian Years (365.2425 days)
				aliases = buildAliasesNormal({"y", "year"}),
				convert = 31556952, -- https://en.wikipedia.org/wiki/Gregorian_calendar
				commonCounterpart = "d",
			},
		},
	}

	for unitType, unitDatas in pairs(UNIT_DATA) do
		local convertersOfType = {}

		for unitKey, unitData in pairs(unitDatas) do
			convertersOfType[unitKey] = unitData.convert
			unitTypes[unitKey] = unitType
			unitCommonCounterparts[unitKey] = unitData.commonCounterpart

			for _, alias in ipairs(unitData.aliases) do
				table.insert(
					unitAliases,
					{
						alias = "%W" .. alias:gsub("%s", "%%W") .. "%W",
						key = unitKey
					}
				)
			end
		end

		unitConverters[unitType] = convertersOfType
	end

	table.sort( -- We want to try and match the longer aliases first, as shorter ones might be contained within longer ones
		unitAliases,
		function(aliasData1, aliasData2)
			return #aliasData1.alias > #aliasData2.alias
		end
	)

	-- Print all the units. Feel free to delete.
	--[[
	do
		local units = ""
		for unitType, unitDatas in pairs(UNIT_DATA) do
			units = units .. string.gsub(unitType, "^%l", string.upper) .. "\n"

			for unitKey, _ in pairs(unitDatas) do
				units = units .. "\t" .. unitKey .. "\n"
			end
		end
		print(units)
	end
	--]]
end

--[[--
	Converts a number using a converter.

	@param number num the number to convert
	@param number|function converter either a number or function which can be used to convert the number
	@param boolean toBase determines the direction this conversion is happening - true if to the base unit,
		false if from the base unit
]]
local function convertRaw(num, converter, toBase)
	if type(converter) ~= "function" then
		if toBase then
			return num * converter
		else
			return num / converter
		end
	else
		return converter(num, toBase)
	end
end

--[[--
	Converts a number from one unit to another by converting to a unit base and then from it.
	
	@param number num the number to convert
	@param string sourceUnits the key of the unit to convert from
	@param string targetUnits the key of the unit to convert to

	@return number the result of the conversion
	@return string the unit key of the result. Identical to targetUnits
]]
local function convert(num, sourceUnits, targetUnits)
	local sourceType = assert(unitTypes[sourceUnits], "Invalid source units!")
	local targetType = assert(unitTypes[targetUnits], "Invalid target units!")

	assert(sourceType == targetType, "Incompatible unit types!")

	local numInBase = convertRaw(num, unitConverters[sourceType][sourceUnits], true)
	local numInTarget = convertRaw(numInBase, unitConverters[targetType][targetUnits], false)

	return numInTarget, targetUnits
end

--[[--
	Wrapper for @{convert} which converts a number to the most common unit counterpart.

	@param number num the number to convert
	@param string sourceUnits the key of the unit to convert from

	@return number the result of the conversion
	@return string the unit key of the result
]]
local function convertToCommonCounterpart(num, sourceUnits)
	return convert(num, sourceUnits, unitCommonCounterparts[sourceUnits])
end


--[[--
	Takes a string and performs several @{string.gsub} operations on it to replace unit aliases with unit keys,
	to get rid of unicode characters and so on. Also @[string.lower}s the string.

	@param string str the string to clean
	@return string the cleaned string
]]
local function cleanString(str)
	str = string.lower(str)

	for replacement, replaceList in pairs(PRE_REPLACEMENTS) do
		for _, replace in ipairs(replaceList) do
			str = str:gsub(replace, replacement)
		end
	end

	str = ' ' .. str .. ' ' -- Padding to make sure edge cases also match
	for _, aliasData in ipairs(unitAliases) do
		str = str:gsub(aliasData.alias, ' ' .. aliasData.key .. ' ') -- Padding to compensate for the extra %W taken from sides
	end

	return str
end

--[[--
	Scans a string for number-unit pairs.

	@param string str the string to search
	@return table[] an array of found pairs. Each pair is a table in the form {num = foundNumber, unit = foundString},
		where foundNumber and foundString are the found number and unit key of the pair respectively
]]
local function findElementsInString(str)
	local cleaned = cleanString(str)
	local foundElements = {}

	for element in string.gmatch(cleaned, "%S+") do
		table.insert(foundElements,
			tonumber(element) or (unitTypes[element] and element) -- If is not number or valid unit, will insert nil which has no effect
		)
	end

	return foundElements
end


--[[
do -- Some tests idk how to do unit tests ;-;
	local tests = {
		["Hello, this road is a road"] = {},
		["Hello, this road is 10 roads"] = {10},
		["Hello, this road is 23 kilometres roads"] = {23, "km"},
		["Hello, this road is a mile"] = {"mi"},
		["Hello, this road is +32765012 us long"] = {32765012, "us"},
		["Hello, this road is 23.3241 metres roads"] = {23.3241, "m"},
		["Hello, this road is -23.3241 metres roads"] = {-23.3241, "m"},
	}

	for test, correctAnswer in pairs(tests) do
		local answer = findElementsInString(test)

		local correct = true
		for key, value in pairs(answer) do
			if correctAnswer[key] ~= value then
				correct = false
				break
			end
		end
		for key, value in pairs(correctAnswer) do
			if answer[key] ~= value then
				correct = false
				break
			end
		end

		if not correct then
			print(string.format(
				"Incorrect test %q.\nExpected: %q\nGot:      %q\n",
				test,
				table.concat(correctAnswer, "\", \""),
				table.concat(answer, "\", \"")
			))
		else
			print("Test passed")
		end
	end
end
--]]



return {
	convert = convert,
	convertToCommonCounterpart = convertToCommonCounterpart,

	findElementsInString = findElementsInString,
}