defmodule ExRagTime.Repo.Migrations.AddChunksTable do
  use Ecto.Migration

  def up() do
    execute(
      "CREATE VIRTUAL TABLE chunks USING vec0(id INTEGER PRIMARY KEY, embedding float[384], document TEXT, source TEXT, chunk TEXT, inserted_at TEXT, updated_at TEXT)"
    )
  end

  def down() do
    drop(table("chunks"))
  end
end
