-- Performance tests

local ffi = require 'ffi'
local zfft = require 'zorgfft'

-- We also want to compare our versions to something else, so...
local complex = {new = require 'ext.complex'}
local luafft = require 'ext.luafft' -- modified to not barf into the global namespace (had an issue already on this on github)

local sampleRate           = 44100 -- test whether we can realtime run this (doesn't take other code's CPU tax into account)
local runCount             =  1000 -- number of fft/ifft calls run on a buffer
local batchCount           =    16 -- repetitions of above amount of runs for averaging purposes
local firstWindowMagnitude =    10 -- 5 --> 32  freq. resolution
local lastWindowMagnitude  =    10 --14 --> 16k freq. resolution

function love.load()

	-- Lua table version - using ext/complex.lua (only used by luafft library)
	local luaTableComplex = {}

	-- Lua table version - separated real and imaginary components
	local luaTableRe, luaTableIm = {}, {}
	local _Re, _Im

	-- timing variables
	local times = {}
	local start, stop = 0, 0
	local average = 0

	-- Test with defined window sizes
	for k = firstWindowMagnitude, lastWindowMagnitude do

		local windowSize = 2^k
		local log = math.floor(math.log10(batchCount))

		for n=1, windowSize do
			luaTableComplex[n] = complex.new( love.math.random(), love.math.random())
			luaTableRe[n], luaTableIm[n] = love.math.random(), love.math.random()
		end

		-- Our implementation - lua tables - FFT
		print("zfft.fft - lua tables (separated real & imaginary components)")
		for j = 0, batchCount-1 do
			start = love.timer.getTime()
			for i = 1, runCount do
				_Re, _Im = zfft.fft(windowSize, luaTableRe, luaTableIm)
			end
			stop = love.timer.getTime()
			times[j] = stop-start
			print(("Time for batch #%0"..log.."X: %0.8f seconds."):format(j, times[j]))
		end
		for n = 1, #times-1 do average = average + times[n] end
		average = average / #times
		print(("Time took (average of %d-2 batches of %d runs on a %d long window): %0.8f seconds."):format(
			batchCount, runCount, windowSize, average))
		print(("Estimated runtime of one call: %0.8f seconds. (%0.8f ms) (%0.8f μs)"):format(
			average/runCount, (average/runCount)*1000, (average/runCount)*1000000))
		print()

		-- Our implementation - lua tables - inverse FFT
		print("zfft.ifft - lua tables (separated real & imaginary components)")
		for j = 0, batchCount-1 do
			start = love.timer.getTime()
			for i = 1, runCount do
				_Re, _Im = zfft.ifft(windowSize, luaTableRe, luaTableIm)
			end
			stop = love.timer.getTime()
			times[j] = stop-start
			print(("Time for batch #%0"..log.."X: %0.8f seconds."):format(j, times[j]))
		end
		for n = 1, #times-1 do average = average + times[n] end
		average = average / #times
		print(("Time took (average of %d-2 batches of %d runs on a %d long window): %0.8f seconds."):format(
			batchCount, runCount, windowSize, average))
		print(("Estimated runtime of one call: %0.8f seconds. (%0.8f ms) (%0.8f μs)"):format(
			average/runCount, (average/runCount)*1000, (average/runCount)*1000000))
		print()

		-- luafft - FFT
		print("luafft.fft - lua tables (using complex library)")
		for j = 0, batchCount-1 do
			start = love.timer.getTime()
			for i = 1, runCount do
				_Complex = luafft.fft(luaTableComplex, false)
			end
			stop = love.timer.getTime()
			times[j] = stop-start
			print(("Time for batch #%0"..log.."X: %0.8f seconds."):format(j, times[j]))
		end
		for n = 1, #times-1 do average = average + times[n] end
		average = average / #times
		print(("Time took (average of %d-2 batches of %d runs on a %d long window): %0.8f seconds."):format(
			batchCount, runCount, windowSize, average))
		print(("Estimated runtime of one call: %0.8f seconds. (%0.8f ms) (%0.8f μs)"):format(
			average/runCount, (average/runCount)*1000, (average/runCount)*1000000))
		print()

		-- luafft - inverse FFT
		print("luafft.fft - lua tables (using complex library)")
		for j = 0, batchCount-1 do
			start = love.timer.getTime()
			for i = 1, runCount do
				_Complex = luafft.fft(luaTableComplex, true)
			end
			stop = love.timer.getTime()
			times[j] = stop-start
			print(("Time for batch #%0"..log.."X: %0.8f seconds."):format(j, times[j]))
		end
		for n = 1, #times-1 do average = average + times[n] end
		average = average / #times
		print(("Time took (average of %d-2 batches of %d runs on a %d long window): %0.8f seconds."):format(
			batchCount, runCount, windowSize, average))
		print(("Estimated runtime of one call: %0.8f seconds. (%0.8f ms) (%0.8f μs)"):format(
			average/runCount, (average/runCount)*1000, (average/runCount)*1000000))
		print()
	end

end