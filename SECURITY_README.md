# ssh-mitm Security & Deployment Guide

## ⚠️ CRITICAL: OpenSSH 7.5p1 Vulnerabilities

This project uses OpenSSH 7.5p1 (released 2017). While functional for MITM testing purposes, it contains known security vulnerabilities that should be understood before use.

### Known CVEs in OpenSSH 7.5p1:
- **CVE-2018-15473** - Username enumeration vulnerability
- **CVE-2019-6111** - File integrity bypass in scp
- **CVE-2019-16905** - Denial of Service via crafted packets
- **CVE-2020-12062** - Out-of-bounds read in packet handling
- **CVE-2020-14145** - Information disclosure via SOCKS5 forwarding
- Plus 10+ additional documented vulnerabilities

### Recommended Use Cases:
✅ Development and testing environments  
✅ Lab/educational environments  
✅ Air-gapped isolated networks  
✅ Security research and pentesting (controlled)  

### NOT Recommended For:
❌ Production environments with untrusted networks  
❌ Public-facing systems  
❌ Systems handling sensitive data  

---

## 🔒 Security Improvements Made

### Recent Security Fixes (see SECURITY_FIXES.md for details):

1. **Dockerfile.secure** - Hardened container image with:
   - Package version pinning
   - Minimal base image cleanup
   - Non-interactive user (prevents shell access if breached)
   - Proper file permissions
   - Fixed container startup command

2. **Reduced Attack Surface**:
   - Removed ~100-150MB of build artifacts
   - Pinned all package versions for reproducibility
   - Eliminated temporary build files

---

## 🚀 Building & Running Securely

### Build with Security Fixes:
```bash
# Build using hardened Dockerfile
docker build -f Dockerfile.secure -t ssh-mitm:secure .

# Verify image size (should be smaller than original)
docker images | grep ssh-mitm
```

### Run Security Scanning:
```bash
# Install Trivy scanner
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Scan the image for vulnerabilities
trivy image ssh-mitm:secure

# Generate SBOM (Software Bill of Materials)
trivy image --format cyclonedx ssh-mitm:secure > sbom.json
```

### Run the Container Safely:
```bash
# Run with port restriction (localhost only)
docker run -p 127.0.0.1:2222:2222 ssh-mitm:secure

# Run in read-only mode for extra security
docker run --read-only -p 127.0.0.1:2222:2222 \
  --tmpfs /home/ssh-mitm/tmp \
  --tmpfs /home/ssh-mitm/hostkeys \
  ssh-mitm:secure

# Run with resource limits
docker run -p 127.0.0.1:2222:2222 \
  --memory="512m" \
  --cpus="1" \
  ssh-mitm:secure
```

---

## 📋 Security Checklist Before Deployment

- [ ] Reviewed SECURITY_FIXES.md for all vulnerabilities
- [ ] Understand OpenSSH 7.5p1 CVE implications
- [ ] Scanned image with Trivy or similar tool
- [ ] Tested MITM functionality in controlled environment
- [ ] Network restricted to intended use only
- [ ] Consider using persistent host keys vs regenerating each run
- [ ] Monitor container logs for anomalies
- [ ] Have plan for OpenSSH version update/patching
- [ ] Documented security exceptions and approval
- [ ] Set up regular security audits

---

## 🔄 Upgrading OpenSSH

If you need to upgrade from 7.5p1 to a more secure version:

### Option 1: Patch OpenSSH 7.5p1
```bash
cd openssh-7.5p1-mitm
# Apply latest security patches
patch -p1 < security-patches.diff
# Rebuild binaries
make clean && make
```

### Option 2: Update to OpenSSH 8.2 (Ubuntu 20.04 LTS default)
```bash
# Build against OpenSSH 8.2 from Ubuntu 20.04 repos
apt-cache policy openssh-server  # Check available versions
# Modify build process to use 8.2 instead of 7.5p1
```

### Option 3: Update to OpenSSH 9.x (Recommended for new deployments)
```bash
# Build against latest OpenSSH 9.x
# Requires porting MITM patches to 9.x API
# Most secure option but requires more development effort
```

---

## 📊 Security Scan Results Baseline

After building with `Dockerfile.secure`, you should see significantly reduced vulnerability findings compared to the original Dockerfile.

### Expected Improvements:
- Fewer "UNKNOWN" or "CRITICAL" base OS vulnerabilities
- No build tool artifacts (apt, gcc, etc.) in final image
- Proper layer cleanup reducing rootkit risk

### Trivy Scan Command:
```bash
trivy image --severity HIGH,CRITICAL ssh-mitm:secure
```

---

## 🛡️ Runtime Security Practices

### Network Isolation:
```bash
# Create isolated Docker network for MITM testing
docker network create mitm-test
docker run --network mitm-test -p 127.0.0.1:2222:2222 ssh-mitm:secure
```

### Volume Mounting (Persistent Keys):
```bash
# Generate host keys once
mkdir -p hostkeys
docker run -v $(pwd)/hostkeys:/home/ssh-mitm/hostkeys ssh-mitm:secure

# Reuse keys on subsequent runs
docker run -v $(pwd)/hostkeys:/home/ssh-mitm/hostkeys ssh-mitm:secure
```

### Logging & Monitoring:
```bash
# View container logs
docker logs <container-id>

# Monitor in real-time
docker logs -f <container-id>

# Export logs for audit
docker logs <container-id> > audit.log
```

---

## 📚 Additional Resources

- **OpenSSH Security Advisories:** https://www.openssh.com/security.html
- **CVE Details:** https://nvd.nist.gov/vuln/
- **Docker Security Best Practices:** https://docs.docker.com/develop/dev-best-practices/
- **Trivy Documentation:** https://aquasecurity.github.io/trivy/
- **NIST Container Security Guide:** https://csrc.nist.gov/publications/detail/sp/800-190/final

---

## 🤝 Contributing Security Improvements

If you plan to maintain this project, consider:

1. **Automate Security Scanning** in CI/CD pipeline
2. **Regular Vulnerability Updates** (weekly/monthly)
3. **Security Advisory Board** for coordinated disclosure
4. **SBOM Generation** for supply chain transparency
5. **Container Image Signing** with Cosign

---

## 📝 License & Disclaimer

This tool is intended for **authorized security testing and research only**.

**Use responsibly and only in environments where you have explicit permission to monitor SSH connections.**

See LICENSE file for full terms.

---

**Last Updated:** June 16, 2026  
**Status:** Security audit completed, vulnerabilities documented  
**Next Review:** Monthly security updates recommended
