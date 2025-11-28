#!/bin/bash
# Validate prerequisites for HL7-EH-FAB deployment
# Run this before deploying infrastructure or application

set -e

echo "=== HL7-EH-FAB Prerequisites Check ==="
echo ""

ERRORS=0

# Check Azure CLI
echo -n "Azure CLI: "
if command -v az &> /dev/null; then
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    echo "✓ Installed (v$AZ_VERSION)"
else
    echo "✗ Not installed"
    echo "  Install: https://aka.ms/installazurecli"
    ERRORS=$((ERRORS + 1))
fi

# Check Azure login
echo -n "Azure Login: "
if az account show &> /dev/null; then
    ACCOUNT=$(az account show --query user.name -o tsv)
    SUBSCRIPTION=$(az account show --query name -o tsv)
    echo "✓ Logged in as $ACCOUNT"
    echo "  Subscription: $SUBSCRIPTION"
else
    echo "✗ Not logged in"
    echo "  Run: az login"
    ERRORS=$((ERRORS + 1))
fi

# Check Bicep
echo -n "Bicep: "
if az bicep version &> /dev/null; then
    BICEP_VERSION=$(az bicep version 2>&1 | head -1)
    echo "✓ $BICEP_VERSION"
else
    echo "✗ Not installed"
    echo "  Install: az bicep install"
    ERRORS=$((ERRORS + 1))
fi

# Check kubectl
echo -n "kubectl: "
if command -v kubectl &> /dev/null; then
    KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null || kubectl version --client -o json | jq -r '.clientVersion.gitVersion')
    echo "✓ Installed ($KUBECTL_VERSION)"
else
    echo "✗ Not installed"
    echo "  Install: az aks install-cli"
    ERRORS=$((ERRORS + 1))
fi

# Check Python (for test scripts)
echo -n "Python: "
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    echo "✓ $PYTHON_VERSION"
else
    echo "⚠ Not installed (optional, for test scripts)"
fi

# Check required Azure providers
echo ""
echo "Checking Azure resource providers..."

check_provider() {
    local PROVIDER=$1
    echo -n "  $PROVIDER: "
    STATE=$(az provider show --namespace $PROVIDER --query registrationState -o tsv 2>/dev/null || echo "Unknown")
    if [ "$STATE" == "Registered" ]; then
        echo "✓ Registered"
    else
        echo "✗ $STATE"
        echo "    Register: az provider register --namespace $PROVIDER --wait"
        ERRORS=$((ERRORS + 1))
    fi
}

check_provider "Microsoft.ContainerRegistry"
check_provider "Microsoft.ContainerService"
check_provider "Microsoft.EventHub"
check_provider "Microsoft.Fabric"
check_provider "Microsoft.Network"

# Check SSH key
echo ""
echo -n "SSH Key (~/.ssh/id_rsa.pub): "
if [ -f ~/.ssh/id_rsa.pub ]; then
    echo "✓ Found"
else
    echo "✗ Not found"
    echo "  Generate: ssh-keygen -t rsa -b 4096"
    ERRORS=$((ERRORS + 1))
fi

# Summary
echo ""
echo "================================"
if [ $ERRORS -eq 0 ]; then
    echo "✓ All prerequisites met!" 
    echo ""
    echo "Next steps:"
    echo "  1. Deploy infrastructure: az deployment sub create --template-file infra/main.bicep --location centralus --parameters infra/main.parameters.json"
    echo "  2. Deploy application: ./deploy.sh"
    exit 0
else
    echo "✗ $ERRORS prerequisite(s) missing"
    echo "  Please fix the issues above and run this script again."
    exit 1
fi
