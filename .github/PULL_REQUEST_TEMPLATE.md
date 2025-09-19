# Algalon Infrastructure Pull Request

## Description

Brief description of the changes and their purpose.

## Type of Change

- [ ] 🐛 Bug fix (non-breaking change which fixes an issue)
- [ ] ✨ New feature (non-breaking change which adds functionality)
- [ ] 💥 Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] 📚 Documentation update
- [ ] 🧹 Code cleanup/refactoring
- [ ] ⚡ Performance improvement
- [ ] 🔒 Security improvement
- [ ] 🧪 Test improvements

## Changes Made

### Infrastructure Changes
- [ ] Network module modifications
- [ ] Host module modifications
- [ ] Worker module modifications
- [ ] Example configurations
- [ ] New modules added

### Testing Changes
- [ ] Unit tests added/modified
- [ ] Integration tests added/modified
- [ ] E2E tests added/modified
- [ ] Security tests added/modified

### Documentation Changes
- [ ] README updates
- [ ] Module documentation
- [ ] Testing documentation
- [ ] Cloud deployment guide

## Testing Checklist

### Pre-submission Testing
- [ ] `make format` - Code is properly formatted
- [ ] `make validate` - Terraform configurations are valid
- [ ] `make lint` - No linting errors
- [ ] `make security` - Security scan passes
- [ ] `make test-unit` - Unit tests pass locally
- [ ] `make docs-check` - Documentation is up to date

### Integration Testing (if applicable)
- [ ] `make test-integration` - Integration tests pass
- [ ] `make test-e2e` - End-to-end tests pass
- [ ] Manual testing in development environment

## Security Considerations

- [ ] No hardcoded secrets or credentials
- [ ] Firewall rules follow least privilege principle
- [ ] Service accounts have minimal required permissions
- [ ] Security scan results reviewed and addressed
- [ ] Any new security exceptions documented and justified

## Breaking Changes

If this PR introduces breaking changes, describe:

1. What breaks:
2. Migration path:
3. Backward compatibility plan:

## Cost Impact

- [ ] No significant cost impact
- [ ] Minor cost increase (< $10/month)
- [ ] Moderate cost increase ($10-100/month)
- [ ] Major cost increase (> $100/month)

**Cost Details** (if applicable):
- New resources added:
- Resource size changes:
- Estimated monthly cost change:

## Deployment Impact

- [ ] Safe to deploy during business hours
- [ ] Requires maintenance window
- [ ] Requires coordination with other teams
- [ ] May cause temporary service disruption

**Deployment Notes**:

## Screenshots/Logs

If applicable, add screenshots or log outputs that help explain the changes.

## Related Issues

Closes #(issue_number)
Related to #(issue_number)

## Review Checklist

### For Reviewers

#### Code Quality
- [ ] Code follows project style guidelines
- [ ] Changes are well documented
- [ ] Complex logic is commented
- [ ] No obvious performance issues

#### Infrastructure
- [ ] Resource naming follows conventions
- [ ] Labels and tags are appropriate
- [ ] Network security is properly configured
- [ ] Monitoring and logging are adequate

#### Testing
- [ ] Adequate test coverage for changes
- [ ] Tests are meaningful and not just for coverage
- [ ] Test cases cover both success and failure scenarios
- [ ] Integration tests verify end-to-end functionality

#### Security
- [ ] Security best practices followed
- [ ] No sensitive information exposed
- [ ] Firewall rules are restrictive
- [ ] IAM permissions follow least privilege

#### Documentation
- [ ] Changes are documented
- [ ] Examples are updated if needed
- [ ] Breaking changes are clearly documented
- [ ] Migration guide provided if needed

## Additional Notes

Any additional information that reviewers should know.

## Checklist for Author

- [ ] I have performed a self-review of my code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have made corresponding changes to the documentation
- [ ] My changes generate no new warnings
- [ ] I have added tests that prove my fix is effective or that my feature works
- [ ] New and existing unit tests pass locally with my changes
- [ ] Any dependent changes have been merged and published

---

**Note**: This PR will trigger automated testing including:
- Terraform validation and formatting checks
- Security scanning with Checkov
- Unit tests with Terratest
- Cost estimation with Infracost (for infrastructure changes)

Integration and E2E tests can be triggered manually after initial review.