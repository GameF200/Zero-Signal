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
    @version 1.1.1
    @author super_sonic
    @changelog:
   		- Initial Release                                                                                                  
--]]



--#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
-- Types
--#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
type Array<T> = {T}
type Fn = () -> ()

export type Signal<T...> = {
	id        : number,
	
	Connect      : (self: Signal<T...>, Callback: (T...) -> ()) -> (),
	Once         : (self: Signal<T...>, Callback: (T...) -> ()) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	Disconnect   : (self: Signal<T...>, Fn: (T...) -> ()) -> (),
	Destroy      : (self: Signal<T...>) -> (),
	Wait         : (self: Signal<T...>) -> (),
	Fire         : (self: Signal<T...>, T...) -> ()
}

--#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
-- Constants
--#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
local CAPACITY = 196
local CALLBACKS_INITIAL_SIZE = 4
local NULL = table.freeze({})
type Nullable<T> = typeof(NULL) | T

--#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
-- SoA arrays
--#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
local Signals        : Array<Signal<any>>              = table.create(CAPACITY) :: Array<Signal<any>>
local Callbacks      : Array<Nullable<Array<Fn>>>      = table.create(CAPACITY, NULL)
local OnceFlags      : Array<Nullable<Array<boolean>>> = table.create(CAPACITY, NULL)  
local ConnectionCount: Array<number>                   = table.create(CAPACITY, 0) -- sentinel value
local Count = 0

local Destroy = function<T...>(self: Signal<T...>)
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
	Callbacks[last] = NULL
	OnceFlags[last] = NULL
	ConnectionCount[last] = 0

	Count -= 1
end

local Disconnect = function<T...>(self: Signal<T...>, Fn: (T...) -> ())
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

local DisconnectAll = function<T...>(self: Signal<T...>)
	local Id = self.id
	local list = Callbacks[Id]
	local flags = OnceFlags[Id]
	
	if list == NULL then return end
	
	table.clear(list)
	table.clear(flags)
	ConnectionCount[Id] = 0
end

local Connect = function<T...>(self: Signal<T...>, Callback: (T...) -> ())
	local Id = self.id
	local list = Callbacks[Id]
	
	if list == NULL then
		list = table.create(CALLBACKS_INITIAL_SIZE)
		Callbacks[Id] = list :: Array<Fn>
		OnceFlags[Id] = table.create(CALLBACKS_INITIAL_SIZE) :: Array<boolean>
	end
	
	local n = ConnectionCount[Id] + 1
	ConnectionCount[Id] = n
	
	list[n] = Callback
	OnceFlags[Id][n] = false
end

local Once = function<T...>(self: Signal<T...>, Callback: (T...) -> ())
	local Id = self.id
	local list = Callbacks[Id]
	if list == NULL then
		list = table.create(CALLBACKS_INITIAL_SIZE)
		Callbacks[Id] = list :: Array<Fn>
		OnceFlags[Id] = table.create(CALLBACKS_INITIAL_SIZE) :: Array<boolean>
	end

	local n = ConnectionCount[Id] + 1
	ConnectionCount[Id] = n

	list[n] = Callback
	OnceFlags[Id][n] = true
end


local Fire = function<T...>(self: Signal<T...>, ...)
	local Id = self.id
	
	local list = Callbacks[Id]
	if list == NULL then return end
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

local Wait = function<T...>(self: Signal<T...>)
	local thread = coroutine.running()

	self:Once(function(...)
		coroutine.resume(thread, ...)
	end)

	return coroutine.yield()
end

local Constructor = function<T...>(): Signal<T...>
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
	} :: Signal<T...>

	Signals[Count] = signal
	Callbacks[Count] = NULL
	OnceFlags[Count] = NULL
	ConnectionCount[Count] = 0

	return signal
end

return Constructor