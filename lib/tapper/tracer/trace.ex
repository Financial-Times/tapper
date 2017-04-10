defmodule Tapper.Tracer.Trace do
    
    @doc "Tracer state: the state of a single trace session."
    defstruct [
        :config,        # configuration from supervisor
        :trace_id,      # root trace_id
        :span_id,       # root span id
        :parent_id,     # parent of trace, or nil if new root trace
        :sample,        # we are sampling this trace
        :debug,         # we are debugging this trace
        :spans,         # map of spans in this trace
        :timestamp,     # start of trace
        :end_timestamp, # end of trace
        :last_activity  # last time a span was started or ended
    ]

    @type trace :: %__MODULE__{}

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
    end

    defmodule Annotation do
        defstruct [
            :timestamp,
            :value,
            :host
        ]
    end

    defmodule Endpoint do
        defstruct [
            :ipv4,
            :port,
            :service_name,
            :ipv6
        ]
    end

    defmodule BinaryAnnotation do
        defstruct [
            :key,
            :value,
            :annotation_type,
            :host
        ]
    end

    @spec to_protocol_spans(%Tapper.Tracer.Trace{}) :: [%Tapper.Protocol.Span{}]
    def to_protocol_spans(%__MODULE__{trace_id: trace_id, debug: debug, spans: spans, end_timestamp: end_timestamp}) do
        
        {hi, lo, _} = trace_id

        spans
        |> Map.values
        |> Enum.map(fn(span) ->

            duration = cond do
                is_nil(span.end_timestamp) -> end_timestamp - span.start_timestamp
                true -> span.end_timestamp - span.start_timestamp
            end

            %Tapper.Protocol.Span{
                trace_id: lo,
                name: span.name,
                id: span.id,
                parent_id: span.parent_id,
                trace_id_high: hi,
                debug: debug,
                timestamp: span.start_timestamp,
                duration: max(duration, 1),
                annotations: to_protocol_annotations(span.annotations),
                binary_annotations: to_protocol_binary_annotations(span.binary_annotations)
            }
        end)
    end

    def to_protocol_annotations(annotations) when is_list(annotations) do
        Enum.map(annotations, &to_protocol_annotation/1)
    end

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
        {a,b,c,d} = host.ipv4
        
        %Tapper.Protocol.Endpoint{
            ipv4: <<a,b,c,d>>,
            port: host.port,
            service_name: host.service_name
        }
    end
end