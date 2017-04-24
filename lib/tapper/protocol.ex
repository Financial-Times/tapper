defmodule Tapper.Protocol.Span do
    defstruct [
        :trace_id,
        :name,
        :id,
        :parent_id,
        :annotations,
        :binary_annotations,
        :debug,
        :timestamp,
        :duration
    ]
end

defmodule Tapper.Protocol.Annotation do
    defstruct [
        :timestamp,
        :value,
        :host
    ]
end

defmodule Tapper.Protocol.Endpoint do
    defstruct [
        :ipv4,
        :port,
        :service_name,
        :ipv6
    ]
end

defmodule Tapper.Protocol.BinaryAnnotation do
    defstruct [
        :key,
        :value,
        :annotation_type,
        :host
    ]
end
