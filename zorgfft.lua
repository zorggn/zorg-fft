-- Löve-specific i/FFT implementation
-- zorg @ 2020 § ISC
-- Mostly based on the lua port of the KissFFT Library (by Mark Borgerding) by Benjamin von Ardenne,
-- as well as KissFFT proper.

-- Currently implements the following:
-- - Recursive complex fft and ifft
-- * Optimized butterfly functions for factors 2,3,4,5 and a generic one otherwise.
-- * Complex types and calculations unrolled.

-- TODO: 
-- - Utilize LÖVE ByteData/SoundData objects with double prec. values through FFI
--   for space, speed optimizations, as well as cross-thread accessibility.
-- - Threaded complex fft and ifft (WIP)
-- - Micro-optimizations
--   - math.pi / pi
--   - if-else chain / enum jumptable / enum jt + metatable for nil indexing

local ffi = require 'ffi'
local cos,sin,pi = math.cos,math.sin,math.pi



-- Helper functions

local function nextPossibleSize(n)
	local m = n
	while true do
		m = n
		while m % 2 == 0 do m = m / 2 end
		while m % 3 == 0 do m = m / 3 end
		while m % 5 == 0 do m = m / 5 end
		if m <= 1 then break end
		n = n + 1
	end
	return n
end

local function calculateFactors(n)
	local buffer = {}
	local i = 1
	local p = 4
	local floorSqrt = math.floor(math.sqrt(n))
	repeat
		while n%p > 0 do
			if      p == 4 then p = 2
			elseif  p == 2 then p = 3
			else                p = p + 2 
			end
			if p > floorSqrt then p = n end
		end
		n = n / p
		buffer[i]   = p
		buffer[i+1] = n
		i = i + 2
	until n <= 1
	return buffer
end



-- Butterfly functions

local function butterfly2(iRe, iIm, oidx, fstride, twRe, twIm, isInverse, m, p)
	local i1 = oidx
	local i2 = oidx + m
	local tw1 = 1
	repeat
		-- LuaJIT Numeric Performance Guide recommends not doing manual common subexpression elimination...
		-- However, we can't do that here, because this backs up values into the locals.
		local tRe = iRe[i2] * twRe[tw1] - iIm[i2] * twIm[tw1]
		local tIm = iRe[i2] * twIm[tw1] + iIm[i2] * twRe[tw1]
		tw1 = tw1 + fstride
		iRe[i2] = iRe[i1] - tRe
		iIm[i2] = iIm[i1] - tIm
		iRe[i1] = iRe[i1] + tRe
		iIm[i1] = iIm[i1] + tIm
		i1 = i1 + 1
		i2 = i2 + 1
		m = m - 1
	until m == 0
end

