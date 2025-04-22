#!/bin/bash

# 定义颜色变量
red="\033[0;31m"
green="\033[0;32m"
purple="\033[0;35m"
yellow="\033[0;33m"
plain="\033[0m"

# 脚本版本
sh_ver="1.2"

# 初始化环境目录
init_env() {
    mkdir -p /root/realm
    mkdir -p /root/.realm
}

# 配置文件路径
CONFIG_PATH="/root/.realm/config.toml"

# 处理命令行参数
while getopts "l:r:" opt; do
  case $opt in
    l)
      listen_ip_port="$OPTARG"
      ;;
    r)
      remote_ip_port="$OPTARG"
      ;;
    *)
      echo "Usage: $0 [-l listen_ip:port] [-r remote_ip:port]"
      exit 1
      ;;
  esac
done

# 如果提供了 -l 和 -r 参数，追加配置到 config.toml
if [ -n "$listen_ip_port" ] && [ -n "$remote_ip_port" ]; then
    echo "配置中转机 IP 和端口为: $listen_ip_port"
    echo "配置落地机 IP 和端口为: $remote_ip_port"

    cat <<EOF >> "$CONFIG_PATH"

[[endpoints]]
listen = "$listen_ip_port"
remote = "$remote_ip_port"
EOF
    echo "配置已追加，listen = $listen_ip_port，remote = $remote_ip_port"
    exit 0
fi

# 更新realm状态
update_realm_status() {
    if [ -f "/root/realm/realm" ]; then
        realm_status="已安装"
        realm_status_color=$green
    else
        realm_status="未安装"
        realm_status_color=$red
    fi
}

# 检查realm服务状态
check_realm_service_status() {
    if systemctl is-active --quiet realm; then
        realm_service_status="启用"
        realm_service_status_color=$green
    else
        realm_service_status="未启用"
        realm_service_status_color=$red
    fi
}

# 更新面板状态
update_panel_status() {
    if [ -f "/root/realm/web/realm_web" ]; then
        panel_status="已安装"
        panel_status_color=$green
    else
        panel_status="未安装"
        panel_status_color=$red
    fi
}

# 检查面板服务状态
check_panel_service_status() {
    if systemctl is-active --quiet realm-panel; then
        panel_service_status="启用"
        panel_service_status_color=$green
    else
        panel_service_status="未启用"
        panel_service_status_color=$red
    fi
}

# 更新脚本
Update_Shell() {
    echo -e "当前脚本版本为 [ ${sh_ver} ]，开始检测最新版本..."
    sh_new_ver=$(wget --no-check-certificate -qO- "https://raw.githubusercontent.com/yancary/realm-script/refs/heads/main/realm.sh" | grep 'sh_ver="' | awk -F "=" '{print $NF}' | sed 's/\"//g' | head -1)
    if [[ -z ${sh_new_ver} ]]; then
        echo -e "${red}检测最新版本失败！请检查网络或稍后再试。${plain}"
        return 1
    fi
    
    if [[ ${sh_new_ver} == ${sh_ver} ]]; then
        echo -e "当前已是最新版本 [ ${sh_new_ver} ]！"
        return 0
    fi
    
    echo -e "发现新版本 [ ${sh_new_ver} ]，是否更新？[Y/n]"
    read -p "(默认: y): " yn
    yn=${yn:-y}
    if [[ ${yn} =~ ^[Yy]$ ]]; then
        cp realm.sh realm.sh.bak
        wget -N --no-check-certificate https://raw.githubusercontent.com/yancary/realm-script/refs/heads/main/realm.sh -O realm.sh
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载脚本失败，请检查网络连接！${plain}"
            mv realm.sh.bak realm.sh
            return 1
        fi
        chmod +x realm.sh
        echo -e "脚本已更新为最新版本 [ ${sh_new_ver} ]！"
        exec bash realm.sh
    else
        echo -e "已取消更新。"
    fi
}

