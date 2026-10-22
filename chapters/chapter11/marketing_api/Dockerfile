# Mock marketing API for the Chapter 11 reverse-ETL push. Stdlib only, so the
# image needs no pip install.
FROM python:3.12-slim

WORKDIR /app
COPY app.py /app/app.py
RUN chmod 755 /app && chmod 644 /app/app.py

EXPOSE 8080
USER nobody

CMD ["python", "app.py"]
