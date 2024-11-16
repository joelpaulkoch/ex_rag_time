Mix.install(
  [
    {:phoenix_playground, "~> 0.1.6"},
    {:phoenix, "~> 1.7.14"},
    {:phoenix_live_view, "~> 1.0.0-rc.1", override: true},
    {:chroma, "~> 0.1.3"},
    {:text_chunker, "~> 0.3.1"},
    {:nx, "~> 0.9.0"},
    {:exla, "~> 0.9.1"},
    {:axon, "~> 0.7.0"},
    {:bumblebee, github: "joelpaulkoch/bumblebee", branch: "jina-embeddings-v2-base-code"}
  ],
  config: [
    chroma: [host: "http://localhost:8000", api_base: "api", api_version: "v1"],
    nx: [default_backend: EXLA.Backend]
  ]
)

defmodule RagTime.Serving do
  def build_embedding_serving() do
    repo = {:hf, "jinaai/jina-embeddings-v2-base-code"}

    {:ok, model_info} =
      Bumblebee.load_model(repo,
        spec_overrides: [architecture: :base],
        params_filename: "model.safetensors"
      )

    {:ok, tokenizer} = Bumblebee.load_tokenizer(repo)

    Bumblebee.Text.TextEmbedding.text_embedding(model_info, tokenizer,
      compile: [batch_size: 64, sequence_length: 512],
      defn_options: [compiler: EXLA],
      output_attribute: :hidden_state,
      output_pool: :mean_pooling
    )
  end

  def build_llm_serving() do
    repo = {:hf, "microsoft/phi-3.5-mini-instruct"}

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

defmodule RagTime.Ingestion do
  def chunk_with_metadata(documents, format) do
    chunks = Enum.map(documents, &TextChunker.split(&1.content, format: format))
    sources = Enum.map(documents, & &1.source)

    Enum.zip(sources, chunks)
    |> Enum.map(fn {source, source_chunks} ->
      for chunk <- source_chunks,
          do: %{
            source: source,
            start_byte: chunk.start_byte,
            end_byte: chunk.end_byte,
            text: chunk.text
          }
    end)
    |> List.flatten()
  end

  def generate_embeddings(chunks) do
    Nx.Serving.batched_run(RagTime.EmbeddingServing, Enum.map(chunks, & &1.text))
    |> Enum.map(fn %{embedding: embedding} -> Nx.to_list(embedding) end)
  end

  def store_embeddings_and_chunks(collection, embeddings, chunks) do
    documents = Enum.map(chunks, & &1.text)
    ids = Enum.map(chunks, &chunk_to_id(&1))

    Chroma.Collection.add(collection, %{documents: documents, ids: ids, embeddings: embeddings})
  end

  defp chunk_to_id(%{source: path, start_byte: start_byte, end_byte: end_byte}) do
    file_content = File.read!(path)

    start_line =
      file_content
      |> String.byte_slice(0, String.to_integer(start_byte))
      |> String.split("\n")
      |> Enum.count()

    end_line =
      file_content
      |> String.byte_slice(0, String.to_integer(end_byte))
      |> String.split("\n")
      |> Enum.count()

    "#{path}:#{start_line}-#{end_line}"
  end

  def ingest(collection, input_path) when is_binary(input_path) do
    files =
      Path.wildcard(input_path <> "/**/*.{ex, exs}")
      |> Enum.filter(fn path ->
        not String.contains?(path, ["/_build/", "/deps/", "/node_modules/"])
      end)

    files_content = for file <- files, do: File.read!(file)

    ingest(
      collection,
      Enum.zip_with(files, files_content, fn file, content ->
        %{content: content, source: file}
      end)
    )
  end

  def ingest(collection, documents) when is_list(documents) do
    chunks = chunk_with_metadata(documents, :elixir)

    embeddings = generate_embeddings(chunks)

    store_embeddings_and_chunks(collection, embeddings, chunks)
  end
end

defmodule RagTime.Retrieval do
  def retrieve(collection, question) do
    %{embedding: query_embedding} = Nx.Serving.batched_run(RagTime.EmbeddingsServing, question)

    {:ok, results} =
      Chroma.Collection.query(collection,
        results: 3,
        query_embeddings: [query_embedding]
      )

    {documents, sources} = {hd(results["documents"]), hd(results["ids"])}

    results =
      Enum.zip(documents, sources)
      |> Enum.map(fn {document, source} -> %{document: document, source: source} end)

    context =
      Enum.map(results, fn %{document: context} ->
        "[...] #{context} [...]"
      end)
      |> Enum.join("\n\n")

    {context, sources}
  end
