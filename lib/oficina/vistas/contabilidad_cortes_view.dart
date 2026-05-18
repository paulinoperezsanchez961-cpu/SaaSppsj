import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';

class ContabilidadCortesView extends StatefulWidget {
  const ContabilidadCortesView({super.key});

  @override
  State<ContabilidadCortesView> createState() => _ContabilidadCortesViewState();
}

class _ContabilidadCortesViewState extends State<ContabilidadCortesView> {
  List<dynamic> _historialCortesTodos = [];
  List<dynamic> _gastosFijos = [];

  // 🚨 SISTEMA MULTI-SUCURSAL
  List<String> _sucursalesDisponibles = ['Todas'];
  String _sucursalSeleccionada = 'Todas';

  bool _cargando = true;

  final TextEditingController _conceptoGastoCtrl = TextEditingController();
  final TextEditingController _montoGastoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    setState(() {
      _cargando = true;
    });

    final cortes = await ApiService.obtenerHistorialCortes();
    final gastos = await ApiService.obtenerGastosFijos();

    if (!mounted) {
      return;
    }

    // 🚨 EXTRAER SUCURSALES ÚNICAS DEL HISTORIAL DE CORTES
    Set<String> sucursalesSet = {'Todas'};
    for (var corte in cortes) {
      String nombreSucursal = corte['sucursal_nombre'] ?? 'Sin Sucursal';
      sucursalesSet.add(nombreSucursal);
    }

