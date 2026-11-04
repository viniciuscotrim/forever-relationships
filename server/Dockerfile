FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY frnet ./frnet
ENV FR_DB=/data/frnet.sqlite3 FR_PORT=8080 PYTHONUNBUFFERED=1
VOLUME /data
EXPOSE 8080
USER 65534
CMD ["python", "-m", "frnet.app"]
