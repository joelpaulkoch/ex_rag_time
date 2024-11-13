defmodule ExRagTime.Repo do
  use Ecto.Repo,
    otp_app: :ex_rag_time,
    adapter: Ecto.Adapters.Postgres
end
