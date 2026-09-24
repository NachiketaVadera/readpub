import '../resource/resource.dart';
import 'model.dart';

/// A normalized publication with storage-independent resource access.
abstract interface class Publication {
  /// The normalized descriptive metadata.
  Metadata get metadata;

  /// The publication-level links.
  List<Link> get links;

  /// The primary reading sequence.
  List<Link> get readingOrder;

  /// The resources outside the primary reading sequence.
  List<Link> get resources;

  /// The nested table of contents.
  List<Link> get tableOfContents;

  /// The publication landmarks.
  List<Link> get landmarks;

  /// The page navigation list.
  List<Link> get pageList;

  /// Other role-based collections.
  List<PublicationCollection> get otherCollections;

  /// Returns a lazy readable resource for a publication link.
  Resource resource(Link link);

  /// Finds a manifest resource by its encoded href.
  Resource? get(String href);

  /// Releases owned storage and invalidates subsequent reads.
  Future<void> close();
}
