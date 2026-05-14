import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';
import '../utils/escaner_utils.dart';

class ApartadosView extends StatefulWidget {
  final Function(double) onVentaExitosa;
  const ApartadosView({super.key, required this.onVentaExitosa});
  @override
  State<ApartadosView> createState() => _ApartadosViewState();
}

class _ApartadosViewState extends State<ApartadosView> {
  final TextEditingController _clienteController = TextEditingController();
  final TextEditingController _telefonoController = TextEditingController();
  final TextEditingController _buscadorController = TextEditingController();
  final TextEditingController _engancheController = TextEditingController();
  final TextEditingController _cuponController = TextEditingController();
  final FocusNode _buscadorFocus = FocusNode();

  final List<Map<String, dynamic>> _carritoApartado = [];
  List<dynamic> _catalogoReal = [];
  List<dynamic> _apartadosActivos = [];

  double _subtotalApartado = 0.0;
  double _descuentoAplicado = 0.0;
  double _totalApartado = 0.0;
  String _vendedorAsociado = "";
  double _descuentoPorPieza = 0.0;

  bool _procesando = false;
  String _metodoPagoNuevo = 'Efectivo';
  Timer? _mpPollingTimer;

  @override
  void initState() {
    super.initState();
    _cargarCatalogo();
    _cargarApartados();

    // 🚨 Aseguramos el foco inicial para el escáner bluetooth
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buscadorFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _mpPollingTimer?.cancel();
    _buscadorFocus.dispose();
    _clienteController.dispose();
    _telefonoController.dispose();
    _buscadorController.dispose();
    _engancheController.dispose();
    _cuponController.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogo() async {
    try {
      var res = await http.get(Uri.parse('${ApiService.baseUrl}/pos/catalogo'));
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
      debugPrint('Aviso: $e');
    }
  }

  Future<void> _cargarApartados() async {
    try {
      var res = await http.get(
        Uri.parse('${ApiService.baseUrl}/pos/apartados'),
      );
      if (!mounted) {
        return;
      }
      if (res.statusCode == 200) {
        var data = jsonDecode(res.body);
        if (data['exito'] == true) {
          setState(() {
            _apartadosActivos = data['apartados'];
          });
        }
      }
    } catch (e) {
      debugPrint("Aviso: $e");
    }
  }

  Future<void> _registrarMovimientoApartado(
    String tipo,
    String clienteConDetalle,
    double monto,
    String metodo,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final String? apartadosStr = prefs.getString('caja_apartados_detalles');
    List<dynamic> apartados = apartadosStr != null
        ? jsonDecode(apartadosStr)
        : [];

    apartados.add({
      'tipo': tipo,
      'cliente': clienteConDetalle,
      'monto': monto,
      'metodo': metodo,
    });

    await prefs.setString('caja_apartados_detalles', jsonEncode(apartados));
  }

  void _mostrarSelectorDeTallasApartado(
    Map<String, dynamic> p,
    List<Map<String, dynamic>> tallasBD,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext contextDialog) {
        return AlertDialog(
          title: Text(
            'Selecciona la talla de ${p['sku']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
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
                        _ejecutarAgregarPrenda(
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
      // 🚨 Candado de Foco
      _buscadorFocus.requestFocus();
    });
  }

  void _agregarPrenda(String codigo) {
    if (codigo.isEmpty) {
      _buscadorFocus.requestFocus();
      return;
    }

    final datosEscaneo = decodificarEscaneo(codigo);
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
        _mostrarSelectorDeTallasApartado(p, tallasBD);
        return;
      }

      _ejecutarAgregarPrenda(p, tallaLimpia, tallasBD);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prenda no encontrada'),
          backgroundColor: Colors.red,
        ),
      );
      _buscadorController.clear();
      _buscadorFocus.requestFocus();
    }
  }

  void _ejecutarAgregarPrenda(
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

    int indexEnCarrito = _carritoApartado.indexWhere(
      (item) => item['id'] == p['id'] && item['talla'] == tallaRealVisual,
    );
    int cantidadActual = indexEnCarrito != -1
        ? _carritoApartado[indexEnCarrito]['cantidad']
        : 0;

    // 🚨 VALIDACIÓN ESTRICTA: Evita robos o alteraciones del stock en apartados
    if (stockDisponible <= cantidadActual) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sin stock suficiente de la talla $tallaRealVisual'),
          backgroundColor: Colors.orange,
        ),
      );
      _buscadorController.clear();
      _buscadorFocus.requestFocus();
      return;
    }

    // 🚨 Confirmación sensorial para la cajera
    HapticFeedback.lightImpact();

    setState(() {
      if (indexEnCarrito != -1) {
        _carritoApartado[indexEnCarrito]['cantidad'] += 1;
      } else {
        double precio =
            double.tryParse(
              (p["en_rebaja"] == 1 ? p["precio_rebaja"] : p["precio_venta"])
                  .toString(),
            ) ??
            0.0;
        _carritoApartado.add({
          "id": p["id"],
          "sku": p["sku"],
          "nombre": p["nombre"],
          "talla": tallaRealVisual,
          "precio": precio,
          "cantidad": 1,
          "foto_url": sanearImagen(p["url_foto_principal"]),
        });
      }
      _calcularTotal();
      _buscadorController.clear();
      _buscadorFocus.requestFocus();
    });
  }

  // 🚨 OPTIMIZACIÓN: Modificar cantidades en vivo con botones (+/-)
  void _modificarCantidad(int index, int delta) {
    setState(() {
      int nuevaCant = _carritoApartado[index]['cantidad'] + delta;
      if (nuevaCant <= 0) {
        _quitarDelCarrito(index);
      } else {
        int stockDisponible = 0;
        final pCatalogo = _catalogoReal.firstWhere(
          (prod) => prod['id'] == _carritoApartado[index]['id'],
          orElse: () => null,
        );

        if (pCatalogo != null) {
          List<Map<String, dynamic>> tallasBD = parsearTallasBD(
            pCatalogo['tallas'],
          );
          if (tallasBD.isNotEmpty) {
            final t = tallasBD.firstWhere(
              (t) => t['talla'] == _carritoApartado[index]['talla'],
              orElse: () => {'cantidad': 0},
            );
            stockDisponible = t['cantidad'];
          } else {
            stockDisponible =
                int.tryParse(pCatalogo["stock_bodega"]?.toString() ?? '0') ?? 0;
          }
        }

        if (nuevaCant > stockDisponible) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Límite de stock alcanzado'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          _carritoApartado[index]['cantidad'] = nuevaCant;
          _calcularTotal();
        }
      }
    });
    _buscadorFocus.requestFocus();
  }

  void _quitarDelCarrito(int index) {
    setState(() {
      _carritoApartado.removeAt(index);
      if (_carritoApartado.isEmpty) {
        _descuentoAplicado = 0.0;
        _vendedorAsociado = "";
        _cuponController.clear();
        _descuentoPorPieza = 0.0;
        _subtotalApartado = 0.0;
      }
      _calcularTotal();
      _buscadorFocus.requestFocus();
    });
  }

  Future<void> _aplicarCupon() async {
    if (_carritoApartado.isEmpty) {
      return;
    }

    String codigoIngresado = _cuponController.text.trim().toUpperCase();
    final sm = ScaffoldMessenger.of(context); // 🚨 Capturado para evitar linter

    if (codigoIngresado.isEmpty) {
      setState(() {
        _vendedorAsociado = "";
        _descuentoPorPieza = 0.0;
        _calcularTotal();
      });
      sm.showSnackBar(
        const SnackBar(
          content: Text('Vendedor / Cupón removido'),
          backgroundColor: Colors.blue,
        ),
      );
      _buscadorFocus.requestFocus();
      return;
    }

    try {
      var res = await http.get(
        Uri.parse('${ApiService.baseUrl}/cupones/validar/$codigoIngresado'),
      );
      if (!mounted) {
        return;
      }

      var data = jsonDecode(res.body);

      if (data['valido'] == true) {
        setState(() {
          _vendedorAsociado = codigoIngresado;
          _descuentoPorPieza =
              double.tryParse(data['descuento'].toString()) ?? 0.0;
          _calcularTotal();
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
          _calcularTotal();
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
    } finally {
      _buscadorFocus.requestFocus();
    }
  }

  void _calcularTotal() {
    int piezasTotales = _carritoApartado.fold(
      0,
      (sum, item) => sum + (item['cantidad'] as int),
    );
    _descuentoAplicado = _descuentoPorPieza * piezasTotales;
    _subtotalApartado = _carritoApartado.fold(
      0,
      (sum, item) => sum + (item["precio"] * item["cantidad"]),
    );
    _totalApartado = _subtotalApartado - _descuentoAplicado;
    if (_totalApartado < 0) {
      _totalApartado = 0.0;
    }
  }

  Future<void> _iniciarCobroTerminalMP(
    double montoACobrar,
    String tipoMovimiento, {
    Map<String, dynamic>? apartadoOriginal,
    bool? esLiquidacion,
    double? cambio,
    double? pagoCliente,
  }) async {
    setState(() {
      _procesando = true;
    });

    final nav = Navigator.of(context, rootNavigator: true);
    final sm = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext contextDialog) {
        // 🚨 BLINDAJE IOS: PopScope evita que el gesto de "atrás" rompa el cobro
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
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
      var res = await http.post(
        Uri.parse('${ApiService.baseUrl}/pos/mp/cobrar-terminal'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"total": montoACobrar}),
      );

      if (!mounted) {
        return;
      }

      var data = jsonDecode(res.body);

      if (data['exito'] == true && data['intent_id'] != null) {
        String intentId = data['intent_id'];

        _mpPollingTimer = Timer.periodic(const Duration(seconds: 3), (
          timer,
        ) async {
          try {
            var statusRes = await http.get(
              Uri.parse('${ApiService.baseUrl}/pos/mp/estado-cobro/$intentId'),
            );
            if (!mounted) {
              timer.cancel();
              return;
            }
            var statusData = jsonDecode(statusRes.body);

            if (statusData['exito'] == true) {
              String estado = statusData['estado'];

              if (estado == 'FINISHED') {
                timer.cancel();
                nav.pop();

                if (tipoMovimiento == 'NUEVO') {
                  _ejecutarCrearApartado(montoACobrar, "Tarjeta MP");
                } else {
                  _ejecutarAbonoOLiquidacion(
                    montoACobrar,
                    esLiquidacion ?? false,
                    apartadoOriginal!,
                    "Tarjeta MP",
                    cambio ?? 0,
                    pagoCliente ?? 0,
                  );
                }
              } else if (estado == 'CANCELED' || estado == 'ERROR') {
                timer.cancel();
                nav.pop();
                sm.showSnackBar(
                  SnackBar(
                    content: Text('Pago cancelado o rechazado ($estado)'),
                    backgroundColor: Colors.red,
                  ),
                );
                setState(() {
                  _procesando = false;
                });
                _buscadorFocus.requestFocus();
              }
            }
          } catch (e) {
            timer.cancel();
            if (!mounted) {
              return;
            }
            nav.pop();
            setState(() {
              _procesando = false;
            });
            sm.showSnackBar(
              const SnackBar(
                content: Text('Error al consultar estado de MP'),
                backgroundColor: Colors.red,
              ),
            );
            _buscadorFocus.requestFocus();
          }
        });
      } else {
        nav.pop();
        setState(() {
          _procesando = false;
        });
        sm.showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'No se pudo conectar a la terminal'),
            backgroundColor: Colors.red,
          ),
        );
        _buscadorFocus.requestFocus();
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      nav.pop();
      setState(() {
        _procesando = false;
      });
      sm.showSnackBar(
        SnackBar(
          content: Text('Error de red: $e'),
          backgroundColor: Colors.red,
        ),
      );
      _buscadorFocus.requestFocus();
    }
  }

  Future<void> _crearApartadoEImprimir() async {
    final sm = ScaffoldMessenger.of(context);

    if (_clienteController.text.isEmpty || _carritoApartado.isEmpty) {
      sm.showSnackBar(
        const SnackBar(
          content: Text('Falta el nombre del cliente o productos'),
          backgroundColor: Colors.orange,
        ),
      );
      _buscadorFocus.requestFocus();
      return;
    }
    double enganche = double.tryParse(_engancheController.text) ?? 0.0;

    // 🚨 BLOQUEO: Si el cliente liquida al instante, debe usar la caja normal
    if (enganche >= _totalApartado) {
      sm.showSnackBar(
        const SnackBar(
          content: Text(
            'Si el cliente paga el total, cóbralo en la pestaña de CAJA.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      _buscadorFocus.requestFocus();
      return;
    }

    if (enganche <= 0) {
      sm.showSnackBar(
        const SnackBar(
          content: Text('Monto de enganche inválido'),
          backgroundColor: Colors.orange,
        ),
      );
      _buscadorFocus.requestFocus();
      return;
    }

    if (_metodoPagoNuevo == 'Tarjeta MP') {
      _iniciarCobroTerminalMP(enganche, 'NUEVO');
    } else if (_metodoPagoNuevo == 'Transferencia') {
      _ejecutarCrearApartado(enganche, "Transferencia");
    } else {
      _ejecutarCrearApartado(enganche, "Efectivo");
    }
  }

  Future<void> _ejecutarCrearApartado(
    double enganche,
    String metodoPagoVerificado,
  ) async {
    setState(() {
      _procesando = true;
    });

    final sm = ScaffoldMessenger.of(context);

    // 🚨 APLICAMOS EL DESCUENTO REAL AL CARRITO QUE SE ENVÍA A LA BD
    List<Map<String, dynamic>> carritoAEnviar = _carritoApartado.map((item) {
      var mod = Map<String, dynamic>.from(item);
      mod['precio'] = (mod['precio'] - _descuentoPorPieza).clamp(
        0.0,
        double.infinity,
      );
      mod['vendedor'] =
          _vendedorAsociado; // Lo guardamos en el JSON para recuperarlo en el futuro
      return mod;
    }).toList();

    // 🚨 CONSTRUIMOS EL NOMBRE MAESTRO (Teléfono + Vendedor)
    String nombreFinalCliente = _clienteController.text.trim();
    if (_telefonoController.text.trim().isNotEmpty) {
      nombreFinalCliente += " (Tel: ${_telefonoController.text.trim()})";
    }
    if (_vendedorAsociado.isNotEmpty) {
      nombreFinalCliente += " | Vendedor: $_vendedorAsociado";
    }

    try {
      var res = await http.post(
        Uri.parse('${ApiService.baseUrl}/pos/apartados/nuevo'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "cliente": nombreFinalCliente,
          "carrito": carritoAEnviar,
          "enganche": enganche,
          "total": _totalApartado,
          "metodo_pago": metodoPagoVerificado,
        }),
      );

      if (!mounted) {
        return;
      }

      var data = jsonDecode(res.body);

      if (data['exito'] == true) {
        String descuentoTxt = _vendedorAsociado.isNotEmpty
            ? "Desc. ($_vendedorAsociado): -\$${_descuentoAplicado.toStringAsFixed(2)}"
            : "";

        await _imprimirTicketApartado(
          "TICKET DE APARTADO",
          nombreFinalCliente,
          carritoAEnviar,
          _totalApartado,
          enganche,
          _totalApartado - enganche,
          metodoPago: metodoPagoVerificado,
          descuentoTxt: descuentoTxt,
        );

        if (!mounted) {
          return;
        }

        widget.onVentaExitosa(enganche);
        String resumenPrendas = carritoAEnviar
            .map(
              (item) =>
                  "${item['cantidad']}x [SKU: ${item['sku']}] ${item['nombre']}",
            )
            .join(", ");
        await _registrarMovimientoApartado(
          'NUEVO APARTADO',
          "$nombreFinalCliente ($resumenPrendas)",
          enganche,
          metodoPagoVerificado,
        );

        setState(() {
          _carritoApartado.clear();
          _clienteController.clear();
          _telefonoController.clear();
          _engancheController.clear();
          _cuponController.clear();
          _totalApartado = 0.0;
          _subtotalApartado = 0.0;
          _descuentoAplicado = 0.0;
          _descuentoPorPieza = 0.0;
          _vendedorAsociado = "";
          _metodoPagoNuevo = 'Efectivo';
        });

        await _cargarApartados();
        sm.showSnackBar(
          const SnackBar(
            content: Text('Apartado creado con éxito'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Aviso al crear apartado: $e');
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
      _buscadorFocus.requestFocus();
    }
  }

  Future<void> _ejecutarAbonoOLiquidacion(
    double dineroParaCuenta,
    bool esLiquidacion,
    Map<String, dynamic> apartado,
    String metodoPagoFinal,
    double cambio,
    double pago,
  ) async {
    setState(() {
      _procesando = true;
    });
    final sm = ScaffoldMessenger.of(context);

    try {
      String url = esLiquidacion
          ? '${ApiService.baseUrl}/pos/apartados/liquidar/${apartado['id']}'
          : '${ApiService.baseUrl}/pos/apartados/abonar/${apartado['id']}';

      double totalOriginal =
          double.tryParse(apartado['total'].toString()) ?? 0.0;
      double restaAnterior =
          double.tryParse(apartado['resta'].toString()) ?? 0.0;
      double nuevaResta = esLiquidacion
          ? 0.0
          : (restaAnterior - dineroParaCuenta);

      await http.post(
        Uri.parse(url),
        body: jsonEncode({
          "pago": dineroParaCuenta,
          "metodo_pago": metodoPagoFinal,
        }),
        headers: {"Content-Type": "application/json"},
      );

      if (!mounted) {
        return;
      }

      widget.onVentaExitosa(dineroParaCuenta);
      await _cargarApartados();

      List<dynamic> itemsRecuperados = jsonDecode(apartado['items'] ?? '[]');
      List<Map<String, dynamic>> carritoRecuperado = itemsRecuperados
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (esLiquidacion) {
        String resumenPrendas = carritoRecuperado
            .map(
              (item) =>
                  "${item['cantidad']}x [SKU: ${item['sku']}] ${item['nombre']}",
            )
            .join(", ");
        await _registrarMovimientoApartado(
          'LIQUIDACIÓN',
          "${apartado['cliente']} ($resumenPrendas)",
          dineroParaCuenta,
          metodoPagoFinal,
        );
        await _imprimirTicketApartado(
          "LIQUIDACIÓN DE APARTADO",
          apartado['cliente'].toString(),
          carritoRecuperado,
          totalOriginal,
          dineroParaCuenta,
          0.0,
          cambio: cambio,
          pagoCliente: pago,
          metodoPago: metodoPagoFinal,
        );
        sm.showSnackBar(
          const SnackBar(
            content: Text('Cuenta liquidada. Ticket impreso.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        await _registrarMovimientoApartado(
          'ABONO',
          apartado['cliente'].toString(),
          dineroParaCuenta,
          metodoPagoFinal,
        );
        await _imprimirTicketApartado(
          "ABONO A CUENTA",
          apartado['cliente'].toString(),
          carritoRecuperado,
          totalOriginal,
          dineroParaCuenta,
          nuevaResta,
          metodoPago: metodoPagoFinal,
        );
        sm.showSnackBar(
          const SnackBar(
            content: Text('Abono registrado. Ticket impreso.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Aviso liquidar/abonar: $e');
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
      _buscadorFocus.requestFocus();
    }
  }

  void _abrirDialogoLiquidarOAbonar(Map<String, dynamic> apartado) {
    double restaAnterior = double.tryParse(apartado['resta'].toString()) ?? 0.0;
    TextEditingController pagoController = TextEditingController();
    String metodoPagoAbono = 'Efectivo';

    showDialog(
      context: context,
      builder: (contextDialog) => StatefulBuilder(
        builder: (contextBuilder, setStateDialog) {
          double pago = double.tryParse(pagoController.text) ?? 0.0;
          bool esLiquidacion = pago >= restaAnterior;
          double cambio = esLiquidacion ? (pago - restaAnterior) : 0.0;
          double nuevaResta = esLiquidacion ? 0.0 : (restaAnterior - pago);

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Cobrar a ${apartado['cliente'].toString().split('|')[0].trim()}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Resta actual:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      Text(
                        '\$${restaAnterior.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: pagoController,
                  keyboardType: TextInputType.number,
                  onChanged: (val) => setStateDialog(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Dinero que entrega el cliente (\$)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                    filled: true,
                    fillColor: Color(0xFFF9F9F9),
                  ),
                ),
                const SizedBox(height: 15),

                const Text(
                  'MÉTODO DE PAGO:',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () =>
                            setStateDialog(() => metodoPagoAbono = 'Efectivo'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: metodoPagoAbono == 'Efectivo'
                                ? Colors.green.shade50
                                : Colors.white,
                            border: Border.all(
                              color: metodoPagoAbono == 'Efectivo'
                                  ? Colors.green
                                  : Colors.grey.shade300,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              'EFECT.',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                color: metodoPagoAbono == 'Efectivo'
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => setStateDialog(
                          () => metodoPagoAbono = 'Tarjeta MP',
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: metodoPagoAbono == 'Tarjeta MP'
                                ? Colors.blue.shade50
                                : Colors.white,
                            border: Border.all(
                              color: metodoPagoAbono == 'Tarjeta MP'
                                  ? Colors.blue
                                  : Colors.grey.shade300,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              'TARJ. MP',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                color: metodoPagoAbono == 'Tarjeta MP'
                                    ? Colors.blue
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => setStateDialog(
                          () => metodoPagoAbono = 'Transferencia',
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: metodoPagoAbono == 'Transferencia'
                                ? Colors.purple.shade50
                                : Colors.white,
                            border: Border.all(
                              color: metodoPagoAbono == 'Transferencia'
                                  ? Colors.purple
                                  : Colors.grey.shade300,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              'TRANSF.',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                color: metodoPagoAbono == 'Transferencia'
                                    ? Colors.purple
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 15),
                if (esLiquidacion) ...[
                  Text(
                    'LIQUIDA CUENTA',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                  Text(
                    'CAMBIO: \$${cambio.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: Colors.green,
                    ),
                  ),
                ] else if (pago > 0) ...[
                  Text(
                    'ABONO PARCIAL',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  Text(
                    'Nueva Resta: \$${nuevaResta.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(contextDialog),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: esLiquidacion ? Colors.black : Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: pago > 0
                    ? () async {
                        Navigator.pop(contextDialog);
                        double dineroParaCuenta = esLiquidacion
                            ? restaAnterior
                            : pago;

                        if (metodoPagoAbono == 'Tarjeta MP') {
                          _iniciarCobroTerminalMP(
                            dineroParaCuenta,
                            esLiquidacion ? 'LIQUIDACION' : 'ABONO',
                            apartadoOriginal: apartado,
                            esLiquidacion: esLiquidacion,
                            cambio: cambio,
                            pagoCliente: pago,
                          );
                        } else if (metodoPagoAbono == 'Transferencia') {
                          _ejecutarAbonoOLiquidacion(
                            dineroParaCuenta,
                            esLiquidacion,
                            apartado,
                            "Transferencia",
                            cambio,
                            pago,
                          );
                        } else {
                          _ejecutarAbonoOLiquidacion(
                            dineroParaCuenta,
                            esLiquidacion,
                            apartado,
                            "Efectivo",
                            cambio,
                            pago,
                          );
                        }
                      }
                    : null,
                child: Text(
                  esLiquidacion ? 'COBRAR Y LIQUIDAR' : 'REGISTRAR ABONO',
                ),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      // 🚨 Candado de Foco al salir del modal
      _buscadorFocus.requestFocus();
    });
  }

  // 🚨 ACTUALIZACIÓN DE IMPRESIÓN PARA SAAS MARCA BLANCA
  Future<void> _imprimirTicketApartado(
    String titulo,
    String cliente,
    List<Map<String, dynamic>> carrito,
    double total,
    double pagoActual,
    double resta, {
    double cambio = 0.0,
    double pagoCliente = 0.0,
    String metodoPago = 'Efectivo',
    String descuentoTxt = '',
  }) async {
    final doc = pw.Document();
    pw.MemoryImage? imageLogo;

    // 🚨 DESCARGAMOS EL LOGO DINÁMICO DEL SaaS DESDE MEMORIA
    try {
      final prefs = await SharedPreferences.getInstance();
      final String logoUrl = prefs.getString('caja_logo_empresa') ?? '';

      if (logoUrl.isNotEmpty) {
        final response = await http.get(Uri.parse(logoUrl));
        if (response.statusCode == 200) {
          imageLogo = pw.MemoryImage(response.bodyBytes);
        }
      }
    } catch (e) {
      debugPrint('Error Logo Apartado: $e');
    }

    final now = DateTime.now();
    final fecha =
        '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute}';

    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          80 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 5 * PdfPageFormat.mm,
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              if (imageLogo != null) pw.Image(imageLogo, width: 40, height: 40),
              pw.SizedBox(height: 5),
              // 🚨 SE QUITA EL TEXTO DURO "JP JEANS" Y SE DEJA EL TÍTULO DEL TICKET COMO PRINCIPAL
              pw.Text(
                titulo,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text('Fecha: $fecha', style: const pw.TextStyle(fontSize: 8)),
              pw.Text(
                'Cliente: ${cliente.toUpperCase()}',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Método: $metodoPago',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),
              ...carrito.map(
                (item) => pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        '${item['cantidad']}x ${item['sku'] ?? ''} - ${item['nombre']} [${item['talla']}]',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ),
                    pw.Text(
                      '\$${(item['precio'] * item['cantidad']).toStringAsFixed(2)}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              ),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),
              if (descuentoTxt.isNotEmpty) ...[
                pw.Text(descuentoTxt, style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 5),
              ],
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL ORIGINAL',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '\$${total.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'SU PAGO HOY',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  pw.Text(
                    '\$${pagoActual.toStringAsFixed(2)}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'RESTA POR PAGAR',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '\$${resta.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (cambio > 0) ...[
                pw.Divider(borderStyle: pw.BorderStyle.dashed),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'EFECTIVO RECIBIDO',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      '\$${pagoCliente.toStringAsFixed(2)}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('CAMBIO', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(
                      '\$${cambio.toStringAsFixed(2)}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              ],
              pw.Divider(borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 5),
              if (resta > 0)
                pw.Text(
                  'TIENES 20 DÍAS PARA LIQUIDAR.',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              pw.Text(
                'NO HAY DEVOLUCIONES.',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 10),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Recibo_Apartado',
    );
  }

  void _devolverAStock(String idApartado) async {
    final sm = ScaffoldMessenger.of(context);
    bool? conf = await showDialog(
      context: context,
      builder: (contextDialog) => AlertDialog(
        title: const Text(
          '¿Devolver al stock?',
          style: TextStyle(color: Colors.red),
        ),
        content: const Text(
          'El cliente perderá el apartado y las prendas regresarán al inventario de venta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contextDialog, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(contextDialog, true),
            child: const Text('SÍ, DEVOLVER'),
          ),
        ],
      ),
    );

    if (conf == true) {
      if (mounted) {
        setState(() {
          _procesando = true;
        });
      }
      try {
        await http.post(
          Uri.parse('${ApiService.baseUrl}/pos/apartados/cancelar/$idApartado'),
        );
        if (!mounted) {
          return;
        }
        await _cargarApartados();
        sm.showSnackBar(
          const SnackBar(
            content: Text('Prendas devueltas al stock exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        debugPrint('Aviso devolver stock: $e');
      } finally {
        if (mounted) {
          setState(() {
            _procesando = false;
          });
        }
      }
    }
    // 🚨 Candado de Foco
    _buscadorFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 800;

    // 🎨 UI OPTIMIZADA: Formulario Dinámico de Nuevo Apartado
    Widget formNuevo = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DATOS DEL CLIENTE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _clienteController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Completo',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                    filled: true,
                    fillColor: Color(0xFFF9F9F9),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _telefonoController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono (Opcional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                    filled: true,
                    fillColor: Color(0xFFF9F9F9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ESCANEAR PRENDAS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _buscadorController,
                  focusNode: _buscadorFocus,
                  decoration: InputDecoration(
                    labelText: 'Escanear Código / QR',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.qr_code_scanner),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => _agregarPrenda(_buscadorController.text),
                    ),
                    filled: true,
                    fillColor: Color(0xFFF9F9F9),
                  ),
                  onSubmitted: _agregarPrenda,
                ),
                const SizedBox(height: 16),

                // 🚨 OPTIMIZACIÓN: shrinkWrap evita la cajita atrapada y hace un scroll natural en móviles
                if (_carritoApartado.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'Escanea prendas para apartar',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _carritoApartado.length,
                    separatorBuilder: (c, i) => const Divider(height: 1),
                    itemBuilder: (c, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              _carritoApartado[i]['foto_url'],
                              width: 45,
                              height: 45,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_carritoApartado[i]['sku']} - ${_carritoApartado[i]['nombre']}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Talla: ${_carritoApartado[i]['talla']}  |  Precio: \$${_carritoApartado[i]['precio']}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 🚨 CONTROLES DE CANTIDAD (+ / -)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  color: Colors.grey,
                                ),
                                onPressed: () => _modificarCantidad(i, -1),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_carritoApartado[i]['cantidad']}',
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
                                onPressed: () => _modificarCantidad(i, 1),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '\$${(_carritoApartado[i]['precio'] * _carritoApartado[i]['cantidad']).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _quitarDelCarrito(i),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cuponController,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Código Vendedor / Cupón',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(
                            Icons.local_offer_outlined,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
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
                      const Text(
                        'Subtotal',
                        style: TextStyle(color: Colors.grey),
                      ),
                      Text(
                        '\$${_subtotalApartado.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Descuento: $_vendedorAsociado',
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
                  const Divider(height: 20),
                ],

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL A PAGAR:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                    Text(
                      '\$${_totalApartado.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                TextField(
                  controller: _engancheController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Monto de Enganche Físico (\$)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payments_outlined),
                    filled: true,
                    fillColor: Color(0xFFF0FDF4),
                  ),
                ),
                const SizedBox(height: 15),

                const Text(
                  'MÉTODO DE PAGO:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _metodoPagoNuevo == 'Efectivo'
                              ? Colors.green.shade50
                              : Colors.transparent,
                          side: BorderSide(
                            color: _metodoPagoNuevo == 'Efectivo'
                                ? Colors.green
                                : Colors.grey.shade300,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: Icon(
                          Icons.money,
                          color: _metodoPagoNuevo == 'Efectivo'
                              ? Colors.green
                              : Colors.grey,
                          size: 16,
                        ),
                        label: Text(
                          'EFECT.',
                          style: TextStyle(
                            color: _metodoPagoNuevo == 'Efectivo'
                                ? Colors.green
                                : Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        onPressed: () =>
                            setState(() => _metodoPagoNuevo = 'Efectivo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _metodoPagoNuevo == 'Tarjeta MP'
                              ? Colors.blue.shade50
                              : Colors.transparent,
                          side: BorderSide(
                            color: _metodoPagoNuevo == 'Tarjeta MP'
                                ? Colors.blue
                                : Colors.grey.shade300,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: Icon(
                          Icons.credit_card,
                          color: _metodoPagoNuevo == 'Tarjeta MP'
                              ? Colors.blue
                              : Colors.grey,
                          size: 16,
                        ),
                        label: Text(
                          'TARJETA',
                          style: TextStyle(
                            color: _metodoPagoNuevo == 'Tarjeta MP'
                                ? Colors.blue
                                : Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        onPressed: () =>
                            setState(() => _metodoPagoNuevo = 'Tarjeta MP'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _metodoPagoNuevo == 'Transferencia'
                              ? Colors.purple.shade50
                              : Colors.transparent,
                          side: BorderSide(
                            color: _metodoPagoNuevo == 'Transferencia'
                                ? Colors.purple
                                : Colors.grey.shade300,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: Icon(
                          Icons.account_balance,
                          color: _metodoPagoNuevo == 'Transferencia'
                              ? Colors.purple
                              : Colors.grey,
                          size: 16,
                        ),
                        label: Text(
                          'TRANSF.',
                          style: TextStyle(
                            color: _metodoPagoNuevo == 'Transferencia'
                                ? Colors.purple
                                : Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        onPressed: () =>
                            setState(() => _metodoPagoNuevo = 'Transferencia'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: _procesando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.receipt_long),
                    label: const Text(
                      'GUARDAR E IMPRIMIR APARTADO',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    onPressed: _procesando ? null : _crearApartadoEImprimir,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );

    // 🎨 UI OPTIMIZADA: Gestión de Activos con Barras de Progreso
    Widget listaActivos = _apartadosActivos.isEmpty
        ? const Center(
            child: Text(
              "No hay apartados activos",
              style: TextStyle(color: Colors.grey),
            ),
          )
        : ListView.builder(
            itemCount: _apartadosActivos.length,
            itemBuilder: (c, i) {
              final apt = _apartadosActivos[i];

              String vistaCliente = apt['cliente']?.toString() ?? 'Cliente';
              String vendedorBadge = "";
              if (vistaCliente.contains(' | Vendedor:')) {
                var partes = vistaCliente.split(' | Vendedor:');
                vistaCliente = partes[0].trim();
                vendedorBadge = partes[1].trim();
              }

              // 🚨 CÁLCULO DE PROGRESO VISUAL
              double total = double.tryParse(apt['total'].toString()) ?? 0.0;
              double resta = double.tryParse(apt['resta'].toString()) ?? 0.0;
              double pagado = total - resta;
              double porcentaje = total > 0 ? (pagado / total) : 0.0;

              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.account_circle,
                                      size: 18,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        vistaCliente,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                if (vendedorBadge.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: Colors.blue.shade100,
                                      ),
                                    ),
                                    child: Text(
                                      'Vendedor: $vendedorBadge',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.blue.shade800,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                Text(
                                  apt['descripcion_prendas']?.toString() ??
                                      'Prendas varias',
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'FALTA POR PAGAR',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                '\$${apt['resta']}',
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 🚨 BARRA DE PROGRESO DE PAGO
                      Row(
                        children: [
                          Text(
                            '\$${pagado.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: porcentaje,
                                minHeight: 8,
                                backgroundColor: Colors.grey.shade200,
                                color: porcentaje > 0.7
                                    ? Colors.green
                                    : Colors.blue,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '\$${total.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(
                                  color: Colors.redAccent,
                                  width: 1.5,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(
                                Icons.assignment_return_outlined,
                                size: 16,
                              ),
                              label: const Text(
                                'DEVOLVER A STOCK',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              onPressed: () =>
                                  _devolverAStock(apt['id'].toString()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(
                                Icons.payments_outlined,
                                size: 16,
                              ),
                              label: const Text(
                                'INGRESAR ABONO / COBRAR',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              onPressed: () =>
                                  _abrirDialogoLiquidarOAbonar(apt),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );

    return DefaultTabController(
      length: 2,
      child: Container(
        color: const Color(0xFFF6F8FA),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SISTEMA DE APARTADOS',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              TabBar(
                labelColor: Colors.black,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.black,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
                tabs: const [
                  Tab(text: 'NUEVO APARTADO'),
                  Tab(text: 'GESTIONAR ACTIVOS'),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(child: TabBarView(children: [formNuevo, listaActivos])),
            ],
          ),
        ),
      ),
    );
  }
}
