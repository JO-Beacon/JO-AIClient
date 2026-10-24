/// 本应用自有数据库文件名。与上游 Kelivo 的 `kelivo.db` 区分，避免把两套
/// schema 不同的库混为一谈。
abstract final class DatabaseNames {
  static const current = 'jo_aiclient.db';
  static const legacy = 'kelivo.db';
  static const familySuffixes = ['', '-wal', '-shm', '-journal'];
  static const conflictDirectory = 'database-conflicts';

  static bool isFamilyMember(String name) {
    for (final base in [current, legacy]) {
      for (final suffix in familySuffixes) {
        if (name == '$base$suffix') return true;
      }
    }
    return false;
  }

  static String familyLabel(String base) => base;

  static bool belongsTo(String name, String base) {
    return familySuffixes.any((suffix) => name == '$base$suffix');
  }
}
