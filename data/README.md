# Usage
  Just git clone this repo, and run ./adhole.sh, which will generate a new adhole.conf.zst
  
# Files
  - adhole.sh: the main script to generate adhole.conf.zst, thanks to:
     - https://unbound.oisd.nl/
  - block_urls.txt: The main URLs to collect the block domains in the final
    list, thanks to:
     - https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts
     - https://blocklistproject.github.io/Lists/adobe.txt
  - block_domains.txt: Add your own domains to block, **LeisureLinux** is collecting more
  - unblock_domains.txt: In case you **don't** want to block some domains, e.g. exeptions
  - LICENSE: MIT License, e.g. modify at your own will, no warranty

# .gitignore
  cache for one day now, e.g. added .cache dir
```
cat ../.gitignore|sort -r
.wpad
.proxy
.gitignore
data/deploy.sh
data/.cache
adhole.conf.zst.old
```
     
# Release: [adhole.conf.zst](https://github.com/LeisureLinux/adhole/releases/download/adhole/adhole.conf.zst)
  - The **dynamic generated** list to be added in unbound DNS server
  - use zst -d adhole.conf.zst to decompress to your unbound config path
  - zst commands are from package: zst
