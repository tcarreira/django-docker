#!/usr/bin/env python
"""Django's command-line utility for administrative tasks."""
import os
import sys
from django.conf import settings


def main():
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "django_demo.settings")
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "Couldn't import Django. Are you sure it's installed and "
            "available on your PYTHONPATH environment variable? Did you "
            "forget to activate a virtual environment?"
        ) from exc

    if settings.DEBUG:
        if (  # as reload relauches itself, workaround for it
            "--noreload" not in sys.argv
            and os.environ.get("PTVSD_RELOAD", "no") == "no"
        ):
            os.environ["PTVSD_RELOAD"] = "yes"
        else:
            import ptvsd

            ptvsd.enable_attach()
            if os.environ.get("DEBUGGER_WAIT_FOR_ATTACH", False):
                ptvsd.wait_for_attach()

    execute_from_command_line(sys.argv)


if __name__ == "__main__":
    main()
