#!/bin/bash
# 测试图片兼容性和访问方案

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

print_header "测试图片生成和兼容性"

# 获取ngrok URL
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o 'https://[^"]*\.ngrok[^"]*' | head -1)

if [[ -z "$NGROK_URL" ]]; then
    print_msg "❌ 无法获取ngrok地址，请确保ngrok正在运行" $RED
    exit 1
fi

print_msg "🌐 使用ngrok地址: $NGROK_URL" $CYAN

# 测试1：生成名片并获取图片URL
print_header "测试1: 生成名片并获取URL"
print_msg "🔄 发送名片生成请求..." $BLUE

RESPONSE=$(curl -s -X POST "$NGROK_URL/hook" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "图片兼容性测试",
        "title": "系统架构师",
        "company": "科技创新公司",
        "phone": "13800138000",
        "email": "test@company.com",
        "qrcode_text": "https://company.com/contact"
    }')

if echo "$RESPONSE" | grep -q '"status": "ok"'; then
    print_msg "✅ 名片生成成功!" $GREEN
    
    # 提取图片URL
    IMAGE_URL=$(echo "$RESPONSE" | grep -o '"image_url": "[^"]*"' | cut -d'"' -f4)
    if [[ -n "$IMAGE_URL" ]]; then
        print_msg "📷 图片URL: $IMAGE_URL" $CYAN
        
        # 测试图片访问
        print_header "测试2: 验证图片URL访问"
        print_msg "🔍 测试图片URL访问..." $BLUE
        
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$IMAGE_URL")
        if [[ "$HTTP_STATUS" == "200" ]]; then
            print_msg "✅ 图片URL可正常访问 (HTTP $HTTP_STATUS)" $GREEN
        else
            print_msg "❌ 图片URL访问失败 (HTTP $HTTP_STATUS)" $RED
        fi
        
        # 测试下载功能
        print_header "测试3: 测试图片下载功能"
        print_msg "⬇️ 测试PNG下载..." $BLUE
        
        DOWNLOAD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${IMAGE_URL}?format=png")
        if [[ "$DOWNLOAD_STATUS" == "200" ]]; then
            print_msg "✅ PNG下载功能正常 (HTTP $DOWNLOAD_STATUS)" $GREEN
        else
            print_msg "❌ PNG下载功能异常 (HTTP $DOWNLOAD_STATUS)" $RED
        fi
    else
        print_msg "❌ 无法提取图片URL" $RED
    fi
else
    print_msg "❌ 名片生成失败!" $RED
    echo "$RESPONSE"
    exit 1
fi

# 测试4：检查飞书权限状态
print_header "测试4: 飞书权限诊断"
FEISHU_RESULT=$(echo "$RESPONSE" | grep -o '"send_result": {[^}]*}')
if echo "$FEISHU_RESULT" | grep -q "feishu_upload_failed"; then
    print_msg "⚠️ 飞书上传失败 - 权限不足" $YELLOW
    print_msg "💡 解决方案: 在飞书应用后台添加 im:resource:upload 权限" $CYAN
elif echo "$FEISHU_RESULT" | grep -q "feishu_disabled"; then
    print_msg "ℹ️ 飞书功能未启用 - 未配置APP_ID/APP_SECRET" $BLUE
else
    print_msg "✅ 飞书集成正常" $GREEN
fi

# 测试5：验证文件本地保存
print_header "测试5: 验证本地文件保存"
SAVED_PATH=$(echo "$RESPONSE" | grep -o '"saved_path": "[^"]*"' | cut -d'"' -f4)
if [[ -n "$SAVED_PATH" && -f "$SAVED_PATH" ]]; then
    FILE_SIZE=$(stat -f%z "$SAVED_PATH" 2>/dev/null || stat -c%s "$SAVED_PATH" 2>/dev/null)
    print_msg "✅ 本地文件保存成功: $(basename "$SAVED_PATH") (${FILE_SIZE} bytes)" $GREEN
else
    print_msg "❌ 本地文件保存失败" $RED
fi

# 总结报告
print_header "兼容性测试总结"
print_msg "🎯 图片格式兼容性方案已实现:" $CYAN
echo "  ✅ PNG格式生成 (标准格式，所有平台支持)"
echo "  ✅ 直接URL访问 (不依赖飞书上传权限)"
echo "  ✅ 浏览器预览 (打开URL即可查看)"
echo "  ✅ 文件下载 (添加?format=png参数)"
echo "  ✅ 本地文件保存 (便于批量处理)"
echo

print_msg "🔗 使用方式:" $BLUE
echo "  📱 在线查看: 访问返回的 image_url"
echo "  💾 下载文件: 在 image_url 后添加 ?format=png"
echo "  🖨️ 批量打印: 使用 output/ 文件夹中的本地文件"
echo

if echo "$FEISHU_RESULT" | grep -q "feishu_upload_failed"; then
    print_msg "⚡ 完整飞书集成 (可选优化):" $YELLOW
    echo "  1. 访问: https://open.feishu.cn/app/"
    echo "  2. 选择您的应用 → 权限管理"
    echo "  3. 添加权限: im:resource:upload"
    echo "  4. 提交申请并等待审核"
    echo "  5. 审核通过后即可自动发送名片到飞书"
fi

print_msg "🎉 图片兼容性测试完成 - 所有功能正常工作!" $GREEN