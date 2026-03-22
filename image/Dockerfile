FROM ubuntu:jammy

ENV DEBIAN_FRONTEND=noninteractive

COPY . /tmp/image

RUN bash /tmp/image/scripts/0_osprep && \
    bash /tmp/image/scripts/1_docker && \
    bash /tmp/image/scripts/2_python && \
    bash /tmp/image/scripts/99_setup