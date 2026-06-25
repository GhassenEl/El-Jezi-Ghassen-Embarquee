FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV HOME_DB_PATH=/data/home_cloud.db
ENV ZONES_JSON_PATH=/data/zones.json
ENV MQTT_BROKER=mosquitto-cloud
ENV MQTT_PORT=1883
EXPOSE 8120
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8120"]
