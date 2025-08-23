#!/bin/bash
# 快速测试排版效果 - 开发调试工具
# 使用方式: ./quick_test.sh

set -e  # 遇到错误立即退出

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

print_msg() {
    echo -e "${2}${1}${NC}"
}

# 检查服务状态
check_service() {
    print_msg "🔍 检查服务状态..." $BLUE
    
    if ! curl -s http://localhost:3001/healthz > /dev/null 2>&1; then
        print_msg "❌ 服务未运行，请先启动Flask服务" $RED
        print_msg "运行: PORT=3001 python app.py" $YELLOW
        exit 1
    fi
    
    print_msg "✅ 服务运行正常" $GREEN
}

# 生成测试图片
generate_test_image() {
    local timestamp=$(date +%H%M%S)
    print_msg "🎨 生成排版测试图片 ($timestamp)..." $BLUE
    
    # 测试数据 - 使用典型的MBTI信息
    local test_data='{
        "nickname": "排版测试'$timestamp'",
        "gender": "女",
        "profession": "UI设计师",
        "interests": "用户体验设计,交互设计,界面美学,产品思维",
        "mbti": "ISFP",
        "introduction": "追求美与和谐的设计师，热爱创造有温度的产品体验",
        "wechatQrAttachmentId": ""
    }'
    
    # 发送请求
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST http://localhost:3001/hook \
        -H "Content-Type: application/json" \
        -d "$test_data" 2>/dev/null)
    
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" == "200" ]]; then
        print_msg "✅ 图片生成成功!" $GREEN
        
        # 尝试从响应中提取有用信息
        if command -v jq &> /dev/null; then
            local saved_path=$(echo "$response_body" | jq -r '.saved_path // ""')
            local image_url=$(echo "$response_body" | jq -r '.image_url // ""')
            
            if [[ -n "$saved_path" && "$saved_path" != "null" ]]; then
                local filename=$(basename "$saved_path")
                print_msg "📁 文件已保存: $filename" $GREEN
            fi
            
            if [[ -n "$image_url" && "$image_url" != "null" ]]; then
                print_msg "🔗 图片URL: ${image_url:0:60}..." $BLUE
            fi
        fi
        
        return 0
    else
        print_msg "❌ 图片生成失败 (HTTP $http_code)" $RED
        print_msg "错误信息: $response_body" $RED
        return 1
    fi
}

# 打开output文件夹
open_output_folder() {
    print_msg "📂 打开output文件夹..." $BLUE
    
    # 确保output目录存在
    if [[ ! -d "output" ]]; then
        print_msg "⚠️ output目录不存在，正在创建..." $YELLOW
        mkdir -p output
    fi
    
    # 检查是否有生成的图片
    local png_count=$(find output -name "*.png" -type f | wc -l)
    if [[ $png_count -gt 0 ]]; then
        print_msg "📸 找到 $png_count 个PNG文件" $GREEN
        
        # 显示最新的3个文件
        print_msg "最新生成的图片:" $BLUE
        ls -lt output/*.png | head -3 | while read -r line; do
            local filename=$(basename "$(echo "$line" | awk '{print $9}')")
            local filedate=$(echo "$line" | awk '{print $6, $7, $8}')
            print_msg "  📄 $filename ($filedate)" $GREEN
        done
    else
        print_msg "⚠️ output目录中暂无PNG文件" $YELLOW
    fi
    
    # 使用macOS的open命令打开文件夹
    if command -v open &> /dev/null; then
        open output/
        print_msg "✅ 已在Finder中打开output文件夹" $GREEN
    else
        print_msg "💡 请手动查看 output/ 目录中的图片文件" $YELLOW
    fi
}

# 主函数
main() {
    print_msg "🚀 飞书MBTI名片 - 快速排版测试工具" $BLUE
    print_msg "=================================================" $BLUE
    
    # 1. 检查服务
    check_service
    
    # 2. 生成测试图片
    if generate_test_image; then
        echo
        # 3. 打开输出文件夹
        open_output_folder
        
        echo
        print_msg "🎉 测试完成! 请查看生成的图片效果" $GREEN
        print_msg "💡 提示: 可重复运行此脚本快速测试不同参数" $YELLOW
    else
        print_msg "❌ 测试失败，请检查服务日志" $RED
        exit 1
    fi
}

# 信号处理
trap 'print_msg "\n🛑 测试被中断" $RED; exit 130' INT

# 执行主函数
main "$@"