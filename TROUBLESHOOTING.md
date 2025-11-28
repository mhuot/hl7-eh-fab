# Troubleshooting Guide

## Common Issues

### Infrastructure Deployment

#### "Fabric capacity quota exceeded"
```
Error: The subscription does not have enough quota for the requested Fabric capacity
```

**Solution**: Request Fabric quota increase or disable Fabric deployment:
```bash
az deployment sub create \
  --template-file infra/main.bicep \
  --location centralus \
  --parameters infra/main.parameters.json \
               deployFabricCapacity=false
```

#### "SSH key not found"
```
Error: Parameter 'sshPublicKey' is required
```

**Solution**: Generate an SSH key:
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
```

Then update `infra/main.parameters.json` with your public key or pass it inline.

---

### Application Deployment

#### "kubectl: cannot execute binary file"
```
Error: /usr/local/bin/kubectl: cannot execute binary file: Exec format error
```

**Cause**: Wrong architecture kubectl binary (x86 vs ARM).

**Solution**:
```bash
# Check your architecture
uname -m

# Remove old kubectl and reinstall
sudo rm /usr/local/bin/kubectl
# For ARM64:
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"
# For AMD64:
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

#### "Pods stuck in ImagePullBackOff"
```
Events:
  Warning  Failed   pull image "hl7listener:v1": failed to resolve reference
```

**Solution**: Check ACR image and AKS pull access:
```bash
# Verify image exists
az acr repository show-tags --name <acr-name> --repository hl7listener

# Verify AKS can pull from ACR
az aks check-acr --name hl7-aks --resource-group hl7-demo-rg --acr <acr-name>.azurecr.io
```

#### "Pods stuck in CrashLoopBackOff"
```
Events:
  Warning  BackOff  Back-off restarting failed container
```

**Solution**: Check pod logs:
```bash
kubectl logs -n hl7 -l app=hl7-listener --previous
kubectl describe pod -n hl7 -l app=hl7-listener
```

Common causes:
- Missing Event Hubs secret
- Invalid connection string
- Port already in use

---

### Connectivity Issues

#### "Connection refused" when sending HL7 messages
```
ConnectionRefusedError: [Errno 111] Connection refused
```

**Solution**:
1. Verify service has external IP:
   ```bash
   kubectl get service hl7-listener -n hl7
   ```

2. Check pods are running:
   ```bash
   kubectl get pods -n hl7
   ```

3. Verify port is correct (2575):
   ```bash
   python src/hl7-listener/send_test_hl7.py <EXTERNAL-IP> 2575
   ```

#### "Kafka broker not available" in pod logs
```
Error: KafkaError: Broker not available
```

**Cause**: Event Hubs connectivity issue (likely private endpoint not resolving).

**Solution**:
1. Verify private endpoint is approved:
   ```bash
   az network private-endpoint show \
     --name hl7-eventhub-pe \
     --resource-group hl7-demo-rg \
     --query 'privateLinkServiceConnections[0].privateLinkServiceConnectionState.status'
   ```

2. Check DNS resolution from pod:
   ```bash
   kubectl exec -n hl7 -it <pod-name> -- nslookup <eventhub-namespace>.servicebus.windows.net
   ```

---

### Microsoft Fabric Issues

#### "Managed private endpoints tab not visible"
**Cause**: Fabric capacity SKU is too low (requires F64+).

**Solution**: Upgrade to F64 SKU in `infra/fabricCapacity.bicep` or use public access (set `publicNetworkAccess: 'Enabled'` in resources.bicep).

#### "Eventstream cannot connect to Event Hubs"
**Solution**:
1. Verify managed private endpoint is approved
2. Check Event Hubs connection string is correct
3. Ensure consumer group exists (`$Default`)

---

## Useful Commands

```bash
# View all resources
kubectl get all -n hl7

# Follow logs
kubectl logs -n hl7 -l app=hl7-listener -f

# Restart deployment
kubectl rollout restart deployment/hl7-listener -n hl7

# Scale up/down
kubectl scale deployment/hl7-listener -n hl7 --replicas=3

# Get events
kubectl get events -n hl7 --sort-by='.lastTimestamp'

# Exec into pod
kubectl exec -n hl7 -it <pod-name> -- /bin/sh

# Check AKS cluster health
az aks show --resource-group hl7-demo-rg --name hl7-aks --query 'powerState'
```

## Getting Help

1. Check pod events: `kubectl describe pod -n hl7 <pod-name>`
2. Check deployment events: `kubectl describe deployment -n hl7 hl7-listener`
3. View AKS diagnostics: Azure Portal → AKS → Diagnose and solve problems
4. View Event Hubs metrics: Azure Portal → Event Hubs → Metrics
