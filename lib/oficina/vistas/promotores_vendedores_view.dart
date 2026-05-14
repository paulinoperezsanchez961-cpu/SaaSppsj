import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';

class PromotoresVendedoresView extends StatefulWidget {
  // Puente de comunicación para avisarle a la caja que salió dinero
  final Function(double)? onGastoRegistrado;

  const PromotoresVendedoresView({super.key, this.onGastoRegistrado});

  @override
  State<PromotoresVendedoresView> createState() =>
      _PromotoresVendedoresViewState();
}

class _PromotoresVendedoresViewState extends State<PromotoresVendedoresView> {
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _codigoController = TextEditingController();
  final TextEditingController _comisionController = TextEditingController();
  final TextEditingController _descuentoController = TextEditingController();

  List<dynamic> _vendedoresDB = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarVendedores();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _codigoController.dispose();
    _comisionController.dispose();
    _descuentoController.dispose();
    super.dispose();
  }

  Future<void> _cargarVendedores() async {
    if (!mounted) {
      return;
    }
    setState(() => _cargando = true);

    final datos = await ApiService.obtenerVendedores();

    if (mounted) {
      setState(() {
        _vendedoresDB = datos;
        _cargando = false;
      });
    }
  }

  Future<void> _registrarVendedor() async {
    if (_nombreController.text.isEmpty || _codigoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nombre y Código son obligatorios'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final nombre = _nombreController.text.trim();
    final codigo = _codigoController.text.trim().toUpperCase();
    final comision = double.tryParse(_comisionController.text) ?? 0.0;
    final descuento = double.tryParse(_descuentoController.text) ?? 0.0;

    setState(() => _cargando = true);
    bool exito = await ApiService.registrarVendedor(
      nombre,
      codigo,
      comision,
      descuento,
    );

    if (!mounted) {
      return;
    }

    if (exito) {
      _nombreController.clear();
      _codigoController.clear();
      _comisionController.clear();
      _descuentoController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Vendedor registrado exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
      _cargarVendedores();
    } else {
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Error al registrar'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _eliminarVendedor(int id) async {
    bool? confirmar = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar vendedor?'),
        content: const Text(
          'Se perderá el acceso del código, pero el historial de ventas se mantiene.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SÍ, ELIMINAR'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      if (!mounted) {
        return;
      }
      setState(() => _cargando = true);
      bool exito = await ApiService.eliminarVendedor(id);
      if (exito) {
        _cargarVendedores();
      } else {
        if (mounted) {
          setState(() => _cargando = false);
        }
      }
    }
  }

  Future<void> _liquidarDeuda(
    Map<String, dynamic> vendedor,
    int piezas,
    double ventasTotales,
    double pagoComision,
  ) async {
    bool? confirmar = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.payments, color: Colors.green),
            SizedBox(width: 10),
            Text('Pagar Comisiones'),
          ],
        ),
        content: Text(
          '¿Confirmas el pago en EFECTIVO de \$${pagoComision.toStringAsFixed(2)} a ${vendedor['nombre']}?\n\nEl dinero se restará de la caja automáticamente como Gasto de Operación y se imprimirá el recibo doble.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CONFIRMAR Y PAGAR'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      if (!mounted) {
        return;
      }

      setState(() => _cargando = true);
      final sm = ScaffoldMessenger.of(context);

      bool exito = await ApiService.liquidarComisiones(
        vendedor['codigo_creador'],
        piezas,
        ventasTotales,
      );

      if (!mounted) {
        return;
      }

      if (exito) {
        // 1. REGISTRAR FÍSICAMENTE COMO GASTO EN LA MEMORIA DE LA TABLET POS
        try {
          final prefs = await SharedPreferences.getInstance();
          final String? gastosStr = prefs.getString('caja_lista_gastos');
          List<dynamic> listaGastos = gastosStr != null
              ? jsonDecode(gastosStr)
              : [];

          final now = DateTime.now();
          listaGastos.add({
            "concepto":
                "Comisiones de ${vendedor['nombre']} (${vendedor['codigo_creador']})",
            "monto": pagoComision,
            "hora":
                "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}",
          });

          await prefs.setString('caja_lista_gastos', jsonEncode(listaGastos));
        } catch (e) {
          debugPrint("Aviso memoria gastos: $e");
        }

        // 2. AVISARLE AL POS QUE RESTE EL DINERO DEL TOTAL
        if (widget.onGastoRegistrado != null) {
          widget.onGastoRegistrado!(pagoComision);
        }

        sm.showSnackBar(
          const SnackBar(
            content: Text(
              '✅ Pago registrado como Gasto. Imprimiendo recibo...',
            ),
            backgroundColor: Colors.green,
          ),
        );

        await _cargarVendedores();
        await _imprimirDobleTicket(
          vendedor['nombre'],
          vendedor['codigo_creador'],
          piezas,
          pagoComision,
        );
      } else {
        setState(() => _cargando = false);
        sm.showSnackBar(
          const SnackBar(
            content: Text('❌ Error al registrar el pago.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 🚨 REIMPRESIÓN MARCA BLANCA SAAS
  Future<void> _imprimirDobleTicket(
    String nombre,
    String codigo,
    int piezas,
    double pago,
  ) async {
    final doc = pw.Document();
    pw.MemoryImage? imageLogo;

    // 🚨 DESCARGAMOS EL LOGO DEL NEGOCIO LOCAL DESDE MEMORIA
    final prefs = await SharedPreferences.getInstance();
    final String logoUrl = prefs.getString('caja_logo_empresa') ?? '';

    if (logoUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(logoUrl));
        if (response.statusCode == 200) {
          imageLogo = pw.MemoryImage(response.bodyBytes);
        }
      } catch (e) {
        debugPrint("Error descargando logo promotores: $e");
      }
    }

    final now = DateTime.now();
    final fecha =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    pw.Widget construirBloqueRecibo(String tipoCopia) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (imageLogo != null) pw.Image(imageLogo, width: 35, height: 35),
          pw.SizedBox(height: 5),
          pw.Text(
            'RECIBO DE PAGO',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'LIQUIDACIÓN DE COMISIONES',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            tipoCopia,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 5),
          pw.Text('Fecha: $fecha', style: const pw.TextStyle(fontSize: 8)),
          pw.Divider(borderStyle: pw.BorderStyle.dashed),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Promotor:', style: const pw.TextStyle(fontSize: 8)),
              pw.Text(
                nombre.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Código:', style: const pw.TextStyle(fontSize: 8)),
              pw.Text(codigo, style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Piezas Pagadas:',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text('$piezas pzs', style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
          pw.Divider(borderStyle: pw.BorderStyle.dashed),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL PAGADO',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                '\$${pago.toStringAsFixed(2)}',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 15),
          pw.Text('Firma Recibido:', style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 15),
          pw.Text(
            '__________________________________',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.SizedBox(height: 5),
        ],
      );
    }

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
              construirBloqueRecibo("COPIA VENDEDOR"),
              pw.SizedBox(height: 10),
              pw.Text(
                '- - - - - - CORTE AQUÍ - - - - - -',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 15),
              construirBloqueRecibo("COPIA NEGOCIO (GASTO DE CAJA)"),
              pw.SizedBox(height: 10),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Recibo_Comisiones_$codigo',
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 800;

    Widget panelAlta = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
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
            children: const [
              Icon(Icons.person_add_alt_1, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'REGISTRO DE PROMOTORES',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nombreController,
            decoration: const InputDecoration(
              labelText: 'Nombre del Vendedor',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.badge_outlined),
              filled: true,
              fillColor: Color(0xFFFBFBFB),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codigoController,
            decoration: const InputDecoration(
              labelText: 'Código de Creador (Ej. PACO_01)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.qr_code_2),
              filled: true,
              fillColor: Color(0xFFFBFBFB),
            ),
          ),
          const SizedBox(height: 16),
          // 🚨 PARCHE: Apilar inputs de dinero en celular para evitar aplastamientos
          isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _comisionController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '\$ Comisión/Pz',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                        filled: true,
                        fillColor: Color(0xFFF0FDF4),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _descuentoController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '\$ Descuento/Pz',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.local_offer_outlined),
                        filled: true,
                        fillColor: Color(0xFFFEF2F2),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _comisionController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '\$ Comisión/Pz',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.attach_money),
                          filled: true,
                          fillColor: Color(0xFFF0FDF4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _descuentoController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '\$ Descuento/Pz',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.local_offer_outlined),
                          filled: true,
                          fillColor: Color(0xFFFEF2F2),
                        ),
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
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text(
                'GUARDAR VENDEDOR EN NUBE',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              onPressed: _cargando ? null : _registrarVendedor,
            ),
          ),
        ],
      ),
    );

    Widget panelLista = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'LISTADO MAESTRO DE COMISIONES',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.blue),
                  onPressed: _cargarVendedores,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _cargando
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  )
                : _vendedoresDB.isEmpty
                ? const Center(
                    child: Text(
                      "No hay vendedores registrados.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: _vendedoresDB.length,
                    separatorBuilder: (c, i) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final v = _vendedoresDB[index];
                      final int piezasVendidas =
                          int.tryParse(
                            v['piezas_vendidas']?.toString() ?? '0',
                          ) ??
                          0;
                      final double ventasTotales =
                          double.tryParse(
                            v['ventas_totales']?.toString() ?? '0',
                          ) ??
                          0.0;
                      final double comisionUnit =
                          double.tryParse(v['comision']?.toString() ?? '0') ??
                          0.0;
                      final double descUnit =
                          double.tryParse(
                            v['descuento_cliente']?.toString() ?? '0',
                          ) ??
                          0.0;
                      final double deudaTotal = piezasVendidas * comisionUnit;

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.05),
                          ),
                        ),
                        // 🚨 PARCHE: Apilar botones en móviles para que las métricas financieras no se rompan
                        child: isMobile
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: const BoxDecoration(
                                          color: Colors.black87,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.person,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              v['nombre'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Wrap(
                                              spacing: 8,
                                              children: [
                                                Text(
                                                  'CÓDIGO: ${v['codigo_creador']}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blue,
                                                  ),
                                                ),
                                                Text(
                                                  '•',
                                                  style: TextStyle(
                                                    color: Colors.grey.shade400,
                                                  ),
                                                ),
                                                Text(
                                                  'Pago/Pz: \$${comisionUnit.toStringAsFixed(0)}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                                Text(
                                                  '•',
                                                  style: TextStyle(
                                                    color: Colors.grey.shade400,
                                                  ),
                                                ),
                                                Text(
                                                  'Desc/Pz: \$${descUnit.toStringAsFixed(0)}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.shopping_bag_outlined,
                                        size: 12,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$piezasVendidas piezas vendidas',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      if (deudaTotal > 0)
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                Colors.green.shade700,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.payments,
                                            size: 16,
                                          ),
                                          label: Text(
                                            'PAGAR \$${deudaTotal.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          onPressed: () => _liquidarDeuda(
                                            v,
                                            piezasVendidas,
                                            ventasTotales,
                                            deudaTotal,
                                          ),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade50,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: Colors.black12,
                                            ),
                                          ),
                                          child: const Text(
                                            'AL CORRIENTE',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.redAccent,
                                          size: 20,
                                        ),
                                        onPressed: () =>
                                            _eliminarVendedor(v['id']),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: const BoxDecoration(
                                      color: Colors.black87,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.person,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          v['nombre'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 8,
                                          children: [
                                            Text(
                                              'CÓDIGO: ${v['codigo_creador']}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue,
                                              ),
                                            ),
                                            Text(
                                              '•',
                                              style: TextStyle(
                                                color: Colors.grey.shade400,
                                              ),
                                            ),
                                            Text(
                                              'Pago/Pz: \$${comisionUnit.toStringAsFixed(0)}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            Text(
                                              '•',
                                              style: TextStyle(
                                                color: Colors.grey.shade400,
                                              ),
                                            ),
                                            Text(
                                              'Desc/Pz: \$${descUnit.toStringAsFixed(0)}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.shopping_bag_outlined,
                                              size: 12,
                                              color: Colors.grey,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$piezasVendidas piezas vendidas',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (deudaTotal > 0) ...[
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade700,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.payments,
                                        size: 16,
                                      ),
                                      label: Text(
                                        'PAGAR \$${deudaTotal.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      onPressed: () => _liquidarDeuda(
                                        v,
                                        piezasVendidas,
                                        ventasTotales,
                                        deudaTotal,
                                      ),
                                    ),
                                  ] else ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.black12,
                                        ),
                                      ),
                                      child: const Text(
                                        'AL CORRIENTE',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 10),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                    onPressed: () => _eliminarVendedor(v['id']),
                                  ),
                                ],
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CENTRO DE COMISIONES',
              style: TextStyle(
                fontSize: isMobile ? 20 : 26,
                fontWeight: FontWeight.w300,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Auditoría de ventas por código de creador y liquidación de deudas a promotores.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 32),

            Expanded(
              child: isMobile
                  ? SingleChildScrollView(
                      child: Column(
                        children: [
                          panelAlta,
                          const SizedBox(height: 20),
                          SizedBox(height: 600, child: panelLista),
                        ],
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: SingleChildScrollView(child: panelAlta),
                        ),
                        const SizedBox(width: 32),
                        Expanded(flex: 3, child: panelLista),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
