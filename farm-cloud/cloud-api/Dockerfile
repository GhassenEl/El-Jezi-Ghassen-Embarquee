FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV FARM_DB_PATH=/data/farm_cloud.db
ENV MQTT_BROKER=mosquitto-cloud
ENV MQTT_PORT=1883
EXPOSE 5070
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "5070"]
