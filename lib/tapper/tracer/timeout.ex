defmodule Tapper.Tracer.Timeout do
  @moduledoc """
  Clean up a trace after a time-out.

  ## Synchronous Traces
  If a trace which has not been marked as `async` times out, this is an error.

  The main span of trace will be marked with a `:timeout` annotation,
  as will any spans which have not been finished (`end_timestamp` set).

  The `end_timestamp` of all unfinished spans, and the main span (which is
  never finished until `Tapper.finish/2` is called) will gain the timestamp
  of the point where the timeout occurred.

  ### Asynchronous Traces
  If a trace which has been marked as `async` times out, this is normal, so
  long as all spans within the trace (except the main span), have been
  finished.

  If all spans are finished, the `end_timestamp` of the main span will be
  set to the lastest `end_timestamp` of all its child spans.

  If some spans are unfinished, behaviour is the same as for the non-async case.

  If an async trace has no child spans, we'll pick up the trace's `last_activity` time,
  which may, or may not, be accurate. It's kind of an edge case that the main span is
  async without any child spans, if intended, then `last_activity` is probably going
  to be pretty good, since it will the the time of the last annotation, e.g. an `ss`,
  or failing that, when `finish` was called.
  """


  alias Tapper.Tracer.Trace
  alias Tapper.Tracer.Annotations

  @doc "apply timeout logic"
  @spec timeout_trace(trace :: Trace.t, timestamp :: integer()) :: Trace.t
  def timeout_trace(trace, timestamp)

  def timeout_trace(trace = %Trace{async: nil}, timestamp) do
    # a timeout on an non-async trace is an error; add timeout annotation to all spans
    %Trace{trace |
      spans: annotate_timeout_spans(trace.spans, timestamp, Trace.endpoint_from_config(trace.config)),
      end_timestamp: timestamp
    }
  end

  def timeout_trace(trace = %Trace{async: true, span_id: main_span_id}, timestamp) do
    # if all spans are finished, set the main span's timestamp to the latest finishing span's timestamp
    # otherwise the main span, and unfinished spans will be marked with a `:timeout` annotaton

    child_spans = child_spans(trace)

    case child_spans do
      [] ->
        # main span only, not an error; just set the `end_timestamp` to the last activity time
        trace = put_in(trace.spans[main_span_id].end_timestamp, trace.last_activity)
        %Trace{trace | end_timestamp: trace.last_activity}

      child_spans ->
        # one or more child spans exist; are they all finished?
        case all_finished?(child_spans) do
          true ->
            # all child spans finished async before the timeout, update main span
            # with most latent child end_timestamp
            end_timestamp = latest_timeout(child_spans) || timestamp
            trace = put_in(trace.spans[main_span_id].end_timestamp, end_timestamp)
            %Trace{trace | end_timestamp: end_timestamp}

          false ->
            # no; this is a timeout error: annotate all unfinished spans with a `:timeout`
            # and set their `end_timestamp`, and the trace's `end_timeout` to timeout time
            %Trace{trace |
              spans: annotate_timeout_spans(trace.spans, timestamp, Trace.endpoint_from_config(trace.config)),
              end_timestamp: timestamp
            }
        end
    end
  end

  @doc "return an Enumerable of child spans, i.e. spans minus the main span"
  @spec child_spans(Trace.t) :: Enumerable.t | []
  def child_spans(%Trace{spans: spans}) when map_size(spans) === 1, do: []
  def child_spans(%Trace{span_id: main_span_id, spans: spans}) do
    spans
    |> Stream.filter(fn
        {^main_span_id, _span} -> false # reject main span
        _ -> true
      end)
    |> Stream.map(fn({_,span}) -> span end) # flatten to stream of spans
  end

  @doc "Calculates the latest finished span time; `false` if there are no finished spans."
  @spec latest_timeout(spans :: Enumerable.t) :: integer() | false
  def latest_timeout(spans) do
    max =
      spans
      |> Stream.filter(&span_finished?/1) # reject unfinished spans
      |> Enum.max_by(fn(span) -> span.end_timestamp end, fn -> false end)

    case max do
      false -> false
      span -> span.end_timestamp
    end
  end

  @doc "Have all spans finished? expects an Enumerable of `%Trace.SpanInfo{}`; returns true for empty Enumerable."
  @spec all_finished?(spans :: Enumerable.t) :: boolean()
  def all_finished?(spans) do
    Enum.all?(spans, fn (span) -> span_finished?(span) end)
  end

  @doc false
  def span_finished?(%Trace.SpanInfo{end_timestamp: nil}), do: false
  def span_finished?(%Trace.SpanInfo{}), do: true

  @doc false
  @spec annotate_timeout_spans(spans :: %{required(Span.Id.t) => Trace.SpanInfo.t}, integer(), Tapper.Endpoint.t) :: %{required(Span.Id.t) => Trace.SpanInfo.t}
  def annotate_timeout_spans(spans, timestamp, endpoint) when is_map(spans) do
    spans
    |> Stream.map(fn({span_id,span}) ->
      span = case span.end_timestamp do
        nil ->  %Trace.SpanInfo{
          span |
          annotations: [timeout_annotation(timestamp, endpoint) | span.annotations],
          end_timestamp: timestamp
        }
        _timestamp -> span
      end
      {span_id, span}
    end)
    |> Enum.into(Map.new)
  end

  @doc false
  def timeout_annotation(timestamp, endpoint) do
    Annotations.annotation(:timeout, timestamp, endpoint)
  end

end