# FINN Preprocessor

The first step to create FINNv2 emission estimates is to produce the FINN input file. This file is a comma-delimited text file that includes the fire locations, burned area, and underlying information about the land cover and vegetation burned. This preprocessor creates the FINN input file for a given set of fire detections (MODIS and/or VIIRS). 
Specifically, this is a PostGIS-based preprocessor. Given a point feature shapefile of active fire detections, this code estimates burned region, and then determines land cover on the burned area. The output from this code is a `*.csv` file that will be used to estimate emissions with the FINN emissions processor. 


## Instructions

Note - Paragraphs starting with an icon :information_source: can be skipped. They are FYI only.

*Note - the instructions here are for all supperted operating systems (Windows, Mac, and Linux). However, there are specific notes throughout for Windows users (including links to other pages with [step by step instructions for Windows](https://github.com/yosukefk/finn_preproc/wiki/Specific-instructions-for-Docker-Desktop-for-Windows)).*

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
The account is used in order to download land cover raster dataset from EarthData.

#### 1.2 Download this software to your computer

The following software must be downloaded and installed on your computer:  

* Docker CE
  * (Windows) https://docs.docker.com/docker-for-windows/install/
  * (Linux) https://docs.docker.com/install/linux/docker-ce/ubuntu/
  * (Mac) https://docs.docker.com/docker-for-mac/install/  

  (Windows/Mac) Depending on version of Windows and Mac, you use either `Docker Desktop` (newer product) or `Docker Toolbox` (legacy product).  Project wiki page for `Docker Desktop for Windows` has [screen shots of installation steps](https://github.com/yosukefk/finn_preproc/wiki/Specific-instructions-for-Docker-Desktop-for-Windows#1-install-docker-ce). 

* QGIS  
  https://qgis.org

  A GIS software analogous to ArcMap.  Recommended to install this on your machine, since it allows you to directly see the PostGIS database to QA the processing.  Instruction to use QGIS to visualize burned area and raster stored in PostGIS database is available in [this wiki page](https://github.com/yosukefk/finn_preproc/wiki/Minimum-Instruction-for-using-QGIS-with-FINN-preprocessor).

* Git
  * (Windows) https://git-scm.com/download/win
  * (Linux/Mac) use system's package manager

*For those using Windows:*  
`Powershell` is recommended as your command line terminal. To open the `PowerShell`, type `PowerShell` in the Windows search bar. This program will open a terminal in which you can use command lines to run the programs (see [screeen shots in wiki page](https://github.com/yosukefk/finn_preproc/wiki/Specific-instructions-for-Docker-Desktop-for-Windows#4-docker-build)).  

Linux/Mac user can use the OS's default terminal.

### 2. (Windows/Mac) Customize virtual machine

Windows/Mac requires customization of Docker environment.  Specific instuction for `Docker Desktop` can be found in [3 Customize Docker Setting](https://github.com/yosukefk/finn_preproc/wiki/Specific-instructions-for-Docker-Desktop-for-Windows#3-customize-docker-settings) of the Project Wiki page for Docker-Desktop.  **Make sure you do this before going further (after you install Docker to your computer).**

### 3. Acquiring this repository

*Note for Windows Users: Open a `PowerShell` terminal and navigate to the directory on your computer where you want to store and run everything.*  

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

NOTE: If you get an error saying that container name "finn" already in use, then you need to either (1) get rid of it first and `docker run` again, or (2) use different name for `--name finn` part, e.g. `--name finn_second`, in the command above.

If you did approach (2), you start having multiple containers for finn, so make sure you keep track of which is what.  Container `finn` is already there, and you now has container `finn_second`.

If you rather take approach (1), type: 

```bash
docker stop finn
docker container rm finn
```

These should remove the pre-existing container `finn` and you should be able to `docker run` now.

If this still doesn't work, you may want to try retarting Docker.  If you are using `Docker Desktop for Windows`,
- Go to Docker whale symbol, right click, and select restart
- Once it's started again, go back to the `PowerShell` and type `docker start finn`. 
Instead of `docker run` after restarting docker, You would try `docker start finn`.  This is because `docker run` creates containers and starts it.  If it fails, it may be that container is created but failed to started.  After restarting docker, the container you have already created may work by just starting it, `docker start finn`

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

NOTE: work_generic/main_generic.ipynb may be overwritten when FINN preprocessor code is updated.  It is recommended for you to copy the file to different name, or even to create separate subdirectory work_XXX to start your work.  Added advantage of this practice is that you can track your work if you have multiple tasks.

NOTE:  [Minimum in struction to use QGIS](https://github.com/yosukefk/finn_preproc/wiki/Minimum-Instruction-for-using-QGIS-with-FINN-preprocessor) available to visualize burned area and raster dataset stored in PostGIS.

### 7 What you'd do day-to-day

You may want to shut down, leave the computer, come back next day to continue you rowrk.  Use the comamnd below.

##### Stopping the container

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

##### Start again

To start the container again and continue your work, use following command.

```bash
docker start finn
```

This command take you to the place right after `docker run`, as in section 5.1 above, except that creating new container, you are reusing the existing container.  

##### List running containers

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

### 8 Database Backup/Restore

Databese backup can be done with `pg_dump` command.

`docker exec finn sudo -u postgres pg_dump finn -f /home/finn/finn.dmp`

This created a postgresql dump file (text file with SQL command to restore data) in /home/finn, which is the same as where you downloaded finn from GitHub.

Restoration can be done with `psql` command with the dump file.  Example below creates new container that restores backed up data.

First, create new docker volume (virtual disk space where PostGIS databse is stored).

`docker volume create pg_data2`

Create new docker container 'finn_testrestore' to restore database (example below is for powershell.  user appropriate path for first -v option if you are on different OS).

```powershell
docker run --name finn_testrestore -v ( (pwd | docker-path) + ':/home/finn') -v pg_data2:/var/lib/postgresql -p 5432:5432 -p 8888:8888 -d -e EARTHDATAUSER=yourusername -e EARTHDATAPW=yourpassword finn
```

Restore the database from backup `finn.dmp` that was created earlier.

`docker exec finn_testrestore sudo -u postgres psql -d finn -f /home/finn/finn.dmp`

Now new container `finn_testrestore` has it's own PostGIS database (stored in `pg_data2` on docker virtual machine).  You can, for example, export the output (last part of `main_XXX.ipynb` to export output without running them.

### 9. Tidy up by removing intermediate or unneeded data

#### 9.1 Removing raw MODIS imagery and intermediate raster data

If you need to remove files to free up hard disk space after running the
FINN preprocessor, you can do so by running the following commands in a
cell at the end of a Jupyter notebook:

```ipython
!rm -rf ../downloads/
!rm -rf ../proc_rst*
```

The first command removes the `downloads` directory which has copy of raw MODIS imagery (hdf files) on EarthLab.  Second command removes all directories that starts with `proc_rst`, where intermediate raster files are created.  ALternatively you can use your system's methods (e.g. `rm` in terminal, Windows Explorer to remove files) to remove the files/directories.

#### 9.2 Removing intermediate fire detection/burned area processing data

The active fire shape file you downloaded from FIRMS website is imported into PostGIS database, and has several intermediate format in the database.  The disk use by the database is checked from Jupyter notebook by `!du -sh /var/lib/postgresql`.  With annual, global processing using combined MODIS/VIIRS detection, disk use was 48GB.  

Or directly from your computer by one of following ways, depending on your OS.  

If you use linux, `du -sh $HOME/pg_data` .  This is where we decided to store database when you created container (`docker run`).  

If you use Windows and using `Docker Destkop for Windows`, easiest way to check diskuse from Windows is to find the size of `C:\Users\Public\Documents\Hyper-V\Virtual hard disks\MobyLinuxVM.vhdx`.  This is the virtual disk image (disk space) for Linux virtual machine.  Docker is started from this Linux virtual machine, and finn preprocessor is running on top of docker.  When finn prorpocessor is set up but starting any analysis, the size of this file was about 10GB.  After running global, annual, MODIS/VIIRS combined case, the size grew to 76GB.   

In order to wipe intermediate data in the database, you'd have to delete each schema in the database.  A query which does this clean-up will be provided soon.

**[TODO]** Adapt these methods to come up with such query: https://stackoverflow.com/questions/21361169/postgresql-drop-tables-with-query https://stackoverflow.com/questions/2596624/how-do-you-find-the-disk-size-of-a-postgres-postgresql-table-and-its-indexes .  With that, insturction would be `!psql -d finn -f the_wiper.sql`

**[TODO]** In order to reclaim the disk space, the Hyper-V virtual machine's virtual image needs to be shrunk to smaller size.  Not sure this is automatic, or user need to go into Hyper-V manager.

#### 9.3 Remove/Recreate/Update docker components

##### Overview of docker components

:information_source: Diagram below shows components of docker involved in FINN preprocessor.

![docker components](https://github.com/yosukefk/finn_preproc/blob/master/images/docker_components.svg)

The day-to-day task covered in this subsection 7 deals with docker container, represented by boxes starting with "Run" and ending with "Conteiner Rm".  Blue arrows indicates that container is running, and `docker exec` can be issued on the container.  "Stop"/"Start" cycle can be repeated as many times.  You will also note that `docker build` and `docker volume create` commands creates "image" and "volume" respectively.  These exists independently until you explicitly delete them.

FINN preprocessor is designed to save data that you download/generate to be saved outside of Docker system for better persistence of data.  First, all of your downloaded files and intermediate data are stored in finn_preproc directory which you created near begining.  We are using docker's "bind-mount" method to access the directory both from inside and outside of docker.  

Another location where FINN store data is PostgreSQL (PostGIS) database.  For Linux users, this is $HOME/pg_data directory, and is "bind-mount"ed similarly to finn_preproc.  The data there can be reused (more later).  For Windows users, we created "named volume" pg_data by command `docker volume create pg_data`.  This will set a directory inside Linux virtual machine (Hyper-V), and docker container is going to access the space to store the database.  Life of docker named volume is independent of docker images and containers, and it persist unless you explicitly delete the volume.

Following section has commands for deleting cocker components used in FINN.  With the exception of removing docker volumes, these have little effects on disk use, as FINN preprocer does not store data in containers/images.  

##### Removing the container

To permanently delete the FINN container, you have to first stop the container `docker stop finn`, then you can use:

```bash
docker rm finn
```

or 

```bash
docker container rm finn
```

Note that this does not delete the files in finn_preproc directory, or the PostgreSQL database stored inside docker volume (Windows) or $HOME/pg_data (Linux).  It simply remove the container which can be easily recreated, by `docker run` command described in Section 5.1.  By using argumeents for `-v pg_data:/var/lib/postgresql` (or `-v ${HOME}/pg_data:/var/lib/postgresql` for Linux), the content of database is unaffected, and all the data you created earlier are still available as it was before removing the container.

##### Removing the image

You have to first remove container made from the image, following the instruction above.  If you created more than one container from the image, all of containers needs to be removed.

```bash
docker rmi finn
```

or 

```bash
docker image rm finn
```

Again, this does not remove any files in finn_preproc directory, or the PostgreSQL database.  Image can be recreated with `docker build` command described in Section 4.


##### Removing the volume 

This applies to Windows users, which uses `docker volume create` to create named volume to house the PostgreSQL database.  

```bash
docker volume rm pg_data
```

This will wipe the PostgreSQL datbase (PostGIS database) stored in Linux virtual machine.  You can now start from Section 5 to create new volume (`docker volume create`) and create container (`docker run`).  The database for this new container is near empty.

:information_source: The content of pg_data is native format for the specific versoin of PostgreSQL.  If you copy the entire directory/files to somewhere and let postgreSQL to point to the directory, the database starts with the data.  This means that that if you have copy of entier pg_data in somewhere safe, you can start the database by restoring the content.  To be specific, you first wipe the pg_data as specified here (or `rm -fr ${HOME}/pg_data` for linux), and then create new docker volume/container to have fresh databse.  You stop the container, and overwrite the content of `pg_data` with copy of older versoin.  You start the docker container, then the database is populated with the old data.  This could be an alternative way to backup/restore the database, rather than the canonical method of creating database dump as explained in Secton 8.  This is easy for Liunx, as pg_data is a directory in host machine.  A log harder to actually do this, because you have to get into Hyper-V linux virtual machine to do the same (this tool lets you do this https://github.com/justincormack/nsenter1).  Moreover, you have to make sure that file ownership is set correctly after restoring data:  PostgreSQL for Linux is pecific about file ownership, and this was the reason why we have to use named volume (diskspace inside Linux virtual machine), instead of bind-mounte volume (directly accessing host computer's diskspace) for Windows application.  

### 10 Update FINN

Note that updating FINN code won't affect your data on the database you have worked on, or input/output you have generated.  It only updates the code to create them.   The only exception that you may loose your work in main_generic.ipynb.  Update will wipe what you have done to the file.  If have customized the file, you save the file with different name before you update FINN.  Better yet, you save in different name if you customized the file (e.g., save as `work_global_2016/main_global_2016.ipynb` for global run for year 2016).

First stop running containers and remove.  Remove the image as well.

```
docker stop finn
docker container rm finn
docker image rm finn
```

In the Terminal, navigate to main directory `../finn_preproc`  
Then type:

```
git checkout -- .
git pull
``` 

You now recreate image (`docker build` as in Section 4) and container (`docer run` as in Section 5.1).  


### 11. Disaster recovery

##### Try this first, restart the container

Stop container and start again.  See section 7 for instructions.

##### Restart docker

Sometimes, restarting the container does not resolves the glitches introduced at runtime.  We noticed several times that restarting docker will resolve the unpredictable behavior of docker container.

For docker desktop for Windows, System taks tray have the whale icon for Docker Desktop.  You can right-click the icon and choose `Restart...`.  On linux, you can `sudo service docker restart`

##### Check if the system has changed in any way

From our experiences, docker may appear to stop functioning because changes in your system.  We observed that

- If you started VPN, docker may lose access to local storage. As a result you cannot see the conent of finn_preproc directory from docker (e.g. Jupyter Notebook).  Stop the VPN and restart the container (`docker stop finn` and then `docker start finn`)
- If you changed password for your machine or domain, it may affects docker.  On `Docker Desktop for Windows`, you can go to the setting (right click the system tray icon for docker), go to  `Shared Drive` tab, and `Reset credentials`.  Then enable the shared drive again.
- You have to be in a user group `docker` in order to use docker.  Make sure that you are in `docker` user.  [Instruction for Docker Desktop for Windows are found here](https://github.com/yosukefk/finn_preproc/wiki/Specific-instructions-for-Docker-Desktop-for-Windows#2-add-yourself-to-docker-users-group).  Linux instruction is ["Manage Docker as a non-root user" section in thie page](https://docs.docker.com/install/linux/linux-postinstall/#manage-docker-as-a-non-root-user).

##### Recreate container/image/volume 

From our experience, this usually does not resolves the "disaster", i.e. Docker suddenly stop working.  This is more of tidy up task.  Go through three kind of Docker `rm` commands to remove docker componets.  You can then start again from Section 4.

##### Last resort, i.e. start over

To wipe everythign and start over, you can first remove everytinng in finn_postproc directory.  You can do it by Windows Explorer, for example.

You also remove all docker containers/images/volumes to start over.  

One way to do this is remove stop/remove all containers, remove images, remove volumes.

```
docker stop finn
docker container rm finn
docker image rm finn
docker volume rm pg_data
```

An easier way to remove docker components for Windows is to uninstall the docker desktop.  Go to `Control Panel` ==> `Programs and Features` and unistall `Docker Desktop`.  The action wipes out the Linux virtual machine (Hyper-V virtual machine) created for Docker, and in effect wipe everything out.  You can then start from Section 1.
