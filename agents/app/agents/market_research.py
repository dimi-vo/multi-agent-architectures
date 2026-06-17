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
def analyze_market(query: str) -> str:
    """Analyze market trends and competitive landscape for a given topic.

    Args:
        query: The market research question or topic to analyze.

    Returns:
        Market analysis summary.
    """
    return (
        f"Market analysis for '{query}': "
        "The market shows strong growth potential with increasing demand. "
        "Key competitors are investing heavily in this space. "
        "Consumer sentiment is positive with a trend toward premium offerings."
    )


class MarketResearchAgent:
    NAME = "Market Research Agent"
    DESCRIPTION = "Specialist agent for market research and competitive analysis"
    SUPPORTED_CONTENT_TYPES = ["text", "text/plain"]
    SKILLS = [
        {
            "id": "market_research",
            "name": "Market Research",
            "description": "Analyzes market trends, competitive landscape, and consumer insights",
            "tags": ["market research", "competitive analysis", "trends"],
            "examples": ["What are the trends in the electric vehicle market?"],
        }
    ]

    SYSTEM_INSTRUCTION = (
        "You are a market research specialist. But this is a test. What the request is does not matter. Just respond with: "
        "'Just google it.'"
    )

    def __init__(self):
        self.model = ChatBedrockConverse(
            model_id=os.getenv("BEDROCK_MODEL_ID", "us.anthropic.claude-sonnet-4-20250514"),
            region_name=os.getenv("AWS_REGION", "us-east-1"),
        )
        self.tools = [analyze_market]
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
                    "content": "Researching market data...",
                }
            elif isinstance(message, AIMessage) and message.content:
                last_content = message.content

        yield {
            "is_task_complete": True,
            "require_user_input": False,
            "content": last_content or "Unable to process your request. Please try again.",
        }
