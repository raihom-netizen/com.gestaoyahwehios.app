/// Serviços que podem falhar sem derrubar o resto da app.
enum DegradedService {
  storage,
  push,
  publicSite,
  firestore,
  functions,
}
