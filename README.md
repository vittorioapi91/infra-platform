# Infra-Platform

Infrastructure platform stack for the TradingPythonAgent project. This repository contains all infrastructure components including Docker Compose configurations, Kubernetes manifests, Jenkins pipelines, and monitoring services.

## 🎯 Overview

Infra-Platform provides a complete infrastructure stack for:

- **Container Orchestration**: Docker Compose configurations for all infrastructure services
- **CI/CD**: Jenkins pipelines for infrastructure validation and deployment
- **Kubernetes**: Manifests and scripts for Kubernetes/kind cluster management
- **Monitoring**: Prometheus, Grafana, and MLflow configurations
- **Workflow Orchestration**: Airflow DAGs and configurations
- **Service Management**: Startup scripts and LaunchAgent configurations

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Infrastructure Services                      │
├─────────────────────────────────────────────────────────────┤
│  Airflow │ Jenkins │ Grafana │ Prometheus │ MLflow         │
│  PostgreSQL │ Redis │ Kubernetes │ Feast │ KServe          │
└─────────────────────────────────────────────────────────────┘
```

## 📦 Repository Structure

```
infra-platform/
├── airflow/                     # Airflow DAGs and configuration
├── docker/                      # Docker Compose configurations
│   ├── docker-compose.infra-platform.yml  # Infrastructure services
│   ├── docker-compose.yml       # Application services (future use)
│   ├── Dockerfile.jenkins       # Jenkins Docker image
│   └── Dockerfile.jenkins.base   # Base Jenkins image
├── feast/                       # Feast feature store configuration
├── grafana/                     # Grafana dashboards and configuration
├── jenkins/                     # Jenkins configuration and plugins
├── kserve/                      # KServe model serving configuration
├── kubeflow/                    # Kubeflow pipelines configuration
├── kubernetes/                  # Kubernetes manifests and scripts
│   ├── hmm-model-training-job.yaml
│   ├── monitoring-stack.yaml
│   └── start-kubernetes.sh
├── mlflow/                      # MLflow configuration
├── prometheus/                  # Prometheus configuration
├── Jenkinsfile.infra-platform   # Infrastructure CI/CD pipeline
├── start-all-services.sh        # Service startup script
├── com.tradingagent.services.plist  # macOS LaunchAgent configuration
└── README.md                    # This file
```

## 🚀 Quick Start

### Prerequisites

- Docker and Docker Compose
- Kubernetes/kind (optional, for Kubernetes deployments)
- kubectl (optional, for Kubernetes management)

### Starting Infrastructure Services

#### Using the Startup Script

```bash
# Start all services
./start-all-services.sh
```

#### Using Docker Compose

```bash
# Start infrastructure services
cd docker
docker-compose -f docker-compose.infra-platform.yml up -d

# Or use the convenience script
./start-docker-monitoring.sh
```

### Service URLs

Once services are running, they are available at:

- **Airflow**: http://localhost:8080
- **Jenkins**: http://localhost:8081
- **Grafana**: http://localhost:3000 (admin/admin)
- **MLflow**: http://localhost:55000
- **Prometheus**: http://localhost:9090
- **Kubernetes Dashboard**: https://localhost:8001
- **PostgreSQL**: localhost:55432
- **Redis**: localhost:6379

## 📋 Services

### Docker Compose Services

The infrastructure stack includes:

- **Airflow**: Workflow orchestration (dev/test/prod environments)
- **Jenkins**: CI/CD pipeline automation
- **Grafana**: Metrics visualization and dashboards
- **Prometheus**: Metrics collection and storage
- **MLflow**: ML experiment tracking and model registry
- **PostgreSQL**: Database for application data
- **Redis**: Caching and message broker

### Kubernetes Services

- **Kind Cluster**: Local Kubernetes cluster for development
- **Kubernetes Dashboard**: Web UI for cluster management
- **Monitoring Stack**: Prometheus and Grafana in Kubernetes
- **Model Training Jobs**: Kubernetes Jobs for ML model training

## 🔧 Configuration

### Docker Compose

Configuration files are in `docker/`:

- `docker-compose.infra-platform.yml`: Main infrastructure services
- `docker-compose.yml`: Application services (future use)
- `docker-compose.override.yml.example`: Example override file

See [`docker/README.md`](docker/README.md) for detailed Docker setup.

### Kubernetes

Kubernetes manifests are in `kubernetes/`:

- `hmm-model-training-job.yaml`: ML model training job
- `monitoring-stack.yaml`: Monitoring services stack
- `start-kubernetes.sh`: Script to create and configure kind cluster

See [`kubernetes/README.md`](kubernetes/README.md) for Kubernetes setup.

### Jenkins

Jenkins configuration is in `jenkins/`:

- Pipeline definitions
- Plugin configurations
- Custom Jenkins images

The `Jenkinsfile.infra-platform` validates and builds infrastructure components.

## 🏭 CI/CD Pipeline

### Infrastructure Pipeline

The `Jenkinsfile.infra-platform` pipeline:

1. **Validates Configuration**: Checks Docker Compose files and Kubernetes manifests
2. **Builds Images**: Builds Jenkins and other infrastructure images
3. **Validates Services**: Ensures services can start correctly
4. **Validates Kubernetes**: Checks kind cluster and Kubernetes resources

### Triggering the Pipeline

The pipeline runs automatically when infrastructure files change, or can be triggered manually in Jenkins.

## 🖥️ macOS LaunchAgent

The repository includes a LaunchAgent configuration (`com.tradingagent.services.plist`) to automatically start services on macOS boot.

### Installation

```bash
# Copy the plist file to LaunchAgents directory
cp com.tradingagent.services.plist ~/Library/LaunchAgents/

