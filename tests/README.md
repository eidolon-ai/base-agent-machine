# Testing your AgentMachine

Testing with LLMs is notoriously difficult. However, we have made that a little easier with Eidolon.

Within `conftst.py` you can see we have added a fixture to run your server in the background and manage state between tests.

What's more, we have also added some fixtures that will make LLM requests deterministic. That means you can use VCR to record and replay your tests.

This gives us the following benefits:
* Fast
* Deterministic
* No token needed to rerun (locally or in in CI/CD)

## Writing Tests
You can write tests using the standard Eidolon client. To record with VCR, just add the `@pytest.mark.vcr()` decorator.

Here is an example:

```python
import pytest
from eidolon_ai_client.client import Agent


@pytest.fixture
def agent():
    return Agent.get("hello-world")


@pytest.mark.vcr()
async def test_agent(agent: Agent):
    process = await agent.create_process()
    response = await process.action("converse", "Hi! What is the capital of France?")
    assert "paris" in response.data.lower()
```

> _Note: While iterating on a test, deleting VCR cassette files wastes time. Consider only adding the vcr decorator when you have finished the test to speed up your workflow._

## Recording Tests
The first time you run your tests, you will need to record them. This means you will need your LLM token set locally as 
an envar. See [How to Authenticate](https://www.eidolonai.com/docs/howto/authenticate_llm) for more details.

When you run the test, you will see a new file in the `tests/cassettes` directory. This is the recording of your test.

## Re-Recording Tests
If you need to change a test, but have already recorded it, you can re-record the cassette by deleting the existing file.
