import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:gestao_yahweh/core/firestore_cursor_pagination.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';

/// Controlador reutilizável — carrega 20 docs e anexa mais 20 no scroll.
class LazyFirestoreListController<T> extends ChangeNotifier {
  LazyFirestoreListController({
    required this.baseQuery,
    required this.mapDocument,
    this.pageSize = YahwehPerformanceV4.defaultPageSize,
  });

  final Query<Map<String, dynamic>> baseQuery;
  final T Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) mapDocument;
  final int pageSize;

  final List<T> items = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool hasMore = true;
  bool loading = false;
  bool loadingMore = false;
  Object? lastError;

  Future<void> loadInitial({bool clear = true}) async {
    if (loading) return;
    loading = true;
    lastError = null;
    if (clear) {
      items.clear();
      _cursor = null;
      hasMore = true;
    }
    notifyListeners();
    try {
      final page = await FirestoreCursorPagination.fetchDocumentsPage(
        baseQuery: baseQuery,
        startAfter: null,
        pageSize: pageSize,
      );
      items.addAll(page.items.map(mapDocument));
      _cursor = page.lastDocument;
      hasMore = page.hasMore;
    } catch (e) {
      lastError = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (loading || loadingMore || !hasMore || _cursor == null) return;
    loadingMore = true;
    notifyListeners();
    try {
      final page = await FirestoreCursorPagination.fetchDocumentsPage(
        baseQuery: baseQuery,
        startAfter: _cursor,
        pageSize: pageSize,
      );
      items.addAll(page.items.map(mapDocument));
      _cursor = page.lastDocument;
      hasMore = page.hasMore;
    } catch (e) {
      lastError = e;
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  void reset() {
    items.clear();
    _cursor = null;
    hasMore = true;
    lastError = null;
    notifyListeners();
  }
}

/// Dispara [onLoadMore] quando o scroll chega perto do fim (~85%).
class LazyLoadScrollWrapper extends StatelessWidget {
  const LazyLoadScrollWrapper({
    super.key,
    required this.controller,
    required this.onLoadMore,
    required this.child,
    this.threshold = 0.85,
  });

  final LazyFirestoreListController<dynamic> controller;
  final VoidCallback onLoadMore;
  final Widget child;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is! ScrollUpdateNotification && n is! ScrollEndNotification) {
          return false;
        }
        final m = n.metrics;
        if (m.maxScrollExtent <= 0) return false;
        if (m.pixels >= m.maxScrollExtent * threshold) {
          if (controller.hasMore && !controller.loadingMore) {
            onLoadMore();
          }
        }
        return false;
      },
      child: child,
    );
  }
}
