import json
from pathlib import Path

from confluent_kafka import SerializingProducer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer

TOPIC = "marketing_event"
SUBJECT = "marketing_event-value"
PROPERTIES_FILE = Path(__file__).parent / "producer.properties"
MESSAGES_FILE = Path(__file__).parent / "messages.json"

SR_CONFIG_KEYS = frozenset({
    "schema.registry.url",
    "basic.auth.credentials.source",
    "basic.auth.user.info",
})


def load_properties(path: Path) -> dict[str, str]:
    props: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, _, value = line.partition("=")
        props[key.strip()] = value.strip()
    return props


def split_config(props: dict[str, str]) -> tuple[dict[str, str], dict[str, str]]:
    sr_config: dict[str, str] = {}
    kafka_config: dict[str, str] = {}
    for key, value in props.items():
        if key in SR_CONFIG_KEYS:
            sr_config[key] = value
        else:
            kafka_config[key] = value
    sr_conf = {"url": sr_config["schema.registry.url"]}
    if "basic.auth.user.info" in sr_config:
        sr_conf["basic.auth.user.info"] = sr_config["basic.auth.user.info"]
    return kafka_config, sr_conf


def delivery_callback(err, msg) -> None:
    if err is not None:
        print(f"DELIVERY FAILED for {msg.key()}: {err}")
    else:
        print(f"Delivered to {msg.topic()} [{msg.partition()}] @ offset {msg.offset()}")


def main() -> None:
    props = load_properties(PROPERTIES_FILE)
    kafka_config, sr_config = split_config(props)

    sr_client = SchemaRegistryClient(sr_config)

    avro_serializer = AvroSerializer(
        schema_registry_client=sr_client,
        schema_str=None,
        conf={"use.latest.version": True, "auto.register.schemas": False, "subject.name.strategy": lambda ctx, rn: SUBJECT},
    )

    producer_config = {
        **kafka_config,
        "value.serializer": avro_serializer,
    }

    messages: list[dict[str, str]] = json.loads(MESSAGES_FILE.read_text())

    producer = SerializingProducer(producer_config)
    for entry in messages:
        producer.produce(topic=TOPIC, key=entry["key"], value={"message": entry["message"]}, on_delivery=delivery_callback)
    producer.flush()


if __name__ == "__main__":
    main()
