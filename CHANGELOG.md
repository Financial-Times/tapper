v0.3.0 

* Use [`DeferredConfig`](https://hexdocs.pm/deferred_config/readme.html) for univeral application of `{:system, ENV_VAR}` style indirections in config.
* Add `Tapper.Ctx` contextual API.
* Change `Logger.metadata` key from `tapper_id` to `trace_id` and ensure it is just the hexidecimal encoding of the trace id. Document it.
* Optimisations; see [benchmarking](benchmarking/BENCHMARKS.md).

v0.2.0

Initial public release.

v0.1.1

Initial release.
