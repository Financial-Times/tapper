# Benchmarks

I've performed a little bit of optimisation from 0.2 -> 0.3, since I'd never had time to see how fast Tapper was, or could be; 
it's just spawning and message passing, and both are fast in Erlang, right?

The design of Tapper assumed this would be fast, and tried to avoid doing much processing on the client-side of the API, with the exception of a bit of parameter checking, and uses only `GenServer.cast/2` rather than `GenServer.call/3`, but what did we achieve?

## Findings

The 0.2.x release, on my 3.10 GHz i7 Mac Book Pro could do ~18k `start`/`finish` *sampled* trace operations per second, adding about 52.00 μs of additional overhead to your code, a little more with annotations, and less if you `join`, rather than `start` traces, since you don't need to generate the `Trace.Id`. Note that the same pair of operations for an *unsampled* trace take about 3 μs (~300k/s). I also noticed that `update_span/3` wasn't
short-circuiting unsampled traces, since it was less than half the speed of the other procs when running unsampled!

The additional overhead over the >200k raw spawn/sends per second you can do on my hardware comes from various places, some in `GenServer` and OTP, which you can't avoid except by removing the advantage of using OTP, and the rest in function calls in Tapper code. You can't avoid generating the `Tapper.Id` on `start/1`, you can't avoid generating a decent monotonic time-stamp, and you can't avoid adding the `Logger` metadata for the trace id (assuming you want it), leaving just parameter checking and other misc code to improve.

From this baseline, I've tried a few things:

   * Remove debug logging during Tracer start-up, although this can be removed during code generation, it was superfluous anyway.
   * Remove use of `Access` module via `[]`, preferring direct use of `Keyword.get/3`.
   * Remove multiple traversals of Keyword lists in favour of a tailored function.

Rewriting to avoid multiple traversals made more difference than just avoiding indirection, as there were several instances of `Keyword.get/3`, and two function calls, which is now one function call, one traversal, which does some list appending, and a bunch of pattern matches. The gain is fairly small, but it also happens to consolidate the options processing code in a pleasing way.

0.3.0 achieves ~20k `start`/`finish` *sampled* trace operations per second on my hardware, adding about 49 μs per pair of operations. More could be achieved by moving all the option checking/defaulting to the server code, at the expense of error locality; using macros for annotations; and some API changes, such as not using a keyword list in `start/1` for the sample and debug flags, which we need to know client-side for sample/no-sample optimisation (because it enables unsampled traces, which is a much more significant boost). Alternatively, the whole thing could be re-coded outside of OTP/GenServer. Do submit your PR ! :)

### Results for Tapper 0.3.0

```
Operating System: macOS
CPU Information: Intel(R) Core(TM) i7-5557U CPU @ 3.10GHz
Number of Available Cores: 4
Available memory: 17.179869184 GB
Elixir 1.4.4
Erlang 19.3

##### With input sampled #####
Name                                                   ips        average  deviation         median
start, finish                                      20.69 K       48.34 μs    ±13.96%       47.00 μs
child span                                         15.54 K       64.36 μs    ±18.68%       64.00 μs
child span, contextual interface                   15.43 K       64.83 μs    ±18.38%       66.00 μs
child span with some annotations                   15.42 K       64.84 μs    ±26.10%       71.00 μs
child span with some annotations, via update       13.88 K       72.07 μs    ±27.96%       77.00 μs

##### With input unsampled #####
Name                                                   ips        average  deviation         median
child span                                        311.53 K        3.21 μs   ±446.82%        3.00 μs
start, finish                                     306.84 K        3.26 μs   ±459.05%        3.00 μs
child span, contextual interface                  291.43 K        3.43 μs   ±398.55%        3.00 μs
child span with some annotations                  297.41 K        3.36 μs   ±351.59%        3.00 μs
child span with some annotations, via update      280.81 K        3.56 μs   ±481.33%        3.00 μs
```

Note that the deviation for unsampled traces is so high because there's really very little to measure, so any jitter makes a big difference.

### Results for Tapper 0.5.0
```
March 2019
Tapper 0.5.0
commit: 46d0ebafc64e4cbd5be01ad457405889b885311e
```

The previous benchmark suite didn't include a representation of encoding the trace
to HTTP headers, which is a typical activity of clients, and one that might be
optimised, as its currently doing a number to hex conversion every time.

For this reason the benchmarks now include a `child span, with destructuring`
benchmark, which uses a `Tapper.Id.destructure/1` call within a child span; 
you can see how this negatively effects the IPS.

We also now benchmark unsampled spans, which is critical to median performance 
when using sampling, since it turns off much of the functionality.

Finally, there's now a benchmark for decoding trace headers, which is 
implemented in `tapper_plug`, but most of the hard work is performed by 
`Tapper.TraceId.parse/1` and `Tapper.SpanId.parse/1`, so we combine those
to parallel the work done.

With these extra benchmarks, we have some more realistic outcomes, and
some more targets to optimisation.

