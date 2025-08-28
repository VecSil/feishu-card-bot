# feishu-card-bot
feishu-card-bot

## 飞书部署所需：
1. 下载python3.12及以上的版本并安装
2. 确认安装好ngrok服务器，按照官网操作下载对应版本，并按指南配置好自己的token
3. 在本文件夹下运行./start.sh 开启服务器，选择选项1（ngrok隧道）无需翻墙即可使用，等到终端打印出“ngrok隧道已启动！”后，复制终端里打印出的webhook地址：（搜索 “url=“ 字段，复制后面的网址，形如https://de490fc954b7.ngrok-free.app这样的
4. 在飞书新建多维表格形式的问卷
5. 添加飞书多维表格自动化：当有人新提交了一个表项（提交人不为空），则发送一个http请求，【请求方法】为post，【请求地址】为上面第3步复制的网址后面加/hook （总体为https://de490fc954b7.ngrok-free.app/hook） 注意！若服务器重启了一遍，这个随机地址会换，记得重新复制并在飞书自动化的【请求地址】里更新。
6. 在飞书后台：https://open.feishu.cn/app 里创建一个应用，名字叫问卷机器人（注意登录的账号是问卷所在账号），在【应用能力】里添加一个默认的机器人能力，然后在【权限管理】里批量导入权限：
{
  "scopes": {
    "tenant": [
      "base:record:update",
      "bitable:app",
      "bitable:app:readonly",
      "drive:file",
      "drive:file.like:readonly",
      "drive:file.meta.sec_label.read_only",
      "drive:file:download",
      "drive:file:readonly",
      "drive:file:upload",
      "drive:file:view_record:readonly",
      "im:message:send_as_bot",
      "im:resource"
    ],
    "user": [
      "bitable:app",
      "bitable:app:readonly",
      "drive:file",
      "drive:file.like:readonly",
      "drive:file.meta.sec_label.read_only",
      "drive:file:download",
      "drive:file:readonly",
      "drive:file:upload",
      "drive:file:view_record:readonly"
    ]
  }
}
开通好之后一定记得要发布这个版本！
7. 复制问卷机器人的【凭证与基础信息】的appid和app secret，填写进本文件夹的.env 里面的 FEISHU_APP_ID 和 FEISHU_APP_SECRET 里
8. 在飞书开放平台里搜索“上传图片”，这个页面里右侧会自动弹出你刚创建的的问卷机器人，获取token复制它的请求头里的Bearer字段
9. 回到飞书问卷填写【请求头】
第一项填写  Content-Type ：application/json
第二项填写 Authorization：Bearer （后面加刚刚复制的Bearer字段
【请求体】填写：
{
  "nickname": "  ",
  "gender": "  ",
  "profession": "  ",
  "interests": "  ",
  "mbti": "  ",
  "introduction": "  ",
  "wechatQrAttachmentId": "  "
}
每个空引号里的字引用第一步里新增的记录对应的字段（右上角小加号可以选）
【响应体】填写：
{
    "image_url":"",
    "image_key":""
}

10. 添加自动化流程第三步，发送飞书消息，接收方选择第一步的提交人，标题随便，内容填写【请查收你的个人名片： + 第二步发送请求的返回值--body--image_url】

11. 保存并启用自动化工作流。

12. 每次运行时，在本文件夹下打开终端，输入./start.sh, 选择1隧道，开启成功后把url输入给飞书自动化流程post的url，然后