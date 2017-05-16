# Tapper - Zipkin client for Elixir.

Implements an interface for recording traces and sending them to a [Zipkin](http://zipkin.io/) server.

## Synopsis

### A Client
A client making a request:

```elixir
# start a new, sampled, trace, and root span;
# creates a 'client send' annotation on root span
# (defaults to type: :client) and a 'server address' (sa)
# binary annotation (because we pass the remote option with
# an endpoint)

service_host = %Tapper.Endpoint{service_name: "my-service"}

id = Tapper.start(name: "fetch", sample: true, remote: service_host)

# add some detail (binary annotations) about the request
# we're about to do
Tapper.update_span(id, [
  Tapper.http_host("my.server.co.uk")
  Tapper.http_path("/index")
  Tapper.http_method("GET")
  Tapper.tag("some-key", "some-value")
])

... do call ...

# finish the trace (and the top-level span), with some detail about the response
Tapper.finish(id, annotations: [
  Tapper.http_status_code(status_code)
])
```

### A Server

A server processing a request (usually performed via integration e.g. [`Tapper.Plug`](https://github.com/Financial-Times/tapper_plug)):

```elixir
# use propagated trace details (e.g. from Plug integration);
# adds a 'server receive' (sr) annotation (defaults to type: :server)
id = Tapper.join(trace_id, span_id, parent_span_id, sample, debug, annotations: [
  Tapper.client_address(%Tapper.Endpoint{ip: conn.remote_ip}), # we could also have used remote option on join
  Tapper.http_path(conn.request_path)
])

# call another service
id = Tapper.start_span(id, name: "fetch-details", annotations: [
    Tapper.http_path("/service/xx")
])
...

Tapper.update_span(id, Tapper.wire_receive())
...

id = Tapper.finish_span(id, annotations: [
    Tapper.tag("userId", 1234),
    Tapper.http_status_code(200)
])

# process request: span for expensive local processing etc.
id = Tapper.start_span(id, name: "process", local: "compute-result") # adds lc binary annotation
...
id = Tapper.finish_span(id)

Tapper.finish(id)
```

> NB `Tapper.start_span/2` and `Tapper.finish_span/2` return an updated id, whereas all other functions return the same id, so you don't need to propagate the id backwards down a call-chain to just add annotations, but you should propagate the id forwards when adding spans, and pair `finish_span/2` with the id from the corresponding `start_span/2`. Parallel spans can share the same starting id.

#### See also
[`Tapper.Plug`](https://github.com/Financial-Times/tapper_plug) - [Plug](https://github.com/elixir-lang/plug) integration: decodes incoming [B3](https://github.com/openzipkin/b3-propagation) trace headers, joining or sampling traces.

## Implementation

The Tapper API starts, and communicates with a supervised `GenServer` process (`Tapper.Tracer.Server`), with one server started per trace; all traces are thus isolated.

Once a trace has been started, all span operations and updates are performed asynchronously by sending a message to the server; this way there is minimum processing on the client side. One message is sent per `Tapper.start_span/2`, `Tapper.finish_span/2` or `Tapper.update_span/2`, tagged with the current timestamp at the point of the call.

When a trace is terminated with `Tapper.finish/2`, the server sends the trace to the configured collector (e.g. a Zipkin server), and exits normally.

If a trace is not terminated by an API call, Tapper will time-out after a pre-determined time since the last API operation (`ttl` option on trace creation, default 30s), and terminate the trace as if `Tapper.finish/2` was called, annotating the unfinished spans with a `timeout` annotation. Timeout will will also happen if the client process exits before finishing the trace.

If the API client starts spans in, or around, asynchronous processes, and exits before they have finished, it should call `Tapper.start_span/2` or `Tapper.update_span/2` with a `Tapper.async/1` annotation, or `Tapper.finish/2` passing the `async: true` option or annotation; async spans should be closed as normal by `Tapper.finish_span/2`, otherwise they will eventually be terminated by the TTL behaviour.

The API client is not effected by the termination, normally or otherwise, of a trace-server, and the trace-server is likewise isolated from the API client, i.e. there is a separate supervision tree. Thus if the API client crashes, then the span can still be reported. The trace-server monitors the API client process for abnormal termination, and annotates the trace with an error (TODO). If the trace-server crashes, any child spans and annotations registered with the server will be lost, but subsequent spans and the trace itself will be reported, since the supervisor will re-start the trace-server using the initial data from `Tapper.start/1` or `Tapper.join/6`.

Trace ids have an additional, unique, identifier, so if a server receives parallel requests within the same client span, the traces are recorded separately: each will start their own trace-server.

The id returned from the API simply tracks the trace id, enabling messages to be sent to the right server, and span nesting, to ensure annotations are added to the correct span.

## Installation

For the latest pre-release (and unstable) code, add github repo to your mix dependencies:

```elixir
def deps do
  [{:tapper, git: "https://github.com/Financial-Times/tapper"}]
end
```

For release versions, the package can be installed by adding `tapper` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:tapper, "~> 0.1.0"}]
end
```

The documentation can be found at [https://hexdocs.pm/tapper](https://hexdocs.pm/tapper).

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

| attribute | type | description |
| --------- | ---- | ----------- |
| `system_id` | String.t | This application's id; used for `service_name` in default endpoint host used in annotations. |
| `ip`        | tuple    | This application's principle IPV4 or IPV6 address, as 4- or 8-tuple of ints; defaults to IP of first non-loopback interface, or `{127.0.0.1}` if none. |
| `port`      | integer  | This application's principle service port, for endpoint port in annotations; defaults to 0 |
| `reporter`  | atom     | Module implementing `Tapper.Reporter.Api` to use for reporting spans, defaults to `Tapper.Reporter.Console`. |

All keys support the Phoenix-style `{:system, var}` format, to allow lookup from shell environment variables, e.g. `{:system, "PORT"}` to read `PORT` environment variable.

The default reporter is `Tapper.Reporter.Console` which just just logs JSON spans;
`Tapper.Reporter.Zipkin` reports spans to a Zipkin server.

### Zipkin Reporter

The Zipkin reporter (`Tapper.Reporter.Zipkin`) has its own configuration:

| attribute | description |
| --------- | ----------- |
| `:collector_url` | full URL of Zipkin server api for reeiving spans |

e.g. in `config.exs` (or `prod.exs` etc.)
```elixir
config :tapper,
    system_id: "my-application",
    reporter: Tapper.Reporter.Zipkin

config :tapper, Tapper.Reporter.Zipkin,
    collector_url: "http://localhost:9411/api/v1/spans"
```

### Custom Reporters

You can implement your own reporter module by implementing the `Tapper.Reporter.Api` protocol.

This defines a function `ingest/1` that receives spans in the form of `Tapper.Protocol.Span` structs,
with timestamps and durations in microseconds. For JSON serialization, see `Tapper.Encoder.Json` which
encodes to a format compatible with Zipkin server.

## Why 'Tapper'?

Dapper (Dutch - original Google paper) - Brave (English - Java client library) - Tapper (Swedish - Elixir client library)

Because Erlang, Ericsson 🇸🇪.
