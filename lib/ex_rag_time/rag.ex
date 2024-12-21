defmodule ExRagTime.Rag do
  alias ExRagTime.Repo
  import Ecto.Query
  import SqliteVec.Ecto.Query

  def ingest(website_url) do
    Hop.new(website_url)
    |> Hop.stream()
    |> Enum.each(fn {url, response, _state} ->
      body =
        response.body
        |> Readability.article()
        |> Readability.readable_text()

      Task.start(fn ->
        %{url: url, body: body}
        |> load()
        |> index()

        IO.puts("ingested #{url}")
      end)
    end)

    []
  end

  def load(%{url: url, body: body} = _website) do
    %{source: url, document: body}
  end

  def index(ingestion) do
    chunks =
      ingestion
      |> Rag.Loading.chunk_text(:document)
      |> Rag.Embedding.Nx.generate_embeddings_batch(:chunk, :embedding)
      |> Enum.map(&to_chunk(&1))

    Repo.insert_all(ExRagTime.Rag.Chunk, chunks)
  end

  def query(query) do
    generation =
      Rag.Generation.new(query)
      |> Rag.Embedding.Nx.generate_embedding()
      # |> Rag.Retrieval.retrieve(:fulltext_results, fn generation -> query_fulltext(generation) end)
      |> Rag.Retrieval.retrieve(:semantic_results, fn generation ->
        query_with_sqlite_vec(generation, 10)
      end)

    # |> Rag.Retrieval.reciprocal_rank_fusion(
    #   %{fulltext_results: 1, semantic_results: 1},
    #   :rrf_result
    # )

    context =
      Rag.Generation.get_retrieval_result(generation, :semantic_results)
      |> Enum.map_join("\n\n", & &1.document)

    context_sources =
      Rag.Generation.get_retrieval_result(generation, :semantic_results)
      |> Enum.map(& &1.source)

    prompt = smollm_prompt(query, context)

    generation = %{
      generation
      | context: context,
        context_sources: context_sources,
        prompt: prompt
    }

    Rag.Generation.Nx.generate_response(generation)
  end

  defp to_chunk(ingestion) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    ingestion
    |> Map.put_new(:inserted_at, now)
    |> Map.put_new(:updated_at, now)
    |> Map.update!(:embedding, &SqliteVec.Float32.new/1)
  end

  defp query_with_sqlite_vec(%{query_embedding: query_embedding}, limit \\ 3) do
    v = SqliteVec.Float32.new(query_embedding)

    Repo.all(
      from(c in ExRagTime.Rag.Chunk,
        where: match(c.embedding, vec_f32(v)),
        limit: ^limit
      )
    )
  end

  # defp query_fulltext(%{query: query}, limit \\ 3) do
  #   query = String.replace(query, " ", " & ")

  #   Repo.all(
  #     from(c in ExRagTime.Rag.Chunk,
  #       where: fragment("to_tsvector(?) @@ to_tsquery(?)", c.document, ^query),
  #       limit: ^limit
  #     )
  #   )
  # end

  defp smollm_prompt(query, context) do
    """
    <|im_start|>system
    You are a helpful assistant.<|im_end|>
    <|im_start|>user
    Context information is below.
    ---------------------
    #{context}
    ---------------------
    Given the context information and no prior knowledge, answer the query.
    Query: #{query}
    Answer: <|im_end|>
    <|im_start|>assist
    """
  end
end
