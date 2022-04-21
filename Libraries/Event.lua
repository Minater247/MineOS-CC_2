
local event, handlers, interruptingKeysDown, lastInterrupt = {
	interruptingEnabled = true,
	interruptingDelay = 1,
	interruptingKeyCodes = {
		[29] = true,
		[46] = true,
		[56] = true
	},
	push = os.queueEvent
}, {}, {}, 0

local computerUptime, mathHuge, mathMin, skipSignalType = os.uptime, math.huge, math.min

--timeout is optional, and may be a name of a signal
--it may also be nil, in which case we have no timeout
local function computerPullSignal(timeout, ...)
	if type(timeout) == "number" then
		local timerID = os.startTimer(timeout)
		local polling = true
		local nevent
		local names = {..., "timer"}
		while polling do
			nevent = {os.pullEvent(unpack(names))}
			if nevent[1] == "timer" and nevent[2] == timerID then
				polling = false
				return nil
			else
				return unpack(nevent)
			end
		end
	else
		return os.pullEvent(...)
	end
end

--------------------------------------------------------------------------------------------------------

function event.addHandler(callback, interval, times)
	checkArg(1, callback, "function")
	checkArg(2, interval, "number", "nil")
	checkArg(3, times, "number", "nil")

	local handler = {
		callback = callback,
		times = times or mathHuge,
		interval = interval,
		nextTriggerTime = interval and computerUptime() + interval or 0
	}

	handlers[handler] = true

	return handler
end

function event.removeHandler(handler)
	checkArg(1, handler, "table")

	if handlers[handler] then
		handlers[handler] = nil

		return true
	else
		return false, "Handler with given table is not registered"
	end
end

function event.getHandlers()
	return handlers
end

function event.skip(signalType)
	skipSignalType = signalType
end

function event.pull(preferredTimeout)	
	local uptime, signalData = computerUptime()
	local deadline = uptime + (preferredTimeout or mathHuge)
	
	repeat
		-- Determining pullSignal timeout
		timeout = deadline
		for handler in pairs(handlers) do
			if handler.nextTriggerTime > 0 then
				timeout = mathMin(timeout, handler.nextTriggerTime)
			end
		end

		-- Pulling signal data
		signalData = { computerPullSignal(timeout - computerUptime()) }
				
		-- Handlers processing
		for handler in pairs(handlers) do
			if handler.times > 0 then
				uptime = computerUptime()

				if
					handler.nextTriggerTime <= uptime
				then
					handler.times = handler.times - 1
					if handler.nextTriggerTime > 0 then
						handler.nextTriggerTime = uptime + handler.interval
					end

					-- Callback running
					handler.callback(table.unpack(signalData))
				end
			else
				handlers[handler] = nil
			end
		end

		-- Program interruption support. It's faster to do it here instead of registering handlers
		if (signalData[1] == "key" or signalData[1] == "key_up") and event.interruptingEnabled then
			-- Analysing for which interrupting key is pressed - we don't need keyboard API for this
			if event.interruptingKeyCodes[signalData[4]] then
				interruptingKeysDown[signalData[4]] = signalData[1] == "key" and true or nil
			end

			local shouldInterrupt = true
			for keyCode in pairs(event.interruptingKeyCodes) do
				if not interruptingKeysDown[keyCode] then
					shouldInterrupt = false
				end
			end
			
			if shouldInterrupt and uptime - lastInterrupt > event.interruptingDelay then
				lastInterrupt = uptime
				error("interrupted", 0)
			end
		end
		
		-- Loop-breaking condition
		if signalData[1] then
			if signalData[1] == skipSignalType then
				skipSignalType = nil
			else
				return table.unpack(signalData)
			end
		end
	until uptime >= deadline
end

-- Sleeps "time" of seconds via "busy-wait" concept
function event.sleep(time)
	checkArg(1, time, "number", "nil")

	local deadline = computerUptime() + (time or 0)
	repeat
		event.pull(deadline - computerUptime())
	until computerUptime() >= deadline
end

--------------------------------------------------------------------------------------------------------

return event
