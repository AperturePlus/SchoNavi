const forkProfessorUnavailableLabel = '导师信息不可用';

/// 一次 fork 追问的元数据。
///
/// 仅存展示与恢复入口所需信息；对话内容由 [ChatRepository.loadHistory]
/// 按 forkId 按需拉取，不塞进本实体。
class ForkRef {
  const ForkRef({
    required this.forkId,
    required this.mainSessionId,
    required this.professorId,
    required this.professorName,
    required this.university,
    required this.college,
    required this.createdAt,
  });

  /// 恢复对话用，跳 /chat?fork&fid=$forkId。
  final String forkId;

  /// 归属主 session（树形挂载用）。
  final String mainSessionId;

  final String professorId;

  /// 头像姓氏 + 姓名展示用。
  final String professorName;

  final String university;

  /// 形如「计算机系」，与 university 组合「清华大学 · 计算机系」。
  final String? college;

  final DateTime createdAt;

  /// 姓氏首字（头像展示）。中文取首字，非中文取首字母大写。
  String get avatarLabel {
    if (professorName == forkProfessorUnavailableLabel) return '?';
    if (professorName.isEmpty) return '?';
    return professorName.substring(0, 1);
  }
}
