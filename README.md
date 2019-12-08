# This is a tutorial on how to run Django with Docker

Includes:
- django application
- nginx as webserver (static content)
- celery 
- best practices for development (fast-dev + debug)
- Dockerfile best practices


# Workshop

1. Setup VirtualEnv and install Django
    ```
    virtualenv -p $(which python3) venv
    . ./venv/bin/activate
    pip install "Django>=3.0,<4"
    ```
1. Create django project and initial setup
    ```
    django-admin startproject django_demo .
    python django_demo/manage.py makemigrations
    python django_demo/manage.py migrate
    python django_demo/manage.py createsuperuser --username admin --email ""
    ```
    You may test it with `python django_demo/manage.py runserver 0.0.0.0:8000` and open the browser at http://120.0.0.1:8000
1. Setup a first draft of a Dockerfile, so we can see what is bad in this draft
    ```Dockerfile
    FROM python
    COPY django_demo/ /app/
    RUN pip install "Django>=3.0,<4"
    ENV PYTHONUNBUFFERED=1
    CMD python /app/manage.py runserver 0.0.0.0:8000
    ```
    and test it
    ```
    docker build -t django-docker-demo .
    docker run -it --rm -p8000:8000 django-docker-demo
    ``` 

    build for the first time: 2:18<br>
    build after minor change: 0:22

    problems:
    * COPY files before 
    * use docker images tags (alpine if possible)
    * beware of context (.dockerignore)

1. Fix problems in Dockerfile
    ```Dockerfile
    FROM python:3.7-alpine
    RUN pip install "Django>=3.0,<4"
    COPY django_demo/ /app/
    ENV PYTHONUNBUFFERED=1
    CMD python /app/manage.py runserver 0.0.0.0:8000
    ```
    and `.dockerignore`
    ```
    venv/
    __pycache__/
    db.sqlite3
    ```
    From `Sending build context to Docker daemon  42.42MB` to `...156.7kB`

    build for the first time: 1:37<br>
    build after minor change: 0:03
1. Let's create our own Django content
    create `django_demo/django_demo/views.py`
    ```python
    import os
    from django.http import HttpResponse

    def hello_world(request):
        output_string = "<h1>Hello People from {}".format(os.environ.get("HOSTNAME", "no_host"))
        return HttpResponse(output_string)
    ```
    change `django_demo/django_demo/urls.py`
    ```python
    from django.contrib import admin
    from django.urls import path
    from . import views

    urlpatterns = [
        path('admin/', admin.site.urls),
        path('', views.hello_world),
    ]
    ```

1. Dispite the fast building time, I don't want to rebuild+restart every time I change something
    add volume on docker run
    ```
    docker run -it --rm -p8000:8000 -v "$(pwd)/django_demo/:/app/" django-docker-demo
    ``` 

    now, every time you change some file, django wil reload itself. Very useful for developmemt.
1. Let's add some more dependencies: Celery (**This is a major step**)

    We are going to use Redis as a message broker, for simplicity

    - Install Celery 
        (as we are getting more dependencies, let's keep a `requirements.txt`)
        ```
        Django>=3.0,<4
        Celery>=4.3.0,<4.4
        redis>=3.3<3.4
        ```
        and update `Dockerfile` (now we don't need to update this with every dependency change)
        ```
        FROM python:3.7-alpine

        COPY django_demo/requirements.txt /app/requirements.txt
        RUN pip install -r /app/requirements.txt
        COPY django_demo/ /app/

        ENV PYTHONUNBUFFERED=1
        WORKDIR /app

        CMD python /app/manage.py runserver 0.0.0.0:8000
        ```
    - Create a `docker-compose.yml` so we can keep 3 running services: django + redis + celery_worker
        ```
        version: "2"
        services:
            django:
                image: django-docker-demo
                ports:
                    - 8000:8000
                volumes:
                    - ./django_demo/:/app/
            celery-worker:
                image: django-docker-demo
                volumes:
                    - ./django_demo/:/app/
                command: "celery -A django-worker.tasks worker --loglevel=info"
            redis:
                image: redis
        ```
    - Update python code with a test

        create `django_demo/django_demo/tasks.py`
        ```python
        from celery import Celery
        import os
        app = Celery('tasks', broker='redis://redis:6379', backend='redis://redis:6379')

        @app.task
        def hello(caller_host):
            return "Hi {}! This is {}.".format(caller_host, os.environ.get("HOSTNAME", 'celery_worker_hostname'))
        ```
        add to `django_demo/django_demo/views.py`
        ```python
        from . import tasks
        def test_task(request):
            task = tasks.hello.delay(os.environ.get("HOSTNAME", "no_host"))
            output_string = task.get(timeout=1)
            return HttpResponse(output_string)
        ```
        update `django_demo/django_demo/urls.py`
        ```python
        urlpatterns = [
            path('admin/', admin.site.urls),
            path('', views.hello_world),
            path('task', views.test_task),
        ]
        ```
    - Finally, we can test our setup

        - run `docker-compose up` (you can see the logs and terminate with ctrl+c. to run in background, add `-d`)
        - open http://127.0.0.1:8000/task
