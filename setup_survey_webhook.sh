#!/bin/bash
# 飞书问卷图片Webhook服务配置脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_msg() {
    echo -e "${2}${1}${NC}"
}

print_header() {
    echo -e "\n${CYAN}=== $1 ===${NC}"
}

print_header "飞书问卷图片Webhook服务配置"

# 检查Python环境
print_msg "🐍 检查Python环境..." $BLUE
if ! command -v python3 &> /dev/null; then
    print_msg "❌ Python3未安装" $RED
    exit 1
fi

python_version=$(python3 --version)
print_msg "✅ $python_version" $GREEN

# 检查并安装依赖
print_msg "📦 检查依赖包..." $BLUE
pip3 install flask requests pillow

# 创建必要的目录
print_msg "📁 创建目录结构..." $BLUE
mkdir -p downloaded_images
mkdir -p logs

# 配置环境变量
print_header "环境变量配置"

# 检查现有配置
if [[ -z "$FEISHU_APP_ID" ]]; then
    print_msg "🔑 请输入飞书应用ID (FEISHU_APP_ID):" $YELLOW
    read -p "APP_ID: " input_app_id
    export FEISHU_APP_ID="$input_app_id"
else
    print_msg "✅ 飞书APP_ID已配置" $GREEN
fi

if [[ -z "$FEISHU_APP_SECRET" ]]; then
    print_msg "🔐 请输入飞书应用密钥 (FEISHU_APP_SECRET):" $YELLOW
    read -p "APP_SECRET: " input_app_secret
    export FEISHU_APP_SECRET="$input_app_secret"
else
    print_msg "✅ 飞书APP_SECRET已配置" $GREEN
fi

if [[ -z "$TARGET_WEBHOOK_URL" ]]; then
    print_msg "🎯 请输入目标数据库Webhook地址 (TARGET_WEBHOOK_URL):" $YELLOW
    read -p "Webhook URL: " input_webhook_url
    export TARGET_WEBHOOK_URL="$input_webhook_url"
else
    print_msg "✅ 目标Webhook已配置: $TARGET_WEBHOOK_URL" $GREEN
fi

# 保存环境变量到文件
print_msg "💾 保存环境变量配置..." $BLUE
cat > survey_webhook.env << EOF
export FEISHU_APP_ID="$FEISHU_APP_ID"
export FEISHU_APP_SECRET="$FEISHU_APP_SECRET"
export TARGET_WEBHOOK_URL="$TARGET_WEBHOOK_URL"
export IMAGE_DOWNLOAD_DIR="./downloaded_images"
export PORT="3001"
EOF

print_msg "✅ 配置已保存到 survey_webhook.env" $GREEN

# 创建启动脚本
print_msg "🚀 创建启动脚本..." $BLUE
cat > start_survey_webhook.sh << 'EOF'
#!/bin/bash
# 飞书问卷图片Webhook服务启动脚本

echo "🚀 启动飞书问卷图片Webhook服务..."

# 加载环境变量
if [ -f survey_webhook.env ]; then
    source survey_webhook.env
    echo "✅ 环境变量已加载"
else
    echo "❌ 找不到环境变量文件 survey_webhook.env"
    exit 1
fi

# 检查必要的环境变量
if [[ -z "$FEISHU_APP_ID" || -z "$FEISHU_APP_SECRET" ]]; then
    echo "❌ 飞书应用配置不完整，请运行 ./setup_survey_webhook.sh"
    exit 1
fi

echo "📊 配置信息:"
echo "  - APP_ID: ${FEISHU_APP_ID:0:10}..."
echo "  - 目标Webhook: ${TARGET_WEBHOOK_URL:-'未配置'}"
echo "  - 图片目录: ${IMAGE_DOWNLOAD_DIR}"
echo "  - 服务端口: ${PORT}"

# 启动服务
echo "🎯 启动Webhook服务..."
python3 feishu_survey_image_webhook.py
EOF

chmod +x start_survey_webhook.sh
print_msg "✅ 启动脚本已创建: start_survey_webhook.sh" $GREEN

# 测试配置
print_header "配置测试"
print_msg "🧪 测试飞书API连接..." $BLUE

python3 << EOF
import os
import requests

app_id = "$FEISHU_APP_ID"  
app_secret = "$FEISHU_APP_SECRET"

if app_id and app_secret:
    try:
        url = "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal/"
        payload = {"app_id": app_id, "app_secret": app_secret}
        response = requests.post(url, json=payload, timeout=10)
        
        if response.status_code == 200:
            data = response.json()
            if data.get("code") == 0:
                print("✅ 飞书API连接成功")
            else:
                print(f"❌ 飞书API错误: {data.get('msg')}")
        else:
            print(f"❌ HTTP错误: {response.status_code}")
    except Exception as e:
        print(f"❌ 连接测试失败: {e}")
else:
    print("⚠️ 飞书配置不完整，跳过API测试")
EOF

print_header "配置完成"
print_msg "🎉 飞书问卷图片Webhook服务配置完成！" $GREEN
echo
print_msg "📋 下一步操作:" $CYAN
echo "1. 启动服务: ./start_survey_webhook.sh"
echo "2. 获取ngrok地址: curl -s http://localhost:4040/api/tunnels"
echo "3. 在飞书多维表格中配置Webhook"
echo "4. 测试完整流程"
echo
print_msg "📖 详细配置指南请查看生成的文档" $BLUE