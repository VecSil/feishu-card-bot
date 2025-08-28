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

### 标准启动方法（推荐）
```bash
# 使用启动脚本（自动处理环境、依赖等）
./start.sh local   # 本地开发模式，前台显示详细日志
./start.sh ngrok   # ngrok隧道模式，日志输出到文件
./start.sh tunnel  # localtunnel模式，日志输出到文件
```

### 手动启动（调试用）
```bash
# 安装依赖
pip install -r requirements.txt

# 配置环境变量
cp .env.example .env  # 然后编辑.env文件

# 前台启动（查看详细日志）
PYTHONUNBUFFERED=1 .venv/bin/python app.py

# 后台启动（生产环境）
.venv/bin/python app.py > flask.log 2>&1 &
```

## 日志查看和调试

### Flask进程与ngrok关系
**双进程架构**：
- **Flask进程**：运行在本地端口3000，处理业务逻辑，包含详细的print日志
- **ngrok进程**：创建公网隧道，只负责转发，记录连接信息

**日志类型**：
- **Flask业务日志**：请求解析、JSON处理、飞书API调用、图片生成等
- **ngrok连接日志**：格式如 `t=2025-08-28T16:24:30+0800 lvl=info msg="join connections"`

### 查看详细日志的方法

#### 方法1：使用本地开发模式（最简单）
```bash
./start.sh local   # Flask前台运行，实时显示所有详细日志
```
你将看到：
- 🔍 收到请求的完整信息
- 📋 JSON数据解析过程
- 🔑 飞书Token获取和API调用
- 📊 图片生成和上传过程
- ✅ 处理成功或❌错误信息

#### 方法2：使用隧道模式查看日志
```bash
./start.sh ngrok   # 启动ngrok隧道
tail -f flask.log  # 另开终端查看Flask日志
```

#### 方法3：使用日志监控工具
```bash
./monitor_logs.sh           # 实时查看所有日志
./monitor_logs.sh errors    # 只看错误日志
./monitor_logs.sh requests  # 只看请求日志
./monitor_logs.sh filter    # 按类型过滤日志
```

### 快速诊断问题
```bash
./diagnose.sh        # 完整系统诊断
./diagnose.sh test   # 测试核心功能
./diagnose.sh errors # 分析最近错误
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
curl -X POST http://localhost:3000/hook \\
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

### 常见问题解决

1. **看不到详细日志**：
   - 问题：只看到ngrok连接日志，看不到Flask处理日志
   - 解决：使用 `./start.sh local` 或 `./monitor_logs.sh`

2. **Flask进程问题**：
   - 进程未启动：`./diagnose.sh service`
   - 后台进程杀不掉：`pkill -f "python.*app.py"`
   - 虚拟环境问题：`rm -rf .venv && ./start.sh`

3. **权限相关错误**：
   - 403错误：飞书应用缺少权限，需要添加 `drive:file`, `im:resource` 权限
   - 404错误：attachment_id无效或文件已删除
   - 使用 `./diagnose.sh errors` 查看详细错误分析

4. **端口占用错误**：使用 `PORT=其他端口 python app.py`
5. **字体渲染问题**：确保 `assets/font.ttf` 存在
6. **MBTI底图缺失**：检查 `assets/` 目录中的PNG文件

### 调试工具
- `./diagnose.sh` - 完整系统诊断
- `./monitor_logs.sh` - 日志监控和过滤
- `tail -f flask.log` - 实时查看日志文件

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