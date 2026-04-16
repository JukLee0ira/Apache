FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    apache2 \
    liblua5.1-0 \
    lua5.1 \
    lua-cjson \
    curl \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN a2enmod lua headers proxy proxy_http rewrite

RUN mkdir -p /usr/local/apache2/scripts

COPY scripts/ /usr/local/apache2/scripts/
COPY conf/sites-enabled/ /etc/apache2/sites-enabled/

RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf

EXPOSE 80

CMD ["apachectl", "-D", "FOREGROUND"]
