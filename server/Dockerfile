FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY trustnet ./trustnet
ENV TA_DB=/data/trustnet.sqlite3 TA_PORT=8080 PYTHONUNBUFFERED=1
VOLUME /data
EXPOSE 8080
USER 65534
CMD ["python", "-m", "trustnet.app"]
