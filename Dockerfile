# syntax=docker/dockerfile:1

### How to build docker images:
# DOCKER_BUILDKIT=1 docker build -t django-docker-demo:latest .
# DOCKER_BUILDKIT=1 docker build -t django-docker-demo:dev --target=dev .
# DOCKER_BUILDKIT=1 docker build -t django-docker-demo:qa --target=qa .
# DOCKER_BUILDKIT=1 docker build -t django-docker-demo:webserver --target=webserver .

##################################################################################
# basepy - base python packages
##################################################################################
FROM python:3.7-alpine as basepy

RUN adduser -D user \
    && mkdir /app \
    && chown user: /app
WORKDIR /app
ENV HOME /app
ENV PYTHONUNBUFFERED=1

RUN --mount=type=cache,id=apk,sharing=locked,target=/var/cache/apk \
    apk add --update \
        bash \
        build-base \
        libevent \
        mariadb-dev \
        python-dev 

COPY --chown=user django_demo/requirements.txt requirements.txt
RUN --mount=type=cache,id=pip,target=/app/.cache/pip \
    pip install -r requirements.txt


##################################################################################
# base - base python stage with code and base packages
##################################################################################
FROM basepy as base

COPY --chown=user django_demo/ /app/
COPY --chown=user conf/run_django.sh /run_django.sh

CMD /run_django.sh

##################################################################################
# dev - all development packages installed
##################################################################################
FROM basepy as dev

COPY --chown=user django_demo/requirements-dev.txt requirements-dev.txt
RUN --mount=type=cache,id=pip,target=/app/.cache/pip \
    pip install -r requirements-dev.txt

COPY --from=base --chown=user /app/ /app/
COPY --from=base --chown=user /run_django.sh /run_django.sh

USER user
CMD /run_django.sh

##################################################################################
# qa - quality stage. Run tests and other quality steps only
##################################################################################
FROM dev AS qa
RUN black --target-version=py37 --check --diff . 
RUN mypy --python-version=3.7 --pretty --show-error-context .
RUN coverage run django_demo/manage.py test
RUN django_demo/manage.py check --deploy --fail-level WARNING

##################################################################################
# webserver - static files and proxy 
##################################################################################
FROM dev AS staticfiles
RUN python manage.py collectstatic --noinput
##################################################################################
FROM nginx:1.17-alpine AS webserver
COPY conf/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=staticfiles /app/static /staticfiles/static

##################################################################################
# final - official image, for running your application
##################################################################################
FROM base
USER user
