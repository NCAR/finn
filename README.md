# FINN Preprocessor

PostGIS based preprorcessor.  Given point feature of active fire detections, this code estimates burned region, and then determine land cover on the burned area.  Output from this code will be used for emission estimate by FINN.


## Instructions

(Paragraphs starting with an icon :information_source: can be skipped. They are FYI only)

### 1. Prerequiste

* Docker CE
  * (Windows) https://docs.docker.com/docker-for-windows/install/
  * (Linux) https://docs.docker.com/install/linux/docker-ce/ubuntu/
  * (Mac) https://docs.docker.com/docker-for-mac/install/  

  (Windows/Mac) Depending on version of Windows and Mac, you use either `Docker Desktop` (newer product) or `Docker Toolbox` (legacy product)

* QGIS  
  https://qgis.org 
  
  A GIS software analogous to ArcMap.  Recommended to install this on your machine, since it allows you to directly see the PostGIS database to QA the processing.

* Git
  * (Windows) https://git-scm.com/download/win
  * (Linux/Mac) use system's package manager

(Windows) With `Docker Toolbox`, it is recommended to use `Docker Quickstart Terminal` to run docer commands, as it emulates Linux behavior.  For example, "C:\Users" is changed to "/c/Users" which is what Decker expects.   
With `Docker Desktop`, `Powershell` is recommended, Windows path may interfere with docker.  Special instruction is given for such case.

### 2. (Windows/Mac) Customize virtual machine

Not needed in order to run the first sample case "testOTS_092018".  To work with larger data set, extra configuration is needed for Windows/Mac application. 

**TODO** *something short nice here, or a link to instruction specific to each environment.  Needs to secure a large enough virtual storage.*

### 3. Acquiring this repository

To get this repository locally, use `git clone`:

```bash
git clone https://github.com/yosukefk/finn_preproc.git
cd finn_preproc
```

Alternatively `Download ZIP` button is available at https://github.com/yosukefk/finn_preproc (or direct link https://github.com/yosukefk/finn_preproc/archive/master.zip )

### 4. Building the Docker image

To build the Docker image, execute the following command from the terminal, in the directory where `Dockerfile` exists (this project directory):

```bash
docker build -t finn .
```

To verify that the image is created, type `docker image ls`.  `finn` should be listed as a REPOSITORY (specified by `-t finn` option).

:information_source:  An image is a template to do the work.  The data for the application (fire detection and burned area) itself won't be attached with the image.  A container is a specific instance made out of an image.  It behave like a semi-independent computer stored inside a computer.  You do your work in a container.  By default, the work you do will be saved in container.  In FINN application, we customize our container to let it store the data outside of container, so that data can exists independent of life of the container.

### 5. Manage the Docker container

#### Create and start

Create and start the container via `docker run`, mounting the current working directory to the location `/home/finn` in the container. 

(Linux)
```bash
mkdir ${HOME}/pg_data
docker run --name finn -v $(pwd):/home/finn -v ${HOME}/pg_data:/var/lib/postgresql -p 5432:5432 -p 8888:8888 -d -e EARTHDATAUSER=yourusername -e EARTHDATAPW=yourpassword finn
```

(Windows with Powershell)
```powershell
# Create named volume to store the database
docker volume create pg_data

# Function to convert windows path to what docker likes
filter docker-path {'/' + $_ -replace '\\', '/' -replace ':', ''}

# Create docker container and start
docker run --name finn -v ( (pwd | docker-path) + ':/home/finn') -v pg_data:/var/lib/postgresql -p 5432:5432 -p 8888:8888 -d -e EARTHDATAUSER=yourusername -e EARTHDATAPW=yourpassword finn
```


To verify that the container is running, type `docker ps`. 
You should see the container listed with a unique container id, the name "finn" and some other information. 

:information_source:  Below the meaning of each options for `docker run`.

* `--name finn`
  This sets the name for the container.  Happened to be the same as image's name, but you may choose other names (to have multiple containers out of one image).  You cannot use same name for two different containers, though, container name must be unique.
