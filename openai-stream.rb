require "bundler/setup"
require "openai"

openai = OpenAI::Client.new(
  api_key: "use_case=development&team=developer-ai",
  base_url: "http://litellm-srv.service.envoy:10080/v1"
)

3.times do
    stream = openai.responses.stream(
    input: "Write a haiku about OpenAI.",
    model: :"gpt-5"
    )

    events = []
    stream.each do |event|
        events << event
    end
end
