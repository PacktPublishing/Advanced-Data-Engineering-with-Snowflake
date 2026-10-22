ARG AIRFLOW_VERSION=3.3.0
FROM apache/airflow:${AIRFLOW_VERSION}-python3.11

ARG AIRFLOW_VERSION

COPY --chown=airflow:root requirements.txt /tmp/chapter11-requirements.txt

RUN pip install --no-cache-dir \
    "apache-airflow==${AIRFLOW_VERSION}" \
    -r /tmp/chapter11-requirements.txt
