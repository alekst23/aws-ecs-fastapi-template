# API Usage Guide

## Authentication

This API uses Bearer Token authentication with API keys. All API endpoints (except `/health` and root `/`) require a valid API key.

### Generating an API Key

You can generate a secure random API key using various methods:

**Using OpenSSL:**
```bash
openssl rand -base64 32
```

**Using Python:**
```bash
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

**Using Node.js:**
```bash
node -e "console.log(require('crypto').randomBytes(32).toString('base64url'))"
```

### API Key Location

Your API key is stored in the `.env` file:
```bash
API_KEY=your-generated-api-key-here
```

### Making Authenticated Requests

Include your API key in the `Authorization` header as a Bearer token:

```bash
Authorization: Bearer your-generated-api-key-here
```

## Example API Calls

### Get All Items
```bash
curl -X GET "http://your-api-url/api/v1/items" \
  -H "Authorization: Bearer your-generated-api-key-here"
```

### Create a New Item
```bash
curl -X POST "http://your-api-url/api/v1/items" \
  -H "Authorization: Bearer your-generated-api-key-here" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Example Item",
    "description": "An example item",
    "price": 29.99
  }'
```

### Get Specific Item
```bash
curl -X GET "http://your-api-url/api/v1/items/1" \
  -H "Authorization: Bearer your-generated-api-key-here"
```

### Update Item
```bash
curl -X PUT "http://your-api-url/api/v1/items/1" \
  -H "Authorization: Bearer your-generated-api-key-here" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Updated Item",
    "description": "Updated description",
    "price": 39.99
  }'
```

### Delete Item
```bash
curl -X DELETE "http://your-api-url/api/v1/items/1" \
  -H "Authorization: Bearer your-generated-api-key-here"
```

## Accessing API Documentation

### Protected Documentation
When API key authentication is enabled, the Swagger docs are protected and require your API key:

- **Swagger UI**: `http://your-api-url/docs` (requires API key)
- **ReDoc**: `http://your-api-url/redoc` (requires API key)

To access the docs, include the Authorization header:
```bash
curl -H "Authorization: Bearer your-generated-api-key-here" \
  http://your-api-url/docs
```

### Public Endpoints
These endpoints do NOT require authentication:
- `GET /` - Root endpoint
- `GET /health` - Health check

## Error Responses

### Missing API Key
```json
{
  "detail": "Invalid or missing API key"
}
```
Status Code: 401 Unauthorized

### Invalid API Key
```json
{
  "detail": "Invalid or missing API key"
}
```
Status Code: 401 Unauthorized

## Security Notes

1. **Keep your API key secret** - Never commit it to version control
2. **Use HTTPS in production** - API keys should only be transmitted over secure connections
3. **Rotate keys regularly** - Generate new API keys periodically
4. **Monitor usage** - Check your API logs for suspicious activity

## Disabling Authentication

For development, you can disable API key authentication by setting:
```bash
ENABLE_API_KEY_AUTH=false
```

When disabled:
- All endpoints become public
- Swagger docs are accessible without authentication
- API key header is ignored