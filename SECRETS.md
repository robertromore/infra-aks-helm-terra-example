# Required GitHub Secrets

Set up these secrets in your GitHub repository:

`AZURE_CREDENTIALS`: Service principal credentials for Azure
`GITHUB_TOKEN`: GitHub Personal Access Token with packages:read and packages:write permissions

# Required Terraform Variables

For SSL certificate management with Cloudflare DNS validation, set these variables in your `terraform.tfvars` file or as environment variables:

## Cloudflare Configuration
- `cloudflare_api_token`: Cloudflare API token with Zone:Edit and Zone:Read permissions
- `cloudflare_zone_id`: Cloudflare Zone ID for your domain
- `domain_name`: Your domain name (e.g., example.com)

## GitHub Container Registry
- `github_username`: Your GitHub username
- `github_token`: GitHub Personal Access Token (same as GITHUB_TOKEN secret)
- `github_email`: Your GitHub email address

## Creating Cloudflare API Token

1. Go to Cloudflare Dashboard → My Profile → API Tokens
2. Create a custom token with these permissions:
   - Zone:Zone:Read
   - Zone:DNS:Edit
3. Include your specific zone in the resources
4. Copy the generated token (you'll only see it once)

## Environment Variables Alternative

For enhanced security, use environment variables instead of terraform.tfvars:

```bash
export TF_VAR_cloudflare_api_token="your-cloudflare-token"
export TF_VAR_cloudflare_zone_id="your-zone-id"
export TF_VAR_domain_name="yourdomain.com"
export TF_VAR_github_username="your-username"
export TF_VAR_github_token="your-github-token"
export TF_VAR_github_email="your-email@yourdomain.com"
```

⚠️ **Security Note**: Never commit `terraform.tfvars` to version control. Use the provided `terraform.tfvars.example` as a template.
