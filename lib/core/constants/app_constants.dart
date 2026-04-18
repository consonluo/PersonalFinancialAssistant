import 'package:flutter/material.dart';

/// 应用常量定义
class AppConstants {
  AppConstants._();

  static const String appName = '家庭资产管理';
  static const String appTagline = '家庭资产，一目了然';
  static const String demoFamilyName = '示范家庭';
  static const String appVersion = '1.0.0';

  // 缓存 TTL（秒）
  static const int marketCacheTTLTrading = 300; // 交易时段5分钟
  static const int marketCacheTTLNonTrading = 3600; // 非交易时段1小时
  static const int marketCacheTTLWeekend = 86400; // 周末1天

  // 数据文件
  static const String dataFileExtension = '.json';
  static const String demoDataFile = 'assets/demo/demo_family.json';

  // 同步
  static const int syncConflictTimeoutSeconds = 30;
  static const String syncRemoteDir = '/FamilyFinance/';

  // 预设 WebDAV 配置（通过 --dart-define 编译时注入）
  static const String webdavUrl = String.fromEnvironment('WEBDAV_URL', defaultValue: 'https://dav.jianguoyun.com/dav/');
  static const String webdavUser = String.fromEnvironment('WEBDAV_USER', defaultValue: '');
  static const String webdavPass = String.fromEnvironment('WEBDAV_PASS', defaultValue: '');
  static const String webdavBaseDir = '/FamilyFinance/';
}

/// 资产类型枚举 — 按金融行业惯例分类
enum AssetType {
  // ---- 股票 ----
  aStock('A股', 'A'),
  hkStock('港股', 'HK'),
  usStock('美股', 'US'),
  // ---- 权益型基金 ----
  indexETF('指数ETF', 'ETF'),
  qdii('QDII基金', 'QDII'),
  dividendFund('红利基金', 'DIV'),
  nasdaqETF('纳指ETF', 'NDQ'),
  mixedFund('混合基金', 'MIX'),
  // ---- 固收类基金 ----
  bondFund('债券基金', 'BOND'),
  moneyFund('货币基金', 'MMF'),
  // ---- 银行理财 ----
  wealth('银行理财', 'WLT'),
  structuredDeposit('结构性存款', 'SD'),
  // ---- 存款 ----
  deposit('活期存款', 'DEP'),
  fixedDeposit('定期存款', 'FD'),
  largeDeposit('大额存单', 'LD'),
  noticeDeposit('通知存款', 'ND'),
  // ---- 低风险投资 ----
  treasuryRepo('国债逆回购', 'TR'),
  // ---- 贵金属 ----
  gold('黄金', 'AU'),
  // ---- 保险 ----
  insurance('储蓄险/年金', 'INS'),
  // ---- 固定资产 ----
  realEstate('房产', 'RE'),
  vehicle('车辆', 'VEH'),
  // ---- 其他 ----
  other('其他', 'OTH');

  const AssetType(this.label, this.code);
  final String label;
  final String code;
}

/// 账户类型枚举
enum AccountType {
  securities('证券账户'),
  bank('银行账户'),
  fund('基金账户'),
  insurance('保险账户');

  const AccountType(this.label);
  final String label;
}

/// 账户子类型枚举
enum AccountSubType {
  stock('股票账户'),
  fund('基金账户'),
  futures('期货账户'),
  checking('活期存款'),
  savings('定期存款'),
  wealthMgmt('理财产品'),
  creditCard('信用卡'),
  thirdParty('第三方平台');  // 蚂蚁财富/天天基金等

  const AccountSubType(this.label);
  final String label;
}

/// 负债类型枚举 — 覆盖中国家庭常见负债
enum LiabilityType {
  // ---- 住房类 ----
  mortgage('商业房贷'),
  housingFund('公积金房贷'),
  combinedLoan('组合贷'),
  // ---- 消费类 ----
  carLoan('车贷'),
  renovationLoan('装修贷'),
  consumerLoan('消费贷'),      // 花呗/借呗/白条等
  creditCard('信用卡'),
  installment('分期付款'),      // 手机/家电等大额分期
  // ---- 经营类 ----
  businessLoan('经营贷'),
  // ---- 其他 ----
  personalLoan('亲友借款'),
  loan('其他借款'),
  other('其他');

  const LiabilityType(this.label);
  final String label;
}

/// 固定资产类型枚举
enum FixedAssetType {
  realEstate('房产', Icons.home),
  vehicle('车辆', Icons.directions_car),
  gold('黄金/贵金属', Icons.diamond),
  insurance('储蓄保险', Icons.health_and_safety),
  collectible('收藏品/艺术品', Icons.palette),
  equity('股权/合伙', Icons.business_center),
  other('其他', Icons.category);

  const FixedAssetType(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// 同步方式枚举
enum SyncType {
  none('未配置'),
  webdav('WebDAV');

  const SyncType(this.label);
  final String label;
}

/// 家庭成员角色枚举
enum FamilyRole {
  owner('户主'),
  spouse('配偶'),
  child('子女'),
  parent('父母'),
  other('其他');

  const FamilyRole(this.label);
  final String label;
}

/// 定投频率
enum InvestFrequency {
  daily('每日'),
  weekly('每周'),
  biweekly('每两周'),
  monthly('每月');

  const InvestFrequency(this.label);
  final String label;
}
