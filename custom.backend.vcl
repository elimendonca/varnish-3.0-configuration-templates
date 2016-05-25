# First backend definition, with a built-in probe
backend default {
    # I have Virtual Hosts that only listen to the Public IP
    # so no 127.0.0.1 for me
    # Backend is running on port 81
    .host = "127.0.0.1";
    .port = "8080";
    .probe = {
        .url = "/ping";
        .timeout  = 1s;
        .interval = 10s;
        .window    = 5;
        .threshold = 2;
    }
    .first_byte_timeout     = 300s;   # How long to wait before we receive a first byte from our backend?
    .connect_timeout        = 5s;     # How long to wait for a backend connection?
    .between_bytes_timeout  = 2s;     # How long to wait between bytes received from our backend?
}

# # Backend definition with entirely custom backend probes (raw HTTP headers) in a separated definition
# backend custom_healthchecks {
#     .host  = "127.0.0.1";
#     .port  = "80";
#     .probe = custom_backend_probe;    # Refer to the probe definition below, so we can reuse the probe.

#     .first_byte_timeout     = 300s;
#     .connect_timeout        = 5s;
#     .between_bytes_timeout  = 2s;
# }

# probe custom_backend_probe {
#   .request   = "GET /some/url HTTP/1.1"
#                "Host: some.virtualhost.domain.Tld"
#                "Connection: close"
#                "Accept-Encoding: text/html"
#                "User-Agent: Varnish Health Probe";
#   .interval  = 10s;
#   .timeout   = 10s;
#   .window    = 2;
#   .threshold = 2;
# }

# # Below is an example redirector based on the Client IP (same returning class C subnet IP will get
# # rerouted to the same backend, as long as it's available).
# #
# # In order for these to work, you need to define 2 backends as shown above named 'web1' and 'web2' (replace 'default'
# # from the example above).
# director pool_clientip client {
#   {
#     .backend = web1;
#     .weight = 1;
#   }
#   {
#     .backend = web2;
#     .weight = 1;
#   }
# }

# # Below is an example that will round-robin (based on the weight) to each backend.
# # Web2 will get twice the hits as web1 since it has double the weight (= preference).
# director pool_clientip {
#   {
#     .backend = web1
#     .weight = 1;
#   }
#   {
#     .backend = web2
#     .weight = 2;
#   }
# }

