zfft
----------------------------------------------------------

### Info

zfft started out as a fast (enough) luaJIT-powered rewrite of luafft by @h4rm, which in turn is an implementation of kissfft by @mborgerding; but in the end got a bit more features.

There are two versions of this library:
- A single file version in src/lua, which works with lua version 5.1 (and may work with others, although at least luaJIT is still recommended for performance reasons)
- One in src/love that requires the LÖVE game framework; currently supported LÖVE versions: 11.x

### Usage

`local zfft = require 'zfft'`

src/lua:

```lua

	local sampleRate = 44100
	local frequency = 440
	local size = 2048
	local inRe = {}
	for i=1, size do
		inRe[i] = math.sin(math.pi * 2 * frequency / sampleRate)
		-- window using triangular window function
		inRe[i] = inRe[i] * math.min(1.0, ((i-1)*2)/size) * math.min(1.0, ((size-(i-1))*2)/size)
	end
	local outRe, outIm = zfft.fft(inRe)
	-- From here, sky's the limit...

```

src/love:

*An audio visualization library utilizing this library will be linked here, when it's done...*

### API (src/lua)

#### fastsize = nextFastSize(size)
Returns the next-largest input size that can make use of the defined optimized butterfly functions (for radixes 2,3,4 and 5), in which case the inputs need to be zero-padded to this returned size.

#### outputRe, outputIm = fft(inputRe, inputIm)
Calculates the fft on the given input arrays, the real and imaginary parts passed in separately.
The imaginary input array may be omitted.

#### outputRe, outputIm = ifft(inputRe, inputIm)
Calculates the inverse fft on the given input arrays, the real and imaginary parts passed in separately.
The imaginary input array may be omitted (but usually isn't.)

### API (src/love)

#### fastsize = nextFastSize(size)
Returns the next-largest input size that can make use of the defined optimized butterfly functions (for radixes 2,3,4 and 5), in which case the inputs need to be zero-padded to this returned size.

#### setMaxTwiddleSize(maxsize)
Due to memory considerations, the twiddle arrays are defined outside of any function calls, and are effectively re-used; hence, the maximum size needs to be settable; this needs to be not less than the i/fft's input array(s') size(s).

#### setupThreads(threadCount)
Spawns *threadCount* worker threads that the threaded i/fft methods can utilize.

#### freeThreads()
Gracefully ends all running worker threads. This should be called in the love.quit callback at the very least, if setupThreads has been called.

#### [outputRe, outputIm] = fft(inputRe, inputIm[, outputRe, outputIm])
Calculates the fft on the given input arrays, the real and imaginary parts passed in separately.
The imaginary input array may be omitted.

