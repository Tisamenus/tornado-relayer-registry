# Tornado Relayer Registry

[![Build Status](https://img.shields.io/github/workflow/status/h-ivor/tornado-relayer-registry/build)](https://github.com/h-ivor/tornado-relayer-registry/actions) [![Coverage Status](https://img.shields.io/coveralls/github/h-ivor/tornado-relayer-registry)](https://coveralls.io/github/h-ivor/tornado-relayer-registry?branch=new)

Repository for a governance upgrade which includes:

- A new Torn staking mechanism.
- Vault to hold user funds.
- Gas compensation mechanism for functions.

## Setup

```bash
git clone --recurse-submodules https://github.com/h-ivor/tornado-relayer-registry.git
cd tornado-relayer-registry
yarn
cp .env.example .env
yarn test
```
