defmodule ExRagTime do
  @moduledoc """
  ExRagTime keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  alias ExRagTime.Repo
  import Ecto.Query
  import Pgvector.Ecto.Query

  defp list_elixir_files(path) do
    Path.wildcard(path <> "/**/*.{ex, exs}")
    |> Enum.filter(fn path ->
      not String.contains?(path, ["/_build/", "/deps/", "/node_modules/"])
    end)
  end

  # try changing between option 1., 2., and 3.
  # 1. is what I assume most real world usage would look like: a customized RAG system
  # 2. is using the provided `Pipelines` module
  # 3. demonstrates usage with openai and chroma (also via `Pipelines`)
  # you must comment/uncomment lines in these files too:
  # - priv/repo/migrations/20241016163412_add_embeddings_table.exs
  # for openai (3.): set your openai api key as OPENAI_API_KEY environment variable
  # for chroma (3.): run chroma using docker `docker run -p 8000:8000 chromadb/chroma`
  def ingest(path) do
    ## 1. custom with bumblebee + pgvector
    chunks =
      path
      |> list_elixir_files()
      |> Enum.map(&%{source: &1})
      |> Enum.map(&Rag.Loading.load_file(&1))
      |> Enum.flat_map(&Rag.Loading.chunk_text(&1))
      |> Rag.Embedding.Bumblebee.generate_embeddings_batch(:chunk, :embedding)
      |> Enum.map(&to_chunk(&1))

    # note how we can just use regular ecto functions
    # there is nothing special about vector stores this way
    # in a real application we would probably move this into a context
    # and we would define our own "chunks" ecto schema as usual
    Repo.insert_all("chunks", chunks)

    ## 2. bumblebee + pgvector
    # path
    # |> list_elixir_files()
    # |> Enum.map(&%{source: &1})
    # |> Rag.Pipelines.ingest_bumblebee_text_embeddings_pgvector(Repo)

    ## 3. openai + chroma
    # {:ok, collection} = Rag.Pipelines.Chroma.get_or_create("rag")

    # path
    # |> list_elixir_files()
    # |> Enum.map(&%{source: &1})
    # |> Rag.Pipelines.ingest_bumblebee_text_embeddings_chroma(collection)
  end

  def query(query) do
    ## 1. custom with bumblebee + pgvector
    %{query: query}
    |> Rag.Embedding.Bumblebee.generate_embedding(:query, :query_embedding)
    # again, this is simply using ecto
    # this would probably live in a context
    |> query_with_pgvector()
    |> Rag.Generation.Bumblebee.generate_response()

    ## 2. bumblebee + pgvector
    # Rag.Pipelines.query_bumblebee_text_embeddings_pgvector(query, Repo)

    ## 3. openai + chroma
    # {:ok, collection} = Rag.Pipelines.Chroma.get_or_create("rag")
    # Rag.Pipelines.query_openai_with_bumblebee_text_embeddings_chroma(query, collection)
  end

  defp to_chunk(input) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    input
    |> Map.take([:document, :source, :chunk, :embedding])
    |> Map.put_new(:inserted_at, now)
    |> Map.put_new(:updated_at, now)
  end

  defp query_with_pgvector(%{query_embedding: query_embedding} = input, limit \\ 3) do
    results =
      Repo.all(
        from(c in "chunks",
          select: %{document: c.document, source: c.source, chunk: c.chunk},
          order_by: l2_distance(c.embedding, ^Pgvector.new(query_embedding)),
          limit: ^limit
        )
      )

    Map.put(input, :query_results, results)
  end
end
