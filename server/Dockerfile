FROM python:3.12-slim
WORKDIR /app
COPY trustnet ./trustnet
ENV TA_DB=/data/trustnet.sqlite3 TA_PORT=8080
VOLUME /data
EXPOSE 8080
USER 65534
CMD ["python", "-m", "trustnet.app"]
