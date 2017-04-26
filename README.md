# Tapper - Experimental Zipkin client for Elixir.

Implements an interface for recording traces and sending them to a [Zipkin](http://zipkin.io/) server.

## Synopsis

### A Client
A client making a request:

```elixir
# start a new trace, and root span;
# creates a 'client send' annotation on root span (defaults to type: :client)
# and an 'server address' binary annotation (because we pass the remote keyword)
server_host = %Tapper.Endpoint{service_name: "my-service"}
id = Tapper.start(name: "fetch", sample: true, remote: server_host)

# add some detail (binary annotations) about the request we're about to do
id
|> Tapper.http_host("my.server.co.uk")
|> Tapper.http_path("/index")
|> Tapper.http_method("GET")
|> Tapper.tag("some-key", "some-value")

... do call ...

# add some detail about the response
id
|> Tapper.client_receive() # add 'client-receive' annotation
|> Tapper.http_status_code(status_code)
|> Tapper.tag("something-else", "some-value")

# finish the trace (and the top-level span)
Tapper.finish(id)
```

### A Server

A server processing a request (usually via integration with e.g. `Plug`):

```elixir
# use propagated trace details (e.g. from Plug integration)
# also adds a 'server receive' annotation (defaults to type: :server)
id = Tapper.join(trace_id, span_id, parent_span_id, sample, debug)

# add some detail
id
|> Tapper.client_address(%Tapper.Endpoint{ipv4: conn.remote_ip})
|> Tapper.http_path(conn.requst_path)

# process request: call-out etc.
id = Tapper.start_span(...)
...
id = Tapper.finish_span(...)

# about to send response
Tapper.wire_send(id)

...

# sent response
Tapper.server_send(id)

Tapper.finish(id)
```

NB in general `start*` and `finish*` return an updated id, all other functions return the same id as before (so you don't need to propagate it backwards to just add annotations).

## Implementation

The Tapper API starts, and communicates with a `gen_server` process (`Tapper.Tracer.Server`), with one server started per trace; all traces are thus isolated.

Once a trace has been started, all span operations and annotation updates are performed asynchronously by sending a message to the server; this way there is minimum processing on the client side.

When a trace is terminated with `Tapper.finish/1`, the server sends the trace to the configured collector (e.g. Zipkin), and shuts-down.

If a trace is not terminated by an API call, Tapper will time-out after a pre-determined time since the last API operation (`:ttl` option on trace creation, default 30s), and terminate the trace as if `Tapper.finish/1` was called. This will also happen if the client process exits before finishing the trace.

If the API client registers asynchronous spans, and exits before they have finished, it should call `finish/1` passing the `async: true` option; async spans should be closed by their processes calling `finish_span/2`, otherwise they will eventually be terminated by the TTL behaviour.

The API client is not effected by the termination, normally or otherwise, of a trace-server, and the trace-server is likewise isolated from the API client, i.e. there is a separate supervision tree. 
Thus if the API client crashes, then the span can still be reported. The trace-server monitors the API client process for abnormal termination, and annotates the trace with an error (TODO monitoring).

Trace ids have an additional, unique, identifier, so if a server receives parallel requests within the same client span, the traces are not confused: each will start their own trace-server.

## Installation

For the latest pre-release (and unstable) code, add github repo to your mix dependencies:

```elixir
def deps do
  [{:tapper, git: "https://github.com/Financial-Times/tapper"}]
end
```

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `tapper` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:tapper, "~> 0.1.0"}]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/tapper](https://hexdocs.pm/tapper).

## Configuration

Add the `:tapper` application to your mix project's applications:

```elixir
  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [mod: {MyApp, []},
     applications: [:tapper]]
  end
```

Tapper looks for the following application configuration settings under the `:tapper` key:

| attribute | description |
| --------- | ----------- |
| `:system_id` | code for the hosting application, for tagging spans |
| `:reporter` | module of reporter `ingest/1` function |
| `:collector_url` | full URL of Zipkin server api for reeiving spans |

e.g. in `config.exs` (or `prod.exs` etc.)
```
config :tapper,
    system_id: "my-application",
    reporter: Tapper.Reporter.Zipkin,
    collector_url: "http://localhost:9411/api/v1/spans"
```

## Why 'Tapper'?

Dapper (Dutch - original Google paper) - Brave (English - Java client library) - Tapper (Swedish - Elixir client library)

Because Erlang, Ericsson 🇸🇪.
