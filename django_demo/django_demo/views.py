import os
from django.http import HttpResponse
from . import tasks

def hello_world(request):
    output_string = "<h1>Hello People from {}".format(os.environ.get("HOSTNAME", "no_host"))
    return HttpResponse(output_string)

def test_task(request):
    task = tasks.hello.delay(os.environ.get("HOSTNAME", "no_host"))
    output_string = task.get(timeout=1)
    return HttpResponse(output_string)