import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:http/http.dart' as http;

import '../../services/api_service.dart';
import '../utils/escaner_utils.dart';
import '../utils/motor_impresion.dart';
import 'registro_vip_view.dart';

class TerminalCobroView extends StatefulWidget {
  final Function(double) onVentaExitosa;
  final VoidCallback onCerrarCaja;
  final double ventasTotales;
  final double gastosTotales;

  const TerminalCobroView({
    super.key,
    required this.onVentaExitosa,
    required this.onCerrarCaja,
    required this.ventasTotales,
    required this.gastosTotales,
  });

  @override
  State<TerminalCobroView> createState() => _TerminalCobroViewState();
}

class _TerminalCobroViewState extends State<TerminalCobroView> {
  final TextEditingController _buscadorController = TextEditingController();
  final TextEditingController _pagoController = TextEditingController();
  final TextEditingController _cuponController = TextEditingController();
  final FocusNode _buscadorFocus = FocusNode();

  final TextEditingController _mixtoEfectivoController =
      TextEditingController();
  final TextEditingController _mixtoTransfController = TextEditingController();

  final List<Map<String, dynamic>> carrito = [];
  List<dynamic> _catalogoReal = [];

  double _subtotal = 0.0;
  double _descuentoAplicado = 0.0;
  double _total = 0.0;
  double _cambio = 0.0;
  String _vendedorAsociado = "";
  double _descuentoPorPieza = 0.0;

  Map<String, dynamic>? _clienteVIP;
  bool _usarSaldoVIP = false;
  double _saldoVipAGastar = 0.0;

  bool _procesandoCobro = false;
  bool _cobroEfectivoModo = false;
  bool _cobroMixtoModo = false;
  Timer? _mpPollingTimer;

  @override
  void initState() {
    super.initState();
    _cargarCatalogoDesdeCerebro();
    _cargarCarritoMemoria();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _buscadorFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _mpPollingTimer?.cancel();
    _buscadorFocus.dispose();
    _buscadorController.dispose();
    _pagoController.dispose();
    _cuponController.dispose();
    _mixtoEfectivoController.dispose();
    _mixtoTransfController.dispose();
    super.dispose();
  }

