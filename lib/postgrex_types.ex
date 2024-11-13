## 2. bumblebee + pgvector
Postgrex.Types.define(
  ExRagTime.PostgrexTypes,
  [Pgvector.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(),
  []
)
