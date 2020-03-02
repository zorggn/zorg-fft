-- Plain lua i/FFT implementation
-- zorg @ 2020 § ISC
-- Mostly based on the lua port of the KissFFT Library (by Mark Borgerding) by Benjamin von Ardenne,
-- as well as KissFFT proper.

-- Currently implements the following:
-- - Recursive complex fft and ifft
-- - Optimized butterfly functions for factors 2,3,4,5 and a generic one otherwise.
-- * Complex types and calculations unrolled.

-- TODO: 
-- - Fix butterfly functions of radix 5 and the generic one, current implementations show ringing with pure tones.

local ffi = require 'ffi'
local cos, sin, pi = math.cos, math.sin, math.pi

-- Helper functions

local function nextFastSize(n)
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
	local n = #iRe+1
	local scratchRe, scratchIm = {},{}

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
				--if twidx >= n then twidx = twidx - n end
				twidx = ((twidx - 1) % n) + 1
				iRe[oidx+k] = iRe[oidx+k] + (scratchRe[q] * twRe[1+twidx] - scratchIm[q] * twIm[1+twidx])
				iIm[oidx+k] = iIm[oidx+k] + (scratchRe[q] * twIm[1+twidx] + scratchIm[q] * twRe[1+twidx])
			end
			k = k + m
		end
	end
end

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

	bfyEnum[p](oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p)
end

-- API functions

local function fft(inputRe, inputIm)

	assert(type(inputRe) == 'table',
		"A lua table needs to be passed as the first parameter.")

	-- Get array size
	local n = #inputRe

	-- Check for imaginary input component
	if not inputIm then
		inputIm = {} for i=0, n-1 do inputIm[1+i] = 0.0 end
	else
		assert(type(inputIm) == 'table',
		"A lua table needs to be passed as the second parameter.")
		assert(#inputRe == #inputIm,
		"Length mismatch between first and second parameters.")
	end

	local twiddlesRe, twiddlesIm = {},{}

	for i=0, n-1 do
		local phase = -2.0 * pi * i / n
		twiddlesRe[1+i], twiddlesIm[1+i] = cos(phase), sin(phase)
	end

	local factors = calculateFactors(n)

	local outputRe, outputIm = {},{}

	-- Define some locals so we know what parameters to the work function are what.
	local outputIndex = 1
	local factorCurrent = 1
	local factorIndex = 1
	local factorStride = 1
	local inputStride = 1

	-- Guts
	work(inputRe, inputIm,
		outputRe, outputIm, outputIndex,
		factorCurrent, factors, factorIndex,
		twiddlesRe, twiddlesIm,
		factorStride, inputStride,
		false)

	----
	return outputRe, outputIm
end

local function ifft(inputRe, inputIm)

	assert(type(inputRe) == 'table',
		"A lua table needs to be passed as the first parameter.")

	-- Get array size
	local n = #inputRe

	-- Check for imaginary input component

	if not inputIm then
		inputIm = {} for i=0, n-1 do inputIm[1+i] = 0.0 end
	else
		assert(type(inputIm) == 'table',
		"A lua table needs to be passed as the second parameter.")
		assert(#inputRe == #inputIm,
		"Length mismatch between first and second parameters.")
	end

	local twiddlesRe, twiddlesIm = {},{}

	for i=0, n-1 do
		local phase = 2.0 * pi * i / n
		twiddlesRe[i], twiddlesIm[i] = cos(phase), sin(phase)
	end

	local factors = calculateFactors(n)

	local outputRe, outputIm = {},{}

	-- Define some locals so we know what parameters to the work function are what.
	local outputIndex = 1
	local factorCurrent = 1
	local factorIndex = 1
	local factorStride = 1
	local inputStride = 1

	-- Guts
	work(inputRe, inputIm,
		outputRe, outputIm, outputIndex,
		factorCurrent, factors, factorIndex,
		twiddlesRe, twiddlesIm,
		factorStride, inputStride,
		true)

	----
	return outputRe, outputIm
end

----
return {fft = fft, ifft = ifft, nextFastSize = nextFastSize}