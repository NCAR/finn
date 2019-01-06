FROM kartoza/postgis:10.0-2.4

ENV PATH /opt/conda/bin:$PATH

RUN apt-get update --fix-missing && apt-get install -y wget bzip2 ca-certificates \
    libglib2.0-0 libxext6 libsm6 libxrender1 postgresql-10-postgis-2.4 postgis git unzip

RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-4.5.11-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo "conda activate base" >> ~/.bashrc

RUN apt-get install -y curl grep sed dpkg postgresql-plpython3-10 unzip python3-pip && \
    TINI_VERSION=`curl https://github.com/krallin/tini/releases/latest | grep -o "/v.*\"" | sed 's:^..\(.*\).$:\1:'` && \
    curl -L "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini_${TINI_VERSION}.deb" > tini.deb && \
    dpkg -i tini.deb && \
    rm tini.deb && \
    apt-get clean

run conda install -c conda-forge jupyterlab gdal ncurses pyproj beautifulsoup4 shapely networkx psycopg2

# conda's networkx cannot be accessed, stuck with debian's python for plpython (set at compile time)
# apt has older version of networkx, cannot be used.
# so i have to use pip3
run pip3 install numpy scipy networkx

EXPOSE 8888

COPY create_plpython3u.sql /docker-entrypoint-initdb.d/

ENTRYPOINT /docker-entrypoint.sh
