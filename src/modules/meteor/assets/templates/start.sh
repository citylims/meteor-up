#!/bin/bash

APPNAME=<%= appName %>
APP_PATH=/opt/$APPNAME
BUNDLE_PATH=$APP_PATH/current
ENV_FILE=$APP_PATH/config/env.list
PORT=<%= port %>

# Remove previous version of the app, if exists
docker rm -f $APPNAME

# Remove frontend container if exists
docker rm -f $APPNAME-frontend
echo "Removed $APPNAME-frontend"

# We don't need to fail the deployment because of a docker hub downtime
set +e
docker pull <%= docker.image %>
set -e
echo "Pulled <%= docker.image %>"

docker run \
  -d \
  --restart=always \
  --expose=80 \
  --volume=$BUNDLE_PATH:/bundle \
  --hostname="$HOSTNAME-$APPNAME" \
  --env-file=$ENV_FILE \
  <% if(useLocalMongo)  { %>--link=mongodb:mongodb --env=MONGO_URL=mongodb://mongodb:27017/$APPNAME <% } %>\
  <% if(logConfig && logConfig.driver)  { %>--log-driver=<%= logConfig.driver %> <% } %>\
  <% for(var option in logConfig.opts) { %>--log-opt <%= option %>=<%= logConfig.opts[option] %> <% } %>\
  <% for(var volume in volumes) { %>-v <%= volume %>:<%= volumes[volume] %> <% } %>\
  <% for(var args in docker.args) { %> <%= docker.args[args] %> <% } %>\
  <% if(typeof sslConfig.autogenerate === "object")  { %> \
    -e "LETSENCRYPT_HOST=<%= sslConfig.autogenerate.domains %>" \
    -e "LETSENCRYPT_EMAIL=<%= sslConfig.autogenerate.email %>" \
  <% } %> \
  --name=$APPNAME \
  <%= docker.image %>
echo "Ran <%= docker.image %>"
sleep 15s

<% if(typeof sslConfig === "object")  { %>
  <% if(typeof sslConfig.autogenerate === "object")  { %>
    echo "Running autogenerate"
    # Get the nginx template for nginx-gen
    wget https://raw.githubusercontent.com/jwilder/nginx-proxy/master/nginx.tmpl -O /opt/$APPNAME/config/nginx.tmpl

    set +e
    docker rm -f $APPNAME-nginx-letsencrypt
    echo "Removed $APPNAME-nginx-letsencrypt"

    docker rm -f $APPNAME-nginx-gen
    echo "Removed $APPNAME-nginx-gen"

    docker rm -f $APPNAME-frontend
    echo "Removed $APPNAME-frontend"
    set -e

    # We don't need to fail the deployment because of a docker hub downtime
    set +e
    docker pull jrcs/letsencrypt-nginx-proxy-companion:latest
    docker pull jwilder/docker-gen:latest
    docker pull nginx:latest
    set -e
    echo "Pulled autogenerate images"
    docker run -d -p 80:80 -p 443:443 \
      --name $APPNAME-frontend \
      --restart=always \
      -e "HTTPS_METHOD=noredirect" \
      --link=$APPNAME:backend \
      -v /opt/$APPNAME/config/conf.d:/etc/nginx/conf.d  \
      -v /opt/$APPNAME/config/vhost.d:/etc/nginx/vhost.d \
      -v /opt/$APPNAME/config/html:/usr/share/nginx/html \
      -v /opt/$APPNAME/certs:/etc/nginx/certs:ro \
      nginx
    echo "Ran nginx"
    sleep 15s

    docker run -d \
      --name $APPNAME-nginx-gen \
      --restart=always \
      --volumes-from $APPNAME-frontend \
      -v /opt/$APPNAME/certs:/etc/nginx/certs:ro \
      -v /opt/$APPNAME/config/nginx.tmpl:/etc/docker-gen/templates/nginx.tmpl:ro \
      -v /var/run/docker.sock:/tmp/docker.sock:ro \
      jwilder/docker-gen \
      -notify-sighup $APPNAME-frontend -watch -only-exposed -wait 5s:30s /etc/docker-gen/templates/nginx.tmpl /etc/nginx/conf.d/default.conf
    echo "Ran jwilder/docker-gen"
    sleep 15s

    docker run -d \
      --name $APPNAME-nginx-letsencrypt \
      --restart=always\
      -e "NGINX_DOCKER_GEN_CONTAINER=$APPNAME-nginx-gen" \
      --volumes-from $APPNAME-frontend \
      -v /opt/$APPNAME/certs:/etc/nginx/certs:rw \
      -v /var/run/docker.sock:/var/run/docker.sock:ro \
      jrcs/letsencrypt-nginx-proxy-companion
    echo "Ran jrcs/letsencrypt-nginx-proxy-companion"
  <% } else { %>
    # We don't need to fail the deployment because of a docker hub downtime
    set +e
    docker pull meteorhacks/mup-frontend-server:latest
    set -e
    docker run \
      -d \
      --restart=always \
      --volume=/opt/$APPNAME/config/bundle.crt:/bundle.crt \
      --volume=/opt/$APPNAME/config/private.key:/private.key \
      --link=$APPNAME:backend \
      --publish=<%= sslConfig.port %>:443 \
      --name=$APPNAME-frontend \
      meteorhacks/mup-frontend-server /start.sh
  <% } %>
<% } %>
