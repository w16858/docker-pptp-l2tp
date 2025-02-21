#!/bin/bash

# 检查 Docker 是否已安装
if ! command -v docker &> /dev/null; then
    echo "Docker 未安装，正在安装 Docker..."
    # 更新包列表
    sudo apt-get update
    # 安装 Docker
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce
    sudo systemctl start docker
    sudo systemctl enable docker
    echo "Docker 安装完成！"
else
    echo "Docker 已安装，跳过安装步骤。"
fi


# 指向主机名
hostname=$(hostname)

# 检查 /etc/hosts 中是否已经包含该主机名指向 127.0.0.1 的条目
if ! grep -q "127.0.0.1.*$hostname" /etc/hosts; then
    # 如果没有条目，添加到 /etc/hosts 文件
    echo "127.0.0.1   $hostname" | sudo tee -a /etc/hosts > /dev/null
    echo "已成功将主机名 $hostname 指向 127.0.0.1"
    sudo systemctl restart systemd-hostnamed
else
    echo "主机名 $hostname 已经指向 127.0.0.1"
fi

# 创建所需的目录和文件
echo "正在创建所需的目录和文件..."
sudo mkdir -p /etc/ppp
echo "vp1 * aa123456+++ *" | sudo tee /etc/ppp/chap-secrets

# L2TP 共享密钥
VPN_IPSEC_PSK="vpn"
VPN_USER="vp1"
VPN_PASSWORD="aa123456+++"

# 启动 L2TP + IPsec VPN 服务器
echo "正在启动 L2TP + IPsec VPN 服务器..."

# 删除同名容器（如果已存在）
if sudo docker ps -a --format '{{.Names}}' | grep -q '^vpn-server$'; then
    echo "发现同名容器 vpn-server，正在删除..."
    sudo docker rm -f vpn-server
fi

# 启动新容器
L2TP_CONTAINER_STATUS=$(sudo docker run -d --name vpn-server --privileged --net=host -v /etc/ipsec.d -v /etc/ppp -e VPN_IPSEC_PSK="$VPN_IPSEC_PSK" -e VPN_USER="$VPN_USER" -e VPN_PASSWORD="$VPN_PASSWORD" hwdsl2/ipsec-vpn-server)
if [[ "$L2TP_CONTAINER_STATUS" ]]; then
    L2TP_STATUS="\033[0;32mL2TP + IPsec VPN 服务器正在运行...${NC}"
else
    L2TP_STATUS="\033[0;31mL2TP + IPsec VPN 服务器启动失败！${NC}"
fi

# 启动 PPTP VPN 服务器
echo "正在启动 PPTP VPN 服务器..."

# 删除同名容器（如果已存在）
if sudo docker ps -a --format '{{.Names}}' | grep -q '^pptp-vpn$'; then
    echo "发现同名容器 pptp-vpn，正在删除..."
    sudo docker rm -f pptp-vpn
fi

# 启动新容器
PPTP_CONTAINER_STATUS=$(sudo docker run -d --privileged --net=host -v /etc/ppp/chap-secrets:/etc/ppp/chap-secrets --name pptp-vpn mobtitude/vpn-pptp)
if [[ "$PPTP_CONTAINER_STATUS" ]]; then
    PPTP_STATUS="\033[0;32mPPTP VPN 服务器正在运行...${NC}"
else
    PPTP_STATUS="\033[0;31mPPTP VPN 服务器启动失败！${NC}"
fi

# 防火墙配置
echo "正在配置防火墙..."
# 检测是否使用 UFW 防火墙
if sudo ufw status &> /dev/null; then
    echo "UFW 防火墙已启用，正在添加必要的端口..."
    sudo ufw allow 500,4500,1701/udp
    sudo ufw allow proto gre
else
    echo "未启用 UFW 防火墙，跳过防火墙配置。"
fi

# 获取并显示容器列表
echo -e "\n当前 Docker 容器状态：\n"
sudo docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | tee /dev/tty | grep "Up" && GREEN='\033[0;32m' || GREEN=''
echo -e "$GREEN"

# 显示容器状态
echo -e "$L2TP_STATUS"
echo -e "$PPTP_STATUS"

# 如果两个容器都启动成功，显示账号密码和密钥
if [[ "$L2TP_CONTAINER_STATUS" ]] && [[ "$PPTP_CONTAINER_STATUS" ]]; then
    echo -e "\033[0;32mVPN 服务器已成功启动！${NC}"
    echo -e "\033[0;32mL2TP + IPsec VPN 用户名: $VPN_USER${NC}"
    echo -e "\033[0;32mL2TP + IPsec VPN 密码: $VPN_PASSWORD${NC}"
    echo -e "\033[0;32mL2TP + IPsec VPN 共享密钥: $VPN_IPSEC_PSK${NC}"
    echo -e "\033[0;32mPPTP VPN 用户名: $VPN_USER${NC}"
    echo -e "\033[0;32mPPTP VPN 密码: $VPN_PASSWORD${NC}"
else
    echo -e "\033[0;31mVPN 服务器启动失败，未显示账号和密钥！${NC}"
fi