end

defmodule RagTime.Generation do
  def generate_response(question, context, context_sources) do
    context = Enum.join(context, "\n\n")

    prompt =
      """
      <|system|>
      You are a helpful assistant.</s>
      <|user|>
      Context information is below.
      ---------------------
      #{context}
      ---------------------
      Given the context information and no prior knowledge, answer the query.
      Query: #{question}
      Answer: </s>
      <|assistant|>
      """

    %{results: [result]} = Nx.Serving.batched_run(RagTime.LLMServing, prompt)

    %{
      query: question,
      context: context,
      context_sources: context_sources,
      response: result.text
    }
  end
end

defmodule RagTime do
  def query(collection, question) do
    {context, sources} = RagTime.Retrieval.retrieve(collection, question)

    RagTime.Generation.generate_response(question, context, sources)
  end
end

defmodule RagLive do
  use Phoenix.LiveView

  @chroma_collection_name "rag-time"

  def mount(_params, _session, socket) do
    {:ok, collection} =
      Chroma.Collection.get_or_create(@chroma_collection_name, %{"hnsw:space" => "l2"})

    socket =
      socket
      |> assign(:query_form, to_form(%{"question" => ""}))
      |> assign(:ingest_form, to_form(%{"path" => ""}))
      |> assign_async(:response, fn -> {:ok, %{response: %{}}} end)
      |> assign_async(
        :chunks,
        fn ->
          {:ok, %{chunks: Chroma.Collection.count(collection)}}
        end,
        reset: true
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div style="display: grid; grid-template-columns: minmax(0, 1fr); gap: 1rem">
      <h1>A RAG for Elixir</h1>
      <div style="display: flex; flex-direction: row; gap: 1rem;">
        <.async_result :let={chunks} assign={@chunks}>
          <:loading>Ingesting...</:loading>
          <:failed>Something went wrong...</:failed>
          <p>Code chunks in database: <%= chunks %></p>
        </.async_result>
        <button phx-click="reset">Reset</button>
      </div>

      <.form for={@ingest_form} phx-submit="ingest">
        <.input type="text" field={@ingest_form[:path]} label="Ingestion Path" />
        <button>Ingest</button>
      </.form>

      <.async_result :let={response} assign={@response}>
        <:loading>Waiting for response...</:loading>
        <:failed>Something went wrong...</:failed>
        <p :if={response[:query]}>Query: <%= response.query %></p>
        <p :if={response[:response]}>Response: <%= response.response %></p>

        <p :if={response[:context_sources]}>Sources:</p>
        <ol style="list-style-type: decimal;">
          <li :for={source <- response[:context_sources] || []}><%= source %></li>
        </ol>
      </.async_result>
      <.form for={@query_form} phx-submit="query">
        <.input type="text" field={@query_form[:question]} label="Question" />
        <button>Send</button>
      </.form>
    </div>
    """
  end

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns[:id] || field.id)
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(assigns) do
    ~H"""
    <div>
      <label for={@id}><%= @label %></label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
      />
    </div>
    """
  end

  def handle_event("ingest", %{"path" => path}, socket) do
    {:ok, collection} =
      Chroma.Collection.get_or_create(@chroma_collection_name, %{"hnsw:space" => "l2"})

    {:noreply,
     assign_async(
       socket,
       :chunks,
       fn ->
         RagTime.Ingestion.ingest(collection, path)
         {:ok, %{chunks: Chroma.Collection.count(collection)}}
       end,
       reset: true
     )}
  end

  def handle_event("reset", _params, socket) do
    {:noreply,
     assign_async(
       socket,
       :chunks,
       fn ->
         Chroma.Collection.delete(@chroma_collection_name)
         {:ok, %{chunks: 0}}
       end,
       reset: true
     )}
  end

  def handle_event("query", %{"question" => question}, socket) do
    {:ok, collection} =
      Chroma.Collection.get_or_create(@chroma_collection_name, %{"hnsw:space" => "l2"})

    {:noreply,
     assign_async(
       socket,
       :response,
       fn -> {:ok, %{response: RagTime.query(collection, question)}} end,
       reset: true
     )}
  end
end

PhoenixPlayground.start(
  live: RagLive,
  child_specs: [
    {Nx.Serving,
     serving: RagTime.Serving.build_embedding_serving(),
     name: RagTime.EmbeddingServing,
     batch_timeout: 100},
    {Nx.Serving,
     serving: RagTime.Serving.build_llm_serving(), name: RagTime.LLMServing, batch_timeout: 100}
  ]
)
