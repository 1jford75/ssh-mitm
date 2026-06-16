# Deployment Guide for ssh-mitm with Security Fixes

## Overview

This guide provides step-by-step instructions for securely deploying ssh-mitm using the hardened `Dockerfile.secure` with all security fixes applied.

---

## Pre-Deployment Checklist

- [ ] Review `SECURITY_ADVISORY.md` for all CVEs
- [ ] Read `SECURITY_README.md` for best practices
- [ ] Understand OpenSSH 7.5p1 limitations
- [ ] Plan for network isolation
- [ ] Prepare host key persistence strategy
- [ ] Set up monitoring/logging

---

## Phase 1: Development Environment (Days 1-2)

### Step 1.1: Build the Hardened Image
```bash
# Clone/update repository
git clone https://github.com/1jford75/ssh-mitm.git
cd ssh-mitm

# Build using Dockerfile.secure
docker build -f Dockerfile.secure -t ssh-mitm:dev .

# Verify build success
docker images | grep ssh-mitm
```

### Step 1.2: Run Security Scans
```bash
# Install Trivy if not present
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Run vulnerability scan
trivy image ssh-mitm:dev

# Generate SBOM
trivy image --format cyclonedx ssh-mitm:dev > sbom.json

# Review results
cat sbom.json | jq '.components[] | select(.vulnerabilities != null)'
```

### Step 1.3: Test Basic Functionality
```bash
# Run container
docker run -p 127.0.0.1:2222:2222 \
  --name ssh-mitm-test \
  ssh-mitm:dev &

# Wait for startup
sleep 5

# Verify port is listening
ss -tulpn | grep 2222

# Test SSH connection (will show MITM in progress)
ssh -p 2222 -o StrictHostKeyChecking=no root@127.0.0.1

# Stop container
docker stop ssh-mitm-test
docker rm ssh-mitm-test
```

---

## Phase 2: Testing Environment (Days 3-5)

### Step 2.1: Deploy to Staging
```bash
# Tag for staging
docker tag ssh-mitm:dev ssh-mitm:staging

# If using registry, push
docker push your-registry/ssh-mitm:staging
```

### Step 2.2: Network Configuration
```bash
# Option A: Localhost-only (most secure for testing)
docker run -p 127.0.0.1:2222:2222 \
  --name ssh-mitm-staging \
  ssh-mitm:staging

# Option B: Specific subnet (lab testing)
docker network create mitm-lab
docker run --network mitm-lab \
  -p 192.168.100.50:2222:2222 \
  --name ssh-mitm-staging \
  ssh-mitm:staging

# Option C: Full network (not recommended)
# docker run -p 0.0.0.0:2222:2222 ssh-mitm:staging
```

### Step 2.3: Persistent Host Keys
```bash
# Create persistent key directory
mkdir -p hostkeys
chmod 700 hostkeys

# Run container with mounted volume
docker run -v $(pwd)/hostkeys:/home/ssh-mitm/hostkeys \
  -p 127.0.0.1:2222:2222 \
  ssh-mitm:staging

# Verify keys are persistent
ls -la hostkeys/
```

### Step 2.4: Logging Setup
```bash
# Option A: File-based logging
docker run -v $(pwd)/logs:/var/log/ssh-mitm \
  -p 127.0.0.1:2222:2222 \
  ssh-mitm:staging

# Option B: Docker logs
docker logs ssh-mitm-staging > audit.log

# Option C: Structured logging (if supported)
docker run --log-driver=json-file \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  -p 127.0.0.1:2222:2222 \
  ssh-mitm:staging
```

### Step 2.5: Performance Testing
```bash
# Monitor resource usage
docker stats ssh-mitm-staging

# Run under load
for i in {1..10}; do
  ssh -p 2222 -o StrictHostKeyChecking=no root@127.0.0.1 "uptime" &
done
wait

# Check memory/CPU limits needed
docker inspect ssh-mitm-staging | grep -A 5 "Memory"
```

---

## Phase 3: Production Deployment (Days 6-7)

### Step 3.1: Production Build
```bash
# Build with production tag
docker build -f Dockerfile.secure \
  -t ssh-mitm:1.0.0 \
  -t ssh-mitm:latest \
  -t your-registry/ssh-mitm:1.0.0 \
  .

# Push to registry
docker push your-registry/ssh-mitm:1.0.0
docker push your-registry/ssh-mitm:latest
```

### Step 3.2: Kubernetes Deployment (if applicable)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ssh-mitm
  namespace: security-tools
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ssh-mitm
  template:
    metadata:
      labels:
        app: ssh-mitm
    spec:
      containers:
      - name: ssh-mitm
        image: your-registry/ssh-mitm:1.0.0
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 2222
          protocol: TCP
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        securityContext:
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1000
        volumeMounts:
        - name: hostkeys
          mountPath: /home/ssh-mitm/hostkeys
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: hostkeys
        persistentVolumeClaim:
          claimName: ssh-mitm-keys
      - name: tmp
        emptyDir: {}
