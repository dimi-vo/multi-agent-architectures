import logging

from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.tasks import TaskUpdater
from a2a.types import (
    Message,
    Part,
    Role,
    Task,
    TaskState,
    TaskStatus,
)
from a2a.utils.errors import (
    A2AError,
    InternalError,
    InvalidParamsError,
    UnsupportedOperationError,
)

logger = logging.getLogger(__name__)


def _agent_message(text: str) -> Message:
    return Message(role=Role.ROLE_AGENT, parts=[Part(text=text)])


class GenericAgentExecutor(AgentExecutor):

    def __init__(self, agent):
        self.agent = agent

    async def execute(
        self,
        context: RequestContext,
        event_queue: EventQueue,
    ) -> None:
        query = context.get_user_input()
        if not query:
            raise InvalidParamsError()

        task = Task(
            id=context.task_id,
            context_id=context.context_id,
            status=TaskStatus(state=TaskState.TASK_STATE_SUBMITTED),
        )
        await event_queue.enqueue_event(task)

        updater = TaskUpdater(event_queue, context.task_id, context.context_id)

        try:
            async for item in self.agent.stream(query, context.context_id):
                is_complete = item["is_task_complete"]
                needs_input = item["require_user_input"]

                if not is_complete and not needs_input:
                    await updater.update_status(
                        TaskState.TASK_STATE_WORKING,
                        _agent_message(item["content"]),
                    )
                elif needs_input:
                    await updater.update_status(
                        TaskState.TASK_STATE_INPUT_REQUIRED,
                        _agent_message(item["content"]),
                    )
                    break
                else:
                    await updater.add_artifact(
                        [Part(text=item["content"])],
                        name="result",
                    )
                    await updater.complete()
                    break

        except Exception as e:
            logger.error(f"Error streaming response: {e}")
            raise InternalError() from e

    async def cancel(self, context: RequestContext, event_queue: EventQueue) -> None:
        raise UnsupportedOperationError()
