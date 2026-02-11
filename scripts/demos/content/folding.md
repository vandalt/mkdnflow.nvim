# Architecture

## API Layer

The API uses a RESTful design with [JSON:API](https://jsonapi.org) conventions.

- Authentication via JWT tokens
- Rate limiting per client
- Request validation middleware

| Endpoint       | Method | Auth     |
| -------------- | ------ | -------- |
| /users         | GET    | Required |
| /users/:id     | PUT    | Required |
| /health        | GET    | None     |

## Data Layer

The data layer handles persistence and caching.

- PostgreSQL for primary storage
- Redis for session caching
- Connection pooling via [PgBouncer](https://pgbouncer.org)

```sql
SELECT u.name, u.email
FROM users u
WHERE u.active = true
ORDER BY u.created_at DESC;
```

## Deployment

Deployment is managed through our [CI pipeline](ci-pipeline.md).

1. Build Docker images
2. Run smoke tests
3. Push to container registry
4. Rolling update via Kubernetes
