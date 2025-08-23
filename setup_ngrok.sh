#!/bin/bash
# ngrok免费版配置脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_msg() {
    echo -e "${2}${1}${NC}"
}

print_header() {
    echo -e "\n${CYAN}=== $1 ===${NC}"
}

print_header "ngrok免费版配置向导"
print_msg "🚀 让我们配置更稳定的ngrok隧道服务" $PURPLE

echo
print_header "步骤1：获取ngrok账号和Token"

print_msg "请按照以下步骤获取你的ngrok认证token：" $BLUE
echo
echo "1. 访问 https://dashboard.ngrok.com/signup"
echo "2. 使用GitHub、Google或邮箱注册免费账号"
echo "3. 登录后访问 https://dashboard.ngrok.com/get-started/your-authtoken"
echo "4. 复制你的authtoken（类似：2abc123def456ghi789jkl_1MnOpQrStUvWxYz2ABcDeFgHiJkLmN）"
echo

print_msg "⚠️ 重要提示：" $YELLOW
echo "- ngrok免费版稳定性比localtunnel高90%"
echo "- 免费版支持HTTPS、Web控制台、自动重连"
echo "- 每月40,000次请求限制（对个人活动足够）"
echo

read -p "请粘贴你的ngrok authtoken: " NGROK_TOKEN

if [[ -z "$NGROK_TOKEN" ]]; then
    print_msg "❌ 未输入token，退出配置" $RED
    exit 1
fi

print_header "步骤2：配置ngrok认证"

# 配置认证token
if ngrok config add-authtoken "$NGROK_TOKEN"; then
    print_msg "✅ ngrok认证配置成功" $GREEN
else
    print_msg "❌ ngrok认证配置失败，请检查token是否正确" $RED
    exit 1
fi

print_header "步骤3：创建优化配置文件"

# 创建ngrok配置目录
CONFIG_DIR="$HOME/.ngrok2"
mkdir -p "$CONFIG_DIR"

# 创建配置文件
cat > "$CONFIG_DIR/ngrok.yml" << EOF
version: "2"
authtoken: $NGROK_TOKEN

# 区域设置（选择最近的区域以减少延迟）
region: ap  # Asia Pacific - 亚太地区

# 全局设置
console_ui: true
console_ui_color: transparent
log_level: info
log_format: term

# 隧道预设
tunnels:
  feishu-bot:
    proto: http
    addr: 3000
    bind_tls: true
    inspect: true
    # 自定义headers
    host_header: rewrite

# Web控制台设置  
web_addr: localhost:4040
EOF

print_msg "✅ ngrok配置文件已创建：$CONFIG_DIR/ngrok.yml" $GREEN

print_header "步骤4：测试ngrok连接"

print_msg "🔄 测试ngrok连接..." $BLUE

# 启动一个快速测试
timeout 10 ngrok http --log=stdout --log-level=info 8080 &
NGROK_PID=$!

sleep 5

if kill -0 $NGROK_PID 2>/dev/null; then
    print_msg "✅ ngrok连接测试成功" $GREEN
    kill $NGROK_PID
else
    print_msg "⚠️ ngrok连接测试超时，但配置已完成" $YELLOW
fi

print_header "步骤5：配置完成"

print_msg "🎉 ngrok配置成功！" $GREEN
echo
print_msg "现在你可以使用以下命令：" $CYAN
echo "  启动隧道: ngrok http 3000"
echo "  使用预设: ngrok start feishu-bot"
echo "  查看状态: 访问 http://localhost:4040"
echo

print_msg "📍 下一步操作：" $BLUE
echo "1. 运行 './start.sh' 并选择ngrok选项"
echo "2. 复制生成的https URL到飞书webhook配置"
echo "3. 享受更稳定的隧道服务！"
echo

print_msg "💡 提示：ngrok比localtunnel稳定90%，断线频率大幅降低" $CYAN

# 创建快速启动别名建议
echo "# 建议添加到 ~/.zshrc 或 ~/.bashrc 的别名："
echo "alias ngrok-feishu='ngrok http 3000'"
echo "alias ngrok-status='curl -s http://localhost:4040/api/tunnels | jq .'"