# TwinEU Big Data Management Module (Data Collection Services Bundle)

This stack provides an agnostic, hybrid data ingestion and curation system designed for TwinEU Data Space Providers. It securely ingests, curates (normalizes timestamps, strips nulls), and routes both real-time streams and batch data to your preferred storage infrastructure.

## Prerequisites
- Docker & Docker Compose
- (Optional) TwinEU Connector MinIO credentials

## Security & Authentication (TwinEU IAM)

To protect your edge storage from unauthorized batch uploads or destructive deletions, this module integrates directly with the TwinEU Central IAM / Marketplace authentication system.

When `REQUIRE_MIDDLEWARE_AUTH=true` is set in your environment, the edge API intercepts requests and validates the user's identity against the central IAM server (with a local edge cache to ensure high performance).

### The Security Split
To balance strict security with edge-computing realities, the module uses a split authentication model:

* **Secured Endpoints (Requires JWT):**
  * `POST /ingest/batch` (Remote file uploads)
  * `DELETE /maintenance/cleanup` (Storage management)
  * `DELETE /maintenance/cleanup-global` (Storage management)
* **Open Endpoints (No Auth Required):**
  * `POST /ingest` (Real-time telemetry). This endpoint is deliberately kept frictionless to support low-compute edge sensors. It should be firewalled within your secure local subnet.

### Obtaining & Using the Token
The required token is the exact same JSON Web Token (JWT) issued by the TwinEU Marketplace upon login.

1. **Get the Token:** Log in via the Marketplace UI or use the provided Postman Collection (**Folder 0. Authentication -> Marketplace Login**).
2. **Pass the Token:** Include it in your API calls using the standard HTTP Authorization header:
   `Authorization: Bearer eyJhbGciOiJIUzI1...`

## 1. Configuration

Copy the `.env.example` file to `.env` and configure your storage backend.

```bash
# ==============================================================================
# TwinEU Data Collection Services Bundle - Environment Configuration
# ==============================================================================

# --- 1. STORAGE ROUTING ---
STORAGE_BACKEND=local # Options: 'minio', 'local', 'azure'
RAW_DATA_CONTAINER=raw-data
BATCH_DATA_CONTAINER=batch-data

# --- 2. STORAGE BACKEND CONFIGURATIONS ---
MINIO_ENDPOINT=http://minio:9000
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin
MINIO_REGION=us-east-1
LOCAL_STORAGE_PATH=/data/staging
AZURE_STORAGE_CONNECTION_STRING=

# --- 3. INTERNAL SERVICES AUTHENTICATION ---
RABBITMQ_USER=user
RABBITMQ_PASS=secure_rabbitmq_password
NIFI_USER=admin
NIFI_PASS=admin1234567

# --- 4. PUBLISHER (AIMIC) CONFIGURATION ---
# Only required if deploying with 'make up-aimic'
MIDDLEWARE_URL=http://4.232.76.64/middleware-dev
MIDDLEWARE_USER=your_provider_username
MIDDLEWARE_PASS=your_provider_password
DSP_CONNECTOR_API_URL=https://your-dsp-connector.euprojects.net
MAX_FILE_SIZE_BYTES=524288000

# --- Edge API Security ---
# Enforces TwinEU IAM validation on all ingestion and maintenance endpoints
MIDDLEWARE_AUTH_CURRENT_URL=http://4.232.76.64/middleware-dev/api/user/current
REQUIRE_MIDDLEWARE_AUTH=false
TOKEN_CACHE_TTL=300

# --- 5. EDGE NETWORK CONFIGURATION ---
API_PORT=8000
AIMIC_PORT=8100
NIFI_INPUT_DIR=/data/input

```

You can configure your storage backend:

