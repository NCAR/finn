FROM kartoza/postgis:10.0-2.4

ENV PATH /opt/conda/bin:$PATH

RUN apt-get update --fix-missing && apt-get install -y wget bzip2 ca-certificates \
    libglib2.0-0 libxext6 libsm6 libxrender1 postgresql-10-postgis-2.4 postgis git unzip

RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo "conda activate base" >> ~/.bashrc

RUN apt-get install -y curl grep sed dpkg postgresql-plpython3-10 unzip python3-pip sudo && \
    TINI_VERSION=`curl https://github.com/krallin/tini/releases/latest | grep -o "/v.*\"" | sed 's:^..\(.*\).$:\1:'` && \
    curl -L "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini_${TINI_VERSION}.deb" > tini.deb && \
    dpkg -i tini.deb && \
    rm tini.deb && \
    apt-get clean

RUN conda install -c conda-forge python=3.6
RUN conda config --remove channels 'defaults'
RUN conda install -c conda-forge jupyterlab ncurses pyproj beautifulsoup4 shapely psycopg2 matplotlib basemap
RUN conda install --channel conda-forge --override-channels "gdal>2.2.4"

# check that key packages are importable
RUN python -c 'from osgeo import gdal'

# conda's networkx cannot be accessed, stuck with debian's python for plpython (set at compile time)
# apt has older version of networkx, cannot be used.
# so i have to use pip3
RUN pip3 install numpy scipy networkx

EXPOSE 8888

COPY create_plpython3u.sql /docker-entrypoint-initdb.d/

# default database settings
ENV POSTGRES_USER=finn \
    POSTGRES_PASS=finn \
    POSTGRES_DBNAME=finn \
    PGDATABASE=finn \
    PGUSER=finn \
    PGPASSWORD=finn \
    PGHOST=localhost \
    PGPORT=5432

RUN echo "psql -d finn -c 'CREATE LANGUAGE plpython3u;'" >> /docker-entrypoint.sh

ENTRYPOINT /docker-entrypoint.sh
