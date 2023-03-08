#!/usr/bin/env python3

from test_compare_outputs import work
from pathlib import Path

if __name__ == '__main__':


    ddirs = {
            'expected': Path('../work_generic/sample_output'),
            'notebook': Path('../work_generic'),
            'no-notebook': Path('../output_data/fire/testOTS_092018'),
            }
    fnames = { knd: d / 'out_testOTS_092018_modlct_2017_modvcf_2017_regnum.csv' for knd,d in ddirs.items()}

    results = work(fnames)
    results.to_csv('compare_oregon.csv')

