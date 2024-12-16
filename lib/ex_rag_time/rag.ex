defmodule ExRagTime.Rag do
  alias ExRagTime.Repo
  import Ecto.Query
  import Pgvector.Ecto.Query

  def list_text_files(path) do
    path
    |> Path.join("/**/*.txt")
    |> Path.wildcard()
  end

  defp load(path) do
    path
    |> list_text_files()
    |> Enum.map(&%Rag.Ingestion{source: &1})
    |> Enum.map(&Rag.Loading.load_file(&1))
  end

  def index(rag_state_list) do
    chunks =
      rag_state_list
      |> Enum.flat_map(&Rag.Loading.chunk_text(&1))
      |> Rag.Embedding.Nx.generate_embeddings_batch(:chunk, :embedding)
      |> Enum.map(&to_chunk(&1))

    Repo.insert_all(ExRagTime.Rag.Chunk, chunks)
  end

  def ingest(path) do
    path
    |> load()
    |> index
  end

  def query(query) do
    rag_state =
      %{query: query}
      |> Rag.Retrieval.retrieve(fn state -> query_fulltext(state, :fulltext_results) end)
      |> Rag.Embedding.Nx.generate_embedding(:query, :query_embedding)
      |> Rag.Retrieval.retrieve(fn state -> query_with_pgvector(state, :semantic_results) end)
      |> Rag.Retrieval.reciprocal_rank_fusion(
        [{:fulltext_results, 1} , {:semantic_results, 1 }],
        :query_results
      )

    context = Enum.map(rag_state.query_results, & &1.document) |> Enum.join("\n\n")
    context_sources = Enum.map(rag_state.query_results, & &1.source)
    prompt = smollm_prompt(context, query)

    rag_state
    |> Map.put(:context, context)
    |> Map.put(:context_sources, context_sources)
    |> Map.put(:prompt, prompt)
    |> Rag.Generation.Nx.generate_response()
  end

  defp to_chunk(input) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    input
    |> Map.take([:document, :source, :chunk, :embedding])
    |> Map.put_new(:inserted_at, now)
    |> Map.put_new(:updated_at, now)
  end

  defp query_with_pgvector(%{query_embedding: query_embedding} = input, output_key, limit \\ 3) do
    results =
      Repo.all(
        from(c in ExRagTime.Rag.Chunk,
          order_by: l2_distance(c.embedding, ^Pgvector.new(query_embedding)),
          limit: ^limit
        )
      )

    Map.put(input, output_key, results)
  end

  defp query_fulltext(%{query: query} = input, output_key, limit \\ 3) do
    query = String.replace(query, " ", " & ")

    results =
      Repo.all(
        from c in ExRagTime.Rag.Chunk,
          where: fragment("to_tsvector(?) @@ to_tsquery(?)", c.document, ^query),
          limit: ^limit
      )

    Map.put(input, output_key, results)
  end

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
    <|im_start|>assistant
    """
  end
end
