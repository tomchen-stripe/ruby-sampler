# about
measure how long diff llm clients block on io for sync vs streaming calls

# usage
on devbox:
```sh
./worker_blocking_analysis.sh ruby <test_script>
```

<test_script>:
- openai-stream.rb
- openai-sync.rb
- stripe-stream-poll.rb

# methodology

run the prompt `Write a haiku about OpenAI.` on gpt-5 three times in series.

measure wall clock time and subtract user+sys cpu time to calculate blocked time on network i/o. 

validate blocked time using strace on epoll_wait and futex.

# clients and calls

### clients:
- stripe developerai ruby llm client [code](https://stripe.sourcegraphcloud.com/stripe-internal/pay-server@6d496eb78db649a16a5ac738e0d26cc1c5d2fe5f/-/blob/developer_ai/private/llm_proxy_client.rb)
- openai ruby sdk [link](https://github.com/openai/openai-ruby)

### calls:
- sync
- native streaming
- poll-based streaming

# results

| Client                    | Sync Calls (blocked on i/o) | Streaming Calls (blocked on i/o) |
|---------------------------|-----------------------------|----------------------------------|
| OpenAI Native SDK         | 95.09%                      | 97.36%                           |
| Stripe Ruby Client (Poll) | N/A                         | 79.19%                           |