```bash
# --- Storage Selector ---
# Options: 'minio' (or 's3'), 'local', 'azure'
STORAGE_BACKEND: "minio"

# --- Option A: MinIO / AWS S3 ---
MINIO_ENDPOINT: "http://minio:9000"
MINIO_ACCESS_KEY: "minioadmin"
MINIO_SECRET_KEY: "minioadmin"
MINIO_REGION: "us-east-1"

# --- Option B: Local Filesystem (Docker Volume / Mount) ---
LOCAL_STORAGE_PATH: "/data/staging"

# --- Option C: Azure Blob Storage (Experimental) ---
AZURE_STORAGE_CONNECTION_STRING: "DefaultEndpointsProtocol=https;AccountName=...;"

# --- Target Containers / Buckets ---
RAW_DATA_CONTAINER: "raw-data"
BATCH_DATA_CONTAINER: "batch-data"

# --- Edge API Security ---
# Enforces TwinEU IAM validation on Batch Ingestion and Maintenance endpoints
REQUIRE_MIDDLEWARE_AUTH: "true"
MIDDLEWARE_AUTH_CURRENT_URL: "http://4.232.76.64/middleware-dev/api/user/current"
TOKEN_CACHE_TTL: "300" # Local edge cache expiration in seconds

```

> ⚠️ **Status Note on Storage Backends:**
> * **MinIO / AWS S3:** Fully integrated and verified baseline.
> * **Local Storage:** Integrated and verified.
> * **Azure Blob Storage:** (WIP) Code adapter included, but **experimental / not fully tested** in live setups yet.
>
>

### 💡 Using an External/Connector MinIO

The consumer service will automatically attempt to create the required buckets on startup. Ensure your provided `MINIO_ACCESS_KEY` has **"Create Bucket" permissions** on the external MinIO. If your credentials are strictly Read/Write, you must manually create these buckets in the Connector's MinIO console before starting this bundle.

### 2. Start the Stack

The TwinEU BDMM uses Docker Compose **Profiles** to keep the deployment modular. This allows you to spin up the core ingestion engine, and optionally attach a local MinIO instance or the AI Models Integration Component (AIMIC) depending on your needs.

If you are using the provided `Makefile`, you can use these helper commands:

```bash
# Core BDMM only (Requires an external storage backend like the TwinEU Connector)
make up

# Core BDMM + Local MinIO Storage
make up-minio

# Core BDMM + AIMIC Publisher
make up-aimic

# Complete Standalone Stack (BDMM + Local MinIO + AIMIC Publisher)
make up-minio-aimic

```

> **Note on AIMIC & Shared Storage:** When deploying AIMIC alongside the BDMM (`make up-aimic`), they automatically share the same network and storage volumes. You can publish curated datasets directly to the TwinEU Marketplace by passing a `storage_uri` (e.g., `minio://batch-data/...`) to AIMIC, bypassing the need to move large files over HTTP between these two components.
> ⚠️ **Publishing Size Limitation:** While this BDMM stack can ingest and curate terabytes of data, the bundled AIMIC publisher enforces a default file size limit of **500MB** when pushing to the TwinEU DSP Connector (due to Base64 JSON encoding requirements). You can increase this threshold using the `MAX_FILE_SIZE_BYTES` variable in your `.env`, but monitor your container's memory usage closely if doing so.

#### Using Standard Docker Compose (No Make)

If your environment does not support `make`, you must explicitly pass the profiles to Docker Compose using the `--profile` flag.

```bash
# Core BDMM only
docker compose -f docker-compose.prod.yaml up -d

# Attach MinIO
docker compose -f docker-compose.prod.yaml --profile include_minio up -d

# Attach AIMIC
docker compose -f docker-compose.prod.yaml --profile include_aimic up -d

# Attach Both
docker compose -f docker-compose.prod.yaml --profile include_minio --profile include_aimic up -d

```

## 3. Real-Time Ingestion

Send telemetry data to the API Gateway. The Curation Engine will automatically clean it and stage it in your storage backend.

> **Security Note:** To support lightweight edge sensors and high-frequency streams without imposing cryptographic compute overhead, the real-time `/ingest` endpoint intentionally bypasses the TwinEU IAM JWT validation. This endpoint should be placed on a secure, firewalled local network.

```bash
curl -X POST "http://localhost:8000/ingest" \
  -H "Content-Type: application/json" \
  -d '{"data": {"temperature": "21.5", "pressure": null}, "source": "sensor-01"}'

```

## 4. Batch Ingestion (Remote API)

