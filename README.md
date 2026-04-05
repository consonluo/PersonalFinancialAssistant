# 家庭资产管理系统

一款支持 Mac/Web/Android/iOS 多端的家庭金融资产管理应用，帮助家庭成员集中管理所有金融资产与负债。

## 功能特性

- **家庭成员管理**：多成员、多账户、多持仓的层级管理
- **资产总览仪表盘**：总资产、净资产、今日涨跌一目了然
- **实时行情追踪**：A股/港股/美股/基金净值实时更新
- **智能分类分析**：自动识别资产类别（股票、ETF、QDII、红利基金、债基等）
- **OCR 截图导入**：通过持仓截图快速录入数据
- **负债管理**：房贷、车贷等负债录入，自动计算净资产
- **数据同步**：支持 WebDAV（坚果云）/ 云盘 API 多端同步
- **导入导出**：JSON 格式数据导入导出
- **游客模式**：内置演示数据，即刻体验
- **无需后端**：纯本地运行，数据存储在设备上

## 技术栈

| 技术 | 说明 |
|------|------|
| Flutter 3.x | 跨平台框架 |
| Riverpod | 状态管理 |
| drift (SQLite) | 本地数据库 |
| go_router | 声明式路由 |
| fl_chart | 图表可视化 |
| dio | HTTP 客户端 |
| Google ML Kit | OCR 文字识别 |

## 快速开始

```bash
# 确保 Flutter SDK 已安装
flutter --version

# 安装依赖
flutter pub get

# 运行代码生成（drift 表定义）
dart run build_runner build --delete-conflicting-outputs

# 运行应用
flutter run -d macos    # macOS
flutter run -d chrome   # Web
flutter run              # 连接的移动设备
```

## 使用流程

1. **首次启动**：选择「新建家庭」/「导入数据」/「游客体验」
2. **选择角色**：选择你是家庭中的哪个成员
3. **添加账户**：为成员添加证券账户、银行账户
4. **录入持仓**：手动添加或通过截图 OCR 批量导入
5. **查看分析**：在仪表盘和分析页查看资产分布

## 数据同步

- **WebDAV**：在设置中配置坚果云等 WebDAV 服务
- **导入导出**：在设置 → 数据管理中导出/导入 JSON 文件
- **云盘**：OneDrive/Google Drive 支持（规划中）

## 项目结构

```
lib/
├── core/          # 核心工具层（主题、常量、路由、分类引擎）
├── data/          # 数据层（数据库、API、模型、同步）
├── providers/     # Riverpod 状态管理
└── ui/            # 展示层（所有页面和组件）
```

## License

MIT
