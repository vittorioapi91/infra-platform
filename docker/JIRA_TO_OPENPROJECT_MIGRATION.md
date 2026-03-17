# Migration Guide: Jira Cloud to OpenProject

This guide helps you migrate from Jira Cloud to self-hosted OpenProject.

## OpenProject Setup

OpenProject has been added to your infrastructure:

- **Container**: `openproject` (running)
- **Database**: `openproject-postgres` (PostgreSQL 15)
- **Port**: `8086` (direct access)
- **Nginx**: `http://openproject.local.info` (after adding to `/etc/hosts`)
- **Default credentials**: `admin` / `admin` (change on first login)

## Initial Setup

1. **Access OpenProject**:
   - Direct: http://localhost:8086
   - Via nginx: http://openproject.local.info (add `127.0.0.1 openproject.local.info` to `/etc/hosts`)

2. **First Login**:
   - Username: `admin`
   - Password: `admin`
   - **Important**: Change the admin password immediately after first login

3. **Create API Key** (for Jenkins integration):
   - Go to: My Account → Access Tokens
   - Create a new API token
   - Save it securely (you'll need it for Jenkins configuration)

## Data Migration

### Export from Jira

1. **Export Issues**:
   - Go to Jira: Settings → System → Import & Export → Backup System
   - Or use Jira REST API to export issues:
     ```bash
     curl -u "user:token" "https://vittorioapi91.atlassian.net/rest/api/3/search?jql=order+by+created+DESC" > jira_export.json
     ```

2. **Export Projects**:
   - Export project data via Jira's export functionality
   - Or use Jira's CSV export for issues

### Import to OpenProject

1. **Manual Import**:
   - OpenProject supports CSV import for work packages
   - Go to: Projects → Import → CSV
   - Map Jira fields to OpenProject fields

2. **API Import** (for automated migration):
   - Use OpenProject REST API to create work packages
   - API documentation: http://localhost:8086/api/docs

## Jenkins Configuration Update

### Current Configuration

Jenkins is currently configured with:
- `JIRA_URL` → Should be updated to `OPENPROJECT_URL`
- `JIRA_USER` → Maps to OpenProject username
- `JIRA_API_TOKEN` → Maps to OpenProject API key

### Environment Variables

The docker-compose file now includes:
```yaml
- OPENPROJECT_URL=http://openproject:80
- OPENPROJECT_API_KEY=<your-api-key>
```

**Action Required**: Update `OPENPROJECT_API_KEY` in docker-compose or set it as an environment variable.

### Pipeline Updates Needed

Jenkins pipelines use Jira API endpoints that need to be updated for OpenProject:

#### Jira API → OpenProject API Mapping

| Jira Endpoint | OpenProject Endpoint |
|--------------|---------------------|
| `/rest/api/3/myself` | `/api/v3/users/me` |
| `/rest/api/3/issue/{key}` | `/api/v3/work_packages/{id}` |
| `/rest/api/3/search?jql=...` | `/api/v3/work_packages?filters=[...]` |

#### Example: Test Connection

**Jira (old)**:
```groovy
def testApiUrl = "${jiraUrl}/rest/api/3/myself"
```

**OpenProject (new)**:
```groovy
def testApiUrl = "${openprojectUrl}/api/v3/users/me"
```

#### Example: Validate Issue/Work Package

**Jira (old)**:
```groovy
def jiraApiUrl = "${jiraUrl}/rest/api/3/issue/${env.JIRA_ISSUE}"
```

**OpenProject (new)**:
```groovy
// OpenProject uses numeric IDs or subject-based search
def openprojectApiUrl = "${openprojectUrl}/api/v3/work_packages?filters=[{\"subject\":{\"operator\":\"~\",\"values\":[\"${env.ISSUE_KEY}\"]}}]"
```

### Authentication

**Jira**: Basic auth with username:token
```bash
curl -u "user:token" "https://jira.example.com/rest/api/3/..."
```

**OpenProject**: API key in header
```bash
curl -H "Authorization: Bearer YOUR_API_KEY" "http://openproject:80/api/v3/..."
```

Or Basic auth:
```bash
curl -u "apikey:YOUR_API_KEY" "http://openproject:80/api/v3/..."
```

## Branch Naming Convention

Your current branch pattern: `dev/{JIRA_ISSUE}/{project}-{subproject}`

**Options for OpenProject**:
1. **Keep same format**: Use work package ID or subject
   - Example: `dev/WP-123/trading-agent-fundamentals`
   - Extract work package ID from branch name

2. **Use work package ID**: OpenProject uses numeric IDs
   - Example: `dev/12345/trading-agent-fundamentals`
   - Extract numeric ID from branch

3. **Use work package subject**: Search by subject
   - Example: `dev/my-feature-name/trading-agent-fundamentals`
   - Search OpenProject API by subject

## Migration Checklist

- [ ] Access OpenProject and change admin password
- [ ] Create API key for Jenkins integration
- [ ] Export data from Jira
- [ ] Import data to OpenProject (CSV or API)
- [ ] Update `OPENPROJECT_API_KEY` in docker-compose or environment
- [ ] Update Jenkins pipeline scripts to use OpenProject API
- [ ] Test Jenkins pipeline with OpenProject integration
- [ ] Update branch naming convention if needed
- [ ] Update documentation references from Jira to OpenProject
- [ ] Remove old Jira credentials from Jenkins (after migration complete)

## API Documentation

- OpenProject API Docs: http://localhost:8086/api/docs
- OpenProject API Guide: https://www.openproject.org/docs/api/

## Notes

- OpenProject uses numeric IDs for work packages (not alphanumeric keys like Jira)
- Work packages in OpenProject are similar to issues in Jira
- OpenProject API uses JSON:API format
- Filter syntax is different from Jira's JQL