#### [outputRe, outputIm] = ifft(inputRe, inputIm[, outputRe, outputIm])
Calculates the inverse fft on the given input arrays, the real and imaginary parts passed in separately.
The imaginary input array may be omitted (but usually isn't.)

#### [outputRe, outputIm] = fft_t(inputRe, inputIm[, outputRe, outputIm])
Calculates the fft on the given input arrays, the real and imaginary parts passed in separately.
The imaginary input array may be omitted.
Utilizes worker threads for top-level work function call.

#### [outputRe, outputIm] = ifft_t(inputRe, inputIm[, outputRe, outputIm])
Calculates the inverse fft on the given input arrays, the real and imaginary parts passed in separately.
The imaginary input array may be omitted (but usually isn't.)
Utilizes worker threads for top-level work function call.

#### i/fft/_t Synopsys
All four of the above support multiple input types:
- One input lua table (real only)
- Two input lua tables (real and imaginary)
- One input luaJIT FFI double array (real only)
- Two input luaJIT FFI double arrays (real and imaginary)
- One input LÖVE SoundData (one channel only) (real only)
- Two input LÖVE SoundDatas (both one channel only) (real and imaginary)

In the above 6 cases, the input(s) will be converted to LÖVE ByteData objects.

- One input LÖVE ByteData (sized to input size * size(double)) (real only)
- Two input LÖVE ByteData (both sized to input size * size(double)) (real and imaginary)

In the above 8 cases, the functions will return two LÖVE ByteData objects with the results.

In case of passing in 4 LÖVE ByteData objects (each sized to input size * size(double)), the second pair will be used to put the results into, in which case one may omit using the function's return values.

### Benchmark

Each test was run a hundred times in a loop, timed and then repeated 16 times, on an Intel i7-4820K with no other CPU or Memory hogging applications running.
- The first column shows the simple arithmetic averages of all minus the first and last batches themselves.
- The second column shows the first column's value divided by the iteration count (100).
- The third and fourth columns show the fastest and slowest batch (minus the first and last batches) divided by the iteration count.
- The fifth column shows the average of only the fastest and slowest batches (minus the first and last batches), divided by the iteration count.

The main takeaway should be: The current threading implementation only shows a performance gain at a window size of 16k; for everything else, one should use the non-threaded ByteData, or plaint lua table variant of this library.

#### Window Size: 32 samples
| Tested function           | Est (x100) | Est (x1) | Min (x1) | Max (1x) | Avg (1x) |
|:--------------------------|-----------:|---------:|---------:|---------:|---------:|
zfft-lua-fft				| 0.00152249 s | 15 μs | 13 μs | 20 μs | 17 μs |
zfft-lua-ifft				| 0.00181079 s | 18 μs | 16 μs | 21 μs | 18 μs |
zfft-love-bytedata-fft		| 0.00118083 s | 12 μs | 11 μs | 14 μs | 12 μs |
zfft-love-bytedata-ifft		| 0.00150991 s | 15 μs | 13 μs | 20 μs | 16 μs |
zfft-love-bytedata-fft_t	| 0.19933392 s | 1993 μs | 1993 μs | 1994 μs | 1993 μs |
zfft-love-bytedata-ifft_t	| 0.19932867 s | 1993 μs | 1993 μs | 1994 μs | 1993 μs |
luafft-fft					| 0.00515301 s | 52 μs | 50 μs | 55 μs | 52 μs |
luafft-ifft					| 0.00511313 s | 51 μs | 49 μs | 55 μs | 52 μs |
rosettacode-fft				| 0.00342046 s | 34 μs | 33 μs | 37 μs | 35 μs |

#### Window Size: 64 samples
| Tested function | Est (x100) | Est (x1) | Min (x1) | Max (1x) | Avg (1x) |
|:----------------|-----------:|---------:|---------:|---------:|---------:|
zfft-lua-fft				| 0.00279773 s | 28 μs | 23 μs | 40 μs | 32 μs |
zfft-lua-ifft				| 0.00270522 s | 27 μs | 24 μs | 30 μs | 27 μs |
zfft-love-bytedata-fft		| 0.00241030 s | 24 μs | 20 μs | 32 μs | 26 μs |
zfft-love-bytedata-ifft		| 0.00242591 s | 24 μs | 20 μs | 29 μs | 25 μs |
zfft-love-bytedata-fft_t	| 0.19932947 s | 1993 μs | 1993 μs | 1994 μs | 1993 μs |
zfft-love-bytedata-ifft_t	| 0.19934551 s | 1993 μs | 1993 μs | 1994 μs | 1994 μs |
luafft-fft					| 0.01313687 s | 131 μs | 130 μs | 133 μs | 131 μs |
luafft-ifft					| 0.01317897 s | 132 μs | 129 μs | 140 μs | 134 μs |
rosettacode-fft				| 0.00780273 s | 78 μs | 77 μs | 81 μs | 79 μs |

#### Window Size: 128 samples
| Tested function | Est (x100) | Est (x1) | Min (x1) | Max (1x) | Avg (1x) |
|:----------------|-----------:|---------:|---------:|---------:|---------:|
zfft-lua-fft				| 0.00281625 s | 28 μs | 25 μs | 33 μs | 29 μs |
zfft-lua-ifft				| 0.00381862 s | 38 μs | 33 μs | 42 μs | 37 μs |
zfft-love-bytedata-fft		| 0.00247993 s | 25 μs | 22 μs | 32 μs | 27 μs |
zfft-love-bytedata-ifft		| 0.00346755 s | 35 μs | 30 μs | 44 μs | 37 μs |
zfft-love-bytedata-fft_t	| 0.19934831 s | 1993 μs | 1993 μs | 1994 μs | 1993 μs |
zfft-love-bytedata-ifft_t	| 0.19935725 s | 1994 μs | 1993 μs | 1994 μs | 1994 μs |
luafft-fft					| 0.02613432 s | 261 μs | 254 μs | 302 μs | 278 μs |
luafft-ifft					| 0.02562574 s | 256 μs | 252 μs | 269 μs | 260 μs |
rosettacode-fft				| 0.01733121 s | 173 μs | 168 μs | 183 μs | 175 μs |

#### Window Size: 256 samples
| Tested function | Est (x100) | Est (x1) | Min (x1) | Max (1x) | Avg (1x) |
|:----------------|-----------:|---------:|---------:|---------:|---------:|
zfft-lua-fft				| 0.00751080 s | 75 μs | 70 μs | 89 μs | 79 μs |
zfft-lua-ifft				| 0.00729515 s | 73 μs | 69 μs | 77 μs | 73 μs |
zfft-love-bytedata-fft		| 0.00699211 s | 70 μs | 66 μs | 77 μs | 72 μs |
zfft-love-bytedata-ifft		| 0.00684729 s | 68 μs | 65 μs | 75 μs | 70 μs |
zfft-love-bytedata-fft_t	| 0.19933649 s | 1993 μs | 1993 μs | 1994 μs | 1993 μs |
zfft-love-bytedata-ifft_t	| 0.19934578 s | 1993 μs | 1993 μs | 1994 μs | 1993 μs |
luafft-fft					| 0.06552983 s | 655 μs | 639 μs | 688 μs | 663 μs |
luafft-ifft					| 0.06503439 s | 650 μs | 639 μs | 681 μs | 660 μs |
rosettacode-fft				| 0.03905778 s | 391 μs | 383 μs | 438 μs | 411 μs |

#### Window Size: 512 samples
| Tested function | Est (x100) | Est (x1) | Min (x1) | Max (1x) | Avg (1x) |
|:----------------|-----------:|---------:|---------:|---------:|---------:|
zfft-lua-fft				| 0.00802774 s | 80  μs | 75 μs | 90 μs | 82 μs |
zfft-lua-ifft				| 0.01150948 s | 115 μs | 109 μs | 132 μs | 121 μs |
zfft-love-bytedata-fft		| 0.00740032 s | 74 μs | 69 μs | 83 μs | 76 μs |
zfft-love-bytedata-ifft		| 0.01094602 s | 109 μs | 104 μs | 114 μs | 109 μs |
zfft-love-bytedata-fft_t	| 0.19934983 s | 1993 μs | 1993 μs | 1994 μs | 1993 μs |
zfft-love-bytedata-ifft_t	| 0.19934206 s | 1993 μs | 1992 μs | 1994 μs | 1993 μs |
luafft-fft					| 0.13161773 s | 1316 μs | 1286 μs | 1485 μs | 1385 μs |
luafft-ifft					| 0.12915693 s | 1292 μs | 1266 μs | 1335 μs | 1301 μs |
rosettacode-fft				| 0.08468485 s | 847 μs | 837 μs | 895 μs | 866 μs |

#### Window Size: 1024 samples
| Tested function | Est (x100) | Est (x1) | Min (x1) | Max (1x) | Avg (1x) |
|:----------------|-----------:|---------:|---------:|---------:|---------:|
zfft-lua-fft				| 0.02596435 s | 260 μs | 255 μs | 270 μs | 262 μs |
zfft-lua-ifft				| 0.02605427 s | 261 μs | 255 μs | 303 μs | 279 μs |
zfft-love-bytedata-fft		| 0.02546795 s | 255 μs | 243 μs | 321 μs | 282 μs |
zfft-love-bytedata-ifft		| 0.02514072 s | 251 μs | 246 μs | 270 μs | 258 μs |
zfft-love-bytedata-fft_t	| 0.19939073 s | 1994 μs | 1992 μs | 2003 μs | 1997 μs |
zfft-love-bytedata-ifft_t	| 0.19934711 s | 1993 μs | 1993 μs | 1994 μs | 1993 μs |
luafft-fft					| 0.32124662 s | 3212 μs | 3128 μs | 3756 μs | 3442 μs |
luafft-ifft					| 0.31526702 s | 3153 μs | 3097 μs | 3223 μs | 3160 μs |
rosettacode-fft				| 0.18589121 s | 1859 μs | 1831 μs | 1890 μs | 1860 μs |

#### Window Size: 2048 samples
| Tested function | Est (x100) | Est (x1) | Min (x1) | Max (1x) | Avg (1x) |
|:----------------|-----------:|---------:|---------:|---------:|---------:|
zfft-lua-fft				| 0.03092334 s | 309 μs | 297 μs | 386 μs | 341 μs |
zfft-lua-ifft				| 0.04286491 s | 429 μs | 417 μs | 465 μs | 441 μs |
zfft-love-bytedata-fft		| 0.02747994 s | 275 μs | 272 μs | 282 μs | 277 μs |
zfft-love-bytedata-ifft		| 0.04098504 s | 410 μs | 405 μs | 429 μs | 417 μs |
zfft-love-bytedata-fft_t	| 0.19992530 s | 1999 μs | 1994 μs | 2004 μs | 1999 μs |
zfft-love-bytedata-ifft_t	| 0.19970779 s | 1997 μs | 1993 μs | 2003 μs | 1998 μs |
luafft-fft					| 0.63786710 s | 6379 μs | 6281 μs | 6615 μs | 6448 μs |
luafft-ifft					| 0.63761092 s | 6376 μs | 6282 μs | 6599 μs | 6440 μs |
rosettacode-fft				| 0.40289405 s | 4029 μs | 3984 μs | 4115 μs | 4050 μs |

#### Window Size: 4096 samples
| Tested function | Est (x100) | Est (x1) | Min (x1) | Max (1x) | Avg (1x) |
|:----------------|-----------:|---------:|---------:|---------:|---------:|
zfft-lua-fft				| 0.10092643 s | 1009 μs | 997 μs | 1036 μs | 1016 μs |
zfft-lua-ifft				| 0.10222268 s | 1022 μs | 1008 μs | 1060 μs | 1034 μs |
zfft-love-bytedata-fft		| 0.09885761 s | 989 μs | 974 μs | 1065 μs | 1020 μs |
zfft-love-bytedata-ifft		| 0.09965629 s | 997 μs | 984 μs | 1018 μs | 1001 μs |
zfft-love-bytedata-fft_t	| 0.20046091 s | 2005 μs | 2001 μs | 2022 μs | 2012 μs |
zfft-love-bytedata-ifft_t	| 0.20048160 s | 2005 μs | 2002 μs | 2022 μs | 2012 μs |
luafft-fft					| 1.51842984 s | 15184 μs | 15086 μs | 15326 μs | 15206 μs |
luafft-ifft					| 1.51094393 s | 15109 μs | 14968 μs | 15315 μs | 15141 μs |
rosettacode-fft				| 0.87012736 s | 8701 μs | 8601 μs | 8846 μs | 8723 μs |

#### Window Size: 8192 samples
| Tested function | Est (x100) | Est (x1) | Min (x1) | Max (1x) | Avg (1x) |
|:----------------|-----------:|---------:|---------:|---------:|---------:|
zfft-lua-fft				| 0.12727525 s | 1273 μs | 1240 μs | 1340 μs | 1290 μs |
zfft-lua-ifft				| 0.17290543 s | 1729 μs | 1703 μs | 1759 μs | 1731 μs |
zfft-love-bytedata-fft		| 0.11244001 s | 1124 μs | 1108 μs | 1144 μs | 1126 μs |
zfft-love-bytedata-ifft		| 0.16758230 s | 1676 μs | 1650 μs | 1712 μs | 1681 μs |
zfft-love-bytedata-fft_t	| 0.24687322 s | 2469 μs | 2012 μs | 2783 μs | 2398 μs |
zfft-love-bytedata-ifft_t	| 0.27839641 s | 2784 μs | 2643 μs | 2884 μs | 2763 μs |
luafft-fft					| 3.19842702 s | 31984 μs | 31737 μs | 32355 μs | 32046 μs |
luafft-ifft					| 3.17866089 s | 31787 μs | 31674 μs | 31958 μs | 31816 μs |
rosettacode-fft				| 1.91093338 s | 19109 μs | 18879 μs | 20035 μs | 19457 μs |

#### Window Size: 16384 samples
| Tested function | Est (x100) | Est (x1) | Min (x1) | Max (1x) | Avg (1x) |
|:----------------|-----------:|---------:|---------:|---------:|---------:|
zfft-lua-fft				| 0.41841840 s | 4184 μs | 4148 μs | 4271 μs | 4210 μs |
zfft-lua-ifft				| 0.42249394 s | 4225 μs | 4175 μs | 4302 μs | 4239 μs |
zfft-love-bytedata-fft		| 0.40930783 s | 4093 μs | 4045 μs | 4172 μs | 4108 μs |
zfft-love-bytedata-ifft		| 0.41501798 s | 4150 μs | 4103 μs | 4237 μs | 4170 μs |
zfft-love-bytedata-fft_t	| 0.32887911 s | 3289 μs | 3178 μs | 3404 μs | 3291 μs |
zfft-love-bytedata-ifft_t	| 0.32781197 s | 3278 μs | 3173 μs | 3384 μs | 3278 μs |
luafft-fft					| 8.42733335 s | 84273 μs | 83973 μs | 84865 μs | 84419 μs |
luafft-ifft					| 8.48615768 s | 84862 μs | 83512 μs | 88316 μs | 85914 μs |
rosettacode-fft				| 4.32942277 s | 43294 μs | 42838 μs | 43948 μs | 43393 μs |

### Version History

#### V1.0

	- First release.

#### TODO:

	- Fix butterfly functions of radix 5 and the generic one, current implementations show ringing with pure tones.
	  (This isn't an issue if one sticks to power of two input sizes.)

### License
This library licensed under the ISC License.
