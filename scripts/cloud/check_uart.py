"""Compile UART sources with slang; this does not run a simulation."""
import argparse
from pathlib import Path
import shlex
import sys

from pyslang.driver import Driver

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prerequisites', action='store_true')
parser.add_argument('--tools-dir', type=Path)
options = parser.parse_args()
root = Path(__file__).resolve().parents[2]
tools = (options.tools_dir or root.parent / '.uart-tools').resolve()
uvm = tools / 'uvm' / 'distrib' / 'src'
source = Path(__file__).with_name(
    'prerequisites.sv' if options.prerequisites else 'compile.sv'
)
args = ['--single-unit', '--timescale', '1ns/10ps', '--error-limit', '20']
args += [f'-I{path}' for path in (uvm, root / 'src', root / 'tb', root / 'test')]
args.append(str(source))
driver = Driver()
driver.addStandardArgs()
driver.setTerminalColorsEnabled(False)
if not driver.parseCommandLine(shlex.join(args)) or not driver.processOptions():
    sys.exit(2)
if not driver.parseAllSources():
    driver.reportParseDiags()
    sys.exit(1)
sys.exit(0 if driver.runFullCompilation() else 1)