local function butterfly4(iRe, iIm, oidx, fstride, twRe, twIm, isInverse, m, p)
	local tw1, tw2, tw3 = 1, 1, 1
	local k = m
	local i = oidx
	local m2 = 2 * m
	local m3 = 3 * m
	local scratchRe, scratchIm = {},{} --ffi.new('double[6]'), ffi.new('double[6]')

	if not isInverse then repeat
		scratchRe[0] = iRe[i+m ] * twRe[tw1] - iIm[i+m ] * twIm[tw1]
		scratchIm[0] = iRe[i+m ] * twIm[tw1] + iIm[i+m ] * twRe[tw1]
		scratchRe[1] = iRe[i+m2] * twRe[tw2] - iIm[i+m2] * twIm[tw2]
		scratchIm[1] = iRe[i+m2] * twIm[tw2] + iIm[i+m2] * twRe[tw2]
		scratchRe[2] = iRe[i+m3] * twRe[tw3] - iIm[i+m3] * twIm[tw3]
		scratchIm[2] = iRe[i+m3] * twIm[tw3] + iIm[i+m3] * twRe[tw3]

		scratchRe[5] = iRe[i] - scratchRe[1]
		scratchIm[5] = iIm[i] - scratchIm[1]
		iRe[i] = iRe[i] + scratchRe[1]
		iIm[i] = iIm[i] + scratchIm[1]

		scratchRe[3] = scratchRe[0] + scratchRe[2]
		scratchIm[3] = scratchIm[0] + scratchIm[2]
		scratchRe[4] = scratchRe[0] - scratchRe[2]
		scratchIm[4] = scratchIm[0] - scratchIm[2]

		iRe[i+m2] = iRe[i] - scratchRe[3]
		iIm[i+m2] = iIm[i] - scratchIm[3]
		tw1 = tw1 + fstride
		tw2 = tw2 + fstride*2
		tw3 = tw3 + fstride*3
		iRe[i] = iRe[i] + scratchRe[3]
		iIm[i] = iIm[i] + scratchIm[3]

		-- part dependent on isInverse
		iRe[i+m ] = scratchRe[5] + scratchIm[4]
		iIm[i+m ] = scratchIm[5] - scratchRe[4]
		iRe[i+m3] = scratchRe[5] - scratchIm[4]
		iIm[i+m3] = scratchIm[5] + scratchRe[4]
		-- //

		i = i + 1
		k = k - 1
	until k == 0 else repeat
		scratchRe[0] = iRe[i+m ] * twRe[tw1] - iIm[i+m ] * twIm[tw1]
		scratchIm[0] = iRe[i+m ] * twIm[tw1] + iIm[i+m ] * twRe[tw1]
		scratchRe[1] = iRe[i+m2] * twRe[tw2] - iIm[i+m2] * twIm[tw2]
		scratchIm[1] = iRe[i+m2] * twIm[tw2] + iIm[i+m2] * twRe[tw2]
		scratchRe[2] = iRe[i+m3] * twRe[tw3] - iIm[i+m3] * twIm[tw3]
		scratchIm[2] = iRe[i+m3] * twIm[tw3] + iIm[i+m3] * twRe[tw3]

		scratchRe[5] = iRe[i] - scratchRe[1]
		scratchIm[5] = iIm[i] - scratchIm[1]
		iRe[i] = iRe[i] + scratchRe[1]
		iIm[i] = iIm[i] + scratchIm[1]

		scratchRe[3] = scratchRe[0] + scratchRe[2]
		scratchIm[3] = scratchIm[0] + scratchIm[2]
		scratchRe[4] = scratchRe[0] - scratchRe[2]
		scratchIm[4] = scratchIm[0] - scratchIm[2]

		iRe[i+m2] = iRe[i] - scratchRe[3]
		iIm[i+m2] = iIm[i] - scratchIm[3]
		tw1 = tw1 + fstride
		tw2 = tw2 + fstride*2
		tw3 = tw3 + fstride*3
		iRe[i] = iRe[i] + scratchRe[3]
		iIm[i] = iIm[i] + scratchIm[3]

		-- part dependent on isInverse
		iRe[i+m ] = scratchRe[5] - scratchIm[4]
		iIm[i+m ] = scratchIm[5] + scratchRe[4]
		iRe[i+m3] = scratchRe[5] + scratchIm[4]
		iIm[i+m3] = scratchIm[5] - scratchRe[4]
		-- //

		i = i + 1
		k = k - 1
	until k == 0 end
end

local function butterfly3(iRe, iIm, oidx, fstride, twRe, twIm, isInverse, m, p)
	local k  = m
	local m2 = m*2
	local tw1, tw2 = 1, 1
	local epi3Re, epi3Im = twRe[fstride*m], twIm[fstride*m]
	local i = oidx
	local scratchRe, scratchIm = {},{} --ffi.new('double[4]'), ffi.new('double[4]')

	repeat
		scratchRe[1] = iRe[i+m ] * twRe[tw1] - iIm[i+m ] * twIm[tw1]
		scratchIm[1] = iRe[i+m ] * twIm[tw1] + iIm[i+m ] * twRe[tw1]
		scratchRe[2] = iRe[i+m2] * twRe[tw2] - iIm[i+m2] * twIm[tw2]
		scratchIm[2] = iRe[i+m2] * twIm[tw2] + iIm[i+m2] * twRe[tw2]

		scratchRe[3] = scratchRe[1] + scratchRe[2]
		scratchIm[3] = scratchIm[1] + scratchIm[2]
		scratchRe[0] = scratchRe[1] - scratchRe[2]
		scratchIm[0] = scratchIm[1] - scratchIm[2]

		tw1 = tw1 + fstride
		tw2 = tw2 + fstride * 2

		iRe[i+m] = iRe[i] - scratchRe[3] * 0.5
		iIm[i+m] = iIm[i] - scratchIm[3] * 0.5

		scratchRe[0] = scratchRe[0] * epi3Im
		scratchIm[0] = scratchIm[0] * epi3Im
		iRe[i] = iRe[i] + scratchRe[3]
		iIm[i] = iIm[i] + scratchIm[3]

		iRe[i+m2] = iRe[i+m ] + scratchIm[0]
		iIm[i+m2] = iIm[i+m ] - scratchRe[0]

		iRe[i+m ] = iRe[i+m ] - scratchIm[0]
		iIm[i+m ] = iIm[i+m ] + scratchRe[0]

		i = i + 1
		k = k - 1
	until k == 0
end

