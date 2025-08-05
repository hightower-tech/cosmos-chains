# Monitoring Cosmos Validators with Prometheus and Grafana
<img src="https://i.imgur.com/DbbZe2X.png" style="width:200px;" /><img src="https://i.imgur.com/UtDivBB.png" style="width:198px;" /><img src="https://i.imgur.com/9wSoHEC.png" style="width:193px;" /><img src="https://i.imgur.com/2D3nPKZ.png" style="width:192px;" /><img src="https://i.imgur.com/5kmHy1M.png" style="width:190px;" /><img src="https://i.imgur.com/1l4e0Nw.png" style="width:192px;" />

While exploring optimal ways to monitor our Cosmos-Tendermint nodes, we settled on a combination of several tools:
* The built-in Prometheus endpoint for basic monitoring.
* cosmos-validators-exporter by QuokkaStake for validator-specific metrics.
* Standard Node Exporter for system-level metrics.
  
All network communication is secured via basic authentication and SSL encryption. Here are some of the steps we use to set up monitoring for our Cosmos validator infrastructure. This guide assumes that Prometheus, Grafana,  Node Exporter are already installed and running.


### Step 1. Enable Prometheus on the node
We recommend binding Prometheus to localhost and exposing it securely via nginx reverse proxy. If needed, you may allow direct external access instead.  Set `prometheus = true` and `prometheus_listen_addr = "127.0.0.1:26660"` in `config.toml`.
```
DAEMON=some-daemon
PROMETHERUS_PORT=26660

sed -i '/^\[instrumentation\]/,/^\[/{s/^\s*prometheus\s*=.*/prometheus = true/}' $HOME/.$DEAMON/config/config.toml
sed -i "/^\[instrumentation\]/,/^\[/{s/^\s*prometheus_listen_addr\s*=.*/prometheus_listen_addr = \"127.0.0.1:$PROMETHERUS_PORT\"/}" $HOME/.$DEAMON/config/config.toml
sed -i '/^\[api\]/,/^\[/{s/^\s*enable\s*=.*/enable = true/}' $HOME/.$DEAMON/config/app.toml
```


### Step 2. Install and configure Cosmos Validators Exporter
This exporter is helpful when running multiple nodes (across different networks) on the same host — a common case for Cosmos testnets.
It requires the API service to be enabled on the node. Set `enable = true` and `address = "tcp://127.0.0.1:1317` in API subsection of `app.toml`
```
API_PORT=1317

sed -i '/^\[api\]/,/^\[/{s/^\s*enable\s*=.*/enable = true/}' $HOME/.$DEAMON/config/app.toml
sed -i "/^\[api\]/,/^\[/{s/^\s*address\s*=.*/address = \"tcp:\/\/127.0.0.1:$API_PORT\"/}" $HOME/.$DEAMON/config/app.toml
```
For installation and configuration, see https://github.com/QuokkaStake/cosmos-validators-exporter. 
In our setup, we set `listen-address = "127.0.0.1:9560"` in `cosmos-validators-exporter/config.toml`.

### Step 3. Configuring Prometheus
Here comes a bit of Prometheus magic — we have three separate metric sources, and cosmos-validators-exporter can expose metrics for multiple networks from a single server.
To keep everything clean and linked, we use file-based discovery and a custom `host` label (stripping the port), which unifies metrics from the same server across jobs.
Example part of `prometheus.yml`
```
scrape_configs:
  - job_name: "Node Exporter"
    scheme: https
    basic_auth:
      username: user
      password: password
    tls_config:
      ca_file: /etc/prometheus/ca/ca.crt
      insecure_skip_verify: false
    relabel_configs:
      - source_labels: [__address__]
        regex: '(.+):(.+)'
        replacement: '${1}'
        target_label: 'host'
    file_sd_configs:
      - files:
          - 'targets/node_exporter.json'

  - job_name: cosmos-testnet
    scheme: https
    basic_auth:
      username: user
      password: password
    tls_config:
      ca_file: /etc/prometheus/ca/ca.crt
    insecure_skip_verify: false
    relabel_configs:
      - source_labels: [__address__]
        regex: '(.+):(.+)'
        replacement: '${1}'
        target_label: 'host'
    file_sd_configs:
      - files:
          - 'targets/cosmos-testnet.json'

  - job_name: "tendermint-testnet"
    scheme: https
    basic_auth:
      username: user
      password: password
    tls_config:
      ca_file: /etc/prometheus/ca/ca.crt
      insecure_skip_verify: false
    relabel_configs:
      - source_labels: [__address__]
        regex: '(.+):(.+)'
        replacement: '${1}'
        target_label: 'host'
    file_sd_configs:
      - files:
          - 'targets/tendermint-testnet.json'
```
This `prometheus.yml` example uses file-based targets for flexibility. We generate a `host` label by stripping port from `__address__`, allowing unified host-level correlation between exporters.
The files `targets/*.json` define scraping targets and instance labels. These are dynamically loaded without Prometheus restart.

For example, files such as  `/etc/prometheus/targets/tendermint-testnet.json` `/etc/prometheus/targets/cosmos-testnet.json ` `targets/node_exporter.json`
```
[
  {
    "targets": ["X.X.X.X:26660"],
    "labels": {
      "instance_name": "testnet 1",
      "tag": "#testnet1"
    }
  },
  {
    "targets": ["X.X.X.X:35660"],
    "labels": {
      "instance_name": "testnet 2",
      "tag": "#testnet2"
    }
  },
  {
    "targets": ["Y.Y.Y.Y:26660"],
    "labels": {
      "instance_name": "testnet 3",
      "tag": "#testnet3"
    }
  }
]
```