  Future<void> _procesarQRVip(String qrHash) async {
    if (!mounted) {
      return;
    }

    _buscadorController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext loaderCtx) =>
          const Center(child: CircularProgressIndicator(color: Colors.amber)),
    );

    final nav = Navigator.of(context);
    final sm = ScaffoldMessenger.of(context);

    try {
      var res = await ApiService.consultarVIP(qrHash);

      if (!mounted) {
        return;
      }
      nav.pop();

      if (res['exito'] == true) {
        _mostrarOpcionesVIP(res['cliente'], qrHash);
      } else {
        sm.showSnackBar(
          SnackBar(
            content: Text(
              res['error'] ?? 'Tarjeta VIP no encontrada o inválida',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      nav.pop();
      sm.showSnackBar(
        const SnackBar(
          content: Text('Error al conectar con la base de datos.'),
          backgroundColor: Colors.red,
        ),
      );
      debugPrint('Error procesando QR VIP: $e');
    }
    if (mounted) {
      _buscadorFocus.requestFocus();
    }
  }

  void _mostrarOpcionesVIP(Map<String, dynamic> cliente, String qrHash) {
    if (!mounted) {
      return;
    }

    bool tieneRopaLinea = carrito.any((item) => item['en_rebaja'] == false);
    double saldoDisponible =
        double.tryParse(cliente['saldo_cashback'].toString()) ?? 0.0;

    showDialog(
      context: context,
      builder: (BuildContext dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.amber, width: 2),
        ),
        title: const Row(
          children: [
            Icon(Icons.stars, color: Colors.amber, size: 30),
            SizedBox(width: 10),
            Text('CLIENTE VIP', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cliente['nombre'].toString().toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
            Text(
              'Nivel actual: ${cliente['nivel_vip'].toString().toUpperCase()}',
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Saldo Disponible:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  Text(
                    '\$${saldoDisponible.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (!tieneRopaLinea && saldoDisponible > 0)
              const Text(
                '⚠️ Para gastar saldo, debe llevar al menos un producto de línea.',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              )
            else
              const Text(
                '¿Qué desea hacer el cliente con esta compra?',
                style: TextStyle(color: Colors.grey),
              ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text(
              'ACUMULAR',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              setState(() {
                _clienteVIP = cliente;
                _clienteVIP!['qr_hash'] = qrHash;
                _usarSaldoVIP = false;
                _saldoVipAGastar = 0.0;
                _recalcularTotal();
              });
              Navigator.pop(dialogCtx);
            },
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            icon: const Icon(Icons.monetization_on),
            label: const Text(
              'GASTAR',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: (!tieneRopaLinea || saldoDisponible <= 0)
                ? null
                : () {
                    setState(() {
                      _clienteVIP = cliente;
                      _clienteVIP!['qr_hash'] = qrHash;
                      _usarSaldoVIP = true;
                      _saldoVipAGastar = saldoDisponible;
                      _recalcularTotal();
                    });
                    Navigator.pop(dialogCtx);
                  },
          ),
        ],
      ),
    ).then((_) {
      if (mounted) {
        _buscadorFocus.requestFocus();
      }
    });
  }

  void _mostrarAlertaTraspaso(String qrViejo, String nuevoNivel) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext traspasoCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: nuevoNivel == 'oro' ? Colors.amber : Colors.black,
            width: 3,
          ),
        ),
        title: Row(
          children: [
            Icon(
              Icons.upgrade,
              color: nuevoNivel == 'oro' ? Colors.amber : Colors.black,
              size: 35,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '¡CLIENTE CALIFICA A UPGRADE!',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          'Este cliente acaba de alcanzar las compras necesarias.\n\n'
          'Es necesario actualizar su tarjeta física al Nivel ${nuevoNivel.toUpperCase()}.\n\n'
          'Presiona OK para abrir el escáner de traspasos.',
          style: const TextStyle(fontSize: 15),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            ),
            onPressed: () {
              Navigator.pop(traspasoCtx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (BuildContext contextRuta) => Scaffold(
                    appBar: AppBar(
                      title: const Text(
                        'TRASPASO DE TARJETA',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(contextRuta),
                      ),
                    ),
                    body: RegistroVipView(
                      qrViejoTraspaso: qrViejo,
                      nivelTraspaso: nuevoNivel,
                    ),
                  ),
                ),
              );
            },
            child: const Text(
              'OK, ACTUALIZAR AHORA',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cargarCatalogoDesdeCerebro() async {
    try {
      // 🚨 SAAS FIX: Inyectamos token JWT
      var res = await http.get(
        Uri.parse('${ApiService.baseUrl}/pos/catalogo'),
        headers: await ApiService.getAuthHeaders(),
      );

      if (!mounted) {
        return;
      }

      if (res.statusCode == 200) {
        var data = jsonDecode(res.body);
        if (data['exito'] == true) {
          setState(() {
            _catalogoReal = data['productos'];
          });
        }
      }
    } catch (e) {
      debugPrint("Error catalogo: $e");
    }
  }

  Future<void> _cargarCarritoMemoria() async {
    final prefs = await SharedPreferences.getInstance();
    final String? carritoStr = prefs.getString('caja_carrito');
    if (carritoStr != null) {
      final List<dynamic> decoded = jsonDecode(carritoStr);
      setState(() {
        carrito.clear();
        for (var item in decoded) {
          carrito.add(Map<String, dynamic>.from(item));
        }
        _recalcularTotal();
      });
    }
  }

  Future<void> _guardarCarritoMemoria() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('caja_carrito', jsonEncode(carrito));
  }

  Future<void> _registrarVentaEnMemoria(
    List<Map<String, dynamic>> carritoVendido,
    double totalTicket,
    String vendedor,
    String metodo,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final String? detallesStr = prefs.getString('caja_ventas_detalles');
    List<dynamic> detalles = detallesStr != null ? jsonDecode(detallesStr) : [];

    String resumenEstructurado = "";
    int piezasTotalesVenta = 0;

    for (var item in carritoVendido) {
      resumenEstructurado +=
          "${item['cantidad']}x [SKU: ${item['sku']}] ${item['nombre']} (Talla: ${item['talla']}) a \$${item['precio']} c/u. ";
      piezasTotalesVenta += (item['cantidad'] as int);
    }

    if (vendedor.isNotEmpty) {
      resumenEstructurado += "| Vendedor: $vendedor";
    } else {
      resumenEstructurado += "| Vendedor: Mostrador General";
    }

    detalles.add({
      'sku': '',
      'nombre': resumenEstructurado,
      'talla': '',
      'precio': totalTicket,
      'cantidad': piezasTotalesVenta,
      'metodo': metodo,
    });

    await prefs.setString('caja_ventas_detalles', jsonEncode(detalles));
  }

  Future<void> _escanearConCamara() async {
    if (!mounted) {
      return;
    }
    final sm = ScaffoldMessenger.of(context);
    try {
      var result = await BarcodeScanner.scan();
      if (result.type == ResultType.Barcode && mounted) {
        String barcodeScanRes = result.rawContent;
        if (barcodeScanRes.isNotEmpty) {
          _buscadorController.text = barcodeScanRes;
          _agregarAlCarrito(barcodeScanRes);
        }
      }
    } catch (e) {
      if (mounted) {
        sm.showSnackBar(
          const SnackBar(
            content: Text('Cancelado o Error al abrir la cámara'),
            backgroundColor: Colors.orange,
          ),
        );
        _buscadorFocus.requestFocus();
      }
      debugPrint('Error cámara: $e');
    }
  }

  void _mostrarSelectorDeTallas(
    Map<String, dynamic> p,
    List<Map<String, dynamic>> tallasBD,
  ) {
    if (!mounted) {
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext contextDialog) {
        return AlertDialog(
          title: Text('Selecciona la talla de ${p['sku']}'),
          content: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: tallasBD.map((t) {
              bool agotado = t['cantidad'] <= 0;
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: agotado ? Colors.grey : Colors.black,
                  foregroundColor: Colors.white,
                ),
                onPressed: agotado
                    ? null
                    : () {
                        Navigator.pop(contextDialog);
                        _ejecutarAgregarAlCarrito(
                          p,
                          sanitizarAlfanumerico(t['talla'].toString()),
                          tallasBD,
                        );
                      },
                child: Text('${t['talla']} (${t['cantidad']} pz)'),
              );
            }).toList(),
          ),
        );
      },
    ).then((_) {
      if (mounted) {
        _buscadorFocus.requestFocus();
      }
    });
  }

  void _agregarAlCarrito(String codigoOBusqueda) {
    if (codigoOBusqueda.isEmpty) {
      if (mounted) {
        _buscadorFocus.requestFocus();
      }
      return;
    }

    if (RegExp(r'^[123]\d{7,}$').hasMatch(codigoOBusqueda) ||
        RegExp(r'^[123]-').hasMatch(codigoOBusqueda)) {
      _procesarQRVip(codigoOBusqueda);
      return;
    }

    final datosEscaneo = decodificarEscaneo(codigoOBusqueda);
    String skuLimpio = datosEscaneo['sku']!;
    String tallaLimpia = datosEscaneo['talla']!;

    final producto = _catalogoReal.where((p) {
      String dbSkuLimpio = sanitizarAlfanumerico(p["sku"].toString());
      String dbNombreLimpio = sanitizarAlfanumerico(p["nombre"].toString());
      return dbSkuLimpio == skuLimpio || dbNombreLimpio.contains(skuLimpio);
    }).toList();

    if (producto.isNotEmpty) {
      var p = producto.first;
      List<Map<String, dynamic>> tallasBD = parsearTallasBD(p['tallas']);
      if (tallaLimpia == 'UNICA' &&
          tallasBD.isNotEmpty &&
          sanitizarAlfanumerico(tallasBD[0]['talla'].toString()) != 'UNICA') {
        _mostrarSelectorDeTallas(p, tallasBD);
        return;
      }
      _ejecutarAgregarAlCarrito(p, tallaLimpia, tallasBD);
    } else {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prenda no encontrada'),
          backgroundColor: Colors.red,
        ),
      );
      _buscadorController.clear();
      if (mounted) {
        _buscadorFocus.requestFocus();
      }
    }
  }

  void _ejecutarAgregarAlCarrito(
    Map<String, dynamic> p,
    String tallaEncontradaLimpia,
    List<Map<String, dynamic>> tallasBD,
  ) {
    String tallaRealVisual = "ÚNICA";
    int stockDisponible = 0;

    for (var t in tallasBD) {
      if (sanitizarAlfanumerico(t['talla'].toString()) ==
          tallaEncontradaLimpia) {
        stockDisponible = t['cantidad'];
        tallaRealVisual = t['talla'].toString();
        break;
      }
    }

    if (stockDisponible == 0 && tallasBD.isEmpty) {
      stockDisponible = int.tryParse(p["stock_bodega"]?.toString() ?? '0') ?? 0;
    }

    int indexEnCarrito = carrito.indexWhere(
      (item) => item['id'] == p['id'] && item['talla'] == tallaRealVisual,
    );
    int cantidadActual = indexEnCarrito != -1
        ? carrito[indexEnCarrito]['cantidad']
        : 0;

    if (stockDisponible <= cantidadActual) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sin stock suficiente de la talla $tallaRealVisual'),
          backgroundColor: Colors.orange,
        ),
      );
      _buscadorController.clear();
      if (mounted) {
        _buscadorFocus.requestFocus();
      }
      return;
    }

    HapticFeedback.lightImpact();

    setState(() {
      if (indexEnCarrito != -1) {
        carrito[indexEnCarrito]['cantidad'] += 1;
      } else {
        double precioVenta =
            double.tryParse(p["precio_venta"].toString()) ?? 0.0;
        bool enRebaja = p["en_rebaja"] == 1 || p["en_rebaja"] == true;
        double precioRebaja =
            double.tryParse(p["precio_rebaja"]?.toString() ?? '0') ?? 0.0;

        carrito.add({
          "id": p["id"],
          "sku": p["sku"],
          "nombre": p["nombre"],
          "talla": tallaRealVisual,
          "precio_venta": precioVenta,
          "en_rebaja": enRebaja,
          "precio_rebaja": precioRebaja,
          "precio": enRebaja ? precioRebaja : precioVenta,
          "cantidad": 1,
          "foto_url": sanearImagen(p["url_foto_principal"]),
        });
      }

      if (_usarSaldoVIP && carrito.every((item) => item['en_rebaja'] == true)) {
        _usarSaldoVIP = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'El saldo VIP solo se puede gastar si hay productos de línea.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      _recalcularTotal();
      _buscadorController.clear();
      _guardarCarritoMemoria();

      if (mounted) {
        _buscadorFocus.requestFocus();
      }
    });
  }

  void _modificarCantidad(int index, int delta) {
    setState(() {
      int nuevaCant = carrito[index]['cantidad'] + delta;
      if (nuevaCant <= 0) {
        _quitarDelCarrito(index);
      } else {
        int stockDisponible = 0;
        final pCatalogo = _catalogoReal.firstWhere(
          (prod) => prod['id'] == carrito[index]['id'],
          orElse: () => null,
        );

        if (pCatalogo != null) {
          List<Map<String, dynamic>> tallasBD = parsearTallasBD(
            pCatalogo['tallas'],
          );
          if (tallasBD.isNotEmpty) {
            final t = tallasBD.firstWhere(
              (t) => t['talla'] == carrito[index]['talla'],
              orElse: () => {'cantidad': 0},
            );
            stockDisponible = t['cantidad'];
          } else {
            stockDisponible =
                int.tryParse(pCatalogo["stock_bodega"]?.toString() ?? '0') ?? 0;
          }
        }

        if (nuevaCant > stockDisponible) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Límite de stock alcanzado'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } else {
          carrito[index]['cantidad'] = nuevaCant;
          _recalcularTotal();
          _guardarCarritoMemoria();
        }
      }
    });
    if (mounted) {
      _buscadorFocus.requestFocus();
    }
  }

  void _quitarDelCarrito(int index) {
    setState(() {
      carrito.removeAt(index);
      if (carrito.isEmpty) {
        _descuentoAplicado = 0.0;
        _vendedorAsociado = "";
        _cuponController.clear();
        _cobroEfectivoModo = false;
        _cobroMixtoModo = false;
        _descuentoPorPieza = 0.0;
      }

      if (_usarSaldoVIP &&
          carrito.isNotEmpty &&
          carrito.every((item) => item['en_rebaja'] == true)) {
        _usarSaldoVIP = false;
      }

      _recalcularTotal();
      _guardarCarritoMemoria();
    });
    if (mounted) {
      _buscadorFocus.requestFocus();
    }
  }

  Future<void> _aplicarCupon() async {
    if (!mounted) {
      return;
    }

    if (carrito.isEmpty) {
      return;
    }

    String codigoIngresado = _cuponController.text.trim().toUpperCase();
    final sm = ScaffoldMessenger.of(context);

    if (codigoIngresado.isEmpty) {
      setState(() {
        _vendedorAsociado = "";
        _descuentoPorPieza = 0.0;
        _recalcularTotal();
      });
      sm.showSnackBar(
        const SnackBar(
          content: Text('Vendedor / Cupón removido'),
          backgroundColor: Colors.blue,
        ),
      );
      if (mounted) {
        _buscadorFocus.requestFocus();
      }
      return;
    }

    try {
      // 🚨 SAAS FIX: Usamos ApiService centralizado con headers JWT
      var data = await ApiService.validarCupon(codigoIngresado);

      if (!mounted) {
        return;
      }

      if (data['valido'] == true) {
        setState(() {
          _vendedorAsociado = codigoIngresado;
          _descuentoPorPieza =
              double.tryParse(data['descuento'].toString()) ?? 0.0;
          _recalcularTotal();
        });
        sm.showSnackBar(
          const SnackBar(
            content: Text('Código aplicado con éxito'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() {
          _vendedorAsociado = "";
          _descuentoPorPieza = 0.0;
          _recalcularTotal();
        });
        sm.showSnackBar(
          const SnackBar(
            content: Text('Código inválido o inactivo'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      sm.showSnackBar(
        const SnackBar(
          content: Text('Error al conectar con servidor'),
          backgroundColor: Colors.orange,
        ),
      );
      debugPrint('Error cupón: $e');
    } finally {
      if (mounted) {
        _buscadorFocus.requestFocus();
      }
    }
  }

  void _recalcularTotal() {
    int piezasTotales = carrito.fold(
      0,
      (sum, item) => sum + (item['cantidad'] as int),
    );
    _descuentoAplicado = _descuentoPorPieza * piezasTotales;
    _subtotal = carrito.fold(
      0,
      (sum, item) => sum + (item["precio"] * item["cantidad"]),
    );

    _total = _subtotal - _descuentoAplicado;

    if (_clienteVIP != null && _usarSaldoVIP) {
      if (_saldoVipAGastar > _total) {
        _saldoVipAGastar = _total;
      }
      _total = _total - _saldoVipAGastar;
    }

    if (_total < 0) {
      _total = 0;
    }
    _calcularCambio();
    _calcularCambioMixto();
  }

  void _calcularCambio() {
    double pago = double.tryParse(_pagoController.text) ?? 0.0;
    setState(() {
      _cambio = (pago >= _total && _total > 0) ? pago - _total : 0.0;
    });
  }

  void _calcularCambioMixto() {
    double ef = double.tryParse(_mixtoEfectivoController.text) ?? 0.0;
    double tr = double.tryParse(_mixtoTransfController.text) ?? 0.0;
    setState(() {
      _cambio = ((ef + tr) >= _total && _total > 0) ? (ef + tr) - _total : 0.0;
    });
  }

  Future<void> _iniciarCobroTerminalMP() async {
    if (!mounted) {
      return;
    }
    if (carrito.isEmpty || _procesandoCobro) {
      return;
    }

    setState(() => _procesandoCobro = true);

    final nav = Navigator.of(context, rootNavigator: true);
    final sm = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext contextDialog) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.blue),
                SizedBox(height: 20),
                Text(
                  "Conectando con la terminal...",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 10),
                Text(
                  "Por favor, pídele al cliente que acerque su tarjeta.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      // 🚨 SAAS FIX: Headers de Autenticación JWT
      var res = await http.post(
        Uri.parse('${ApiService.baseUrl}/pos/mp/cobrar-terminal'),
        headers: await ApiService.getAuthHeaders(),
        body: jsonEncode({"total": _total}),
      );

      if (!mounted) {
        return;
      }
      var data = jsonDecode(res.body);

      if (data['exito'] == true && data['intent_id'] != null) {
        String intentId = data['intent_id'];

        _mpPollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
          Future<void> verificarEstado() async {
            try {
              // 🚨 SAAS FIX: Headers de Autenticación JWT
              var statusRes = await http.get(
                Uri.parse(
                  '${ApiService.baseUrl}/pos/mp/estado-cobro/$intentId',
                ),
                headers: await ApiService.getAuthHeaders(),
              );

              if (!mounted) {
                timer.cancel();
                return;
              }

              var statusData = jsonDecode(statusRes.body);

              if (statusData['exito'] == true) {
                String estado = statusData['estado'];
                String estadoPago = statusData['estado_pago'] ?? 'desconocido';

                if (estado == 'FINISHED') {
                  timer.cancel();
                  nav.pop();

                  if (estadoPago == 'approved') {
                    _ejecutarCobroEImprimirTicket(
                      metodo: "Tarjeta MP",
                      mpIntentId: intentId,
                    );
                  } else {
                    sm.showSnackBar(
                      SnackBar(
                        content: Text('❌ Pago RECHAZADO ($estadoPago).'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    setState(() => _procesandoCobro = false);
                    if (mounted) {
                      _buscadorFocus.requestFocus();
                    }
                  }
                } else if (estado == 'CANCELED' || estado == 'ERROR') {
                  timer.cancel();
                  nav.pop();
                  sm.showSnackBar(
                    SnackBar(
                      content: Text(
                        '❌ Pago cancelado en la terminal ($estado)',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  setState(() => _procesandoCobro = false);
                  if (mounted) {
                    _buscadorFocus.requestFocus();
                  }
                }
              }
            } catch (e) {
              if (!mounted) {
                timer.cancel();
                return;
              }
              timer.cancel();
              nav.pop();
              setState(() => _procesandoCobro = false);
              sm.showSnackBar(
                const SnackBar(
                  content: Text('Error al consultar estado a Mercado Pago'),
                  backgroundColor: Colors.red,
                ),
              );
              debugPrint('Error status MP: $e');
              if (mounted) {
                _buscadorFocus.requestFocus();
              }
            }
          }

          verificarEstado();
        });
      } else {
        nav.pop();
        setState(() => _procesandoCobro = false);
        sm.showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'No se pudo conectar a la terminal'),
            backgroundColor: Colors.red,
          ),
        );
        if (mounted) {
          _buscadorFocus.requestFocus();
        }
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      nav.pop();
      setState(() => _procesandoCobro = false);
      sm.showSnackBar(
        const SnackBar(
          content: Text('Error de red'),
          backgroundColor: Colors.red,
        ),
      );
      debugPrint('Error init MP: $e');
      if (mounted) {
        _buscadorFocus.requestFocus();
      }
    }
  }

  // =========================================================================
  // 🖨️ DELEGAMOS LA IMPRESIÓN AL MOTOR EXTERNO
  // =========================================================================
  Future<void> _ejecutarCobroEImprimirTicket({
    required String metodo,
    String? mpIntentId,
  }) async {
    if (!mounted) {
      return;
    }

    double pagoEf = 0.0;
    double pagoTr = 0.0;
    String metodoDB = metodo;
    final sm = ScaffoldMessenger.of(context);

    if (metodo == "Efectivo") {
      pagoEf = double.tryParse(_pagoController.text) ?? 0.0;
      if (pagoEf < _total) {
        sm.showSnackBar(
          const SnackBar(
            content: Text('Falta dinero para cubrir el total'),
            backgroundColor: Colors.orange,
          ),
        );
        if (mounted) {
          _buscadorFocus.requestFocus();
        }
        return;
      }
    } else if (metodo == "MIXTO") {
      pagoEf = double.tryParse(_mixtoEfectivoController.text) ?? 0.0;
      pagoTr = double.tryParse(_mixtoTransfController.text) ?? 0.0;
      if ((pagoEf + pagoTr) < _total) {
        sm.showSnackBar(
          const SnackBar(
            content: Text('La suma no cubre el total de la compra'),
            backgroundColor: Colors.orange,
          ),
        );
        if (mounted) {
          _buscadorFocus.requestFocus();
        }
        return;
      }
      double netoEfectivo = pagoEf - _cambio;
      if (netoEfectivo < 0) {
        netoEfectivo = 0;
      }
      metodoDB =
          "MIXTO (Efectivo: \$${netoEfectivo.toStringAsFixed(2)}, Transf: \$${pagoTr.toStringAsFixed(2)})";
    }

    if (metodoDB == "Tarjeta MP") {
      metodoDB = "Tarjeta";
    }

    setState(() => _procesandoCobro = true);

    List<Map<String, dynamic>> carritoAEnviar = carrito.map((item) {
      var mod = Map<String, dynamic>.from(item);
      mod['precio_venta'] = (mod['precio_venta'] - _descuentoPorPieza).clamp(
        0.0,
        double.infinity,
      );
      if (mod['en_rebaja']) {
        mod['precio_rebaja'] = (mod['precio_rebaja'] - _descuentoPorPieza)
            .clamp(0.0, double.infinity);
      }
      mod['precio'] = (mod['precio'] - _descuentoPorPieza).clamp(
        0.0,
        double.infinity,
      );
      return mod;
    }).toList();

    try {
      var bodyData = {
        "carrito": carritoAEnviar,
        "metodo_pago": metodoDB,
        "codigo_creador": _vendedorAsociado,
      };

      if (mpIntentId != null) {
        bodyData["mp_intent_id"] = mpIntentId;
      }
      if (_clienteVIP != null) {
        bodyData["qr_vip"] = _clienteVIP!['qr_hash'];
        bodyData["monto_cashback_usado"] = _usarSaldoVIP ? _saldoVipAGastar : 0;
      }

      var res = await http.post(
        Uri.parse('${ApiService.baseUrl}/pos/vender'),
        headers:
            await ApiService.getAuthHeaders(), // 🚨 SAAS: Inyección del Token JWT de autenticación de sucursal
        body: jsonEncode(bodyData),
      );

      if (!mounted) {
        return;
      }

      var data = jsonDecode(res.body);

      if (data['exito'] == true) {
        final double totalImpresion = _total;
        final double cambioImpresion = _cambio;
        final String descuentoTxt = _vendedorAsociado.isNotEmpty
            ? "Desc. ($_vendedorAsociado): -\$${_descuentoAplicado.toStringAsFixed(2)}"
            : "";
        final String vipTxt = (_clienteVIP != null && _usarSaldoVIP)
            ? "Pago con Saldo VIP: -\$${_saldoVipAGastar.toStringAsFixed(2)}"
            : "";

        final String? alertaTraspaso = data['alerta_traspaso'];
        final String? qrViejo = _clienteVIP != null
            ? _clienteVIP!['qr_hash']
            : null;

        await _registrarVentaEnMemoria(
          carritoAEnviar,
          totalImpresion,
          _vendedorAsociado,
          metodoDB,
        );

        if (!mounted) {
          return;
        }
        widget.onVentaExitosa(_total);

        setState(() {
          carrito.clear();
          _pagoController.clear();
          _cuponController.clear();
          _mixtoEfectivoController.clear();
          _mixtoTransfController.clear();
          _vendedorAsociado = "";
          _descuentoAplicado = 0.0;
          _descuentoPorPieza = 0.0;
          _cobroEfectivoModo = false;
          _cobroMixtoModo = false;
          _cambio = 0.0;
          _clienteVIP = null;
          _usarSaldoVIP = false;
          _saldoVipAGastar = 0.0;
          _recalcularTotal();
        });

        _guardarCarritoMemoria();
        _cargarCatalogoDesdeCerebro();

        // 🚨 LLAMADA AL MOTOR DE IMPRESIÓN EXTERNO
        await MotorImpresion.imprimirTicketVenta(
          carritoAEnviar: carritoAEnviar,
          metodoDB: metodoDB,
          totalImpresion: totalImpresion,
          pagoEf: pagoEf,
          pagoTr: pagoTr,
          cambioImpresion: cambioImpresion,
          descuentoTxt: descuentoTxt,
          vipTxt: vipTxt,
        );

        if (alertaTraspaso != null && qrViejo != null && mounted) {
          _mostrarAlertaTraspaso(qrViejo, alertaTraspaso);
        }
      } else {
        sm.showSnackBar(
          SnackBar(
            content: Text('❌ Error BD: ${data['error']}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      sm.showSnackBar(
        SnackBar(
          content: Text('❌ Error de red: $e'),
          backgroundColor: Colors.red,
        ),
      );
      debugPrint('Error de cobro final: $e');
    } finally {
      if (mounted) {
        setState(() {
          _procesandoCobro = false;
        });
      }
      if (mounted) {
        _buscadorFocus.requestFocus();
      }
    }
  }

  Future<void> _imprimirCorteCaja() async {
    if (!mounted) {
      return;
    }

    final sm = ScaffoldMessenger.of(context);
    final prefs = await SharedPreferences.getInstance();

    final String? detallesStr = prefs.getString('caja_ventas_detalles');
    List<dynamic> detalles = detallesStr != null ? jsonDecode(detallesStr) : [];
    int totalPiezas = 0;
    double calcEfectivo = 0.0;
    double calcTarjeta = 0.0;
    double calcTransferencia = 0.0;

    for (var d in detalles) {
      totalPiezas += (d['cantidad'] as int);
      double monto = (d['precio'] as num).toDouble();
      String met = d['metodo'].toString().toUpperCase();

      if (met.contains('TARJETA') || met == 'TARJETA MP') {
        calcTarjeta += monto;
      } else if (met.contains('TRANSF')) {
        calcTransferencia += monto;
      } else if (met.contains('MIXTO')) {
        RegExp reg = RegExp(
          r'Efectivo:\s*\$([\d\.]+),\s*Transf:\s*\$([\d\.]+)',
        );
        var match = reg.firstMatch(d['metodo'].toString());
        if (match != null) {
          calcEfectivo += double.tryParse(match.group(1) ?? '0') ?? 0;
          calcTransferencia += double.tryParse(match.group(2) ?? '0') ?? 0;
        }
      } else {
        calcEfectivo += monto;
      }
    }

    final String? apartadosStr = prefs.getString('caja_apartados_detalles');
    List<dynamic> apartados = apartadosStr != null
        ? jsonDecode(apartadosStr)
        : [];
    for (var a in apartados) {
      double monto = (a['monto'] as num).toDouble();
      String met = a['metodo'].toString().toUpperCase();

      if (met.contains('TARJETA') || met == 'TARJETA MP') {
        calcTarjeta += monto;
      } else if (met.contains('TRANSF')) {
        calcTransferencia += monto;
      } else {
        calcEfectivo += monto;
      }
    }

    final String? cambiosStr = prefs.getString('caja_cambios_detalles');
    List<dynamic> cambios = cambiosStr != null ? jsonDecode(cambiosStr) : [];

    final String? gastosStr = prefs.getString('caja_lista_gastos');
    List<dynamic> gastosLista = gastosStr != null ? jsonDecode(gastosStr) : [];

    double calcVentasTotales = calcEfectivo + calcTarjeta + calcTransferencia;
    double totalFisicoCaja = calcEfectivo - widget.gastosTotales;

    Map<String, dynamic> detallesCorte = {
      "piezas": totalPiezas,
      "items": detalles,
      "apartados": apartados,
      "cambios": cambios,
      "gastos": gastosLista,
    };

    try {
      await ApiService.guardarCorteCaja(
        "Cajero Mostrador",
        calcEfectivo,
        calcTarjeta,
        calcTransferencia,
        widget.gastosTotales,
        detalles: detallesCorte,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      sm.showSnackBar(
        const SnackBar(
          content: Text(
            '❌ No hay internet. El corte NO se guardó en el servidor.',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 6),
        ),
      );
      debugPrint('Error corte red: $e');
      return;
    }

    if (!mounted) {
      return;
    }

    // 🚨 LLAMADA AL MOTOR DE IMPRESIÓN EXTERNO
    await MotorImpresion.imprimirCorteCaja(
      totalPiezas: totalPiezas,
      detalles: detalles,
      apartados: apartados,
      cambios: cambios,
      gastosLista: gastosLista,
      calcVentasTotales: calcVentasTotales,
      calcTarjeta: calcTarjeta,
      calcTransferencia: calcTransferencia,
      calcEfectivo: calcEfectivo,
      gastosTotales: widget.gastosTotales,
      totalFisicoCaja: totalFisicoCaja,
    );

    if (!mounted) {
      return;
    }

    widget.onCerrarCaja();
    await prefs.remove('caja_ventas_detalles');
    await prefs.remove('caja_apartados_detalles');
    await prefs.remove('caja_cambios_detalles');
    await prefs.remove('caja_lista_gastos');

    if (!mounted) {
      return;
    }

    sm.showSnackBar(
      const SnackBar(
        content: Text('✅ Corte exitoso. Memoria de caja limpiada.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 800;

    Widget panelBuscador = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            Text(
              'TERMINAL DE COBRO',
              style: TextStyle(
                fontSize: isMobile ? 20 : 24,
                fontWeight: FontWeight.w300,
                letterSpacing: 3,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.point_of_sale, size: 16),
                  label: const Text(
                    'CERRAR CAJA',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _imprimirCorteCaja,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _buscadorController,
          focusNode: _buscadorFocus,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Escanear Producto o Tarjeta VIP',
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: const Color(0xFFF9F9F9),
            prefixIcon: const Icon(Icons.qr_code_scanner),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => _agregarAlCarrito(_buscadorController.text),
            ),
          ),
          onSubmitted: _agregarAlCarrito,
        ),
        const SizedBox(height: 20),
        Container(
          height: isMobile ? 90 : 100,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            border: Border.all(color: Colors.green.shade200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.barcode_reader, color: Colors.green, size: 30),
                  SizedBox(height: 5),
                  Text(
                    'LECTOR ACTIVO',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    'Listo para escanear',
                    style: TextStyle(color: Colors.green, fontSize: 8),
                  ),
                ],
              ),
              if (isMobile)
                InkWell(
                  onTap: _escanearConCamara,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt, color: Colors.white, size: 24),
                        SizedBox(height: 4),
                        Text(
                          'USAR CÁMARA',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    Widget panelTicket = Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TICKET DE VENTA',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.5,
              color: Colors.grey,
            ),
          ),
          const Divider(height: 20),
          Container(
            constraints: BoxConstraints(maxHeight: isMobile ? 250 : 400),
            child: carrito.isEmpty
                ? const Center(
                    child: Text(
                      'Escanea un producto para comenzar',
                      style: TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: carrito.length,
                    itemBuilder: (BuildContext listCtx, int index) {
                      final item = carrito[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.network(
                                item["foto_url"],
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => Container(
                                  width: 40,
                                  height: 40,
                                  color: Colors.grey.shade200,
                                  child: const Icon(
                                    Icons.checkroom,
                                    color: Colors.grey,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item["nombre"],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        item["sku"],
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 10,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          'Talla: ${item["talla"]}',
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () =>
                                      _modificarCantidad(index, -1),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${item["cantidad"]}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.add_circle_outline,
                                    color: Colors.black,
                                  ),
                                  onPressed: () => _modificarCantidad(index, 1),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '\$${(item["precio"] * item["cantidad"]).toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                        size: 16,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _quitarDelCarrito(index),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cuponController,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Código Creador',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.local_offer_outlined, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                ),
                onPressed: _aplicarCupon,
                child: const Text('APLICAR'),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_descuentoAplicado > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal', style: TextStyle(color: Colors.grey)),
                Text(
                  '\$${_subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Código: $_vendedorAsociado',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '-\$${_descuentoAplicado.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          if (_clienteVIP != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 15),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '👑 VIP: ${_clienteVIP!['nombre']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        if (_usarSaldoVIP)
                          Text(
                            'Gastando: -\$${_saldoVipAGastar.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        else
                          Text(
                            'Acumulando Cashback en esta compra',
                            style: TextStyle(
                              color: Colors.amber.shade800,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() {
                      _clienteVIP = null;
                      _usarSaldoVIP = false;
                      _saldoVipAGastar = 0.0;
                      _recalcularTotal();
                    }),
                  ),
                ],
              ),
            ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TOTAL',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w300),
              ),
              Text(
                '\$${_total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (carrito.isNotEmpty) ...[
            if (!_cobroEfectivoModo && !_cobroMixtoModo) ...[
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            foregroundColor: Colors.black,
                            side: const BorderSide(color: Colors.black),
                          ),
                          icon: const Icon(Icons.money),
                          label: const Text(
                            'EFECTIVO',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              _cobroEfectivoModo = true;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.credit_card),
                          label: const Text(
                            'TARJETA',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          onPressed: _iniciarCobroTerminalMP,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.account_balance),
                          label: const Text(
                            'TRANSFER.',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          onPressed: () => _ejecutarCobroEImprimirTicket(
                            metodo: "Transferencia",
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.orange.shade700,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.donut_large),
                          label: const Text(
                            'PAGO MIXTO',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              _cobroMixtoModo = true;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ] else if (_cobroEfectivoModo) ...[
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      setState(() {
                        _cobroEfectivoModo = false;
                      });
                    },
                  ),
                  const Text(
                    'Cobro en Efectivo',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pagoController,
                keyboardType: TextInputType.number,
                onChanged: (val) => _calcularCambio(),
                decoration: const InputDecoration(
                  labelText: 'Pago del cliente (\$)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                  filled: true,
                  fillColor: Color(0xFFF9F9F9),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _cambio > 0
                      ? Colors.green.shade50
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CAMBIO',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _cambio > 0 ? Colors.green : Colors.grey,
                      ),
                    ),
                    Text(
                      '\$${_cambio.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _cambio > 0 ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _procesandoCobro
                      ? null
                      : () => _ejecutarCobroEImprimirTicket(metodo: "Efectivo"),
                  child: _procesandoCobro
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'COBRAR E IMPRIMIR',
                          style: TextStyle(
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ] else if (_cobroMixtoModo) ...[
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      setState(() {
                        _cobroMixtoModo = false;
                      });
                    },
                  ),
                  const Expanded(
                    child: Text(
                      'Cobro Mixto (Efectivo + Transferencia)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mixtoEfectivoController,
                      keyboardType: TextInputType.number,
                      onChanged: (val) => _calcularCambioMixto(),
                      decoration: const InputDecoration(
                        labelText: '\$ Efectivo',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.money),
                        filled: true,
                        fillColor: Color(0xFFF9F9F9),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _mixtoTransfController,
                      keyboardType: TextInputType.number,
                      onChanged: (val) => _calcularCambioMixto(),
                      decoration: const InputDecoration(
                        labelText: '\$ Transf',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.account_balance),
                        filled: true,
                        fillColor: Color(0xFFF9F9F9),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _cambio > 0
                      ? Colors.green.shade50
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CAMBIO EN EFECTIVO',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _cambio > 0 ? Colors.green : Colors.grey,
                      ),
                    ),
                    Text(
                      '\$${_cambio.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _cambio > 0 ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _procesandoCobro
                      ? null
                      : () => _ejecutarCobroEImprimirTicket(metodo: "MIXTO"),
                  child: _procesandoCobro
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'COBRAR MIXTO E IMPRIMIR',
                          style: TextStyle(
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ],
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
        child: isMobile
            ? SingleChildScrollView(
                child: Column(
                  children: [
                    panelBuscador,
                    const SizedBox(height: 20),
                    panelTicket,
                    const SizedBox(height: 40),
                  ],
                ),
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: panelBuscador),
                  const SizedBox(width: 32),
                  Expanded(
                    flex: 5,
                    child: SingleChildScrollView(child: panelTicket),
                  ),
                ],
              ),
      ),
    );
  }
}