local function butterfly5(iRe, iIm, oidx, fstride, twRe, twIm, isInverse, m, p)
	local i0, i1, i2, i3, i4 = oidx, oidx+m, oidx+2*m, oidx+3*m, oidx+4*m
	local yaRe, ybRe = twRe[1+fstride*m], twRe[1+fstride*2*m]
	local yaIm, ybIm = twIm[1+fstride*m], twIm[1+fstride*2*m]
	local scratchRe, scratchIm = {},{} --ffi.new('double[13]'), ffi.new('double[13]')

	for u = 0, m-1 do
		scratchRe[ 0] = iRe[i0]
		scratchIm[ 0] = iIm[i0]

		scratchRe[ 1] = iRe[i1] * twRe[1+  u*fstride] - iIm[i1] * twIm[1+  u*fstride]
		scratchIm[ 1] = iRe[i1] * twIm[1+  u*fstride] + iIm[i1] * twRe[1+  u*fstride]
		scratchRe[ 2] = iRe[i2] * twRe[1+2*u*fstride] - iIm[i2] * twIm[1+2*u*fstride]
		scratchIm[ 2] = iRe[i2] * twIm[1+2*u*fstride] + iIm[i2] * twRe[1+2*u*fstride]
		scratchRe[ 3] = iRe[i3] * twRe[1+3*u*fstride] - iIm[i3] * twIm[1+3*u*fstride]
		scratchIm[ 3] = iRe[i3] * twIm[1+3*u*fstride] + iIm[i3] * twRe[1+3*u*fstride]
		scratchRe[ 4] = iRe[i4] * twRe[1+4*u*fstride] - iIm[i4] * twIm[1+4*u*fstride]
		scratchIm[ 4] = iRe[i4] * twIm[1+4*u*fstride] + iIm[i4] * twRe[1+4*u*fstride]

		scratchRe[ 7] = scratchRe[1] + scratchRe[4]
		scratchIm[ 7] = scratchIm[1] + scratchIm[4]
		scratchRe[ 8] = scratchRe[2] + scratchRe[3]
		scratchIm[ 8] = scratchIm[2] + scratchIm[3]
		scratchRe[ 9] = scratchRe[2] - scratchRe[3]
		scratchIm[ 9] = scratchIm[2] - scratchIm[3]
		scratchRe[10] = scratchRe[1] - scratchRe[4]
		scratchIm[10] = scratchIm[1] - scratchIm[4]

		iRe[i0] = iRe[i0] + scratchRe[7] + scratchRe[8]
		iIm[i0] = iIm[i0] + scratchIm[7] + scratchIm[8]

		scratchRe[ 5] = scratchRe[0] + scratchRe[7] * yaRe + scratchRe[8] * ybRe
		scratchIm[ 5] = scratchIm[0] + scratchIm[7] * yaRe + scratchIm[8] * ybRe

		scratchRe[ 6] =        scratchIm[10] * yaIm + scratchIm[9] * ybIm
		scratchIm[ 6] = -1.0 * scratchRe[10] * yaIm + scratchRe[9] * ybIm

		iRe[i1] = scratchRe[5] - scratchRe[6]
		iIm[i1] = scratchIm[5] - scratchIm[6]
		iRe[i4] = scratchRe[5] + scratchRe[6]
		iIm[i4] = scratchIm[5] + scratchIm[6]

		scratchRe[11] = scratchRe[0] + scratchRe[7] * ybRe + scratchRe[8] * yaRe
		scratchIm[11] = scratchIm[0] + scratchIm[7] * ybRe + scratchIm[8] * yaRe

		scratchRe[12] = -1.0 * scratchIm[10] * ybIm + scratchIm[9] * yaIm
		scratchIm[12] =        scratchRe[10] * ybIm - scratchRe[9] * yaIm

		iRe[i2] = scratchRe[11] + scratchRe[12]
		iIm[i2] = scratchIm[11] + scratchIm[12]
		iRe[i3] = scratchRe[11] - scratchRe[12]
		iIm[i3] = scratchIm[11] - scratchIm[12]

		i0 = i0 + 1
		i1 = i1 + 1
		i2 = i2 + 1
		i3 = i3 + 1
		i4 = i4 + 1
	end
end

