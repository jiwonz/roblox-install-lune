-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2024-present jiwonz
--
-- Modifications:
-- - Ported to Luau from roblox-install by Kampfkarren under MPL 2.0.

local process = require("@lune/process")
local pathfs = require("../lune_packages/pathfs")
local dirs = require("../lune_packages/dirs")

local targetOs = process.os
local RegKey
if targetOs == "windows" then
	RegKey = require("../lune_packages/winreg").RegKey
end

local ROBLOX_STUDIO_PATH_VARIABLE = "ROBLOX_STUDIO_PATH"

local Error = {
	DocumentsDirectoryNotFound = "Couldn't find Documents directory",
	MalformedRegistry = "The values of the registry keys used to find Roblox are malformed, maybe your Roblox installation is corrupt?",
	PlatformNotSupported = "Your platform is not currently supported",
	PluginsDirectoryNotFound = "Couldn't find Plugins directory",
	RegistryError = "Couldn't find registry keys, Roblox might not be installed",
	EnvironmentVariableError = "Environment variable misconfigured: %s",
	NotInstalled = "Couldn't find Roblox Studio"
}

local function mapErr<T...>(err: string | (...any) -> (string), success: boolean, ...: T...): T...
	if success then
		return ...
	else
		if type(err) == "function" then
			err = err(...)
		end
		error(`{err}: {table.concat(table.pack(...), " ")}`, 2)
	end
end

export type RobloxStudio = {
	content: pathfs.Path,
	application: pathfs.Path,
	builtInPlugins: pathfs.Path,
	plugins: pathfs.Path,
	root: pathfs.Path
}

type RobloxStudioImpl = {
	locate: () -> (RobloxStudio),
	locateTargetSpecific: () -> (RobloxStudio),
	locatePluginsOnWindows: () -> (pathfs.Path),
	locateFromDirectory: (root: pathfs.Path) -> (RobloxStudio),
	locateFromWindowsDirectory: (root: pathfs.Path) -> (RobloxStudio),
	locateFromEnv: () -> (RobloxStudio?)
}

local RobloxStudio = {} :: RobloxStudioImpl

function RobloxStudio.locate()
	local robloxStudio = RobloxStudio.locateFromEnv()
	if robloxStudio then
		return robloxStudio
	end
	return RobloxStudio.locateTargetSpecific()
end

if targetOs == "windows" then
	function RobloxStudio.locateTargetSpecific()
		local hkcu = RegKey.predef("HKEY_CURRENT_USER")

		local robloxStudioReg = mapErr(
			Error.RegistryError,
			pcall(
				hkcu.openSubkey, hkcu,
				"Software\\Roblox\\RobloxStudio"
			)
		)

		local contentFolderValue: string = mapErr(
			Error.RegistryError,
			pcall(
				robloxStudioReg.getValue, robloxStudioReg,
				"ContentFolder"
			)
		)

		local contentFolderPath = pathfs.Path.from(contentFolderValue)

        local root = contentFolderPath:parent()
		if not root then
			error(Error.MalformedRegistry)
		end

        local plugins = RobloxStudio.locatePluginsOnWindows()

		return {
			content = contentFolderPath,
			application = root:join("RobloxStudioBeta.exe"),
			builtInPlugins = root:join("BuiltInPlugins"),
			plugins = plugins,
			root = root
		}
	end
end

if targetOs ~= "macos" then
    function RobloxStudio.locatePluginsOnWindows()
        local pluginDir = dirs.homeDir()
		if not pluginDir then
			error(Error.PluginsDirectoryNotFound)
		end
        pluginDir:push("AppData")
        pluginDir:push("Local")
        pluginDir:push("Roblox")
        pluginDir:push("Plugins")
		return pluginDir
	end
end

if targetOs == "macos" then
	function RobloxStudio.locateTargetSpecific()
		local root = pathfs.Path.from("/Applications")
		root:push("RobloxStudio.app")
		return RobloxStudio.locateFromDirectory(root)
	end
end

if targetOs ~= "windows" and targetOs ~= "macos" then
	function RobloxStudio.locateTargetSpecific()
		error(Error.PlatformNotSupported)
	end
