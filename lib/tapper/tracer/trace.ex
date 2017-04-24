defmodule Tapper.Tracer.Trace do
    
    @doc "Tracer state: the state of a single trace session."
    defstruct [
        :config,        # configuration from supervisor
        :trace_id,      # root trace_id
        :span_id,       # root span id
        :parent_id,     # parent of trace, or :root if new root trace
        :sample,        # we are sampling this trace
        :debug,         # we are debugging this trace

        :spans,         # map of spans in this trace
        :timestamp,     # start of trace
        :end_timestamp, # end of trace
        :last_activity  # last time a span was started or ended
    ]

    @type trace :: %__MODULE__{trace_id: Tapper.TraceId.t, span_id: Tapper.SpanId.t, parent_id: Tapper.SpanId.t | nil, spans: [Tapper.Traceer.SpanInfo.t]}

    defmodule SpanInfo do
        defstruct [
            :name,
            :id,
            :parent_id,
            :start_timestamp,
            :end_timestamp,
            :annotations,
            :binary_annotations
        ]
        
        @type t :: %__MODULE__{}
    end

    defmodule Endpoint do
        defstruct [
            :ipv4,
            :port,
            :service_name,
            :ipv6
        ]

        @type t :: %__MODULE__{}
    end

    defmodule Annotation do
        defstruct [
            :timestamp,
            :value,
            :host
        ]

        @type t :: %__MODULE__{}

        def new(value, timestamp, endpoint = %Tapper.Tracer.Trace.Endpoint{}) do
            %__MODULE__{
                value: value,
                timestamp: timestamp,
                host: endpoint
            }
        end

        def new(value, timestamp) do
            %__MODULE__{
                value: value,
                timestamp: timestamp
            }
        end
    end

    defmodule BinaryAnnotation do
        defstruct [
            :key,
            :value,
            :annotation_type,
            :host
        ]

        @type t :: %__MODULE__{}
    end

    @spec to_protocol_spans(%Tapper.Tracer.Trace{}) :: [%Tapper.Protocol.Span{}]
    def to_protocol_spans(%__MODULE__{trace_id: trace_id, debug: debug, spans: spans, end_timestamp: end_timestamp}) do
        
        {trace_id, _} = trace_id

        spans
        |> Map.values
        |> Enum.map(fn(span) ->

            duration = cond do
                is_nil(span.end_timestamp) -> end_timestamp - span.start_timestamp
                true -> span.end_timestamp - span.start_timestamp
            end

            %Tapper.Protocol.Span{
                trace_id: trace_id,
                name: span.name,
                id: span.id,
                parent_id: span.parent_id,
                debug: debug,
                timestamp: span.start_timestamp,
                duration: max(duration, 1),
                annotations: to_protocol_annotations(span.annotations),
                binary_annotations: to_protocol_binary_annotations(span.binary_annotations)
            }
        end)
    end

    def to_protocol_annotations(annotations) when is_nil(annotations), do: []
    def to_protocol_annotations(annotations) when is_list(annotations) do
        Enum.map(annotations, &to_protocol_annotation/1)
    end

    def to_protocol_binary_annotations(binary_annotations) when is_nil(binary_annotations), do: []
    def to_protocol_binary_annotations(binary_annotations) when is_list(binary_annotations) do
        Enum.map(binary_annotations, &to_protocol_binary_annotation/1)
    end

    def to_protocol_annotation(annotation = %__MODULE__.Annotation{}) do
        %Tapper.Protocol.Annotation{
            timestamp: annotation.timestamp,
            value: annotation.value,
            host: to_protocol_endpoint(annotation.host)
        }
    end

    def to_protocol_binary_annotation(annotation = %__MODULE__.BinaryAnnotation{}) do
        %Tapper.Protocol.BinaryAnnotation{
            key: annotation.key,
            value: annotation.value,
            annotation_type: annotation.annotation_type,
            host: to_protocol_endpoint(annotation.host)
        }
    end

    def to_protocol_endpoint(nil), do: nil
    def to_protocol_endpoint(host = %__MODULE__.Endpoint{}) do
      
        %Tapper.Protocol.Endpoint{
            ipv4: host.ipv4,
            port: host.port,
            service_name: host.service_name
        }
    end
end