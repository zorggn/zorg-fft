-- Löve-specific i/FFT worker thread implementation
-- zorg @ 2020 § ISC
-- see zorgfft.lua for acknowledgements

require('love.thread')
require('love.timer')

-- Things are a bit different in a thread...
local initData = {...}

local current_folder = initData[2]
local ffi = require 'ffi'
local cos,sin,pi = math.cos,math.sin,math.pi

-- Save the thread's assigned named channel we passed.
local inChannel = initData[1]

-- Helper functions

-- Include butterfly functions
local bfyEnum = require(current_folder .. 'zorgfft_butterfly')

-- Computational functions

local function work(iRe, iIm, oRe, oIm, oidx, f, factors, fidx, twRe, twIm, fstride, istride, isInverse)
	local p, m  = factors[fidx], factors[fidx + 1]

	fidx = fidx + 2

	--print(#iRe, #iIm, #oRe, #oIm, #twRe, #twIm, fstride)

	local last  = oidx + p*m
	local begin = oidx

	if m == 1 then
		repeat
			oRe[oidx], oIm[oidx] = iRe[f], iIm[f]
			f = f + fstride * istride
			oidx = oidx + 1
		until oidx == last
	else
		repeat
			work(iRe, iIm, oRe, oIm, oidx, f, factors, fidx, twRe, twIm, fstride * p, istride, isInverse)
			f = f + fstride * istride
			oidx = oidx + m
		until oidx == last
	end

	oidx = begin

	bfyEnum[p](oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p)
end

-- Thread loop

while true do

	-- Handle messages in inbound queue. Atomic ops in the other threads should guarantee ordering
	-- of elements.
	local data = inChannel:pop()

	local fromChannel
	if data == 'procThread?' then
		-- Worker thread existence check
		fromChannel = inChannel:pop()
		fromChannel:push(true)
	elseif data == 'stop' then
		-- Worker thread shutdown
		return
	elseif data == 'work' then
		-- Worker thread process request
		fromChannel = inChannel:pop()

		local iRe, iIm, oRe, oIm, oidx, f, factors, fidx, twRe, twIm, fstride, istride, isInverse,
			BDiRe, BDiIm, BDoRe, BDoIm, BDFactors, BDtwRe, BDtwIm

		BDiRe		= inChannel:pop()
		BDiIm		= inChannel:pop()
		BDoRe		= inChannel:pop()
		BDoIm		= inChannel:pop()
		oidx		= inChannel:pop()
		f			= inChannel:pop()
		BDfactors	= inChannel:pop()
		fidx		= inChannel:pop()
		BDtwRe		= inChannel:pop()
		BDtwIm		= inChannel:pop()
		fstride		= inChannel:pop()
		istride		= inChannel:pop()
		isInverse	= inChannel:pop()

		iRe		= ffi.cast("double *", BDiRe:getFFIPointer())
		iIm		= ffi.cast("double *", BDiIm:getFFIPointer())
		oRe		= ffi.cast("double *", BDoRe:getFFIPointer())
		oIm		= ffi.cast("double *", BDoIm:getFFIPointer())
		factors	= ffi.cast("double *", BDfactors:getFFIPointer())
		twRe	= ffi.cast("double *", BDtwRe:getFFIPointer())
		twIm	= ffi.cast("double *", BDtwIm:getFFIPointer())

		-- Process one recursive work unit.
		work(iRe, iIm, oRe, oIm, oidx, f, factors, fidx, twRe, twIm, fstride, istride, isInverse)

		-- Send back signal that we're done processing.
		fromChannel:push(true)
	end
	
	-- Don't hog a core.
	love.timer.sleep(0.002)
end

-- TODO: when receiving data, process, then return