v0.4.1
* Fix deprecation warnings from System.convert_time_unit/3 (thanks to @indrekj)
* Lock max `poison` version to 4.0.0 since its API was changed in 4.0.1 removing `Poison.encode_to_iodata/2` (https://github.com/devinus/poison/commit/a4208a6252f4e58fbcc8d9fd2f4f64c99e974cc8#r26410188)

v0.4.0
* **Requires Elixir 1.6+**
* `Tapper.Reporter.AsyncReporter` (thanks to @indrekj)
* Tapper will now start reporters under its supervision tree if given as `{module, args}` supervisor-style tuple.
* Enforces that reporters are a module implementing `Tapper.Api.Reporter`, or a function with arity-1.

v0.3.6
* Allow 1.x versions of HTTPoison.

v0.3.5
* DEFECT: shared span flag should only be true for joined traces, not all `:server` traces.

v0.3.4
* Add `Tapper.Reporter.Null` (HT @TKasekamp)
* Doc fixes.
* Update deps.

v0.3.3
* DEFECT: "unknown" being recorded as service name.
* DEFECT: remove `trace_id` from Logger context (HT @TKasekamp)
* suppress all server logging unless `server_trace` is set to a log level (HT @TKasekamp)

v0.3.2
* `Tapper.error_message/1` (and `TapperCtx.error_message`) should take any term (and convert to a string) for convenience.
* update `dialyxir`.

v0.3.1
* DEFECT: joined traces (shared spans) should not set duration on root span.
* use custom `Logger.metadata/1` implementation for small perf gain.
* parse child span name from opts in server rather than client, for tiny perf gain.
* tiny refactoring things.

v0.3.0

* Use [`DeferredConfig`](https://hexdocs.pm/deferred_config/readme.html) for univeral application of `{:system, ENV_VAR}` style indirections in config.
* Add `Tapper.Ctx` contextual API.
* Change `Logger.metadata` key from `tapper_id` to `trace_id` and ensure it is just the hexidecimal encoding of the trace id. Document it.
* Optimisations; see [benchmarking](benchmarking/BENCHMARKS.md).

v0.2.0

Initial public release.

v0.1.1

Initial release.
