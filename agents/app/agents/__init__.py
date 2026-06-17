from app.agents.market_research import MarketResearchAgent
from app.agents.creative_design import CreativeDesignAgent
from app.agents.copywriting import CopywritingAgent

AGENT_REGISTRY = {
    "market_research": MarketResearchAgent,
    "creative_design": CreativeDesignAgent,
    "copywriting": CopywritingAgent,
}