local function butterflyG(iRe, iIm, oidx, fstride, twRe, twIm, isInverse, m, p)
	local n = #iRe+1 --ffi.sizeof(iRe) / ffi.sizeof('double')
	local scratchRe, scratchIm = {},{} --ffi.new('double[' .. p .. ']'), ffi.new('double[' .. p .. ']')

	for u = 0, m - 1 do
		local k = u
		for q1 = 0, p-1 do
			scratchRe[q1] = iRe[oidx+k]
			scratchIm[q1] = iIm[oidx+k]
			k = k + m
		end
		k = u
		for q1 = 0, p-1 do
			local twidx = 0
			iRe[oidx+k] = scratchRe[0]
			iIm[oidx+k] = scratchIm[0]
			for q=1, p-1 do
				twidx = twidx + fstride * k
				if twidx >= n then twidx = twidx - n end
				iRe[oidx+k] = iRe[oidx+k] + (scratchRe[q] * twRe[1+twidx] - scratchIm[q] * twIm[1+twidx])
				iIm[oidx+k] = iIm[oidx+k] + (scratchRe[q] * twIm[1+twidx] + scratchIm[q] * twRe[1+twidx])
			end
			k = k + m
		end
	end
end

-- TESTME: if having a metatable to this to return butterflyG on undefined key would be faster or not.
--         also whether the metamethod should return t[1] or butterflyG directly.
local bfyEnum = {butterflyG, butterfly2, butterfly3, butterfly4, butterfly5}
setmetatable(bfyEnum, {__index = function(t,k) return t[1] end})



-- Computational functions

local function work(iRe, iIm, oRe, oIm, oidx, f, factors, fidx, twRe, twIm, fstride, istride, isInverse)
	local p, m  = factors[fidx], factors[fidx + 1]
	fidx = fidx + 2

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

	--TODO: Performance test
	-- RESULTS: Not significant enough to care about which implementation is used.
		-- 327-370 us average for one call w/ windowsize of 1024, using if-else chain;
		-- 331-375 us average for one call w/ windowsize of 1024, using table access and else for generic;
		-- 333-378 us average for one call w/ windowsize of 1024, using table access with metatable for generic.
		-- 5618-6327 us, 5529-6182 us, 5579-6312 us for 16k window
		-- 11-12 us, 11-14 us, 12-14 us for 32 window
	---[[
	bfyEnum[p](oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p)
	--]]
	--[[
	if bfyEnum[p] then bfyEnum[p](oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p)
	              else butterflyG(oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p)
	end
	--]]
	--[[
	if     p == 2 then butterfly2(oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p) --print "2"
	elseif p == 3 then butterfly3(oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p) --print "3"
	elseif p == 4 then butterfly4(oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p) --print "4"
	elseif p == 5 then butterfly5(oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p) --print "5"
	else               butterflyG(oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p) --print "G"
	end
	--]]
end

local function work_t(iRe, iIm, oRe, oIm, oidx, f, factors, fidx, twRe, twIm, fstride, istride, isInverse)
	local p, m  = factors[fidx], factors[fidx + 1]
	fidx = fidx + 2

	-- Threaded call (top-level only)
	if fstride == 1 and p <= 5 and m ~= 1 then
		for k = 0, p-1 do
			work(iRe, iIm, oRe, oIm, oidx + m * k, f + fstride * istride * k, factors, fidx, twRe, twIm, fstride * p, istride, isInverse)
		end
	end

	--TODO: Performance test
	--[[
	if bfyEnum[p] then bfyEnum[p](oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p)
	              else butterflyG(oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p)
	end
	--]]
	---[[
	if     p == 2 then butterfly2(oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p) --print "2"
	elseif p == 3 then butterfly3(oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p) --print "3"
	elseif p == 4 then butterfly4(oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p) --print "4"
	elseif p == 5 then butterfly5(oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p) --print "5"
	else               butterflyG(oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p) --print "G"
	end
	--]]
end

-- API functions

local function fft(n, inputRe, inputIm)
	assert(n == nextPossibleSize(n),
		string.format("Can't work on input of size %i, give an input of size %i padded with zeros at the end.",
			n, nextPossibleSize(n)))

	if not inputIm then
		--inputIm = ffi.new('double[' .. n .. ']')
		inputIm = {} for i=0, n-1 do inputIm[1+i] = 0.0 end -- TESTME: param means this shouldn't leak as a global
	end

	local twiddlesRe, twiddlesIm = {},{} --ffi.new('double[' .. n .. ']'), ffi.new('double[' .. n .. ']')

	for i=0, n-1 do
		local phase = -2.0 * pi * i / n
		twiddlesRe[1+i], twiddlesIm[1+i] = cos(phase), sin(phase)
	end

	local factors = calculateFactors(n)

	-- TESTME: Is the output size guaranteed to be, at most, equal to the input size?
	local outputRe, outputIm = {},{} --ffi.new('double[' .. n .. ']'), ffi.new('double[' .. n .. ']')

	-- 2 input components, 2 output components, output index,
	-- f, factors, factor index, 2 twiddle components, fstride, input stride, isInverse
	work(inputRe, inputIm, outputRe, outputIm, 1, 1, factors, 1, twiddlesRe, twiddlesIm, 1, 1, false)

	return outputRe, outputIm
