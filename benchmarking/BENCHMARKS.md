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
child span with some annotations                  297.41 K        3.36 μs   ±351.59%        3.00 μs
child span, contextual interface                  291.43 K        3.43 μs   ±398.55%        3.00 μs
child span with some annotations, via update      280.81 K        3.56 μs   ±481.33%        3.00 μs
```

Note that the deviation for unsampled traces is so high because there's really very little to measure, so any jitter makes a big difference.

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
