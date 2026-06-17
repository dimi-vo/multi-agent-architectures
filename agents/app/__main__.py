import logging
import os
import signal
import subprocess
import sys

import click
import uvicorn
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.tasks import (
    InMemoryPushNotificationConfigStore,
    InMemoryTaskStore,
)
from a2a.server.routes.jsonrpc_routes import create_jsonrpc_routes
from a2a.server.routes.agent_card_routes import create_agent_card_routes
from a2a.types import AgentCapabilities, AgentCard, AgentInterface, AgentSkill
from dotenv import load_dotenv
from starlette.applications import Starlette

from app.agents import AGENT_REGISTRY
from app.agent_executor import GenericAgentExecutor

load_dotenv()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

AGENT_NAMES = list(AGENT_REGISTRY.keys())
DEFAULT_PORTS = {
    "market_research": 10001,
    "creative_design": 10002,
    "copywriting": 10003,
}


def start_agent(agent_name: str, host: str, port: int):
    agent_cls = AGENT_REGISTRY[agent_name]
    agent_instance = agent_cls()

    skills = [AgentSkill(**skill_def) for skill_def in agent_cls.SKILLS]

    public_url = os.getenv(f"A2A_PUBLIC_URL_{agent_name.upper()}") or os.getenv("A2A_PUBLIC_URL")

    interfaces = [
        AgentInterface(
            url=f"http://{host}:{port}/",
            protocol_binding="JSONRPC",
            protocol_version="0.3",
        ),
    ]
    if public_url:
        public_url = public_url.rstrip("/") + "/"
        interfaces.insert(0, AgentInterface(
            url=public_url,
            protocol_binding="JSONRPC",
            protocol_version="0.3",
        ))

    agent_card = AgentCard(
        name=agent_cls.NAME,
        description=agent_cls.DESCRIPTION,
        version="1.0.0",
        supported_interfaces=interfaces,
        default_input_modes=agent_cls.SUPPORTED_CONTENT_TYPES,
        default_output_modes=agent_cls.SUPPORTED_CONTENT_TYPES,
        capabilities=AgentCapabilities(streaming=True, push_notifications=True),
        skills=skills,
    )



    request_handler = DefaultRequestHandler(
        agent_executor=GenericAgentExecutor(agent_instance),
        task_store=InMemoryTaskStore(),
        agent_card=agent_card,
    )

    routes = create_agent_card_routes(agent_card) + create_jsonrpc_routes(request_handler, "/", enable_v0_3_compat=True)

    app = Starlette(routes=routes)

    logger.info(f"Starting {agent_cls.NAME} on {host}:{port}")
    uvicorn.run(app, host=host, port=port)


@click.command()
@click.option("--agent", type=click.Choice(AGENT_NAMES + ["all"]), required=True, help="Which agent to run, or 'all'")
@click.option("--host", default="localhost")
@click.option("--port", default=None, type=int, help="Port (defaults per agent: 10001-10004, ignored with 'all')")
def main(agent, host, port):
    if agent != "all":
        start_agent(agent, host, port or DEFAULT_PORTS[agent])
        return

    procs = []
    for name in AGENT_NAMES:
        p = subprocess.Popen(
            ["uv", "run", "app", "--agent", name, "--host", host, "--port", str(DEFAULT_PORTS[name])],
        )
        procs.append(p)
        logger.info(f"Launched {name} (pid {p.pid}) on port {DEFAULT_PORTS[name]}")

    def shutdown(*_):
        logger.info("Shutting down all agents...")
        for p in procs:
            p.terminate()
        for p in procs:
            try:
                p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                p.kill()

    signal.signal(signal.SIGINT, lambda *_: shutdown())
    signal.signal(signal.SIGTERM, lambda *_: shutdown())

    try:
        for p in procs:
            p.wait()
    except KeyboardInterrupt:
        shutdown()


if __name__ == "__main__":
    main()
