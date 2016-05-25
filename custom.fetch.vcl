# stream big file, add missing extention below
if (req.url ~ "\.(avi|deb|tar|gz|rar|iso|img|dmg|mkv|zip)$") {
    set beresp.do_stream = true;
    set beresp.ttl = 1d;
}

include "conf.d/fetch/wordpress.vcl";