# 检查依赖
check_dependencies() {
    echo "正在检查当前环境依赖"
    local dependencies=("wget" "tar" "systemctl" "sed" "grep" "curl" "unzip")

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "正在安装 $dep..."
            if [ -x "$(command -v apt-get)" ]; then
                apt-get update && apt-get install -y "$dep"
            elif [ -x "$(command -v yum)" ]; then
                yum install -y "$dep"
            else
                echo "无法安装 $dep。请手动安装后重试。"
                exit 1
            fi
        fi
    done

    echo "所有依赖已满足。"
}

# 显示菜单的函数
show_menu() {
    clear
    update_realm_status
    check_realm_service_status
    update_panel_status
    check_panel_service_status
    echo "欢迎使用Realm一键部署脚本"
    echo "================="
    echo "1. 部署Realm"
    echo "2. 查看规则"
    echo "3. 添加规则"
    echo "4. 删除规则"
    echo "5. 启动服务"
    echo "6. 停止服务"
    echo "7. 重启服务"
    echo "8. 更新Realm"
    echo "9. 卸载Realm"
    echo "10. 更新脚本"
    echo "88. 退出脚本"
    echo "================="
    echo -e "Realm服务状态：${realm_status_color}${realm_status}${plain}"
    echo -e "Realm转发状态：${realm_service_status_color}${realm_service_status}${plain}"
}

# 部署环境的函数
deploy_realm() {
    mkdir -p /root/realm
    cd /root/realm

    _version=$(curl -s https://api.github.com/repos/zhboner/realm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$_version" ]; then
        echo "获取版本号失败，请检查本机能否链接 https://api.github.com/repos/zhboner/realm/releases/latest"
        return 1
    else
        echo "当前最新版本为: ${_version}"
    fi

    arch=$(uname -m)
    os=$(uname -s | tr '[:upper:]' '[:lower:]')

    case "$arch-$os" in
        x86_64-linux)
            download_url="https://github.com/zhboner/realm/releases/download/${_version}/realm-x86_64-unknown-linux-gnu.tar.gz"
            ;;
        x86_64-darwin)
            download_url="https://github.com/zhboner/realm/releases/download/${_version}/realm-x86_64-apple-darwin.tar.gz"
            ;;
        aarch64-linux)
            download_url="https://github.com/zhboner/realm/releases/download/${_version}/realm-aarch64-unknown-linux-gnu.tar.gz"
            ;;
        aarch64-darwin)
            download_url="https://github.com/zhboner/realm/releases/download/${_version}/realm-aarch64-apple-darwin.tar.gz"
            ;;
        arm-linux)
            download_url="https://github.com/zhboner/realm/releases/download/${_version}/realm-arm-unknown-linux-gnueabi.tar.gz"
            ;;
        armv7-linux)
            download_url="https://github.com/zhboner/realm/releases/download/${_version}/realm-armv7-unknown-linux-gnueabi.tar.gz"
            ;;
        *)
            echo -e "${red}不支持的架构或操作系统: $arch-$os${plain}"
            echo "请手动下载适配的 realm 文件并安装。"
            exit 1
            ;;
    esac

    wget -O "/root/realm/realm-${_version}.tar.gz" "$download_url"
    tar -xvf "/root/realm/realm-${_version}.tar.gz" -C /root/realm/
    chmod +x /root/realm/realm

    # 创建 config.toml 模板
    mkdir -p /root/.realm    
    cat <<EOF > "$CONFIG_PATH"
[network]
no_tcp = false #是否关闭tcp转发
use_udp = true #是否开启udp转发
EOF

    echo "[Unit]
Description=realm
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
DynamicUser=true
WorkingDirectory=/root/realm
ExecStart=/root/realm/realm -c /root/.realm/config.toml

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/realm.service

    systemctl daemon-reload
    update_realm_status
    echo "部署完成。"
}

