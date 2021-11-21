FROM java

RUN wget http://mirror.bit.edu.cn/apache/kafka/2.1.0/kafka_2.12-2.1.0.tgz -O /opt/kafka.tgz \
    && cd /opt \
    && tar xzvf kafka.tgz
#    && cd kafka_2.12-2.1.0

EXPOSE 9092
WORKDIR /opt/kafka_2.12-2.1.0

CMD ["/opt/kafka_2.12-2.1.0/bin/kafka-server-start.sh", "/opt/kafka_2.12-2.1.0/config/server.properties"]
#CMD ["nginx", "-g", "daemon off;"]

#CMD ["/opt/docker-entrypoint.sh"]

#ENTRYPOINT ["sh"]
