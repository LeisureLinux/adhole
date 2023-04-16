# Usage
  Just git clone this repo, and run ./adhole.sh, which will generate a new adhole.conf.xz
  
# Files
  - adhole.sh: the main script to generate adhole.conf.xz, thanks to:
     - https://unbound.oisd.nl/
  - block_urls.txt: The main URLs to collect the block domains in the final
    list, thanks to:
     - https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts
     - https://blocklistproject.github.io/Lists/adobe.txt
  - block_domains.txt: Add your own domains to block, **LeisureLinux** is collecting more
  - unblock_domains.txt: In case you **don't** want to block some domains, e.g. exeptions
  - LICENSE: MIT License, e.g. modify at your own will, no warranty
     
# Release: [adhole.conf.xz](https://raw.githubusercontent.com/LeisureLinux/adhole/main/data/adhole.conf.xz)
  - The **dynamic generated** list to be added in unbound DNS server
  - use unxz command or xz -d adhole.conf.xz to decompress to your unbound config path
  - xz & unxz commands are from package: xz-utils
