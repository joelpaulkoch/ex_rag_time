defmodule ExRagTime.Retrieval do
  alias ExRagTime.Repo
  alias ExRagTime.CodeChunk
  import Ecto.Query
  import SqliteVec.Ecto.Query

  def retrieve(question) do
    if !question || question == "", do: raise("Empty question")

    %{embedding: query_embedding} = Nx.Serving.batched_run(ExRagTime.EmbeddingsServing, question)

    query_vector = SqliteVec.Float32.new(query_embedding)

    results =
      Repo.all(
        from(c in CodeChunk,
          order_by: l2_distance(c.embedding, vec_f32(^query_vector.data)),
          limit: 5
        )
      )

    context_sources = Enum.map(results, & &1.source)

    context =
      Enum.map(results, fn %{document: context} ->
        "[...] #{context} [...]"
      end)
      |> Enum.join("\n\n")

    {context, context_sources}
  end
end
