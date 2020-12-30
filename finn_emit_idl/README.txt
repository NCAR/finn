While finn_emit python code becomes QA'd here is version of IDL code for calculte finn emissions.

You need IDL (harrisgeospatial.com/Software-Technology/IDL) to run.

Run global_fire_*.pro first, then speciate*.pro next


First one have giant function which takes *.csv from finn_preproc as input.  Run the code, get an intermediate, unspeciated text file.

Use the output from above for input to next code (again have a giant function).


global_fire_v2.pro:
	"main" function is named global_fire_v2.  I usually try matching file
	name and function name, their could be $MAIN or somethin more clever
	way but that's what i do.  

	you may have to edit path of the directory:
		inputdir: Came with code , the "Inputs" dir
		outputdir: where you want output to go.  You have to make dir
			by yourself
		prepprocdir: where you run preprocessor, and where out_*.csv
			file from preprocessor is, unless you move it around
	
	global_fire_v2: 
	
		the main, driver function.  all it does is to grab right file
		name, year of simulation etc.  see next section

	x_global_fire_v2_02222019_yk3:

		you may have to edit indir and outdir, if you don't like the
		default

		it takes following arguments 
			infile: path/name of preprocessor output CSV file
			simid: a short tag identify the run, used as part of output file
			yearnum: year being simulated
				(code assumes that simulation is for a
				particular year, and fires other than the year got dropped, so that it
				can internally use dayofyear (jd) to specify date) etc.
			input_lct: either "majority" or "all"
				this option is tied to what method was used in
				preprocessor, when more than one LCT overlaid
				on a polygon.  If only Majority LCT was
				exported, specify "majority".  If all LCT are
				exported, use "all" here.

				We are still making final call for  this majority/all
				behavior, and it will be cleaner soon, i hope
			todaydate: date that emission processed

speciate_mozart_finnv2.pro
	baheves similar to global_finn_v2, i will write down 

