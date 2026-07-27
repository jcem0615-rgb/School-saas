/// A college degree program/course (e.g. "BS Computer Science"). Only
/// meaningful for the College division -- Elementary and High School
/// students never reference this. Managed by Director/Admin as
/// institutional configuration, the same way Teacher Assignment is.
class Program {
  final String id;
  final String name;
  final String code;
  final String department;

  const Program({
    required this.id,
    required this.name,
    required this.code,
    required this.department,
  });
}
