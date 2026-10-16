FROM ghcr.io/osgeo/gdal:ubuntu-small-3.10.3

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3-psycopg2 python3-openpyxl postgresql-client \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY load.py .
ENTRYPOINT ["python3", "/app/load.py"]
