defmodule ExRagTime.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Nx.Serving,
       serving: build_embedding_serving(), name: ExRagTime.EmbeddingsServing, batch_timeout: 100},
      {Nx.Serving, serving: build_llm_serving(), name: ExRagTime.LLMServing, batch_timeout: 100},
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
    System.get_env("RELEASE_NAME") != nil
  end

  def build_embedding_serving() do
    repo = {:hf, "thenlper/gte-small"}

    {:ok, model_info} = Bumblebee.load_model(repo)
    {:ok, tokenizer} = Bumblebee.load_tokenizer(repo)

    Bumblebee.Text.TextEmbedding.text_embedding(model_info, tokenizer,
      compile: [batch_size: 64, sequence_length: 512],
      defn_options: [compiler: EXLA],
      output_attribute: :hidden_state,
      output_pool: :mean_pooling
    )
  end

  def build_llm_serving() do
    repo = {:hf, "meta-llama/Llama-3.2-1B", auth_token: "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"}

    {:ok, model_info} = Bumblebee.load_model(repo)
    {:ok, tokenizer} = Bumblebee.load_tokenizer(repo)
    {:ok, generation_config} = Bumblebee.load_generation_config(repo)

    generation_config = Bumblebee.configure(generation_config, max_new_tokens: 100)

    Bumblebee.Text.generation(model_info, tokenizer, generation_config,
      compile: [batch_size: 1, sequence_length: 6000],
      defn_options: [compiler: EXLA],
      stream: true
    )
  end
end
