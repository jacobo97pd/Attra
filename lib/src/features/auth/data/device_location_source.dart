import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/location_refresh_policy.dart';

/// Acceso al GPS del dispositivo. Es una interfaz porque Geolocator es un canal
/// nativo: en `flutter test` no existe, así que TODA la decisión vive en
/// [LocationRefreshPolicy] y aquí solo queda la traducción al plugin (la única
/// parte que no se puede cubrir con pruebas).
abstract class DeviceLocationSource {
  /// Estado actual del permiso SIN abrir ningún diálogo.
  Future<LocationAuthorization> authorization();

  /// Abre el diálogo del sistema. Solo se llama tras un gesto explícito.
  Future<LocationAuthorization> requestAuthorization();

  /// Última posición que YA tiene el sistema. Barata: no despierta el GPS ni
  /// enciende el indicador de localización de iOS.
  Future<LocationFix?> lastKnownFix();

  /// Fix activo (precisión baja: para el feed sobra con la ciudad).
  Future<LocationFix?> currentFix({Duration timeout});
}

class GeolocatorLocationSource implements DeviceLocationSource {
  const GeolocatorLocationSource();

  @override
  Future<LocationAuthorization> authorization() async {
    try {
      // El servicio apagado manda sobre el permiso: con la localización del
      // dispositivo desactivada, `checkPermission` puede devolver "concedido" y
      // luego no llega ninguna posición.
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationAuthorization.serviceDisabled;
      }
      return _map(await Geolocator.checkPermission());
    } catch (_) {
      return LocationAuthorization.unknown;
    }
  }

  @override
  Future<LocationAuthorization> requestAuthorization() async {
    try {
      return _map(await Geolocator.requestPermission());
    } catch (_) {
      return LocationAuthorization.unknown;
    }
  }

  @override
  Future<LocationFix?> lastKnownFix() async {
    // No soportado en web.
    if (kIsWeb) return null;
    try {
      final Position? pos = await Geolocator.getLastKnownPosition();
      if (pos == null) return null;
      return LocationFix(
        latitude: pos.latitude,
        longitude: pos.longitude,
        timestamp: pos.timestamp,
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<LocationFix?> currentFix({
    Duration timeout = LocationRefreshPolicy.fixTimeout,
  }) async {
    try {
      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      ).timeout(timeout);
      return LocationFix(
        latitude: pos.latitude,
        longitude: pos.longitude,
        timestamp: pos.timestamp,
      );
    } catch (_) {
      // Sin fix: el feed cae al filtro por país (FeedFilter salta la regla de
      // radio si falta alguno de los dos lados).
      return null;
    }
  }

  static LocationAuthorization _map(LocationPermission perm) {
    switch (perm) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationAuthorization.granted;
      case LocationPermission.denied:
        return LocationAuthorization.denied;
      case LocationPermission.deniedForever:
        return LocationAuthorization.deniedForever;
      case LocationPermission.unableToDetermine:
        return LocationAuthorization.unknown;
    }
  }
}
