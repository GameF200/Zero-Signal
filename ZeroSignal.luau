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
    @version 1.3.1
    @author super_sonic
    @changelog:
   		- Fixed Wait function bug
		- Added some micro optimizations
		- Fixed NULL in Once function                                                                                             
--]]


--#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
-- Types
--#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
type Array<T> = {T}
type Fn = () -> ()

type Connection = {
	Disconnect: (self: Connection) -> (),
	_signalId : number?,
	_index    : number,
	_connected: boolean,
}

export type Signal<T...> = {
	id        : number,
	
	Connect      : (self: Signal<T...>, Callback: (T...) -> ()) -> (),
	Once         : (self: Signal<T...>, Callback: (T...) -> ()) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy      : (self: Signal<T...>) -> (),
	Wait         : (self: Signal<T...>) -> (),
	Fire         : (self: Signal<T...>, T...) -> ()
}

local table_clear = table.clear
local table_create = table.create

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
local Connections    : Array<Nullable<Array<any>>>     = table.create(CAPACITY, NULL)
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

local Disconnect = function(self: Connection)
	local signalId = self._signalId
	local index = self._index

	if not signalId then return end

	local list = Callbacks[signalId]
	local flags = OnceFlags[signalId]
	local conns = Connections[signalId]
	local n = ConnectionCount[signalId]

	if n == 0 then return end

	local last = n

	-- swap remove
	list[index] = list[last]
	flags[index] = flags[last]
	conns[index] = conns[last]

	local movedConn = conns[index]
	if movedConn then
		movedConn._index = index
	end

	list[last] = nil
	flags[last] = nil
	conns[last] = nil

	ConnectionCount[signalId] = n - 1
	self._signalId = nil
end

local DisconnectAll = function<T...>(self: Signal<T...>)
	local Id = self.id
	local list = Callbacks[Id]
	local flags = OnceFlags[Id]
	
	if list == NULL then return end
	
	table_clear(list)
	table_clear(flags)
	ConnectionCount[Id] = 0
end

local Connect = function<T...>(self: Signal<T...>, Callback: (T...) -> ())
	local Id = self.id
	local list = Callbacks[Id]

	if list == NULL then
		list = table_create(CALLBACKS_INITIAL_SIZE)
		Callbacks[Id] = list
		OnceFlags[Id] = table_create(CALLBACKS_INITIAL_SIZE)
		Connections[Id] = table_create(CALLBACKS_INITIAL_SIZE)
	end

	local n = ConnectionCount[Id] + 1
	ConnectionCount[Id] = n

	list[n] = Callback
	OnceFlags[Id][n] = false
	
	local conn = {
		_signalId = Id,
		_index = n,
		Disconnect = Disconnect,
	}

	Connections[Id][n] = conn

	return conn
end

local Once = function<T...>(self: Signal<T...>, Callback: (T...) -> ())
	local Id = self.id
	local list = Callbacks[Id]
	if list == NULL then
		list = table_create(CALLBACKS_INITIAL_SIZE)
		Callbacks[Id] = list :: Array<Fn>
		OnceFlags[Id] = table_create(CALLBACKS_INITIAL_SIZE) :: Array<boolean>
		Connections[Id] = table_create(CALLBACKS_INITIAL_SIZE)
	end

	local n = ConnectionCount[Id] + 1
	ConnectionCount[Id] = n

	list[n] = Callback
	OnceFlags[Id][n] = true
	
	local conn = {
		_signalId = Id,
		_index = n,
		Disconnect = Disconnect,
	}
	Connections[Id][n] = conn
	return conn
end


local Fire = function<T...>(self: Signal<T...>, ...)
	local Id = self.id
	
	local list = Callbacks[Id]
	if list == NULL then return end
	local flags = OnceFlags[Id]
	local n = ConnectionCount[Id]
	local conns = Connections[Id]
	
	local i = 1
	while i <= n do
		list[i](...)
		
		if flags[i] == true then
			local last = n
			
			list[i] = list[last]
			flags[i] = flags[last]
			
			local movedConn = conns[i]
			if movedConn then
				movedConn._index = i
			end
			
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
	local thread: thread = coroutine.running()
	if not thread then warn "Wait must be called inside a coroutine" end

	local fired = false
	local result: {any}

	self:Once(function(...)
		fired = true
		result = {...}
			
		if coroutine.status(thread) == "suspended" then
			coroutine.resume(thread)
		end
	end)

	if fired then
		return table.unpack(result)
	end

	coroutine.yield()
	return table.unpack(result)
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
	} :: Signal<T...>

	Signals[Count] = signal
	Callbacks[Count] = NULL
	OnceFlags[Count] = NULL
	ConnectionCount[Count] = 0

	return signal
end

return Constructor