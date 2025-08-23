#!/bin/bash
# 测试飞书问卷图片Webhook功能

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

print_header "飞书问卷图片Webhook功能测试"

# 获取服务地址
SERVICE_PORT=${PORT:-3001}
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o 'https://[^"]*\.ngrok[^"]*' | head -1)

if [[ -n "$NGROK_URL" ]]; then
    SERVICE_URL="$NGROK_URL"
    print_msg "🌐 使用ngrok地址: $SERVICE_URL" $CYAN
else
    SERVICE_URL="http://localhost:$SERVICE_PORT"
    print_msg "🏠 使用本地地址: $SERVICE_URL" $YELLOW
fi

# 测试1: 健康检查
print_header "测试1: 服务健康检查"
print_msg "🏥 检查服务状态..." $BLUE

HEALTH_RESPONSE=$(curl -s "$SERVICE_URL/healthz" 2>/dev/null)
if echo "$HEALTH_RESPONSE" | grep -q "ok"; then
    print_msg "✅ 服务运行正常" $GREEN
    echo "$HEALTH_RESPONSE"
else
    print_msg "❌ 服务异常或未启动" $RED
    print_msg "请先运行: ./start_survey_webhook.sh" $YELLOW
    exit 1
fi

# 测试2: 模拟多维表格Webhook
print_header "测试2: 模拟多维表格Webhook请求"
print_msg "📨 发送模拟问卷数据..." $BLUE

WEBHOOK_RESPONSE=$(curl -s -X POST "$SERVICE_URL/webhook" \
    -H "Content-Type: application/json" \
    -d '{
        "event": {
            "after_change": {
                "fields": {
                    "姓名": "张三",
                    "邮箱": "zhangsan@example.com",
                    "头像照片": [
                        {
                            "file_token": "mock_image_token_001",
                            "name": "avatar.jpg",
                            "type": "image/jpeg", 
                            "size": 102400
                        }
                    ],
                    "身份证照片": [
                        {
                            "file_token": "mock_image_token_002", 
                            "name": "id_card.png",
                            "type": "image/png",
                            "size": 256000
                        }
                    ]
                }
            }
        }
    }')

if echo "$WEBHOOK_RESPONSE" | grep -q "ok"; then
    print_msg "✅ Webhook处理成功" $GREEN
    echo "$WEBHOOK_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$WEBHOOK_RESPONSE"
else
    print_msg "❌ Webhook处理失败" $RED
    echo "$WEBHOOK_RESPONSE"
fi

# 测试3: 测试专用端点
print_header "测试3: 内置测试功能"
print_msg "🧪 运行内置测试..." $BLUE

TEST_RESPONSE=$(curl -s -X POST "$SERVICE_URL/test" 2>/dev/null)
if echo "$TEST_RESPONSE" | grep -q "test_result"; then
    print_msg "✅ 内置测试完成" $GREEN
    echo "$TEST_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$TEST_RESPONSE"
else
    print_msg "❌ 内置测试失败" $RED
    echo "$TEST_RESPONSE"
fi

# 测试4: 检查文件下载目录
print_header "测试4: 检查下载目录"
print_msg "📁 检查图片下载目录..." $BLUE

if [ -d "downloaded_images" ]; then
    IMAGE_COUNT=$(find downloaded_images -type f | wc -l)
    print_msg "✅ 下载目录存在，包含 $IMAGE_COUNT 个文件" $GREEN
    
    if [ "$IMAGE_COUNT" -gt 0 ]; then
        print_msg "📋 最近下载的文件:" $CYAN
        ls -la downloaded_images/ | tail -5
    fi
else
    print_msg "⚠️ 下载目录不存在" $YELLOW
fi

# 测试5: 验证环境变量
print_header "测试5: 环境变量检查"
print_msg "🔍 检查关键配置..." $BLUE

if [ -f "survey_webhook.env" ]; then
    print_msg "✅ 配置文件存在" $GREEN
    
    source survey_webhook.env
    
    if [[ -n "$FEISHU_APP_ID" ]]; then
        print_msg "✅ FEISHU_APP_ID: ${FEISHU_APP_ID:0:10}..." $GREEN
    else
        print_msg "❌ FEISHU_APP_ID 未配置" $RED
    fi
    
    if [[ -n "$TARGET_WEBHOOK_URL" ]]; then
        print_msg "✅ TARGET_WEBHOOK_URL: $TARGET_WEBHOOK_URL" $GREEN
    else
        print_msg "⚠️ TARGET_WEBHOOK_URL 未配置" $YELLOW
    fi
else
    print_msg "❌ 配置文件不存在" $RED
    print_msg "请先运行: ./setup_survey_webhook.sh" $YELLOW
fi

# 生成配置信息
print_header "配置信息总结"
print_msg "🔗 Webhook配置信息:" $CYAN
echo "多维表格Webhook URL: $SERVICE_URL/webhook"
echo "服务健康检查: $SERVICE_URL/healthz"
echo "图片访问地址: $SERVICE_URL/images/{filename}"
echo "测试端点: $SERVICE_URL/test"

print_header "飞书多维表格配置步骤"
print_msg "📋 在飞书中配置以下信息:" $BLUE
echo "1. 打开飞书多维表格 → 自动化"  
echo "2. 创建自动化 → 选择触发条件: 记录创建/更新"
echo "3. 添加动作: 发送HTTP请求"
echo "4. 配置请求信息:"
echo "   - URL: $SERVICE_URL/webhook"
echo "   - 方法: POST"
echo "   - Content-Type: application/json"
echo "   - 请求体: 选择发送字段数据"

print_header "测试完成"
if curl -s "$SERVICE_URL/healthz" >/dev/null 2>&1; then
    print_msg "🎉 系统运行正常，可以开始接收飞书问卷数据！" $GREEN
else
    print_msg "⚠️ 请检查服务状态并重新测试" $YELLOW
fi