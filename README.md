# FINN Preprocessor

The first step to create FINNv2 emission estimates is to produce the FINN input file. This file is a comma-delimited text file that includes the fire locations, burned area, and underlying information about the land cover and vegetation burned. This preprocessor creates the FINN input file for a given set of fire detections (MODIS and/or VIIRS). 
Specifically, this is a PostGIS-based preprocessor. Given a point feature shapefile of active fire detections, this code estimates burned region, and then determines land cover on the burned area. The output from this code is a `*.csv` file that will be used to estimate emissions with the FINN emissions processor. 


## Instructions

Note - Paragraphs starting with an icon :information_source: can be skipped. They are FYI only,

*Note - the instructions here are for all operating systems (Windows, Mac, and Linux). However, there are specific notes throughout for Windows users (including links to other pages with step by step instructions for Windows).*

The user is expected to provide the MODIS and/or VIIRS fire detection shapefile for the time and spatial extent to be processed. The user can request these files from the NASA Fire Information for Resource Management System (FIRMS). Information about the VIIRS and MODIS products are at:  
https://earthdata.nasa.gov/earth-observation-data/near-real-time/firms

To request archived data, the user can go to the Archive Download:   https://firms.modaps.eosdis.nasa.gov/download/

Users can also request the active fire data for up to 7 days ago at:  
https://earthdata.nasa.gov/earth-observation-data/near-real-time/firms/active-fire-data

Users can chose MODIS and/or VIIRS fire detections. When requesting data, the shapefile file format should be chosen. 

### 1. Prerequiste

Before running this code, the user must have accounts set up and software installed. Specifically,  

#### 1.1 EarthData Login

The user must have an EarthData login (this is necessary for downloading the required MODIS LCT and VCF products). If you do not have a NASA EarthData account, you can create one here:  
https://urs.earthdata.nasa.gov/

#### 1.2 Download this software to your computer

The following software must be downloaded and installed on the computer:  

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

*For those using Windows:*  
`Powershell` is recommended as your command line terminal. To open the PowerShell, type PowerShell in the Windows search bar. This program will open a terminal in which you can use command lines to run the programs.  

Linux/Mac user can use the OS's default terminal.

### 2. (Windows/Mac) Customize virtual machine