```                                                                                                    
[
  {
    "targets": ["X.X.X.X:9560"],
    "labels": {
      "instance_name": "X.X.X.X Cosmos explo",
      "tag": "#X.X.X.X Cosmos explo"
    }
  },
  {
    "targets": ["Y.Y.Y.Y:9560"],
    "labels": {
      "instance_name": "Y.Y.Y.Y Cosmos explo",
      "tag": "#Y.Y.Y.Y Cosmos explo"
    }
  }
]
```
`/etc/prometheus/targets/node_exporter.json`
```                                                                                                    
[
  {
    "targets": ["X.X.X.X:9100"],
    "labels": {
      "instance_name": "X.X.X.X Node explo",
      "tag": "#X.X.X.X Node explo"
    }
  },
  {
    "targets": ["Y.Y.Y.Y:9100"],
    "labels": {
      "instance_name": "Y.Y.Y.Y Node explo",
      "tag": "#Y.Y.Y.Y Node explo"
    }
  }
]
```

### Step 4. Authentication and SSL
Here in Prometheus config we enable HTTPS responses, set up basic authentication (login + password), and enforce SSL certificate validation.
```
    scheme: https
    basic_auth:
      username: user
      password: password
    tls_config:
      ca_file: /etc/prometheus/ca/ca.crt
```

To make it all work, we generate our own root Certificate Authority (CA) — designed to last a very long time. This gives us full control over issuing and verifying certs within our infrastructure, without relying on external CAs.

```
# make a folder for certs
mkdir -p /etc/prometheus/certs/ca
cd /etc/prometheus/certs/ca

openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 9999  -out ca.crt   -subj "/CN=MyOwnCA"
```
Generate a self-signed CA and TLS certs for each IP:

```
# make a folder for keys
mkdir -p /etc/prometheus/certs/tls-keys
cd /etc/prometheus/certs/tls-keys

# key
openssl genrsa -out node_exporter.key 2048

# cert IP X.X.X.X
openssl req -new -key node_exporter.key -out node_exporter.csr   -subj "/CN=X.X.X.X"
openssl x509 -req -in node_exporter.csr  -CA ../ca/ca.crt -CAkey ../ca/ca.key -CAcreateserial  -out X.X.X.X_node_exporter.crt -days 9999 -sha256
```
Don't forget to copy `.crt` and `.key` files to the `/etc/node_exporter` folder in approptiate server. 

### Step 6. Secure reverse proxy with nginx

To securely expose local metrics endpoints via HTTPS and protect them with basic authentication, you’ll need `nginx`.
Install nginx and required utilities

```
sudo apt update
sudo apt install nginx apache2-utils -y
```
Create basic auth credentials. This user/password pair should match the `basic_auth` section in your Prometheus scrape config. Replace `user` with your preferred username. You’ll be prompted to enter a password.

```
sudo htpasswd -c /etc/nginx/.htpasswd user
```

Enable and start nginx.

```
sudo systemctl enable nginx
sudo systemctl start nginx
```
(Optional) Allow HTTPS traffic in firewall if you’re using `ufw`:

```
sudo ufw allow 'Nginx Full'
```
You can use the following nginx examples to securely expose metrics

`/etc/nginx/site-available/cosmos-exporter `

```
server {
    listen X.X.X.X:9560 ssl;
    server_name X.X.X.X;

    ssl_certificate     /etc/node_exporter/X.X.X.X_node_exporter.crt;
    ssl_certificate_key /etc/node_exporter/X.X.X.X_node_exporter.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy-Report-Only "
        default-src 'self';
        script-src 'self';
        style-src 'self' 'unsafe-inline' fonts.googleapis.com;
        font-src 'self' fonts.gstatic.com;
        img-src 'self' data:;
        connect-src 'self' wss:;
        frame-ancestors 'none';
        base-uri 'self';
    " always;

location = /metrics {    
    auth_basic "Protected Metrics";
    auth_basic_user_file /etc/nginx/.htpasswd;
    
    proxy_pass http://localhost:9560/metrics;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_hide_header Content-Type;
    add_header Content-Type "text/plain; version=0.0.4";
}
    location / {
        return 444;
    }
}
```
`/etc/nginx/site-available/some-deamon-prometheus`
```
server {
    listen X.X.X.X:26660 ssl;
    server_name X.X.X.X;

    ssl_certificate     /etc/node_exporter/X.X.X.X_node_exporter.crt;
    ssl_certificate_key /etc/node_exporter/X.X.X.X_node_exporter.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy-Report-Only "
        default-src 'self';
        script-src 'self';
        style-src 'self' 'unsafe-inline' fonts.googleapis.com;
        font-src 'self' fonts.gstatic.com;
        img-src 'self' data:;
        connect-src 'self' wss:;
        frame-ancestors 'none';
        base-uri 'self';
    " always;

location = /metrics {
    auth_basic "Protected Metrics";
    auth_basic_user_file /etc/nginx/.htpasswd;

    proxy_pass http://localhost:26660/metrics;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_hide_header Content-Type;
    add_header Content-Type "text/plain; version=0.0.4";
}
    location / {
        return 444;
    }
}
```
Validate and reload nginx:

```
sudo nginx -t && sudo systemctl reload nginx
```

Now export grafa-dashboard.json. 