# 卸载realm
uninstall_realm() {
    systemctl stop realm
    systemctl disable realm
    rm -f /etc/systemd/system/realm.service
    systemctl daemon-reload

    rm -f /root/realm/realm
    echo "realm已被卸载。"

    read -e -p "是否删除配置文件 (Y/N, 默认N): " delete_config
    delete_config=${delete_config:-N}

    if [[ $delete_config == "Y" || $delete_config == "y" ]]; then
        rm -rf /root/realm
        rm -rf /root/.realm
        echo "配置文件已删除。"
    else
        echo "配置文件保留。"
    fi
    update_realm_status
}

# 查看当前转发规则
view_forward_rules() {
    if [ ! -f "$CONFIG_PATH" ]; then
        echo -e "${red}配置文件不存在，未设置任何转发规则。${plain}"
        return
    fi

    if ! grep -v '^[[:space:]]*#' "$CONFIG_PATH" | grep -q "\[\[endpoints\]\]"; then
        echo -e "${red}配置文件中没有找到任何转发规则。${plain}"
        echo "请使用选项 3 添加转发规则。"
        return
    fi

    echo
    echo -e "${green}┌────────────────────────── 当前转发规则 ──────────────────────────┐${plain}"
    printf "${green}│${plain} %-4s │ %-25s │ %-28s ${green}│${plain}\n" "序号" "本地监听" "远程目标"
    echo -e "${green}├──────┼───────────────────────────┼──────────────────────────────┤${plain}"

    local idx=0
    local listen=""
    local remote=""

    while IFS= read -r line; do
        # 去掉前后的空格
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ "$line" == "[[endpoints]]" ]]; then
            if [[ -n "$listen" && -n "$remote" ]]; then
                idx=$((idx + 1))
                printf "${green}│${plain} %-4s │ %-25s │ %-28s ${green}│${plain}\n" "$idx" "$listen" "$remote"
            fi
            listen=""
            remote=""
        elif [[ "$line" == listen* ]]; then
            listen=$(echo "$line" | cut -d'"' -f2)
        elif [[ "$line" == remote* ]]; then
            remote=$(echo "$line" | cut -d'"' -f2)
        fi
    done < "$CONFIG_PATH"

    # 输出最后一组
    if [[ -n "$listen" && -n "$remote" ]]; then
        idx=$((idx + 1))
        printf "${green}│${plain} %-4s │ %-25s │ %-28s ${green}│${plain}\n" "$idx" "$listen" "$remote"
    fi

    if [ "$idx" -eq 0 ]; then
        echo -e "${green}│${plain}                    没有发现有效的转发规则                    ${green}│${plain}"
    fi

    echo -e "${green}└─────────────────────────────────────────────────────────────┘${plain}"
    echo
}

