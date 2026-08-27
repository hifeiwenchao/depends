FROM nginx:1.30.4-trixie

COPY ["conf/upstream.conf", "/etc/nginx/conf.d"]
#COPY ["static", "/etc/nginx/static"]
#COPY ["media", "/etc/nginx/media"]

RUN rm -f /etc/nginx/conf.d/default.conf && mkdir /etc/nginx/html && mkdir /etc/nginx/media && mkdir /etc/nginx/static

EXPOSE 80
EXPOSE 443

#CMD ["nginx", "-g", "daemon off;"]

#CMD ["/opt/docker-entrypoint.sh"]

#ENTRYPOINT ["sh"]
