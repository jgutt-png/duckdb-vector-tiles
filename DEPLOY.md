# Deployment Guide

## Setup: GitHub Actions → Docker Hub → Cloud Run

### 1. Set up Docker Hub

1. Create account at https://hub.docker.com
2. Create repository: `duckdb-tiles`
3. Generate access token: Account Settings → Security → New Access Token

### 2. Configure GitHub Secrets

Go to your GitHub repo → Settings → Secrets and variables → Actions

Add these secrets:
- `DOCKER_USERNAME`: Your Docker Hub username
- `DOCKER_PASSWORD`: Your Docker Hub access token

### 3. Push to GitHub

```bash
# Already initialized, just commit and push
git add .
git commit -m "Add DuckDB vector tiles demo with cloud build"
gh repo create duckdb-tiles --public --source=. --push

# Or manually:
git remote add origin https://github.com/YOUR_USERNAME/duckdb-tiles.git
git branch -M main
git push -u origin main
```

GitHub Actions will automatically build the image (takes ~60 mins).

### 4. Deploy to Google Cloud Run

```bash
# Install gcloud CLI
brew install google-cloud-sdk

# Login
gcloud auth login
gcloud config set project YOUR_PROJECT_ID

# Deploy from Docker Hub
gcloud run deploy duckdb-tiles \
  --image docker.io/YOUR_USERNAME/duckdb-tiles:latest \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 4Gi \
  --cpu 4 \
  --port 8000 \
  --timeout 3600

# You'll get a URL like: https://duckdb-tiles-xxx-uc.a.run.app
```

### 5. Alternative: Railway (Simplest)

```bash
# Install Railway CLI
npm install -g @railway/cli

# Login
railway login

# Deploy
railway init
railway up

# Link custom domain (optional)
railway domain
```

## Cost Estimates

### GitHub Actions
- **Free tier**: 2000 minutes/month
- **Build time**: ~60 minutes
- **Monthly cost**: FREE (33 builds/month within free tier)

### Docker Hub
- **Free tier**: Unlimited public repos
- **Monthly cost**: FREE

### Google Cloud Run
- **Pay per use** (only when running)
- **Idle**: $0 (scales to zero)
- **Running 24/7**: ~$15-30/month
- **Recommended**: Keep offline, deploy on-demand

### Railway
- **Free tier**: $5 credit/month
- **Typical usage**: $3-5/month
- **Includes**: Automatic SSL, custom domains

## Triggering Manual Build

```bash
# Via GitHub CLI
gh workflow run build.yml

# Via GitHub UI
# Go to Actions tab → Build Docker Image → Run workflow
```

## Monitoring Build

```bash
# Watch GitHub Actions
gh run watch

# Check Docker Hub
open https://hub.docker.com/r/YOUR_USERNAME/duckdb-tiles/builds
```