# 删除转发规则的函数
delete_forward() {
    if [ ! -f "$CONFIG_PATH" ]; then
        echo -e "${red}配置文件不存在，未设置任何转发规则。${plain}"
        return
    fi

    view_forward_rules

    local total_rules=0
    local is_comment=0
    local inblock=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            is_comment=1
            continue
        fi

        line=$(echo "$line" | sed 's/#.*$//' | xargs)
        
        if [[ -z "$line" ]]; then
            continue
        fi

        if [[ $line == "[[endpoints]]" && $is_comment -eq 0 ]]; then
            total_rules=$((total_rules + 1))
        fi
        
        if [[ $line == "[[endpoints]]" ]]; then
            is_comment=0
        fi
    done < "$CONFIG_PATH"
    
    if [ $total_rules -eq 0 ]; then
        return
    fi

    echo "请输入要删除的规则序号 [1-$total_rules]："
    echo "  -或输入范围 [例如: 1-$total_rules] 删除全部规则"
    read -p "输入序号(输入 0 取消): " choice

    if [[ "$choice" == "0" ]]; then
        echo "已取消删除操作。"
        return
    fi

    local rules_to_delete=()
    
    if [[ "$choice" =~ ^[0-9]+-[0-9]+$ ]]; then
        local start_range=$(echo "$choice" | cut -d'-' -f1)
        local end_range=$(echo "$choice" | cut -d'-' -f2)
        
        if [[ $start_range -lt 1 || $end_range -gt $total_rules || $start_range -gt $end_range ]]; then
            echo -e "${red}无效的范围，请确保范围在 1-$total_rules 之间且起始值小于结束值。${plain}"
            return
        fi
        
        for ((i=start_range; i<=end_range; i++)); do
            rules_to_delete+=($i)
        done
    elif [[ "$choice" =~ ^[0-9]+$ ]]; then
        if [[ $choice -lt 1 || $choice -gt $total_rules ]]; then
            echo -e "${red}无效的序号，请输入 1-$total_rules 之间的数字。${plain}"
            return
        fi
        rules_to_delete+=($choice)
    else
        echo -e "${red}无效的输入格式。${plain}"
        return
    fi

    IFS=$'\n' rules_to_delete=($(sort -nr <<<"${rules_to_delete[*]}"))
    unset IFS
    
    local tmp_config=$(mktemp)
    
    local deleted_count=0
    
    cp "$CONFIG_PATH" "$tmp_config"
    
    for rule_num in "${rules_to_delete[@]}"; do
        local current_rule=0
        local start_line=""
        local end_line=""
        local line_number=0
        local in_rule=0
        
        while IFS= read -r line || [[ -n "$line" ]]; do
            ((line_number++))
            
            trimmed_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            if [[ "$trimmed_line" =~ ^# ]]; then
                continue
            fi
            
            if [[ "$trimmed_line" == "[[endpoints]]" ]]; then
                ((current_rule++))
                if [[ $current_rule -eq $rule_num ]]; then
                    start_line=$line_number
                    in_rule=1
                elif [[ $in_rule -eq 1 ]]; then
                    end_line=$((line_number - 1))
                    break
                fi
            fi
        done < "$CONFIG_PATH"
        
        if [[ -n "$start_line" && -z "$end_line" ]]; then
            end_line=$(wc -l < "$CONFIG_PATH")
        fi
        
        if [[ -z "$start_line" ]]; then
            echo -e "${red}未找到规则 #$rule_num。${plain}"
            continue
        fi
        
        local extra_lines_before=0
        for ((i=start_line-1; i>=1; i--)); do
            line=$(sed "${i}q;d" "$CONFIG_PATH")
            if [[ -z "$(echo "$line" | tr -d '[:space:]')" ]]; then
                ((extra_lines_before++))
            else
                break
            fi
        done
        
        local extra_lines_after=0
        local total_lines=$(wc -l < "$CONFIG_PATH")
        for ((i=end_line+1; i<=total_lines; i++)); do
            line=$(sed "${i}q;d" "$CONFIG_PATH")
            if [[ -z "$(echo "$line" | tr -d '[:space:]')" ]]; then
                ((extra_lines_after++))
            else
                break
            fi
        done
        
        start_line=$((start_line - extra_lines_before))
        end_line=$((end_line + extra_lines_after))
        
        start_line=$((start_line > 0 ? start_line : 1))
        
        sed -i "${start_line},${end_line}d" "$tmp_config"
        ((deleted_count++))
    done
    
    if [[ $deleted_count -gt 0 ]]; then
        sed -i '/^[[:space:]]*$/N;/^\n[[:space:]]*$/D' "$tmp_config"
        mv "$tmp_config" "$CONFIG_PATH"
    else
        rm -f "$tmp_config"
    fi

    if [[ $deleted_count -eq 0 ]]; then
        echo -e "${red}未删除任何规则。${plain}"
    elif [[ $deleted_count -eq 1 ]]; then
        echo -e "${green}已成功删除 1 条规则。${plain}"
    else
        echo -e "${green}已成功删除 $deleted_count 条规则。${plain}"
    fi
    
    echo "当前剩余规则："
    view_forward_rules
    
    if [[ $deleted_count -gt 0 ]]; then
        echo -e "${yellow}注意: 规则删除后需要重启服务才能生效。${plain}"
        read -e -p "是否立即重启服务使更改生效? (Y/N): " restart_service
        
        if [[ $restart_service == "Y" || $restart_service == "y" ]]; then
            systemctl restart realm.service
            echo -e "${green}服务已重启，更改已生效。${plain}"
            check_realm_service_status
        else
            echo -e "${yellow}您选择了不重启服务，请记得手动重启服务以使更改生效。${plain}"
        fi
    fi
}

# 添加转发规则
add_forward() {
    while true; do
        read -e -p "请输入本地中转节点的端口（port1）: " port1
        read -e -p "请输入落地节点的IP: " ip
        read -e -p "请输入落地节点端口（port2）: " port2
        echo "
[[endpoints]]
listen = \"0.0.0.0:$port1\"
remote = \"$ip:$port2\"" >> /root/.realm/config.toml

        read -e -p "是否继续添加转发规则(Y/N)? " answer
        if [[ $answer != "Y" && $answer != "y" ]]; then
            break
        fi
    done
    
    echo -e "${green}转发规则添加完成。${plain}"
    echo -e "${yellow}注意: 新添加的规则需要重启服务后才能生效。${plain}"
    read -e -p "是否立即重启服务使规则生效? (Y/N): " restart_service
    
    if [[ $restart_service == "Y" || $restart_service == "y" ]]; then
        systemctl restart realm.service
        echo -e "${green}服务已重启，规则已生效。${plain}"
        check_realm_service_status
    else
        echo -e "${yellow}您选择了不重启服务，请记得手动重启服务以使规则生效。${plain}"
    fi
}

# 启动服务
start_service() {
    systemctl unmask realm.service
    systemctl daemon-reload
    systemctl restart realm.service
    systemctl enable realm.service
    echo "Realm服务已启动并设置为开机自启。"
    check_realm_service_status
}

# 停止服务
stop_service() {
    systemctl stop realm.service
    systemctl disable realm.service
    echo "Realm服务已停止并已禁用开机自启。"
    check_realm_service_status
}

# 重启服务
restart_service() {
    systemctl daemon-reload
    systemctl restart realm.service
    echo "realm服务已重启。"
    check_realm_service_status
}

# 更新realm
update_realm() {
    echo "> 检测并更新 Realm"

    current_version=$(/root/realm/realm --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    tag_version=$(curl -Ls "https://api.github.com/repos/zhboner/realm/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [[ -z "$tag_version" ]]; then
        echo -e "${red}获取 Realm 版本失败，可能是由于 GitHub API 限制，请稍后再试${plain}"
        exit 1
    fi

    if [[ "$current_version" == "$tag_version" ]]; then
        echo "当前已经是最新版本: ${current_version}"
        return
    fi

    echo -e "获取到 Realm 最新版本: ${tag_version}，开始安装..."

    arch=$(uname -m)
    wget -N --no-check-certificate -O /root/realm/realm.tar.gz "https://github.com/zhboner/realm/releases/download/${tag_version}/realm-${arch}-unknown-linux-gnu.tar.gz"
    
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载 realm 失败，请确保您的服务器可以访问 GitHub${plain}"
        exit 1
    fi

    cd /root/realm
    tar -xvf realm.tar.gz
    chmod +x realm

    echo -e "Realm 更新成功。"
    update_realm_status
}

# 主程序入口
main() {
    check_dependencies
    init_env

    while true; do
        show_menu
        read -p "请输入选项 [1-88]: " choice

        case $choice in
            1) deploy_realm ;;
            2) view_forward_rules ;;
            3) add_forward ;;
            4) delete_forward ;;
            5) start_service ;;
            6) stop_service ;;
            7) restart_service ;;
            8) update_realm ;;
            9) uninstall_realm ;;
            10) Update_Shell ;;
            88) exit 0 ;;
            *) echo "无效的选项，请重新输入。" ;;
        esac
        
        if [ "$choice" != "88" ]; then
            echo
            echo
            echo -e "${purple}按回车键返回主菜单...${plain}"
            read -n 1
        fi
    done
}

main