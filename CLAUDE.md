# 飞书问卷MBTI名片生成系统使用指南

## 功能概述

本系统实现了完整的飞书问卷到MBTI个性化名片的生成流程：
1. 接收飞书多维表格发送的JSON格式数据
2. 自动获取用户上传的微信二维码图片
3. 根据MBTI类型选择对应的名片底图
4. 将6个字段信息排版到名片指定位置
5. 返回生成的名片URL给飞书

## JSON数据格式

系统接收以下JSON格式的数据（飞书多维表格自动化发送）：

```json
{
  "nickname": "用户昵称",
  "gender": "性别", 
  "profession": "职业",
  "interests": "兴趣爱好或在做的项目方向",
  "mbti": "MBTI类型（16种之一）",
  "introduction": "一句话介绍",
  "wechatQrAttachmentId": "飞书附件ID（微信二维码）"
}
```

## 启动服务

```bash
# 安装依赖
pip install -r requirements.txt

# 配置环境变量（复制.env.example为.env并填写）
cp .env.example .env

# 启动服务
python app.py
# 或指定端口
PORT=3001 python app.py
```

## 测试功能

### 基本测试
```bash
python test_mbti_card.py
```

### 调试单个MBTI类型
```bash
python debug_single_mbti.py
```

### 手动测试API
```bash
curl -X POST http://localhost:3001/hook \\
  -H "Content-Type: application/json" \\
  -d '{
    "nickname": "测试用户",
    "gender": "未知",
    "profession": "工程师", 
    "interests": "编程和设计",
    "mbti": "INFP",
    "introduction": "热爱创新的理想主义者",
    "wechatQrAttachmentId": ""
  }'
```

## API接口

### POST /hook
主要的名片生成接口

**请求格式：** JSON
**响应格式：** JSON

成功响应示例：
```json
{
  "status": "ok",
  "saved_path": "/path/to/output/名片.png",
  "image_url": "http://your-server/image/名片.png",
  "image_key": "feishu_image_key_if_uploaded",
  "send_result": {...},
  "suggestions": {
    "view_image": "访问 URL 查看生成的名片",
    "download_png": "访问 URL?format=png 下载名片", 
    "feishu_setup": "飞书配置状态"
  }
}
```

### GET /image/<filename>
访问生成的名片图片

参数：
- `?format=png` - 强制下载PNG文件

### GET /healthz
健康检查接口

## MBTI底图支持

系统支持16种MBTI类型，对应的底图文件：
- ENFJ.png, ENFP.png, ENTJ.png, ENTP.png
- ESFJ.png, ESFP.png, ESTJ.png, ESTP.png  
- INFJ.png, INFP.png, INTJ.png, INTP.png
- ISFJ.png, ISFP.png, ISTJ.png, ISTP.png

底图文件存放在 `assets/` 目录中。

## 名片布局

名片使用选定的MBTI底图作为背景，字段布局如下：
- **左上**：昵称（大字体）
- **左中**：性别 + 职业  
- **左下**：兴趣爱好（支持换行）
- **右上**：MBTI类型标识
- **右中**：一句话介绍（支持换行）
- **右下**：微信二维码（如果提供了attachmentId）

## 文件结构

```
feishu-card-bot/
├── app.py                 # 主应用文件
├── test_mbti_card.py      # 功能测试脚本
├── debug_single_mbti.py   # 单个MBTI调试脚本
├── assets/               # 资源文件
│   ├── font.ttf         # 字体文件
│   └── [MBTI].png       # 16张MBTI底图
├── output/              # 生成的名片输出目录
├── requirements.txt     # Python依赖
├── .env.example        # 环境变量示例
└── CLAUDE.md          # 本使用指南
```

## 环境变量配置

```bash
# 必需的飞书应用配置
FEISHU_APP_ID=your_app_id
FEISHU_APP_SECRET=your_app_secret

# 可选配置
FEISHU_DEBUG_OPEN_ID=debug_open_id  # 测试时强制发送消息的用户
OUTPUT_DIR=./output                 # 名片输出目录
ASSETS_DIR=./assets                # 资源文件目录
PORT=3001                          # 服务端口
```

## 错误排查

1. **端口占用错误**：使用 `PORT=其他端口 python app.py`
2. **字体渲染问题**：确保 `assets/font.ttf` 存在
3. **MBTI底图缺失**：检查 `assets/` 目录中的PNG文件
4. **飞书权限问题**：检查应用权限设置，需要上传图片权限

## 工作流程集成

1. 用户在飞书问卷中填写6个字段并上传微信二维码
2. 飞书多维表格自动化触发webhook，发送JSON到本服务
3. 服务获取微信二维码图片，生成个性化名片
4. 返回名片URL给飞书，用户可查看和下载

## 性能优化建议

- 使用生产级WSGI服务器（如Gunicorn）部署
- 配置反向代理（如Nginx）
- 定期清理output目录中的旧文件
- 考虑使用Redis缓存飞书token

---

*最后更新：2025年8月24日*