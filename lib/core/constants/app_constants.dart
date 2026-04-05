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

  // 预设 WebDAV 配置（坚果云公共存储后台）
  static const String webdavUrl = 'https://dav.jianguoyun.com/dav/';
  static const String webdavUser = 'luo.gz@qq.com';
  static const String webdavPass = 'a5fh7wv56g4mg6jc';
  static const String webdavBaseDir = '/FamilyFinance/';
}

/// 资产类型枚举
enum AssetType {
  aStock('A股', 'A'),
  hkStock('港股', 'HK'),
  usStock('美股', 'US'),
  indexETF('指数ETF', 'ETF'),
  qdii('QDII基金', 'QDII'),
  dividendFund('红利基金', 'DIV'),
  nasdaqETF('纳指ETF', 'NDQ'),
  bondFund('债券基金', 'BOND'),
  moneyFund('货币基金', 'MMF'),
  mixedFund('混合基金', 'MIX'),
  wealth('银行理财', 'WLT'),
  deposit('存款', 'DEP'),
  realEstate('房产', 'RE'),
  vehicle('车辆', 'VEH'),
  other('其他', 'OTH');

  const AssetType(this.label, this.code);
  final String label;
  final String code;
}

/// 账户类型枚举
enum AccountType {
  securities('证券账户'),
  bank('银行账户');

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
  creditCard('信用卡');

  const AccountSubType(this.label);
  final String label;
}

/// 负债类型枚举
enum LiabilityType {
  mortgage('房贷'),
  carLoan('车贷'),
  creditCard('信用卡'),
  loan('借款'),
  other('其他');

  const LiabilityType(this.label);
  final String label;
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