    setState(() {
      _historialCortesTodos = cortes;
      _gastosFijos = gastos;
      _sucursalesDisponibles = sucursalesSet.toList();

      // Si la sucursal seleccionada previamente ya no existe (raro, pero seguro), volvemos a 'Todas'
      if (!_sucursalesDisponibles.contains(_sucursalSeleccionada)) {
        _sucursalSeleccionada = 'Todas';
      }

      _cargando = false;
    });
  }

  // 🚨 FILTRO INTELIGENTE POR SUCURSAL
  List<dynamic> get _cortesFiltrados {
    if (_sucursalSeleccionada == 'Todas') {
      return _historialCortesTodos;
    }
    return _historialCortesTodos.where((c) {
      String nombre = c['sucursal_nombre'] ?? 'Sin Sucursal';
      return nombre == _sucursalSeleccionada;
    }).toList();
  }

  Future<void> _guardarGastoFijo() async {
    if (_conceptoGastoCtrl.text.isEmpty || _montoGastoCtrl.text.isEmpty) {
      return;
    }
    double monto = double.tryParse(_montoGastoCtrl.text) ?? 0;

    final sm = ScaffoldMessenger.of(context);
    bool exito = await ApiService.agregarGastoFijo(
      _conceptoGastoCtrl.text,
      monto,
    );

    if (exito) {
      _conceptoGastoCtrl.clear();
      _montoGastoCtrl.clear();
      _cargarTodo();
      sm.showSnackBar(
        const SnackBar(
          content: Text('Gasto agregado'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _eliminarGastoFijo(int id) async {
    bool exito = await ApiService.eliminarGastoFijo(id);
    if (exito) {
      _cargarTodo();
    }
  }

  // =========================================================================
  // 🖨️ MOTOR DE REIMPRESIÓN DEL CORTE DE CAJA HISTÓRICO (SAAS)
  // =========================================================================
  Future<void> _reimprimirCorteCaja(Map<String, dynamic> c) async {
    final ventasTotales = double.tryParse(c['ventas_totales'].toString()) ?? 0;
    final ventasEfectivo =
        double.tryParse(c['ventas_efectivo']?.toString() ?? '0') ?? 0;
    final ventasTarjeta =
        double.tryParse(c['ventas_tarjeta']?.toString() ?? '0') ?? 0;
    final ventasTransferencia =
        double.tryParse(c['ventas_transferencia']?.toString() ?? '0') ?? 0;
    final gastos = double.tryParse(c['gastos_totales'].toString()) ?? 0;
    final entregaFisicaCajero = ventasEfectivo - gastos;
    final nombreSucursal = c['sucursal_nombre'] ?? 'Mostrador';

    Map<String, dynamic> jsonDetalles = {};
    try {
      jsonDetalles = jsonDecode(c['detalles'] ?? '{}');
    } catch (e) {
      debugPrint('Aviso JSON: $e');
    }

    List items = jsonDetalles['items'] ?? [];
    List apartados = jsonDetalles['apartados'] ?? [];
    List cambios = jsonDetalles['cambios'] ?? [];
    List gastosDetalle = jsonDetalles['gastos'] ?? [];
    int totalPiezas = jsonDetalles['piezas'] ?? 0;

    if (totalPiezas == 0 && items.isNotEmpty) {
      for (var i in items) {
        totalPiezas += (int.tryParse(i['cantidad']?.toString() ?? '1') ?? 1);
      }
    }

    final doc = pw.Document();
    pw.MemoryImage? imageLogo;

    // 🚨 1. CARGAMOS CONFIGURACIÓN SAAS
    final prefs = await SharedPreferences.getInstance();
    final String logoUrl = prefs.getString('caja_logo_empresa') ?? '';
    final String nombreEmpresa =
        prefs.getString('caja_nombre_empresa') ?? 'MI NEGOCIO';
    final double anchoImpresora =
        prefs.getDouble('caja_ancho_impresora') ?? 80.0;

    if (logoUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(logoUrl));
        if (response.statusCode == 200) {
          imageLogo = pw.MemoryImage(response.bodyBytes);
        }
      } catch (e) {
        debugPrint('Aviso Logo SaaS: $e');
      }
    }

    final fechaHora = c['fecha_formateada'] ?? 'Sin fecha';

    // 🚨 3. ESCALADO INTELIGENTE SEGÚN IMPRESORA
    double fBase = anchoImpresora == 58.0 ? 7.0 : 9.0;
    double fTitle = anchoImpresora == 58.0 ? 11.0 : 14.0;
    double fSubtitle = anchoImpresora == 58.0 ? 8.0 : 10.0;
    double fSmall = anchoImpresora == 58.0 ? 6.0 : 8.0;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          anchoImpresora * PdfPageFormat.mm,
          double.infinity,
          marginAll: 5 * PdfPageFormat.mm,
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              if (imageLogo != null)
                pw.Image(
                  imageLogo,
                  width: anchoImpresora == 58.0 ? 35 : 45,
                  height: anchoImpresora == 58.0 ? 35 : 45,
                ),
              pw.SizedBox(height: 5),
              pw.Text(
                'COPIA - CORTE DE CAJA',
                style: pw.TextStyle(
                  fontSize: fTitle,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                '$nombreEmpresa - ${nombreSucursal.toUpperCase()}',
                style: pw.TextStyle(fontSize: fSubtitle),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 5),
              pw.Text(fechaHora, style: pw.TextStyle(fontSize: fBase)),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),

              if (items.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text(
                  'VENTAS DEL DÍA ($totalPiezas PZS)',
                  style: pw.TextStyle(
                    fontSize: fSubtitle,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                ...items.map((item) {
                  String line = item['nombre'].toString();
                  String itemsVendidos = line.split('| Vendedor:')[0];
                  String vendedor = line.split('| Vendedor:').length > 1
                      ? line.split('| Vendedor:')[1]
                      : '';

                  return pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        itemsVendidos.replaceAll('c/u.', 'c/u\n'),
                        style: pw.TextStyle(fontSize: fBase),
                      ),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            '${item['metodo'] ?? 'Efectivo'}',
                            style: pw.TextStyle(
                              fontSize: fBase,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.black,
                            ),
                          ),
                          pw.Text(
                            vendedor != '' ? 'Vend: $vendedor' : '',
                            style: pw.TextStyle(
                              fontSize: fBase,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.end,
                        children: [
                          pw.Text(
                            '\$${(item['precio'] as num).toDouble().toStringAsFixed(2)}',
                            style: pw.TextStyle(
                              fontSize: fSubtitle,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                    ],
                  );
                }),
                pw.Divider(borderStyle: pw.BorderStyle.dashed),
              ],

              if (apartados.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text(
                  'APARTADOS Y ABONOS',
                  style: pw.TextStyle(
                    fontSize: fSubtitle,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                ...apartados.map(
                  (item) => pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          '${item['tipo']} - ${item['cliente']}',
                          style: pw.TextStyle(fontSize: fBase),
                        ),
                      ),
                      pw.Text(
                        '\$${(item['monto'] as num).toDouble().toStringAsFixed(2)}',
                        style: pw.TextStyle(fontSize: fBase),
                      ),
                    ],
                  ),
                ),
                pw.Divider(borderStyle: pw.BorderStyle.dashed),
              ],

              if (cambios.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text(
                  'CAMBIOS REALIZADOS',
                  style: pw.TextStyle(
                    fontSize: fSubtitle,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                ...cambios.map(
                  (item) => pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Entró: ${item['entra']}',
                        style: pw.TextStyle(fontSize: fBase),
                      ),
                      pw.Text(
                        'Salió: ${item['sale']}',
                        style: pw.TextStyle(fontSize: fBase),
                      ),
                      pw.Text(
                        'Motivo: ${item['motivo']}',
                        style: pw.TextStyle(
                          fontSize: fSmall,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                    ],
                  ),
                ),
                pw.Divider(borderStyle: pw.BorderStyle.dashed),
              ],

              if (gastosDetalle.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text(
                  'DETALLE DE GASTOS',
                  style: pw.TextStyle(
                    fontSize: fSubtitle,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                ...gastosDetalle.map(
                  (item) => pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          '${item['concepto']} (${item['hora'] ?? ''})',
                          style: pw.TextStyle(fontSize: fBase),
                        ),
                      ),
                      pw.Text(
                        '-\$${(item['monto'] as num).toDouble().toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: fBase,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Divider(borderStyle: pw.BorderStyle.dashed),
              ],

              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '+ VENTAS TOTALES',
                    style: pw.TextStyle(fontSize: fSubtitle),
                  ),
                  pw.Text(
                    '\$${ventasTotales.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontSize: fSubtitle),
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '  💳 En Tarjeta',
                    style: pw.TextStyle(
                      fontSize: fBase,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Text(
                    '\$${ventasTarjeta.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: fBase,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '  📱 En Transf.',
                    style: pw.TextStyle(
                      fontSize: fBase,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Text(
                    '\$${ventasTransferencia.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: fBase,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '  💵 En Efectivo',
                    style: pw.TextStyle(
                      fontSize: fBase,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Text(
                    '\$${ventasEfectivo.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: fBase,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '- GASTOS FISICOS',
                    style: pw.TextStyle(fontSize: fSubtitle),
                  ),
                  pw.Text(
                    '\$${gastos.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontSize: fSubtitle),
                  ),
                ],
              ),
              pw.Divider(borderStyle: pw.BorderStyle.dashed),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'ENTREGA FÍSICA',
                    style: pw.TextStyle(
                      fontSize: fTitle,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '\$${entregaFisicaCajero.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: fTitle,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => await doc.save(),
      name: 'Copia_Corte_${c['id']}',
    );
  }

  // =========================================================================
  // 🧩 WIDGETS INTERNOS DE UI
  // =========================================================================
  Widget _dibujarDesgloseAvanzado(Map<String, dynamic> json) {
    List items = json['items'] ?? [];
    List apartados = json['apartados'] ?? [];
    List cambios = json['cambios'] ?? [];
    List gastosDetalle = json['gastos'] ?? [];

    if (items.isEmpty &&
        apartados.isEmpty &&
        cambios.isEmpty &&
        gastosDetalle.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text(
          "Corte ciego (Sin registros en bitácora).",
          style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isNotEmpty) ...[
          const Text(
            '👕 VENTAS DEL TURNO',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          ...items.map((i) {
            String nombreRaw = i['nombre']?.toString() ?? '';
            String precioRaw = i['precio']?.toString() ?? '0';
            String metodoPago = i['metodo']?.toString() ?? 'Efectivo';

            if (nombreRaw.contains('[SKU:')) {
              List<String> partesVendedor = nombreRaw.split('| Vendedor:');
              String itemsVenta = partesVendedor[0];
              String vendedor = partesVendedor.length > 1
                  ? partesVendedor[1].trim()
                  : 'Mostrador General';
              List<String> lineasItems = itemsVenta.split('c/u.');

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...lineasItems.where((l) => l.trim().isNotEmpty).map((
                      linea,
                    ) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Text(
                          '• ${linea.trim()} c/u',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                      );
                    }),
                    const Divider(height: 16, color: Colors.black12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                metodoPago,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.person,
                                    size: 12,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    vendedor,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'Total: \$$precioRaw',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            } else {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Text(
                  '- $nombreRaw (\$$precioRaw)',
                  style: const TextStyle(fontSize: 11),
                ),
              );
            }
          }),
          const SizedBox(height: 16),
        ],

        if (gastosDetalle.isNotEmpty) ...[
          const Text(
            '💸 GASTOS REGISTRADOS',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          ...gastosDetalle.map((g) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      g['concepto'].toString(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.red.shade900,
                      ),
                    ),
                  ),
                  Text(
                    '-\$${g['monto']}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.red.shade900,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
        ],

        if (apartados.isNotEmpty) ...[
          const Text(
            '🛍️ APARTADOS Y ABONOS',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.orange,
            ),
          ),
          const SizedBox(height: 8),
          ...apartados.map((a) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        a['tipo'].toString().replaceAll('_', ' '),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                        ),
                      ),
                      Text(
                        '+\$${a['monto']}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    a['cliente'].toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
        ],

        if (cambios.isNotEmpty) ...[
          const Text(
            '🔄 CAMBIOS FÍSICOS',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.purple,
            ),
          ),
          const SizedBox(height: 8),
          ...cambios.map(
            (c) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.shade100),
              ),
              child: Text(
                'Entró: ${c['entra']}\nSalió: ${c['sale']}\nMotivo: ${c['motivo']}',
                style: TextStyle(fontSize: 12, color: Colors.purple.shade900),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // 🚨 UI: LISTADO DE CORTES POR SUCURSAL
  Widget _buildListaCortes() {
    final cortes = _cortesFiltrados;

    if (cortes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 60,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              _sucursalSeleccionada == 'Todas'
                  ? "Aún no se han registrado cortes de caja"
                  : "No hay cortes registrados para $_sucursalSeleccionada",
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: cortes.length,
      itemBuilder: (context, index) {
        final c = cortes[index];

        final ventasTotales =
            double.tryParse(c['ventas_totales'].toString()) ?? 0;
        final ventasEfectivo =
            double.tryParse(c['ventas_efectivo']?.toString() ?? '0') ?? 0;
        final ventasTarjeta =
            double.tryParse(c['ventas_tarjeta']?.toString() ?? '0') ?? 0;
        final ventasTransferencia =
            double.tryParse(c['ventas_transferencia']?.toString() ?? '0') ?? 0;
        final gastos = double.tryParse(c['gastos_totales'].toString()) ?? 0;
        final entregaFisicaCajero = ventasEfectivo - gastos;

        Map<String, dynamic> jsonDetalles = {};
        try {
          jsonDetalles = jsonDecode(c['detalles'] ?? '{}');
        } catch (e) {
          debugPrint('Parse error');
        }

        List items = jsonDetalles['items'] ?? [];
        List apartados = jsonDetalles['apartados'] ?? [];
        List cambios = jsonDetalles['cambios'] ?? [];
        int piezasCount = jsonDetalles['piezas'] ?? 0;

        if (piezasCount == 0 && items.isNotEmpty) {
          for (var i in items) {
            piezasCount +=
                (int.tryParse(i['cantidad']?.toString() ?? '1') ?? 1);
          }
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            title: Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  c['fecha_formateada'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                if (_sucursalSeleccionada == 'Todas')
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Text(
                      c['sucursal_nombre'] ?? 'Mostrador',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Wrap(
                spacing: 10,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'FÍSICO A ENTREGAR: \$${entregaFisicaCajero.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Colors.green.shade900,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    'Total Operado: \$${ventasTotales.toStringAsFixed(2)} | Resp: ${c['cajero']}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                padding: const EdgeInsets.all(16),
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'EFECTIVO',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '\$${ventasEfectivo.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.green,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'TARJETA',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '\$${ventasTarjeta.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.purple.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'TRANSF.',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '\$${ventasTransferencia.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.purple,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade100),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'GASTOS FISICOS EN CAJA',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '-\$${gastos.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Text(
                                '👕 PIEZAS',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '$piezasCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            height: 30,
                            width: 1,
                            color: Colors.white24,
                          ),
                          Column(
                            children: [
                              const Text(
                                '🛍️ APARTADOS',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${apartados.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            height: 30,
                            width: 1,
                            color: Colors.white24,
                          ),
                          Column(
                            children: [
                              const Text(
                                '🔄 CAMBIOS',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${cambios.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.print, size: 18),
                        label: const Text(
                          'REIMPRIMIR CORTE DE CAJA',
                          style: TextStyle(
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () => _reimprimirCorteCaja(c),
                      ),
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Divider(color: Colors.black26),
                    ),

                    _dibujarDesgloseAvanzado(jsonDetalles),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPestanaGastosFijos(bool isMobile) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey.shade50,
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _conceptoGastoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Concepto (Ej. Renta, Luz)',
                        isDense: true,
                        border: OutlineInputBorder(),
                        fillColor: Colors.white,
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _montoGastoCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '\$ Monto Semanal',
                              isDense: true,
                              border: OutlineInputBorder(),
                              fillColor: Colors.white,
                              filled: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _guardarGastoFijo,
                          child: const Text('AGREGAR'),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _conceptoGastoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Concepto (Ej. Renta, Luz)',
                          isDense: true,
                          border: OutlineInputBorder(),
                          fillColor: Colors.white,
                          filled: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _montoGastoCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '\$ Monto Semanal',
                          isDense: true,
                          border: OutlineInputBorder(),
                          fillColor: Colors.white,
                          filled: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _guardarGastoFijo,
                      child: const Text('AGREGAR'),
                    ),
                  ],
                ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _gastosFijos.isEmpty
              ? const Center(child: Text("Sin gastos fijos configurados"))
              : ListView.builder(
                  itemCount: _gastosFijos.length,
                  itemBuilder: (c, i) => ListTile(
                    title: Text(
                      _gastosFijos[i]['concepto'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '\$${_gastosFijos[i]['monto']}',
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.grey,
                            size: 18,
                          ),
                          onPressed: () =>
                              _eliminarGastoFijo(_gastosFijos[i]['id']),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 800;

    return DefaultTabController(
      length: 2, // 🚨 AHORA SOLO 2 PESTAÑAS (CORTES Y GASTOS FIJOS)
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Padding(
          padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
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
                        Text(
                          'CONTABILIDAD MULTI-SUCURSAL',
                          style: TextStyle(
                            fontSize: isMobile ? 20 : 24,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Auditoría y control de efectivo estructurada por puntos de venta.',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _cargarTodo,
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('ACTUALIZAR'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              const TabBar(
                labelColor: Colors.black,
                indicatorColor: Colors.black,
                tabs: [
                  Tab(text: 'HISTORIAL DE CORTES POR SUCURSAL'),
                  Tab(text: 'GASTOS FIJOS SEMANALES'),
                ],
              ),
              const SizedBox(height: 20),

              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: _cargando
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.black),
                        )
                      : TabBarView(
                          children: [
                            // 🚨 PESTAÑA 1: CORTES CON SELECTOR DE SUCURSAL
                            Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    border: const Border(
                                      bottom: BorderSide(color: Colors.black12),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.storefront,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 10),
                                      const Text(
                                        'Filtrar por: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: _sucursalSeleccionada,
                                            isExpanded: true,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black,
                                              fontSize: 16,
                                            ),
                                            items: _sucursalesDisponibles.map((
                                              String sucursal,
                                            ) {
                                              return DropdownMenuItem<String>(
                                                value: sucursal,
                                                child: Text(sucursal),
                                              );
                                            }).toList(),
                                            onChanged: (String? nuevaSucursal) {
                                              if (nuevaSucursal != null) {
                                                setState(() {
                                                  _sucursalSeleccionada =
                                                      nuevaSucursal;
                                                });
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(child: _buildListaCortes()),
                              ],
                            ),

                            // PESTAÑA 2: GASTOS FIJOS
                            _buildPestanaGastosFijos(isMobile),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
