# adhole
Adhole, A better pi-hole

# Files
  - LICENSE: MIT License, e.g. modify at your own will, no warranty
  - unblock_domains.txt: In case you **don't** want to block some domains, e.g. exeptions
  - block_urls.txt: The main URLs to collect the block domains in the final
    list, thanks to:
     - https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts
     - https://blocklistproject.github.io/Lists/adobe.txt
  - adhole.conf: The **dynamic generated** list to be added in unbound DNS server
  - block_domains.txt: Add your own domains to block, LeisureLinux is collecting
    more
  - adhole.sh: the main script to generate adhole.conf, thanks to:
     - https://unbound.oisd.nl/
