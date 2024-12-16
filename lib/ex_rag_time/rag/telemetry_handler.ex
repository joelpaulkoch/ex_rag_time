defmodule ExRagTime.Rag.TelemetryHandler do
  alias Phoenix.PubSub

  def handle_event(prefix, measurement, metadata, config) do
    # dbg({prefix, measurement, metadata, config})
    dbg(prefix)
    dbg(metadata)

    [:rag, key, event] = prefix

    PubSub.broadcast(ExRagTime.PubSub, "rag", {key, event})
  end
end
