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
def generate_design_brief(campaign_theme: str, target_audience: str) -> str:
    """Generate a creative design brief for a marketing campaign.

    Args:
        campaign_theme: The theme or concept for the campaign.
        target_audience: The intended audience for the campaign.

    Returns:
        A creative design brief.
    """
    return (
        f"Design brief for '{campaign_theme}' targeting '{target_audience}': "
        "Visual direction: modern, bold typography with vibrant gradients. "
        "Color palette: primary brand blue (#1a73e8) with warm accent (#ff6d00). "
        "Key assets: hero banner (1920x1080), social cards (1080x1080), email header (600x200). "
        "Mood: confident, forward-looking, approachable."
    )


class CreativeDesignAgent:
    NAME = "Creative Design Agent"
    DESCRIPTION = "Specialist agent for creative design briefs and visual direction"
    SUPPORTED_CONTENT_TYPES = ["text", "text/plain"]
    SKILLS = [
        {
            "id": "creative_design",
            "name": "Creative Design",
            "description": "Generates creative design briefs, visual direction, and asset specifications",
            "tags": ["design", "creative", "visual", "branding"],
            "examples": ["Create a design brief for a summer product launch targeting millennials"],
        }
    ]

    SYSTEM_INSTRUCTION = (
        "You are a creative design specialist. But, this is a test. What the request is does not matter. Just respond with the following sentence: "
        "'I don't feel very creative today. Sorry.'"
    )

    def __init__(self):
        self.model = ChatBedrockConverse(
            model_id=os.getenv("BEDROCK_MODEL_ID", "us.anthropic.claude-sonnet-4-20250514"),
            region_name=os.getenv("AWS_REGION", "us-east-1"),
        )
        self.tools = [generate_design_brief]
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
                    "content": "Generating design brief...",
                }
            elif isinstance(message, AIMessage) and message.content:
                last_content = message.content

        yield {
            "is_task_complete": True,
            "require_user_input": False,
            "content": last_content or "Unable to process your request. Please try again.",
        }
