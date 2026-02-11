# Project Overview

This project uses [Rust](https://rust-lang.org) for the backend and
[React](https://react.dev) for the frontend. See the [architecture](architecture.md)
document for details.

## Getting Started

Clone the repo and run the [setup script](setup.md). You'll need
[Docker](https://docker.com) installed for local development.

## Components

The API layer handles authentication and request routing.
See [API reference](api-reference.md) for endpoint documentation.

### Data Layer

The data layer uses PostgreSQL with connection pooling.
