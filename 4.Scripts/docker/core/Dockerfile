FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 XDG_CACHE_HOME=/tmp/.cache \
    JAVA_TOOL_OPTIONS="-XX:+UseSerialGC -Xms16m -Xmx512m -XX:ActiveProcessorCount=1"
ARG SEQKIT_VERSION=2.8.2
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
    bash ca-certificates wget curl git gzip tar unzip file procps coreutils gawk sed grep util-linux \
    python3 python3-pip python3-setuptools python3-wheel \
    samtools bowtie2 fastp sra-toolkit subread bedtools rna-star docker.io \
 && rm -rf /var/lib/apt/lists/*
RUN wget -qO /tmp/seqkit.tar.gz "https://github.com/shenwei356/seqkit/releases/download/v${SEQKIT_VERSION}/seqkit_linux_amd64.tar.gz" \
 && tar -xzf /tmp/seqkit.tar.gz -C /usr/local/bin seqkit \
 && chmod +x /usr/local/bin/seqkit && rm -f /tmp/seqkit.tar.gz
RUN pip3 install --no-cache-dir pandas numpy scipy pysam biopython pyarrow
RUN STAR --version && samtools --version | head -1 && featureCounts -v && seqkit version \
 && python3 -c "import pandas,numpy,scipy,pysam,Bio,pyarrow; print('core imports OK')"
WORKDIR /project
CMD ["bash"]
