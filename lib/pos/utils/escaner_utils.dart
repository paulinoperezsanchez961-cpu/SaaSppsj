import 'dart:convert';
import 'package:flutter/material.dart';

// ============================================================================
// 🧠 SANADORES GLOBALES (RAYOS X PARA EL ESCÁNER Y BD SAAS)
// ============================================================================

/// Repara las URLs de las imágenes que vienen de la base de datos
String sanearImagen(dynamic dbPath) {
  if (dbPath == null || dbPath.toString().trim().isEmpty) {
    // 🚨 SAAS: Imagen de respaldo genérica sin marca
    return "https://via.placeholder.com/200?text=Sin+Imagen";
  }
  String path = dbPath.toString().trim();
  if (path.startsWith('http')) {
    return path;
  }

  String cleanPath = path
      .replaceAll('/api/uploads/', '/uploads/')
      .replaceAll('/api/media/', '/uploads/');

  if (cleanPath.contains('?f=')) {
    cleanPath = '/uploads/${cleanPath.split('?f=')[1]}';
  }

  if (!cleanPath.startsWith('/')) {
    cleanPath = '/$cleanPath';
  }

  // 🚨 SAAS: Apuntamos al dominio central de tu sistema
  return 'https://ppservice.icu$cleanPath';
}

/// Limpia cualquier texto de acentos, espacios y caracteres raros
String sanitizarAlfanumerico(String text) {
  if (text.isEmpty) {
    return "";
  }
  String t = text.toUpperCase();
  t = t
      .replaceAll('Á', 'A')
      .replaceAll('É', 'E')
      .replaceAll('Í', 'I')
      .replaceAll('Ó', 'O')
      .replaceAll('Ú', 'U');
  return t.replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

/// Convierte el texto JSON de la Base de Datos a una lista manejable de Tallas Multi-Sucursal
List<Map<String, dynamic>> parsearTallasBD(dynamic tallasRawData) {
  List<dynamic> tallasRaw = [];
  if (tallasRawData != null) {
    if (tallasRawData is String) {
      try {
        tallasRaw = jsonDecode(tallasRawData);
      } catch (e) {
        debugPrint('Aviso: $e');
      }
    } else if (tallasRawData is List) {
      tallasRaw = tallasRawData;
    }
  }

  return tallasRaw.map((e) {
    if (e is Map) {
      return {
        'talla': (e['talla'] ?? e['nombre'] ?? 'ÚNICA')
            .toString()
            .trim()
            .toUpperCase(),
        'cantidad':
            int.tryParse(
              e['cantidad']?.toString() ?? e['stock']?.toString() ?? '0',
            ) ??
            0,
        // 🚨 SAAS: Añadimos compatibilidad nativa para separar stock por sucursal
        'sucursal': (e['sucursal'] ?? 'BODEGA CENTRAL')
            .toString()
            .toUpperCase(),
      };
    }
    return {
      'talla': e.toString().trim().toUpperCase(),
      'cantidad': 1,
      'sucursal': 'BODEGA CENTRAL',
    };
  }).toList();
}

/// Lee la pistola de código de barras o cámara y separa el SKU de la Talla
Map<String, String> decodificarEscaneo(String raw) {
  String limpio = raw.trim().toUpperCase();
  String sku = limpio, talla = "UNICA";

  if (limpio.contains('TALLA')) {
    var parts = limpio.split('TALLA');
    sku = sanitizarAlfanumerico(parts[0]);
    if (parts.length > 1) {
      talla = sanitizarAlfanumerico(parts[1]);
    }
  } else if (limpio.contains('SKU') && limpio.contains('TALLA')) {
    final sMatch = RegExp(r'SKU[^\w\d]+([A-Z0-9\-\/]+)').firstMatch(limpio);
    if (sMatch != null) {
      sku = sanitizarAlfanumerico(sMatch.group(1)!);
    }

    final tMatch = RegExp(r'TALLA[^\w\d]+([A-Z0-9\-\/]+)').firstMatch(limpio);
    if (tMatch != null) {
      talla = sanitizarAlfanumerico(tMatch.group(1)!);
    }
  } else {
    sku = sanitizarAlfanumerico(limpio);
  }

  if (talla.isEmpty) {
    talla = "UNICA";
  }

  return {'sku': sku, 'talla': talla};
}
