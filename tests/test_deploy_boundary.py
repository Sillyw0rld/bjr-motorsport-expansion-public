# SPDX-License-Identifier: AGPL-3.0-or-later
import importlib.util
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('deploy_bjr',ROOT/'dist/deploy-bjr.py')
deploy=importlib.util.module_from_spec(spec);spec.loader.exec_module(deploy)

class DeployBoundary(unittest.TestCase):
    def test_bjr_owned_paths_are_never_deployed(self):
        self.assertTrue(deploy.is_bjr_owned('Resources/Client/BJ.zip'))
        self.assertTrue(deploy.is_bjr_owned('Resources/Server/BeamJoyServer/main.lua'))
        self.assertTrue(deploy.is_bjr_owned('Resources/Server/BeamJoyServerHooks/main.lua'))
        self.assertFalse(deploy.is_bjr_owned('Resources/Client/BJR_RacePrep.zip'))
        self.assertFalse(deploy.is_bjr_owned('Resources/Server/RacePrep/RacePrep.lua'))

if __name__=='__main__':unittest.main()
