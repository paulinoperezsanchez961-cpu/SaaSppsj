import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../../services/api_service.dart';

class OficinaVipView extends StatefulWidget {
  const OficinaVipView({super.key});

  @override
  State<OficinaVipView> createState() => _OficinaVipViewState();
}

class _OficinaVipViewState extends State<OficinaVipView> {
  // Configuración de Cashback
  double _bonoBienvenida = 150.0;
  double _plEfe = 5.0, _orEfe = 10.0, _tiEfe = 15.0;
  double _plTar = 2.0, _orTar = 5.0, _tiTar = 8.0;

  List<dynamic> _clientes = [];
  List<dynamic> _clientesFiltrados =
      []; // 🚨 NUEVO: Para el buscador inteligente
  final TextEditingController _buscadorCtrl = TextEditingController();

  bool _cargandoTodo = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _buscadorCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    final config = await ApiService.obtenerConfiguracionVIP();
    final clientes = await ApiService.obtenerClientesVIP();

    if (mounted) {
      setState(() {
        if (config.isNotEmpty) {
          _bonoBienvenida =
              double.tryParse(config['bono_bienvenida']?.toString() ?? '150') ??
              150.0;
          _plEfe =
              double.tryParse(
                config['cashback_plata_efectivo']?.toString() ?? '5',
              ) ??
              5.0;
          _plTar =
              double.tryParse(
                config['cashback_plata_tarjeta']?.toString() ?? '2',
              ) ??
              2.0;
          _orEfe =
              double.tryParse(
                config['cashback_oro_efectivo']?.toString() ?? '10',
              ) ??
              10.0;
          _orTar =
              double.tryParse(
                config['cashback_oro_tarjeta']?.toString() ?? '5',
              ) ??
              5.0;
          _tiEfe =
              double.tryParse(
                config['cashback_titanio_efectivo']?.toString() ?? '15',
              ) ??
              15.0;
          _tiTar =
              double.tryParse(
                config['cashback_titanio_tarjeta']?.toString() ?? '8',
              ) ??
              8.0;
        }
        _clientes = clientes;
        _clientesFiltrados = clientes;
        _cargandoTodo = false;
      });
    }
  }

  // 🚨 NUEVO: Motor de Búsqueda Dinámico
  void _filtrarClientes(String query) {
    if (query.isEmpty) {
      setState(() => _clientesFiltrados = List.from(_clientes));
      return;
    }
    final q = query.toLowerCase();
    setState(() {
      _clientesFiltrados = _clientes.where((c) {
        final nombre = (c['nombre'] ?? '').toString().toLowerCase();
        final nivel = (c['nivel_vip'] ?? '').toString().toLowerCase();
        return nombre.contains(q) || nivel.contains(q);
      }).toList();
    });
  }

  Future<void> _guardarConfiguracion() async {
    setState(() {
      _guardando = true;
    });

    final exito = await ApiService.guardarConfiguracionVIP(
      _bonoBienvenida,
      _plEfe,
      _plTar,
      _orEfe,
      _orTar,
      _tiEfe,
      _tiTar,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _guardando = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          exito ? '✅ Ajustes guardados correctamente.' : '❌ Error al guardar.',
        ),
        backgroundColor: exito ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _eliminarCliente(int id) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctxDialog) => AlertDialog(
        title: const Text('Eliminar Cliente'),
        content: const Text(
          '¿Deseas eliminar este cliente y sus puntos acumulados?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctxDialog, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctxDialog, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      final exito = await ApiService.eliminarClienteVIP(id);
      if (exito) {
        _cargarDatos();
      }
    }
  }

  // 🚨 NUEVO: Conexión con el endpoint "huérfano" de la API
  Future<void> _hacerSorteo(String nivel) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    final res = await ApiService.sortearVIP(nivel);

    if (!mounted) {
      return;
    }
    Navigator.pop(context);

    if (res['exito'] == true && res['ganador'] != null) {
      final ganador = res['ganador'];
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: const [
              Icon(Icons.celebration, color: Colors.deepPurple, size: 30),
              SizedBox(width: 10),
              Text(
                '¡TENEMOS GANADOR!',
                style: TextStyle(
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('El sistema ha elegido al azar al siguiente cliente:'),
              const SizedBox(height: 20),
              Text(
                ganador['nombre'].toString().toUpperCase(),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 5),
              Chip(
                label: Text(
                  ganador['nivel_vip'].toString().toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: Colors.deepPurple,
              ),
              const SizedBox(height: 15),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.phone),
                title: const Text('Teléfono'),
                subtitle: Text(
                  ganador['telefono']?.toString() ?? 'No registrado',
                ),
                dense: true,
              ),
              ListTile(
                leading: const Icon(Icons.email),
                title: const Text('Correo'),
                subtitle: Text(ganador['email']?.toString() ?? 'No registrado'),
                dense: true,
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('¡EXCELENTE!'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No hay suficientes clientes activos en el nivel ${nivel.toUpperCase()} para hacer un sorteo.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ===========================================================================
  // 🏭 FASE 1: GENERADOR DE LOTES DE STOCK (SÓLO PVC CR80)
  // ===========================================================================

  void _mostrarDialogoLotes(String nivel) {
    TextEditingController cantidadCtrl = TextEditingController(text: '50');

    showDialog(
      context: context,
      builder: (BuildContext ctxDialog) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Generar Lote: Tarjeta ${nivel.toUpperCase()}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingresa la cantidad de tarjetas vírgenes a mandar a imprenta.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: cantidadCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Cantidad a imprimir',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.style),
                isDense: true,
              ),
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Se generará un PDF en tamaño Tarjeta de Crédito (CR80) estándar.',
                      style: TextStyle(fontSize: 11, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctxDialog),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              int cant = int.tryParse(cantidadCtrl.text) ?? 0;
              if (cant > 0) {
                Navigator.pop(ctxDialog);
                _generarLotePDF(nivel, cant);
              }
            },
            child: const Text('CREAR PDF DE STOCK'),
          ),
        ],
      ),
    );
  }

  Future<void> _generarLotePDF(String nivel, int cantidad) async {
    setState(() {
      _guardando = true;
    });

    final pdf = pw.Document();

    PdfColor bgColor = const PdfColor.fromInt(0xFFE8E8E8); // Plata
    PdfColor accentColor = const PdfColor.fromInt(0xFF010101);
    PdfColor borderOpacity = const PdfColor(0.01, 0.01, 0.01, 0.3);
    String prefijo = '1';

    if (nivel == 'oro') {
      bgColor = const PdfColor.fromInt(0xFFD4AF37);
      prefijo = '2';
    }

    final prefs = await SharedPreferences.getInstance();
    final String logoUrl = prefs.getString('caja_logo_empresa') ?? '';
    final String nombreEmpresa =
        prefs.getString('caja_nombre_empresa') ?? 'SISTEMA VIP';

    pw.MemoryImage? logoImage;
    if (logoUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(logoUrl));
        if (response.statusCode == 200) {
          logoImage = pw.MemoryImage(response.bodyBytes);
        }
      } catch (e) {
        debugPrint("Error descargando logo VIP: $e");
      }
    }

    for (int i = 0; i < cantidad; i++) {
      final String uniqueId =
          "$prefijo-${DateTime.now().microsecondsSinceEpoch.toString().substring(8)}-${(100 + (i % 899))}";

      // Frente de la Tarjeta
      pdf.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(
            85.6 * PdfPageFormat.mm,
            53.98 * PdfPageFormat.mm,
            marginAll: 0,
          ),
          build: (pw.Context ctx) => pw.Container(
            padding: const pw.EdgeInsets.all(3),
            decoration: pw.BoxDecoration(color: bgColor),
            child: pw.Container(
              padding: const pw.EdgeInsets.all(2),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: borderOpacity, width: 1.5),
              ),
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: borderOpacity, width: 0.5),
                ),
                child: pw.Center(
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      if (logoImage != null)
                        pw.Image(logoImage, width: 65, height: 65)
                      else
                        pw.Text(
                          nombreEmpresa,
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                      pw.SizedBox(height: 18),
                      pw.Text(
                        "CLIENTE DISTINGUIDO",
                        style: pw.TextStyle(
                          fontSize: 6.5,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1.2,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Reverso de la Tarjeta
      pdf.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(
            85.6 * PdfPageFormat.mm,
            53.98 * PdfPageFormat.mm,
            marginAll: 0,
          ),
          build: (pw.Context ctx) => pw.Container(
            padding: const pw.EdgeInsets.all(3),
            decoration: pw.BoxDecoration(color: bgColor),
            child: pw.Container(
              padding: const pw.EdgeInsets.all(2),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: borderOpacity, width: 1.5),
              ),
              child: pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: borderOpacity, width: 0.5),
                ),
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      "PRESENTA ESTA TARJETA PARA OBTENER TUS BENEFICIOS",
                      style: pw.TextStyle(
                        fontSize: 6,
                        fontWeight: pw.FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                    pw.Center(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(3),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: uniqueId,
                          width: 80,
                          height: 80,
                        ),
                      ),
                    ),
                    pw.Text(
                      "ID: $uniqueId",
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _guardando = false;
      });
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Lotes_VIP_$nivel',
    );
  }

  // ===========================================================================
  // 👑 REIMPRESIÓN TITANIO (EDICIÓN ESPECIAL PERSONALIZADA SAAS)
  // ===========================================================================

  void _prepararImpresionTitanio(dynamic cliente) {
    showDialog(
      context: context,
      builder: (BuildContext ctxDialog) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Imprimir Tarjeta Titanio Black'),
        content: const Text(
          'Se generará el archivo PDF en formato estándar PVC de Tarjeta de Crédito (CR80) listo para imprenta.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctxDialog),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctxDialog);
              _generarPdfTitanioPersonalizada(cliente);
            },
            child: const Text('GENERAR PDF'),
          ),
        ],
      ),
    );
  }

  Future<void> _generarPdfTitanioPersonalizada(dynamic cliente) async {
    final pdf = pw.Document();
    final String nombre = cliente['nombre'].toString().toUpperCase();
    final String qrData = cliente['qr_hash'] ?? 'ERROR';
    final DateTime hoy = DateTime.now();
    final String emitido =
        "${hoy.day.toString().padLeft(2, '0')}/${hoy.month.toString().padLeft(2, '0')}/${hoy.year}";
    final String vence =
        "${hoy.day.toString().padLeft(2, '0')}/${hoy.month.toString().padLeft(2, '0')}/${hoy.year + 1}";

    PdfColor bgColor = const PdfColor.fromInt(0xFF222222);
    PdfColor accentColor = const PdfColor.fromInt(0xFFF5F5F5);
    PdfColor accentColorMuted = const PdfColor(0.96, 0.96, 0.96, 0.7);
    PdfColor borderOpacity = const PdfColor(0.95, 0.95, 0.95, 0.3);

    final prefs = await SharedPreferences.getInstance();
    final String logoUrl = prefs.getString('caja_logo_empresa') ?? '';
    final String nombreEmpresa =
        prefs.getString('caja_nombre_empresa') ?? 'SISTEMA VIP';

    pw.MemoryImage? logoImage;
    if (logoUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(logoUrl));
        if (response.statusCode == 200) {
          logoImage = pw.MemoryImage(response.bodyBytes);
        }
      } catch (e) {
        debugPrint("Error descargando logo VIP: $e");
      }
    }

    // FRENTE PVC (CR80: 85.6 x 53.98 mm)
    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          85.6 * PdfPageFormat.mm,
          53.98 * PdfPageFormat.mm,
          marginAll: 0,
        ),
        build: (pw.Context ctx) => pw.Container(
          padding: const pw.EdgeInsets.all(3),
          decoration: pw.BoxDecoration(color: bgColor),
          child: pw.Container(
            padding: const pw.EdgeInsets.all(2),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: borderOpacity, width: 1.5),
            ),
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: borderOpacity, width: 0.5),
              ),
              child: pw.Center(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    if (logoImage != null)
                      pw.Image(logoImage, width: 60, height: 60)
                    else
                      pw.Text(
                        nombreEmpresa,
                        style: pw.TextStyle(
                          fontSize: 16,
                          color: accentColor,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    pw.SizedBox(height: 15),
                    pw.Text(
                      nombre,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.5,
                        color: accentColor,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      "SOCIO DISTINGUIDO",
                      style: pw.TextStyle(fontSize: 5, color: accentColorMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // REVERSO PVC
    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          85.6 * PdfPageFormat.mm,
          53.98 * PdfPageFormat.mm,
          marginAll: 0,
        ),
        build: (pw.Context ctx) => pw.Container(
          padding: const pw.EdgeInsets.all(3),
          decoration: pw.BoxDecoration(color: bgColor),
          child: pw.Container(
            padding: const pw.EdgeInsets.all(2),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: borderOpacity, width: 1.5),
            ),
            child: pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: borderOpacity, width: 0.5),
              ),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    "PRESENTA ESTA TARJETA PARA OBTENER TUS BENEFICIOS",
                    style: pw.TextStyle(
                      fontSize: 5,
                      fontWeight: pw.FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                  pw.Center(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(3),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: qrData,
                        width: 65,
                        height: 65,
                      ),
                    ),
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            "EMITIDA",
                            style: pw.TextStyle(
                              fontSize: 4,
                              color: accentColorMuted,
                            ),
                          ),
                          pw.Text(
                            emitido,
                            style: pw.TextStyle(
                              fontSize: 6,
                              fontWeight: pw.FontWeight.bold,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                      pw.Text(
                        "ID: $qrData",
                        style: pw.TextStyle(
                          fontSize: 6,
                          fontWeight: pw.FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            "VENCE",
                            style: pw.TextStyle(
                              fontSize: 4,
                              color: accentColorMuted,
                            ),
                          ),
                          pw.Text(
                            vence,
                            style: pw.TextStyle(
                              fontSize: 6,
                              fontWeight: pw.FontWeight.bold,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Titanio_Black_$nombre',
    );
  }

  // ===========================================================================
  // INTERFAZ DE USUARIO
  // ===========================================================================

  Widget _construirTarjetaConfigDual(
    String titulo,
    double valEfe,
    Function(double) onEfe,
    double valTar,
    Function(double) onTar,
    Color colorBase,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: colorBase,
              fontSize: 16,
            ),
          ),
          const Divider(height: 20),
          Row(
            children: [
              const Icon(Icons.payments, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: valEfe,
                  min: 0,
                  max: 50,
                  divisions: 50,
                  activeColor: Colors.green,
                  label: '${valEfe.toInt()}%',
                  onChanged: onEfe,
                ),
              ),
              Text(
                '${valEfe.toInt()}%',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.credit_card, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: valTar,
                  min: 0,
                  max: 50,
                  divisions: 50,
                  activeColor: Colors.blue,
                  label: '${valTar.toInt()}%',
                  onChanged: onTar,
                ),
              ),
              Text(
                '${valTar.toInt()}%',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF9F9F9),
        appBar: AppBar(
          title: const Text(
            'CONTROL VIP Y RECOMPENSAS',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5),
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.black,
            indicatorColor: Colors.black,
            tabs: [
              Tab(icon: Icon(Icons.settings), text: 'AJUSTES CASHBACK'),
              Tab(icon: Icon(Icons.people), text: 'BASE DE DATOS CLIENTES'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // PESTAÑA 1: CONFIGURACIÓN
            _cargandoTodo
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Bono Inicial de Bienvenida',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.green,
                                  fontSize: 16,
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Slider(
                                      value: _bonoBienvenida,
                                      min: 0,
                                      max: 500,
                                      divisions: 100,
                                      activeColor: Colors.green,
                                      label: '\$${_bonoBienvenida.toInt()}',
                                      onChanged: (v) =>
                                          setState(() => _bonoBienvenida = v),
                                    ),
                                  ),
                                  Text(
                                    '\$${_bonoBienvenida.toInt()}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        GridView.count(
                          crossAxisCount:
                              MediaQuery.of(context).size.width > 800 ? 2 : 1,
                          crossAxisSpacing: 24,
                          mainAxisSpacing: 24,
                          shrinkWrap: true,
                          childAspectRatio: 2.2,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _construirTarjetaConfigDual(
                              'Nivel Plata',
                              _plEfe,
                              (v) => setState(() => _plEfe = v),
                              _plTar,
                              (v) => setState(() => _plTar = v),
                              Colors.blueGrey,
                            ),
                            _construirTarjetaConfigDual(
                              'Nivel Oro',
                              _orEfe,
                              (v) => setState(() => _orEfe = v),
                              _orTar,
                              (v) => setState(() => _orTar = v),
                              Colors.amber.shade600,
                            ),
                            _construirTarjetaConfigDual(
                              'Nivel Titanio',
                              _tiEfe,
                              (v) => setState(() => _tiEfe = v),
                              _tiTar,
                              (v) => setState(() => _tiTar = v),
                              Colors.black87,
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        Center(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 40,
                                vertical: 20,
                              ),
                            ),
                            icon: _guardando
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : const Icon(Icons.save),
                            label: const Text('GUARDAR AJUSTES DE CASHBACK'),
                            onPressed: _guardando
                                ? null
                                : _guardarConfiguracion,
                          ),
                        ),
                      ],
                    ),
                  ),

            // PESTAÑA 2: BASE DE DATOS Y FABRICA DE STOCK
            _cargandoTodo
                ? const Center(child: CircularProgressIndicator())
                : Container(
                    padding: const EdgeInsets.all(24),
                    child: ListView(
                      children: [
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Colors.black12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.factory_outlined, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'FÁBRICA DE TARJETAS (PVC PARA IMPRENTA)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 15),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(
                                          Icons.print,
                                          color: Colors.grey,
                                        ),
                                        label: const Text(
                                          'GENERAR LOTE PLATA (1-)',
                                          style: TextStyle(color: Colors.black),
                                        ),
                                        onPressed: () =>
                                            _mostrarDialogoLotes('plata'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(
                                          Icons.print,
                                          color: Colors.amber,
                                        ),
                                        label: const Text(
                                          'GENERAR LOTE ORO (2-)',
                                          style: TextStyle(color: Colors.black),
                                        ),
                                        onPressed: () =>
                                            _mostrarDialogoLotes('oro'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 30),
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.card_giftcard,
                                      size: 20,
                                      color: Colors.deepPurple,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'SORTEOS Y REGALOS VIP',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                        color: Colors.deepPurple,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 15),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.casino),
                                      label: const Text('SORTEO PLATA'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueGrey,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => _hacerSorteo('plata'),
                                    ),
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.casino),
                                      label: const Text('SORTEO ORO'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.amber.shade700,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => _hacerSorteo('oro'),
                                    ),
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.casino),
                                      label: const Text('SORTEO TITANIO'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.black,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => _hacerSorteo('titanio'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 🚨 NUEVO: Buscador de Clientes
                        TextField(
                          controller: _buscadorCtrl,
                          onChanged: _filtrarClientes,
                          decoration: InputDecoration(
                            labelText:
                                'Buscar cliente VIP por nombre o nivel...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _buscadorCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _buscadorCtrl.clear();
                                      _filtrarClientes('');
                                      FocusScope.of(context).unfocus();
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 20),

                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Card(
                            elevation: 2,
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(
                                Colors.grey.shade200,
                              ),
                              columns: const [
                                DataColumn(label: Text('Nombre')),
                                DataColumn(label: Text('Nivel')),
                                DataColumn(label: Text('Saldo')),
                                DataColumn(label: Text('Compras')),
                                DataColumn(label: Text('Acciones')),
                              ],
                              rows:
                                  _clientesFiltrados // 🚨 Ahora usa la lista filtrada
                                      .map(
                                        (c) => DataRow(
                                          cells: [
                                            DataCell(
                                              SizedBox(
                                                width: 150,
                                                child: Text(
                                                  c['nombre'],
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Chip(
                                                label: Text(
                                                  c['nivel_vip']
                                                      .toString()
                                                      .toUpperCase(),
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                  ),
                                                ),
                                                backgroundColor:
                                                    c['nivel_vip'] == 'titanio'
                                                    ? Colors.black
                                                    : Colors.grey.shade300,
                                                labelStyle: TextStyle(
                                                  color:
                                                      c['nivel_vip'] ==
                                                          'titanio'
                                                      ? Colors.white
                                                      : Colors.black,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                '\$${c['saldo_cashback']}',
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                c['compras_totales'].toString(),
                                              ),
                                            ),
                                            DataCell(
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (c['nivel_vip'] ==
                                                      'titanio')
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.print,
                                                        color: Colors.black,
                                                      ),
                                                      tooltip:
                                                          'Imprimir Titanio Black (PVC)',
                                                      onPressed: () =>
                                                          _prepararImpresionTitanio(
                                                            c,
                                                          ),
                                                    ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.delete,
                                                      color: Colors.red,
                                                    ),
                                                    tooltip: 'Eliminar',
                                                    onPressed: () =>
                                                        _eliminarCliente(
                                                          c['id'],
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                      .toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
