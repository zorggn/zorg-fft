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

local current_folder = (...):match("(.-)[^%.]+$")
local ffi = require 'ffi'
local cos, sin, pi = math.cos, math.sin, math.pi
-- PERF TEST: math.pi localizing
-- localized:      11 us - 14 us | 336 us - 371 us
-- in math module: 11 us - 15 us | 342 us - 380 us
-- Yeah, keep it local.

local bfyEnum = require(current_folder .. 'zorgfft_butterfly')

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

local function work_t(iRe, iIm, oRe, oIm, oidx, f, factors, fidx, twRe, twIm, fstride, istride, isInverse)
	local p, m  = factors[fidx], factors[fidx + 1]
	fidx = fidx + 2

	-- Threaded call (top-level only)
	if fstride == 1 and p <= 5 and m ~= 1 then
		for k = 0, p-1 do
			work(iRe, iIm, oRe, oIm, oidx + m * k, f + fstride * istride * k, factors, fidx, twRe, twIm, fstride * p, istride, isInverse)
		end
	end

	bfyEnum[p](oRe, oIm, oidx, fstride, twRe, twIm, isInverse, m, p)
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