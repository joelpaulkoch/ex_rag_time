defmodule ExRagTime.Ingestion do
  alias ExRagTime.Repo

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

    for {{embedding, document, source}, _i} <-
          Enum.with_index(Enum.zip([embeddings, documents, ids])) do
      %{embedding: embedding} = embedding
      embedding = Nx.to_list(embedding)

      code_chunk = %ExRagTime.CodeChunk{
        document: document,
        source: source,
        metadata: "",
        embedding: embedding
      }

      Repo.insert(code_chunk)
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
