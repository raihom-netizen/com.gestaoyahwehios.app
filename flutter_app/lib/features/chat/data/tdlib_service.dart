/// Export condicional — Web usa stub; mobile/desktop usam FFI (Isolate no libtdjson).
library;

export 'tdlib_service_stub.dart'
    if (dart.library.io) 'tdlib_service_io.dart';
