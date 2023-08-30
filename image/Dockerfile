FROM ubuntu:jammy-20220801

COPY . /tmp/image

RUN ls -lR /tmp/image

RUN bash /tmp/image/scripts/0_osprep
RUN bash /tmp/image/scripts/1_docker
