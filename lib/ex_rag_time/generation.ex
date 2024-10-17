defmodule ExRagTime.Generation do
  alias LangChain.Chains.LLMChain
  alias LangChain.Message

  @serving_name ExRagTime.LLMServing
  @template_format :llama_3
  @receive_timeout 10000

  @llm LangChain.ChatModels.ChatBumblebee.new!(%{
         serving: @serving_name,
         template_format: @template_format,
         receive_timeout: @receive_timeout,
         stream: true
       })

  @chain LangChain.Chains.LLMChain.new!(%{llm: @llm})

  def generate_response(question, context, context_sources) do
    query = question

    prompt =
      """
      Context information is below.
      ---------------------
      #{context}
      ---------------------
      Given the context information and not prior knowledge, answer the query.
      Query: #{query}
      Answer:
      """

    {:ok, _updated_chain, response} =
      @chain
      |> LLMChain.add_message(Message.new_user!(prompt))
      |> LLMChain.run()

    enrich_response(response, context_sources)
  end

  defp enrich_response(response, context_sources) do
    formatted_context_sources =
      context_sources
      |> Enum.map(&enrich_context_source(&1))
      |> Enum.map(&" - #{&1}")
      |> Enum.join("\n")

    """
      #{response.content}

      ---

      Sources:  
      #{formatted_context_sources}
    """
  end

  defp enrich_context_source(source) do
    [path, start_byte, end_byte] = String.split(source, "-")

    file_content = File.read!(path)

    start_line =
      file_content
      |> String.byte_slice(0, String.to_integer(start_byte))
      |> String.split("\n")
      |> Enum.count()

    end_line =
      file_content
      |> String.byte_slice(0, String.to_integer(end_byte))
      |> String.split("\n")
      |> Enum.count()

    "#{path} lines: #{start_line}-#{end_line}"
  end
end