end

if targetOs == "windows" then
	function RobloxStudio.locateFromDirectory(root)
		return RobloxStudio.locateFromWindowsDirectory(root)
	end
end

if targetOs ~= "macos" then
	function RobloxStudio.locateFromWindowsDirectory(root)
		local contentFolderPath = root:join("content")
		local plugins = RobloxStudio.locatePluginsOnWindows()

		if pathfs.isDir(contentFolderPath) then
			return {
				content = contentFolderPath,
				application = root:join("RobloxStudioBeta.exe"),
				builtInPlugins = root:join("BuiltInPlugins"),
				plugins = plugins,
				root = root
			}
		else
			local versions = root:join("Versions")

			if pathfs.isDir(versions) then
				local entries: { pathfs.Path } = mapErr(
					Error.NotInstalled,
					pcall(
						pathfs.readDir,
						versions
					)
				)
				for _, entry in entries do
					local version = pathfs.Path.from(entry)
					local application = version:join("RobloxStudioBeta.exe")

					if pathfs.isFile(application) then
						return {
							content = version:join("content"),
							application = application,
							builtInPlugins = version:join("BuiltInPlugins"),
							plugins = plugins,
							root = version
						}
					end
				end
				error(Error.NotInstalled)
			else
				error(Error.NotInstalled)
			end
		end
	end
end

if targetOs == "macos" then
	function RobloxStudio.locateFromDirectory(root)
		local contents = root:join("Contents")
		local application = contents:join("MacOS"):join("RobloxStudio")
		local builtInPlugins = contents:join("Resources"):join("BuiltInPlugins")
		local documents = dirs.documentDir()
		if not documents then
			error(Error.DocumentsDirectoryNotFound)
		end
		local plugins = documents:join("Roblox"):join("Plugins")
		local content = contents:join("Resources"):join("content")

		return {
			content = content,
			application = application,
			builtInPlugins = builtInPlugins,
			plugins = plugins,
			root = root
		}
	end
end

if targetOs ~= "windows" and targetOs ~= "macos" then
	function RobloxStudio.locateFromDirectory(root)
		return mapErr(
			Error.PlatformNotSupported,
			pcall(
				RobloxStudio.locateFromWindowsDirectory,
				root
			)
		)
	end
end

function RobloxStudio.locateFromEnv()
	local variableValue = process.env[ROBLOX_STUDIO_PATH_VARIABLE]
	if not variableValue then
		return
	end

	local result = RobloxStudio.locateFromDirectory(
		mapErr(
			function(err)
				return Error.EnvironmentVariableError:format(
					`could not convert environment variable '{ROBLOX_STUDIO_PATH_VARIABLE}' to path ({err})`
				)
			end,
			pcall(
				pathfs.Path.from,
				variableValue
			)
		)
	)

	return result
end

export type RobloxPlayer = {
	content: pathfs.Path,
	application: pathfs.Path,
	root: pathfs.Path
}

type RobloxPlayerImpl = {
	locate: () -> (RobloxPlayer)
}

local RobloxPlayer = {} :: RobloxPlayerImpl

if targetOs == "windows" then
	function RobloxPlayer.locate()
		local hkcu = RegKey.predef("HKEY_CURRENT_USER")

		local robloxPlayerReg = mapErr(
			Error.RegistryError,
			pcall(
				hkcu.openSubkey, hkcu,
				"Software\\ROBLOX Corporation\\Environments\\roblox-player"
			)
		)

		local clientExeValue: string = mapErr(
			Error.RegistryError,
			pcall(
				robloxPlayerReg.getValue, robloxPlayerReg,
				"clientExe"
			)
		)

		local clientExePath = pathfs.Path.from(clientExeValue)

		local root = clientExePath:parent()
		if not root then
			error(Error.MalformedRegistry)
		end

		return {
			content = root:join("content"),
			application = clientExePath,
			root = root
		}
	end
end

if targetOs ~= "windows" then
	function RobloxPlayer.locate()
		error(Error.PlatformNotSupported)
	end
end

return {
	RobloxStudio = RobloxStudio,
	RobloxPlayer = RobloxPlayer
}
