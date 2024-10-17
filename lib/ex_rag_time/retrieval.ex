defmodule ExRagTime.Retrieval do
  def retrieve(question) do
    if !question || question == "", do: raise("Empty question")

    %{embedding: query_embedding} = Nx.Serving.batched_run(ExRagTime.EmbeddingsServing, question)

    query_embedding = Nx.to_list(query_embedding)
    query_embedding_string = "[" <> Enum.join(query_embedding, ", ") <> "]"

    {:ok, result} =
      Ecto.Adapters.SQL.query(
        ExRagTime.Repo,
        """
        select 
          embeddings.id,
          distance,
          document,
          source
        from embeddings
        left join chunks on chunks.id = embeddings.id
        where sample_embedding match ?
        and k = 3
        order by distance
        """,
        [query_embedding_string]
      )

    context_sources =
      for [_something, _distance, _context, context_source] <- result.rows, do: context_source

    context =
      Enum.map(result.rows, fn [_something, _distance, context, _context_source] ->
        "[...] #{context} [...]"
      end)
      |> Enum.join("\n\n")

    {context, context_sources}
  end
end
