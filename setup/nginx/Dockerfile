FROM nginx:1.15.6

COPY ["conf/upstream.conf", "/etc/nginx/conf.d"]
COPY ["ssl", "/etc/nginx/ssl"]

RUN rm -f /etc/nginx/conf.d/default.conf && mkdir /etc/nginx/html && mkdir /data

EXPOSE 80
EXPOSE 443

#CMD ["nginx", "-g", "daemon off;"]

#CMD ["/opt/docker-entrypoint.sh"]

#ENTRYPOINT ["sh"]
