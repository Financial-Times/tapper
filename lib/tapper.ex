defmodule Tapper do
  @moduledoc """
  Interface with Tapper.

  ```
  span_id = Tapper.start("name", type: :client) # start new trace and span
  # or join an existing one
  span_id = Trapper.join("name", trace_id, span_id, parent_id, debug: true)

  # then
  span_id
  |> Tapper.tag(:http_path, "/resource/1234")
  |> Tapper.tag(:version, "1.1")

  |> Tapper.binary_annotation(options...)
  
  child_id = Tapper.start_span(span_id) # start child span
  span_id = Tapper.end_span(child_id) # end child span
  
  Tapper.end_trace(span_id) # end trace
  ```
  """
  


  
end
