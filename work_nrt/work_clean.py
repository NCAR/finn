#!/usr/bin/env python3

import sys
import argparse
from pathlib import Path

## finn preproc codes
sys.path = sys.path + ['../code_anaconda']
import run_extra

import work_common as common



def main(tag_af, summary_file = None):

    user_config = common.sec1_user_config(tag_af, af_fnames=None, year_rst=None)
    globals().update(user_config)

    if summary_file is not None:
        summary_file = Path(summary_file).open('a')

    run_extra.purge_db_af(tag_af, outfile=summary_file)



if __name__ == '__main__':

    #parser = argparse.ArgumentParser(formatter_class = argparse.ArgumentDefaultsHelpFormatter)
    parser = argparse.ArgumentParser()
    required_named = parser.add_argument_group('required arguments')

    required_named.add_argument('-t', '--tag_af', 
            default=None, required=True, help='tag for AF processing', type=str)
    parser.add_argument('-s', '--summary_file', 
            default=None, required=False, help='summary filename', type=str)

    args = parser.parse_args()
    print(args)
    
    main(**vars(args))
