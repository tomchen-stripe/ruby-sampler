require "bundler/setup"
require "openai"

openai = OpenAI::Client.new(
  api_key: "use_case=development&team=developer-ai",
  base_url: "http://litellm-srv.service.envoy:10080/v1"
)

3.times do
  response = openai.responses.create(
    input: "Write a haiku about OpenAI.",
    model: :"gpt-5"
  )
end
