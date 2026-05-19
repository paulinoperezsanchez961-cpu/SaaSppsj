import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // 🚨 CONEXIÓN A PRODUCCIÓN SAAS
  static const String baseUrl = "https://ppservice.icu/api";

  // 🚨 CALLBACK GLOBAL: Se disparará desde main.dart para expulsar al usuario a la pantalla de Login
  static VoidCallback? onTokenExpirado;

  // ==========================================================
  // 🛡️ MOTOR DE SEGURIDAD JWT E INTERCEPTORES
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

  // 🚨 VIGILANTE: Borra la sesión si el servidor rechaza el Token
  static Future<void> _verificarTokenExpirado(http.Response res) async {
    if (res.statusCode == 401 || res.statusCode == 403) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token_jwt');
      await prefs.remove('rol_usuario');
      if (onTokenExpirado != null) {
        onTokenExpirado!();
      }
    }
  }

  // ==========================================================
  // 🔑 AUTENTICACIÓN (LOGIN) SAAS
  // ==========================================================
  static Future<Map<String, dynamic>> login(
    String usuario,
    String password,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"usuario": usuario, "password": password}),
      );

      final data = jsonDecode(res.body);

      if (data['exito'] == true && data['token'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token_jwt', data['token']);
        await prefs.setString(
          'rol_usuario',
          data['rol'] ?? 'cajero',
        ); // Guardamos el rol (admin o cajero)
      }

      return data;
    } catch (e) {
      return {
        'exito': false,
        'error': 'Error de conexión con el servidor SaaS.',
      };
    }
  }

  // ==========================================================
  // 🏢 SaaS: GENERACIÓN Y CONSUMO DE LICENCIAS
  // ==========================================================
  static Future<Map<String, dynamic>> generarLicenciaSaaS(
    String nombreEmpresa,
    String codigoEmpresa,
    String plan,
    int limite,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/superadmin/generar-licencia'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          "nombre_comercial": nombreEmpresa,
          "codigo_empresa": codigoEmpresa,
          "plan": plan,
          "limite_sucursales": limite,
        }),
      );
      await _verificarTokenExpirado(res);
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'exito': false,
        'error': 'Fallo de conexión al generar licencia.',
      };
    }
  }

  static Future<Map<String, dynamic>> registrarClienteApp(
    String codigoEmpresa,
    String codigoLicencia,
    String usuarioAdmin,
    String passwordAdmin,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/publico/registro-cliente'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "codigo_empresa": codigoEmpresa,
          "codigo_licencia": codigoLicencia,
          "admin_usuario": usuarioAdmin,
          "admin_password": passwordAdmin,
        }),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'exito': false, 'error': 'Fallo de conexión al registrarte.'};
    }
  }

  // ==========================================================
  // 🛡️ MODO DIOS: SÚPER ADMIN SAAS
  // ==========================================================
  static Future<List<dynamic>> obtenerTodasLasEmpresas() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/superadmin/empresas'),
        headers: await getAuthHeaders(),
      );
      await _verificarTokenExpirado(res);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['exito']) return data['empresas'];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> cambiarEstadoEmpresa(
    String codigoEmpresa,
    bool suspender,
  ) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/superadmin/empresas/$codigoEmpresa/estado'),
        headers: await getAuthHeaders(),
        body: jsonEncode({"suspendida": suspender}),
      );
      await _verificarTokenExpirado(res);
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // 🚨 NUEVA FUNCIÓN: PARA MEJORAR EL PLAN DE UN CLIENTE
  static Future<bool> actualizarPlanEmpresa(
    String codigoEmpresa,
    String nuevoPlan,
    int nuevoLimite,
  ) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/superadmin/empresas/$codigoEmpresa/plan'),
        headers: await getAuthHeaders(),
        body: jsonEncode({"plan": nuevoPlan, "limite_sucursales": nuevoLimite}),
      );
      await _verificarTokenExpirado(res);
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
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
      await _verificarTokenExpirado(res);

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
      await _verificarTokenExpirado(res);
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

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      await _verificarTokenExpirado(response);

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
      await _verificarTokenExpirado(res);

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
      await _verificarTokenExpirado(res);

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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);

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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);

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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);

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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);

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
      await _verificarTokenExpirado(res);

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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);

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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);

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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);

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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);

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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);
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
      await _verificarTokenExpirado(res);
      return jsonDecode(res.body);
    } catch (e) {
      return {'exito': false, 'error': 'Fallo de conexión con el servidor.'};
    }
  }
}
