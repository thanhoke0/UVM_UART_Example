# Cloud development setup

Use the existing checkout in the isolated cloud environment. No Git worktree is
needed. Python 3 with venv support, Git, and HTTPS access to github.com, pypi.org,
and files.pythonhosted.org are required. No additional credentials are needed
for these public dependencies.

From the repository root:

```bash
bash scripts/cloud/setup.sh
```

This installs pyslang 11.0.0 and Accellera UVM 1.2 (commit
`71f30a7473118b3cea582d7673c3af8e161fce71`) into the sibling `.uart-tools`
directory. Set `UART_TOOLS_DIR` to use another writable directory. Existing UVM
checkouts at a different revision are rejected rather than overwritten.
The command is repeatable and runs a prerequisite compilation of UVM, both
interfaces, and `uart_host_config`. Warnings may be emitted; success requires
an exit status of zero. No services need to start.

For the default `/workspace/UVM_UART_Example` checkout, run full static compilation:

```bash
/workspace/.uart-tools/venv/bin/python scripts/cloud/check_uart.py
```

If using a custom tools directory, use its Python and pass
`--tools-dir /absolute/path/to/tools` to the checker.

The prerequisite compilation passed during onboarding. Full compilation fails
on missing repository definitions, including `uart_trans` and `UART_WRITE`.
Inspection also found missing `uart_top` RTL, `cpu_rw_sequence`,
`ral_block_uart`, AHB integration, and clock period definitions in
`tb/dut_wrapper.sv`. The root README describes intentional omissions.
`testbench_ready.sv` is an alternative bundled source, not a verified runnable
simulation target.

pyslang performs static compilation, not simulation. No UART functional test has
passed and no UVM simulator or license is installed by this setup. Complete
source dependencies and a suitable simulator are required before running
`uart_rdwr_test`. Do not treat a passing prerequisite compilation as validation
of UART TX/RX behavior. Source repairs are separate from environment setup.
