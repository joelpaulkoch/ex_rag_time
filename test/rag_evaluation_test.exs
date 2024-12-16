defmodule RagEvaluationTest do
  use ExRagTime.DataCase

  @tag timeout: :infinity
  test "RAG Triad" do
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

    answers =
      for question <- data["question"] do
        ExRagTime.Rag.query(question)
      end
      |> dbg

    RagEvaluation.EndToEnd.evaluate_triad(data, answers)
  end
end
