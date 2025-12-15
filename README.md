![OpenTelemetry Collector Architecture Diagram](https://cdn.sanity.io/images/rdn92ihu/production/b1c172e7f1a8895bf3b9a2a6d4ab10f9f93161b5-2902x1398.png?w=1200)

---

## 🧠 Core Component of OpenTelemetry Collector

The OpenTelemetry Collector works by chaining these three component types in a **pipeline** to move, transform, and route data.

---

### 1. Receivers (The Entry Point) 📥

**Receivers** are the components that receive telemetry data (traces, metrics, or logs) from your instrumented applications and other sources. They are the input mechanism of the Collector.

- **Function:** Listen on specific network ports and protocols.
- **Key Type Used in Setup:** **OTLP** (OpenTelemetry Protocol). This is the standard, vendor-neutral format used by the applications in your setup to send data via gRPC (port 4317) or HTTP (port 4318).
- **Other Types Used:** The setup also included a **Jaeger receiver** to handle data from legacy Jaeger clients, and a **Prometheus receiver** to scrape metrics from the Collector itself and potentially other targets.

### 2. Processors (The Transformer) ⚙️

**Processors** are intermediate components that modify, filter, or enrich the data as it flows through the pipeline. They are essential for efficiency, resource management, and security in a production environment.

- **Function:** Manipulate data before it is exported.
- **Key Types Used in Setup:**
  - **`batch`**: Collects items (spans, metrics, or logs) into batches and sends them periodically or when the batch size limit is met. This is **critical for performance** and reducing network overhead.
  - **`memory_limiter`**: Stops the Collector from running out of memory (OOMKilled) during traffic spikes by dropping incoming data if necessary. This protects the stability of the Collector.
  - **`resource`**: Adds or updates common resource attributes (like `deployment.environment` or `cluster.name`) to all incoming telemetry data, ensuring consistent metadata.
  - **`attributes`**: Used to filter or redact sensitive information, such as deleting the `http.request.header.authorization` key from traces/logs before they leave the Collector.

### 3. Exporters (The Exit Point) 📤

**Exporters** are responsible for sending the processed telemetry data to the final storage backends or analysis tools.

- **Function:** Send data out of the Collector to a specified destination.
- **Key Types Used in Setup:**
  - **`otlp/jaeger`**: An OTLP exporter configured to send traces specifically to the Jaeger collector service.
  - **`otlphttp/logstash`**: An OTLP HTTP exporter configured to send structured logs to the Logstash HTTP input endpoint for further processing before Elasticsearch.
  - **`prometheus`**: Configures an HTTP endpoint (`0.0.0.0:9090`) which exposes the received metrics in the format Prometheus can scrape.
  - **`debug`**: Logs data to the Collector's console. Crucial for debugging but kept with reduced verbosity in production.

---

## 🔗 The Service Pipeline

The **`service`** section ties these components together, defining the flow for each type of telemetry data: **traces**, **metrics**, and **logs**.

A typical pipeline looks like this:

> **Pipeline:** $\text{Receivers} \rightarrow \text{Processors} \rightarrow \text{Exporters}$

| Pipeline    | Receivers (Input)    | Processors (Transform)                              | Exporters (Output)           |
| :---------- | :------------------- | :-------------------------------------------------- | :--------------------------- |
| **Traces**  | `otlp`, `jaeger`     | `memory_limiter`, `resource`, `attributes`, `batch` | `otlp/jaeger`, `debug`       |
| **Metrics** | `otlp`, `prometheus` | `memory_limiter`, `resource`, `batch`               | `prometheus`, `debug`        |
| **Logs**    | `otlp`               | `memory_limiter`, `resource`, `attributes`, `batch` | `otlphttp/logstash`, `debug` |
