import 'dart:async';

import 'package:scho_navi/domain/entities/favorite_item.dart';
import 'package:scho_navi/domain/repositories/favorite_repository.dart';

/// 测试用内存版 [FavoriteRepository]：同步维护收藏列表并通过 stream 通知
/// 订阅者。用于 widget 测试中覆盖 [favoriteRepositoryProvider]，避免真实
/// HTTP 调用。
class FakeFavoriteRepository implements FavoriteRepository {
  final _items = <String, FavoriteItem>{};
  final _controller = StreamController<List<FavoriteItem>>.broadcast();

  @override
  List<FavoriteItem> list() => _items.values.toList();

  @override
  Stream<List<FavoriteItem>> watch() => _controller.stream;

  @override
  bool isFavorite(String professorId) => _items.containsKey(professorId);

  @override
  Future<void> add(FavoriteItem item) async {
    _items[item.professorId] = item;
    _controller.add(list());
  }

  @override
  Future<void> remove(String professorId) async {
    _items.remove(professorId);
    _controller.add(list());
  }

  @override
  Future<bool> toggle(FavoriteItem item) async {
    if (_items.containsKey(item.professorId)) {
      await remove(item.professorId);
      return false;
    }
    await add(item);
    return true;
  }

  void dispose() => _controller.close();
}
