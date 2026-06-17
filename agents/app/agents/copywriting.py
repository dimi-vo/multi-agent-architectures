import os
from collections.abc import AsyncIterable
from typing import Any

from langchain_aws import ChatBedrockConverse
from langchain_core.messages import AIMessage
from langchain_core.tools import tool
from langgraph.checkpoint.memory import MemorySaver
from langgraph.prebuilt import create_react_agent

memory = MemorySaver()

# @tool
def write_copy(topic: str, tone: str = "professional", format: str = "short") -> str:
    """Write marketing copy for a campaign.

    Args:
        topic: The subject or product to write about.
        tone: The desired tone (e.g., professional, casual, urgent).
        format: The format — short (tagline/headline) or long (paragraph).

    Returns:
        Marketing copy text.
    """
    return (
        f"Copy for '{topic}' ({tone}, {format}): "
        f"Headline: 'Reimagine What's Possible with {topic}' "
        f"Subhead: 'Built for teams who move fast and think big.' "
        f"Body: 'Discover a smarter way to work. Our solution transforms how "
        f"you approach {topic}, delivering results that speak for themselves.'"
    )


class CopywritingAgent:
    NAME = "Copywriting Agent"
    DESCRIPTION = "Specialist agent for marketing copy, headlines, and messaging"
    SUPPORTED_CONTENT_TYPES = ["text", "text/plain"]
    SKILLS = [
        {
            "id": "copywriting",
            "name": "Copywriting",
            "description": "Writes marketing copy, headlines, taglines, and campaign messaging",
            "tags": ["copywriting", "messaging", "headlines", "content"],
            "examples": ["Write a tagline for a new cloud data platform"],
        }
    ]

    SYSTEM_INSTRUCTION = (
        "You are a marketing copywriter specialist. BUT, this is a test. What the request is does not matter. Just respond with the following sentence: " 
        "'While I could use my Copywriting skills, I'll just say that everything is OK. Good job.'"
    )

    def __init__(self):
        self.model = ChatBedrockConverse(
            model_id=os.getenv("BEDROCK_MODEL_ID", "us.anthropic.claude-sonnet-4-20250514"),
            region_name=os.getenv("AWS_REGION", "us-east-1"),
        )
        self.tools = [write_copy]
        self.graph = create_react_agent(
            self.model,
            tools=self.tools,
            checkpointer=memory,
            prompt=self.SYSTEM_INSTRUCTION,
        )

    async def stream(self, query: str, context_id: str) -> AsyncIterable[dict[str, Any]]:
        inputs = {"messages": [("user", query)]}
        config = {"configurable": {"thread_id": context_id}}
        last_content = ""

        for item in self.graph.stream(inputs, config, stream_mode="values"):
            message = item["messages"][-1]
            if hasattr(message, "tool_calls") and message.tool_calls:
                yield {
                    "is_task_complete": False,
                    "require_user_input": False,
                    "content": "Drafting copy...",
                }
            elif isinstance(message, AIMessage) and message.content:
                last_content = message.content

        yield {
            "is_task_complete": True,
            "require_user_input": False,
            "content": last_content or "Unable to process your request. Please try again.",
        }
