FROM python:3.7-alpine

COPY django_demo/requirements.txt /app/requirements.txt
RUN pip install -r /app/requirements.txt
COPY django_demo/ /app/

ENV PYTHONUNBUFFERED=1
WORKDIR /app

CMD python /app/manage.py runserver 0.0.0.0:8000