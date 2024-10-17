defmodule ExRagTime.Repo do
  use Ecto.Repo,
    otp_app: :ex_rag_time,
    adapter: Ecto.Adapters.SQLite3
end
