require "bundler/setup"
require_relative "init_autoloader"

Opus::Initialize.init

3.times do
  streaming_response = Opus::DeveloperAi::Private::LlmProxyClient.begin_streaming_chat_completion(
    model: 'GPT_5',
    messages: [Opus::DeveloperAi::Structs::ChatCompletionMessage.new(
      role: Opus::DeveloperAi::Structs::ChatCompletionMessage::Role::User,
      content: 'Write a haiku about OpenAI.' 
    )],
    params: Opus::DeveloperAi::Structs::StreamingChatCompletionParams.new(temperature: 1.0),
    project: Opus::DeveloperAi::Structs::Project::Experiments
  )

  buffer = Opus::DeveloperAi::Eval::Utils.get_response_from_conversation(streaming_response.conversation_id)
end
