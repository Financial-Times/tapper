# Run benchmarks with following command:
# MIX_ENV=bench mix bench

# Run fprof with:
# FPROF=1 MIX_ENV=bench mix profile.fprof --callers benchmarking/tapper_bench.exs
#

Logger.configure(level: :error)

inputs = %{sampled: [sample: true], unsampled: [sample: false]}

start_finish = fn(opts) ->
  id = Tapper.start(opts)
  Tapper.finish(id)
end

child_span = fn(opts) ->
  id = Tapper.start(opts)

  id = Tapper.start_span(id, name: "span-1")
  id = Tapper.finish_span(id)

  Tapper.finish(id)
end

child_span_with_destructuring = fn(opts) ->
  id = Tapper.start(opts)

  id = Tapper.start_span(id, name: "span-1")
  Tapper.Id.destructure(id)
  id = Tapper.finish_span(id)

  Tapper.finish(id)
end

child_span_ctx = fn(opts) ->
  Tapper.Ctx.start(opts)

  Tapper.Ctx.start_span(name: "span-1")
  Tapper.Ctx.finish_span()

  Tapper.Ctx.finish()
end

child_span_with_annotations = fn(opts) ->
  id = Tapper.start(opts)

  id = Tapper.start_span(id, name: "span-1", annotations: [
    Tapper.client_send(),
    Tapper.server_address(%Tapper.Endpoint{service_name: "remote"})
  ])
  id = Tapper.finish_span(id, annotations: Tapper.client_receive())

  Tapper.finish(id)
end

child_span_with_annotations_via_update = fn(opts) ->
  id = Tapper.start(opts)

  id = Tapper.start_span(id, name: "span-1")

  Tapper.update_span(id, [
    Tapper.client_send(),
    Tapper.server_address(%Tapper.Endpoint{service_name: "remote"})
  ])
  Tapper.update_span(id, Tapper.client_receive())

  id = Tapper.finish_span(id)

  Tapper.finish(id)
end

raw_trace_id = "ba50b795b208fffbb3724d69ddc34e56"
raw_span_id = "b4f20245e9a2a297"

decode_trace_headers = fn(_opts) ->
  {:ok, _} = Tapper.TraceId.parse(raw_trace_id)
  {:ok, _} = Tapper.SpanId.parse(raw_span_id)
end

if System.get_env("FPROF") do
  # Use this instead of Benchee.run for fprof'ing
  Mix.shell.info("Running in fprof mode (10000 runs of start_finish/0)")
  for _ <- 1..10000 do
    start_finish.([sample: true])
  end
else
  Mix.shell.info("Running Benchee")

  Benchee.run %{
    "start, finish" => start_finish,
    "child span" => child_span,
    "child span, contextual interface" => child_span_ctx,
    "child span, with destructuring" => child_span_with_destructuring,
    "child span with some annotations" => child_span_with_annotations,
    "child span with some annotations, via update" => child_span_with_annotations_via_update,
    "decode_trace_headers" => decode_trace_headers,
  }, time: 5, inputs: inputs
end