# Load the service
launchctl load ~/Library/LaunchAgents/com.tradingagent.services.plist

# Start the service
launchctl start com.tradingagent.services
```

### Uninstallation

```bash
# Unload the service
launchctl unload ~/Library/LaunchAgents/com.tradingagent.services.plist

# Remove the plist file
rm ~/Library/LaunchAgents/com.tradingagent.services.plist
```

## 📖 Documentation

- **Docker Setup**: [`docker/DOCKER_SETUP.md`](docker/DOCKER_SETUP.md)
- **Docker Start Guide**: [`docker/DOCKER_START.md`](docker/DOCKER_START.md)
- **Kubernetes Setup**: [`kubernetes/README.md`](kubernetes/README.md)
- **Kubernetes Quick Start**: [`kubernetes/QUICK_START.md`](kubernetes/QUICK_START.md)
- **Jenkins Image Build**: [`docker/BUILD_JENKINS_IMAGE.md`](docker/BUILD_JENKINS_IMAGE.md)
- **Base Images**: [`docker/README_BASE_IMAGES.md`](docker/README_BASE_IMAGES.md)

## 🔗 Related Repositories

- **TradingPythonAgent**: Main application repository
  - Contains application code, data collection modules, and ML models
  - References this infrastructure repository for deployment

## 🛠️ Development

### Building Base Images

Some infrastructure images require base images to be built manually:

```bash
cd docker
docker build -t jenkins-custom:base -f Dockerfile.jenkins.base .
```

See [`docker/README_BASE_IMAGES.md`](docker/README_BASE_IMAGES.md) for details.

### Local Development

1. Clone the repository
2. Start services using Docker Compose
3. Make changes to configurations
4. Test changes locally
5. Commit and push changes

### Testing Infrastructure Changes

The Jenkins pipeline automatically validates:
- Docker Compose file syntax
- Kubernetes manifest validity
- Airflow DAG syntax
- Service startup capabilities

## 🔐 Security

- **Never commit** sensitive credentials or API keys
- Use environment variables or secure credential stores
- Review Docker Compose configurations before deployment
- Keep base images updated with security patches

## 📝 License

[Add your license here]

## 🤝 Contributing

1. Create a feature branch
2. Make your changes
3. Test thoroughly
4. Submit a pull request

## 🐛 Troubleshooting

### Services Won't Start

- Check Docker is running: `docker info`
- Verify ports are not in use: `lsof -i :8080`
- Check Docker Compose logs: `docker-compose -f docker/docker-compose.infra-platform.yml logs`

### Kubernetes Issues

- Verify kind cluster exists: `kind get clusters`
- Check cluster context: `kubectl config current-context`
- Review Kubernetes logs: `kubectl logs -n <namespace> <pod-name>`

### Jenkins Pipeline Failures

- Check Jenkins logs in Docker: `docker logs <jenkins-container>`
- Verify base images are built
- Review pipeline console output in Jenkins UI

## 📞 Support

For issues or questions:
1. Check the relevant documentation in subdirectories
2. Review service logs
3. Check Jenkins build logs
4. Review GitHub issues

---

**Built with**: Docker, Kubernetes, Jenkins, Airflow, Prometheus, Grafana, MLflow
