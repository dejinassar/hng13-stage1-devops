# HNGi13 DevOps Stage 1 - Automated Deployment Bash Script

## Project Overview
This project automates the setup, deployment, and configuration of a Dockerized Flask application on a remote Linux server using a single Bash script. It includes Nginx as a reverse proxy and handles all dependencies automatically.

**Key Features:**
- Clone or update Git repository
- Build and run Docker containers
- Configure Nginx reverse proxy dynamically
- Automatic installation of Docker, Docker Compose, and Nginx
- Logging, error handling, and idempotent deployment
- Simple and reproducible deployment for production-grade environments

---

##  Prerequisites
- Remote Linux server (Ubuntu recommended)
- SSH access with private key
- Git installed locally
- Optional: Personal Access Token (PAT) if the repository is private
- Bash shell (POSIX-compliant)

---

##  Usage

1. Make the script executable:
```bash
chmod +x deploy.sh
./deploy.sh
