# Tests

Run all tests:

```bash
bundle exec ruby -I tests -e 'Dir["tests/test_*.rb"].each { |f| require_relative f }'
```

Or with plain Ruby:

```bash
ruby -I lib -I tests -e 'Dir["tests/test_*.rb"].each { |f| require_relative f }'
```

Notes:
- Tests stub external services (IMAP, OpenAI) and use temporary directories/files.
- No real secrets are loaded; `Dotenv.load` is stubbed in `tests/test_helper.rb`.
