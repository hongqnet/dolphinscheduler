USER root
#设置时区
RUN ln -snf /usr/share/zoneinfo/$tz /etc/localtime && echo '$tz' > /etc/timezone
#安装sudo
RUN apt install -y psmisc
RUN apt install -y telnet
RUN apt install -y openjdk-8-jdk
RUN apt install -y sudo
RUN chmod 640 /etc/sudoers

RUN groupadd scrapyer  && \
    useradd -m scrapyer -g scrapyer -s /bin/bash -d /home/scrapyer && \
    sed -i '$ascrapyer  ALL=(ALL)  NOPASSWD: ALL' /etc/sudoers && \
    sed -i 's/Defaults    requirett/#Defaults    requirett/g' /etc/sudoers && \
    mkdir -p /home/scrapyer/dolphinscheduler && \
    mkdir -p /usr/local/flink-1.19 && \
    mkdir -p /usr/local/datax
# 安装datax组件
#拷贝到指定目录
COPY ./dolphinscheduler-dist/target/apache-dolphinscheduler-3.2.2-bin.tar.gz ./
COPY ./dolphinscheduler-data-quality/target/dolphinscheduler-data-quality-3.2.2.jar ./
COPY ./flink-1.19.2  /usr/local/flink-1.19
COPY ./datax  /usr/local/datax
COPY ./requirements.txt  ./
# 解压编译软件到指定目录
RUN tar -xzf  apache-dolphinscheduler-3.2.2-bin.tar.gz && \
    mv  ./apache-dolphinscheduler-3.2.2-bin/* /home/scrapyer/dolphinscheduler && \
    mv  ./dolphinscheduler-data-quality-3.2.2.jar /home/scrapyer/dolphinscheduler/worker-server/libs

#安装python依赖环境包
RUN sudo pip install -r ./requirements.txt

RUN chown -R scrapyer:scrapyer /home/scrapyer/dolphinscheduler && \
    chown -R scrapyer:scrapyer /usr/local/flink-1.19 && \
    chown -R scrapyer:scrapyer /usr/local/datax
USER scrapyer

workdir /home/scrapyer/dolphinscheduler

cmd ["bash", "start.sh"]