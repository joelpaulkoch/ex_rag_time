defmodule ExRagTime.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Nx.Serving,
       serving: ExRagTime.Rag.Serving.build_embedding_serving(),
       name: Rag.EmbeddingServing,
       batch_timeout: 100},
      {Nx.Serving,
       serving: ExRagTime.Rag.Serving.build_llm_serving(),
       name: Rag.LLMServing,
       batch_timeout: 100},
      ExRagTimeWeb.Telemetry,
      ExRagTime.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:ex_rag_time, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:ex_rag_time, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ExRagTime.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: ExRagTime.Finch},
      # Start a worker by calling: ExRagTime.Worker.start_link(arg)
      # {ExRagTime.Worker, arg},
      # Start to serve requests, typically the last entry
      ExRagTimeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExRagTime.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ExRagTimeWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    false
  end
end
