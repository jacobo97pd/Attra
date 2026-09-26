import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../domain/travel_destination_resolver.dart';

/// Tercera fuente: el callable `resolveTravelDestination` (Places en servidor,
/// con caché de 90 días y tope diario por usuario). Es la única que funciona en
/// web cuando el dataset no tiene centro para la ciudad.
///
/// La instancia de Functions se pide AL LLAMAR, no al construir: la cadena se
/// crea con la sesión y casi siempre acierta antes (dataset), así que en tests
/// y sin Firebase inicializado esto no se toca nunca.
class CallableTravelDestinationResolver implements TravelDestinationResolver {
  CallableTravelDestinationResolver({FirebaseFunctions Function()? functions})
      : _functions = functions ??
            (() => FirebaseFunctions.instanceFor(region: 'europe-west1'));

  final FirebaseFunctions Function() _functions;

  @override
  Future<TravelDestination?> resolve({
    required String iso2,
    required String city,
    String countryName = '',
  }) async {
    try {
      final HttpsCallableResult<dynamic> result = await _functions()
          .httpsCallable('resolveTravelDestination')
          .call<dynamic>(<String, dynamic>{'iso2': iso2, 'city': city});
      final Object? data = result.data;
      if (data is! Map) return null;
      final Object? lat = data['lat'];
      final Object? lng = data['lng'];
      if (lat is! num || lng is! num) return null;
      if (!TravelDestination.isValid(lat.toDouble(), lng.toDouble())) {
        return null;
      }
      return TravelDestination(
        latitude: lat.toDouble(),
        longitude: lng.toDouble(),
        source: TravelGeoSource.server,
      );
    } catch (error) {
      // Función sin desplegar, sin red, tope diario agotado o sin clave de
      // Places: el viaje se guarda a nivel de país.
      debugPrint('[geo] el servidor no pudo situar el destino: $error');
      return null;
    }
  }
}
