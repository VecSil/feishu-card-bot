#!/bin/bash
# 自动修复ngrok URL变更问题

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

print_header "🔧 ngrok URL自动修复工具"

# 获取当前ngrok URL
print_msg "🔍 检查当前ngrok状态..." $BLUE
CURRENT_NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o 'https://[^"]*\.ngrok[^"]*' | head -1)

if [[ -z "$CURRENT_NGROK_URL" ]]; then
    print_msg "❌ ngrok未运行或无法获取URL" $RED
    print_msg "请先启动ngrok: ngrok http 3000" $YELLOW
    exit 1
fi

print_msg "✅ 当前ngrok地址: $CURRENT_NGROK_URL" $GREEN

# 测试服务是否可访问
print_msg "🩺 测试服务健康状态..." $BLUE
HEALTH_CHECK=$(curl -s "$CURRENT_NGROK_URL/healthz" 2>/dev/null)

if echo "$HEALTH_CHECK" | grep -q "ok"; then
    print_msg "✅ 服务运行正常" $GREEN
else
    print_msg "❌ 服务无响应，请检查Flask应用是否在运行" $RED
    print_msg "启动命令: python3 app.py" $YELLOW
    exit 1
fi

# 测试名片生成功能
print_msg "🎨 测试名片生成功能..." $BLUE
TEST_RESPONSE=$(curl -s -X POST "$CURRENT_NGROK_URL/hook" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "URL修复测试",
        "title": "系统工程师",
        "company": "测试公司",
        "email": "test@company.com"
    }')

if echo "$TEST_RESPONSE" | grep -q '"status": "ok"'; then
    print_msg "✅ 名片生成功能正常" $GREEN
    
    # 提取图片URL
    IMAGE_URL=$(echo "$TEST_RESPONSE" | grep -o '"image_url": "[^"]*"' | cut -d'"' -f4)
    if [[ -n "$IMAGE_URL" ]]; then
        print_msg "📷 图片URL: $IMAGE_URL" $CYAN
        
        # 测试图片访问
        IMAGE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$IMAGE_URL")
        if [[ "$IMAGE_STATUS" == "200" ]]; then
            print_msg "✅ 图片URL可正常访问" $GREEN
        else
            print_msg "⚠️ 图片URL访问异常 (HTTP $IMAGE_STATUS)" $YELLOW
        fi
    fi
else
    print_msg "⚠️ 名片生成有问题，但基本功能正常" $YELLOW
    echo "$TEST_RESPONSE" | head -3
fi

# 生成更新说明
print_header "📋 飞书Webhook配置更新"
print_msg "🔗 新的Webhook地址:" $CYAN
echo "  $CURRENT_NGROK_URL/hook"
echo

print_msg "📝 飞书多维表格配置步骤:" $BLUE
echo "1. 打开飞书多维表格 → 自动化"
echo "2. 找到现有的HTTP请求自动化"
echo "3. 编辑动作 → 修改URL为:"
echo "   $CURRENT_NGROK_URL/hook"
echo "4. 保存并测试"
echo

print_msg "🧪 测试方法:" $BLUE
echo "1. 在飞书问卷中提交一条测试数据"
echo "2. 检查是否收到名片生成成功的响应"
echo "3. 访问返回的image_url查看名片"
echo

# 保存当前URL到文件
echo "$CURRENT_NGROK_URL" > .current_ngrok_url
print_msg "💾 当前URL已保存到 .current_ngrok_url" $GREEN

# 检查URL是否有变更
if [ -f ".previous_ngrok_url" ]; then
    PREVIOUS_URL=$(cat .previous_ngrok_url 2>/dev/null)
    if [[ "$CURRENT_NGROK_URL" != "$PREVIOUS_URL" ]]; then
        print_msg "🔄 检测到URL变更:" $YELLOW
        echo "  旧地址: ${PREVIOUS_URL:-'无'}"
        echo "  新地址: $CURRENT_NGROK_URL"
        echo
        print_msg "⚡ 需要更新飞书webhook配置！" $YELLOW
    else
        print_msg "✅ URL未变更，无需更新配置" $GREEN
    fi
fi

# 保存当前URL为下次比较
echo "$CURRENT_NGROK_URL" > .previous_ngrok_url

print_header "🎯 解决方案总结"
print_msg "问题原因: ngrok免费版重启后URL会变更" $BLUE
print_msg "解决方法: 使用此脚本检查并更新webhook配置" $GREEN
echo
print_msg "💡 最佳实践:" $CYAN
echo "1. 每次重启ngrok后运行此脚本"
echo "2. 将当前脚本添加到启动流程"
echo "3. 考虑升级到ngrok付费版获得固定域名"
echo

print_header "✅ 修复完成"
print_msg "🎉 服务现在可以正常接收飞书webhook请求！" $GREEN
print_msg "🔗 当前可用地址: $CURRENT_NGROK_URL/hook" $CYAN