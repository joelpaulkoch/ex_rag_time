defmodule ExRagTimeWeb.RagLive do
  use ExRagTimeWeb, :live_view
  import ExRagTimeWeb.CoreComponents

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:messages, [])
      |> assign(:form, to_form(%{"question" => ""}))
      |> assign(:ingest_form, to_form(%{"path" => ""}))

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.simple_form for={@ingest_form} phx-submit="ingest">
      <.input field={@ingest_form[:path]} label="Ingestion Path" />
      <:actions>
        <.button>Ingest</.button>
      </:actions>
    </.simple_form>

    <%= for message <- @messages do %>
      <p><%= message %></p>
    <% end %>

    <.simple_form for={@form} phx-submit="query">
      <.input field={@form[:question]} label="Question" />
      <:actions>
        <.button>Send</.button>
      </:actions>
    </.simple_form>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("ingest", %{"path" => path}, socket) do
    ExRagTime.ingest(path)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("query", %{"question" => question}, socket) do
    messages = socket.assigns.messages

    response = ExRagTime.query(question)

    messages = messages ++ [question, response]

    {:noreply, assign(socket, :messages, messages)}
  end
end