* `-v $(pwd):/home/finn`  
  This makes $(pwd) (current working directory, where you downloaded FINN preprocessor by Git) to be accessible as `/home/finn` from inside the container being made ( [bind mounts](https://docs.docker.com/storage/bind-mounts/) ).  Therefore the change you make in FINN directory on your machine is reflected immediately in files in /home/finn in the container and vice versa, since they are identical file on the storage.  Our code/inputs/intermediate files/outputs is stored in FINN direoctory which becomes /home/finn when you look from the container.
* (Linux) `-v ${HOME}/pg_data:/var/lib/postgresql`  
  Does bind mounting again, mounting pg_data directory you created (this can be anywhere on your machine) to the container's `/var/lib/postgresql` directory.  The directory is used by PostgreSQL/PostGIS running in container to store the database.  With this setting, database itself becomes independent of the container.  Instead of ${HOME}/pg_data you can use any directory in your system.
* (Windows/Mac) `-v pg_data:/var/lib/posrgresql`  
  Unfortunately this setting does not work for Windows and Mac version of Docker since the host machine's files system is not compatible of PostgreSQL in the container (Linux version).  Instead we recommend to create [named volumes](https://docs.docker.com/storage/volumes/) and store database there.  See project wiki page for [volume management](https://github.com/yosukefk/finn_preproc/wiki/Docker-volume-to-store-postgreSQL-database) for more detail.
* `-p 5432:5432` and `-p 8888:8888`
  Maps container's port for PostgreSQL and Jupyter Notebook to those on the host machine.  You can, for example, `-p 25432:5432` if your machine uses 5432 for other purpose.
* `-d`
  Makes the container be detached from the terminal you created container (makes it a daemon)
* `-e EARTHDATAUSER=yourusename` and `-e EARTHDATAPW=yourpassword`
  The code has functionality to download MODIS raster data from [Earthdata website](https://earthdata.nasa.gov/), and they require you to register to do that.  Create one if you plan to use MODIS raster directly downloaded from Earthdata website.

#### Start Jupyter Notebook from the container

Once the container is running, you can launch a jupyter notebook using `docker exec`: 

```
docker exec -it finn jupyter notebook --ip=0.0.0.0 --port=8888 --allow-root --notebook-dir /home/finn
```

Then, go to `localhost:8888/?token=...` in a web browser to open the notebook interface, pasting the token that is printed in the termainal in place of `...`.
For example: `localhost:8888/?token=6d87327966c2769ea5a8d2da792e34127ac7dca29f78133d` (though your token will be different). 
If running on a remote server (e.g., an Amazon EC2 instance) replace `localhost` with the server's IP address. 

The fourth word in the command `finn` refers to container name you careated in `docker run` command.  If you use different `--name`, use the name here.

See "Running the notebook" section below for actually running the tool.

#### Stop

When you are done for the day, you stop container.  First stop the Jupyter Notebook application by typing `ctrl+C` in the terminal that started the Notebook.  Then use following command. 

```bash
docker stop finn
```

`finn` here refers to the name of container, the `--name` option you used in `docker run`.  `docker ps` shows all running containers (or  `docker container ls`).  Use `docker ps -a` to see all container including ones that is stopped.

#### Start again

To start the container again and continue your work,

```bash
docker stop finn
```

#### More container management

**TODO** *a wiki page for `docker rm`, `docker inspect`, or link to suitable webpage*

### 6. Running the notebook

To open the notebook, navigate to the `work_testOTS_092018/` directory and open `main_testOTS_092018.ipynb`.  
This notebook runs FINN (press Shift+Enter to run a cell), including the components related to downloading MODIS data. 

Execute the cells of the notebook to run the analysis.

## Turorial

[Tutorial page](https://github.com/yosukefk/finn_preproc/wiki/Tutorial) is prepared in project wiki.  It explains purpose of each sample cases.