> The benchmarking software, Erlang and Elixir have changed too, and we now
have (possibly ineffective) OS patches for [Meltdown and Spectre](https://meltdownattack.com/) 
which slow nearly everything down.

```
Operating System: macOS
CPU Information: Intel(R) Core(TM) i7-2635QM CPU @ 2.00GHz
Number of Available Cores: 8
Available memory: 16 GB
Elixir 1.8.1
Erlang 21.2.4

##### With input sampled #####
Name                                                   ips        average  deviation         median         99th %
decode_trace_headers                              323.43 K        3.09 μs   ±957.70%        2.97 μs        6.97 μs
start, finish                                      16.39 K       61.00 μs    ±31.11%       54.97 μs      131.97 μs
child span                                         14.31 K       69.89 μs    ±32.82%       59.97 μs      147.97 μs
child span, contextual interface                   13.58 K       73.62 μs    ±34.93%       62.97 μs      159.97 μs
child span with some annotations                   16.38 K       61.04 μs    ±31.78%       55.97 μs      148.97 μs
child span with some annotations, via update       15.00 K       66.69 μs    ±30.78%       60.97 μs      150.90 μs
child span, with destructuring                     10.17 K       98.36 μs    ±30.09%       84.97 μs      199.97 μs

##### With input unsampled #####
Name                                                   ips        average  deviation         median         99th %
decode_trace_headers                              322.25 K        3.10 μs   ±857.30%        2.97 μs        6.97 μs
start, finish                                     211.33 K        4.73 μs   ±413.71%        3.97 μs        9.97 μs
child span                                        208.11 K        4.81 μs   ±465.87%        3.97 μs       10.97 μs
child span, contextual interface                  173.16 K        5.78 μs   ±219.45%        4.97 μs       12.97 μs
child span with some annotations                  176.54 K        5.66 μs   ±257.49%        4.97 μs       11.97 μs
child span with some annotations, via update      187.28 K        5.34 μs   ±374.50%        4.97 μs       11.97 μs
child span, with destructuring                     53.68 K       18.63 μs    ±34.07%       17.97 μs       33.97 μs
```

### Results for Tapper 0.6.0

Late March 2019
commit: 8e28e74710faa0730f8c8fb57993a5d8ccb7ffe2

Tapper now keeps the trace ids as binaries, rather than integers. This means that any decoding or 
encoding of trace headers doesn't need to convert an integer to/from hex format every time, which 
should reduce real-world overhead. Significant effort has been put in to optimising the generation 
and parsing of the ids, applying many of the binary pattern-matching tricks from the core Elixir
`Base.encode16/2` and `Integer.parse/1` functions, but optimised further for this specific use-case. 
Yes, I've looked at the BEAM code, and it was good. ☺️

> Note that if you were relying on directly interpreting the previous `Tapper.TraceId` or `Tapper.SpanId` 
internal representations outside of the official Tapper API functions, your code may break!

The benchmark below shows the significant improvement in decoding trace headers and destructuring the
`Tapper.Id` over the previous version, while other benchmarks remain stable.

```
Operating System: macOS
CPU Information: Intel(R) Core(TM) i7-2635QM CPU @ 2.00GHz
Number of Available Cores: 8
Available memory: 16 GB
Elixir 1.8.1
Erlang 21.2.4

##### With input sampled #####
Name                                                   ips        average  deviation         median         99th %
decode_trace_headers                              529.22 K        1.89 μs  ±1439.96%        1.97 μs        3.97 μs
start, finish                                      16.02 K       62.43 μs    ±32.56%       55.97 μs      135.97 μs
child span                                         13.81 K       72.40 μs    ±31.97%       62.97 μs      149.97 μs
child span, contextual interface                   13.37 K       74.82 μs    ±31.96%       64.97 μs      156.97 μs
child span with some annotations                   15.69 K       63.72 μs    ±34.56%       57.97 μs      160.97 μs
child span with some annotations, via update       15.22 K       65.69 μs    ±29.15%       59.97 μs      144.97 μs
child span, with destructuring                     13.64 K       73.31 μs    ±30.72%       63.97 μs      148.97 μs

##### With input unsampled #####
Name                                                   ips        average  deviation         median         99th %
decode_trace_headers                              533.58 K        1.87 μs  ±1500.12%        1.97 μs        3.97 μs
start, finish                                     211.20 K        4.73 μs   ±400.76%        3.97 μs       10.97 μs
child span                                        203.86 K        4.91 μs   ±410.36%        3.97 μs       10.97 μs
child span, contextual interface                  181.08 K        5.52 μs   ±158.93%        4.97 μs       12.97 μs
child span with some annotations                  163.21 K        6.13 μs   ±212.32%        4.97 μs       12.97 μs
child span with some annotations, via update      176.83 K        5.66 μs   ±307.06%        4.97 μs       12.97 μs
child span, with destructuring                    193.98 K        5.16 μs   ±362.21%        4.97 μs       11.97 μs
```

## Some Performance Tips

To get the last drop out of the current implementation:

* Ensure that you are not over-sampling: using `debug` or a high sampling rate will add to the median processing time; unsampled traces have extremely low overhead.
* Send annotations bundled with `start/1` or `start_span/2` if you can, rather than adding with `update_span/2` to avoid the overhead of extra calls; at least batch up annotations in `update_span/1` rather than calling it multiple times.
* Use literals for annotations, rather than the helper functions, e.g. `:cr` rather than `Tapper.client_receive()` to avoid the function call overhead.
* The contextual API (`Tapper.Ctx`) is a little bit slower, due to the additional process dictionary look-up/store for each operation.

## Running Benchmarks

Run benchmarks with following command:

```
MIX_ENV=bench mix bench
```

The `config/bench.exs` config just sets the logging level to `:error`.

## Running the profiler

To locate optimisation opportunities, I used `fprof`, outside of Benchee, calling the
test function in loop over a range.

Run fprof with:

```
FPROF=1 MIX_ENV=bench mix profile.fprof --callers benchmarking/tapper_bench.exs
```
