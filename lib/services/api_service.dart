import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // 🚨 CONEXIÓN A PRODUCCIÓN SAAS
  static const String baseUrl = "https://ppservice.icu/api";

  // ==========================================================
  // 🛡️ MOTOR DE SEGURIDAD JWT (INYECTA EL TOKEN)
  // ==========================================================
  static Future<Map<String, String>> getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('token_jwt');

    return {
      "Content-Type": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
  }

  static Future<Map<String, String>> getMultipartAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('token_jwt');

    return {if (token != null) "Authorization": "Bearer $token"};
  }

  // ==========================================================
  // ⚙️ CONFIGURACIÓN GLOBAL SAAS (LOGOS, API KEYS, TICKETS)
  // ==========================================================
  static Future<Map<String, dynamic>> obtenerLlavesAPI() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/oficina/llaves-api'),
        headers: await getAuthHeaders(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['exito']) return data['llaves'] ?? {};
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  static Future<bool> guardarLlavesAPI(Map<String, dynamic> llaves) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/oficina/llaves-api'),
        headers: await getAuthHeaders(),
        body: jsonEncode({"llaves": llaves}),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<String?> subirLogoEmpresa(
    Uint8List bytes,
    String filename,
  ) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/oficina/upload-directo'),
      );
      request.headers.addAll(await getMultipartAuthHeaders());
      request.files.add(
        http.MultipartFile.fromBytes('imagen', bytes, filename: filename),
      );
      var response = await http.Response.fromStream(await request.send());

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        if (data['exito']) return data['url'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ==========================================================
  // 👑 CLUB VIP & CASHBACK DUAL
  // ==========================================================
  static Future<Map<String, dynamic>> consultarVIP(String qrHash) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/pos/vip/consultar/$qrHash'),
        headers: await getAuthHeaders(),
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
      return {'exito': false, 'error': 'Tarjeta VIP no encontrada o expirada.'};
    } catch (e) {
      return {'exito': false, 'error': 'Error de conexión con el servidor.'};
    }
  }

  static Future<Map<String, dynamic>> consultarQRVIP(String qr) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/pos/vip/consultar/$qr'),
        headers: await getAuthHeaders(),
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
      return {
        "exito": false,
        "registrado": false,
        "error": "Error de servidor",
      };
    } catch (e) {
      return {"exito": false, "error": e.toString()};
    }
  }

  static Future<Map<String, dynamic>> registrarVIP(
    String nombre,
    String email,
    String telefono,
    String qrHash,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/pos/vip/registrar'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          "nombre": nombre,
          "email": email,
          "telefono": telefono,
          "qr_hash": qrHash,
        }),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'exito': false, 'error': 'Error al registrar al cliente VIP.'};
    }
  }

  static Future<Map<String, dynamic>> traspasarVIP(
    String viejoQr,
    String nuevoQr,
    String nuevoNivel,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/pos/vip/traspasar'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          "viejo_qr": viejoQr,
          "nuevo_qr": nuevoQr,
          "nuevo_nivel": nuevoNivel,
        }),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {"exito": false, "error": e.toString()};
    }
  }

  static Future<Map<String, dynamic>> sortearVIP(String nivel) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/oficina/vip/sorteo/$nivel'),
        headers: await getAuthHeaders(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'exito': false, 'error': 'Error al girar la ruleta de sorteos.'};
    }
  }

  static Future<Map<String, dynamic>> obtenerConfiguracionVIP() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/oficina/configuracion'),
        headers: await getAuthHeaders(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['exito']) return data['config'];
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  static Future<bool> guardarConfiguracionVIP(
    double bono,
    double plEfe,
    double plTar,
    double orEfe,
    double orTar,
    double tiEfe,
    double tiTar,
  ) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/oficina/configuracion'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          "bono_bienvenida": bono,
          "pl_efe": plEfe,
          "pl_tar": plTar,
          "or_efe": orEfe,
          "or_tar": orTar,
          "ti_efe": tiEfe,
          "ti_tar": tiTar,
        }),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>> obtenerClientesVIP() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/oficina/clientes'),
        headers: await getAuthHeaders(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['exito']) return data['clientes'];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> eliminarClienteVIP(int idCliente) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/oficina/clientes/$idCliente'),
        headers: await getAuthHeaders(),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ==========================================================
  // 📦 INVENTARIO Y POS
  // ==========================================================
  static Future<bool> preRegistrarProducto({
    required String sku,
    required String nombreInterno,
    required double precio,
    required List<Map<String, dynamic>> tallas,
    required int totalPiezas,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/pos/pre-registro'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          "sku": sku,
          "nombre_interno": nombreInterno,
          "precio": precio,
          "tallas": tallas,
          "stock_total": totalPiezas,
        }),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>> obtenerInventario() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/bodega/inventario'),
        headers: await getAuthHeaders(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['exito'] == true) return data['productos'];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ==========================================================
  // 💼 CONTABILIDAD Y CORTES
  // ==========================================================
  static Future<bool> guardarCorteCaja(
    String cajero,
    double ventasEfectivo,
    double ventasTarjeta,
    double ventasTransferencia,
    double gastosTotales, {
    Map<String, dynamic>? detalles,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/pos/corte-caja'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          "cajero": cajero,
          "ventas_efectivo": ventasEfectivo,
          "ventas_tarjeta": ventasTarjeta,
          "ventas_transferencia": ventasTransferencia,
          "gastos_totales": gastosTotales,
          "detalles": detalles ?? {},
        }),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>> obtenerHistorialCortes() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/oficina/cortes-caja'),
        headers: await getAuthHeaders(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['exito']) return data['cortes'];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<dynamic>> obtenerVentasEnVivo({
    String? fechaInicio,
    String? fechaFin,
  }) async {
    try {
      String urlStr = '$baseUrl/oficina/ventas-en-vivo';
      if (fechaInicio != null && fechaFin != null) {
        urlStr += '?fechaInicio=$fechaInicio&fechaFin=$fechaFin';
      }
      final res = await http.get(
        Uri.parse(urlStr),
        headers: await getAuthHeaders(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['exito']) return data['ventas'];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> procesarCambioFisico(
    List<Map<String, dynamic>> entran,
    List<Map<String, dynamic>> salen,
    String motivo,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/pos/cambio'),
        headers: await getAuthHeaders(),
        body: jsonEncode({"entran": entran, "salen": salen, "motivo": motivo}),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ==========================================================
  // 🤖 INTELIGENCIA ARTIFICIAL
  // ==========================================================
  static Future<String> preguntarALaIA(String pregunta) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/oficina/ia/copiloto'),
        headers: await getAuthHeaders(),
        body: jsonEncode({"pregunta": pregunta}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['respuesta'] ?? "Sin respuesta.";
      }
      return "Error de conexión.";
    } catch (e) {
      return "Fallo al contactar servidor.";
    }
  }

  // ==========================================================
  // 👑 GESTIÓN DE OFICINA Y PRODUCTOS
  // ==========================================================
  static Future<bool> eliminarProducto(int idProducto) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/oficina/productos/$idProducto'),
        headers: await getAuthHeaders(),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> actualizarOferta(
    int idProducto,
    bool enRebaja,
    double precioRebaja,
  ) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/oficina/productos/$idProducto/oferta'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          "en_rebaja": enRebaja ? 1 : 0,
          "precio_rebaja": precioRebaja,
        }),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> resurtirProducto(
    int idProducto,
    List<Map<String, dynamic>> tallasActualizadas,
    int nuevoStockTotal,
  ) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/oficina/productos/$idProducto/resurtir'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          "tallas": tallasActualizadas,
          "stock_bodega": nuevoStockTotal,
        }),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ==========================================================
  // 📊 GASTOS AUTOMÁTICOS Y CARGA MASIVA EXCEL
  // ==========================================================
  static Future<List<dynamic>> obtenerGastosFijos() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/oficina/gastos-fijos'),
        headers: await getAuthHeaders(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['exito']) return data['gastos'];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> agregarGastoFijo(String concepto, double monto) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/oficina/gastos-fijos'),
        headers: await getAuthHeaders(),
        body: jsonEncode({"concepto": concepto, "monto": monto}),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> eliminarGastoFijo(int idGasto) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/oficina/gastos-fijos/$idGasto'),
        headers: await getAuthHeaders(),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> cargaMasivaProductos(
    List<Map<String, dynamic>> productos,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/oficina/carga-masiva'),
        headers: await getAuthHeaders(),
        body: jsonEncode({"productos": productos}),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ==========================================================
  // 👥 VENDEDORES Y CUPONES
  // ==========================================================
  static Future<bool> liquidarComisiones(
    String codigo,
    int piezas,
    double ventasTotales,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/oficina/vendedores/pagar'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          "codigo_creador": codigo,
          "piezas": piezas,
          "ventas_totales": ventasTotales,
        }),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>> obtenerVendedores() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/oficina/vendedores'),
        headers: await getAuthHeaders(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['exito']) return data['vendedores'];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> registrarVendedor(
    String nombre,
    String codigo,
    double comision,
    double descuento,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/oficina/vendedores'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          "nombre": nombre,
          "codigo_creador": codigo,
          "comision_porcentaje": comision,
          "descuento_cliente": descuento,
        }),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> eliminarVendedor(int idVendedor) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/oficina/vendedores/$idVendedor'),
        headers: await getAuthHeaders(),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> validarCupon(String codigo) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/cupones/validar/$codigo'),
        headers: await getAuthHeaders(),
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
      return {'valido': false};
    } catch (e) {
      return {'valido': false};
    }
  }

  // ==========================================================
  // 🔐 SEGURIDAD
  // ==========================================================
  static Future<bool> verificarClaveAdmin(String password) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/oficina/verificar-admin'),
        headers: await getAuthHeaders(),
        body: jsonEncode({"password": password}),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> cambiarClaves(
    String clavePos,
    String claveOficina,
  ) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/oficina/cambiar-claves'),
        headers: await getAuthHeaders(),
        body: jsonEncode({"clavePos": clavePos, "claveOficina": claveOficina}),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ==========================================================
  // 🏢 GESTIÓN DE SUCURSALES (SaaS)
  // ==========================================================
  static Future<Map<String, dynamic>> crearSucursal(
    String nombre,
    String direccion,
    String usuarioCaja,
    String passwordCaja,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/oficina/sucursales/nueva'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          "nombre_sucursal": nombre,
          "direccion": direccion,
          "pos_usuario": usuarioCaja,
          "pos_password": passwordCaja,
        }),
      );

      // Regresamos el JSON directo porque el servidor nos manda mensajes de error detallados (Ej: Límite de plan alcanzado)
      return jsonDecode(res.body);
    } catch (e) {
      return {'exito': false, 'error': 'Fallo de conexión con el servidor.'};
    }
  }
}
