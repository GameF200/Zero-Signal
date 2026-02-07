--!strict
--!optimize 2

--[[
	----------                                     -------   ---                                 --- 
	      ---                                     ---   ---                                      --- 
	     ---    --------  --------  --------     ---         --- --------- ---------   -------   --- 
	   ----    ---    --- ----     ---    ---     ---------  ------    --- ---    ---       ---  --- 
	  ---      ---------- ---      ---    ---            --- ------    --- ---    ---  --------  --- 
	 ---       ---        ---      ---    ---     ---   ---  ------   ---- ---    --- ---   ---  --- 
	----------  --------  ---       --------       -------   --- --------- ---    ---  --------- --- 
	                                                                   ---                           
	                                                             --------                            
    ??????????  
    Zero Signal - next-gen Signal implementation for any your needs
                                                                      
    @license Apache 2.0
    @version 1.0.0
    @changelog:
   		- Initial Release                                                                                                  
--]]



--#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
-- Types
--#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
type Array<T> = {T}
type Fn = () -> ()

type Signal = {
	id        : number,
	
	Connect      : (self: Signal, Callback: (...any) -> ()) -> (),
	Once         : (self: Signal, Callback: (...any) -> ()) -> (),
	DisconnectAll: (self: Signal) -> (),
	Disconnect   : (self: Signal, Fn: (...any) -> ()) -> (),
	Destroy      : (self: Signal) -> (),
	Wait         : (self: Signal) -> (),
	Fire         : (self: Signal, ...any) -> ()
}

--#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
-- Constants
--#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
local CAPACITY = 196
local CALLBACKS_INITIAL_SIZE = 4
local EMPTY_LIST = table.freeze({})

--#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
-- SoA arrays
--#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
local Signals        : Array<Signal>         = table.create(CAPACITY) :: Array<Signal>
local Callbacks      : Array<Array<Fn>>      = table.create(CAPACITY, EMPTY_LIST)  :: Array<Array<Fn>> -- shared ref to 1 table
local OnceFlags      : Array<Array<boolean>> = table.create(CAPACITY, EMPTY_LIST)  :: Array<Array<boolean>>  -- shared ref too
local ConnectionCount: Array<number>         = table.create(CAPACITY, 0) -- sentinel value
local Count = 0

local Destroy = function(self: Signal)
	local id = self.id
	local last = Count

	-- swap-remove hell yeah
	if id ~= last then
		Callbacks[id] = Callbacks[last]
		OnceFlags[id] = OnceFlags[last]
		ConnectionCount[id] = ConnectionCount[last]

		local movedSignal = Signals[last]
		Signals[id] = movedSignal
		movedSignal.id = id
	end

	Signals[last] = nil
	Callbacks[last] = EMPTY_LIST
	OnceFlags[last] = EMPTY_LIST
	ConnectionCount[last] = 0

	Count -= 1
end

local Disconnect = function(self: Signal, Fn: (...any) -> ())
	local Id = self.id
	local list = Callbacks[Id]
	local flags = OnceFlags[Id]
	local n = ConnectionCount[Id]
	
	for i = 1, n do
		if list[i] == Fn then
			local last = n
			
			list[i] = list[last]
			flags[i] = flags[last]
			
			list[last] = nil
			flags[last] = nil
			
			ConnectionCount[Id] -= 1
			return
		end
	end
end

local DisconnectAll = function(self: Signal)
	local Id = self.id
	local list = Callbacks[Id]
	local flags = OnceFlags[Id]
	
	if list == EMPTY_LIST then return end
	
	table.clear(list)
	table.clear(flags)
	ConnectionCount[Id] = 0
end

local Connect = function(self: Signal, Callback: (...any) -> ())
	local Id = self.id
	local list = Callbacks[Id]
	
	if list == EMPTY_LIST then
		list = table.create(CALLBACKS_INITIAL_SIZE)
		Callbacks[Id] = list :: Array<Fn>
		OnceFlags[Id] = table.create(CALLBACKS_INITIAL_SIZE) :: Array<boolean>
	end
	
	local n = ConnectionCount[Id] + 1
	ConnectionCount[Id] = n
	
	list[n] = Callback
	OnceFlags[Id][n] = false
end

local Once = function(self: Signal, Callback: (...any) -> ())
	local Id = self.id
	local list = Callbacks[Id]
	if list == EMPTY_LIST then
		list = table.create(CALLBACKS_INITIAL_SIZE)
		Callbacks[Id] = list :: Array<Fn>
		OnceFlags[Id] = table.create(CALLBACKS_INITIAL_SIZE) :: Array<boolean>
	end

	local n = ConnectionCount[Id] + 1
	ConnectionCount[Id] = n

	list[n] = Callback
	OnceFlags[Id][n] = true
end


local Fire = function(self: Signal, ...)
	local Id = self.id
	
	local list = Callbacks[Id]
	if list == EMPTY_LIST then return end
	local flags = OnceFlags[Id]
	local n = ConnectionCount[Id]
	
	
	local i = 1
	while i <= n do
		list[i](...)
		
		if flags[i] == true then
			local last = n
			
			list[i] = list[last]
			flags[i] = flags[last]
			
			list[last] = nil
			flags[last] = nil
			
			n -= 1
			ConnectionCount[Id] = n
		else
			i += 1
		end
	end
end

local Wait = function(self: Signal)
	local thread = coroutine.running()

	self:Once(function(...)
		coroutine.resume(thread, ...)
	end)

	return coroutine.yield()
end

local Constructor = function(): Signal
	Count += 1
	local signal = {
		id = Count,
		Connect = Connect,
		Once = Once,
		Fire = Fire,
		Destroy = Destroy,
		Wait = Wait,
		DisconnectAll = DisconnectAll,
		Disconnect = Disconnect
	} :: Signal

	Signals[Count] = signal
	Callbacks[Count] = EMPTY_LIST
	OnceFlags[Count] = EMPTY_LIST
	ConnectionCount[Count] = 0

	return signal
end

return Constructor