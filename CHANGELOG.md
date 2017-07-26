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
