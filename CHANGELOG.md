# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive Implementation Plan with step-by-step deployment guide
- Complete Helm chart documentation with configuration examples
- Enhanced Helm templates with proper component labels and selectors
- Pod Disruption Budget for high availability
- Conditional deployment templates (queue workers, scheduler)
- Database migration init container with PostgreSQL support
- Comprehensive health checks (liveness, readiness, startup probes)
- Service Account template with proper RBAC configuration
- Secret management template
- Helper functions for database connectivity

### Changed
- **BREAKING**: Standardized file extensions to `.yaml` (was mixed `.yml`/`.yaml`)
- Updated Chart.yaml to use proper Helm chart format
- Enhanced deployment templates with PostgreSQL support (was MySQL)
- Improved component labeling and selector strategies
- Updated CI/CD pipeline to include Helm dependency management
- Restructured values.yaml with proper configuration sections
- Enhanced production values with high-availability configurations

### Fixed
- Database wait container now uses PostgreSQL port 5432 instead of MySQL 3306
- Proper selector labels for web components vs queue workers
- Missing service account automation configuration
- Inconsistent file naming conventions across the repository
- Missing Helm template files (service, ingress, serviceaccount, secret)
- Queue deployment template now includes proper security contexts
- Scheduler template enhanced with complete Kubernetes manifest structure

### Security
- Added security contexts for all pod templates
- Implemented proper RBAC with service accounts
- Enhanced secret management with Kubernetes native approach

## [1.0.0] - Initial Release

### Added
- Basic Helm charts for Laravel API deployment
- Terraform infrastructure configuration for AKS
- GitHub Actions CI/CD pipelines
- Basic Kubernetes manifests
- Documentation for setup and deployment

### Infrastructure
- Azure Kubernetes Service (AKS) deployment
- GitHub Container Registry integration
- Traefik ingress controller
- cert-manager for SSL certificates
- PostgreSQL and Redis dependencies

---

## Migration Notes

### v1.0.0 to v1.1.0

**File Extension Changes**:
- All YAML files now use `.yaml` extension consistently
- Update any scripts or references that use `.yml` extensions

**Helm Chart Changes**:
- New helper templates in `_helpers.tpl`
- Enhanced selector labels - check custom configurations
- New conditional templates may require values adjustment

**Database Changes**:
- Wait container now connects to PostgreSQL (port 5432)
- Database migration is now conditional (`databaseMigration.enabled`)

**Required Actions**:
1. Update any hardcoded file references from `.yml` to `.yaml`
2. Review custom values files for new configuration options
3. Test deployments in staging environment before production
4. Update CI/CD pipelines if they reference specific file names