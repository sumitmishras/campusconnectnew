/// One page of results from a repository.
///
/// Repositories never return bare lists: the caller has to know whether it
/// reached the end, and where the next page starts. Bundling the three
/// together means an infinite-scroll list cannot drift out of step with the
/// query that produced it.
class PageResult<T> {
  final List<T> items;

  /// False once the backend has nothing left to give for this query.
  final bool hasMore;

  /// Offset to pass to the next `fetch` call. Always
  /// `previousOffset + items.length`, so a caller can loop without tracking
  /// page sizes itself.
  final int nextOffset;

  const PageResult({
    required this.items,
    required this.hasMore,
    required this.nextOffset,
  });
}
