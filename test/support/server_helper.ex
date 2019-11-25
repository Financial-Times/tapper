defmodule Test.Helper.Server do
  @moduledoc false

  alias Tapper.Timestamp
  alias Tapper.Tracer.Trace
  alias Tapper.Tracer

  # create some basic Tapper.Tracer.Server configuration
  def config() do
    %{
      host_info: %{
        ip: {2, 1, 1, 2},
        system_id: "default-host"
      },
      server_trace: false
    }
  end

  # create a random endpoint for testing
  def random_endpoint() do
    n = :rand.uniform(254)
    p = :rand.uniform(9999)
    %Tapper.Endpoint{
      ip: if(p < 5000, do: {n, n, n, n + 1}, else: {n, n, n, n, n, n, n, n + 1}),
      port: p,
      service_name: Integer.to_string(n) <> ":" <> Integer.to_string(p)
    }
  end

  # initialise a Tapper.Tracer.Server outside of GenServer, in sample mode, passing `opts`
  def init_with_opts(opts \\ []) do
    config = opts[:config] || config()
    id = %{span_id: span_id} = Tapper.Id.test_id()
    timestamp = Timestamp.instant()

    shared = opts[:shared] || false

    {:ok, trace, _ttl} = Tapper.Tracer.Server.init([config, id, shared, self(), timestamp, opts])
    {trace, span_id}
  end

  @doc """
  returns a function (arity 1) which, when called, sends a message to the original caller, passing the `term()`
  given to the function.

  Use in tests to receive values from (possibly async) functions which take, or are configured with,
  a callback function, e.g. the `Tapper.Tracer.Server` reporter.

  ### Example
  ```
  {ref, fun} = msg_reporter()

  # invoked from another function/process
  spawn(fn -> fun.("hello") end)

  assert_receive {ref, "hello"}
  ```
  """
  @spec msg_reporter() :: {ref :: reference(), (arg :: term() -> {ref :: reference(), arg :: term()}) }
  def msg_reporter() do
    self_pid = self()
    ref = make_ref()
    fun = fn(term) -> send(self_pid, {ref, term}) end
    {ref, fun}
  end

  def trace(spans \\ []) do
    timestamp = Timestamp.instant()

    spans = Enum.into(spans, Map.new, fn(span) -> {span.id, span} end)

    %Trace{
      parent_id: :root,
      trace_id: Tapper.TraceId.generate(),
      span_id: 1,
      timestamp: timestamp,
      end_timestamp: Timestamp.incr(timestamp, 5000),
      spans: spans
    }
  end

  def span(id, start_timestamp, duration_us) do
    %Trace.SpanInfo{
        id: id,
        name: "span_#{id}",
        start_timestamp: start_timestamp,
        end_timestamp: Timestamp.incr(start_timestamp, duration_us),
        annotations: [],
        binary_annotations: [],
        shared: false
      }
  end

  def name_update_message(span_id, timestamp, name) do
    {:update, span_id, timestamp, [Tracer.name_delta(name)]}
  end

  def annotation_update_message(span_id, timestamp, {value, endpoint}) do
    {:update, span_id, timestamp, [Tracer.annotation_delta(value, endpoint)]}
  end

  def annotation_update_message(span_id, timestamp, value) do
    {:update, span_id, timestamp, [value]}
  end

  def binary_annotation_update_message(span_id, timestamp, {type, key, value, endpoint}) do
    {:update, span_id, timestamp, [Tracer.binary_annotation_delta(type, key, value, endpoint)]}
  end

  def span_by_name(spans, name) do
      Enum.find(spans, fn(span) -> span.name === name end)
  end

  def annotation_by_value(%Trace.SpanInfo{annotations: annotations}, value), do: annotation_by_value(annotations, value)
  def annotation_by_value(annotations, value) do
      Enum.find(annotations, fn(%Trace.Annotation{value: an_value}) -> an_value === value end)
  end

  def binary_annotation_by_key(%Trace.SpanInfo{binary_annotations: annotations}, key), do: binary_annotation_by_key(annotations, key)
  def binary_annotation_by_key(annotations, key) when is_list(annotations) do
      Enum.find(annotations, fn(%Trace.BinaryAnnotation{key: an_key}) -> an_key === key end)
  end

end
