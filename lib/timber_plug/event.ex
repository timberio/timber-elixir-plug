defmodule Timber.Plug.Event do
  @moduledoc """
  Automatically logs metadata information about HTTP requests
  and responses in Plug-based frameworks like Phoenix.

  Whether you use Plug by itself or as part of a framework like Phoenix,
  adding this plug to your pipeline will automatically create events
  for incoming HTTP requests and responses for your log statements.

  Note: If you're using `Timber.Plug.HTTPContext`, that plug should come before
  `Timber.Plug.Event` in any pipeline. This will give you the best results.

  ## Adding the Plug

  `Timber.Plug.Event` can be added to your plug pipeline using the standard
  `Plug.Builder.plug/2` macro. The point at which you place it determines
  what state Timber will receive the connection in, therefore it's
  recommended you place it as close to the origin of the request as
  possible.

  ### Plug (Standalone or Plug.Router)

  If you are using Plug without a framework, your setup will vary depending
  on your architecture. The call to `plug Timber.Plug.Event` should be grouped
  with any other plugs you call prior to performing business logic.

  Timber expects query paramters to have already been fetched on the
  connection using `Plug.Conn.fetch_query_params/2`.

  ### Phoenix

  Phoenix's flexibility means there are multiple points in the plug pipeline
  where the `Timber.Plug.Event` can be inserted. The recommended place is in
  a `:logging` pipeline in your router, but if you have more complex needs
  you can also place the plug in an endpoint or a controller.

  ```elixir
  defmodule MyApp.Router do
    use MyApp.Web, :router

    pipeline :logging do
      plug Timber.Plug.Event
    end

    scope "/api", MyApp do
      pipe_through :logging
    end
  end
  ```

  If you place the plug call in your endpoint, you will need to make sure
  that it appears after `Plug.RequestId` (if you are using it) but before
  the call to your router.

  ## Issues with Plug.ErrorHandler

  If you are using `Plug.ErrorHandler`, you will not see a response
  event if an exception is raised. This is because of how the error
  handler works in practice. In order to capture information about the
  response, Timber registers a callback to be used before Plug actually
  sends the response. Plug stores this information on the
  connection struct. When an exception is raised, the methodology used
  by the error handler will reset the conn to the state it was first
  accepted by the router.
  """

  @behaviour Plug

  require Logger

  alias Timber.Timer

  @doc false
  @impl true
  def init(opts) do
    opts
  end

  @doc false
  @impl true
  def call(conn, opts) do
    timer = Timer.start()
    log_level = Keyword.get(opts, :log_level, :info)
    request_id_header_name = Keyword.get(opts, :request_id_header, "x-request-id")
    request_id_header = Timber.Plug.get_request_id(conn, request_id_header_name)
    request_id = request_id_from_header(request_id_header)
    method = conn.method
    host = conn.host
    port = conn.port
    scheme = conn.scheme
    path = conn.request_path
    headers = List.flatten([request_id_header | conn.req_headers])
    headers_json = Timber.try_encode_to_json(headers)
    query_string = conn.query_string

    event = %{
      http_request_received: %{
        headers_json: headers_json,
        host: host,
        method: method,
        path: path,
        port: port,
        query_string: query_string,
        request_id: request_id,
        scheme: scheme
      }
    }

    message =
      if path do
        ["Received ", method, " ", path]
      else
        ["Received ", method]
      end

    Logger.log(log_level, message, metadata)

    conn
    |> Plug.Conn.put_private(:timber_opts, opts)
    |> Plug.Conn.put_private(:timber_timer, timer)
    |> Plug.Conn.register_before_send(&log_response_event/1)
  end

  @spec log_response_event(Plug.Conn.t()) :: Plug.Conn.t()
  defp log_response_event(conn) do
    duration_ms = Timber.duration_ms(conn.private.timber_timer)
    opts = conn.private.timber_opts
    log_level = Keyword.get(opts, :log_level, :info)
    status = Plug.Conn.Status.code(conn.status)
    request_id_header_name = Keyword.get(opts, :request_id_header, "x-request-id")
    request_id_header = Timber.Plug.get_request_id(conn, request_id_header_name)

    # The response body typing is iodata; it should not be assumed
    # to be a binary
    bytes = body_bytes(conn.resp_body)

    headers = [
      {"content-length", Integer.to_string(bytes)},
      request_id_header | conn.resp_headers
    ]

    headers_json = Timber.try_encode_to_json(headers)
    request_id = request_id_from_header(request_id_header)

    event = %{
      http_response_sent: %{
        headers_json: headers_json,
        request_id: request_id,
        status: status,
        duration_ms: duration_ms
      }
    }

    message = [
      "Sent ",
      Integer.to_string(event.status),
      " response in ",
      Timber.format_duration_ms(event.time_ms)
    ]

    Logger.log(log_level, message, event: event)

    conn
  end

  defp body_bytes(nil), do: 0
  defp body_bytes(body), do: IO.iodata_length(body)

  defp request_id_from_header(request_id_header) do
    case request_id_header do
      [{_, request_id}] -> request_id
      [] -> nil
    end
  end

  # Constructs a full path from the given parts
  def full_url(scheme, host, path, port, query_string) do
    %URI{scheme: scheme, host: host, path: path, port: port, query: query_string}
    |> URI.to_string()
  end
end
