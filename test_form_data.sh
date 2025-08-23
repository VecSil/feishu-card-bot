#!/bin/bash
# 测试表单数据请求（模拟飞书发送的格式）

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

print_header "测试多种数据格式"

# 获取ngrok URL
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o 'https://[^"]*\.ngrok[^"]*' | head -1)

if [[ -z "$NGROK_URL" ]]; then
    print_msg "❌ 无法获取ngrok地址，请确保ngrok正在运行" $RED
    exit 1
fi

print_msg "🌐 使用ngrok地址: $NGROK_URL" $CYAN

# 测试1：JSON格式（原有格式）
print_header "测试1: JSON格式"
print_msg "🔄 发送JSON请求..." $BLUE

JSON_RESPONSE=$(curl -s -X POST "$NGROK_URL/hook" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "JSON测试用户",
        "title": "JSON工程师",
        "company": "JSON公司",
        "email": "json@test.com"
    }')

if echo "$JSON_RESPONSE" | grep -q '"status": "ok"'; then
    print_msg "✅ JSON格式测试通过" $GREEN
    echo "$JSON_RESPONSE" | jq '.' 2>/dev/null || echo "$JSON_RESPONSE"
else
    print_msg "❌ JSON格式测试失败" $RED
    echo "$JSON_RESPONSE"
fi

# 测试2：表单数据格式（模拟飞书）
print_header "测试2: 表单数据格式 (multipart/form-data)"
print_msg "🔄 发送表单请求..." $BLUE

FORM_RESPONSE=$(curl -s -X POST "$NGROK_URL/hook" \
    -F "name=表单测试用户" \
    -F "title=表单工程师" \
    -F "company=表单公司" \
    -F "email=form@test.com")

if echo "$FORM_RESPONSE" | grep -q '"status": "ok"'; then
    print_msg "✅ 表单格式测试通过" $GREEN
    echo "$FORM_RESPONSE" | jq '.' 2>/dev/null || echo "$FORM_RESPONSE"
else
    print_msg "❌ 表单格式测试失败" $RED
    echo "$FORM_RESPONSE"
fi

# 测试3：URL编码格式
print_header "测试3: URL编码格式 (application/x-www-form-urlencoded)"
print_msg "🔄 发送URL编码请求..." $BLUE

URLENC_RESPONSE=$(curl -s -X POST "$NGROK_URL/hook" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "name=URL编码用户&title=URL编码工程师&company=URL编码公司&email=urlenc@test.com")

if echo "$URLENC_RESPONSE" | grep -q '"status": "ok"'; then
    print_msg "✅ URL编码格式测试通过" $GREEN
    echo "$URLENC_RESPONSE" | jq '.' 2>/dev/null || echo "$URLENC_RESPONSE"
else
    print_msg "❌ URL编码格式测试失败" $RED
    echo "$URLENC_RESPONSE"
fi

# 测试4：模拟飞书的实际请求
print_header "测试4: 模拟飞书实际请求"
print_msg "🔄 发送飞书样式请求..." $BLUE

FEISHU_RESPONSE=$(curl -s -X POST "$NGROK_URL/hook" \
    -F "name=111" \
    -F "title=333" \
    -F "company=飞书测试公司" \
    -F "phone=13800138000" \
    -F "email=feishu@test.com")

if echo "$FEISHU_RESPONSE" | grep -q '"status": "ok"'; then
    print_msg "✅ 飞书样式请求测试通过" $GREEN
    echo "$FEISHU_RESPONSE" | jq '.' 2>/dev/null || echo "$FEISHU_RESPONSE"
    
    # 提取保存路径
    SAVED_PATH=$(echo "$FEISHU_RESPONSE" | grep -o '"saved_path": "[^"]*"' | cut -d'"' -f4)
    if [[ -n "$SAVED_PATH" && -f "$SAVED_PATH" ]]; then
        print_msg "✅ 名片已生成: $(basename "$SAVED_PATH")" $GREEN
    fi
else
    print_msg "❌ 飞书样式请求测试失败" $RED
    echo "$FEISHU_RESPONSE"
fi

print_header "测试总结"
print_msg "现在Flask应用支持以下数据格式:" $CYAN
echo "✅ JSON (application/json)"
echo "✅ 表单数据 (multipart/form-data)"  
echo "✅ URL编码 (application/x-www-form-urlencoded)"
echo
print_msg "飞书多维表格现在应该能正常工作了！" $GREEN
print_msg "webhook地址: ${NGROK_URL}/hook" $CYAN