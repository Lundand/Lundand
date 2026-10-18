--!strict
-- Puts the persistence library behind a small session interface, so services never depend on it
-- directly. ProfileStore is used when vendored at ServerScriptService.Server.Vendor.ProfileStore;
-- otherwise an in-memory provider keeps Studio testing possible (nothing is saved).
-- Session: { Data, End(), Save(), SaveAsync(timeout) -> boolean, OnEnded(callback) }
-- The ProfileStore calls follow its published API and have not been run yet (docs/INTEGRATION.md).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Table = require(ReplicatedStorage:WaitForChild("Shared").Util.Table)

local Server = script.Parent.Parent

local ProfileProviders = {}

local function profileStoreProvider(module: ModuleScript, storeName: string, template: any)
	local ProfileStore = require(module) :: any
	local store = ProfileStore.New(storeName, template)
	local provider = { kind = "ProfileStore" }

	function provider.startSession(player: Player)
		local profile = store:StartSessionAsync(tostring(player.UserId), {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})
		if profile == nil then
			return nil
		end
		profile:AddUserId(player.UserId)
		profile:Reconcile()
		local session = { Data = profile.Data }
		function session.End()
			if profile:IsActive() then
				profile:EndSession()
			end
		end
		function session.Save()
			if profile:IsActive() and profile.Save then
				profile:Save()
			end
		end
		-- Requests a save and waits for confirmation; used before acknowledging Robux purchases.
		function session.SaveAsync(timeout: number): boolean
			if not profile:IsActive() or not profile.Save or not profile.OnAfterSave then
				return false
			end
			local done = false
			local connection = profile.OnAfterSave:Connect(function()
				done = true
			end)
			profile:Save()
			local started = os.clock()
			while not done and os.clock() - started < timeout and profile:IsActive() do
				task.wait(0.1)
			end
			connection:Disconnect()
			return done
		end
		function session.OnEnded(callback: () -> ())
			profile.OnSessionEnd:Connect(callback)
		end
		return session
	end

	return provider
end

local function memoryProvider(template: any)
	local stored = {}
	local active = {}
	local provider = { kind = "Memory" }

	function provider.startSession(player: Player)
		local key = tostring(player.UserId)
		if active[key] then
			return nil
		end
		if stored[key] == nil then
			stored[key] = Table.deepCopy(template)
		end
		active[key] = true
		local callbacks = {}
		local session = { Data = stored[key] }
		function session.End()
			if active[key] then
				active[key] = nil
				for _, callback in ipairs(callbacks) do
					callback()
				end
			end
		end
		function session.Save() end
		function session.SaveAsync(timeout: number): boolean
			return true
		end
		function session.OnEnded(callback: () -> ())
			table.insert(callbacks, callback)
		end
		return session
	end

	return provider
end

function ProfileProviders.create(storeName: string, template: any)
	local vendor = Server:FindFirstChild("Vendor")
	local module = vendor and vendor:FindFirstChild("ProfileStore")
	if module and module:IsA("ModuleScript") then
		return profileStoreProvider(module, storeName, template)
	end
	return memoryProvider(template)
end

return ProfileProviders
