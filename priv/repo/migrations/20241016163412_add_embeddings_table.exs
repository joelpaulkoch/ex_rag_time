defmodule ExRagTime.Repo.Migrations.AddEmbeddingsTable do
  use Ecto.Migration

  ## 1. custom with bumblebee + pgvector
  def up() do
    execute("CREATE EXTENSION IF NOT EXISTS vector")

    flush()

    create table(:chunks) do
      add(:document, :text)
      add(:source, :text)
      add(:chunk, :text)
      add(:embedding, :vector, size: 768)

      timestamps()
    end
  end

  ## 2. Pipelines bumblebee + pgvector
  # def up, do: Rag.Pipelines.Pgvector.Migrations.up()

  # 1. custom with bumblebee + pgvector
  def down() do
    drop(table(:chunks))
    execute("DROP EXTENSION vector")
  end

  ## 2. Pipelines bumblebee + pgvector
  # def down, do: Rag.Pipelines.Pgvector.Migrations.down()
end