You do not need SSH access to the host machine to ingest large batch files. Use the `/ingest/batch` helper endpoint to securely stream large CSVs or JSON datasets directly to the NiFi processing directory.

```bash
curl -X POST "http://localhost:8000/ingest/batch" \
  -H "Authorization: Bearer <your_jwt_token>" \
  -F "file=@massive_dataset.json"

```

*Note: The API utilizes a stream-and-rename pattern, meaning it handles gigabyte-scale files safely without exhausting edge container memory. NiFi will automatically pick up the file once the upload reaches 100%.*

---

## Service Access Ports

| Service | URL | Default Credentials |
| --- | --- | --- |
| API Gateway | [http://localhost:8000/docs](http://localhost:8000/docs) | — |
| RabbitMQ Management | [http://localhost:15672](http://localhost:15672) | `user` / `password` |
| MinIO Console | [http://localhost:9001](http://localhost:9001) | `minioadmin` / `minioadmin` |
| Apache NiFi Console | [https://localhost:9443/nifi](https://localhost:9443/nifi) | `admin` / `admin1234567` |
| Filebrowser (Local Storage UI) | [http://localhost:8081](http://localhost:8081) | No Auth (Development) |

---

## NiFi Batch Flow Setup & Curation

To ensure 100% parity with the real-time Python curation engine, the TwinEU batch pipelines intelligently route data, apply automated curation (stripping nulls, standardizing timestamps), dynamically generate storage folders based on sensor names, and inject `X-Amz-Meta` and MinIO tags.

You can either import the pre-configured flow template (Recommended) or build the pipeline manually.

---

### Option 1: Import Pre-configured Flow (Recommended)

1. Open the NiFi UI at `https://localhost:9443/nifi` (Default login: `admin` / `admin1234567`).
2. From the top component toolbar, drag a **Process Group** onto the empty canvas.
3. In the "Add Process Group" window, click the **Browse (Import)** icon (the small folder icon).
4. Select the appropriate flow definition file from the repository based on your `STORAGE_BACKEND`:
   * For MinIO/S3: Select `twineu-batch-minio.json`
   * For Local Filesystem: Select `twineu-batch-local.json`
5. Click **Add**.
6. **(MinIO / S3 Only - Credential Sync):** Because NiFi templates do not automatically read your `.env` file, you must manually align the flow with your custom configurations:
   * Double-click the process group to enter it.
   * Right-click the empty canvas -> **Configure** -> **Controller Services**.
   * Click the gear icon next to **AWS Credentials Provider** and enter your specific `Access Key` and `Secret Key`. Click Apply.
   * *If you are using an external MinIO (not the default `http://minio:9000`)*: Double-click the **PutS3Object** processor, go to the **Properties** tab, and update the **Endpoint Override URL** to match your `.env`.
   * Finally, go back to the Controller Services list and click the **Lightning Bolt** icon to enable the AWS Credentials Provider.
7. Right-click the Process Group and select **Start**.

---

### Option 2: Manual Pipeline Construction

If you prefer to build or modify the pipeline manually, follow these exact steps to ensure metadata and routing parity.

#### Step 1: The Source (GetFile)
1. Drag "Processor" onto the canvas → search **GetFile** → click **Add**.
2. Double-click **GetFile** → **Properties** tab: 
   * `Input Directory`: `/data/input` 
   * `Keep Source File`: `false` 
   * `Polling Interval`: `60 sec` 
   * `File Filter`: `.*`

#### Step 2: The Traffic Cop (RouteOnAttribute)
*Separates JSON files for curation from binary/flat files.*
1. Drag "Processor" → search **RouteOnAttribute** → click **Add**.
2. Connect **GetFile** to **RouteOnAttribute** (Select Relationship: `success`).
3. Double-click **RouteOnAttribute** → **Properties** tab → click the **"+"** icon (add new property):
   * **Property Name:** `is_json`
   * **Property Value:** `${filename:endsWith('.json')}`
4. Double-click **RouteOnAttribute** → **Settings** tab: Ensure `unmatched` is UNCHECKED under "Automatically Terminate Relationships".

#### Step 3: Extract Sensor Name (EvaluateJsonPath)
1. Drag "Processor" → search **EvaluateJsonPath** → click **Add**.
2. Connect **RouteOnAttribute** to **EvaluateJsonPath** (Select Relationship: `is_json`).
3. Double-click **EvaluateJsonPath** → **Properties** tab:
   * `Destination`: `flowfile-attribute`
   * Click the **"+"** icon (add new property):
     * **Property Name:** `extracted_source`
     * **Property Value:** `$.sensor` *(or `$.source`)*
4. Double-click **EvaluateJsonPath** → **Settings** tab: Check the box to auto-terminate `failure`.

#### Step 4: Inject JSON State & Tags (UpdateAttribute)
1. Drag "Processor" → search **UpdateAttribute** → click **Add**.
2. Connect **EvaluateJsonPath** to **UpdateAttribute** (Select Relationships: BOTH `matched` and `unmatched`).
3. Double-click **UpdateAttribute** → **Properties** tab → add the following dynamic properties:
   * `safe_source`: `${extracted_source:replaceNull('unknown'):toLower():replace(' ', '_')}`
   * `meta_timestamp`: `${now():format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')}`
   * `s3tag.curated`: `true`
   * `s3tag.processed_at`: `${now():format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')}`

#### Step 5: Clean Null Values (ConvertRecord)
1. Drag "Processor" → search **ConvertRecord** → click **Add**.
2. Connect the JSON **UpdateAttribute** to **ConvertRecord** (Select Relationship: `success`).
3. Double-click **ConvertRecord** → **Properties** tab:
   * `Record Reader`: Click the value field, click the **three dots** (...), and select **Create new service**. Choose **JsonTreeReader**.
   * `Record Writer`: Click the value field, click the **three dots** (...), and select **Create new service**. Choose **JsonRecordSetWriter**.
4. Configure the **JsonRecordSetWriter**:
   * Click the **three dots** (...) next to the Record Writer property and select **Go to Service**.
   * Click the **Gear icon** to configure it.
   * Set **Output Grouping** to: `One Line Per Object`
   * Set **Suppress Null Values** to: `Always Suppress`
   * Click Apply.
5. In the Controller Services list, click the **Lightning Bolt** icon to enable both the Reader and the Writer. Close the window.
6. Double-click **ConvertRecord** → **Settings** tab: Check the box to auto-terminate `failure`.

#### Step 6: Inject Metadata (JoltTransformJSON)
1. Drag "Processor" → search **JoltTransformJSON** → click **Add**.
2. Connect **ConvertRecord** to **JoltTransformJSON** (Select Relationship: `success`).
3. Double-click **JoltTransformJSON** → **Properties** tab: 
   * `Jolt Transform`: `Chain` 
   * `Jolt Specification`:
     ```json
     [
       {
         "operation": "default",
         "spec": {
           "_metadata": {
             "curated": true,
             "processed_at": "${meta_timestamp}"
           }
         }
       }
     ]
     ```
4. Double-click **JoltTransformJSON** → **Settings** tab: Check the box to auto-terminate `failure`.

#### Step 7: The CSV/ZIP Bypass Route (UpdateAttribute)
*Protects binary data from corruption while categorizing it safely.*
1. Drag "Processor" → search **UpdateAttribute** → click **Add**.
2. Connect **RouteOnAttribute** to this second **UpdateAttribute** (Select Relationship: `unmatched`).
3. Double-click **UpdateAttribute** → **Properties** tab → add the following dynamic properties:
   * `safe_source`: `unknown`
   * `meta_timestamp`: `${now():format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')}`
   *(Note: Do NOT add `s3tag.` properties here so raw files remain untagged).*

#### Step 8: The Destination (PutS3Object or PutFile)
1. Drag "Processor" → search **PutS3Object** (for MinIO) or **PutFile** (for Local) → click **Add**.
2. Connect **JoltTransformJSON** to the Destination (Select Relationship: `success`).
3. Connect the **Bypass UpdateAttribute** to the Destination (Select Relationship: `success`).

**For MinIO / S3 (`PutS3Object`):**
* Double-click **PutS3Object** → **Properties** tab:
  * `Bucket`: `batch-data`
  * `Object Key`: `${safe_source}/${now():format('yyyy/MM/dd')}/${now():toNumber()}_${filename}`
  * `Endpoint Override URL`: `http://minio:9000`
  * `Object Tags Prefix`: `s3tag.`
  * `Remove Tag Prefix`: `true`
  * *Dynamic Properties (User Metadata):* Add `Server_received_at` = `${now():toNumber()}`, `Source` = `${safe_source}`, `Timestamp` = `${meta_timestamp}`
* Configure the AWS Credentials Provider controller service.
* Double-click **PutS3Object** → **Settings** tab: Check the boxes to auto-terminate BOTH `success` and `failure`.

**For Local Storage (`PutFile`):**
* Double-click **PutFile** → **Properties** tab:
  * `Directory`: `/data/staging/batch-data/${safe_source}/${now():format('yyyy/MM/dd')}`
  * `Conflict Resolution Strategy`: `replace`
* Double-click **PutFile** → **Settings** tab: Check the boxes to auto-terminate BOTH `success` and `failure`.

#### Step 9: Start the Engine
1. Highlight all processors on the canvas by dragging a box over them.
2. Right-click any highlighted processor and select **Start**.

---

To process batch files, either upload them remotely via the `POST /ingest/batch` API endpoint, or drop them directly into your host machine's `./nifi_input` folder. JSON files will be curated; all other files will bypass curation and be saved directly to storage.

## Data Retention & Maintenance

To prevent storage exhaustion, the API provides dual cleanup endpoints that purge old telemetry data across both the `raw-data` and `batch-data` containers. 

*Note: If `REQUIRE_MIDDLEWARE_AUTH` is enabled, both of these endpoints strictly require a valid TwinEU IAM Bearer token.*

**1. Clean up a specific source**
Requires the `source` query parameter to target a specific sensor or dataset folder.
```bash
curl -X DELETE "http://localhost:8000/maintenance/cleanup?source=sensor-01&days_old=30" \
  -H "Authorization: Bearer <your_jwt_token>"

```

**2. Global Clean up**
Safely sweeps the entire storage backend and deletes all files older than the threshold, regardless of their source prefix.

```bash
curl -X DELETE "http://localhost:8000/maintenance/cleanup-global?days_old=30" \
  -H "Authorization: Bearer <your_jwt_token>"

```

### ⚠️ Edge Deployment: Docker Volume Permissions
This stack relies on shared local storage volumes (`./nifi_input` and `./local_staging`) mounted from your host machine into the containers. 
* **Symptom:** The API or NiFi containers crash on startup, or throw `EACCES: permission denied` errors when trying to read/write files.
* **Fix:** Docker occasionally mounts bind volumes as `root`. If you are running Docker in rootless mode or with restricted user namespaces, ensure your host directories are writable by the container. Before bringing the stack up, execute:
```bash
mkdir -p nifi_input local_staging
chmod -R 777 nifi_input local_staging
```
## Going Live (Production Deployment Checklist)

Out of the box, this stack binds to local ports over standard HTTP. To safely expose the APIs to the internet or the TwinEU Data Space, you must wrap the deployment in standard web infrastructure:

* **Reverse Proxy & SSL/TLS:** Place a reverse proxy (such as NGINX, Traefik, or Apache) in front of the services. **HTTPS is mandatory** for production, as the APIs transmit sensitive TwinEU IAM JWT Bearer tokens in their headers.
* **Firewall Restrictions:** Only expose the public-facing API ports to the internet (e.g., `8000` for BDMM Ingestion, `8100` for AIMIC Registration).
* **Protect Management Interfaces:** Strict firewall rules should block public access to internal dashboards. RabbitMQ (15672), MinIO Console (9001), Filebrowser (8081), and NiFi (9443) should only be accessible via a secure local network, SSH tunnel, or corporate VPN.
* **DNS Configuration:** Map your edge node's public IP to a domain (e.g., `api.your-node.eu`) and update any webhook or callback URLs in your `.env` to reflect the public domain instead of `localhost`.
