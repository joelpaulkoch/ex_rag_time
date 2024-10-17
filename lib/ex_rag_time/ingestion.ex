defmodule ExRagTime.Ingestion do
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
    Nx.Serving.batched_run(ExRagTime.EmbeddingsServing, Enum.map(chunks, & &1.text))
  end

  def store_embeddings_and_chunks(embeddings, chunks) do
    documents = Enum.map(chunks, & &1.text)
    ids = Enum.map(chunks, &"#{&1.source}-#{&1.start_byte}-#{&1.end_byte}")

    for {{embedding, document, source}, i} <-
          Enum.with_index(Enum.zip([embeddings, documents, ids])) do
      dbg(embedding)
      %{embedding: embedding} = embedding
      embedding = Nx.to_list(embedding)
      embedding_string = "[" <> Enum.join(embedding, "") <> "]"

      Ecto.Adapters.SQL.query(
        ExRagTime.Repo,
        "insert into embeddings(id, sample_embedding) values(?, ?)",
        [i, embedding_string]
      )

      Ecto.Adapters.SQL.query(
        ExRagTime.Repo,
        "insert into chunks(id, document, source) values(?, ?, ?)",
        [i, document, source]
      )
    end
  end

  def ingest(input_path) when is_binary(input_path) do
    if !input_path || input_path == "", do: raise("Empty input path")

    files =
      Path.wildcard(input_path <> "/**/*.{ex, exs}")
      |> Enum.filter(fn path ->
        not String.contains?(path, ["/_build/", "/deps/", "/node_modules/"])
      end)

    files_content = for file <- files, do: File.read!(file)

    ingest(
      Enum.zip_with(files, files_content, fn file, content ->
        %{content: content, source: file}
      end)
    )
  end

  def ingest(documents) when is_list(documents) do
    chunks = chunk_with_metadata(documents, :elixir)

    embeddings = generate_embeddings(chunks)

    store_embeddings_and_chunks(embeddings, chunks)
  end
end
