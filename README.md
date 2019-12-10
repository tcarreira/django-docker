# This is a tutorial on how to run Django with Docker

### TOC

1. Start a Django project (from scratch)
1. Setup Docker
1. Testing Django
1. Docker volumes for development
1. Docker-compose - a simple multi-container orchestration tool
1. Debugging a Django application
1. Improve `Dockerfile` and other thing...
1. Test it all together
1. Last notes

### Includes:

- django
- celery 
- docker
    - best practices for development 
    - best practices for Dockerfile 
    - volumes for fast development
- debugging
- some production best practices
    - do not run as root
    - use gunicorn and serve static content
    - small docker image
    - environemnt variables


### Previous notes

- This tutorial comes along with this presentation: 
    - http://tcarreira.github.io/presentations/django-docker 
    - ([also in portuguese - PT](http://tcarreira.github.io/presentations/django-docker/pt.html))

- Development best practices 

    What do you need to develop? (not an exaustive list)
    
    | tool | what for | example |
    | --- | --- | --- |
    | a good IDE | auto-completion, debugging  | vscode |
    | good IDE plugins | framework specifics (django) | `ms-python.python`,<br>`batisteo.vscode-django` |
    | linter | you need to have a real-time feedback about what is wrong | mypy |
    | formatter | it's great for code sharing | black |
    | unit tests | you should really not test your code. Make your computer do it | pytest |
    | code-to-execution | low latency after writing your code until it gets executed | manage.py runserver |



# Workshop

1. Start a Django project (from scratch)
    - Setup VirtualEnv and install Django
        ```
        virtualenv -p $(which python3) venv
        . ./venv/bin/activate
        pip install "Django>=3.0,<4"
        ```
    - Create django project and initial setup
        ```
        django-admin startproject django_demo .
        python django_demo/manage.py makemigrations
        python django_demo/manage.py migrate
        python django_demo/manage.py createsuperuser --username admin --email ""
        ```
        You may test it with `python django_demo/manage.py runserver 0.0.0.0:8000` and open the browser at http://127.0.0.1:8000
    
1. Setup Docker

    - Install Docker

        - Do NOT install from apt-get: very outdated (almost useless)
        - Windows - Docker Desktop
            - https://docs.docker.com/docker-for-windows/install/
        - Mac - Docker Desktop
            - https://docs.docker.com/docker-for-mac/install/
        - Linux
            - Brain dead easy way: `wget -qO- https://get.docker.com | sh`
            - Other way: https://docs.docker.com/install/

    - Setup a first draft of a Dockerfile, so we can see what is bad in this draft
        ```Dockerfile
        FROM python
        COPY django_demo/ /app/
        RUN pip install --no-cache-dir "Django>=3.0,<4"
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
        - COPY files before pip install
        - use docker images tags (alpine if possible)
        - beware of context (.dockerignore)

    - Identify some problems in Dockerfile
        ```Dockerfile
        FROM python:3.7-alpine
        RUN pip install --no-cache-dir "Django>=3.0,<4"
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

1. Testing Django

    Let's create our own Django content

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

1. Docker volumes for development

    Dispite the fast building time, I don't want to rebuild+restart every time I change something
    
    add volume on docker run
    ```
    docker run -it --rm -p8000:8000 -v "$(pwd)/django_demo/:/app/" django-docker-demo
    ``` 

    now, every time you change some file, django wil reload itself. Very useful for developmemt.

1. Docker-compose - a simple multi-container orchestration tool

    Let's add some more dependencies: Celery (**This is a major step**)

    Celery depends on a message broker, and we are going to use Redis, for simplicity

    - Install Celery and Redis client

        (as we are getting more dependencies, let's keep a `requirements.txt`)
        ```Dockerfile
        Django>=3.0,<4
        Celery>=4.3.0,<4.4
        redis>=3.3<3.4
        ```
        and update `Dockerfile` (now we don't need to update this with every dependency change)
        ```Dockerfile
        FROM python:3.7-alpine

        COPY django_demo/requirements.txt /app/requirements.txt
        RUN pip install --no-cache-dir -r /app/requirements.txt
        COPY django_demo/ /app/

        ENV PYTHONUNBUFFERED=1
        WORKDIR /app

        CMD python /app/manage.py runserver 0.0.0.0:8000
        ```
    - Create a `docker-compose.yml` so we can keep 3 running services: django + redis + celery_worker
        ```yaml
        version: "3.4"
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
            output_string = task.get(timeout=5)
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

        - build docker image: `docker build -t django-docker-demo .`
        - run `docker-compose up` (you can see the logs and terminate with ctrl+c. to run in background, add `-d`)
        - open http://127.0.0.1:8000/task


    Now that things got a little confusing, it gets worse.


    <br><br>
    *do you remeber some development best practices?*

1. Debugging a Django application

    example with vscode, which uses ptvsd for debugging, `.vscode/launch.json`
    ```json
    { 
        "version": "0.2.0",
        "configurations": [
            {
                "name": "Python: Current File",
                "type": "python",
                "request": "launch",
                "program": "${file}",
            }, 
            {
                "name": "Python: Debug Django",
                "type": "python",
                "request": "launch",
                "program": "${workspaceFolder}/django_demo/manage.py",
                "args": [
                    "runserver",
                    "--nothreading"
                ],
                "subProcess": true,
            }
        ]
    }
    ```

    The first one is good enough for python scripts, but not so nice for django applications.
    The second one is very good, but it runs locally (no docker)

    or...

    - You could be running a debugger with docker

        - change the `Dockerfile` in order to include `requirements-dev.txt` instead of `requirements.txt` (we need development tools for debugging) and some other dependencies
            ```dockerfile
            FROM python:3.7-alpine

            RUN apk add --update --no-cache \
                    bash \
                    build-base

            COPY django_demo/requirements-dev.txt /app/requirements.txt
            RUN pip install --no-cache-dir -r /app/requirements.txt
            COPY django_demo/ /app/

            ENV PYTHONUNBUFFERED=1
            WORKDIR /app

            CMD python /app/manage.py runserver 0.0.0.0:8000
            ```
            and build it again 
            ```
            docker build -t django-docker-demo .
            ```
        - expose port 5678 on django service inside `docker-compose.yml`
            ```yaml
            version: "3.4"
            services:
                django:
                    image: django-docker-demo:latest
                    ports:
                        - "8000:8000"
                        - "5678:5678"
                    volumes:
                        - "./django_demo/:/app/"
                celery-worker:
                    image: django-docker-demo:latest
                    volumes:
                        - "./django_demo/:/app/"
                    command: "celery -A django_demo.tasks worker --loglevel=info"
                redis:
                    image: redis:5.0-alpine
            ```
        - modify `django_demo/manage.py` (add it inside main, before `execute_from_command_line(sys.argv)`)
            ```python
            from django.conf import settings
            if settings.DEBUG:
                if (  # as reload relauches itself, workaround for it
                    "--noreload" not in sys.argv
                    and os.environ.get("PTVSD_RELOAD", "no") == "no"
                ):
                    os.environ["PTVSD_RELOAD"] = "yes"
                else:
                    import ptvsd
                    ptvsd.enable_attach()
            ```
        - add a remote debugger on your IDE. For vscode add a configuration to `.vscode/launch.json`
            ```json
            {
                "name": "Python: Debug Django attach Docker",
                "type": "python",
                "request": "attach",
                "localRoot": "${workspaceFolder}/django_demo",
                "remoteRoot": "/app",
                "host": "127.0.0.1",
                "port": 5678,
            },
            ```
        - and test it
            ```
            docker-compose up
            ```
            After adding a breakpoint inside `django_demo.views.hello_world()` reload your browser.

1. Improve `Dockerfile` and other thing...

    **note**: this list is not fully comprehensive.<br> 
    You may clone the code with everying with `git clone https://github.com/tcarreira/django-docker.git`

    - do not run as root.
        ```Dockerfile
        RUN adduser -D user
        USER user
        ```
    - remove unnecessary dependencies. Keep different images for different uses (use multi-stage builds)
        ```Dockerfile
        FROM python:3.7-alpine AS base
        ...
        FROM base AS dev
        ...
        FROM base AS final
        ...
        ```
    - clean your logs
        ```yaml
        services:
            app:
                ...
                logging:
                    options:
                        max-size: "10m"
                        max-file: "3"
        ```
        or shorter:
        ```yaml
                logging: { options: { max-size: "10m", max-file: "3" } }
        ```
    - next level caching (with Buildkit `DOCKER_BUILDKIT=1`) - https://github.com/moby/buildkit
        ```Dockerfile
        # syntax=docker/dockerfile:experimental
        ...
        ENV HOME /app
        WORKDIR /app
        RUN --mount=type=cache,uid=0,target=/app/.cache/pip,from=base \
            pip install -r requirements.txt
        ```
        **note**: `# syntax=docker/dockerfile:experimental` on the first line of your `Dockerfile` is mandatory for using BUILDKIT new features
    - quality as part of the pipeline
        ```Dockerfile
        FROM dev AS qa
        RUN black --target-version=py37 --check --diff . 
        RUN mypy --python-version=3.7 --pretty --show-error-context .
        RUN coverage run django_demo/manage.py test
        RUN django_demo/manage.py check --deploy --fail-level WARNING
        ```

    - Prepare Django for production
        - Prepare Django for production - https://docs.djangoproject.com/en/3.0/howto/deployment/checklist/ (out of the scope for this)
        - Use a decent webserver <br>
            > from: https://docs.djangoproject.com/en/3.0/ref/django-admin/#runserver <br>
            DO NOT USE THIS SERVER IN A PRODUCTION SETTING. It has not gone through security audits or performance tests. 
            (And that’s how it’s gonna stay. We’re in the business of making Web frameworks, not Web servers, 
            so improving this server to be able to handle a production environment is outside the scope of Django.)
            
            and  build static files (you will need it for the new webserver)
            ```Dockerfile
            FROM dev AS staticfiles
            RUN python manage.py collectstatic --noinput

            FROM nginx:1.17-alpine
            COPY conf/nginx.conf /etc/nginx/conf.d/default.conf
            COPY --from=staticfiles /app/static /staticfiles/static
            ```
            and create the corresponding `conf/nginx.conf` (just a minimal example. Don't use in production)
            ```
            server {
                listen 80 default_server;
                server_name _;

                location /static {
                    root /staticfiles;
                }

                location / {
                    proxy_pass http://django:8000;
                }
            }
            ```
        - you probably want to use a different database

            add to your `docker-compose.yml`
            ```yaml
                db:
                    image: mariadb:10.4
                    restart: always
                    environment:
                        MYSQL_DATABASE: "django"
                        MYSQL_USER: "user"
                        MYSQL_PASSWORD: "pass"
                        MYSQL_RANDOM_ROOT_PASSWORD: "yes"
                    volumes:
                        - django-db:/var/lib/mysql
            ```
            and configure your `django_demo/django_demo/settings.py`
            ```python
            # If database is defined, overrides the default
            if (
                os.environ.get("DJANGO_DB_HOST")
                and os.environ.get("DJANGO_DB_DATABASE")
                and os.environ.get("DJANGO_DB_USER")
                and os.environ.get("DJANGO_DB_PASSWORD")
            ):
                DATABASES["default"] = {
                    "ENGINE": "django.db.backends.mysql",
                    "NAME": os.environ.get("DJANGO_DB_DATABASE", ""),
                    "USER": os.environ.get("DJANGO_DB_USER", ""),
                    "PASSWORD": os.environ.get("DJANGO_DB_PASSWORD", ""),
                    "HOST": os.environ.get("DJANGO_DB_HOST", ""),
                    "PORT": os.environ.get("DJANGO_DB_PORT", "3306"),
                }
            ```
     
        - build a common entrypoint (so you don't have to change dockerfile later)
            ```bash
            #!/bin/bash

            # wait until database is ready
            if [[ ${DJANGO_DB_HOST} != "" ]]; then
                while !</dev/tcp/${DJANGO_DB_HOST}/${DJANGO_DB_PORT:-3306} ; do 
                    sleep 1;
                    [[ $((counter++)) -gt 60 ]] && break
                done
            fi

            python manage.py migrate

            case $DJANGO_DEBUG in
                true|True|TRUE|1|YES|Yes|yes|y|Y)
                    echo "================= Starting debugger =================="
                    python manage.py runserver 0.0.0.0:8000
                    ;;
                *)
                    gunicorn --worker-class gevent -b 0.0.0.0:8000 django_demo.wsgi
                    ;;
            esac
            ```

1. Test it all together

    **note**: now it's a good time for `git clone https://github.com/tcarreira/django-docker.git`

    Update your docker-compose
    `docker-compose.yml`
    ```
    version: "3.4"
    services:
        webserver:
            image: django-docker-demo:webserver
            build:
                dockerfile: Dockerfile
                target: webserver
                context: .
            ports:
                - 8080:80
            logging: { options: { max-size: "10m", max-file: "3" } }
        django:
            image: django-docker-demo:dev
            build:
                dockerfile: Dockerfile
                target: dev
                context: .
            ports:
                - 8000:8000
                - 5678:5678
            volumes:
                - ./django_demo/:/app/
            environment:
                DJANGO_DEBUG: "y"
                DJANGO_DB_HOST: "db"
                DJANGO_DB_DATABASE: "django"
                DJANGO_DB_USER: "djangouser"
                DJANGO_DB_PASSWORD: "djangouserpassword"
            logging: { options: { max-size: "10m", max-file: "3" } }

        celery-worker:
            image: django-docker-demo:latest
            build:
                dockerfile: Dockerfile
                context: .
            volumes:
                - ./django_demo/:/app/
            command: "celery -A django_demo.tasks worker --loglevel=info"
            logging: { options: { max-size: "10m", max-file: "3" } }

        redis:
            image: redis:5.0-alpine
            logging: { options: { max-size: "10m", max-file: "3" } }
        
        db:
            image: mariadb:10.4
            restart: always
            environment:
                MYSQL_DATABASE: "django"
                MYSQL_USER: "djangouser"
                MYSQL_PASSWORD: "djangouserpassword"
                MYSQL_RANDOM_ROOT_PASSWORD: "yes"
            volumes:
                - django-db:/var/lib/mysql
            logging: { options: { max-size: "10m", max-file: "3" } }

    volumes:
        django-db:
    ```

    and run 
    ```
    DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1 docker-compose up --build
    ```

    **note**: you need docker-compose >= 1.25 in order to use builkit directly. If you don't have it, build images first, then docker-compose 


1. Last notes

    - keep separate `docker-compose.qa.yml` for testing/qa with final images
    ```yaml
    version: "3.4"
    services:
        webserver:
            image: django-docker-demo:webserver
            ports:
                - 80:80
            logging: { options: { max-size: "10m", max-file: "3" } }
                
        django:
            image: django-docker-demo:latest
            environment:
                DJANGO_DEBUG: "false"
                DJANGO_SECRET_KEY: "AVhqJxkBn5cSS7Zp4jqWAMMAOXRoKfuOHduKVFUo"
                DJANGO_DB_HOST: "db"
                DJANGO_DB_DATABASE: "djangoqa"
                DJANGO_DB_USER: "djangouser"
                DJANGO_DB_PASSWORD: "djangouserpassword"
            logging: { options: { max-size: "10m", max-file: "3" } }

        celery-worker:
            image: django-docker-demo:latest
            command: "celery -A django_demo.tasks worker --loglevel=info"
            logging: { options: { max-size: "10m", max-file: "3" } }

        redis:
            image: redis:5.0-alpine
            logging: { options: { max-size: "10m", max-file: "3" } }
            
        db:
            image: mariadb:10.4
            restart: always
            environment:
                MYSQL_DATABASE: "djangoqa"
                MYSQL_USER: "djangouser"
                MYSQL_PASSWORD: "djangouserpassword"
                MYSQL_RANDOM_ROOT_PASSWORD: "yes"
            volumes:
                - django-db-qa:/var/lib/mysql
            logging: { options: { max-size: "10m", max-file: "3" } }

    volumes:
        django-db-qa:
    ```

    - And build your continuous integration process (this is a simple process)
        
        - Code + commit + push 
        - auto-start CI/CD process
        - `DOCKER_BUILDKIT=1 docker build -t django-docker-demo:qa --target=qa .` (this is the test stage)
        - `DOCKER_BUILDKIT=1 docker build -t django-docker-demo:dev --target=dev .` + push docker image dev internally (optional)
        - `DOCKER_BUILDKIT=1 docker build -t django-docker-demo:latest --target .` + push official docker image
        - update running containers (outside the scope of this tutorial)