defmodule ExRagTime do
  @moduledoc """
  ExRagTime keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  def ingest(path), do: ExRagTime.Ingestion.ingest(path)

  def query(question) do
    {context, sources} = ExRagTime.Retrieval.retrieve(question)

    ExRagTime.Generation.generate_response(question, context, sources)
  end
end
