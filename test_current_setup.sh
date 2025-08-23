#!/bin/bash
# 测试当前ngrok配置的脚本

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

print_header "测试当前ngrok配置"

# 检查本地服务
print_msg "🔍 检查本地Flask服务..." $BLUE
if curl -s http://localhost:3000/healthz > /dev/null; then
    print_msg "✅ 本地Flask服务正常" $GREEN
else
    print_msg "❌ 本地Flask服务不可用" $RED
    print_msg "请先运行: ./start.sh 1" $YELLOW
    exit 1
fi

# 获取ngrok URL
print_msg "🌐 获取ngrok隧道地址..." $BLUE
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o 'https://[^"]*\.ngrok[^"]*' | head -1)

if [[ -z "$NGROK_URL" ]]; then
    print_msg "❌ 无法获取ngrok地址" $RED
    print_msg "请检查ngrok是否正在运行" $YELLOW
    print_msg "访问 http://localhost:4040 查看状态" $CYAN
    exit 1
fi

print_msg "✅ 获取到ngrok地址: $NGROK_URL" $GREEN

# 测试健康检查端点
print_header "测试API端点"
print_msg "🩺 测试健康检查端点..." $BLUE
HEALTH_RESPONSE=$(curl -s "$NGROK_URL/healthz")
if echo "$HEALTH_RESPONSE" | grep -q '"ok": true'; then
    print_msg "✅ 健康检查通过: $HEALTH_RESPONSE" $GREEN
else
    print_msg "❌ 健康检查失败: $HEALTH_RESPONSE" $RED
fi

# 测试hook端点
print_msg "🎯 测试名片生成端点..." $BLUE
HOOK_RESPONSE=$(curl -s -X POST "$NGROK_URL/hook" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "测试用户",
        "title": "测试工程师",
        "company": "测试公司",
        "email": "test@example.com"
    }')

if echo "$HOOK_RESPONSE" | grep -q '"status": "ok"'; then
    print_msg "✅ 名片生成成功!" $GREEN
    print_msg "响应: $HOOK_RESPONSE" $CYAN
    
    # 提取保存路径
    SAVED_PATH=$(echo "$HOOK_RESPONSE" | grep -o '"saved_path": "[^"]*"' | cut -d'"' -f4)
    if [[ -n "$SAVED_PATH" && -f "$SAVED_PATH" ]]; then
        print_msg "✅ 名片文件已保存: $SAVED_PATH" $GREEN
    fi
else
    print_msg "❌ 名片生成失败!" $RED
    print_msg "响应: $HOOK_RESPONSE" $RED
fi

# 提供飞书配置信息
print_header "飞书Webhook配置信息"
print_msg "🔗 Webhook URL: ${NGROK_URL}/hook" $CYAN
print_msg "📝 配置步骤:" $BLUE
echo "1. 飞书多维表格 → 自动化 → 创建自动化"
echo "2. 触发条件: 记录创建时"
echo "3. 动作: 发送HTTP请求"
echo "4. URL: ${NGROK_URL}/hook"
echo "5. 方法: POST" 
echo "6. Content-Type: application/json"
echo "7. 请求体示例:"
echo '{
  "name": "{{姓名}}",
  "title": "{{职位}}",
  "company": "{{公司}}",
  "phone": "{{电话}}",
  "email": "{{邮箱}}"
}'

print_header "测试完成"
if curl -s "$NGROK_URL/healthz" > /dev/null && echo "$HOOK_RESPONSE" | grep -q '"status": "ok"'; then
    print_msg "🎉 所有测试通过，可以开始使用!" $GREEN
    print_msg "💡 建议: 在飞书中配置上方的webhook信息" $CYAN
else
    print_msg "⚠️ 部分测试失败，请检查配置" $YELLOW
fi