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