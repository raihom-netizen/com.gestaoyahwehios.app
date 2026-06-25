import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/marketing_storage_layout.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/master_admin_firestore.dart';

/// Leituras Firestore do site de divulgação e config global de downloads.
///
/// Paths canónicos:
/// - `app_public/institutional_gallery` — galeria CMS
/// - `app_public/marketing_clientes` — igrejas em destaque
/// - `app_public/site` — hero vídeo/textos
/// - `config/appDownloads` — links Play Store / TestFlight
abstract final class MarketingPublicSiteService {
  MarketingPublicSiteService._();

  static DocumentReference<Map<String, dynamic>> get _galleryDoc =>
      firebaseDefaultFirestore
          .collection(MarketingStorageLayout.firestoreCollection)
          .doc(MarketingStorageLayout.firestoreGalleryDocId);

  static DocumentReference<Map<String, dynamic>> get _siteDoc =>
      firebaseDefaultFirestore
          .collection(MarketingStorageLayout.firestoreCollection)
          .doc(MarketingStorageLayout.firestoreSiteDocId);

  static DocumentReference<Map<String, dynamic>> get _marketingClientesDoc =>
      firebaseDefaultFirestore
          .collection(MarketingStorageLayout.firestoreCollection)
          .doc(MarketingStorageLayout.firestoreMarketingClientesDocId);

  static DocumentReference<Map<String, dynamic>> get marketingClientesDocRef =>
      _marketingClientesDoc;

  static DocumentReference<Map<String, dynamic>> get galleryDocRef => _galleryDoc;

  static DocumentReference<Map<String, dynamic>> get siteDocRef => _siteDoc;

  static DocumentReference<Map<String, dynamic>> get appDownloadsDoc =>
      firebaseDefaultFirestore.doc(MarketingStorageLayout.appDownloadsConfigPath);

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchGallery() =>
      FirestoreStreamUtils.documentWatchSafe(_galleryDoc);

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchSite() =>
      FirestoreStreamUtils.documentWatchSafe(_siteDoc);

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchMarketingClientes() =>
      FirestoreStreamUtils.documentWatchSafe(_marketingClientesDoc);

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchAppDownloads() =>
      FirestoreStreamUtils.documentWatchBootstrap(appDownloadsDoc);

  /// Painel master — leitura resiliente da galeria CMS.
  static Future<DocumentSnapshot<Map<String, dynamic>>> readGalleryOnce() =>
      MasterAdminFirestore.document(
        _galleryDoc,
        cacheKey: 'app_public_institutional_gallery',
      );

  static Future<DocumentSnapshot<Map<String, dynamic>>> readSiteOnce() =>
      MasterAdminFirestore.document(
        _siteDoc,
        cacheKey: 'app_public_site',
      );
}
