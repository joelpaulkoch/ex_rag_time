defmodule ExRagTime.Repo.Migrations.AddEmbeddingsTable do
  use Ecto.Migration

  def up do
    execute(
      "create virtual table embeddings using vec0( sample_embedding float[384], id INTEGER PRIMARY KEY);"
    )

    execute(
      "create table chunks( id INTEGER PRIMARY KEY, document TEXT, metadata TEXT, source TEXT)"
    )
  end
end
