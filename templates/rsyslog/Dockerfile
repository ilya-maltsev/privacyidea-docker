FROM alpine:latest
RUN apk add --no-cache rsyslog && \
    mkdir -p /var/log/remote /var/lib/rsyslog
COPY rsyslog.conf /etc/rsyslog.conf
EXPOSE 514/udp 514/tcp
CMD ["rsyslogd", "-n", "-f", "/etc/rsyslog.conf"]
