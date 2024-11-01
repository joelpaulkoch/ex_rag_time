defmodule ExRagTime.Repo.Migrations.AddCodeChunksTable do
  use Ecto.Migration

  def change do
    create table(:code_chunks) do
      add :document, :text
      add :metadata, :text
      add :source, :text
      add :embedding, :binary

      timestamps()
    end
  end
end