Windows/Mac requires customization of Docker environment.  Specific instuction for Docker Desktop can be found in [3 Customize Docker Setting](https://github.com/yosukefk/finn_preproc/wiki/Specific-instructions-for-Docker-Desktop-for-Windows#3-customize-docker-settings) of the Project Wiki page for Docker-Desktop.  **Make sure you do this before going further (after you install Docker to your computer).**

### 3. Acquiring this repository

*Note for Windows Users: Open a PowerShell terminal and navigate to the directory on your computer where you want to store and run everything.*  

To get this repository locally, use `git clone`:

```bash
git clone https://github.com/yosukefk/finn_preproc.git
cd finn_preproc
```

Alternatively `Download ZIP` button is available at https://github.com/yosukefk/finn_preproc (or direct link https://github.com/yosukefk/finn_preproc/archive/master.zip )

Next, copy your fire detection shapefile(s) into the directory ../finn_preproc/data/.
These files need to be UNZIPPED. 

### 4. Building the Docker image

The next step is to build the Docker image. To build the Docker image, execute the following command from the terminal, in the directory where `Dockerfile` exists (this project directory):

```bash
docker build -t finn .
```

Look for an output line that says "Successfully built ..." and "Successfully tagged finn:latest". The security warning that may follow can be ignored. 

To verify that the image is created, type `docker image ls`.  One record should list `finn` as a `REPOSITORY` (specified by `-t finn` option).

:information_source:  An image is a template to do the work.  The data for the application (fire detection and burned area) itself won't be attached with the image.  A container is a specific instance made out of an image.  It behave like a semi-independent computer stored inside a computer.  You do your work in a container.  By default, the work you do will be saved in container.  In FINN application, we customize our container to let it store the data outside of container, so that data can exists independent of life of the container.

### 5. Manage the Docker container

The next step is to create your Docker container and then run the code within it. This is still done within the terminal (for Windows users, continue in `PowerShell`).  

#### 5.1 Create and start

Create and start the container via `docker run`, mounting the current working directory to the location `/home/finn` in the container.


**Note:** In the commands below, replace `yourusername` and `yourpassword` with your NASA EarthData username and password (note that if you have special characters in your username or password, you may need to escape those characters or use quotes, e.g., `password\!` or `'password!'`).  REMEMBER: If you do not have a NASA EarthData account, you can create one here: https://urs.earthdata.nasa.gov/  You should only have to do this once. 

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

NOTE: If you get an error saying that container name "finn" already in use, then you need to get rid of it first or rename in the command above. To do this, type: 

```bash
docker stop finn
docker container rm finn
```

If this still doesn’t work, you may want to try retarting Docker: 
- Go to Docker whale symbol, right click, and select restart
- Once it’s started again, go back to the PowerShell and type Docker start finn


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
* `finn` at the end refers to docker image `finn` created by `docker build` command earlier.


#### 5.2 Start Jupyter Notebook from the container

Once the container is running, you can launch a jupyter notebook using `docker exec`:

```
docker exec -it finn jupyter notebook --ip=0.0.0.0 --port=8888 --allow-root --notebook-dir /home/finn
```

You should see something like the following in your terminal:

```bash
...
Or copy and paste one of these URLs:
        http://(604ea0e75121 or 127.0.0.1):8888/?token=a7217f195e3cdbfdf...
```

The Jupyter notebook (and the code there) will be run from a web browser. 

Open a web brower. First type in 
```
localhost:
```
And copy the “8888/?....” in after the localhost as the web address. For example, you may type in something like this in your web browser: 

`localhost:8888/?token=d81907a2a19dc112c68cf14f56bc4c9ebf65f575ab6944be`

This address will take you to the Jupyter notebook. 

Note that your token (the part after `token=...`) will be different.

If running on a remote server (e.g., an Amazon EC2 instance) replace `localhost` with the server's IP address.

See "Running the notebook" section below for actually running the tool.

### 6. Running the notebook

From this point forward, leave the terminal open and move to the newly opened web browser. 

To open the notebook, navigate to the `work_generic/` directory and open [`main_generic.ipynb`](http://localhost:8888/notebooks/work_generic/main_generic.ipynb) by double clicking on that file.  
The code on this page runs the FINN preprocessor, including the components related to downloading MODIS land cover and vegetation data. The user is able to run a test case or to run a specific time and location for which the user has already downloaded fire detections.

Before running, the user must first edit the first cell (the coded part that is shaded in gray) in "Section 1". Instructions in Section 1 include information about what to edit. Read this and then edit the first cell. Make sure you have the correct path to the input fire detection shapefile(s) and the year. 

Once you have edited the first cell, you can go ahead and run the code. 

This can be done a couple of ways. 

You can press the `Run`  button at the top, which will run one cell at a time. (so you have to click it through the entire page), or you can go to `Cell` -> `Run All` from the top bar. 

Next to each cell is `In [ ]:`. When there is a `In [*]:`, the cell is cued up to run. When there is a number in there, the results are finished. 

At the end of the run, your FINN input file will be in the directory of the name that you chose in cell 1. The created file will be a comma-delimited file that can be used as input to the FINN emissions code. 

NOTE: If running a recent year, the year-specific MODIS LCT and VCF files may not be yet available. This will lead to an error statement in Section 5. If the year-specific data are unavailable, we recommend choosing the most recent year available for your processing. You will have to go back and edit the first cell and restart the kernel. 

### 7. Backup/Restore

Databese backup can be done with `pg_dump` command.

`docker exec finn sudo -u postgres pg_dump finn -f /home/finn/finn.dmp`

This created a postgresql dump file (text file with SQL command to restore data) in /home/finn, which is the same as where you downloaded finn from GitHub.

Restoration can be done with `psql` command with the dump file.

```powershell
# create new docker container 'finn_testrestore' to restore database
docker run --name finn_testrestore -v ( (pwd | docker-path) + ':/home/finn') -v pg_data:/var/lib/postgresql -p 5432:5432 -p 8888:8888 -d -e EARTHDATAUSER=yourusername -e EARTHDATAPW=yourpassword finn

# restore the database
docker exec finn_testrestore sudo -u postgres psql -d finn -f /home/finn/finn.dmp

# confirmed that output shp and csv can be exported without running analysis.
```

### 8. Removing raw MODIS imagery and intermediate data

If you need to remove files to free up hard disk space after running the
FINN preprocessor, you can do so by running the following commands in a
cell at the end of a Jupyter notebook:

```python
!rm -rf ../downloads/
!rm -rf ../proc_rst*
```


### 9, Just in case: starting, stopping, and deleting Docker containers

Sometimes you may want to stop the container, and start it again.

#### 9.1 Stopping the container

When you are done for the day, you should stop container.  To do this, follow these instructions:

First stop the Jupyter Notebook application by typing `ctrl+C` in the
terminal that started the Notebook.  Then use following command.

```bash
docker stop finn
```

`finn` here refers to the name of container, the `--name` option you used
in `docker run`.  `docker ps` shows all running containers (or
`docker container ls`).  Use `docker ps -a` to see all container including ones
that is stopped.

#### 9.2 Start again

To start the container again and continue your work,

```bash
docker start finn
```

#### 9.3 List running containers

If you're not sure whether there are any Docker containers currently running,
you can check with:

```bash
docker ps
```

If nothing is running, then all you will see is a header: 
<pre>
CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS   
</pre>
Otherwise, there will be information below these headers about the container(s) that is running.

#### 9.4 Removing the container

To permanently delete the FINN container, you can use:

```bash
docker rm finn
```
#### 9.5 To update the code (or if it was updated and you need to start from scratch): 

In the Terminal, navigate to main directory `../finn_preproc`  
Then type:

```
git checkout -- .
git pull
``` 

Be careful that this will overwrite your edits on `main_generic.ipynb`.  So save it with different name if it is needed.
