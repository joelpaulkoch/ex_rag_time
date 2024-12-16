data =
  Req.get!(
    "https://huggingface.co/datasets/explodinggradients/amnesty_qa/resolve/main/english.json"
  ).body
  |> Jason.decode!()

data["contexts"]
|> Enum.map(&Enum.join(&1, " "))
|> Enum.with_index(&%{document: &1, source: "#{&2}"})
|> ExRagTime.Rag.index()
|> dbg

rag_states = [ExRagTime.Rag.query(Enum.at(data["question"], 0))] |> dbg

for question <- data["question"] do
  ExRagTime.Rag.query(question)
end

openai_params = %{
  model: "gpt-4o-mini",
  api_key: "key"
}

rag_states =
  for state <- rag_states do
    Rag.Evaluation.OpenAI.evaluate_rag_triad(state, openai_params)
  end

json =
  Enum.at(rag_states, 0)
  |> Map.take([:query, :context, :response, :evaluation])
  |> Jason.encode!()

File.write!(Path.join(__DIR__, "triad_eval.json"), json)
