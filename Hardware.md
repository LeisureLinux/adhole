#### 硬件板子使用说明
 - 如果已经有一块香橙派 (Orange Pi)，并且已经有一张烧写好 Debian/Armbian 操作系统，已经做好配置的一张 SD 卡．
 - 把板子的网口(RJ45)连接到家里无线路由器的LAN口，Type-C 供电后，可以看到连接的网口灯都会亮起．
 - 浏览器登陆无线路由器的管理界面，可以看到有一台新的设备，名称为 wpad，去 LAN DHCP 或者相关界面，把IP地址和 MAC 地址绑定，确保板子的IP地址不会变动．
 - 在无线路由器的 DHCP　管理界面，把第一个 DNS 的 IP 地址，设置为上面 wpad 的 IP 地址，第二个DNS IP建议设置为阿里云的 223.5.5.5，保存配置后，重启无线路由器.
 - 以上 DNS 配置完成后，在 PC 上运行 nslookup a.baidu.com 应该返回 0.0.0.0 的地址(广告以及恶意网站阻挡能力)
 - 在手机，智能电视，Pad，Windows PC(IE浏览器) 等设备上，设置 HTTP 代理为＂自动＂即可科学上网．

#### SwitchyOmega 插件
 - 在 Chrome 浏览器上，建议安装 SwitchyOmega 浏览器插件(从 Chrome 应用商店安装需要先全局科学上网)， https://www.bilibili.com/video/BV1eu4y1A7DX/

#### 工作原理
 - 板子上启动了 80 端口用于 WPAD 服务，Web Proxy Auto Discovery，如果设置了自动代理，会寻找 http://wpad/wpad.dat 这个代理脚本（可以理解为 JS 代码）
 - wpad.dat 上规定了设置代理的规则，例如访问哪些网站要使用哪个代理服务
 - 板子本身启动了一个 sock5 的代理服务(自定义端口2023)，上层又启动了一个转化为 http 协议的代理服务（自定义端口8888）
 - 如果 PC 端要使用代理服务，既可以用 http://wpad:8888/ 也可以用 socks5h://wpad:2023/ 就可以科学上网．
   - 例如：命令行下可以用：curl -q -x http://wpad:8888/ https://www.google.com/ 

#### 问题诊断
 - 有问题不能解决的话，找一台有 ssh 客户端的 PC 操作系统，Windows 上，有 git-bash， putty 等，macOS 和 Linux 都自带 ssh 客户端
 - ssh adhole@IP (口令为： ADh0!@#$)

