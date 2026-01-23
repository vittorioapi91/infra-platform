#!/bin/bash
# Quick start script for Grafana, Prometheus, MLflow, Airflow, and PostgreSQL

set -e

echo "🚀 Starting ML Workflow Monitoring Services (Docker Compose)..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Error: Docker is not running. Please start Docker first."
    exit 1
fi

# Navigate to docker directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Start infra-platform services
echo "📦 Starting Infra-Platform services..."
docker-compose -f docker-compose.infra-platform.yml up -d

# Start application services (if any)
if [ -f "docker-compose.yml" ]; then
    echo "📦 Starting Application services..."
    docker-compose -f docker-compose.yml up -d
fi

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 10

# Check service status
echo ""
echo "📊 Infra-Platform Service Status:"
docker-compose -f docker-compose.infra-platform.yml ps

if [ -f "docker-compose.yml" ]; then
    echo ""
    echo "📊 Application Service Status:"
    docker-compose -f docker-compose.yml ps
fi

echo ""
echo "✅ Services started successfully!"
echo ""
echo "🌐 Access your services:"
echo "   Grafana:      http://localhost:3000   (admin/2014)"
echo "   Prometheus:   http://localhost:9090"
echo "   MLflow:       http://localhost:55000"
echo "   Airflow DEV:  http://localhost:8082   (admin/2014) - for dev/* branches"
echo "   Airflow TEST: http://localhost:8083   (admin/2014) - for staging branch"
echo "   Airflow PROD: http://localhost:8084   (admin/2014) - for main branch"
echo "   Postgres:     host=localhost port=55432 user=tradingAgent"
echo "   Redis:        localhost:6379"
echo "   RedisInsight: http://localhost:5540   (Redis web GUI)"
echo "   NATS:         localhost:4222 (client), localhost:8222 (monitoring)"
echo "   OpenProject:  http://localhost:8086   (Project Management - admin/admin)"
echo ""
echo "📝 To view logs: cd .ops/.docker && docker-compose logs -f"
echo "🛑 To stop:     cd .ops/.docker && ./stop-docker-monitoring.sh"
echo ""