```

### Step 3.3: Docker Compose Setup
```yaml
version: '3.8'

services:
  ssh-mitm:
    image: ssh-mitm:1.0.0
    container_name: ssh-mitm-prod
    ports:
      - "127.0.0.1:2222:2222"
    volumes:
      - ./hostkeys:/home/ssh-mitm/hostkeys
      - ./logs:/var/log/ssh-mitm
    environment:
      - MITM_MODE=production
    restart: unless-stopped
    networks:
      - mitm-network
    healthcheck:
      test: ["CMD", "ss", "-tulpn"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 5s

networks:
  mitm-network:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.200.0/24
```

### Step 3.4: Security Hardening for Production
```bash
# Run in read-only filesystem mode
docker run --read-only \
  --tmpfs /tmp \
  --tmpfs /home/ssh-mitm/tmp \
  -v $(pwd)/hostkeys:/home/ssh-mitm/hostkeys \
  -p 127.0.0.1:2222:2222 \
  ssh-mitm:1.0.0

# Add resource limits
docker run --memory=512m \
  --cpus=1 \
  --pids-limit=100 \
  -p 127.0.0.1:2222:2222 \
  ssh-mitm:1.0.0

# Enable security options
docker run --cap-drop=ALL \
  --cap-add=NET_BIND_SERVICE \
  --security-opt no-new-privileges:true \
  -p 127.0.0.1:2222:2222 \
  ssh-mitm:1.0.0
```

### Step 3.5: Monitoring Setup
```bash
# Monitor container metrics
docker stats --no-stream ssh-mitm-prod

# Set up log aggregation (example with ELK)
docker run --log-driver=awslogs \
  --log-opt awslogs-group=/ecs/ssh-mitm \
  --log-opt awslogs-region=us-east-1 \
  ssh-mitm:1.0.0
```

---

## Post-Deployment Validation

### Checklist
- [ ] Container starts successfully
- [ ] Port 2222 listening on correct interface
- [ ] Host keys persisting across restarts
- [ ] Logs being captured
- [ ] Security scan shows expected results
- [ ] Monitoring/alerting working
- [ ] Network isolation verified
- [ ] Performance within acceptable limits
- [ ] Documentation updated
- [ ] Team trained on operation

### Validation Commands
```bash
# Check container health
docker ps | grep ssh-mitm

# Verify network binding
netstat -tulpn | grep 2222

# Check logs
docker logs ssh-mitm-prod

# Test MITM functionality
ssh -v -p 2222 root@127.0.0.1

# Verify non-root user
docker exec ssh-mitm-prod whoami  # Should return: ssh-mitm

# Check filesystem
docker exec ssh-mitm-prod ls -la /home/ssh-mitm/
```

---

## Ongoing Maintenance

### Weekly
- [ ] Review security scan results
- [ ] Check for new CVEs in advisories
- [ ] Monitor performance metrics
- [ ] Backup host keys

### Monthly
- [ ] Run full security audit
- [ ] Check for base image patches
- [ ] Review logs for anomalies
- [ ] Update documentation

### Quarterly
- [ ] Review `.trivyignore` file
- [ ] Assess OpenSSH upgrade path
- [ ] Conduct penetration testing
- [ ] Update security advisory

---

## Troubleshooting

### Port Already in Use
```bash
# Find what's using port 2222
lsof -i :2222

# Kill if needed
kill -9 <pid>

# Or use different port
docker run -p 127.0.0.1:2223:2222 ssh-mitm:1.0.0
```

### Host Keys Not Persisting
```bash
# Check volume mount
docker inspect ssh-mitm-prod | grep -A 10 Mounts

# Verify permissions
ls -la hostkeys/

# Fix if needed
chmod 700 hostkeys/
```

### High CPU/Memory Usage
```bash
# Check process
docker top ssh-mitm-prod

# Reduce limits
docker run --cpus=0.5 --memory=256m ssh-mitm:1.0.0
```

---

## Rollback Plan

If issues occur:

```bash
# Keep previous version available
docker pull ssh-mitm:previous-version

# Quick rollback
docker stop ssh-mitm-prod
docker rename ssh-mitm-prod ssh-mitm-bad
docker run -d --name ssh-mitm-prod \
  -p 127.0.0.1:2222:2222 \
  ssh-mitm:previous-version

# Investigate issues
docker logs ssh-mitm-bad > incident-report.log
```

---

## Security Incident Response

### If Compromise Suspected
1. Stop container immediately
2. Preserve logs and host keys for forensics
3. Review `.trivyignore` and security scan results
4. Rebuild from `Dockerfile.secure`
5. Conduct security audit
6. Re-deploy with fresh host keys

---

## References

- SECURITY_FIXES.md - Technical vulnerability details
- SECURITY_README.md - Best practices and guidelines
- SECURITY_ADVISORY.md - Full security advisory
- Dockerfile.secure - Hardened container definition

---

**Last Updated:** June 16, 2026  
**Status:** Ready for Production Deployment  
**Next Review:** Monthly
