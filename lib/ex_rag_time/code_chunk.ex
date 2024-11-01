defmodule ExRagTime.CodeChunk do
  use Ecto.Schema

  schema "code_chunks" do
    field :document, :string
    field :metadata, :string
    field :source, :string
    field :embedding, SqliteVec.Ecto.Float32

    timestamps()
  end
end
