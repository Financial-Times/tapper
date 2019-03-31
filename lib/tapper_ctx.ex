defmodule Tapper.Ctx do
  @moduledoc """
  Contextual interface to Tapper.

  This interface uses the process dictionary to store and provide the `Tapper.Id` to
  API functions, removing this burden from your code, with the caveat of making things
  slightly 'magic'.

  It provides all the annotation helper functions of the non-contextual `Tapper` API,
  (in fact you can still use the helper functions from the `Tapper` module, rather than
  prefixing them all with `Tapper.Ctx`).

  You can still any API functions that need a `Tapper.Id` via the
  `Tapper.Ctx.context/0` and  `Tapper.Ctx.put_context/1` functions, indeed
  this is how to pass the `Tapper.Id` through to child processes etc. Beware
  however that functions outside of this module will not automatically update
  the contextual `Tapper.Id` for you. Contextual API functions return the
  `Tapper.Id` in the same way as the non-contextual API, should you need it.

  ## Child Processes

  Use `Tapper.Ctx.context/0` and `Tapper.Ctx.put_context/1` to surface and
  submerge the id:

  ```
  # surface from parent process
  tapper_id = Tapper.Ctx.context()

  pid = spawn(fn ->
    # contextualize in child process
    Tapper.Ctx.put_context(tapper_id)

    # now use Tapper.Ctx functions as normal.
    Tapper.Ctx.start_span(name: "child")
    ...
    Tapper.Ctx.finish_span()
  end)
  ```

  ## Debugging

  Set the `:tapper` config var `:debug_context` to debug missing contextual ids:

  ```
  config :tapper,
    debug_context: true
  ```

  See also `Tapper.Ctx.context/0`.
  """

  require Logger

  alias Tapper.Tracer
  alias Tapper.Tracer.Api

  @doc """
  Starts a new root trace, e.g. on originating a request.

  A new `Tapper.Id` is returned, and stored in the process context,
  see `Tapper.Ctx.put_context/1`.

  ```
  id = Tapper.Ctx.start(name: "request resource", type: :client, remote: remote_endpoint)
  ^id = Tapper.Ctx.context()
  ```

  See `Tapper.Tracer.start/1` for options.
  """
  @spec start(opts :: Keyword.t) :: Tapper.Id.t
  def start(opts \\ []) do
    id = Tracer.start(opts)
    put_context(id)
  end

  @doc """
  Joins an existing trace, e.g. server recieving an annotated request.

  A `Tapper.Id` is returned, and stored it in the process context.

  ```
  id = Tapper.Ctx.join(trace_id, span_id, parent_id, sample, debug, name: "receive request")
  ^id = Tapper.Ctx.context()
  ```

  See `Tapper.Tracer.join/6` for options.
  """
  @spec join(trace_id :: Tapper.TraceId.t,
    span_id :: Tapper.SpanId.t,
    parent_id :: Tapper.SpanId.t | :root,
    sample :: boolean(), debug :: boolean(),
    opts :: Keyword.t) :: Tapper.Id.t
  def join(trace_id, span_id, parent_id, sample, debug, opts \\ []) do
    id = Tracer.join(trace_id, span_id, parent_id, sample, debug, opts)
    put_context(id)
  end

  @doc """
  Finishes the trace, for the current contextual `Tapper.Id`, removing
  the id from the process context.

  See `Tapper.Tracer.finish/2` for options.
  """
  @spec finish(opts :: Keyword.t) :: :ok
  def finish(opts \\ []) do
    id = delete_context()
    Tracer.finish(id, opts)
  end

  @doc """
  Starts a child span of the current span of the current contextual `Tapper.Id`,
  returning an updated `Tapper.Id`, and updating the id in the context.

  See `Tapper.Tracer.start_span/2` for options.
  """
  @spec start_span(opts :: Keyword.t) :: Tapper.Id.t
  def start_span(opts \\ []), do: put_context(Tracer.start_span(context(), opts))

  @doc """
  Finish a nested span of the current contextual `Tapper.Id`, returning an updated
  `Tapper.Id`, and updating the id in the context.

  See `Tapper.Tracer.finish_span/2` for options.
  """
  @spec finish_span(opts :: Keyword.t) :: Tapper.Id.t
  def finish_span(opts \\ []), do: put_context(Tracer.finish_span(context(), opts))

  @doc """
  Add annotations to the current contextual span, returning the same `Tapper.Id`.

  See `Tapper.Tracer.update_span/3` for details.
  """
  @spec update_span(deltas :: Api.delta | [Api.delta], opts :: Keyword.t) :: Tapper.Id.t
  def update_span(deltas, opts \\ []), do: Tracer.update_span(context(), deltas, opts)

  @doc """
  Get the in-context `Tapper.Id` of this process.

  If the context does not exist, and `:tapper` configuration option
  `:debug_context` is is `:warn` will log a warning with stack-trace,
  if otherwise truthy, will raise a `RuntimeError`,
  else will just return `:ignore`.
  """
  @spec context() :: Tapper.Id.t | no_return
  def context do
    case Process.get(__MODULE__) do
      nil -> debug_context()
      id = %Tapper.Id{} -> id
      :ignore -> :ignore
    end
  end

  @doc "Set the in-context `Tapper.Id` of this process."
  @spec put_context(id :: Tapper.Id.t) :: Tapper.Id.t
  def put_context(id)

  def put_context(id = %Tapper.Id{}) do
    # NB we return the id, rather than any existing one
    Process.put(__MODULE__, id)
    id
  end

  def put_context(id = :ignore) do
    Process.put(__MODULE__, id)
    id
  end

  @doc false
  def debug_context() do
    msg = "Reference to missing contextual Tapper.Id"
    case Application.get_env(:tapper, :debug_context, false) do
      :warn ->
        try do
          raise RuntimeError, msg
        rescue
          x ->
            Logger.warn(fn -> Exception.format(:error, x) end)
            :ignore
        end
      nil ->
        :ignore
      false ->
        :ignore
      _ ->
        raise msg
    end
  end

  @doc "determine if there is a `Tapper.Id` in context"
  def context?() do
    !!Process.get(__MODULE__, false)
  end

  @doc "delete the in-context `Tapper.Id`"
  def delete_context do
    Process.delete(__MODULE__)
  end

  use Tapper.AnnotationHelpers
end
