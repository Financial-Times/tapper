# Run benchmarks with following command:
# MIX_ENV=bench mix bench

# Run fprof with:
# FPROF=inline_hex MIX_ENV=bench mix profile.fprof --callers benchmarking/tapper_hex_bench.exs
#

Logger.configure(level: :error)

inputs = %{
  "0.4.0" => :'0_4_0',
  "base_mod" => :base_mod,
  "inline_hex" => :inline_hex,
  "inline_hex_no_size" => :inline_hex_no_size,
  "inline_hex_bl" => :inline_hex_bl,
  "lookup_table" => :lookup_table
}

generate_trace_id = fn(opts) ->
  Tapper.TraceId.generate(opts)
end

fprof = System.get_env("FPROF")
if fprof do
  # Use this instead of Benchee.run for fprof'ing
  Mix.shell.info("Running hex_bench in fprof mode (10000 runs of generate_trace_id/0)")
  for _n <- 1..100000 do
    generate_trace_id.(String.to_atom(fprof))
  end
else
  Mix.shell.info("Running Benchee for hex_bench")

  Benchee.run %{
    "generate_trace_id" => generate_trace_id,
  }, time: 10, inputs: inputs, parallel: 2
end
