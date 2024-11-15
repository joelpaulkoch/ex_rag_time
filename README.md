# RAG in Elixir

1. Run `mix deps.get`.
2. Run `mix rag.install pgvector` to install dependencies and generate code to work with postgres/pgvector.
3. Have a look at the generate code
4. Run `mix phx.server` and use the system at `http://localhost:4000`

You can also try `mix rag.install sqlite_vec` or `mix rag.install chroma` to work with another vector store.
