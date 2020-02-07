# Este é um tutorial em como correr Django em Docker

### Índice

1. Iniciar um projeto Django (do zero)
1. Configurar Docker
1. Testar Django (com Docker)
1. Desenvolver com *Docker volumes*
1. Docker-compose - uma ferramenta simples para gestão de múltiplos *containers*
1. Depurar (debug) uma aplicação Django
1. Melhorar um `Dockerfile` e outras coisas...
1. Testar tudo junto
1. Notas finais

### Inclui:

- django
- celery 
- docker
    - boas práticas para desenvolvimento
    - boas práticas num Dockerfile 
    - volumes para um desenvolvimento mais rápido
- depuração (debug)
- algumas boas práticas em produção
    - não correr como root
    - usar gunicorn e servir o conteúdo estático
    - imagens de docker pequenas
    - variáveis de ambiente


### Notas introdutórias

- Este tutorial acompanha esta apresentação: 
    - http://tcarreira.github.io/presentations/django-docker/pt.html
    - ([também em inglês](http://tcarreira.github.io/presentations/django-docker))

- Boas práticas em desenvolvimento 

    O que é necessário para desenvolver código? (uma lista não exaustiva)

    | ferramenta | para que serve | exemplo |
    | --- | --- | --- |
    | um bom IDE | auto-completion, debugging  | vscode |
    | bons plugins no IDE | específico para a framework (django) | `ms-python.python`,<br>`batisteo.vscode-django` |
    | linter | é necessário feedback em tempo real sobre o que está errado | mypy |
    | formatador | é fantástico para partilha de código | black |
    | testes unitários | ninguém devia testar o seu código. Deixem os computadores fazê-lo | pytest |
    | código-execução | mínimo tempo desde a escrita do código até que ele é executado | manage.py runserver |



# Workshop

1. Iniciar um projeto Django (do zero)
    - Configurar um VirtualEnv e instalar Django
        ```
        virtualenv -p $(which python3) venv
        . ./venv/bin/activate
        pip install "Django>=3.0.3,<4"
        ```
    - Criar um projeto Django e configurações iniciais
        ```
        django-admin startproject django_demo
        python django_demo/manage.py makemigrations
        python django_demo/manage.py migrate
        python django_demo/manage.py createsuperuser --username admin --email ""
        ```
        Podemos correr `python django_demo/manage.py runserver 0.0.0.0:8000` e abrir um navegador em http://127.0.0.1:8000
    
1. Configurar Docker

    - Instalar o Docker

        - NÃO instalar com apt-get: bastante desatualizado (quase inútil)
        - Windows - Docker Desktop
            - https://docs.docker.com/docker-for-windows/install/
        - Mac - Docker Desktop
            - https://docs.docker.com/docker-for-mac/install/
        - Linux
            - Super fácil: `wget -qO- https://get.docker.com | sh`
            - Outra forma: https://docs.docker.com/install/

    - Criar um primeiro rascunho de um Dockerfile, para podermos encontrar o que está errado
        ```Dockerfile
        FROM python
        COPY django_demo/ /app/
        RUN pip install --no-cache-dir "Django>=3.0.3,<4"
        ENV PYTHONUNBUFFERED=1
        CMD python /app/manage.py runserver 0.0.0.0:8000
        ```
        e testar
        ```
        docker build -t django-docker-demo .
        docker run -it --rm -p8000:8000 django-docker-demo
        ``` 

        primeiro build: 2:18<br>
        build após pequena alteração: 0:22

        problemas:
        - COPY dos ficheiros antes do pip install
        - não usar tags das imagens de docker (usar alpine se possível)
        - atenção ao contexto (.dockerignore)

    - Identificar alguns problemas no Dockerfile
        ```Dockerfile
        FROM python:3.7-alpine
        RUN pip install --no-cache-dir "Django>=3.0.3,<4"
        COPY django_demo/ /app/
        ENV PYTHONUNBUFFERED=1
        CMD python /app/manage.py runserver 0.0.0.0:8000
        ```
        e `.dockerignore`
        ```
        venv/
        __pycache__/
        db.sqlite3
        ```
        De `Sending build context to Docker daemon  42.42MB` passamos a `...156.7kB`

        primeiro build: 1:37<br>
        build após pequena alteração: 0:03

1. Testar Django (com Docker)

    Vamos criar o nosso próprio conteúdo em Django

    criar `django_demo/django_demo/views.py`
    ```python
    import os
    from django.http import HttpResponse

    def hello_world(request):
        output_string = "<h1>Hello World from {}".format(os.environ.get("HOSTNAME", "no_host"))
        return HttpResponse(output_string)
    ```
    alterar `django_demo/django_demo/urls.py`
    ```python
    from django.contrib import admin
    from django.urls import path
    from . import views

    urlpatterns = [
        path('admin/', admin.site.urls),
        path('', views.hello_world),
    ]
    ```

1. Desenvolver com *Docker volumes*

    Apesar da criação de uma imagem de docker ser rápida, não queremos ter de recriar+reiniciar a aplicação cada vez que há alguma alteração
    
    adicionar um volume no docker run
    ```
    docker run -it --rm -p8000:8000 -v "$(pwd)/django_demo/:/app/" django-docker-demo
    ``` 

    agora, cada vez que algum ficheiro for alterado, o próprio django irá reiniciar. Muito útil para desenvolvimento.

1. Docker-compose - uma ferramenta simples para gestão de múltiplos *containers*

    Vamos adicionar algumas dependências: Celery + Redis (**This is a major step**)

    o Celery depende de um broker, e vamos usar Redis para ser mais simples
    
    - Instalar Celery e cliente de Redis

        (como estamos a adicionar mais dependências, vamos manter um ficheiro à parte com as mesmas `django_demo/requirements.txt`)
        ```Dockerfile
        Django>=3.0.3,<4
        Celery>=4.3.0,<4.4
        redis>=3.3<3.4
        ```
        e atualizar `Dockerfile` (assim não precisamos de voltar a atualizar quando houver novas dependências)
        ```Dockerfile
        FROM python:3.7-alpine

        COPY django_demo/requirements.txt /app/requirements.txt
        RUN pip install --no-cache-dir -r /app/requirements.txt
        COPY django_demo/ /app/

        ENV PYTHONUNBUFFERED=1
        WORKDIR /app

        CMD python /app/manage.py runserver 0.0.0.0:8000
        ```
    - Criar um `docker-compose.yml` para ter os 3 serviços a correr: django + redis + celery_worker
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
                command: "celery -A django_demo.tasks worker --loglevel=info"
            redis:
                image: redis:5.0-alpine
        ```
    - Atualizar o código python com um teste

        criar `django_demo/django_demo/tasks.py`
        ```python
        from celery import Celery
        import os
        app = Celery('tasks', broker='redis://redis:6379', backend='redis://redis:6379')

        @app.task
        def hello(caller_host):
            return "<h1>Hi {}! This is {}.</h1>".format(caller_host, os.environ.get("HOSTNAME", 'celery_worker_hostname'))
        ```
        adicioanr ao `django_demo/django_demo/views.py`
        ```python
        from . import tasks
        def test_task(request):
            task = tasks.hello.delay(os.environ.get("HOSTNAME", "no_host"))
            output_string = task.get(timeout=5)
            return HttpResponse(output_string)
        ```
        atualizar `django_demo/django_demo/urls.py`
        ```python
        urlpatterns = [
            path('admin/', admin.site.urls),
            path('', views.hello_world),
            path('task', views.test_task),
        ]
        ```
    - Finalmente podemos testar esta configuração

        - build docker image: `docker build -t django-docker-demo .`
        - run `docker-compose up` (you can see the logs and terminate with ctrl+c. to run in background, add `-d`)
        - open http://127.0.0.1:8000/task


    Agora que as coisas estão um pouco mais confusas, vamos piorar.


    <br><br>
    *lembrando algumas boas práticas para desenvolvimento*

1. Depurar (debug) uma aplicação Django

    exemplo com vscode, que usa ptvsd para depuração, `.vscode/launch.json`
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

    O primeiro é suficiente para scripts em python, mas não é muito prático em Django
    O segundo é muito bom, mas corre localmente (sem docker)

    ou...

    - Podemos correr o depurador diretamente com docker
        - criar um `django_demo/requirements-dev.txt` com as dependências para desenvolvimento (resultado do `pip freeze`) (nota: este exemplo tem demasiados pacotes)
            ```
            amqp==2.5.2
            appdirs==1.4.3
            asgiref==3.2.3
            astroid==2.3.3
            attrs==19.3.0
            billiard==3.6.1.0
            black==19.10b0
            celery==4.3.0
            Click==7.0
            Django==3.0.3
            importlib-metadata==1.2.0
            isort==4.3.21
            kombu==4.6.7
            lazy-object-proxy==1.4.3
            mccabe==0.6.1
            more-itertools==8.0.2
            mypy==0.750
            mypy-extensions==0.4.3
            pathspec==0.6.0
            ptvsd==4.3.2
            pylint==2.4.4
            pytz==2019.3
            redis==3.3.11
            regex==2019.11.1
            six==1.13.0
            sqlparse==0.3.0
            toml==0.10.0
            typed-ast==1.4.0
            typing-extensions==3.7.4.1
            vine==1.3.0
            wrapt==1.11.2
            zipp==0.6.0
            ```
        - alterar o `Dockerfile` para incluir um `requirements-dev.txt` em vez do `requirements.txt` (precisamos das ferramentas de depuração instaladas) e mais algumas dependências
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
            e voltar a recriar a imagem 
            ```
            docker build -t django-docker-demo .
            ```
        - expôr o porto 5678 no serviço django dentro do `docker-compose.yml`
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
        - alterar `django_demo/manage.py` (adicionar dentro do *main* antes de `execute_from_command_line(sys.argv)`)
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
        - adicionar um depurador remoto dentro do IDE. No caso do vscode, adicionar a confuração ao `.vscode/launch.json`
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
        - e testar
            ```
            docker-compose up
            ```
            Depois adicionar um *breakpoint* dentro da função `django_demo.views.hello_world()` e recarregar o browser.

1. Melhorar um *Dockerfile* e outras coisas...

    Talvez seja uma boa ideia fazer apenas `git clone https://github.com/tcarreira/django-docker.git`

    - não correr como root
        ```Dockerfile
        RUN adduser -D user
        USER user
        ```
    - remover dependências desnecessárias. Manter imagens diferentes para diferentes casos (usar multi-stage builds)
        ```Dockerfile
        FROM python:3.7-alpine AS base
        ...
        FROM base AS dev
        ...
        FROM base AS final
        ...
        ```
    - manter os registos (logs) limpos
        ```yaml
        services:
            app:
                ...
                logging:
                    options:
                        max-size: "10m"
                        max-file: "3"
        ```
        ou de forma mais curta:
        ```yaml
                logging: { options: { max-size: "10m", max-file: "3" } }
        ```
    - cache de nível avançado (com Buildkit `DOCKER_BUILDKIT=1`)- https://github.com/moby/buildkit
        ```Dockerfile
        # syntax=docker/dockerfile:experimental
        ...
        ENV HOME /app
        WORKDIR /app
        RUN --mount=type=cache,uid=0,target=/app/.cache/pip,from=base \
            pip install -r requirements.txt
        ```
        **note**: `# syntax=docker/dockerfile:experimental` na primeira linha do `Dockerfile` é obrigatório para usar as novas funcionalidades do BUILDKIT 
    - qualidade como parte da linha de montagem
        ```Dockerfile
        FROM dev AS qa
        RUN black --target-version=py37 --check --diff . 
        RUN mypy --python-version=3.7 --pretty --show-error-context .
        RUN coverage run django_demo/manage.py test
        RUN django_demo/manage.py check --deploy --fail-level WARNING
        ```
    
    - Preparar o Django para produção
        - Preparar o Django para produção - https://docs.djangoproject.com/en/3.0/howto/deployment/checklist/ (fora do âmbiro deste tutorial)
            - usar um servidor web <br>
            > em: https://docs.djangoproject.com/en/3.0/ref/django-admin/#runserver <br>
            NÂO USE ESTE SERVIDOR EM PRODUÇÃO. Ele não passou pela auditoria de segurança nem por testes de eficiência. 
            (E é assim que se vai manter. Estamos no negócio de produzir uma framework Web, não de servidores web, 
            portanto está fora do âmbito do Django melhorar este servidor para aguentar um ambiente de produção.)
            
            e gerar o conteúdo estático (necessário para o novo servidor web)
            ```Dockerfile
            FROM dev AS staticfiles
            RUN python manage.py collectstatic --noinput

            FROM nginx:1.17-alpine
            COPY conf/nginx.conf /etc/nginx/conf.d/default.conf
            COPY --from=staticfiles /app/static /staticfiles/static
            ```
            e criar o `conf/nginx.conf` correspondente (este é só um exemplo mínimo funcional. Não está preparado para produção)
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
        
        - provavelmente vamos querer usar uma base de dados diferente

            adicionar ao `docker-compose.yml`
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
            e alterar configurações em `django_demo/django_demo/settings.py`
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

        - criar um entrypoint comum (para que não tenhamos de alterar o dockerfile mais tarde)
            ```bash
            #!/bin/bash

            # esperar que a base de dados esteja pronta
            if [[ ${DJANGO_DB_HOST} != "" ]]; then
                while !</dev/tcp/${DJANGO_DB_HOST}/${DJANGO_DB_PORT:-3306} ; do 
                    sleep 1;
                    [[ $((counter++)) -gt 60 ]] && break
                done
            fi

            python manage.py migrate

            case $DJANGO_DEBUG in
                true|True|TRUE|1|YES|Yes|yes|y|Y)
                    echo "================= Iniciando o depurador =================="
                    python manage.py runserver 0.0.0.0:8000
                    ;;
                *)
                    gunicorn --worker-class gevent -b 0.0.0.0:8000 django_demo.wsgi
                    ;;
            esac
            ```

1. Testar tudo junto

    **note**: agora é uma ótima altura para `git clone https://github.com/tcarreira/django-docker.git`

    atualizar o docker-compose
    `docker-compose.yml`
    ```yaml
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

    e correr
    ```
    DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1 docker-compose up --build
    ```

    **note**: é necessário docker-compose >= 1.25 para correr o buildkit diretamente. Caso não esteja disponível, primeiro é necessário criar as imagens e só depois correr `docker-compose up`


1. Notas finais

    - criar um `docker-compose.qa.yml` separado para testes de qualidade com as imagens finais
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

    - criar uma linha de montagem para integração contínua (CI/CD) (este é apenas um exemplo simples)
        
        - Código + commit + push 
        - iniciar automaticamente o processo CI/CD
        - `DOCKER_BUILDKIT=1 docker build -t django-docker-demo:qa --target=qa .` (esta é a fase de testes)
        - `DOCKER_BUILDKIT=1 docker build -t django-docker-demo:dev --target=dev .` + push da imagem de docker dev, internamente (opcional)
        - `DOCKER_BUILDKIT=1 docker build -t django-docker-demo:latest --target .` + push da imagem de docker oficial
        - atualizar os containers em execução (fora do âmbito deste tutorial)
