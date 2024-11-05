defmodule ExRagTimeWeb.RagLive do
  use ExRagTimeWeb, :live_view
  import ExRagTimeWeb.CoreComponents

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:form, to_form(%{"question" => ""}))
      |> assign(:ingest_form, to_form(%{"path" => ""}))
      |> assign_async(:response, fn -> {:ok, %{response: %{}}} end)
      |> assign_async(
        :chunks,
        fn ->
          {:ok, %{chunks: ExRagTime.Repo.aggregate(ExRagTime.CodeChunk, :count)}}
        end,
        reset: true
      )

    {:ok, socket}
  end

  # <div :if={@chunks.loading}>Ingesting...</div>
  # <div :if={chunks = @chunks.ok? && @chunks.result}>Code chunks in database: <%= chunks %></div>
  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="grid grid-col-1 gap-4">
      <div class="grid grid-cols-[1fr_auto]">
        <.async_result :let={chunks} assign={@chunks}>
          <:loading>Ingesting...</:loading>
          <:failed>Something went wrong...</:failed>
          <p>Code chunks in database: <%= chunks %></p>
        </.async_result>
        <.button phx-click="reset">Reset</.button>
      </div>

      <.simple_form for={@ingest_form} phx-submit="ingest">
        <.input field={@ingest_form[:path]} label="Ingestion Path" />
        <:actions>
          <.button>Ingest</.button>
        </:actions>
      </.simple_form>

      <.async_result :let={response} assign={@response}>
        <:loading>Waiting for response...</:loading>
        <:failed>Something went wrong...</:failed>
        <p :if={response[:query]}>Query: <%= response.query %></p>
        <p :if={response[:response]}>Response: <%= response.response %></p>

        <p :if={response[:context_sources]}>Sources:</p>
        <ol class="list-decimal">
          <li :for={source <- response[:context_sources] || []}><%= source %></li>
        </ol>
      </.async_result>

      <.simple_form for={@form} phx-submit="query">
        <.input field={@form[:question]} label="Question" />
        <:actions>
          <.button>Send</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("ingest", %{"path" => path}, socket) do
    {:noreply,
     assign_async(
       socket,
       :chunks,
       fn -> {:ok, %{chunks: ExRagTime.ingest(path) |> Enum.count()}} end,
       reset: true
     )}
  end

  def handle_event("reset", _params, socket) do
    {:noreply,
     assign_async(
       socket,
       :chunks,
       fn ->
         ExRagTime.Repo.delete_all(ExRagTime.CodeChunk)

         {:ok, %{chunks: 0}}
       end,
       reset: true
     )}
  end

  def handle_event("query", %{"question" => question}, socket) do
    {:noreply,
     assign_async(socket, :response, fn -> {:ok, %{response: ExRagTime.query(question)}} end,
       reset: true
     )}
  end
end
