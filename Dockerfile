FROM python:3.7-alpine
RUN pip install "Django>=3.0,<4"
COPY django_demo/ /app/
CMD python /app/manage.py runserver 0.0.0.0:8000