end

local function ifft(n, inputRe, inputIm)
	assert(n == nextPossibleSize(n),
		string.format("Can't work on input of size %i, give an input of size %i padded with zeros at the end.",
			n, nextPossibleSize(n)))

	local inputIm = inputIm
	if not inputIm then
		--inputIm = ffi.new('double[' .. n .. ']')
		inputIm = {} for i=0, n-1 do inputIm[1+i] = 0.0 end -- TESTME: param means this shouldn't leak as a global
	end

	local twiddlesRe, twiddlesIm = {},{} --ffi.new('double[' .. n .. ']'), ffi.new('double[' .. n .. ']')

	for i=0, n-1 do
		local phase = 2.0 * pi * i / n
		twiddlesRe[i], twiddlesIm[i] = cos(phase), sin(phase)
	end

	local factors = calculateFactors(n)

	-- TESTME: Is the output size guaranteed to be, at most, equal to the input size?
	local outputRe, outputIm = {},{} --ffi.new('double[' .. n .. ']'), ffi.new('double[' .. n .. ']')

	-- 2 input components, 2 output components, output index,
	-- f, factors, factor index, 2 twiddle components, fstride, input stride, isInverse
	work(inputRe, inputIm, outputRe, outputIm, 1, 1, factors, 1, twiddlesRe, twiddlesIm, 1, 1, true)

	return outputRe, outputIm
end

local function fft_t(n, inputRe, inputIm, threadCount)
	assert(love.thread,
		"This function needs love.thread to be loaded!")

	assert(n == nextPossibleSize(n),
		string.format("Can't work on input of size %i, give an input of size %i padded with zeros at the end.",
			n, nextPossibleSize(n)))

	if not inputIm then
		--inputIm = ffi.new('double[' .. n .. ']')
		inputIm = {} for i=0, n-1 do inputIm[1+i] = 0.0 end -- TESTME: param means this shouldn't leak as a global
	end

	local twiddlesRe, twiddlesIm = {},{} --ffi.new('double[' .. n .. ']'), ffi.new('double[' .. n .. ']')

	for i=0, n-1 do
		local phase = -2.0 * pi * i / n
		twiddlesRe[1+i], twiddlesIm[1+i] = cos(phase), sin(phase)
	end

	local factors = calculateFactors(n)

	-- TESTME: Is the output size guaranteed to be, at most, equal to the input size?
	local outputRe, outputIm = {},{} --ffi.new('double[' .. n .. ']'), ffi.new('double[' .. n .. ']')

	-- TODO: Check if threadCount worker threads exist or not,
	--       if not, create as much as needed, then keep them around.


	-- 2 input components, 2 output components, output index,
	-- f, factors, factor index, 2 twiddle components, fstride, input stride, isInverse
	work_t(inputRe, inputIm, outputRe, outputIm, 1, 1, factors, 1, twiddlesRe, twiddlesIm, 1, 1, false)

	return outputRe, outputIm
end

local function ifft_t(n, inputRe, inputIm, threadCount)
	assert(love.thread,
		"This function needs love.thread to be loaded!")

	assert(n == nextPossibleSize(n),
		string.format("Can't work on input of size %i, give an input of size %i padded with zeros at the end.",
			n, nextPossibleSize(n)))

	local inputIm = inputIm
	if not inputIm then
		inputIm = ffi.new('double[' .. n .. ']')
	end

	local twiddlesRe, twiddlesIm = ffi.new('double[' .. n .. ']'), ffi.new('double[' .. n .. ']')

	for i=0, n-1 do
		local phase = 2.0 * pi * i / n
		twiddlesRe[i], twiddlesIm[i] = cos(phase), sin(phase)
	end

	local factors = calculateFactors(n)

	-- TESTME: Is the output size guaranteed to be, at most, equal to the input size?
	local outputRe, outputIm = ffi.new('double[' .. n .. ']'), ffi.new('double[' .. n .. ']')

	-- TODO: Check if threadCount worker threads exist or not,
	--       if not, create as much as needed, then keep them around.


	-- 2 input components, 2 output components, output index,
	-- f, factors, factor index, 2 twiddle components, fstride, input stride, isInverse
	work_t(inputRe, inputIm, outputRe, outputIm, 0, 0, factors, 0, twiddlesRe, twiddlesIm, 1, 1, true)

	return outputRe, outputIm
end

----
return {fft = fft, ifft = ifft, fft_t = fft_t, ifft_t = ifft_t}