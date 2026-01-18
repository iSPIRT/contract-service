# Contact Ledger Service

This repository contains the source code for contract service, an application
that runs on top of [CCF](https://ccf.dev/) implementing standards developed within the [DEPA Training Framework](https://github.com/iSPIRT/depa-training/). Its purpose is to provide registry for contracts. The contract service achieves this by allowing signed contracts to be submitted to a secure immutable ledger, and returning receipts which prove contracts have been stored.

This research project is at an early stage and is open sourced to facilitate academic collaborations. We are keen to engage in research collaborations on this project, please do reach out to discuss this by opening an issue.

## Getting Started

The instructions below guide you through building and deploying a local instance of contract service for development and testing purposes.

Being a CCF application, contract service runs in SGX enclaves. However, for testing purposes, it also supports running on non-SGX hardware in what is called *virtual* mode.

All instructions below assume Linux as the operating system.

### Quick Demo

A live contract ledger service (single-node, virtual mode) for demos is available at **https://216.48.178.54:8000**. This service can be used to sign contracts and register them on the ledger via the [demo UI](./demo-ui/README.md). This GUI application provides a user-friendly web interface for demonstrating multi-party electronic contract signing for selected DEPA training scenarios.

The quickest way to get started is to create a GitHub Codespace on the `main` branch, run `./launch-demo.sh` from the project root, then open your browser and navigate to **http://localhost:5050**

1. Go to **Code → Codespaces → Create codespace on main**
2. Open a terminal and run:
   ```bash
   ./launch-demo.sh
   ```
   This script installs all required prerequisites and launches the demo UI.
3. Open your browser and navigate to **http://localhost:5050**

This demo requires two GitHub accounts and corresponding GitHub Pages user/organization sites, one for the Training Data Providers (TDPs - represented in this demo by a single entity for sake of simplicity) and one for the Training Data Consumer (TDC). To create a GitHub page site, follow the [GitHub Pages user/organization documentation](https://pages.github.com/). You will be asked to create a new repository with the URL `<username>.github.io`. If you don't have two GitHub accounts or you don't want to use the GitHub Pages site associated with your account, you can create a new user on [GitHub](https://github.com/signup).

Note: If you’re using GitHub Codespaces, be sure to create and use separate Codespace instances under the respective GitHub accounts for the TDP and TDC, when executing the contract signing steps specific to each of them.

If you encounter any issues with the live demo service, please contact the repository owners by opening an issue. To run your own instance of the contract service, follow the instructions below.

### Build and Deploy using Docker

Use the following commands to start a single-node CCF network with the contract service application setup for development purposes.

Note: `PLATFORM` should be set to `sgx` or `virtual` to select the type of build.

```sh
export PLATFORM=<sgx|virtual>
./docker/build.sh
./docker/run-dev.sh
```

The node is now reachable at https://127.0.0.1:8000/.

Alternatively, a live demo contract service is available at **https://216.48.178.54:8000** for testing purposes. If you encounter any issues, please contact the repository owners by opening an issue.

Note that `run-dev.sh` configures the network in a way that is not suitable for production, in particular it generates an ad-hoc governance member key pair and it disables API authentication.

### Sign and Register Contracts

Follow [instructions](./demo/contract/README.md) on how to sign and register contracts with an active contract service. You can also try the [demo UI](./demo-ui/README.md) to sign and register contracts using a user-friendly web interface.

### Development setup

See [DEVELOPMENT.md](DEVELOPMENT.md) for instructions on building, running, and testing contract-ledger without Docker.

### Using the CLI

To help with the configuration of an application or to be able to interact with its API you could leverage the available CLI.

The `pyscitt` CLI is written in Python and is available on PyPi [here](https://pypi.org/project/pyscitt/). To install it, you can use the following command:

```sh
pip install pyscitt
```

The CLI is also distributed through the GitHub releases as a `wheel` file. Optionally, it can be used from within the repository using the [`./pyscitt.sh`](../pyscitt.sh) script. For example: 

```sh
./pyscitt.sh --help
```

The CLI is extensively used in the following functional tests and demo scripts:

- [Transparency service demo](../demo/cts_poc/README.md)
- [GitHub hosted DID demo](../demo/github/README.md)
- [CLI tests](../test/test_cli.py)

See [pyscitt](pyscitt/README.md) for more details.

### Reproducing builds

See [reproducibility.md](./docs/reproducibility.md) for instructions.

## Contributing

This project welcomes contributions and suggestions. Please see the [Contribution guidelines](CONTRIBUTING.md).
