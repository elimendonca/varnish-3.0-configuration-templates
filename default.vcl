# Default backend definition.  Set this to point to your content server.
# all paths relative to varnish option vcl_dir

include "custom.backend.vcl";
include "custom.acl.vcl";

# Handle the HTTP request received by the client
sub vcl_recv {
    # shortcut for DFind requests
    if (req.url ~ "^/w00tw00t") {
        error 404 "Not Found";
    }

    if (req.restarts == 0) {
        if (req.http.X-Forwarded-For) {
            set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
        } else {
            set req.http.X-Forwarded-For = client.ip;
        }
    }

    # Normalize the header, remove the port (in case you're testing this on various TCP ports)
    set req.http.Host = regsub(req.http.Host, ":[0-9]+", "");

    # Allow purging
    if (req.request == "PURGE") {
        if (!client.ip ~ purge) {
            # Not from an allowed IP? Then die with an error.
            error 405 "This IP is not allowed to send PURGE requests.";
        }

        # If you got this stage (and didn't error out above), do a cache-lookup
        # That will force entry into vcl_hit() or vcl_miss() below and purge the actual cache
        return (lookup);
    }

    # Only deal with "normal" types
    if (req.request != "GET" &&
            req.request != "HEAD" &&
            req.request != "PUT" &&
            req.request != "POST" &&
            req.request != "TRACE" &&
            req.request != "OPTIONS" &&
            req.request != "PATCH" &&
            req.request != "DELETE") {
        /* Non-RFC2616 or CONNECT which is weird. */
        return (pipe);
    }

    # Only cache GET or HEAD requests. This makes sure the POST requests are always passed.
    if (req.request != "GET" && req.request != "HEAD") {
        return (pass);
    }

    # For Websocket support, always pipe the requests: https://www.varnish-cache.org/docs/3.0/tutorial/websockets.html
    if (req.http.Upgrade ~ "(?i)websocket") {
        return (pipe);
    }

    # Configure grace period, in case the backend goes down. This allows otherwise "outdated"
    # cache entries to still be served to the user, because the backend is unavailable to refresh them.
    # This may not be desireable for you, but showing a Varnish Guru Meditation error probably isn't either.
    if (req.backend.healthy) {
        set req.grace = 30s;
    } else {
        unset req.http.Cookie;
        set req.grace = 6h;
    }

    # Some generic URL manipulation, useful for all templates that follow
    # First remove the Google Analytics added parameters, useless for our backend
    if (req.url ~ "(\?|&)(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=") {
        set req.url = regsuball(req.url, "&(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "");
        set req.url = regsuball(req.url, "\?(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "?");
        set req.url = regsub(req.url, "\?&", "?");
        set req.url = regsub(req.url, "\?$", "");
    }

    # Strip hash, server doesn't need it.
    if (req.url ~ "\#") {
        set req.url = regsub(req.url, "\#.*$", "");
    }

    # Strip a trailing ? if it exists
    if (req.url ~ "\?$") {
        set req.url = regsub(req.url, "\?$", "");
    }

    # This is an example to redirect with a 301/302 HTTP status code from within Varnish
    # if (req.http.Host ~ "secure.mysite.tld") {
    #   # We may want to force our users from the secure site to the HTTPs version?
    #   error 720 "https://secure.mysite.tld";
    #   # If you want to keep the URLs intact, this also works:
    #   error 720 "https://" + req.http.Host + req.url;
    # }
    #
    # Or to force a 302 temporary redirect, use error 721
    # if (req.http.Host ~ "temp.mysite.tld") {
    #   # Temporary redirect
    #   error 721 "http://mysite.tld/temp";
    # }
    #

    # Some generic cookie manipulation, useful for all templates that follow
    # Remove the "has_js" cookie
    set req.http.Cookie = regsuball(req.http.Cookie, "has_js=[^;]+(; )?", "");

    # Remove any Google Analytics based cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "__utm.=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "_ga=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmctr=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmcmd.=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmccn.=[^;]+(; )?", "");

    # Remove DoubleClick offensive cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "__gads=[^;]+(; )?", "");

    # Remove the Quant Capital cookies (added by some plugin, all __qca)
    set req.http.Cookie = regsuball(req.http.Cookie, "__qc.=[^;]+(; )?", "");

    # Remove the AddThis cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "__atuv.=[^;]+(; )?", "");

    # Remove a ";" prefix in the cookie if present
    set req.http.Cookie = regsuball(req.http.Cookie, "^;\s*", "");

    # Are there cookies left with only spaces or that are empty?
    if (req.http.cookie ~ "^\s*$") {
        unset req.http.cookie;
    }

    # Normalize Accept-Encoding header
    # straight from the manual: https://www.varnish-cache.org/docs/3.0/tutorial/vary.html
    if (req.http.Accept-Encoding) {
        if (req.url ~ "\.(7z|bz2|docx|flac|flv|gz|jpeg|jpg|mka|mkv|mov|mp3|mp4|mpeg|mpg|ogg|ogm|opus|png|pptx|rar|svgz|tbz|tgz|txz|webm|webp|woff2|xlsx|xz|zip)$") {
            # No point in compressing these
            remove req.http.Accept-Encoding;
        } elsif (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } elsif (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            # unkown algorithm
            remove req.http.Accept-Encoding;
        }
    }

    # Large static files should be piped, so they are delivered directly to the end-user without
    # waiting for Varnish to fully read the file first.
    # TODO: once the Varnish Streaming branch merges with the master branch, use streaming here to avoid locking.
    if (req.url ~ "^[^?]*\.(7z|avi|bz2|flac|flv|gz|mka|mkv|mov|mp3|mp4|mpeg|mpg|ogg|ogm|opus|rar|tar|tgz|tbz|txz|wav|webm|xz|zip)(\?.*)?$") {
        unset req.http.Cookie;
        return (pipe);
    }

    # Remove all cookies for static files
    # A valid discussion could be held on this line: do you really need to cache static files that don't cause load? Only if you have memory left.
    # Sure, there's disk I/O, but chances are your OS will already have these files in their buffers (thus memory).
    # Before you blindly enable this, have a read here: https://ma.ttias.be/stop-caching-static-files/
    if (req.url ~ "^[^?]*\.(7z|avi|bmp|bz2|css|csv|doc|docx|eot|flac|flv|gif|gz|ico|jpeg|jpg|js|less|mka|mkv|mov|mp3|mp4|mpeg|mpg|odt|otf|ogg|ogm|opus|pdf|png|ppt|pptx|rar|rtf|svg|svgz|swf|tar|tbz|tgz|ttf|txt|txz|wav|webm|webp|woff|woff2|xls|xlsx|xml|xz|zip)(\?.*)?$") {
        unset req.http.Cookie;
        return (lookup);
    }

    # Send Surrogate-Capability headers to announce ESI support to backend
    set req.http.Surrogate-Capability = "key=ESI/1.0";

    if (req.http.Authorization) {
        # Not cacheable by default
        return (pass);
    }

    # Include custom vcl_recv logic
    include "custom.recv.vcl";

    return (lookup);
}

sub vcl_pipe {
    # Note that only the first request to the backend will have
    # X-Forwarded-For set.  If you use X-Forwarded-For and want to
    # have it set for all requests, make sure to have:
    # set bereq.http.connection = "close";
    # here.  It is not set by default as it might break some broken web
    # applications, like IIS with NTLM authentication.

    #set bereq.http.Connection = "Close";

    # Needed for WS (Websocket) support: https://www.varnish-cache.org/docs/3.0/tutorial/websockets.html
    if (req.http.upgrade) {
        set bereq.http.upgrade = req.http.upgrade;
    }

    return (pipe);
}

sub vcl_pass {
    return (pass);
}

# The data on which the hashing will take place
sub vcl_hash {
    hash_data(req.url);

    if (req.http.host) {
        hash_data(req.http.host);
    } else {
        hash_data(server.ip);
    }

    # hash cookies for requests that have them
    if (req.http.Cookie) {
        hash_data(req.http.Cookie);
    }

    return (hash);
}

sub vcl_hit {
    # Allow purges
    if (req.request == "PURGE") {
        purge;
        error 200 "purged";
    }

    return (deliver);
}

sub vcl_miss {
    # Allow purges
    if (req.request == "PURGE") {
        purge;
        error 200 "purged";
    }

    return (fetch);
}

# Handle the HTTP request coming from our backend
sub vcl_fetch {
    # Include custom vcl_fetch logic
    include "custom.fetch.vcl";

    # Parse ESI request and remove Surrogate-Control header
    if (beresp.http.Surrogate-Control ~ "ESI/1.0") {
        unset beresp.http.Surrogate-Control;
        set beresp.do_esi = true;
    }

    # https://www.varnish-cache.org/docs/3.0/tutorial/compression.html
    # gzip content that can be compressed
    # Do wildcard matches, since additional info (like charsets) can be added in the Content-Type header
    if (beresp.http.content-type ~ "text/plain"
          || beresp.http.content-type ~ "text/xml"
          || beresp.http.content-type ~ "text/css"
          || beresp.http.content-type ~ "text/html"
          || beresp.http.content-type ~ "application/(x-)?javascript"
          || beresp.http.content-type ~ "application/(x-)?font-ttf"
          || beresp.http.content-type ~ "application/(x-)?font-opentype"
          || beresp.http.content-type ~ "application/font-woff"
          || beresp.http.content-type ~ "application/vnd\.ms-fontobject"
          || beresp.http.content-type ~ "image/svg\+xml"
       ) {
        set beresp.do_gzip = true;
    }

    # If the request to the backend returns a code is 5xx, restart the loop
    # If the number of restarts reaches the value of the parameter max_restarts,
    # the request will be error'ed.  max_restarts defaults to 4.  This prevents
    # an eternal loop in the event that, e.g., the object does not exist at all.
    if (beresp.status >= 500 && beresp.status <= 599){
        return(restart);
    }

    # Enable cache for all static files
    # The same argument as the static caches from above: monitor your cache size, if you get data nuked out of it, consider giving up the static file cache.
    # Before you blindly enable this, have a read here: https://ma.ttias.be/stop-caching-static-files/
    if (req.url ~ "^[^?]*\.(7z|avi|bmp|bz2|css|csv|doc|docx|eot|flac|flv|gif|gz|ico|jpeg|jpg|js|less|mka|mkv|mov|mp3|mp4|mpeg|mpg|odt|otf|ogg|ogm|opus|pdf|png|ppt|pptx|rar|rtf|svg|svgz|swf|tar|tbz|tgz|ttf|txt|txz|wav|webm|webp|woff|woff2|xls|xlsx|xml|xz|zip)(\?.*)?$") {
        unset beresp.http.set-cookie;
    }

    # Sometimes, a 301 or 302 redirect formed via Apache's mod_rewrite can mess with the HTTP port that is being passed along.
    # This often happens with simple rewrite rules in a scenario where Varnish runs on :80 and Apache on :8080 on the same box.
    # A redirect can then often redirect the end-user to a URL on :8080, where it should be :80.
    # This may need finetuning on your setup.
    #
    # To prevent accidental replace, we only filter the 301/302 redirects for now.
    if (beresp.status == 301 || beresp.status == 302) {
        set beresp.http.Location = regsub(beresp.http.Location, ":[0-9]+", "");
    }

    # Set 2min cache if unset for static files
    if (beresp.ttl <= 0s || beresp.http.Set-Cookie || beresp.http.Vary == "*") {
        set beresp.ttl = 120s;
        return (hit_for_pass);
    }

    # If the backend response is an HTTP error (500, 502, 503), enter saint mode.
    # This will block this particular request from happening again to this backend, and will restart the request on the next available backend.
    # In case, for instance, the first backend is temporarily unavailable, this will restart the request to the second backend, without the client noticing it.
    #
    # Explained from the manual: by setting beresp.saintmode to a period of time, Varnish will not ask that backend again for this object for that amount of time.
    # This only works if you have multiple baceknds.
    if (beresp.status == 500 || beresp.status == 502 || beresp.status == 503) {
        # Don't use this server, for this particular URL, for the next 10 seconds.
        set beresp.saintmode = 10s;

        # Restart the HTTP request, this will automatically happen on the next available server (due to saintmode, see above).
        # But we don't want to restart POST requests, as that's dangerous (duplicate form submits etc.)
        if (req.request != "POST") {
            return(restart);
        }
    }

    # Keep all objects for 6h longer in the cache than their TTL specifies.
    # So even if HTTP objects are expired (they've passed their TTL), we can still use them in case all backends go down.
    # Remember: old content to show is better than no content at all (or an error page).
    set beresp.grace = 6h;

    return (deliver);
}

# The routine when we deliver the HTTP request to the user
# Last chance to modify headers that are sent to the client
sub vcl_deliver {
    if (obj.hits > 0) {
        set resp.http.X-Cache = "cached";
    } else {
        set resp.http.x-Cache = "uncached";
    }

    # Remove some headers: PHP version
    unset resp.http.X-Powered-By;

    # Remove some headers: Apache version & OS
    unset resp.http.Server;
    unset resp.http.X-Drupal-Cache;
    unset resp.http.X-Varnish;
    unset resp.http.Via;
    unset resp.http.Link;

    return (deliver);
}

sub vcl_error {
    if (obj.status >= 500 && obj.status <= 599) {
        # 4 retry for 5xx error
        return(restart);
    } elseif (obj.status >= 400 && obj.status <= 499 ) {
        # use 404 error page for 4xx error
        include "conf.d/error-404.vcl";
    } elseif (obj.status == 720) {
        # We use this special error status 720 to force redirects with 301 (permanent) redirects
        # To use this, call the following from anywhere in vcl_recv: error 720 "http://host/new.html"
        set obj.status = 301;
        set obj.http.Location = obj.response;
        return (deliver);
    } elseif (obj.status == 721) {
        # And we use error status 721 to force redirects with a 302 (temporary) redirect
        # To use this, call the following from anywhere in vcl_recv: error 720 "http://host/new.html"
        set obj.status = 302;
        set obj.http.Location = obj.response;
        return (deliver);
    } else {
        # for other errors (not 5xx, not 4xx and not 2xx)
        include "conf.d/error.vcl";
    }

    return (deliver);
}

sub vcl_init {
    return (ok);
}

sub vcl_fini {
    return (ok);
}
