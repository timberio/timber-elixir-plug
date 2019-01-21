defmodule Timber.Plug.HTTPContext do
  @moduledoc """
  Automatically captures the HTTP method, path, and request_id in Plug-based
  frameworks like Phoenix and adds it to the context.

  By adding this data to the context, you'll be able to associate all the log
  statements that occur while processing that HTTP request.

  ## Adding the Plug

  `Timber.Plug.HTTPContext` can be added to your plug pipeline using the
  standard `Plug.Builder.plug/2` macro. The point at which you place it
  determines what state Timber will receive the connection in, therefore it's
  recommended you place it as close to the origin of the request as possible.

  ### Plug (Standalone or Plug.Router)

  If you are using Plug without a framework, your setup will vary depending on
  your architecture. The call to `plug Timber.Plug.HTTPContext` should be
  grouped with any other plugs you call prior to performing business logic.

  Timber expects query parameters to have already been fetched on the connection
  using `Plug.Conn.fetch_query_params/2`.

  ### Phoenix

  Phoenix's flexibility means there are multiple points in the plug pipeline
  where the `Timber.Plug.HTTPContext` can be inserted. The recommended place is
  in `endpoint.ex`. Make sure that you insert this plug immediately before your
  `Router` plug.

  ## Request ID

  Timber does its best to track the request ID for every HTTP request in order
  to help you filter your logs easily. If you are calling the `Plug.RequestId`
  plug in your pipeline, you should make sure that `Timber.Plug.HTTPContext`
  appears _after_ that plug so that it can pick up the correct ID.

  By default, Timber expects your request ID to be stored using the header name
  "X-Request-ID" (casing irrelevant), but that may not fit all needs. If you use
  a custom header name for your request ID, you can pass that name as an option
  to the plug:

  ```
  plug Timber.Plug, request_id_header: "req-id"
  ```
  """

  @behaviour Plug

  @doc false
  @impl true
  def init(opts) do
    opts
  end

  @doc false
  @impl true
  def call(%{method: method, request_path: request_path} = conn, opts) do
    request_id_header = Keyword.get(opts, :request_id_header, "x-request-id")
    remote_addr = Timber.Plug.get_client_ip(conn)

    request_id =
      case Timber.Plug.get_request_id(conn, request_id_header) do
        [{_, request_id}] -> request_id
        [] -> nil
      end

    %{
      http: %{
        method: method,
        path: request_path,
        request_id: request_id,
        remote_addr: remote_addr
      }
    }
    |> Timber.add_context()

    conn
  end
end
