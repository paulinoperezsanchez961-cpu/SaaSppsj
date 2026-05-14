import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart'
    as http; // 🚨 IMPORTANTE PARA DESCARGAR EL LOGO DINÁMICO
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
  bool _cargandoTodo = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
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
        _cargandoTodo = false;
      });
    }
  }

  Future<void> _guardarConfiguracion() async {
    setState(() => _guardando = true);
    final exito = await ApiService.guardarConfiguracionVIP(
      _bonoBienvenida,
      _plEfe,
      _plTar,
      _orEfe,
      _orTar,
      _tiEfe,
      _tiTar,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
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
            child: const Text('Cancelar'),
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
      if (exito) _cargarDatos();
    }
  }

  // ===========================================================================
  // 🏭 FASE 1: GENERADOR DE LOTES DE STOCK (TARJETAS GENÉRICAS SAAS)
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
          children: [
            const Text(
              'Ingresa la cantidad de tarjetas vírgenes para stock.',
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
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctxDialog),
            child: const Text('Cancelar'),
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
    setState(() => _guardando = true);
    final pdf = pw.Document();

    PdfColor bgColor = const PdfColor.fromInt(0xFFE8E8E8); // Plata
    PdfColor accentColor = const PdfColor.fromInt(0xFF010101);
    PdfColor borderOpacity = const PdfColor(0.01, 0.01, 0.01, 0.3);
    String prefijo = '1';

    if (nivel == 'oro') {
      bgColor = const PdfColor.fromInt(0xFFD4AF37);
      prefijo = '2';
    }

    // 🚨 DESCARGA DINÁMICA DEL LOGO DE LA EMPRESA DESDE SHAREDPREFERENCES
    final prefs = await SharedPreferences.getInstance();
    final String logoUrl = prefs.getString('caja_logo_empresa') ?? '';

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

      // CARA A
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
                          "VIP",
                          style: pw.TextStyle(
                            fontSize: 30,
                            fontWeight: pw.FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                      pw.SizedBox(height: 18),
                      // 🚨 TEXTO GENÉRICO DE MARCA BLANCA
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

      // CARA B
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
                    // 🚨 TEXTO GENÉRICO DE MARCA BLANCA
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

    if (mounted) setState(() => _guardando = false);
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) => pdf.save());
  }

  // ===========================================================================
  // 👑 REIMPRESIÓN TITANIO (EDICIÓN ESPECIAL PERSONALIZADA SAAS)
  // ===========================================================================

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

    // 🚨 DESCARGA DINÁMICA DEL LOGO DE LA EMPRESA
    final prefs = await SharedPreferences.getInstance();
    final String logoUrl = prefs.getString('caja_logo_empresa') ?? '';

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

    // FRENTE
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
                        "VIP",
                        style: pw.TextStyle(fontSize: 30, color: accentColor),
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
                    // 🚨 TEXTO GENÉRICO
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

    // REVERSO
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
                  // 🚨 TEXTO GENÉRICO
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

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) => pdf.save());
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
                                      'FÁBRICA DE TARJETAS (STOCK FÍSICO)',
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
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Card(
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
                            rows: _clientes
                                .map(
                                  (c) => DataRow(
                                    cells: [
                                      DataCell(
                                        Text(
                                          c['nombre'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
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
                                            color: c['nivel_vip'] == 'titanio'
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
                                        Text(c['compras_totales'].toString()),
                                      ),
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (c['nivel_vip'] == 'titanio')
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.print,
                                                  color: Colors.black,
                                                ),
                                                tooltip:
                                                    'Imprimir Titanio Black',
                                                onPressed: () =>
                                                    _generarPdfTitanioPersonalizada(
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
                                                  _eliminarCliente(c['id']),
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
                      ],
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
