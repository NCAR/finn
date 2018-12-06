# FINN Preprocessor

PostGIS based preprorcessor.  Given point feature of active fire detections, this code estimates burned region, and then determine land cover on the burned area.


## Instructions


### Starting the Docker container

Start the container via `docker run`, mounting the current working directory to the location `/home/finn` in the container. 

```bash
docker run -v $(pwd):/home/finn --name 'finn' -p 5432:5432 -p 8888:8888 -d -e EARTHDATAUSER=yourusername -e EARTHDATAPW=yourpassword finn
```

To verify that the container is running, type `docker ps`. 
You should see the container listed with a unique container id, the name "finn" and some other information. 

Once the container is running, we can launch a jupyter notebook using `docker exec`: 

```
docker exec -it finn jupyter notebook --ip=0.0.0.0 --port=8888 --allow-root --notebook-dir /home/finn
```

Then, go to `localhost:8888` in a web browser to open the notebook interface. 
If running on a remote server (e.g., an Amazon EC2 instance) replace `localhost` with the server's IP address. 


### Running the notebook

To open the notebook, navigate to the `code_anaconda/` directory and open `main.ipynb`. 
This notebook runs FINN (press Shift+Enter to run a cell), including the components related to downloading MODIS data.

    > Note that 2016 is the only year currently supported.
