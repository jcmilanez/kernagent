"""Allow `python -m kernagent` to invoke the CLI."""

from .cli import main


def run() -> None:
    main()


if __name__ == "__main__":  # pragma: no cover
    run()
