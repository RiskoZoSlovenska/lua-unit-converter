--[[--
	@module unit-converter
	@author RiskoZoSlovenska

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
	hopefully faster albeit much more complex system which makes up the vast majority of commented-out code in this library (yes, I
	know too many comments are unhealthy. welp.) I decided to go with the mass gsub-ing for the sake of simplicity and because
	performance wasn't my priority (note that unit-to-unit conversions are still kinda fast (I think)).

	If performance is an issue for you... (eek, does this mean you're actually using this in a high-stress, possibly professional
	environment? .-.) The old system worked by splitting up strings into arrays of words, holding these arrays in more arrays which were
	in one big dictionary, indexed by their first word, so something like:

	local aliases = {
		["metre"] = {
			{{"metre squared"}, "m2"},
			{{"metre cubed"}, "m3"},
			{{"metre"}, "m"},
		},
		["us"] = {
			-- Sorted by word list length
			{{"us", "liquid", "ounce"}, "uslqoz"},
			{{"us", "gallon"}, "usgal"},
			{{"us"}, "us"}, -- (Micrometres)
		},
		-- etc.
	}

	Then, when you have your string split up into an array of words, you simply look for a number "word" and check if the next few words
	correspond to any alias. (Sorry, that wasn't explained well, I know.)



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

	Lastly, because this library was meant to be used by a Discord bot, for utility it also support "common unit counterparts" - 
	each unit has a designated other unit to which a number can be converted by suppling only the target unit.


	aaaaaaand I think that's everything I have to tell you! Once again, I apoligize for my incompetence, and if for some reason
	you actually *do* decide to use this library, pls give me credit. Thanks!
]]



--- Metatable for an auto-constructing 2D-array
--[[local TWO_D_META = {
	__index = function(tbl, key)
		local new = {}
		tbl[key] = new
		return new
	end
}]]

--[[--
	Converts a string to an array of words.

	@tparam string str the string to split
	@treturn string[] an array of all %w+ pattersn in the string
]]
--[[local function stringToTable(str)
	local words = {}
	string.gsub(str, "[%-%w%.]+", function(word) table.insert(words, word) end)

	return words
end]]

--- A table of basic character replacements to be performed on messages at first
local PRE_REPLACEMENTS = {
	["km"] = {"㎞"},
	["cm"] = {"㎝"},
	["mm"] = {"㎜"},
	["um"] = {"㎛", "μm"},
	["nm"] = {"㎚"},
	["us"] = {"μs"},

	["km2"] = {"㎢"},
	["cm2"] = {"㎠"},
	["mm2"] = {"㎣"},

	["2"] = {"²", "%^2"},
	["3"] = {"³", "%^3"},

	["metre"] = {"meter"},
	["litre"] = {"liter"},

	[""] = {"[^%P%^%.]"}, -- All punctuation except ^ and .
}

local unitAliases = {} -- These will be initialized right below
local unitConverters = {}
local unitTypes = {}
local unitCommonCounterparts = {}
do -- We will be able to throw away much of everything in this block
	--[[--
		Builds a list of unit aliases by prepending or appending strings.

		@tparam string[] modifiable all the base strings to prepend/append things to
		@tparam string[] prepends all the prefixes to prepend to each base string
		@tparam string[] appends all the suffixes to append to each base string
		@tparam string[] exceptions base strings to which no prepends/appends will be made
		@tparam boolean includeOriginal determines whether to inclide unmodified copies of each string
			in the modifiable array
		
		@treturn string[] the result of the build, as dictated by parameters
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

		@tparam string[] modifiabl string to which to append 's'
		@tparam string[] nonPluralable of strings to which to not append 's'

		@treturn string[] which contains all element of modifiable appended with an 's',
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

		@tparam string[] modifiable the base strings which will be pluralized and prepended/appended to
		@tparam string[] exceptions the base string which will be left unmodified
		@tparam string[] nonPluralable the baseString which will not be pluralized, but will be prepended/appended to

		@treturn string[] the resulting aliases
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

		@tparam string[] modifiable the base strings which will be pluralized and prepended/appended to
		@tparam string[] exceptions the base string which will be left unmodified
		@tparam string[] nonPluralable the baseString which will not be pluralized, but will be prepended/appended to

		@treturn string[] the resulting aliases
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
				commonCounterpart = "in",
			},
			["um"] = { -- Micrometres
				aliases = buildAliasesNormal({"um", "micrometre"}),
				convert = 1e-6,
				commonCounterpart = "in",
			},
			["nm"] = { -- Nanometres
				aliases = buildAliasesNormal({"nm", "nanometre"}),
				convert = 1e-9,
				commonCounterpart = "in",
			},

			["mi"] = { -- Miles
				aliases = buildAliasesNormal({"mi", "mile"}),
				convert = 1609.344,
				commonCounterpart = "in",
			},
			["yd"] = { -- Yards
				aliases = buildAliasesNormal({"yd", "yard"}),
				convert = 0.9144,
				commonCounterpart = "in",
			},
			["ft"] = { -- Feet
				aliases = buildAliasesNormal({"ft"}, {"foot", "feet"}),
				convert = 0.3048,
				commonCounterpart = "in",
			},
			["in"] = { -- Inches -- ('in' is a keyword)
				aliases = buildAliasesNormal({"in"}, {"inch", "inches"}),
				convert = 0.0254,
				commonCounterpart = "in",
			},

			["ly"] = { -- Light years
				aliases = buildAliasesNormal({"ly", "lightyear", "light year"}),
				convert = 9460730472580800,
				commonCounterpart = "in",
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
				convert = function(num, toBase)
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
				convert = function(num, toBase)
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
				convert = 1e4, -- (10000)
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
				convert = 4046.8564224,
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
			["cm3"] = { -- Cubic Centimeteres
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
				convert = 1e-3,
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

			--[[["usgal"] = {}, -- US Gallon
			["usquart"] = {}, -- US Quart
			["uspint"] = {}, -- US Pint
			["uscup"] = {}, -- US Cup
			["usfluidounce"] = {}, -- US Fluid Ounce
			["ustbsp"] = {}, -- US Tablespoon
			["sutsp"] = {}, -- US Teaspoon

			impgal = {}, -- Imperial Gallon
			imptbsp = {}, -- Imperial Tablespoon
			imptsp = {}, -- Imperial Teaspoon]]
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
				convert = 453.59237,
				commonCounterpart = "kg",
			},
			["oz"] = { -- Ounces
				aliases = buildAliasesNormal({"oz", "pound"}),
				convert = 28.349523125,
				commonCounterpart = "g",
			},

			["ct"] = { -- Carats
				aliases = buildAliasesNormal({"ct", "carat", "karat"}),
				convert = 0.2,
				commonCounterpart = "kg",
			},

			--[[longton = {}, -- Long Ton
			shortton = {}, -- Short Ton

			atomicmass = {}, -- Atomic Mass Unit]]
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
				commonCounterpart = "lb",
			},
			["us"] = { -- Microseconds
				aliases = buildAliasesNormal({"us", "microsecond", "micro"}),
				convert = 1e-3,
				commonCounterpart = "oz",
			},
			["ns"] = { -- Nanoseconds
				aliases = buildAliasesNormal({"ns", "nanosecond"}),
				convert = 1e6,
				commonCounterpart = "lb",
			},
			["ps"] = { -- Picoseconds
				aliases = buildAliasesNormal({"ps", "picosecond"}),
				convert = 1,
				commonCounterpart = "oz",
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
			["y"] = { -- Julian Years (365.25 days)
				aliases = buildAliasesNormal({"y", "a", "year", "julian year"}),
				convert = 31557600,
				commonCounterpart = "lb",
			},
		},
	}

	--setmetatable(unitAliases, TWO_D_META) -- This and other comments in this block were from previous unit matching method

	for unitType, unitDatas in pairs(UNIT_DATA) do
		local convertertsOfType = {}

		for unitKey, unitData in pairs(unitDatas) do
			convertertsOfType[unitKey] = unitData.convert
			unitTypes[unitKey] = unitType
			unitCommonCounterparts[unitKey] = unitData.commonCounterpart

			--print(table.concat(unitData.aliases, ", "))
			for _, alias in ipairs(unitData.aliases) do
				--alias = stringToTable(alias)
				
				table.insert(
					unitAliases,
					--unitAliases[alias[1]],
					{
						alias = "%W" .. alias:gsub("%s", "%%W") .. "%W",
						-- alias = alias,
						key = unitKey
					}
				)
			end
		end

		unitConverters[unitType] = convertertsOfType
	end

	table.sort( -- We want to try and match the longer aliases first, as shorter ones might be contained within longer ones
		unitAliases,
		function(aliasData1, aliasData2)
			return #aliasData1.alias > #aliasData2.alias
		end
	)

	-- for _, aliasDatas in pairs(unitAliases) do
	-- 	table.sort(
	-- 		aliasDatas,
	-- 		function(aliasData1, aliasData2)
	-- 			return #aliasData1.alias > #aliasData2.alias -- Sort by ascending
	-- 		end
	-- 	)
	-- end

	--setmetatable(unitAliases, nil)

	-- Print all the units. Feel free to delete.
	--[[do
		local units = ""
		for unitType, unitDatas in pairs(UNIT_DATA) do
			units = units .. string.gsub(unitType, "^%l", string.upper) .. "\n"

			for unitKey, _ in pairs(unitDatas) do
				units = units .. "\t" .. unitKey .. "\n"
			end
		end
		print(units)
	end]]
end

--[[--
	Converts a number using a converter.

	@tparam number num the number to convert
	@tparam number|function either a number or function which can be used to convert the number
	@tparam boolean determines the direction this conversion is happening - true if to the base unit,
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
	
	@tparam number num the number to convert
	@tparam string sourceUnits the key of the unit to convert from
	@tparam string targetUnits the key of the unit to convert to

	@treturn number the result of the conversion
	@treturn string the unit key of the result. Identical to targetUnits
]]
local function convert(num, sourceUnits, targetUnits)
	local sourceType = assert(unitTypes[sourceUnits], "Invalid source units!")
	local targetType = assert(unitTypes[targetUnits], "Invalid target units!")

	assert(sourceType == targetType, "Incompatible unit types!")

	local numInBase = convertRaw(num, unitConverters[sourceType][sourceUnits], true)
	print(numInBase)
	local numInTarget = convertRaw(numInBase, unitConverters[targetType][targetUnits], false)

	return numInTarget, targetUnits
end

--[[--
	Wrapper for @{convert} which converts a number to the most common unit counterpart.

	@tparam number num the number to convert
	@tparam sourceUnits the key of the unit to convert from

	@treturn number the result of the conversion
	@treturn string the unit key of the result
]]
local function convertToCommonCounterpart(num, sourceUnits)
	return convert(num, sourceUnits, unitCommonCounterparts[sourceUnits])
end


--[[--
	Takes a string and performs several @{string.gsub} operations upon it to replace unit aliases with unit keys,
	to get rid of unicode characters and so on. Also lowers the string.

	@tparam string str the string to clean
	@treturn string the cleaned string
]]
local function cleanString(str)
	str = string.lower(str)

	for replacement, replaceList in pairs(PRE_REPLACEMENTS) do
		for _, replace in ipairs(replaceList) do
			str = str:gsub(replace, replacement)
		end
	end

	str = ' ' .. str .. ' '
	for _, aliasData in ipairs(unitAliases) do
		--print(str, aliasData.alias)
		str = str:gsub(aliasData.alias, ' ' .. aliasData.key .. ' ')
	end

	return str
end

--[[--
	Takes two lists and checks if one is contained within the other, starting from a certain position.

	Used for an alternate alias matching method.

	Read the implementation.

	@tparam table words an array of values
	@tparam number startNum the index from which to start the comparisonc checking
	@tparam table unitWords the table to check if is contained within the words table

	@treturn boolean whether unitWords is contained within words, starting at the startNum index
]]
--[[local function isUnitInWordList(words, startNum, unitWords)
	for wordIndex, unitWord in ipairs(unitWords) do
		if words[wordIndex + startNum - 1] ~= unitWord then
			return false
		end
	end

	return true
end]]

--[[--
	Calls a @{isUnitInWordList}  on all the possible alias word tables.

	Used for an alternate alias matching method.

	@tparam table words an array of values
	@tparam number startNum the index from which tp start the search

	@treturn string the key of the unit which was matched, or nil if none was matched
]]
--[[local function findUnitInWordList(words, startNum)
	local possibleAliases = unitAliases[(words[startNum])] -- Double ending brackets conflicted with comments
	if possibleAliases then
		for aliasWords, unitKey in pairs(possibleAliases) do
			if isUnitInWordList(words, startNum, aliasWords) then
				return unitKey
			end
		end
	end

	return nil
end]]

--[[--
	Scans a string for number-unit pairs.

	Implementation is for an alternate alias matching method.

	@tparam string str the string to search
	@treturn table[] an array of found pairs. Each pair is a table in the form {num = foundNumber, unit = foundString},
		where foundNumber and foundString are the found number and unit key of the pair respectively
]]
--[[local function findNumUnitPairsInString(str)
	str = cleanString(str)
	
	local words = stringToTable(str)
	local foundPairs = {}

	for wordNum, word in ipairs(words) do
		local num = tonumber(word)
		if num then
			-- Check if prev words are units
			local unitKey = findUnitInWordList(words, wordNum + 1)
			if unitKey then
				table.insert( -- Insert num-unit pair
					foundPairs,
					{
						num = num,
						unit = unitKey,
					}
				)
			end
		end
	end

	return foundPairs
end]]

--[[--
	Scans a string for number-unit pairs.

	@tparam string str the string to search
	@treturn table[] an array of found pairs. Each pair is a table in the form {num = foundNumber, unit = foundString},
		where foundNumber and foundString are the found number and unit key of the pair respectively
]]
local function findNumUnitPairsInString(str)
	local cleaned = cleanString(str)
	local foundPairs = {}

	for num, unit in string.gmatch(cleaned ,"%W(%-?[%d%.]+)%W+(%w+)") do -- Match a number (minus sign and decimals included) plus string
		if unitTypes[unit] then -- This is a valid unit.
			table.insert(
				foundPairs,
				{
					num = tonumber(num),
					unit = unit,
				}
			)
		end
	end

	return foundPairs
end


return {
	convert = convert,
	convertToCommonCounterpart = convertToCommonCounterpart,

	findNumUnitPairsInString = findNumUnitPairsInString,
}



--[[
-- Some tests idk how to do unit tests ;-;

for _, pair in ipairs(findNumUnitPairsInString("Hello, this road is 3781 meters long!")) do
	print(pair.num, pair.unit)
end
for _, pair in ipairs(findNumUnitPairsInString("Hello, this road is -3781 meters cubed long!")) do
	print(pair.num, pair.unit)
end
for _, pair in ipairs(findNumUnitPairsInString("Hello, this road is 3781.234 light years long!")) do
	print(pair.num, pair.unit)
end
for _, pair in ipairs(findNumUnitPairsInString("Hello, this road is -3781.12 us long!")) do
	print(pair.num, pair.unit)
end

print(convert(1, "mi", "ft"))
]]