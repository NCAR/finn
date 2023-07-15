# 2023-04-08 updated from postgis 2.5
FROM kartoza/postgis:14-3.3

ENV PATH /opt/conda/bin:$PATH

RUN rm -fr /var/lib/apt/lists/* && apt-get update --fix-missing && \
    apt-get install -y wget bzip2 ca-certificates \
    libglib2.0-0 libxext6 libsm6 libxrender1 postgis git unzip

RUN apt-get install -y curl grep sed dpkg unzip python3-pip sudo

# 2023-04-08 TINI version fixed
ENV TINI_VERSION 0.19.0
RUN curl -L "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini_${TINI_VERSION}.deb" > tini.deb && \
    dpkg -i tini.deb && \
    rm tini.deb && \
    apt-get clean

RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo "conda activate" >> ~/.bashrc && \
    export PATH="$HOME/miniconda/bin:$PATH"

RUN conda info && \
  . ~/.bashrc && \
  conda activate

RUN conda update conda

# 2023-04-08 version of packages that works
# 2023-04-23 minor version specifications relaxed
# 2023-07-12 notebook separatedly needed for jupyterlab
# 2023-07-12 switched from basemap to catopy
RUN conda install -c conda-forge -y \
	gdal=3.6 \
	python=3.11 \
	jupyterlab=4.0 \
	notebook=6.5 \
	pyproj=3.6 \
	beautifulsoup4=4.12 \
	shapely=2.0 \
	psycopg2=2.9 \
	matplotlib=3.7 \
	cartopy=0.21

# verify that gdal is importable
RUN /opt/conda/bin/python -c "from osgeo import gdal"

# conda's networkx cannot be accessed, stuck with debian's python for plpython (set at compile time)
# apt has older version of networkx, cannot be used.
# so i have to use pip3
# also i SOULD specify version of library so that results are reproducible...
RUN /usr/bin/pip3 install numpy scipy networkx # no specfic version, 2023-04-08

EXPOSE 8888

# default database settings
ENV POSTGRES_USER=finn \
    POSTGRES_PASS=finn \
    POSTGRES_DBNAME=finn \
    PGDATABASE=finn \
    PGUSER=finn \
    PGPASSWORD=finn \
    PGHOST=localhost \
    PGPORT=5432


### # as of 2019-12-21, kartoza/postgis:11.0-2.5 has postgresql 11.6 and postgis
### # 3.0.0, for some reason.  And the binary does not have raster support at
### # compiler time.  I was told
### # https://github.com/kartoza/docker-postgis/issue/172 that raster support can
### # be enabled at run time
### 
### ENV POSTGRES_MULTIPLE_EXTENSIONS=postgis,postgis_raster
### 
### # the above to actually kick in i had to do below..., seems like?  Hope this
### # doesn't backfire when the postgis has raster enabled at compile time.  in
### # that case i will come back here and remove two lines around here
### 
### RUN echo "psql -d finn -c 'create extension postgis_raster;'" >> /docker-entrypoint.sh

# 2023-04-08 not needed anymore?
# the docker-entrypoint.sh is now in /script , and i dont need to call it.  seems to be executed without having following line
# ENTRYPOINT /docker-entrypoint.sh
