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
1. Setup a first draft of a Dockerfile, so we can see what is bad in this draft - (first build: 1:35) 
    ```Dockerfile
    FROM python
    COPY django_demo/ /app/
    RUN pip install "Django>=3.0,<4"
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
    * beware of context (.gockerignore)

1. Fix problems in Dockerfile
    ```Dockerfile
    FROM python:3.7-alpine
    RUN pip install "Django>=3.0,<4"
    COPY django_demo/ /app/
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